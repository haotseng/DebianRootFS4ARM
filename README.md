DebianRootFS4ARM
================

This script can create a ARM Debian Root FileSystem image file automatically.

After run this script, you also need to merge uboot and linux kernen into this image for booting on ARM board.

***

Here are some things you need to know when you first booting by this image.

- The password for root is "123456"

- Please modify the /etc/network/interface for network settings

- Run 'dpkg-reconfigure locales' to set your language.

- Run 'dpkg-reconfigure tzdata' to set your timezone.

 
