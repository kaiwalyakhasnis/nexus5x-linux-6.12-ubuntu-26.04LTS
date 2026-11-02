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
# GPU: the Adreno 418 runs the A420 microcode (qcom/, LICENSE.qcom)
for f in qcom/a420_pm4.fw qcom/a420_pfp.fw LICENSE.qcom; do
	[ -f linux-firmware/${f#qcom/} ] || curl -fL -o linux-firmware/${f#qcom/} "$LF/$f?h=20241210"
done
for f in regulatory.db regulatory.db.p7s; do
	[ -f linux-firmware/$f ] || curl -fL -o linux-firmware/$f "$RD/$f?h=master-2024-10-07"
done
sha256sum -c <<'SUMS'
04d3bad5efa3f9fbe3ba53fd3e25fa9b0585ed227eea8111303b4e08861f979d  linux-firmware/firmware-6.bin
8ce5c6ea0542bf4aac31fc3ae16a39792ad22d0eae4543063fac56fb3380f021  linux-firmware/notice_ath10k_firmware-6.txt
92eec693a0a9ec460be6bb3ff9e22b259b2f906eddd2984dd90654b5ecfa0f18  linux-firmware/regulatory.db
4242d15defb0608b917a2c3cd0dbea21c026a4acc905093e8947dd494c2e26b1  linux-firmware/regulatory.db.p7s
52eced2d9a908651d3f34ad5f68fc5f17d2c46c00b20530bbf1bedd54e5d5512  linux-firmware/a420_pm4.fw
cca23b697d4a08d8146893985f8196960106a936de74d9a60d6e70cca79d46eb  linux-firmware/a420_pfp.fw
be904cd28cb292b80cdb6cf412ab0d9159d431671e987ad433c1f62e0988a9bc  linux-firmware/LICENSE.qcom
SUMS
cd "$TOP/src"
[ -d linux-6.12.112 ] || tar xf ../downloads/linux-6.12.112.tar.xz
[ -d busybox-1.36.1 ] || tar xf ../downloads/busybox-1.36.1.tar.bz2
