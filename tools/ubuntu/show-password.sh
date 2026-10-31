#!/bin/sh
# show-password.sh [IMG]: print the desktop's VNC password (also shown on the
# phone's screen), read-only from the phone's disk image on this PC. The
# first boot makes it. debugfs is in e2fsprogs.
HERE=$(cd "$(dirname "$0")" && pwd)
IMG=$1
[ -n "$IMG" ] || for f in "$HERE/ubuntu-26.04-xfce-nexus5x.img" "$HERE/../../out/ubuntu-nbd/ubuntu.img"; do
	[ -e "$f" ] && { IMG=$f; break; }
done
[ -n "$IMG" ] || { echo "no disk image found"; exit 1; }
PW=$(/sbin/debugfs -c -R "cat /etc/nexus5x-vnc-password" "$IMG" 2>/dev/null)
[ -n "$PW" ] || { echo "no password yet: boot the phone once (nexus5x-desktop.sh)"; exit 1; }
echo "$PW"
