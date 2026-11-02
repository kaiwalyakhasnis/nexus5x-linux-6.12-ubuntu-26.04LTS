#!/bin/bash
# make-release-disk.sh [IMG]: the shareable disk for nexus5x-desktop.sh, from
# this PC's working one (out/ubuntu-nbd/ubuntu.img by default):
# out/release/ubuntu-26.04-lomiri-nexus5x.img.zst.
#
# Needs the phone in the BusyBox system (boot-rev-*.img), never the Ubuntu it
# cleans: a copy is attached there as /dev/nbd1 and stripped of everything
# personal or per-phone (SSH keys, VNC password, Wi-Fi settings, the vendor
# Wi-Fi calibration, machine id, apt lists, logs, history, browser data, what
# the keyboard learned, build trees), then trimmed so the free space compresses
# to nothing. The first boot makes new ones. The copy starts Lomiri on the panel
# at boot instead of the VNC desktop; the working disk keeps its own setting.
set -euo pipefail
TOP=$(cd "$(dirname "$0")/../.." && pwd)
SRC=${1:-$TOP/out/ubuntu-nbd/ubuntu.img}
OUT=$TOP/out/release
IMG=$OUT/ubuntu-26.04-lomiri-nexus5x.img
PHONE=172.16.42.1
tel() { (sleep 1; echo "$1"; sleep "${2:-2}") | timeout $((${2:-2} + 3)) nc $PHONE 23 2>/dev/null | tr -d '\r' || true; }

timeout 2 bash -c "</dev/tcp/$PHONE/23" 2>/dev/null || {
	echo "boot the phone into BusyBox first (scripts/phone-boot.sh out/boot-rev-10.img)"; exit 1; }
mkdir -p "$OUT"
rm -f "$IMG" "$IMG.zst"
# (no fsck yet: the phone replays the journal of a disk that was not unmounted)
cp --sparse=always "$SRC" "$IMG"

# one client, gone when it disconnects; discard so fstrim punches holes
qemu-nbd -f raw -x release -b 172.16.42.2 -p 10810 --discard=unmap --cache=writeback "$IMG" &
Q=$!
trap 'kill $Q 2>/dev/null || true' EXIT
sleep 2

# runs on the phone (BusyBox) with the copy mounted on $1
cat > "$OUT/clean.sh" <<'EOF'
R=$1
rm -f $R/root/.ssh/authorized_keys $R/etc/ssh/ssh_host_*
printf "[Service]\nExecStartPre=\nExecStartPre=/usr/bin/ssh-keygen -A\nExecStartPre=/usr/sbin/sshd -t\n" > $R/etc/systemd/system/ssh.service.d/hostkeys.conf
rm -f $R/etc/nexus5x-vnc-password $R/home/nexus/.config/tigervnc/passwd
rm -f $R/home/nexus/.config/tigervnc/*.log $R/home/nexus/.config/tigervnc/*.pid
rm -rf $R/etc/NetworkManager/system-connections/* $R/var/lib/NetworkManager/*
rm -f $R/etc/wpa_supplicant/*.conf
rm -f $R/usr/lib/firmware/ath10k/QCA6174/hw3.0/board.bin
: > $R/etc/machine-id
rm -f $R/var/lib/dbus/machine-id $R/var/lib/systemd/random-seed
rm -rf $R/var/lib/apt/lists/* $R/var/cache/apt/*.bin $R/var/cache/apt/archives/*.deb
rm -rf $R/var/log/journal/* $R/tmp/* $R/var/tmp/*
find $R/var/log -type f | while read -r f; do : > "$f"; done
rm -rf $R/root/.bash_history $R/home/nexus/.bash_history $R/home/nexus/.Xauthority
# Lomiri's display config (output scale 1) is the one thing in ~/.cache to keep
N=$R/home/nexus
mv $N/.cache/lomiri/00.edid $R/tmp/00.edid
rm -rf $N/.cache
mkdir -p $N/.cache/lomiri
mv $R/tmp/00.edid $N/.cache/lomiri/00.edid
chown -R 1000:1000 $N/.cache
rm -rf $R/root/* $R/root/.cache $R/root/.config $R/opt/mesa-a418.nonglvnd
rm -rf $N/.presage $N/.gnupg $N/.ssh $N/.ICEauthority $N/.dbus $N/Pictures/Screenshots
rm -rf $N/.local/share/morph-browser $N/.local/share/history-service $N/.local/share/lomiri-history-service
rm -rf $N/.local/share/telepathy $N/.local/share/gallery.ubports
rm -rf $N/.config/morph-browser $N/.config/connectivity-service $N/.config/pulse $N/.config/libaccounts-glib
rm -rf $R/var/lib/bluetooth/*
# Lomiri on the panel at boot, in place of the VNC desktop and tty1's shell
S=$R/etc/systemd/system
rm -f $S/multi-user.target.wants/xfce-vnc.service $S/multi-user.target.wants/novnc.service
rm -f $S/getty.target.wants/getty@tty1.service
ln -sf /etc/systemd/system/lomiri-phone.service $S/graphical.target.wants/lomiri-phone.service
# no Wi-Fi password may be left anywhere
if grep -rlE '(^|[^a-z_])psk=' $R/etc $R/var/lib $R/root $R/home 2>/dev/null; then
	echo "a Wi-Fi key is still on the disk"; exit 1
fi
sync
fstrim -v $R
echo CLEAN_OK
EOF
timeout 20 nc -l -N 9007 < "$OUT/clean.sh" &
tel 'nc 172.16.42.2 9007 > /tmp/clean.sh' 3 >/dev/null
wait $! || true
# detached from the telnet session: deleting and trimming over NBD takes minutes
tel 'rm -f /tmp/clean.log; setsid sh -c "nbd-client -N release 172.16.42.2 10810 /dev/nbd1; sleep 3; mkdir -p /mnt/rel; mount -t ext4 -o noatime /dev/nbd1 /mnt/rel && sh /tmp/clean.sh /mnt/rel; umount /mnt/rel; nbd-client -d /dev/nbd1; echo CLEAN_DONE" > /tmp/clean.log 2>&1 < /dev/null &' >/dev/null
RES=
for i in $(seq 1 120); do
	sleep 10
	RES=$(tel 'cat /tmp/clean.log')
	grep -aq '^CLEAN_DONE' <<<"$RES" && break
done
echo "$RES" | grep -aE 'trimmed|still|CLEAN_OK' || true
grep -aqx CLEAN_OK <<<"$RES" || { echo "cleaning failed"; echo "$RES" | tail -5; exit 1; }
wait $Q 2>/dev/null || true
trap - EXIT
rm -f "$OUT/clean.sh"

e2fsck -fp "$IMG"
echo "disk: $(du -h "$IMG" | cut -f1) used of $(du -h --apparent-size "$IMG" | cut -f1); compressing"
zstd -q -T0 -19 "$IMG" -o "$IMG.zst"
rm -f "$IMG"
(cd "$OUT" && sha256sum "$(basename "$IMG.zst")" | tee "$(basename "$IMG.zst").sha256")
ls -la "$IMG.zst"
