#!/bin/bash
# nbd-install.sh: fill the phone's Ubuntu disk once, so the phone can boot it
# (boot image boot-ubuntu-rev-*.img, "ubuntu=nbd"). Needs the phone in the
# BusyBox system (normal boot image) and tools/ubuntu/nbd-root.sh running.
#
# The disk is attached as /dev/nbd0 on /ubuntu, where ubuntu-on-phone.sh then
# unpacks Ubuntu Base (instead of into RAM) and sets up SSH. On top come
# systemd, our kernel's Wi-Fi modules and firmware (copied from the running
# initramfs), an fstab for the NBD root, and root auto-login on the panel.
set -euo pipefail
TOP=$(cd "$(dirname "$0")/../.." && pwd)
PHONE=172.16.42.1
tel() { (sleep 1; echo "$1"; sleep "${2:-2}") | timeout $((${2:-2} + 3)) nc $PHONE 23 2>/dev/null | tr -d '\r' || true; }

pgrep -x qemu-nbd >/dev/null || { echo "start tools/ubuntu/nbd-root.sh first"; exit 1; }
ping -c1 -W2 $PHONE >/dev/null || { echo "phone not reachable on $PHONE"; exit 1; }
if tel 'mountpoint -q /ubuntu && echo UBUNTU_BUSY' | grep -aqx UBUNTU_BUSY; then
	echo "/ubuntu is in use on the phone (RAM Ubuntu?): reboot it into BusyBox first"; exit 1
fi
tel 'nbd-client -N ubuntu 172.16.42.2 10809 /dev/nbd0; for i in 1 2 3 4 5 6 7 8; do [ "$(cat /sys/block/nbd0/size)" -gt 0 ] && break; sleep 1; done; mkdir -p /ubuntu; mount -t ext4 -o noatime /dev/nbd0 /ubuntu && echo DISK_MOUNTED' 10 \
	| grep -aqx DISK_MOUNTED || { echo "could not attach the disk"; exit 1; }
echo "disk attached on the phone as /dev/nbd0 on /ubuntu"

UBUNTU_RAM=unused "$TOP/tools/ubuntu/ubuntu-on-phone.sh"

echo "installing systemd and setting up the NBD boot"
"$TOP/tools/ubuntu/ssh-phone.sh" 'set -e
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -q --no-install-recommends systemd-sysv udev kmod iproute2 dbus \
	iputils-ping iw wpasupplicant >/dev/null
# the root is mounted by the initramfs; never fsck it from here
echo "/dev/nbd0 / ext4 noatime 0 0" > /etc/fstab
echo bullhead > /etc/hostname
printf "127.0.0.1 localhost\n127.0.1.1 bullhead\n" > /etc/hosts
# the running initramfs (PID 1 here is BusyBox init) has our kernel modules
# and the QCA6174 firmware
cp -a /proc/1/root/lib/modules/. /usr/lib/modules/
mkdir -p /usr/lib/firmware && cp -a /proc/1/root/lib/firmware/. /usr/lib/firmware/
# the panel (tty1) logs in as root, as the BusyBox system does
mkdir -p /etc/systemd/system/getty@tty1.service.d
printf "[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin root --noclear %%I \$TERM\n" \
	> /etc/systemd/system/getty@tty1.service.d/autologin.conf
systemctl enable ssh >/dev/null 2>&1 || true
ls -l /sbin/init; du -sh --exclude=proc --exclude=sys --exclude=dev / 2>/dev/null | tail -1
echo NBD_SETUP_OK' </dev/null | tee /dev/stderr | grep -aqx NBD_SETUP_OK || { echo "setup failed"; exit 1; }

# stop what ubuntu-on-phone.sh started in the chroot, then detach the disk
tel 'killall sshd; sleep 1; sync; for m in dev/pts dev sys proc tmp; do umount /ubuntu/$m 2>/dev/null; done; umount /ubuntu && nbd-client -d /dev/nbd0 && echo DISK_DETACHED' 5 \
	| grep -aqx DISK_DETACHED || echo "WARNING: the disk is still attached on the phone"
echo "done: boot out/boot-ubuntu-rev-10.img (scripts/phone-boot.sh) with nbd-root.sh running"
