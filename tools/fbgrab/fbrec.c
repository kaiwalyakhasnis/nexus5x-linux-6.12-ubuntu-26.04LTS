// fbrec OUT SECONDS [card]: record what the panel shows. Each new frame the
// compositor flips to goes to OUT as a u32 millisecond timestamp and half-size
// (nearest) RGB888 pixels; a still screen writes nothing, and a frame the
// compositor flipped away from during the read is dropped, since that buffer
// may already be half redrawn. Rows are copied whole first: the buffer is
// uncached, so word-by-word reads would take longer than a frame. Same limits as fbgrab:
// root, 32-bit XRGB/ARGB8888 linear buffers. Keep OUT in /dev/shm: the root disk
// is on the PC. tools/fbgrab/rec2gif.py turns the result into a GIF.
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <drm_fourcc.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

#define NMAPS 32

static struct { uint32_t id, w, h, pitch; size_t size; uint8_t *map; } maps[NMAPS];
static unsigned next_map;

static uint32_t now_ms(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

static uint32_t scanout_fb(int fd, drmModePlaneResPtr pr)
{
	uint32_t id = 0;
	for (uint32_t i = 0; i < pr->count_planes && !id; i++) {
		drmModePlanePtr p = drmModeGetPlane(fd, pr->planes[i]);
		if (p)
			id = p->fb_id;
		drmModeFreePlane(p);
	}
	return id;
}

static int find_map(int fd, uint32_t id)
{
	for (int i = 0; i < NMAPS; i++)
		if (maps[i].id == id)
			return i;
	drmModeFB2Ptr fb = drmModeGetFB2(fd, id);
	if (!fb || !fb->handles[0] || (fb->pixel_format != DRM_FORMAT_XRGB8888 &&
				       fb->pixel_format != DRM_FORMAT_ARGB8888)) {
		drmModeFreeFB2(fb);
		return -1;
	}
	int dmafd, n = next_map++ % NMAPS;
	if (drmPrimeHandleToFD(fd, fb->handles[0], DRM_CLOEXEC, &dmafd)) {
		drmModeFreeFB2(fb);
		return -1;
	}
	if (maps[n].map)
		munmap(maps[n].map, maps[n].size);
	maps[n].id = id;
	maps[n].w = fb->width;
	maps[n].h = fb->height;
	maps[n].pitch = fb->pitches[0];
	maps[n].size = (size_t)fb->pitches[0] * fb->height + fb->offsets[0];
	maps[n].map = mmap(NULL, maps[n].size, PROT_READ, MAP_SHARED, dmafd, 0);
	close(dmafd);
	drmCloseBufferHandle(fd, fb->handles[0]);
	drmModeFreeFB2(fb);
	if (maps[n].map == MAP_FAILED) {
		maps[n].map = NULL;
		maps[n].id = 0;
		return -1;
	}
	return n;
}

int main(int argc, char **argv)
{
	const char *card = argc > 3 ? argv[3] : "/dev/dri/card1";
	int fd = open(card, O_RDWR | O_CLOEXEC);
	if (fd < 0 || argc < 3) {
		fprintf(stderr, "usage: fbrec OUT SECONDS [card]\n");
		return 1;
	}
	drmSetClientCap(fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1);
	drmModePlaneResPtr pr = drmModeGetPlaneResources(fd);
	FILE *out = fopen(argv[1], "wb");
	if (!pr || !out) {
		perror("start");
		return 1;
	}
	uint32_t start = now_ms(), end = start + atoi(argv[2]) * 1000, last = 0, frames = 0, dropped = 0;
	uint32_t flips = 0, seen = 0, read_ms = 0;
	uint8_t *pix = NULL;
	uint32_t *copy = NULL;
	while (now_ms() < end) {
		uint32_t id = scanout_fb(fd, pr);
		if (id && id != seen) {
			seen = id;
			flips++;
		}
		if (!id || id == last) {
			usleep(1000);
			continue;
		}
		int n = find_map(fd, id);
		if (n < 0) {
			fprintf(stderr, "fb %u: no linear XRGB8888 buffer\n", id);
			return 1;
		}
		last = id;
		uint32_t t = now_ms() - start, w = maps[n].w / 2, h = maps[n].h / 2;
		if (!pix) {
			pix = malloc(w * h * 3);
			copy = malloc(maps[n].w * 4 * h);
		}
		uint32_t r0 = now_ms();
		for (uint32_t y = 0; y < h; y++)
			memcpy(copy + y * maps[n].w, maps[n].map + (size_t)y * 2 * maps[n].pitch, maps[n].w * 4);
		read_ms += now_ms() - r0;
		if (scanout_fb(fd, pr) != id) {
			dropped++;
			last = 0;
			continue;
		}
		if (!frames)
			fprintf(out, "FBREC %u %u\n", w, h);
		fwrite(&t, 4, 1, out);
		for (uint32_t i = 0; i < w * h; i++) {
			uint32_t p = copy[(i / w) * maps[n].w + (i % w) * 2];
			pix[i * 3] = p >> 16;
			pix[i * 3 + 1] = p >> 8;
			pix[i * 3 + 2] = p;
		}
		fwrite(pix, 3, w * h, out);
		frames++;
	}
	fclose(out);
	printf("%u frames, %u dropped, %u flips seen, in %u ms; %u ms per read\n", frames, dropped,
	       flips, now_ms() - start, frames + dropped ? read_ms / (frames + dropped) : 0);
	return 0;
}
