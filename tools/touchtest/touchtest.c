// SPDX-License-Identifier: GPL-2.0
/*
 * touchtest [seconds]: draw what the touchscreen and a USB mouse report.
 *
 * Takes the framebuffer from the console (unbinds fbcon, rebinds it on exit)
 * and paints each finger's path in its own colour, logging touch
 * down/move/up to stdout. Three fingers at once clear the screen. A mouse
 * moves a pointer and paints while the left button is held; the right
 * button clears. On a keyboard, c clears and q or Esc quits. Input devices
 * are rescanned every 2 s, so a mouse plugged in later is picked up (the
 * phone has one USB port). Stops on Ctrl-C, SIGTERM, or after [seconds].
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
#define MAXDEV	16
#define CURSOR	11
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

enum kind { TOUCH, MOUSE, KEYS };

struct dev {
	int fd;
	enum kind kind;
	char path[32];
};

static struct dev devs[MAXDEV];
static int ndevs;

/* mouse pointer, and the pixels it covers */
static int mx, my, mbutton, cursor_shown;
static uint32_t under[CURSOR][CURSOR];

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

static void cursor_hide(void)
{
	if (!cursor_shown)
		return;
	for (int y = 0; y < CURSOR; y++)
		for (int x = 0; x < CURSOR; x++)
			put(mx + x, my + y, under[y][x]);
	cursor_shown = 0;
}

/* a white arrow-ish triangle with a dark edge */
static void cursor_show(void)
{
	for (int y = 0; y < CURSOR; y++)
		for (int x = 0; x < CURSOR; x++) {
			int px = mx + x, py = my + y;

			if (px < 0 || py < 0 || (unsigned)px >= fb_w || (unsigned)py >= fb_h)
				continue;
			under[y][x] = *(uint32_t *)(fb + py * fb_stride + px * 4);
			if (x <= y)
				put(px, py, x == 0 || x == y || y == CURSOR - 1 ?
				    0x202020 : 0xffffff);
		}
	cursor_shown = 1;
}

static int known(const char *path)
{
	for (int i = 0; i < ndevs; i++)
		if (!strcmp(devs[i].path, path))
			return 1;
	return 0;
}

/* open input devices not seen yet: touchscreens, mice, keyboards */
static void scan(void)
{
	unsigned long abs[(ABS_MAX + 1) / (8 * sizeof(long)) + 1];
	unsigned long rel[(REL_MAX + 1) / (8 * sizeof(long)) + 1];
	unsigned long key[(KEY_MAX + 1) / (8 * sizeof(long)) + 1];
	char path[32], name[128];
	enum kind kind;
	int fd;

	for (int i = 0; i < 32 && ndevs < MAXDEV; i++) {
		snprintf(path, sizeof(path), "/dev/input/event%d", i);
		if (known(path))
			continue;
		fd = open(path, O_RDONLY | O_NONBLOCK);
		if (fd < 0)
			continue;
		memset(abs, 0, sizeof(abs));
		memset(rel, 0, sizeof(rel));
		memset(key, 0, sizeof(key));
		ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(abs)), abs);
		ioctl(fd, EVIOCGBIT(EV_REL, sizeof(rel)), rel);
		ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(key)), key);

		if (TEST_BIT(ABS_MT_POSITION_X, abs) && TEST_BIT(ABS_MT_SLOT, abs)) {
			kind = TOUCH;
			ioctl(fd, EVIOCGABS(ABS_MT_POSITION_X), &ax);
			ioctl(fd, EVIOCGABS(ABS_MT_POSITION_Y), &ay);
		} else if (TEST_BIT(REL_X, rel) && TEST_BIT(REL_Y, rel)) {
			kind = MOUSE;
		} else if (TEST_BIT(KEY_Q, key) && TEST_BIT(KEY_C, key)) {
			kind = KEYS;
		} else {
			close(fd);
			continue;
		}
		name[0] = 0;
		ioctl(fd, EVIOCGNAME(sizeof(name)), name);
		printf("%s: %s (%s)\n", kind == TOUCH ? "touchscreen" :
		       kind == MOUSE ? "mouse" : "keyboard", path, name);
		devs[ndevs].fd = fd;
		devs[ndevs].kind = kind;
		snprintf(devs[ndevs].path, sizeof(devs[ndevs].path), "%s", path);
		ndevs++;
	}
}

