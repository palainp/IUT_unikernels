#!/usr/bin/env bash

set -e

opam pin | grep solo5 || opam opam pin solo5 git@github.com:palainp/solo5.git#vga -y
opam pin | grep tcpip || opam pin git@github.com:palainp/mirage-tcpip.git#add-default-route -y

for UNIKERNEL in dhcp website simple-fw nat dns-resolver ; do
    printf -- "---\n- Compilation of %s\n---\n" $UNIKERNEL
    cd $UNIKERNEL
    mirage configure -t virtio && make depend && dune build && cp dist/$UNIKERNEL.virtio ../image
    printf -- "---\n- Image creation for %s\n---\n" $UNIKERNEL
    cd ../image
    bash create_img.sh $UNIKERNEL
    cd ..
done

