#!/bin/bash
# Arch Installer (Server based installer)
set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

### Set up logging ###
exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")

timedatectl set-ntp true

### User input section ###
hostname=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
clear
: ${hostname:?"hostname cannot be empty"}

sudo_user=$(dialog --stdout --inputbox "Enter main account username" 0 0) || exit 1
clear
: ${sudo_user:?"user cannot be empty"}

sudo_user_password=$(dialog --stdout --passwordbox "Enter $sudo_user password" 0 0) || exit 1
clear
: ${sudo_user_password:?"password cannot be empty"}
sudo_user_password2=$(dialog --stdout --passwordbox "Enter $sudo_user password again" 0 0) || exit 1
clear
[[ "$sudo_user_password" == "$sudo_user_password2" ]] || ( echo "Passwords did not match"; exit 1; )

root_user_password=$(dialog --stdout --passwordbox "Enter root password" 0 0) || exit 1
clear
: ${root_user_password:?"password cannot be empty"}
root_user_password2=$(dialog --stdout --passwordbox "Enter root password again" 0 0) || exit 1
clear
[[ "$root_user_password" == "$root_user_password2" ]] || ( echo "Passwords did not match"; exit 1; )

# Installation destination
devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
# want to replace this with something other then dialog
device=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1
clear
# Checking for existing partitions and exiting, forcing user to clear partitions manually.
# This also prevents errors with partition later.
# device_check=`lsblk | grep ${device}1 | awk -F' ' '{print $6}'`
# if [ $device_check == "part" ]; then
#   echo "Partitions exist, exiting..."
#   exit
# fi

# Setup mirrors for less 404's from dumb mirrors
# curl -s "https://www.archlinux.org/mirrorlist/?country=US&protocol=https&use_mirror_status=on" | sed -e 's/^#Server/Server/' -e '/^#/d' | rankmirrors -n 10 -
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
curl -s https://gist.githubusercontent.com/endorsystems/053223063a4c91d6f75ac1ed6992b2dd/raw/ccfbff8f9ace2f21775cdcb433987baf8fd07de3/mirrorlist -o /etc/pacman.d/mirrorlist
pacman -Sy

### Setup the disk and partitions ###
swap_size=2048
swap_end=$(( $swap_size + 512 + 1 ))MiB

parted --script "${device}" -- mklabel gpt \
  mkpart ESP fat32 1Mib 513MiB \
  set 1 boot on \
  mkpart primary linux-swap 513MiB ${swap_end} \
  mkpart primary xfs ${swap_end} 100%

# Simple globbing was not enough as on one device I needed to match /dev/mmcblk0p1
# but not /dev/mmcblk0boot1 while being able to match /dev/sda1 on other devices.
part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
part_swap="$(ls ${device}* | grep -E "^${device}p?2$")"
part_root="$(ls ${device}* | grep -E "^${device}p?3$")"

wipefs "${part_boot}"
wipefs "${part_swap}"
wipefs "${part_root}"

mkfs.fat -F32 "${part_boot}"
mkswap "${part_swap}"
mkfs.xfs "${part_root}"

swapon "${part_swap}"
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
  cryptsetup \
  luks \
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
  efibootmgr \
# Laptop packages
  ansible \
  # i3 \
  # i3-gaps \
  # rofi \
  # dunst \
  # xorg-server \
  # xorg-xinit \
  # unzip \
  # stow \
  # samba \
  # cups \
  # rxvt-unicode \
  # remmina \
  # freerdp \
  # tigervnc \
  # signal-desktop \
  # ranger \
  # picom \
  # papirus-icon-theme \
  # noto-fonts \
  # lm_sensors \
  # bluez \
  # feh \
  # htop \
  # imagemagick \
  # kitty \
  # alsa \
  # pulseaudio \
  # pulseaudio-alsa \
  # pulseaudio-bluetooth \
  # xf86-input-libinput \
  # virtualbox \
  # virtualbox-host-dkms \
  # xorg-xbacklight \
  # code \
  # fish \
  # ttf-dejavu \
  # ttf-liberation \
  # ttf-roboto \
  # rsync \
  # firefox \
  # libva-intel-driver \
  # libva-vdpau-driver \
  # xf86-video-intel \
  # libva-intel-driver \
  git

# Generate fstab
genfstab /mnt >> /mnt/etc/fstab

# Set hostname
arch-chroot /mnt echo "$hostname" > /mnt/etc/hostname

# locales
arch-chroot /mnt sed -i 's/#\(en_US\.UTF-8\)/\1/' /etc/locale.gen
arch-chroot /mnt locale-gen
arch-chroot /mnt echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
arch-chroot /mnt ln -sf /usr/share/zoneinfo/US/Eastern /etc/localtime

# User config (removed $user for server installer)
arch-chroot /mnt useradd -mU -G wheel "$sudo_user"

# Sudoers edits
arch-chroot /mnt echo "$sudo_user ALL=(ALL) ALL:ALL" > /etc/sudoers.d/1-$sudo_user

# Bootloader install
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/ --bootloader-id=GRUB
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# set all passwords
echo "$sudo_user:$sudo_user_password" | chpasswd --root /mnt
echo "root:$root_user_password" | chpasswd --root /mnt

# download aur ansible module
#arch-chroot /mnt git clone https://github.com/kewlfft/ansible-aur.git /etc/ansible/plugins/modules/aur

# umount partitions
umount ${part_boot}
umount ${part_root}

# reboot
#reboot