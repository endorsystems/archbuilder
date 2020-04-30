#!/bin/bash
# Arch Installer (Server based installer)
# Built by sean@endorsystems.com
set -uo pipefail
#trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

### Get infomation from user ###
hostname=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
clear
: ${hostname:?"hostname cannot be empty"}

user=$(dialog --stdout --inputbox "Enter admin username" 0 0) || exit 1
clear
: ${user:?"user cannot be empty"}

password=$(dialog --stdout --passwordbox "Enter admin password" 0 0) || exit 1
clear
: ${password:?"password cannot be empty"}
password2=$(dialog --stdout --passwordbox "Enter admin password again" 0 0) || exit 1
clear
[[ "$password" == "$password2" ]] || ( echo "Passwords did not match"; exit 1; )

rootpassword=$(dialog --stdout --passwordbox "Enter root password" 0 0) || exit 1
clear
: ${rootpassword:?"password cannot be empty"}
rootpassword2=$(dialog --stdout --passwordbox "Enter root password again" 0 0) || exit 1
clear
[[ "$rootpassword" == "$rootpassword2" ]] || ( echo "Passwords did not match"; exit 1; )

# getting interface name
ifname=`ip a | grep "2:" | awk -F':' '{print $2}' | sed -e 's/^[[:space:]]*//'`

devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
device=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1
clear

# generate UUID for interface
ifuuid=`uuidgen ${ifname}`

### Set up logging ###
exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")

timedatectl set-ntp true

# Setup local mirror for faster install.
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
curl -s https://git.endorsystems.com/snippets/6/raw -o /etc/pacman.d/mirrorlist
pacman -Sy

### Setup the disk and partitions ###
parted --script "${device}" -- mklabel msdos \
  mkpart primary ext4 0% 512MiB \
  set 1 boot on \
  mkpart primary xfs 512MiB 100%

# Simple globbing was not enough as on one device I needed to match /dev/mmcblk0p1
# but not /dev/mmcblk0boot1 while being able to match /dev/sda1 on other devices.
part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
part_root="$(ls ${device}* | grep -E "^${device}p?2$")"

wipefs "${part_boot}"
wipefs "${part_root}"

mkfs.ext4 "${part_boot}"
mkfs.xfs "${part_root}"

mount "${part_root}" /mnt
mkdir /mnt/boot
mount "${part_boot}" /mnt/boot

# Install needed packages
pacstrap /mnt \
  base \
  base-devel \
  linux \
  linux-firmware \
  linux-headers \
  device-mapper \
  inetutils \
  diffutils \
  e2fsprogs \
  man-db \
  man-pages \
  perl \
  sysfsutils \
  vim \
  which \
  xfsprogs \
  usbutils \
  less \
  logrotate \
  python \
  python-pip \
  grub \
  os-prober \
  openssh \
  networkmanager \
  fish \
  git

# Generate 
genfstab /mnt >> /mnt/etc/fstab

# Set hostname
arch-chroot /mnt echo "${hostname}" > /mnt/etc/hostname

# locales
arch-chroot /mnt sed -i 's/#\(en_US\.UTF-8\)/\1/' /etc/locale.gen
arch-chroot /mnt locale-gen
arch-chroot /mnt echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
arch-chroot /mnt ln -sf /usr/share/zoneinfo/US/Eastern /etc/localtime

# User config (removed $user for server installer)
arch-chroot /mnt useradd -m -s /usr/bin/fish -G wheel "$user"
arch-chroot /mnt chsh -s /usr/bin/fish

# Setup sshd for use, root as needed.
arch-chroot /mnt mkdir /home/sean/.ssh
arch-chroot /mnt echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDpqbowDq3rOocJIhsTSNcIsbiouKWWsY2Z8wLqvgg+ZXnyC1axqg80mnnGVdZNem3wq+G4T/ob52qGpdJMqx/SmJx1rKPO9FGLIZk3l8TM6CqzVz8YfHnhwx6vZAJE5uv5ijMredSDt862nClb4eWADHb/GtXZW8rk7hVLt9wE/iomxWdUbzlthg6kFGquMfCmfkwJbZj9Cia9BIDGKA1yflze7Mn1le/1E4xsw/OrrJiKUOxT81RLzrJxJDgQbvr3Mxzt/rb81sE19f9vCDmgT5lW5ariSPwHHQGMoKSa3mftrTVBMzf3Pgh15j+QJarxu1oPFxPHD9hZWf7XxTPPFTTV5ZTwV+vvyljFNBk2mxSq401Htdzv9vpJPnoCg8ugtzNhkiYzkTSlJFikiPS7Tc3X4d+v5hFf2vhtXTN+1xmUoVMYJ3SKhWKsImluY9esaf4pA1oWAreuBTJO0SjeS4n1HJoRiml0tupb4t8S6ZUz9cxnYs6A8THnDbRpAPLY9WsSeDclmWgHUsHnvgDC5yMT+dC74WiFhPg9Pz0NKo5SR4n1PB+yzGQ/3bwdH6VO6WUQc9ZAMZVacwAapePKpoF+8wiOvdY7QvLKQV7h+DRPN6jGTfhuQUDXvdwaNv50LGNCOiNli9YBND8Hay2oukpXKdUwp8nxiU3ElYCq8w== blackmage" > /mnt/sean/.ssh/authorized_keys

# Systemd enables
arch-chroot /mnt systemctl enable sshd

# Bootloader install
arch-chroot /mnt grub-install ${device}
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

#echo "$user:$password" | chpasswd --root /mnt
echo "root:$rootpassword" | chpasswd --root /mnt

# umount partitions
umount ${part_boot}
umount ${part_root}

# reboot
#reboot