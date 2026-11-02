#!/usr/bin/env python3
"""rec2gif.py IN.rec OUT.gif [WIDTH] [FPS]: fbrec's recording to a real-time GIF
(each frame stays up until the next one was flipped). Needs ffmpeg."""
import struct, subprocess, sys

src, dst = sys.argv[1:3]
width = int(sys.argv[3]) if len(sys.argv) > 3 else 360
fps = int(sys.argv[4]) if len(sys.argv) > 4 else 12

f = open(src, "rb")
magic, w, h = f.readline().split()
w, h = int(w), int(h)
size = w * h * 2

def rgb(frame):
    out = bytearray(w * h * 3)
    for i, (p,) in enumerate(struct.iter_unpack("<H", frame)):
        out[i * 3] = (p >> 8 & 0xf8) | p >> 13
        out[i * 3 + 1] = (p >> 3 & 0xfc) | (p >> 9 & 3)
        out[i * 3 + 2] = (p << 3 & 0xf8) | (p >> 2 & 7)
    return bytes(out)

ff = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo",
    "-pix_fmt", "rgb24", "-s", f"{w}x{h}", "-r", str(fps), "-i", "-", "-vf",
    f"scale={width}:-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];"
    "[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle", dst],
    stdin=subprocess.PIPE)

tick = 1000 / fps
frame, t, emitted, cached = None, None, 0, None
while True:
    head = f.read(4)
    if len(head) < 4:
        break
    next_t = struct.unpack("<I", head)[0]
    next_frame = f.read(size)
    if len(next_frame) < size:
        break
    if frame is not None:
        while emitted * tick < next_t:
            if cached is None:
                cached = rgb(frame)
            ff.stdin.write(cached)
            emitted += 1
    frame, cached = next_frame, None
for _ in range(fps):		# hold the last frame for a second
    ff.stdin.write(cached or rgb(frame))
ff.stdin.close()
ff.wait()
print(f"{emitted + fps} frames at {fps} fps, {w}x{h} -> width {width}")
