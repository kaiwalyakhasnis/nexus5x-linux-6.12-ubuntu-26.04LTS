#!/bin/bash
# Pack rootfs/ + static busybox into a cpio initramfs (what the kernel unpacks into RAM).
set -euo pipefail
TOP=$(cd "$(dirname "$0")/.." && pwd)
STAGE=$TOP/out/initramfs
rm -rf "$STAGE"
mkdir -p "$STAGE"/{bin,sbin,usr/bin,usr/sbin,dev,proc,sys,run,tmp,root,mnt}
cp -a "$TOP"/rootfs/. "$STAGE"/
cp "$TOP/out/busybox/busybox" "$STAGE/bin/busybox"
# reboot-to bootloader|recovery: BusyBox's reboot cannot pass a reason
aarch64-linux-gnu-gcc -static -Os -s -o "$STAGE/sbin/reboot-to" "$TOP/tools/reboot-to/reboot-to.c"
# touchtest [seconds]: paint what the touchscreen reports
aarch64-linux-gnu-gcc -static -Os -s -o "$STAGE/usr/bin/touchtest" "$TOP/tools/touchtest/touchtest.c"
# Wi-Fi: the modules from build-kernel.sh and the QCA6174 firmware. The
# board data (calibration) is the phone's own, copied at boot from its vendor
# partition (rootfs/usr/share/learn/wlan-board.sh), so no image carries it.
cp -a "$TOP/out/modules/." "$STAGE/"
FW=$STAGE/lib/firmware/ath10k/QCA6174/hw3.0
mkdir -p "$FW"
cp "$TOP/downloads/linux-firmware/firmware-6.bin" "$TOP/downloads/linux-firmware/notice_ath10k_firmware-6.txt" "$FW/"
cp "$TOP"/downloads/linux-firmware/regulatory.db* "$STAGE/lib/firmware/"
ln -sf /bin/busybox "$STAGE/sbin/init"
ln -sf busybox "$STAGE/bin/sh"
# /dev/console must exist before devtmpfs is mounted, or init has no stdout.
# The kernel's gen_init_cpio takes a text list, so no root is needed for the device node.
KOUT=$TOP/out/kernel
LIST=$TOP/out/initramfs.list
{
	cd "$STAGE"
	find . -mindepth 1 | sort | while read -r f; do
		p=${f#.}
		m=$(stat -c %a "$f")
		if [ -L "$f" ]; then echo "slink $p $(readlink "$f") 0777 0 0"
		elif [ -d "$f" ]; then echo "dir $p $m 0 0"
		else echo "file $p $STAGE$p $m 0 0"; fi
	done
	echo "nod /dev/console 0600 0 0 c 5 1"   # after "dir /dev"
} > "$LIST"
"$KOUT/usr/gen_init_cpio" "$LIST" | gzip -9 > "$TOP/out/initramfs.cpio.gz"
ls -la "$TOP/out/initramfs.cpio.gz"
