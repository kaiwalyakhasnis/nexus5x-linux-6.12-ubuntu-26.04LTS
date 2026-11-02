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
size = w * h * 3

ff = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo",
    "-pix_fmt", "rgb24", "-s", f"{w}x{h}", "-r", str(fps), "-i", "-", "-vf",
    f"scale={width}:-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=full[p];"
    "[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle", dst],
    stdin=subprocess.PIPE)

tick = 1000 / fps
frame, emitted = None, 0
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
            ff.stdin.write(frame)
            emitted += 1
    frame = next_frame
for _ in range(fps):		# hold the last frame for a second
    ff.stdin.write(frame)
ff.stdin.close()
ff.wait()
print(f"{emitted + fps} frames at {fps} fps, {w}x{h} -> width {width}")
