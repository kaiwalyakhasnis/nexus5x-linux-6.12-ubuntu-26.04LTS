// fbgrab OUT.ppm [card]: save what the panel shows (the framebuffer on the
// first active plane) as a binary PPM. Root: GETFB2 hands out buffer handles
// only to CAP_SYS_ADMIN. 32-bit XRGB/ARGB8888 linear buffers (Mir in sysmem
// rendering, the console) only.
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
#include <drm_fourcc.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

int main(int argc, char **argv)
{
	const char *card = argc > 2 ? argv[2] : "/dev/dri/card1";
	int fd = open(card, O_RDWR | O_CLOEXEC);
	if (fd < 0 || argc < 2) {
		fprintf(stderr, "usage: fbgrab OUT.ppm [card]\n");
		return 1;
	}
	drmSetClientCap(fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1);
	drmModePlaneResPtr pr = drmModeGetPlaneResources(fd);
	drmModeFB2Ptr fb = NULL;
	for (uint32_t i = 0; pr && i < pr->count_planes && !fb; i++) {
		drmModePlanePtr p = drmModeGetPlane(fd, pr->planes[i]);
		if (p && p->fb_id)
			fb = drmModeGetFB2(fd, p->fb_id);
		drmModeFreePlane(p);
	}
	if (!fb || !fb->handles[0]) {
		fprintf(stderr, "no framebuffer with a handle (root?)\n");
		return 1;
	}
	if (fb->pixel_format != DRM_FORMAT_XRGB8888 &&
	    fb->pixel_format != DRM_FORMAT_ARGB8888) {
		fprintf(stderr, "format %.4s not handled\n", (char *)&fb->pixel_format);
		return 1;
	}
	int dmafd;
	if (drmPrimeHandleToFD(fd, fb->handles[0], DRM_CLOEXEC, &dmafd)) {
		perror("prime export");
		return 1;
	}
	size_t size = (size_t)fb->pitches[0] * fb->height + fb->offsets[0];
	uint8_t *map = mmap(NULL, size, PROT_READ, MAP_SHARED, dmafd, 0);
	if (map == MAP_FAILED) {
		perror("mmap");
		return 1;
	}
	FILE *out = fopen(argv[1], "wb");
	fprintf(out, "P6 %u %u 255\n", fb->width, fb->height);
	uint8_t *row = malloc(fb->width * 3);
	for (uint32_t y = 0; y < fb->height; y++) {
		const uint8_t *s = map + fb->offsets[0] + (size_t)y * fb->pitches[0];
		for (uint32_t x = 0; x < fb->width; x++) {
			row[x * 3 + 0] = s[x * 4 + 2];
			row[x * 3 + 1] = s[x * 4 + 1];
			row[x * 3 + 2] = s[x * 4 + 0];
		}
		fwrite(row, 3, fb->width, out);
	}
	fclose(out);
	printf("%ux%u fb %u\n", fb->width, fb->height, fb->fb_id);
	return 0;
}
