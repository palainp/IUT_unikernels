#!/usr/bin/env bash

set -e

opam pin | grep solo5 || opam opam pin solo5 git@github.com:palainp/solo5.git#vga -y
opam pin | grep tcpip || opam pin git@github.com:palainp/mirage-tcpip.git#add-default-route -y

# unikernels that relies on DHCP for interface configuration
for UNIKERNEL in website nat dns-resolver ; do
    printf -- "---\n- Compilation of %s\n---\n" $UNIKERNEL
    cd $UNIKERNEL
    mirage configure -t virtio --dhcp=true && make depend && dune build && cp dist/$UNIKERNEL.virtio ../image
    printf -- "---\n- Image creation for %s\n---\n" $UNIKERNEL
    cd ../image
    bash create_img.sh $UNIKERNEL
    cd ..
done

# special net unikernel (not using DHCP for interface configuration)
for UNIKERNEL in dhcp simple-fw ; do
    printf -- "---\n- Compilation of %s\n---\n" $UNIKERNEL
    cd $UNIKERNEL
    mirage configure -t virtio && make depend && dune build && cp dist/$UNIKERNEL.virtio ../image
    printf -- "---\n- Image creation for %s\n---\n" $UNIKERNEL
    cd ../image
    bash create_img.sh $UNIKERNEL
    cd ..
done

