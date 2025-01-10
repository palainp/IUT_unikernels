#!/bin/bash

if [ $# -lt 1 ] ; then
    echo "Usage: SCRIPT unikernel"
    exit 10
fi

UNIKERNEL_NAME=$1

shift 
OPTIONS="$*"

UNIKERNEL=$UNIKERNEL_NAME.virtio
IMAGE=$UNIKERNEL_NAME.qcow2

set -e 

##### create initial image
rm -f $IMAGE
qemu-img create -f qcow2 $IMAGE 30M

##### paritition and mount
DEVICE=/dev/nbd0
MOUNT=/mnt
sudo modprobe nbd max_parts=10
sudo qemu-nbd --connect $DEVICE $IMAGE

#no partition
#printf "n\np\n1\n\n\na\np\nw\n" | sudo fdisk $DEVICE
#BOOTDEV=${DEVICE}p1
BOOTDEV=${DEVICE}

sudo /sbin/mkfs.fat $BOOTDEV
sudo mount -o uid=user $BOOTDEV $MOUNT
mkdir -p $MOUNT/boot

# and create /boot -> . symlink so it doesn't matter if grub looks for
# /boot/grub or /grub
#ln -s . "$INSTALLDIR/boot/boot"

cp $UNIKERNEL $MOUNT/boot/kernel

mkdir -p $MOUNT/boot/grub2
cat > $MOUNT/boot/grub2/grub.cfg <<EOF
set timeout=0
terminal_output console
menuentry mirage {
    set root="(hd0)"
    multiboot /boot/kernel $OPTIONS
}
EOF

cat $MOUNT/boot/grub2/grub.cfg

sudo grub2-install --no-floppy --boot-directory=$MOUNT/boot $DEVICE --force

##### save properly
sudo umount $MOUNT
sudo qemu-nbd --disconnect $DEVICE
