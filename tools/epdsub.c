/*
 * epdsub — submit one EPDC update via the driver ioctl only.
 * Does NOT touch the framebuffer (fb_deferred_io + msync wedges the driver).
 * Writes a marker line to /dev/kmsg so it can be aligned with register samples.
 *
 * usage: epdsub <wf> [mode] [temp] [flags] [marker]
 *
 * IMPORTANT: struct offset +36 must be 4097 (TEMP_USE_AMBIENT) — pass DITH=4097.
 * With 0 the driver selects a cold-temperature waveform (~3x longer).
 * An older "+28 temp +36 dither" layout seen in notes is wrong for this driver.
 *
 * env: DITH (+36, use 4097), FLAGS2 (+32), QUANT (+40), HB/HG (+72/+76, default 1/2)
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <stdarg.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/fb.h>

#define CMD_SUBMIT 0x4050464eUL

static void kmark(const char *fmt, ...) {
    char b[192];
    va_list ap; va_start(ap, fmt);
    vsnprintf(b, sizeof b, fmt, ap);
    va_end(ap);
    int fd = open("/dev/kmsg", O_WRONLY);
    if (fd >= 0) { ssize_t n = write(fd, b, strlen(b)); (void)n; close(fd); }
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <wf> [mode] [temp] [flags] [marker]\n", argv[0]); return 2; }
    uint32_t wf = (uint32_t)strtoul(argv[1], 0, 0);
    uint32_t mode = (argc > 2) ? (uint32_t)strtoul(argv[2], 0, 0) : 1u;
    int32_t temp = (argc > 3) ? (int32_t)strtol(argv[3], 0, 0) : 0;
    uint32_t flags = (argc > 4) ? (uint32_t)strtoul(argv[4], 0, 0) : 0u;
    uint32_t marker = (argc > 5) ? (uint32_t)strtoul(argv[5], 0, 0) : 0x5001u;

    int fd = open("/dev/graphics/fb0", O_RDWR);
    if (fd < 0) { perror("open fb0"); return 1; }
    struct fb_var_screeninfo vi;
    if (ioctl(fd, FBIOGET_VSCREENINFO, &vi)) { perror("FBIOGET_VSCREENINFO"); return 1; }

    unsigned char b[80];
    memset(b, 0, sizeof b);
    uint32_t L = 0, T = 0, W = vi.xres, H = vi.yres;
    memcpy(b + 0, &L, 4); memcpy(b + 4, &T, 4);
    memcpy(b + 8, &W, 4); memcpy(b + 12, &H, 4);
    memcpy(b + 16, &wf, 4); memcpy(b + 20, &mode, 4);
    memcpy(b + 24, &marker, 4); memcpy(b + 28, &temp, 4);
    int32_t dith = getenv("DITH") ? (int32_t)strtol(getenv("DITH"), 0, 0) : 0;
    int32_t quant = getenv("QUANT") ? (int32_t)strtol(getenv("QUANT"), 0, 0) : 0;
    uint32_t flags2 = getenv("FLAGS2") ? (uint32_t)strtoul(getenv("FLAGS2"), 0, 0) : flags;
    memcpy(b + 32, &flags2, 4);
    memcpy(b + 36, &dith, 4);
    memcpy(b + 40, &quant, 4);
    uint32_t hb = getenv("HB") ? (uint32_t)strtoul(getenv("HB"), 0, 0) : 1u;
    uint32_t hg = getenv("HG") ? (uint32_t)strtoul(getenv("HG"), 0, 0) : 2u;
    memcpy(b + 72, &hb, 4); memcpy(b + 76, &hg, 4);

    kmark("WFTEST IOCTL wf=%u mode=%u temp=%d flags=%u hb=%u hg=%u %ux%u", wf, mode, temp, flags, hb, hg, W, H);
    errno = 0;
    int ret = ioctl(fd, CMD_SUBMIT, b);
    int e = errno;
    printf("wf=%-3u mode=%u temp=%d flags=%u ret=%d errno=%d(%s)\n", wf, mode, temp, flags, ret, e, strerror(e));
    close(fd);
    return ret < 0 ? 1 : 0;
}
