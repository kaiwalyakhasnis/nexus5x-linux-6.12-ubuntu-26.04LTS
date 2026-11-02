#!/usr/bin/env python3
"""touch.py tap X Y | swipe X1 Y1 X2 Y2 [MS] | range: fake a finger on the real
touchscreen, by writing events to its evdev node (panel pixels). Root."""
import fcntl, struct, sys, time

DEV = "/dev/input/event2"
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
BTN_TOUCH = 0x14a
ABS_X, ABS_Y = 0, 1
MT_SLOT, MT_X, MT_Y, MT_ID = 0x2f, 0x35, 0x36, 0x39

dev = open(DEV, "r+b", buffering=0)

def absinfo(code):
    buf = bytearray(24)
    fcntl.ioctl(dev, 0x80184540 + code, buf)
    return struct.unpack("6i", buf)

def emit(*events):
    data = b"".join(struct.pack("qqHHi", 0, 0, *e) for e in events)
    dev.write(data + struct.pack("qqHHi", 0, 0, EV_SYN, 0, 0))

def down(x, y):
    emit((EV_ABS, MT_SLOT, 0), (EV_ABS, MT_ID, int(time.time()) & 0xffff),
         (EV_ABS, MT_X, x), (EV_ABS, MT_Y, y),
         (EV_KEY, BTN_TOUCH, 1), (EV_ABS, ABS_X, x), (EV_ABS, ABS_Y, y))

def move(x, y):
    emit((EV_ABS, MT_X, x), (EV_ABS, MT_Y, y), (EV_ABS, ABS_X, x), (EV_ABS, ABS_Y, y))

def up():
    emit((EV_ABS, MT_ID, -1), (EV_KEY, BTN_TOUCH, 0))

cmd, args = sys.argv[1], [int(a) for a in sys.argv[2:]]
if cmd == "range":
    print("x", absinfo(MT_X)[1:3], "y", absinfo(MT_Y)[1:3])
elif cmd == "tap":
    x, y = args
    down(x, y)
    time.sleep(0.08)
    up()
elif cmd == "swipe":
    x1, y1, x2, y2 = args[:4]
    ms = args[4] if len(args) > 4 else 400
    steps = max(ms // 16, 2)
    down(x1, y1)
    for i in range(1, steps + 1):
        time.sleep(ms / steps / 1000)
        move(x1 + (x2 - x1) * i // steps, y1 + (y2 - y1) * i // steps)
    time.sleep(0.05)
    up()
