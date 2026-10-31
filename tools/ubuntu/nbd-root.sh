#!/bin/bash
# nbd-root.sh [IMG]: serve the phone's Ubuntu disk (a sparse ext4 image file on
# this PC, out/ubuntu-nbd/ubuntu.img by default, made on first use) over the
# USB network with qemu-nbd: export "ubuntu", 172.16.42.2:10809. Only the USB
# address listens; nothing is reachable from the LAN. No root needed.
#
# The phone takes it as /dev/nbd0: rootfs/usr/share/learn/ubuntu-nbd.sh (boot
# with ubuntu=nbd), or tools/ubuntu/nbd-install.sh to fill it. Keep this
# running while Ubuntu runs on the phone: it is the phone's root disk.
set -euo pipefail
TOP=$(cd "$(dirname "$0")/../.." && pwd)
IMG=${1:-$TOP/out/ubuntu-nbd/ubuntu.img}
SIZE=${UBUNTU_DISK:-8G}

if [ ! -f "$IMG" ]; then
	mkdir -p "$(dirname "$IMG")"
	truncate -s "$SIZE" "$IMG"
	mkfs.ext4 -q -L ubuntu "$IMG"
	echo "made $IMG ($SIZE, sparse)"
fi
# The PC's USB address comes and goes with the phone (reboots): serve while it
# is there, and stop when it goes. A rebooted phone never closes its old
# connection, and qemu-nbd serves one client at a time, so the new boot would
# wait forever behind the dead one.
up() { ip -4 addr show | grep -q 'inet 172\.16\.42\.2/'; }
while true; do
	until up; do sleep 1; done
	echo "serving $IMG on 172.16.42.2:10809 (export ubuntu)"
	qemu-nbd -f raw -x ubuntu -b 172.16.42.2 -p 10809 -t --cache=writeback "$IMG" &
	Q=$!
	while up && kill -0 $Q 2>/dev/null; do sleep 1; done
	kill $Q 2>/dev/null && echo "USB link gone: stopped serving"
	wait $Q 2>/dev/null || true
done
