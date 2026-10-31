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