static void drop(int i)
{
	printf("gone: %s\n", devs[i].path);
	close(devs[i].fd);
	devs[i] = devs[--ndevs];
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

static void touch_event(struct input_event *ev, struct slot *s, int *cur)
{
	int active = 0;

	if (ev->type == EV_ABS) {
		if (ev->code == ABS_MT_SLOT && ev->value >= 0 && ev->value < SLOTS)
			*cur = ev->value;
		else if (ev->code == ABS_MT_TRACKING_ID)
			s[*cur].id = ev->value;
		else if (ev->code == ABS_MT_POSITION_X)
			s[*cur].x = scale(ev->value, &ax, fb_w);
		else if (ev->code == ABS_MT_POSITION_Y)
			s[*cur].y = scale(ev->value, &ay, fb_h);
		return;
	}
	if (ev->type != EV_SYN || ev->code != SYN_REPORT)
		return;

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
}

static void mouse_event(struct input_event *ev)
{
	int ox = mx, oy = my;

	if (ev->type == EV_REL && ev->code == REL_X)
		mx += ev->value;
	else if (ev->type == EV_REL && ev->code == REL_Y)
		my += ev->value;
	else if (ev->type == EV_KEY && ev->code == BTN_LEFT) {
		mbutton = ev->value;
		printf("mouse %s at %4d,%4d\n", mbutton ? "down" : "up  ", mx, my);
		if (mbutton) {
			cursor_hide();
			dot(mx, my, colours[7]);
		}
	} else if (ev->type == EV_KEY && ev->code == BTN_RIGHT && ev->value) {
		printf("mouse right button: clear\n");
		cursor_hide();
		clear();
	}
	if (mx < 0)
		mx = 0;
	if (my < 0)
		my = 0;
	if ((unsigned)mx >= fb_w)
		mx = fb_w - 1;
	if ((unsigned)my >= fb_h)
		my = fb_h - 1;

	if (ev->type == EV_SYN) {
		cursor_hide();
		if (mbutton && (mx != ox || my != oy))
			stroke(ox, oy, mx, my, colours[7]);
		cursor_show();
	}
}

int main(int argc, char **argv)
{
	struct fb_var_screeninfo var;
	struct fb_fix_screeninfo fix;
	struct slot s[SLOTS];
	struct input_event ev;
	int cur = 0, quit = 0;
	time_t end = argc > 1 ? time(NULL) + atoi(argv[1]) : 0;
	time_t next_scan = 0;
	long events = 0;

	setvbuf(stdout, NULL, _IOLBF, 0);

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
	printf("framebuffer: %ux%u (%s)\n", fb_w, fb_h, fix.id);
	printf("touch: three fingers clear; mouse: left paints, right clears; "
	       "keys: c clears, q/Esc quits\n");

	scan();
	mx = fb_w / 2;
	my = fb_h / 2;
	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);
	vtcon("0");
	clear();
	flush();
	memset(s, 0, sizeof(s));
	for (int i = 0; i < SLOTS; i++)
		s[i].id = -1;

	while (!stop && !quit && (!end || time(NULL) < end)) {
		struct pollfd p[MAXDEV];

		if (time(NULL) >= next_scan) {
			scan();
			next_scan = time(NULL) + 2;
		}
		for (int i = 0; i < ndevs; i++) {
			p[i].fd = devs[i].fd;
			p[i].events = POLLIN;
			p[i].revents = 0;
		}
		if (poll(p, ndevs, 200) <= 0)
			continue;

		for (int i = ndevs - 1; i >= 0; i--) {
			if (p[i].revents & (POLLERR | POLLHUP | POLLNVAL)) {
				drop(i);
				continue;
			}
			if (!(p[i].revents & POLLIN))
				continue;
			while (read(devs[i].fd, &ev, sizeof(ev)) == sizeof(ev)) {
				events++;
				if (devs[i].kind == TOUCH) {
					touch_event(&ev, s, &cur);
				} else if (devs[i].kind == MOUSE) {
					mouse_event(&ev);
				} else if (ev.type == EV_KEY && ev.value == 1) {
					if (ev.code == KEY_C) {
						printf("key c: clear\n");
						cursor_hide();
						clear();
					} else if (ev.code == KEY_Q || ev.code == KEY_ESC) {
						quit = 1;
					}
				}
			}
		}
		flush();
	}

	printf("%ld input events\n", events);
	clear();
	flush();
	vtcon("1");
	return 0;
}
