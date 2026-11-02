#!/bin/bash
# Image.gz + appended DTB + initramfs -> boot-<rev>.img for `fastboot boot`.
set -euo pipefail
TOP=$(cd "$(dirname "$0")/.." && pwd)
K=$TOP/out/kernel/arch/arm64/boot
# clk/pd/regulator_ignore_unused: keep what LK switched on alive (the display
# pipeline until the msm driver takes it over, rails nothing claims yet).
# msm.vram + cma: the MDP has no IOMMU here and scans out of a contiguous
# carveout (1080x1920 XRGB = 8 MiB per buffer); the GPU has no IOMMU either
# and works from the same carveout (msm.allow_vram_carveout=1), so it is
# bigger: window buffers come out of it too. consoleblank=0: blanking the
# console would power the panel down and up again through the new driver.
# arm64.late_cpu_conflicts=warn: the A57s start at late init and would be
# refused for capabilities the A53-only boot did not enable (kernel patch 0009).
CMDLINE="console=tty0 earlycon clk_ignore_unused pd_ignore_unused regulator_ignore_unused cma=320M msm.vram=256m msm.allow_vram_carveout=1 consoleblank=0 fbcon=font:TER16x32 arm64.late_cpu_conflicts=warn rdinit=/init"
# Two images per board revision: the panel driver either power-cycles the
# panel and sends LK's full init (gamma + on-commands), or keeps LK's state.
for rev in rev-101 rev-10; do
	cat "$K/Image.gz" "$K/dts/qcom/msm8992-lg-bullhead-$rev-learn.dtb" > "$TOP/out/Image.gz-dtb-$rev"
	python3 "$TOP/scripts/mkbootimg.py" \
		--kernel "$TOP/out/Image.gz-dtb-$rev" --ramdisk "$TOP/out/initramfs.cpio.gz" \
		--cmdline "$CMDLINE" -o "$TOP/out/boot-$rev.img"
	python3 "$TOP/scripts/mkbootimg.py" \
		--kernel "$TOP/out/Image.gz-dtb-$rev" --ramdisk "$TOP/out/initramfs.cpio.gz" \
		--cmdline "$CMDLINE panel_lg_bullhead_jd35695b.keep=1" -o "$TOP/out/boot-$rev-keep.img"
	# Ubuntu from the PC's disk (tools/ubuntu/nbd-root.sh; rootfs/init). The
	# classic interface names keep udev from renaming usb0 under the NBD root.
	python3 "$TOP/scripts/mkbootimg.py" \
		--kernel "$TOP/out/Image.gz-dtb-$rev" --ramdisk "$TOP/out/initramfs.cpio.gz" \
		--cmdline "$CMDLINE ubuntu=nbd net.ifnames=0" -o "$TOP/out/boot-ubuntu-$rev.img"
done
