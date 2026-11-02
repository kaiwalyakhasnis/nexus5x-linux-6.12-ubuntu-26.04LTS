#!/bin/bash
# make-release.sh VERSION: out/release/nexus5x-ubuntu-desktop-VERSION.tar with
# what a Nexus 5X owner needs next to the disk image (make-release-disk.sh):
# the Ubuntu boot images for both board revisions and the PC-side scripts.
set -euo pipefail
TOP=$(cd "$(dirname "$0")/../.." && pwd)
VER=${1:?usage: make-release.sh VERSION}
NAME=nexus5x-ubuntu-desktop-$VER
D=$TOP/out/release/$NAME
rm -rf "$D"
mkdir -p "$D"
cp "$TOP"/out/boot-ubuntu-rev-10.img "$TOP"/out/boot-ubuntu-rev-101.img "$D/"
cp "$TOP"/tools/ubuntu/{nexus5x-desktop.sh,nbd-root.sh,usb-proxy.py,show-password.sh} "$D/"
cat > "$D/README.txt" <<EOF
Ubuntu 26.04.1 + Lomiri on a Nexus 5X's own screen, drawn by its GPU ($VER)
https://github.com/kaiwalyakhasnis/nexus5x-linux-6.12-wip

An experiment, use at your own risk. Nothing is flashed: the phone boots
from RAM (fastboot boot), and Ubuntu's disk is a file on this PC.

1. Put ubuntu-26.04-lomiri-nexus5x.img.zst (separate download) in this folder.
2. sudo apt install fastboot adb qemu-utils zstd
3. Unlocked bootloader; phone on USB in Android (USB debugging) or fastboot.
4. ./nexus5x-desktop.sh   and keep it running. Lomiri comes up on the phone.
   If the Google logo stays, hold Power and run it again (about 1 boot in 6).
   Wi-Fi: sudo nmtui in the Terminal app.

The XFCE desktop in the PC's browser is still on the disk. To use it instead,
in the Terminal app:
   sudo systemctl disable lomiri-phone
   sudo systemctl enable xfce-vnc novnc
   sudo reboot
Then run ./nexus5x-desktop.sh again. The browser opens http://172.16.42.1:6080
and ./show-password.sh prints the VNC password.

A reboot of the phone goes back to whatever is installed on it.
EOF
(cd "$TOP/out/release" && tar cf "$NAME.tar" "$NAME" && sha256sum "$NAME.tar" | tee "$NAME.tar.sha256")
ls -la "$TOP/out/release/$NAME.tar"
