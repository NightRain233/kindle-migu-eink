/*
 * einkctl.c — EPDC 只读查询 + 受控提交（含"提交/等待"分开计时）
 *
 * 提交： ioctl(fd, 0x4050464e = _IOW('F',0x4E,80), struct80*)
 * 等待： ioctl(fd, 0xc008464f = _IOWR('F',0x4F,8), {marker, collision}*)
 * 配置： 0x4601 —— 危险，本程序绝不调用
 *
 * struct80 布局（实测确认）：
 *   +0 left  +4 top  +8 width  +12 height
 *   +16 waveform  +20 update_mode  +24 marker
 *   +28 temp  +32 flags  +36 dither  +40 quant
 *   +44 alt_buffer(28B)  +72 hist_bw  +76 hist_gray
 *
 * 用法：
 *   einkctl                      只读查询
 *   ONE_WF=8 ONE_W=600 ONE_H=800 einkctl    指定波形/区域提交一次
 *   ONE_FULL=1 ONE_WF=2 einkctl             按当前 fb 几何整屏刷新
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <linux/fb.h>

#define CMD_INFO    0x4600UL
#define CMD_NAME    0x4602UL
#define CMD_SUBMIT  0x4050464eUL
#define CMD_WAIT    0xc008464fUL

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

static void hexdump32(const char *tag, const unsigned char *b, int n) {
    printf("    %s:", tag);
    for (int i = 0; i < n; i++) printf(" %02x", b[i]);
    printf("\n");
}

static int stage_queries(int fd) {
    printf("== queries ==\n");
    struct fb_var_screeninfo vi; memset(&vi, 0, sizeof vi);
    struct fb_fix_screeninfo fi; memset(&fi, 0, sizeof fi);
    if (ioctl(fd, FBIOGET_VSCREENINFO, &vi) == 0)
        printf("  var: %ux%u bpp=%u rotate=%u\n", vi.xres, vi.yres, vi.bits_per_pixel, vi.rotate);
    else printf("  var failed: %s\n", strerror(errno));
    if (ioctl(fd, FBIOGET_FSCREENINFO, &fi) == 0)
        printf("  fix: id='%s' line_length=%u smem_len=%u\n", fi.id, fi.line_length, fi.smem_len);
    else printf("  fix failed: %s\n", strerror(errno));

    unsigned long cmds[2] = { CMD_INFO, CMD_NAME };
    const char *names[2] = { "INFO", "NAME" };
    for (int i = 0; i < 2; i++) {
        unsigned char buf[256]; memset(buf, 0, sizeof buf);
        errno = 0;
        int r = ioctl(fd, cmds[i], buf);
        printf("  %-4s ret=%d errno=%d\n", names[i], r, errno);
        if (r == 0) hexdump32("buf", buf, 16);
    }
    return 0;
}

static int stage_one(int fd) {
    alarm(8);
    uint32_t wf  = getenv("ONE_WF")  ? (uint32_t)strtoul(getenv("ONE_WF"), 0, 0)  : 1u;
    uint32_t mkr = getenv("ONE_MKR") ? (uint32_t)strtoul(getenv("ONE_MKR"), 0, 0) : 0x1001u;
    uint32_t L = getenv("ONE_L") ? (uint32_t)atoi(getenv("ONE_L")) : 0u;
    uint32_t T = getenv("ONE_T") ? (uint32_t)atoi(getenv("ONE_T")) : 0u;
    uint32_t W = getenv("ONE_W") ? (uint32_t)atoi(getenv("ONE_W")) : 600u;
    uint32_t H = getenv("ONE_H") ? (uint32_t)atoi(getenv("ONE_H")) : 800u;

    if (getenv("ONE_FULL")) {
        struct fb_var_screeninfo vi; memset(&vi, 0, sizeof vi);
        if (ioctl(fd, FBIOGET_VSCREENINFO, &vi) != 0) {
            printf("FBIOGET_VSCREENINFO failed: %s\n", strerror(errno));
            return 1;
        }
        L = 0; T = 0; W = vi.xres; H = vi.yres;
    }

    unsigned char b[80]; memset(b, 0, sizeof b);
    uint32_t v;
    memcpy(b + 0,  &L, 4);
    memcpy(b + 4,  &T, 4);
    memcpy(b + 8,  &W, 4);
    memcpy(b + 12, &H, 4);
    memcpy(b + 16, &wf, 4);        /* waveform */
    v = 0; memcpy(b + 20, &v, 4);  /* update_mode = PARTIAL */
    memcpy(b + 24, &mkr, 4);       /* marker */
    v = 1; memcpy(b + 72, &v, 4);  /* hist_bw = DU */
    v = 2; memcpy(b + 76, &v, 4);  /* hist_gray = GC16 */

    uint32_t w[2] = { mkr, 0 };
    double t0 = now_ms();
    errno = 0;
    int ret = ioctl(fd, CMD_SUBMIT, b);
    int sret = errno;
    double send_ms = now_ms() - t0;
    if (ret < 0) {
        printf("wf=%-3u rect=%u,%u %ux%u submit=FAIL errno=%d (%s) send=%.2fms\n",
               wf, L, T, W, H, sret, strerror(sret), send_ms);
        return 1;
    }
    double t1 = now_ms();
    errno = 0;
    int wr = ioctl(fd, CMD_WAIT, w);
    int wret = errno;
    double wait_ms = now_ms() - t1;
    printf("wf=%-3u rect=%u,%u %ux%u send=%.2fms wait=%.2fms(%s) total=%.2fms\n",
           wf, L, T, W, H, send_ms, wait_ms,
           wr < 0 ? strerror(wret) : "ok", send_ms + wait_ms);
    return 0;
}

int main(int argc, char **argv) {
    const char *dev = (argc > 1) ? argv[1] : "/dev/graphics/fb0";
    int fd = open(dev, O_RDWR);
    if (fd < 0) { printf("open %s failed: %s\n", dev, strerror(errno)); return 1; }

    if (getenv("ONE_WF") || getenv("ONE_FULL")) {
        int r = stage_one(fd);
        close(fd);
        return r;
    }
    stage_queries(fd);
    close(fd);
    return 0;
}
