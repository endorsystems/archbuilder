#!/bin/bash
# Arch Installer
# Built by sean@endorsystems.com
set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

REPO_URL=https://mirror.endorsystems.com/archlinux/$repo/os/$arch

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

devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
device=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1
clear

offline=$(dialog --stdout --inputbox "Offline install?" 0 0)

### Set up logging ###
exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")

timedatectl set-ntp true

### Setup the disk and partitions ###
swap_size=2048MiB
swap_end=$(( $swap_size + 129 + 1 ))MiB

parted --script "${device}" -- mklabel gpt \
  mkpart ESP fat32 1Mib 512MiB \
  set 1 boot on \
  mkpart primary linux-swap 129MiB ${swap_end} \
  mkpart primary ext4 ${swap_end} 100%

# Simple globbing was not enough as on one device I needed to match /dev/mmcblk0p1
# but not /dev/mmcblk0boot1 while being able to match /dev/sda1 on other devices.
part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
part_swap="$(ls ${device}* | grep -E "^${device}p?2$")"
part_root="$(ls ${device}* | grep -E "^${device}p?3$")"

wipefs "${part_boot}"
wipefs "${part_swap}"
wipefs "${part_root}"

mkfs.ext4 "${part_boot}"
mkswap "${part_swap}"
mkfs.ext4 "${part_root}"

swapon "${part_swap}"
mount "${part_root}" /mnt
mkdir /mnt/boot
mount "${part_boot}" /mnt/boot

### Install and configure the basic system ###
cat >>/etc/pacman.conf <<EOF
[endor]
SigLevel = Optional TrustAll
Server = $REPO_URL
EOF

pacstrap /mnt \
  base \
  base-devel \
  linux linux-firmware \
  cryptsetup \
  device-mapper \
  networkmanager \
  network-manager-applet \
  inetutils \
  diffutils \
  e2fsprogs \
  man-db \
  man-pages \
  perl \
  reiserfsprogs \
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
  fish \
  openssh

# Setup sshd for use, root as needed.
sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes'
mkdir /mnt/root/.ssh
echo "" > /mnt/root/.ssh/authorized_keys
arch-chroot /mnt systemctl enable sshd

# Generate 
genfstab -t PARTUUID /mnt >> /mnt/etc/fstab
echo "${hostname}" > /mnt/etc/hostname

# Repo setup - default home mirror
cat >>/mnt/etc/pacman.conf <<EOF
[endor]
SigLevel = Optional TrustAll
Server = $REPO_URL
EOF

# Bootloader install
arch-chroot /mnt grub-install /dev/sda
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

arch-chroot /mnt sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

arch-chroot /mnt useradd -mU -s /usr/bin/fish -G wheel "$user"
arch-chroot /mnt chsh -s /usr/bin/zsh

echo "$user:$password" | chpasswd --root /mnt
echo "root:$password" | chpasswd --root /mnt
