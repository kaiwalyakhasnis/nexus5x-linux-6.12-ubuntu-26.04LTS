// SPDX-License-Identifier: GPL-2.0
/*
 * touchtest [seconds]: draw what the touchscreen reports.
 *
 * Finds the multitouch input device, takes the framebuffer from the console
 * (unbinds fbcon, rebinds it on exit) and paints each finger's path in its
 * own colour, logging touch down/move/up to stdout. Three fingers at once
 * clear the screen. Stops on Ctrl-C, SIGTERM, or after [seconds].
 *
 * The Nexus 5X panel is a command-mode one: it only shows what the display
 * driver sends it, and drawing into the mmap'd framebuffer does not tell the
 * msm driver anything changed. So the changed rows are written back through
 * write() (fbdev's damage tracking), which makes it send them.
 */
#include <dirent.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define SLOTS	10
#define RADIUS	9
#define VTCON	"/sys/class/vtconsole/vtcon1/bind"

#define TEST_BIT(b, a) ((a)[(b) / (8 * sizeof(long))] >> ((b) % (8 * sizeof(long))) & 1)

static volatile sig_atomic_t stop;
static uint8_t *fb;
static int fbfd;
static unsigned int fb_w, fb_h, fb_stride;
static int dirty_top = -1, dirty_bottom;
static struct input_absinfo ax, ay;

static const uint32_t colours[SLOTS] = {
	0xff4040, 0x40ff40, 0x4080ff, 0xffff40, 0xff40ff,
	0x40ffff, 0xffa040, 0xffffff, 0xa060ff, 0x80ff80,
};

struct slot {
	int id, x, y, px, py, down;
};

static void on_signal(int sig)
{
	(void)sig;
	stop = 1;
}

static void put(int x, int y, uint32_t c)
{
	if (x >= 0 && y >= 0 && (unsigned)x < fb_w && (unsigned)y < fb_h) {
		*(uint32_t *)(fb + y * fb_stride + x * 4) = c;
		if (dirty_top < 0 || y < dirty_top)
			dirty_top = y;
		if (y > dirty_bottom)
			dirty_bottom = y;
	}
}

/* write the changed rows back, so the driver sends them to the panel */
static void flush(void)
{
	if (dirty_top < 0)
		return;
	if (pwrite(fbfd, fb + dirty_top * fb_stride,
		   (dirty_bottom - dirty_top + 1) * fb_stride,
		   (off_t)dirty_top * fb_stride) < 0)
		perror("fb write");
	dirty_top = -1;
	dirty_bottom = 0;
}

static void dot(int cx, int cy, uint32_t c)
{
	for (int y = -RADIUS; y <= RADIUS; y++)
		for (int x = -RADIUS; x <= RADIUS; x++)
			if (x * x + y * y <= RADIUS * RADIUS)
				put(cx + x, cy + y, c);
}

/* join the last point to this one, so fast strokes stay continuous */
static void stroke(int x0, int y0, int x1, int y1, uint32_t c)
{
	int dx = abs(x1 - x0), dy = abs(y1 - y0);
	int n = (dx > dy ? dx : dy) / (RADIUS / 2) + 1;

	for (int i = 0; i <= n; i++)
		dot(x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n, c);
}

static void clear(void)
{
	memset(fb, 0, fb_stride * fb_h);
	dirty_top = 0;
	dirty_bottom = fb_h - 1;
	/* frame, so it is clear the screen is ours */
	for (unsigned int i = 0; i < fb_w; i++) {
		put(i, 0, 0x808080);
		put(i, fb_h - 1, 0x808080);
	}
	for (unsigned int i = 0; i < fb_h; i++) {
		put(0, i, 0x808080);
		put(fb_w - 1, i, 0x808080);
	}
}

static int scale(int v, const struct input_absinfo *a, unsigned int size)
{
	if (a->maximum <= a->minimum)
		return v;
	return (long long)(v - a->minimum) * (size - 1) / (a->maximum - a->minimum);
}

static int open_touchscreen(char *name, size_t len)
{
	unsigned long abs[(ABS_MAX + 1) / (8 * sizeof(long)) + 1];
	char path[64];
	int fd;

	for (int i = 0; i < 32; i++) {
		snprintf(path, sizeof(path), "/dev/input/event%d", i);
		fd = open(path, O_RDONLY);
		if (fd < 0)
			continue;
		memset(abs, 0, sizeof(abs));
		if (ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(abs)), abs) >= 0 &&
		    TEST_BIT(ABS_MT_POSITION_X, abs) && TEST_BIT(ABS_MT_SLOT, abs)) {
			ioctl(fd, EVIOCGNAME(len), name);
			printf("touchscreen: %s (%s)\n", path, name);
			return fd;
		}
		close(fd);
	}
	return -1;
}

