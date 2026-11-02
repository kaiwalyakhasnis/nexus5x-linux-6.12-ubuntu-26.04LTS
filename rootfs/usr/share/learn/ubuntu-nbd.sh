#!/bin/sh
# Run by /init for "ubuntu=nbd": bring up the USB network, attach the Ubuntu
# disk the PC serves (tools/ubuntu/nbd-root.sh: qemu-nbd, export "ubuntu", port
# 10809) as /dev/nbd0, mount it on /newroot and move the API filesystems
# there, ready for switch_root. Exit 1 to stay in BusyBox instead.
#
# udhcpd (the PC's USB address) and nbd-client keep running under Ubuntu:
# they were started from here and switch_root does not stop them.
NEWROOT=/newroot

UDC=
for i in $(seq 1 10); do
	UDC=$(ls /sys/class/udc 2>/dev/null | head -n1)
	[ -n "$UDC" ] && break
	sleep 1
done
[ -n "$UDC" ] || { echo "ubuntu-nbd: no USB device controller"; exit 1; }
/usr/share/learn/usb-gadget.sh "$UDC"
ifconfig lo 127.0.0.1 up
ifconfig usb0 172.16.42.1 netmask 255.255.255.0 up
udhcpd /etc/udhcpd.conf

# -p reconnects if the link drops, but the first connect still fails while the
# PC has no USB address yet: start it again until the disk is there
echo "ubuntu-nbd: waiting for the PC's disk (tools/ubuntu/nbd-root.sh)"
for i in $(seq 1 60); do
	[ "$(cat /sys/block/nbd0/size 2>/dev/null)" -gt 0 ] 2>/dev/null && break
	pidof nbd-client >/dev/null || nbd-client -p -N ubuntu 172.16.42.2 10809 /dev/nbd0
	sleep 1
done
[ "$(cat /sys/block/nbd0/size 2>/dev/null)" -gt 0 ] 2>/dev/null || {
	echo "ubuntu-nbd: no disk after 60 s"; nbd-client -d /dev/nbd0; exit 1; }

# no RTC: take the PC's clock (tools/ubuntu/usb-proxy.py), or apt rejects
# its package lists as "not valid yet"
T=$(wget -q -T 3 -O- http://172.16.42.2:3128/time 2>/dev/null) && date -u -s "@$T" >/dev/null

mkdir -p $NEWROOT
mount -t ext4 -o noatime /dev/nbd0 $NEWROOT || { echo "ubuntu-nbd: mount failed"; exit 1; }
# switch_root execs this; without it PID 1 would die and the kernel panic
if [ ! -x $NEWROOT/sbin/init ] && [ ! -L $NEWROOT/sbin/init ]; then
	echo "ubuntu-nbd: no /sbin/init on the disk (systemd-sysv not installed?)"
	umount $NEWROOT; exit 1
fi
# this kernel's modules and the Wi-Fi calibration, if the disk lacks them
# (a disk made with another build of the kernel, or a released one)
K=$(uname -r)
[ -d $NEWROOT/usr/lib/modules/$K ] || cp -a /lib/modules/$K $NEWROOT/usr/lib/modules/
/usr/share/learn/wlan-board.sh $NEWROOT/usr/lib/firmware
# the GPU microcode (the disk may not have linux-firmware)
[ -f $NEWROOT/usr/lib/firmware/qcom/a420_pm4.fw ] || { mkdir -p $NEWROOT/usr/lib/firmware/qcom; cp /lib/firmware/qcom/* $NEWROOT/usr/lib/firmware/qcom/; }
# reboot-to bootloader|recovery (scripts/phone-boot.sh uses it over telnet)
cp /sbin/reboot-to $NEWROOT/usr/sbin/reboot-to
umount /tmp 2>/dev/null
for m in dev proc sys run; do
	mkdir -p $NEWROOT/$m
	mount --move /$m $NEWROOT/$m
done
echo "ubuntu-nbd: switching to Ubuntu on /dev/nbd0"
