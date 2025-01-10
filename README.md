# Introduction

This repository groups several unikernels I use on our Univeristy's KVM cyberrange.

## Compilation and image creation

I create qcow2 images with `image/create_img.sh` likewise (`UNIKERNEL` stands for both the directory name and the producted unikernel name, which should be the case in this repository):
```bash
export UNIKERNEL=<unikernel>
cd $UNIKERNEL
mirage configure -t virtio && make depend && dune build && cp dist/$UNIKERNEL.virtio ../image
cd ../image
bash create_img.sh $UNIKERNEL
```

This creates a 30MB disk image that can be directly uploaded on the cyberrange, I usually set the unikernels with 32MB of RAM, and all network interfaces should be configured as virtio interfaces. The icon used for those unikernels is provided in this repository.

## Note on serial outputs

Sadly our cyberrange does not support printing via serial port, so before compiling I need to pin a specific branchn that prints over a VGA console instead of serial, of the virtio tender:
```bash
opam pin solo5 git@github.com:palainp/solo5.git#vga -y
```

# DHCP

That unikernel serves IP addresses for a configured network. Modify `dhcp/dhcp_config.ml` to change the network.
For the time being, the hardcoded addresses of the router and the DNS server are distributed for the virtual machines with MAC addresses `ca:fe:ba:5e:ba:11` and `ca:fe:f0:07:ba:11` respectively.

It comes from https://github.com/mirage/mirage-skeleton.
The licence is "The Unlicense".

# Firewall

That unikernel forward packets from one interface to the other. It also filter packets based on a ruleset. Modify `simple-fw/rules.ml` to match your needs.

DO NOT USE THIS UNIKERNEL IN PRODUCTION : there is a way, described in `simple-fw/rules.ml` as python oneliner, to update the rules at runtime without any authentification.

It comes from https://github.com/palainp/simple-fw.
The licence is "BSD-2-Clause".

