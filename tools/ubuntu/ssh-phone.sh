#!/bin/sh
# ssh-phone.sh [command...]: log in to Ubuntu on the phone over the USB
# network, with the project's own key (out/ssh, made by the setup; the PC's
# ~/.ssh is not used). "ssh-phone.sh screen" mirrors the phone's panel
# (tty1) instead: BusyBox's conspy, reached from Ubuntu through /proc/1/root.
TOP=$(cd "$(dirname "$0")/../.." && pwd)
K=$TOP/out/ssh
[ "$1" = screen ] && set -- /proc/1/root/bin/busybox conspy 1
exec ssh -t -i "$K/id_ed25519" -o UserKnownHostsFile="$K/known_hosts" \
	-o StrictHostKeyChecking=accept-new root@172.16.42.1 "$@"
