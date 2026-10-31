#!/bin/bash
# phone-boot.sh [IMG]: get the phone into fastboot from wherever it is (our
# kernel over telnet, Android over adb, or already in fastboot), then
# `fastboot boot` IMG (RAM only, nothing is flashed) and wait for USB network.
TOP=$(cd "$(dirname "$0")/.." && pwd)
IMG=${1:-$TOP/out/boot-rev-10.img}
if ping -c1 -W1 172.16.42.1 >/dev/null 2>&1; then
	echo "our kernel: reboot-to bootloader"
	# sync first: under Ubuntu the root disk is on the PC (ubuntu=nbd). Ubuntu
	# has no telnet: SSH there (tools/ubuntu/ssh-phone.sh, this PC's key).
	if timeout 2 bash -c '</dev/tcp/172.16.42.1/23' 2>/dev/null; then
		(sleep 1; echo 'sync; reboot-to bootloader'; sleep 3) | timeout 7 nc 172.16.42.1 23 >/dev/null 2>&1
	else
		timeout 15 "$TOP/tools/ubuntu/ssh-phone.sh" 'sync; reboot-to bootloader' </dev/null >/dev/null 2>&1
	fi
fi
for i in $(seq 1 90); do
	[ -n "$(fastboot devices)" ] && break
	if adb devices | sed 1d | grep -qw device; then
		echo "android: adb reboot bootloader"
		adb reboot bootloader
		sleep 5
	fi
	sleep 2
done
[ -n "$(fastboot devices)" ] || { echo "no fastboot device"; exit 1; }
fastboot boot "$IMG" 2>&1 | tail -1
for i in $(seq 1 60); do
	ping -c1 -W1 172.16.42.1 >/dev/null 2>&1 && { echo "USB network up after ${i}s"; exit 0; }
	sleep 1
done
echo "no USB network"; exit 1
