#!/bin/bash
# Same kernel + initramfs on an emulated generic arm64 board. Interactive shell
# on this terminal (serial ttyAMA0). Quit with Ctrl-A then X.
TOP=$(cd "$(dirname "$0")/.." && pwd)
exec qemu-system-aarch64 -M virt -cpu cortex-a57 -smp 2 -m 1024 -nographic \
	-kernel "$TOP/out/kernel/arch/arm64/boot/Image" \
	-initrd "$TOP/out/initramfs.cpio.gz" \
	-append "console=ttyAMA0 rdinit=/init" "$@"
