#!/bin/bash
# nexus5x-desktop.sh: run Ubuntu 26.04 + XFCE on a Nexus 5X and show its
# desktop on this PC, over the USB cable. Nothing is flashed: the phone boots
# our kernel from RAM (fastboot boot), and its root disk is a file on this PC,
# served over the USB network. Keep this running while you use the phone.
#
# Needs: an unlocked bootloader, and on this PC fastboot (adb optional),
# qemu-nbd (qemu-utils), zstd, python3. Looks for its files next to itself
# (the release), else in this repository's out/:
#   boot-ubuntu-rev-10.img, boot-ubuntu-rev-101.img, nbd-root.sh, usb-proxy.py,
#   ubuntu-26.04-xfce-nexus5x.img (or .img.zst: unpacked on first use).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." 2>/dev/null && pwd || echo "$HERE")
find_file() { for f in "$@"; do [ -e "$f" ] && { echo "$f"; return 0; }; done; return 0; }

for t in fastboot qemu-nbd zstd python3; do
	command -v $t >/dev/null || { echo "missing $t (sudo apt install fastboot qemu-utils zstd python3)"; exit 1; }
done
IMG=$(find_file "$HERE/ubuntu-26.04-xfce-nexus5x.img" "$TOP/out/ubuntu-nbd/ubuntu.img")
if [ -z "$IMG" ]; then
	ZST=$(find_file "$HERE/ubuntu-26.04-xfce-nexus5x.img.zst")
	[ -n "$ZST" ] || { echo "no ubuntu-26.04-xfce-nexus5x.img(.zst) next to $0"; exit 1; }
	IMG=${ZST%.zst}
	echo "unpacking $(basename "$ZST") (once; an 8 GB sparse file)"
	zstd -d --sparse "$ZST" -o "$IMG"
fi
NBD=$(find_file "$HERE/nbd-root.sh")
PROXY=$(find_file "$HERE/usb-proxy.py")

# the phone's root disk and its apt proxy / clock, stopped when this exits
"$NBD" "$IMG" > /tmp/nexus5x-nbd.log 2>&1 &
NBD_PID=$!
python3 "$PROXY" > /tmp/nexus5x-proxy.log 2>&1 &
PROXY_PID=$!
trap 'kill $NBD_PID $PROXY_PID 2>/dev/null; pkill -P $NBD_PID 2>/dev/null; echo; echo "stopped: the phone has lost its disk, hold Power to turn it off"' EXIT

if ! [ -n "$(fastboot devices)" ]; then
	if command -v adb >/dev/null && adb devices | sed 1d | grep -qw device; then
		echo "Android: rebooting to the bootloader"
		adb reboot bootloader
	else
		echo "Put the phone in fastboot: hold Power + Volume down (or enable USB debugging in Android)"
	fi
	for i in $(seq 1 120); do [ -n "$(fastboot devices)" ] && break; sleep 1; done
	[ -n "$(fastboot devices)" ] || { echo "no phone in fastboot"; exit 1; }
fi

REV=$(fastboot getvar version-hardware 2>&1 | sed -n 's/^version-hardware: *//p')
case "$REV" in
rev_1.01) B=rev-101 ;;
rev_1.0) B=rev-10 ;;
*) B=rev-10; echo "hardware revision '$REV' untested, trying the rev_1.0 image" ;;
esac
BOOT=$(find_file "$HERE/boot-ubuntu-$B.img" "$TOP/out/boot-ubuntu-$B.img")
echo "booting $(basename "$BOOT") ($REV), from RAM only"
fastboot boot "$BOOT"

echo "waiting for Ubuntu (about a minute)"
for i in $(seq 1 180); do
	timeout 2 bash -c '</dev/tcp/172.16.42.1/6080' 2>/dev/null && break
	sleep 1
done
timeout 2 bash -c '</dev/tcp/172.16.42.1/6080' 2>/dev/null || {
	echo "no desktop yet. A Google logo that stays: hold Power, then run this again"; exit 1; }
echo
echo "Desktop: http://172.16.42.1:6080   (F11: fullscreen)"
echo "The VNC password is shown on the phone's screen (or ./show-password.sh)."
echo "Keep this running; Ctrl+C here takes the phone's disk away."
xdg-open http://172.16.42.1:6080 >/dev/null 2>&1 || true
wait $NBD_PID
