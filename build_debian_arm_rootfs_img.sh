#!/bin/bash
#
# build your own ARM-Debian Root-FS image.
#
# you need at least
# apt-get install binfmt-support qemu qemu-user-static debootstrap kpartx lvm2 dosfstools
# And ARM GNU toolchain arm-linux-gnueabihf-xxx
THIS_SCRIPT=`echo $0 | sed "s/^.*\///"`
SCRIPT_PATH=`echo $0 | sed "s/\/${THIS_SCRIPT}$//"`
real_pwd=`pwd`
real_pwd=`realpath ${real_pwd}`
work_dir=${real_pwd}/_build_tmp

#
# Arguments process
#
function show_syntax () {
  echo 
  echo "This script will create a Debian Root FileSystem for ARM hard-float device."
  echo "The default image size will be 1048576 * 1900 bytes"
  echo "Before you run this script , please make-sure you already install below packages :"
  echo "binfmt-support qemu qemu-user-static debootstrap kpartx lvm2 dosfstools"
  echo "and ARM GNU toolchain arm-linux-gnueabihf-xxx"
  echo
  echo "The syntax:"
  echo "$1  img|dev  image_file_name_or_device_name"
  echo
}

function generate_imag_file () {
  echo "Generate temp image file : $1"
  dd if=/dev/zero of=$1 bs=1048576 count=1900
}

function exit_process () {
  if [ -d $work_dir ]; then
      rm -rf $work_dir
  fi
  exit $1
}

temp_image=${work_dir}/disk_img.tmp

if [ $EUID -ne 0 ]; then
  echo "this tool must be run as root"
  exit_process 1
fi

if [ $# -lt 2 ]; then
    show_syntax $0
    exit_process 1
fi

if [ -d $work_dir ]; then
    echo "Working directory $work_dir exist, please remove it before run this script"
    exit 1
fi

mkdir -p $work_dir

dev_type=$1
device=$2
case "$dev_type" in
  'img')
      target_image=$device
      if [ -f $target_image ]; then
          echo "The file $target_image exist, do you want to overwrite it (yes/no)?"
          read yno
          case $yno in
            [yY] | [yY][Ee][Ss] )
                rm -rf $target_image
                ;;
            [nN] | [n|N][O|o] )
                echo "Exit!";
                exit_process 1
                ;;
            *)
                echo "Invalid input"
                exit_process 1
                ;;
          esac
      fi
      generate_imag_file $temp_image
      device=`losetup -f --show $temp_image`
      echo "image $temp_image created and mounted as $device"
      ;;
  'dev')
      target_image=""
      if ! [ -b $device ]; then
          echo "$device is not a block device"
          exit_process 1
      fi
      # clean some sectors for partition & special location for cubieboard.
      dd if=/dev/zero of=$device bs=1048576 count=20
      ;;
  *)
      show_syntax $0
      exit_process 1
      ;;
esac

#
# Debian parameters
#
#deb_mirror="http://http.debian.net/debian"
deb_mirror="http://ftp.tw.debian.org/debian"
#deb_local_mirror="http://debian.kmp.or.at:3142/debian"

bootsize="100M"
deb_release="wheezy"

rootfs="${work_dir}/rootfs"
bootfs="${rootfs}/boot"

architecture="armhf"
#architecture="armel"

if [ "$deb_local_mirror" == "" ]; then
  deb_local_mirror=$deb_mirror
fi

#
# Create two partitions (bootp, rootp)
# 1st partition is 100MB, start sector offset from 40960
# 2nd partition occupy left size, start sector offset from 204760 (=100M/512 + 40960)
#
fdisk $device << EOF
n
p
1
40960
+$bootsize
t
c
n
p
2
245760

w
EOF

if [ "$dev_type" == "img" ]; then
  sleep 3
  losetup -d $device
  sleep 3

  device=`kpartx -va $temp_image | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`

  # Wait a while until the loop-device ready
  sleep 3

  bootp_dmsetup_name=${device}p1
  rootp_dmsetup_name=${device}p2
  device="/dev/mapper/${device}"
  bootp=${device}p1
  rootp=${device}p2
else
  if ! [ -b ${device}1 ]; then
    bootp=${device}p1
    rootp=${device}p2
    if ! [ -b ${bootp} ]; then
      echo "uh, oh, something went wrong, can't find bootpartition neither as ${device}1 nor as ${device}p1, exiting."
      exit_process 1
    fi
  else
    bootp=${device}1
    rootp=${device}2
  fi  
fi

mkfs.vfat $bootp
mkfs.ext4 $rootp

#
# 1st stage
#
mkdir -p $rootfs
mount $rootp $rootfs
debootstrap --foreign --arch $architecture $deb_release $rootfs $deb_local_mirror
cp /usr/bin/qemu-arm-static ${rootfs}/usr/bin/

