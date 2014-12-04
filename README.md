DebianRootFS4ARM
================

This script can create a ARM Debian Root FileSystem image file automatically.


## Prepare

Before you start, Some packets must be installed in you environment.

    # apt-get install binfmt-support qemu qemu-user-static debootstrap kpartx lvm2 dosfstools

## How to use

    # ./build_debian_arm_rootfs_img.sh img  your_image_file

After run this script, you also need to merge uboot and linux kernel into this image for a bootable image in ARM system.

***

## Note

Here are some things you need to know when you first booting by this image.

- The password for root is "123456"

- Please modify the /etc/network/interface for network settings

- Run 'dpkg-reconfigure locales' to set your language.

- Run 'dpkg-reconfigure tzdata' to set your timezone.

 
