/*
 * epdprobe — measure EPDC LUT (waveform) activity on-device, no camera needed.
 *
 * Mechanism: reading <epdc>/mxc_epdc_regs makes mxc_epdc_fb dump every EPDC
 * register into the kernel log (show() returns 0 bytes, the data goes to printk).
 * EPDC_STATUS_LUTS is a bitmap of LUTs the waveform engine is currently playing,
 * so "LUTS != 0" means "panel is being driven right now".
 *
 * We drain /dev/kmsg continuously (small kernel ring buffer would otherwise drop
 * lines) and keep only the EPDC_STATUS* records. printk timestamps are
 * CLOCK_MONOTONIC based, so they are directly comparable with our own clock.
 *
 * usage:
 *   epdprobe <regs_path> <update_path> <loop_seconds> <trigger_at_s> \
 *            <wfm_name> <update_mode> <left> <top> <w> <h> [repeat [interval_s]]
 *
 * output (stdout, csv):
 *   t_us,kernel_ts_us,key,value
 *   TRIG,<t_us>  marks the moment the update was requested
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>

static long long now_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000LL + ts.tv_nsec / 1000;
}

static const char *g_keep[8]; static int g_nkeep;
static int keep_match(const char *p) {
    for (int i = 0; i < g_nkeep; i++) if (strstr(p, g_keep[i])) return 1;
    return 0;
}

static void drain_kmsg(int kfd, long long trig_us) {
    char buf[4096];
    for (;;) {
        ssize_t n = read(kfd, buf, sizeof buf - 1);
        if (n <= 0) {
            if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return;
            if (n < 0 && errno == EPIPE) return;
            return;
        }
        buf[n] = 0;
        /* header: prio,seq,ts_usec,flags;msg */
        char *p = buf;
        long long ts = 0;
        int field = 0;
        for (char *q = buf; *q; q++) {
            if (*q == ',') { field++; if (field == 2) { ts = atoll(q + 1); break; } }
        }
        p = strchr(buf, ';');
        if (!p) continue;
        p++;
        if (!keep_match(p)) continue;
        /* split "EPDC_KEY 0xVAL" */
        char key[64]; unsigned long val = 0;
        if (sscanf(p, "%63s %li", key, (long *)&val) != 2) continue;
        printf("%lld,%lld,%s,0x%lx\n", (long long)(now_us() - trig_us), ts, key, val);
        fflush(stdout);
    }
}

static int trigger(const char *path, const char *name, int mode, int l, int t, int w, int h) {
    char cmd[256];
    int n = snprintf(cmd, sizeof cmd, "%s %d %d %d %d %d\n", name, mode, l, t, w, h);
    int fd = open(path, O_WRONLY);
    if (fd < 0) { perror("open update"); return -1; }
    ssize_t r = write(fd, cmd, n);
    close(fd);
    if (r != n) { perror("write update"); return -1; }
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 10) {
        fprintf(stderr,
            "usage: %s <regs> <update> <loop_s> <trigger_at_s> <wfm> <mode> <l> <t> <w> <h> [repeat [interval_s]]\n",
            argv[0]);
        return 2;
    }
    const char *regs = argv[1], *upd = argv[2];
    double loop_s = atof(argv[3]), trig_at = atof(argv[4]);
    const char *wfm = argv[5];
    int mode = atoi(argv[6]), l = atoi(argv[7]), t = atoi(argv[8]), w = atoi(argv[9]), h = atoi(argv[10]);
    int repeat = (argc > 11) ? atoi(argv[11]) : 1;
    double interval = (argc > 12) ? atof(argv[12]) : 0.5;

    const char *keep = getenv("KEEP");
    if (!keep) keep = "EPDC_STATUS";
    { char *dup = strdup(keep), *tok, *save = NULL;
      for (tok = strtok_r(dup, ",", &save); tok && g_nkeep < 8; tok = strtok_r(NULL, ",", &save))
          g_keep[g_nkeep++] = strdup(tok); }

    int kfd = open("/dev/kmsg", O_RDONLY | O_NONBLOCK);
    if (kfd < 0) { perror("open /dev/kmsg"); return 1; }
    /* drop anything already queued */
    char tmp[4096];
    while (read(kfd, tmp, sizeof tmp - 1) > 0) {}

    long long t0 = now_us();
    long long deadline = t0 + (long long)(loop_s * 1e6);
    long long next_trig = t0 + (long long)(trig_at * 1e6);
    int fired = 0;
    unsigned long dumps = 0;

    while (now_us() < deadline) {
        long long tn = now_us();
        if (fired < repeat && tn >= next_trig) {
            printf("%lld,%lld,TRIG,%s\n", tn - t0, tn, wfm);
            fflush(stdout);
            trigger(upd, wfm, mode, l, t, w, h);
            fired++;
            next_trig = tn + (long long)(interval * 1e6);
        }
        int fd = open(regs, O_RDONLY);
        if (fd >= 0) {
            char b[256];
            ssize_t n = read(fd, b, sizeof b);
            (void)n;
            close(fd);
            dumps++;
        }
        drain_kmsg(kfd, t0);
    }
    drain_kmsg(kfd, t0);
    fprintf(stderr, "dumps=%lu loops=%d\n", dumps, fired);
    close(kfd);
    return 0;
}
