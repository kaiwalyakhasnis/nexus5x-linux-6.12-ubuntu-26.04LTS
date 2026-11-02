// fbrec OUT SECONDS [card]: record what the panel shows. Each new frame the
// compositor flips to goes to OUT as a u32 millisecond timestamp and third-size
// RGB888 pixels (every third row, columns averaged); a still screen writes nothing, and a frame the
// compositor flipped away from during the read is dropped, since that buffer
// may already be half redrawn. Rows are copied whole first: the buffer is
// uncached, so word-by-word reads would take longer than a frame. A second thread
// converts and writes, so the first is back in time for the next flip. Same limits as fbgrab:
// root, 32-bit XRGB/ARGB8888 linear buffers. Keep OUT in /dev/shm: the root disk
// is on the PC. tools/fbgrab/rec2gif.py turns the result into a GIF.
#include <fcntl.h>
#include <pthread.h>
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
#define NSLOTS 16
#define STEP 3

static struct { uint32_t id, w, h, pitch; size_t size; uint8_t *map; } maps[NMAPS];
static unsigned next_map;

static struct { uint32_t t; uint32_t *copy; } slots[NSLOTS];
static unsigned slot_in, slot_out;
static int done;
static uint32_t rec_w, rec_h, rec_stride, written;
static FILE *out;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t wake = PTHREAD_COND_INITIALIZER;

static void *writer(void *arg)
{
	uint8_t *pix = NULL;
	for (;;) {
		pthread_mutex_lock(&lock);
		while (slot_out == slot_in && !done)
			pthread_cond_wait(&wake, &lock);
		if (slot_out == slot_in) {
			pthread_mutex_unlock(&lock);
			break;
		}
		unsigned n = slot_out % NSLOTS;
		pthread_mutex_unlock(&lock);
		uint32_t w = rec_w, h = rec_h;
		if (!pix)
			pix = malloc(w * h * 3);
		for (uint32_t y = 0, i = 0; y < h; y++) {
			const uint32_t *row = slots[n].copy + y * rec_stride;
			for (uint32_t x = 0; x < w; x++, i++) {
				uint32_t r = 0, g = 0, b = 0;
				for (uint32_t k = 0; k < STEP; k++) {
					uint32_t p = row[x * STEP + k];
					r += p >> 16 & 0xff;
					g += p >> 8 & 0xff;
					b += p & 0xff;
				}
				pix[i * 3] = r / STEP;
				pix[i * 3 + 1] = g / STEP;
				pix[i * 3 + 2] = b / STEP;
			}
		}
		if (!written)
			fprintf(out, "FBREC %u %u\n", w, h);
		fwrite(&slots[n].t, 4, 1, out);
		fwrite(pix, 3, w * h, out);
		written++;
		pthread_mutex_lock(&lock);
		slot_out++;
		pthread_mutex_unlock(&lock);
	}
	return arg;
}

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
	out = fopen(argv[1], "wb");
	if (!pr || !out) {
		perror("start");
		return 1;
	}
	uint32_t start = now_ms(), end = start + atoi(argv[2]) * 1000, last = 0, dropped = 0, full = 0;
	uint32_t flips = 0, seen = 0, read_ms = 0, reads = 0;
	pthread_t thread;
	pthread_create(&thread, NULL, writer, NULL);
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
		pthread_mutex_lock(&lock);
		int room = slot_in - slot_out < NSLOTS;
		pthread_mutex_unlock(&lock);
		if (!room) {
			full++;
			continue;
		}
		rec_w = maps[n].w / STEP;
		rec_h = maps[n].h / STEP;
		rec_stride = maps[n].w;
		unsigned k = slot_in % NSLOTS;
		if (!slots[k].copy)
			slots[k].copy = malloc(maps[n].w * 4 * rec_h);
		slots[k].t = now_ms() - start;
		uint32_t r0 = now_ms();
		for (uint32_t y = 0; y < rec_h; y++)
			memcpy(slots[k].copy + y * rec_stride, maps[n].map + (size_t)y * STEP * maps[n].pitch, maps[n].w * 4);
		read_ms += now_ms() - r0;
		reads++;
		if (scanout_fb(fd, pr) != id) {
			dropped++;
			last = 0;
			continue;
		}
		pthread_mutex_lock(&lock);
		slot_in++;
		pthread_cond_signal(&wake);
		pthread_mutex_unlock(&lock);
	}
	pthread_mutex_lock(&lock);
	done = 1;
	pthread_cond_signal(&wake);
	pthread_mutex_unlock(&lock);
	pthread_join(thread, NULL);
	fclose(out);
	printf("%u frames, %u dropped mid-read, %u with the queue full, %u flips seen, in %u ms; %u ms per read\n",
	       written, dropped, full, flips, now_ms() - start, reads ? read_ms / reads : 0);
	return 0;
}