#
# 2nd stage
#
LANG=C chroot $rootfs /debootstrap/debootstrap --second-stage

mount $bootp $bootfs

cat << EOF > ${rootfs}/etc/apt/sources.list
deb $deb_local_mirror $deb_release main contrib non-free
EOF

#cat << EOF > ${bootfs}/cmdline.txt
#dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait
#EOF

cat << EOF > ${rootfs}/etc/fstab
proc            /proc           proc    defaults        0       0
/dev/mmcblk0p1  /boot           vfat    defaults        0       0
EOF

echo "bsms" > ${rootfs}/etc/hostname

cat << EOF > ${rootfs}/etc/resolv.conf
nameserver 8.8.8.8
EOF

cat << EOF > ${rootfs}/etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
allow-hotplug eth0

## use IP autoconfiguration
iface eth0 inet dhcp

## confiure for static IP
#iface eth0 inet static
#address 10.0.0.10
#netmask 255.255.255.0
#network 10.0.0.0
#broadcast 10.0.0.255
#gateway 10.0.0.1

## set the mac address
#pre-up ifconfig eth0 hw ether "0011aabbccdd"

## setup wifi
#auto wlan0
#iface wlan0 inet dhcp
#pre-up ip link set wlan0 up
#pre-up iwconfig wlan0 essid your-ap-ssid
#wpa-ssid your-ap-ssid
#wpa-psk your-ap-passwd
#wpa-scan_ssid 1

EOF

echo T0:2345:respawn:/sbin/getty -L ttyS0 115200 vt100 >> ${rootfs}/etc/inittab

#
# 3rd stage
#
export MALLOC_CHECK_=0 # workaround for LP: #520465
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

mount -t proc proc ${rootfs}/proc
mount -o bind /dev/ ${rootfs}/dev/
mount -o bind /dev/pts ${rootfs}/dev/pts

cat << EOF > ${rootfs}/debconf.set
console-common console-data/keymap/policy select Select keymap from full list
console-common console-data/keymap/full select en-latin1-nodeadkeys
EOF

cat << EOF > ${rootfs}/third-stage
#!/bin/bash
apt-get update
apt-get install locales locales-all
locale-gen en_US.UTF-8

debconf-set-selections /debconf.set
rm -f /debconf.set
apt-get update
apt-get -y install git-core binutils ca-certificates initramfs-tools uboot-mkimage
apt-get -y install locales console-common ntp less openssh-server nano git vim 
apt-get -y install wireless-tools wpasupplicant
echo "root:123456" | chpasswd
sed -i -e 's/KERNEL\!=\"eth\*|/KERNEL\!=\"/' /lib/udev/rules.d/75-persistent-net-generator.rules
rm -f /etc/udev/rules.d/70-persistent-net.rules
rm -f /third-stage
EOF

chmod +x ${rootfs}/third-stage
LANG=C chroot ${rootfs} /third-stage

#
# Manual Configuration Within the chroot
#

#LANG=C chroot ${rootfs}
#{make additional changes within the chroot}
#exit


#
# Cleanup
# 
cat << EOF > ${rootfs}/cleanup
#!/bin/bash
rm -rf /root/.bash_history
aptitude update
#aptitude clean
#apt-get clean
rm -f cleanup
EOF

chmod +x ${rootfs}/cleanup
LANG=C chroot ${rootfs} /cleanup

sync

sleep 3

# The 'qemu-arm-static' will occurpy some device resource. It will cause the 'umount' don't work.
# Because the ${rootfs}/dev/ is occupied by qemu-arm-static.
# So, before umount all device, we must kill the 'qemu-arm-static' process.
ps -ef | grep qemu-arm-static | awk '{print $2}' | xargs kill -9

sleep 2
umount ${rootfs}/proc
sleep 2
umount ${rootfs}/dev/pts
sleep 2
umount ${rootfs}/dev/

sleep 2
umount $bootp
sleep 2
umount $rootp

if [ "$dev_type" == "img" ]; then
    
  #
  # Sometimes the "kpartx -d" can't remove the block device in /dev/mapper.
  # It seems caused by system still using the device mapper.
  # So we use dmsetup command force remove device mapper.
  #
  sleep 3
  dmsetup clear $bootp_dmsetup_name
  dmsetup remove $bootp_dmsetup_name
  sleep 3
  dmsetup clear $rootp_dmsetup_name
  dmsetup remove $rootp_dmsetup_name
  sleep 3
  kpartx -d $temp_image
  mv $temp_image $target_image
  echo "created image $target_image"
fi

echo "Finished !!"
exit_process 0

