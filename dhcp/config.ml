(* mirage >= 4.10.1 & < 4.11.0 *)
open Mirage

let packages =
  [
    package ~min:"2.1.0" "charrua";
    package "charrua-server";
    package ~min:"3.0.0" ~sublibs:[ "mirage" ] "arp";
    package ~min:"3.0.0" "ethernet";
  ]

let main = main "Unikernel.Main" ~packages (network  @-> job)

let () =
  register "dhcp"
    [ main  $ default_network ]
