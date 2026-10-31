#!/bin/bash
# Build mainline Linux for the Nexus 5X (and for QEMU "virt": same Image).
set -euo pipefail
TOP=$(cd "$(dirname "$0")/.." && pwd)
KSRC=$TOP/src/linux-6.12.112-bullhead
KOUT=$TOP/out/kernel
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-

# kernel.org 6.12.112 + patches/ (display, SMP), regenerated each build.
"$TOP/scripts/prepare-kernel.sh"

# Our device trees live outside the kernel tree; drop them in at build time.
cp "$TOP"/dts/*.dts* "$KSRC/arch/arm64/boot/dts/qcom/"

mkdir -p "$KOUT"
make -C "$KSRC" O="$KOUT" defconfig
"$KSRC/scripts/kconfig/merge_config.sh" -m -O "$KOUT" "$KOUT/.config" "$TOP/scripts/kernel.config"
make -C "$KSRC" O="$KOUT" olddefconfig
make -C "$KSRC" O="$KOUT" -j"$(nproc)" Image.gz
for rev in rev-101 rev-10; do
	make -C "$KSRC" O="$KOUT" qcom/msm8992-lg-bullhead-$rev-learn.dtb
done
# Show any fragment option that did not stick (missing dependency). A disabled
# option may also vanish from .config entirely, which is fine.
grep -E '^CONFIG_' "$TOP/scripts/kernel.config" | while read -r opt; do
	grep -qxF "$opt" "$KOUT/.config" || echo "WARNING: not set: $opt"
done
sed -nE 's/^# (CONFIG_[A-Z0-9_]+) is not set/\1/p' "$TOP/scripts/kernel.config" | while read -r opt; do
	if grep -q "^$opt=[ym]" "$KOUT/.config"; then echo "WARNING: still enabled: $opt"; fi
done
# LK (aboot) loads a 64-bit kernel at 0x80000 and the DTB at 0x1e00000.
# The arm64 Image header (offset 16) holds the full in-memory size incl. BSS.
size=$(od -An -t u8 -j 16 -N 8 "$KOUT/arch/arm64/boot/Image" | tr -d ' ')
printf 'kernel image_size: %d bytes (%d MiB), limit %d\n' "$size" $((size >> 20)) $((0x1e00000 - 0x80000))
[ "$size" -lt $((0x1e00000 - 0x80000)) ] || echo "WARNING: kernel overlaps LK's DTB/ramdisk area"
ls -la "$KOUT/arch/arm64/boot/Image.gz" "$KOUT"/arch/arm64/boot/dts/qcom/*learn.dtb
