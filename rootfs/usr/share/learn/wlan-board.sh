#!/bin/sh
# wlan-board.sh FIRMWARE_DIR: copy the phone's own QCA6174 board data
# (calibration, /vendor/firmware/bdwlan30.bin) to
# FIRMWARE_DIR/ath10k/QCA6174/hw3.0/board.bin, where ath10k looks for it.
# It is a vendor file, so no image carries it: every Nexus 5X has it on its
# own vendor partition, mounted here read-only (noload: no journal replay).
# The chip reports PCI subsystem 0000:0000, which board-2.bin has no entry for.
DST=$1/ath10k/QCA6174/hw3.0
[ -s "$DST/board.bin" ] && exit 0
P=$(grep -l '^PARTNAME=vendor$' /sys/class/block/*/uevent 2>/dev/null | head -n1 | cut -d/ -f5)
[ -n "$P" ] || { echo "wlan-board: no vendor partition"; exit 1; }
M=/run/vendor-ro
mkdir -p $M "$DST"
mount -t ext4 -o ro,noload /dev/$P $M || { echo "wlan-board: cannot mount /dev/$P"; exit 1; }
cp $M/firmware/bdwlan30.bin "$DST/board.bin" && echo "wlan-board: board.bin from /dev/$P"
umount $M
