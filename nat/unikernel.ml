open Lwt.Infix

module Main
    (* our unikernel is functorized over the physical, ethernet, ARP, and IPv4
       modules for the public and private interfaces, so each one shows up as
       a module argument. *)
    (Public_net: Mirage_net.S) (Private_net: Mirage_net.S)
    (Public_ethernet : Ethernet.S) (Private_ethernet : Ethernet.S)
    (Public_arpv4 : Arp.S) (Private_arpv4 : Arp.S)
    (Public_ipv4 : Tcpip.Ip.S with type ipaddr = Ipaddr.V4.t and type prefix = Ipaddr.V4.Prefix.t)
    (Private_ipv4 : Tcpip.Ip.S with type ipaddr = Ipaddr.V4.t and type prefix = Ipaddr.V4.Prefix.t)
  = struct

  (* Use a NAT table implementation which expires entries in response
     to memory pressure.  (See mirage-nat's documentation for more
     information on what this means.) *)
  module Nat = Mirage_nat_lru

  (* configure logs, so we can use them later *)
  let log = Logs.Src.create "nat" ~doc:"NAT device"
  module Log = (val Logs.src_log log : Logs.LOG)

  (* the specific impls we're using show up as arguments to start. *)
  let start public_netif private_netif
            public_ethernet private_ethernet
            public_arpv4 private_arpv4
            public_leasev4 private_leasev4 =

    (* Helpers functions *)
    let get_dst (`IPv4 (packet, _) : Nat_packet.t) = packet.Ipv4_packet.dst in

    let try_decompose cache ~now f packet =
      let cache', r = Nat_packet.of_ipv4_packet !cache ~now:(now ()) packet in
      cache := cache';
      match r with
      | Error e ->
        Logs.err (fun m -> m "of_ipv4_packet error %a" Nat_packet.pp_error e);
        Lwt.return_unit
      | Ok Some packet -> f packet
      | Ok None -> Lwt.return_unit
    in

    let payload_to_buf pkt =
      match pkt with
      | `IPv4 (ip_hdr, p) ->
        let src = ip_hdr.Ipv4_packet.src and dst = ip_hdr.dst in
        match p with
        | `ICMP (icmp_header, payload) -> begin
            let payload_start = Icmpv4_wire.sizeof_icmpv4 in
            let buf = Cstruct.create (payload_start + Cstruct.length payload) in
            Cstruct.blit payload 0 buf payload_start (Cstruct.length payload);
            match Icmpv4_packet.Marshal.into_cstruct icmp_header ~payload buf with
            | Error s ->
              Logs.warn (fun m -> m "Error writing ICMPv4 packet: %s" s);
              Error ()
            | Ok () -> Ok (buf, `ICMP, ip_hdr)
          end
        | `UDP (udp_header, udp_payload) -> begin
            let payload_start = Udp_wire.sizeof_udp in
            let buf = Cstruct.create (payload_start + Cstruct.length udp_payload) in
            Cstruct.blit udp_payload 0 buf payload_start (Cstruct.length udp_payload);
            let pseudoheader =
              Ipv4_packet.Marshal.pseudoheader ~src ~dst ~proto:`UDP
                (Cstruct.length udp_payload + Udp_wire.sizeof_udp)
            in
            match Udp_packet.Marshal.into_cstruct
                    ~pseudoheader ~payload:udp_payload udp_header buf
            with
            | Error s ->
              Logs.warn (fun m -> m "Error writing UDP packet: %s" s);
              Error ()
            | Ok () -> Ok (buf, `UDP, ip_hdr)
          end
        | `TCP (tcp_header, tcp_payload) -> begin
            let payload_start =
              let options_length = Tcp.Options.lenv tcp_header.Tcp.Tcp_packet.options in
              (Tcp.Tcp_wire.sizeof_tcp + options_length)
            in
            let buf = Cstruct.create (payload_start + Cstruct.length tcp_payload) in
            Cstruct.blit tcp_payload 0 buf payload_start (Cstruct.length tcp_payload);
            (* and now transport header *)
            let pseudoheader =
              Ipv4_packet.Marshal.pseudoheader ~src ~dst ~proto:`TCP
                (Cstruct.length tcp_payload + payload_start)
            in
            match Tcp.Tcp_packet.Marshal.into_cstruct
                    ~pseudoheader tcp_header
                    ~payload:tcp_payload buf
            with
            | Error s ->
              Logs.warn (fun m -> m "Error writing TCP packet: %s" s);
              Error ()
            | Ok _ -> Ok (buf, `TCP, ip_hdr)
          end
    in

    (* when we see packets on the private interface,
       we should check to see whether a translation exists for them already.
       If there is one, we would like to translate the packet and send it out
       the public interface.
       If there isn't, we should add one, then do as above.
    *)
    let rec ingest_private table packet =
      Log.debug (fun f -> f "Private interface got a packet: %a" Nat_packet.pp packet);
      match Nat.translate table packet with
      | Ok packet ->
        begin match payload_to_buf packet with
        | Ok (buf, proto, ip_hdr) ->
          (Public_ipv4.write public_leasev4 ip_hdr.dst proto (fun _ -> 0) [buf]
           >|= function
           | Ok () -> ()
           | Error _e ->
             (* could send back host unreachable if this was an arp timeout *)
             (* Logs.err (fun m -> m "error %a while forwarding %a"
                Public_ipv4.pp_error e Ipv4_packet.pp hdr)) *)
             ())
        | Error () -> Lwt.return_unit
        end
      | Error `TTL_exceeded ->
        (* TODO: if we were really keen, we'd send them an ICMP message back. *)
        (* But for now, let's just drop the packet. *)
        Log.debug (fun f -> f "TTL exceeded for a packet on the private interface");
        Lwt.return_unit
      | Error `Untranslated ->
        (* In order to add a source NAT rule, we have to come up with an unused
           source port to use for disambiguating return traffic. *)
        let public_ip = Public_ipv4.src public_leasev4 ~dst:(get_dst packet) in
        (* TODO: this may generate low-numbered source ports, which may be treated
           with suspicion by other nodes on the network *)
        let port_gen () = Some (Randomconv.int16 Mirage_crypto_rng.generate) in
        match Nat.add table packet public_ip port_gen `NAT with
        | Error e ->
          Log.debug (fun f -> f "Failed to add a NAT rule: %a" Mirage_nat.pp_error e);
          Lwt.return_unit
        | Ok () -> ingest_private table packet
    in

    (* when we see packets on the public interface,
       we only want to translate them and send them out over the private
       interface if a rule already exists.
       we shouldn't make new rules from public traffic. *)
    let ingest_public table packet =
      match Nat.translate table packet with
      | Ok packet ->
        begin match payload_to_buf packet with
        | Ok (buf, proto, ip_hdr) ->
          (Private_ipv4.write private_leasev4 ~src:ip_hdr.src ip_hdr.dst proto (fun _ -> 0) [buf]
           >|= function
           | Ok () -> ()
           | Error _e ->
             (* could send back host unreachable if this was an arp timeout *)
             (* Logs.err (fun m -> m "error %a while forwarding %a"
                Private_ipv4.pp_error e Ipv4_packet.pp hdr)) *)
             ())
        | Error () -> Lwt.return_unit
        end
      | Error `TTL_exceeded ->
        Log.debug (fun f -> f "TTL exceeded for a packet on the public interface");
        Lwt.return_unit
      | Error `Untranslated ->
        Log.debug (fun f -> f
                      "Packet received on public interface for which no match exists.  BLOCKED!");
        Lwt.return_unit
    in

    (* get an empty NAT table *)
    let table = Nat.empty ~tcp_size:1024 ~udp_size:1024 ~icmp_size:20 in

    (* we need to establish listeners for the private and public interfaces *)
    (* we're interested in all traffic to the physical interface; we'd like to
       send ARP traffic to the normal ARP listener and responder,
       handle ipv4 traffic with the functions we've defined above for NATting,
       and ignore all ipv6 traffic (ipv6 has no need for NAT!). *)
    let listen_public =
      let cache = ref (Fragments.Cache.empty (256 * 1024)) in
      let header_size = Ethernet.Packet.sizeof_ethernet
      and input =
        Public_ethernet.input
          ~arpv4:(Public_arpv4.input public_arpv4)
          ~ipv4:(try_decompose cache ~now:Mirage_mtime.elapsed_ns (ingest_public table))
          ~ipv6:(fun _ -> Lwt.return_unit)
          public_ethernet
      in
      Public_net.listen ~header_size public_netif input >>= function
      | Error e -> Log.debug (fun f -> f "public interface stopped: %a"
                                 Public_net.pp_error e); Lwt.return_unit
      | Ok () -> Log.debug (fun f -> f "public interface terminated normally");
        Lwt.return_unit
    in

    let listen_private =
      let cache = ref (Fragments.Cache.empty (256 * 1024)) in
      let header_size = Ethernet.Packet.sizeof_ethernet
      and input =
        Private_ethernet.input
          ~arpv4:(Private_arpv4.input private_arpv4)
          ~ipv4:(try_decompose cache ~now:Mirage_mtime.elapsed_ns (ingest_private table))
          ~ipv6:(fun _ -> Lwt.return_unit)
          private_ethernet
      in
      Private_net.listen ~header_size private_netif input >>= function
      | Error e -> Log.debug (fun f -> f "private interface stopped: %a"
                                 Private_net.pp_error e); Lwt.return_unit
      | Ok () -> Log.debug (fun f -> f "private interface terminated normally");
        Lwt.return_unit
    in

    (* Notice how we haven't said anything about ICMP anywhere.  The unikernel
       doesn't know anything about it, so pinging this host on either interface
       will just be ignored -- the only way this unikernel can be easily seen,
       without sending traffic through it, is via ARP.  The `arping` command
       line utility might be useful in trying to see whether your unikernel is
       up.  *)

    (* start both listeners, and continue as long as both are working. *)
    Lwt.pick [
      listen_public;
      listen_private;
    ]
end
