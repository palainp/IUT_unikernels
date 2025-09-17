(* mirage >= 4.10.1 & < 4.11.0 *)
open Mirage

(* we need two network interfaces: a public side and a private side *)
(* a bit of magic: currently, multiple networks only work on Unix and Xen
   backends, so we can get away with this indexes-as-numbers-as-strings
   silliness.
   See https://github.com/mirage/mirage/issues/645 *)
let public_netif =
  Key.(if_impl is_solo5
         (netif ~group:"public" "public")
         (netif ~group:"public" "0"))
let private_netif =
  Key.(if_impl is_solo5
         (netif ~group:"private" "private")
         (netif ~group:"private" "1"))

(* build ethernet interfaces on top of those network interfaces *)
let public_ethernet = ethif public_netif
let private_ethernet = ethif private_netif

(* use the functional address resolution protocol *)
let public_arpv4 = arp public_ethernet
let private_arpv4 = arp private_ethernet

let public_ipv4 = ipv4_of_dhcp public_netif public_ethernet public_arpv4
let private_ipv4 = ipv4_of_dhcp private_netif private_ethernet private_arpv4

let packages = [
  package ~min:"3.0.1" "mirage-nat";
  package "ethernet";
  package ~min:"7.0.0" "tcpip";
  package ~min:"4.0.0" "mirage-runtime";
]

(* our unikernel needs to know about physical network, ethernet, arp, and ipv4
   modules for each interface. Even though these modules will be the same for
   both interfaces in our case, we have to pass them separately. *)
let main = main "Unikernel.Main" ~packages
           (network  @-> network  @->
            ethernet @-> ethernet @->
            arpv4    @-> arpv4    @->
            ipv4     @-> ipv4     @-> job)

(* we need to pass each of the network-related impls we've made to the
   unikernel, so that it can start the appropriate listeners. *)
let () = register "nat" [ main
                          $ public_netif    $ private_netif
                          $ public_ethernet $ private_ethernet
                          $ public_arpv4    $ private_arpv4
                          $ public_ipv4     $ private_ipv4
                        ]
