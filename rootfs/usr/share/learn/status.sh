#!/bin/sh
# Shown on the phone panel (tty2: Alt+F2 or chvt 2). Refreshes every 2 s.
while :; do
	clear
	echo "  Nexus 5X - mainline Linux $(uname -r)"
	echo "  $(tr -d '\0' < /proc/device-tree/model 2>/dev/null)"
	echo
	echo "  uptime : $(cut -d' ' -f1 /proc/uptime) s"
	echo "  load   : $(cut -d' ' -f1-3 /proc/loadavg)"
	echo "  cpus   : $(cat /sys/devices/system/cpu/online)"
	echo "  mem    : $(awk '/MemAvailable/{print int($2/1024)" MiB free"}' /proc/meminfo)"
	echo "  procs  : $(ls -d /proc/[0-9]* | wc -l)"
	echo "  usb0   : $(ifconfig usb0 2>/dev/null | awk '/inet /{print $2}' || echo none)"
	echo "  mmc    : $(ls /sys/block | grep mmc | tr '\n' ' ')"
	echo "  battery: $(cat /sys/class/power_supply/*/capacity 2>/dev/null | head -n1)"
	echo
	echo "  PC: telnet 172.16.42.1"
	echo "  Hold POWER ~10 s to force reboot"
	echo
	dmesg | tail -n 25 | cut -c1-60
	sleep 2
done
