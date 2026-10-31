#!/bin/sh
# desktop-open.sh: open the phone's XFCE desktop (tools/ubuntu/desktop-setup.sh)
# in this PC's browser, through noVNC on the USB network. F11: fullscreen.
TOP=$(cd "$(dirname "$0")/../.." && pwd)
PW=$(cat "$TOP/out/ssh/vnc-password") || exit 1
exec xdg-open "http://172.16.42.1:6080/vnc.html?autoconnect=1&resize=remote&reconnect=1&password=$PW"
