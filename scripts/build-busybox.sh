#!/bin/bash
# Static BusyBox: one ~2 MB binary that provides sh, init, mount, ls, telnetd...
set -euo pipefail
TOP=$(cd "$(dirname "$0")/.." && pwd)
BOUT=$TOP/out/busybox
mkdir -p "$BOUT"
# patches-busybox/*.patch, each applied once
for p in "$TOP"/patches-busybox/*.patch; do
	[ -e "$p" ] || continue
	patch -d "$TOP/src/busybox-1.36.1" -p1 -R -s -f --dry-run < "$p" >/dev/null 2>&1 ||
		patch -d "$TOP/src/busybox-1.36.1" -p1 -s < "$p"
done
make -C "$TOP/src/busybox-1.36.1" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O="$BOUT" defconfig
# CONFIG_TC does not build against kernel headers >= 6.8 (CBQ was removed).
sed -i -e 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' -e 's/^CONFIG_TC=y/# CONFIG_TC is not set/' "$BOUT/.config"
make -C "$BOUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)"
