open Dhcp_wire

let ip = Ipaddr.V4.of_string_exn
let net = Ipaddr.V4.Prefix.of_string_exn
let mac = Macaddr.of_string_exn
let hostname = "charrua-dhcp-server"
let default_lease_time = 60 * 60 * 1 (* 1 hour *)
let max_lease_time = 60 * 60 * 24 (* A day *)
let ip_address = ip "10.10.42.5"
let network = net "10.10.42.0/24"
let range = Some (ip "10.10.42.100", ip "10.10.42.200")

(* List of dhcp options to be advertised *)
let options =
  [
    (* Routers is a list of default routers *)
    Routers [ ip "10.10.42.254" ];
    (* Dns_servers is a list of dns servers *)
    Dns_servers [ ip "10.10.42.53" (* ip "192.168.1.6" *) ];
    (* Ntp_servers is a list of ntp servers, Time_servers (old protocol) is also available *)
    (* Ntp_servers [ip "192.168.1.5"]; *)
    Domain_name "pampas";
    (*
     * Check dhcp_wire.mli for the other options:
     * https://github.com/haesbaert/charrua-core/blob/master/lib/dhcp_wire.mli
     *)
  ]

(*
 * Static hosts configuration, list options will be merged with global ones
 * while non-list options will override the global, example: options `Routers',
 * `Dns_servers', `Ntp_servers' will always be merged; `Domain_name',
 * `Time_offset', `Max_datagram; will always override the global (if present).
 *)

let router_special_mac = {
   Dhcp_server.Config.hostname = "router";
   options = [
     (* Routers [ip "10.10.42.254"]; *)
   ];
   hw_addr = mac "ca:fe:ba:5e:ba:11";
   fixed_addr = Some (ip "10.10.42.254"); (* Must be outside of range. *)
}

let dns_special_mac = {
   Dhcp_server.Config.hostname = "dns";
   options = [
     Routers [ip "10.10.42.254"];
   ];
   hw_addr = mac "ca:fe:f0:07:ba:11";
   fixed_addr = Some (ip "10.10.42.53"); (* Must be outside of range. *)
}

let hosts = [router_special_mac ; dns_special_mac]
