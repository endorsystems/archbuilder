#!/bin/bash
# Arch Installer (Server based installer)
# Built by sean@endorsystems.com
set -uo pipefail
#trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

# Check for existing host info
arg_hostname="$@"
FILE="host_vars/$arg_hostname"
if test -f "$FILE"; then
  echo "$FILE exists... importing settings"
  source $FILE
else
  ### Get infomation from user ###
  echo "$FILE doesn't exist... asking for info."
  
  hostname=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
  clear
  : ${hostname:?"hostname cannot be empty"}

  # user=$(dialog --stdout --inputbox "Enter admin username" 0 0) || exit 1
  # clear
  # : ${user:?"user cannot be empty"}

  # password=$(dialog --stdout --passwordbox "Enter admin password" 0 0) || exit 1
  # clear
  # : ${password:?"password cannot be empty"}
  # password2=$(dialog --stdout --passwordbox "Enter admin password again" 0 0) || exit 1
  # clear
  # [[ "$password" == "$password2" ]] || ( echo "Passwords did not match"; exit 1; )

  rootpassword=$(dialog --stdout --passwordbox "Enter root password" 0 0) || exit 1
  clear
  : ${rootpassword:?"password cannot be empty"}
  rootpassword2=$(dialog --stdout --passwordbox "Enter root password again" 0 0) || exit 1
  clear
  [[ "$rootpassword" == "$rootpassword2" ]] || ( echo "Passwords did not match"; exit 1; )

  ipv4_address=$(dialog --stdout --inputbox "Enter Primary ipv4 address without CIDR (10.10.10.100)" 0 0) || exit 1
  clear
  : ${ipv4_address:?"ipv4 cannot be blank"}

  # ipv4_gateway=$(dialog --stdout --inputbox "Enter default gateway" 0 0) || exit 1
  # clear
  # : ${ipv4_gateway:?"gateway cannot be empty"}

  # dns_search=$(dialog --stdout --inputbox "Enter Domain Search" 0 0) || exit 1
  # clear
  # : ${dns_search:?"dns search cannot be empty"}

  # ipv4_dns1=$(dialog --stdout --inputbox "Enter primary DNS" 0 0) || exit 1
  # clear
  # : ${ipv4_dns1:?"primary dns cannot be empty"}

  # ipv4_dns2=$(dialog --stdout --inputbox "Enter secondary DNS" 0 0) || exit 1
  # clear
  # : ${ipv4_dns2:?"secondary dns cannot be empty"}

  # getting interface name

  devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
  device=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1
fi

# getting interface name
ifname=`ip a | grep "2:" | awk -F':' '{print $2}' | sed -e 's/^[[:space:]]*//'`

clear

# generate UUID for interface
# ifuuid=`uuidgen ${ifname}`

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
  netctl \
  git \
  dnsutils \
  iperf \
  qemu-guest-agent

# Generate 
genfstab /mnt >> /mnt/etc/fstab

# Set hostname
arch-chroot /mnt echo "${hostname}" > /mnt/etc/hostname

# set some root user stuff
arch-chroot /mnt 

# locales
arch-chroot /mnt sed -i 's/#\(en_US\.UTF-8\)/\1/' /etc/locale.gen
arch-chroot /mnt locale-gen
arch-chroot /mnt echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
arch-chroot /mnt ln -sf /usr/share/zoneinfo/US/Eastern /etc/localtime

# Setup sshd for use, root as needed.
arch-chroot /mnt sed -i 's/#\(PermitRootLogin \).\+/\1yes/' /etc/ssh/sshd_config
arch-chroot /mnt mkdir /root/.ssh
arch-chroot /mnt echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCz47smL6+lCmLtBnstgSEBa3S2YW0Ys+qGUqAC6m1gxEQB5wshjAlB/BuoSlc6HpDVGhOvxWq/Zl7Uh2toSg2uDjhRaqXe2MgpGzWkmL+7VXbF3Iv/NRssEXKs5vc6W/b10bRbTkoy3RyGIrtozYl+M5uXj4oxSnVFnR4kwk194apVdTMJRYcbgxHShxURJipofdBGtEIkGMyrNgZRAOoqFGEnOOmfpov5hRpJwhYifBK/pCjM73BJ4slm9tp0iwVj7mgmmWH9gEqBM+1A9WZ1bkGxO5CArkeN8lBL90D2bm/IWSYNngfHhcy1ndozb7A2nDVbpvae9EGDOdXXgYsiybPsEMj1YRYFgwmfhi8hKOamndcKCIllIqh/wd0ZRyTgbFcdlbOvh6bN6eDoPbRz9gMgwnrWglMNHbq/uQrZ2HjAKinLY4UfC0gidXlchZoj0NJ2q9UuJhRGMIsx91wGBpbyO1CzVkLTRtpsOxmHEzb4K5V6r9CMJLI1iI/OocnKW5SxZhlTK2wgRYaEUzfya0By+0yqC33vDk+u8a/KRBTpuM0cTSFBDtpzeGahizW3hPXfbzbl/QjrZZybBwFHrk8NE7kdCa8InuaoYY8Z0Z/lJyXAmbKfxyUS/rJQjvLQev1L2tmOBIPuXkx5mHJGwDV1AhOQ4e6rBsWlmFZXiQ== root@kronos" > /mnt/root/.ssh/authorized_keys

# Systemd enables
arch-chroot /mnt systemctl enable qemu-ga.service
arch-chroot /mnt systemctl enable sshd

# Setup netctl
cat >>/mnt/etc/netctl/${ifname} <<EOF
Description='Primary Static'
Interface=${ifname}
Connection=ethernet
IP=static
Address=('${ipv4_address}/23')
Gateway='10.10.10.1'
DNS=('10.10.10.3' '1.1.1.1')
DNSSearch=endorsystems.com
EOF
arch-chroot /mnt netctl enable ${ifname}

# Bootloader install
arch-chroot /mnt grub-install ${device}
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# User config (removed $user for server installer)
#arch-chroot /mnt useradd -m -s /usr/bin/fish -G wheel "$user"
#arch-chroot /mnt chsh -s /usr/bin/fish

#echo "$user:$password" | chpasswd --root /mnt
echo "root:$rootpassword" | chpasswd --root /mnt

# umount partitions
umount ${part_boot}
umount ${part_root}

# reboot
#reboot