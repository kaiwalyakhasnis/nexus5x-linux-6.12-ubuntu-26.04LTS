#!/bin/bash
# desktop-setup.sh: the XFCE desktop on the phone's Ubuntu (NBD disk, booted
# with ubuntu=nbd), shown on this PC. Run once, after
#   apt-get install --no-install-recommends xfce4 xfce4-terminal \
#       tigervnc-standalone-server dbus-x11
# on the phone.
#
# - user "nexus" runs the session (some apps refuse root)
# - xfce-vnc.service: TigerVNC display :1, 1920x1080, listening only on the USB
#   address 172.16.42.1:5901, with a random VNC password kept on this PC in
#   out/ssh/vnc-password
# - novnc.service: noVNC (a VNC viewer in the browser) on 172.16.42.1:6080,
#   from the upstream release tarballs (Ubuntu's novnc pulls in Node.js)
#
# Then tools/ubuntu/desktop-open.sh opens it in the browser (F11 for
# fullscreen); the desktop follows the browser window's size.
set -euo pipefail
TOP=$(cd "$(dirname "$0")/../.." && pwd)
D=$TOP/downloads/novnc
SSH="$TOP/tools/ubuntu/ssh-phone.sh"
mkdir -p "$D"
[ -f "$D/noVNC-1.5.0.tar.gz" ] || curl -fL -o "$D/noVNC-1.5.0.tar.gz" https://github.com/novnc/noVNC/archive/refs/tags/v1.5.0.tar.gz
[ -f "$D/websockify-0.12.0.tar.gz" ] || curl -fL -o "$D/websockify-0.12.0.tar.gz" https://github.com/novnc/websockify/archive/refs/tags/v0.12.0.tar.gz
(cd "$D" && sha256sum -c) <<'SUMS'
6a73e41f98388a5348b7902f54b02d177cb73b7e5eb0a7a0dcf688cc2c79b42a  noVNC-1.5.0.tar.gz
37448ec992ef626f29558404cf6535592d02894ec1d5f0990a8c62621b39a967  websockify-0.12.0.tar.gz
SUMS

PWF=$TOP/out/ssh/vnc-password
mkdir -p "$(dirname "$PWF")"
# VNC passwords are at most 8 characters
[ -f "$PWF" ] || { tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8 > "$PWF"; chmod 600 "$PWF"; }

for t in noVNC-1.5.0 websockify-0.12.0; do
	"$SSH" "rm -rf /opt/$t && tar xzf - -C /opt" < "$D/$t.tar.gz"
done
"$SSH" 'umask 077; cat > /tmp/vnc-password' < "$PWF"

"$SSH" 'set -e
ln -sfn /opt/noVNC-1.5.0 /opt/novnc
ln -sfn /opt/websockify-0.12.0 /opt/websockify
# Python 3.14 starts child processes with "forkserver" by default; websockify
# 0.12 handlers then never answer (the browser shows "Failed to connect")
cat > /opt/websockify-fork.py <<"EOF"
import multiprocessing, runpy, sys
multiprocessing.set_start_method("fork")
sys.path.insert(0, "/opt/websockify")
sys.argv[0] = "websockify"
runpy.run_module("websockify", run_name="__main__")
EOF
# the start page connects straight away (asking for the VNC password) and
# resizes the desktop to the window
cat > /opt/novnc/index.html <<"EOF"
<!doctype html><meta charset="utf-8"><title>Nexus 5X desktop</title>
<meta http-equiv="refresh" content="0; url=vnc.html?autoconnect=1&amp;resize=remote&amp;reconnect=1">
EOF
export LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive
# Wi-Fi with NetworkManager (nmtui). usb0 is the root disk'"'"'s link: never touch
# it. Written before the install, which starts NetworkManager.
mkdir -p /etc/NetworkManager/conf.d
printf "[keyfile]\nunmanaged-devices=interface-name:usb0\n" > /etc/NetworkManager/conf.d/10-usb0.conf
apt-get install -y -q --no-install-recommends tigervnc-tools sudo network-manager fastfetch >/dev/null
id nexus >/dev/null 2>&1 || useradd -m -s /bin/bash nexus
# a single-user dev board: the desktop user is admin without a password
echo "nexus ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/nexus
chmod 440 /etc/sudoers.d/nexus

