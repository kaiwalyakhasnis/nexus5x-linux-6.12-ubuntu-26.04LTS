#!/bin/sh
# Login shell on QEMU's serial port (PL011). The phone has no ttyAMA0, and
# init would print "can't open /dev/ttyAMA0" on the panel at every respawn,
# so idle there instead. init already made this a session leader, so opening
# the tty makes it the controlling terminal.
[ -c /dev/ttyAMA0 ] || exec sleep 2147483647
exec /bin/sh -l <>/dev/ttyAMA0 >&0 2>&1
