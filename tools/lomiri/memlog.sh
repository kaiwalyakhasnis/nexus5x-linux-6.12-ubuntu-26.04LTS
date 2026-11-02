#!/bin/sh
# memlog.sh: every 2 s, memory, swap and GPU activity to /var/log/memlog.txt
# (fsynced), so a lockup leaves a trail on the disk.
while :; do
	{ date +%T; grep -E "MemAvailable|SwapFree|Shmem:|CmaFree" /proc/meminfo | tr -s ' ' | tr '\n' ' '
	  echo; cat /sys/class/devfreq/*/cur_freq 2>/dev/null; uptime; } >> /var/log/memlog.txt
	sync /var/log/memlog.txt
	sleep 2
done
