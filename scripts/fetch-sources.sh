#!/bin/bash
# Download + unpack pristine upstream sources into src/ (not tracked in git).
set -euo pipefail
TOP=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$TOP/downloads" "$TOP/src"
cd "$TOP/downloads"
[ -f linux-6.12.112.tar.xz ] || curl -fLO https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.112.tar.xz
[ -f busybox-1.36.1.tar.bz2 ] || curl -fLO https://busybox.net/downloads/busybox-1.36.1.tar.bz2
# Wi-Fi: the QCA6174's ath10k firmware (linux-firmware, with its licence
# notice) and the signed regulatory database (wireless-regdb). The board data
# (calibration) is the phone's own, copied at boot from its vendor partition.
mkdir -p linux-firmware
LF=https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain
RD=https://git.kernel.org/pub/scm/linux/kernel/git/wens/wireless-regdb.git/plain
for f in firmware-6.bin notice_ath10k_firmware-6.txt; do
	[ -f linux-firmware/$f ] || curl -fL -o linux-firmware/$f "$LF/ath10k/QCA6174/hw3.0/$f?h=20241210"
done
for f in regulatory.db regulatory.db.p7s; do
	[ -f linux-firmware/$f ] || curl -fL -o linux-firmware/$f "$RD/$f?h=master-2024-10-07"
done
sha256sum -c <<'SUMS'
04d3bad5efa3f9fbe3ba53fd3e25fa9b0585ed227eea8111303b4e08861f979d  linux-firmware/firmware-6.bin
8ce5c6ea0542bf4aac31fc3ae16a39792ad22d0eae4543063fac56fb3380f021  linux-firmware/notice_ath10k_firmware-6.txt
92eec693a0a9ec460be6bb3ff9e22b259b2f906eddd2984dd90654b5ecfa0f18  linux-firmware/regulatory.db
4242d15defb0608b917a2c3cd0dbea21c026a4acc905093e8947dd494c2e26b1  linux-firmware/regulatory.db.p7s
SUMS
cd "$TOP/src"
[ -d linux-6.12.112 ] || tar xf ../downloads/linux-6.12.112.tar.xz
[ -d busybox-1.36.1 ] || tar xf ../downloads/busybox-1.36.1.tar.bz2
