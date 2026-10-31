#!/bin/bash
# phone-boot.sh [IMG]: get the phone into fastboot from wherever it is (our
# kernel over telnet, Android over adb, or already in fastboot), then
# `fastboot boot` IMG (RAM only, nothing is flashed) and wait for USB network.
TOP=$(cd "$(dirname "$0")/.." && pwd)
IMG=${1:-$TOP/out/boot-rev-10.img}
if ping -c1 -W1 172.16.42.1 >/dev/null 2>&1; then
	echo "our kernel: reboot-to bootloader"
	(sleep 1; echo 'reboot-to bootloader'; sleep 2) | timeout 6 nc 172.16.42.1 23 >/dev/null 2>&1
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