# SSH host keys are made on the first boot (a released disk has none), before
# the stock unit's sshd -t, which fails without them
mkdir -p /etc/systemd/system/ssh.service.d
printf "[Service]\nExecStartPre=\nExecStartPre=/usr/bin/ssh-keygen -A\nExecStartPre=/usr/sbin/sshd -t\n" > /etc/systemd/system/ssh.service.d/hostkeys.conf

# The VNC password: kept in /etc/nexus5x-vnc-password (root only) and shown on
# the panel (tty1). A released disk has none; the first boot makes a random one.
cat > /usr/local/sbin/nexus5x-vnc-password <<"EOF"
#!/bin/sh
V=/home/nexus/.config/tigervnc
P=/etc/nexus5x-vnc-password
[ -s $V/passwd ] && [ -s $P ] && exit 0
[ -s $P ] || { umask 077; tr -dc A-Za-z0-9 < /dev/urandom | head -c 8 > $P; }
install -d -o nexus -g nexus -m 700 /home/nexus/.config $V
vncpasswd -f < $P > $V/passwd
chown nexus:nexus $V/passwd
chmod 600 $V/passwd
EOF
chmod 755 /usr/local/sbin/nexus5x-vnc-password
cat > /etc/systemd/system/vnc-password.service <<"EOF"
[Unit]
Description=VNC password for the desktop (made on the first boot)
# before the panel'"'"'s login too, which shows it
Before=xfce-vnc.service getty@tty1.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/nexus5x-vnc-password

[Install]
WantedBy=multi-user.target
EOF
cat > /etc/profile.d/nexus5x-desktop.sh <<"EOF"
# On the panel (tty1, root): how to reach the desktop from the PC
if [ "$(tty)" = /dev/tty1 ] && [ "$(id -u)" = 0 ] && [ -s /etc/nexus5x-vnc-password ]; then
	echo
	echo "  Desktop: on the PC open  http://172.16.42.1:6080"
	echo "  VNC password:            $(cat /etc/nexus5x-vnc-password)"
	echo
fi
EOF

# TigerVNC 1.14 keeps its files in ~/.config/tigervnc (and fails trying to
# migrate an old ~/.vnc). This PC'"'"'s password replaces the generated one.
rm -rf /home/nexus/.vnc /home/nexus/.config/tigervnc/passwd
(umask 077; cp /tmp/vnc-password /etc/nexus5x-vnc-password)
rm -f /tmp/vnc-password
/usr/local/sbin/nexus5x-vnc-password

cat > /etc/systemd/system/xfce-vnc.service <<"EOF"
[Unit]
Description=XFCE desktop on VNC display :1 (USB network only)
After=network.target

[Service]
User=nexus
Environment=HOME=/home/nexus
ExecStart=/usr/bin/tigervncserver :1 -fg -localhost no -interface 172.16.42.1 \
	-geometry 1920x1080 -depth 24 -SecurityTypes VncAuth \
	-PasswordFile /home/nexus/.config/tigervnc/passwd -xstartup /usr/bin/startxfce4
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/novnc.service <<"EOF"
[Unit]
Description=noVNC: the VNC desktop in a browser, http://172.16.42.1:6080
After=xfce-vnc.service

[Service]
User=nexus
ExecStart=/usr/bin/python3 /opt/websockify-fork.py --web /opt/novnc 172.16.42.1:6080 127.0.0.1:5901
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable vnc-password.service xfce-vnc.service novnc.service
# (re)start, so a rerun takes the new units
systemctl restart xfce-vnc.service novnc.service
sleep 8
systemctl --no-pager --lines=0 status xfce-vnc.service novnc.service | grep -E "service -|Active:"
echo DESKTOP_SETUP_OK' </dev/null | grep -v '^Pseudo' | tee /dev/stderr | grep -aqx DESKTOP_SETUP_OK
echo "open it with tools/ubuntu/desktop-open.sh"
