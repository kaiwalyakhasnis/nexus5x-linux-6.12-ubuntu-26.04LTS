#!/bin/bash
# ubuntu-on-phone.sh: unpack Ubuntu Base (arm64) into RAM on the phone, start
# the proxy apt uses, set the phone's clock (no RTC driver yet: apt rejects
# "future" Release files otherwise), and install an SSH server with this
# project's key (out/ssh). Nothing is written to the phone's storage; a
# reboot removes it. Then: tools/ubuntu/ssh-phone.sh (or "... screen"), or
# on the phone: ubuntu-chroot.
set -euo pipefail
TOP=$(cd "$(dirname "$0")/../.." && pwd)
TAR=${1:-$TOP/downloads/ubuntu/ubuntu-base-26.04.1-base-arm64.tar.gz}
PHONE=172.16.42.1
SIZE=${UBUNTU_RAM:-1200m}

ping -c1 -W2 $PHONE >/dev/null || { echo "phone not reachable on $PHONE"; exit 1; }
if ! pgrep -f 'usb-proxy\.py' >/dev/null; then
	nohup python3 "$TOP/tools/ubuntu/usb-proxy.py" > "$TOP/out/usb-proxy.log" 2>&1 &
	echo "proxy started (log: out/usb-proxy.log)"
fi

# the phone unpacks as it receives
(sleep 1; echo "pkill -f 'nc -l -p 9004'; mountpoint -q /ubuntu || { mkdir -p /ubuntu && mount -t tmpfs -o size=$SIZE tmpfs /ubuntu; }; nc -l -p 9004 | tar xzf - -C /ubuntu && echo UNPACKED &"; sleep 1) \
	| timeout 5 nc $PHONE 23 >/dev/null 2>&1 || true
sleep 1
echo "sending $(basename "$TAR") ($(du -h "$TAR" | cut -f1))"
nc -q 2 $PHONE 9004 < "$TAR"
sleep 3
(sleep 1; echo 'ls /ubuntu; df -h /ubuntu | tail -1; cat /ubuntu/etc/lsb-release'; sleep 2) \
	| timeout 5 nc $PHONE 23 2>/dev/null | tr -d '\r' | grep -aE 'DISTRIB|tmpfs|^bin|usr' || true

echo "setting the phone's clock from this PC"
(sleep 1; echo "date -u -s @$(date +%s) >/dev/null"; sleep 1) | timeout 4 nc $PHONE 23 >/dev/null 2>&1 || true

K=$TOP/out/ssh
mkdir -p "$K"
[ -f "$K/id_ed25519" ] || ssh-keygen -q -t ed25519 -N '' -C bullhead-ubuntu -f "$K/id_ed25519"
rm -f "$K/known_hosts"	# a fresh Ubuntu has fresh host keys
PUB=$(cat "$K/id_ed25519.pub")
echo "installing openssh-server in Ubuntu (apt through the proxy)"
OUT=$( (sleep 1; echo "ubuntu-chroot /bin/bash -c 'DEBIAN_FRONTEND=noninteractive apt-get update -q >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends openssh-server >/dev/null; mkdir -p /root/.ssh /run/sshd; chmod 700 /root/.ssh; echo \"$PUB\" > /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys; ssh-keygen -A >/dev/null; /usr/sbin/sshd && echo SSHD_UP'"; sleep 240) \
	| timeout 245 nc $PHONE 23 2>/dev/null | tr -d '\r' || true)
# the telnet session ends by timeout; the marker alone on a line is the result
grep -aqx SSHD_UP <<<"$OUT" || { echo "SSH setup failed"; exit 1; }
"$TOP/tools/ubuntu/ssh-phone.sh" 'grep PRETTY /etc/os-release'