static void vtcon(const char *v)
{
	int fd = open(VTCON, O_WRONLY);

	if (fd >= 0) {
		if (write(fd, v, 1) < 0)
			perror(VTCON);
		close(fd);
	}
}

int main(int argc, char **argv)
{
	struct fb_var_screeninfo var;
	struct fb_fix_screeninfo fix;
	struct slot s[SLOTS];
	struct input_event ev;
	char name[128] = "";
	int cur = 0, fd, active = 0;
	time_t end = argc > 1 ? time(NULL) + atoi(argv[1]) : 0;
	long events = 0;

	setvbuf(stdout, NULL, _IOLBF, 0);
	fd = open_touchscreen(name, sizeof(name));
	if (fd < 0) {
		fprintf(stderr, "no multitouch input device\n");
		return 1;
	}
	ioctl(fd, EVIOCGABS(ABS_MT_POSITION_X), &ax);
	ioctl(fd, EVIOCGABS(ABS_MT_POSITION_Y), &ay);
	printf("x %d..%d, y %d..%d\n", ax.minimum, ax.maximum, ay.minimum, ay.maximum);

	fbfd = open("/dev/fb0", O_RDWR);
	if (fbfd < 0 || ioctl(fbfd, FBIOGET_VSCREENINFO, &var) ||
	    ioctl(fbfd, FBIOGET_FSCREENINFO, &fix) || var.bits_per_pixel != 32) {
		fprintf(stderr, "need a 32 bpp /dev/fb0\n");
		return 1;
	}
	fb_w = var.xres;
	fb_h = var.yres;
	fb_stride = fix.line_length;
	fb = mmap(NULL, fb_stride * fb_h, PROT_READ | PROT_WRITE, MAP_SHARED, fbfd, 0);
	if (fb == MAP_FAILED) {
		perror("mmap");
		return 1;
	}
	printf("framebuffer: %ux%u (%s); three fingers clear, Ctrl-C quits\n",
	       fb_w, fb_h, fix.id);

	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);
	vtcon("0");
	clear();
	flush();
	memset(s, 0, sizeof(s));
	for (int i = 0; i < SLOTS; i++)
		s[i].id = -1;

	while (!stop && (!end || time(NULL) < end)) {
		struct pollfd p = { .fd = fd, .events = POLLIN };

		if (poll(&p, 1, 200) <= 0)
			continue;
		if (read(fd, &ev, sizeof(ev)) != sizeof(ev))
			break;
		events++;

		if (ev.type == EV_ABS) {
			if (ev.code == ABS_MT_SLOT && ev.value >= 0 && ev.value < SLOTS)
				cur = ev.value;
			else if (ev.code == ABS_MT_TRACKING_ID)
				s[cur].id = ev.value;
			else if (ev.code == ABS_MT_POSITION_X)
				s[cur].x = scale(ev.value, &ax, fb_w);
			else if (ev.code == ABS_MT_POSITION_Y)
				s[cur].y = scale(ev.value, &ay, fb_h);
			continue;
		}
		if (ev.type != EV_SYN || ev.code != SYN_REPORT)
			continue;

		active = 0;
		for (int i = 0; i < SLOTS; i++) {
			struct slot *t = &s[i];

			if (t->id >= 0) {
				active++;
				if (!t->down) {
					printf("down  finger %d at %4d,%4d\n", i, t->x, t->y);
					dot(t->x, t->y, colours[i]);
				} else if (t->x != t->px || t->y != t->py) {
					printf("move  finger %d to %4d,%4d\n", i, t->x, t->y);
					stroke(t->px, t->py, t->x, t->y, colours[i]);
				}
				t->down = 1;
				t->px = t->x;
				t->py = t->y;
			} else if (t->down) {
				printf("up    finger %d at %4d,%4d\n", i, t->px, t->py);
				t->down = 0;
			}
		}
		if (active >= 3) {
			printf("three fingers: clear\n");
			clear();
		}
		flush();
	}

	printf("%ld input events\n", events);
	clear();
	flush();
	vtcon("1");
	return 0;
}
