/* Legacy: tapctl DEV X Y COUNT GAP_MS
 * Benchmark: tapctl --sequence DEV X1 Y1 X2 Y2 COUNT PERIOD_MS
 * Device monotonic deadlines; timestamps bracket SYN writes, not finger contact.
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <signal.h>
#include <linux/input.h>
static volatile sig_atomic_t stopped;
static void stop(int sig) { (void)sig; stopped = 1; }
static int64_t now_ns(clockid_t clock) {
    struct timespec t;
    if (clock_gettime(clock, &t)) { perror("clock_gettime"); exit(1); }
    return (int64_t)t.tv_sec * 1000000000LL + t.tv_nsec;
}
static int number(const char *s, int max) {
    char *end; errno = 0;
    long n = strtol(s, &end, 10);
    if (errno || !*s || *end || n < 0 || n > max) {
        fprintf(stderr, "invalid argument: %s\n", s); exit(2);
    }
    return (int)n;
}
static int emit(int fd, int type, int code, int value) {
    struct input_event ev;
    memset(&ev, 0, sizeof ev);
    ev.type = type; ev.code = code; ev.value = value;
    ssize_t n;
    do { n = write(fd, &ev, sizeof ev); } while (n < 0 && errno == EINTR);
    if (n != sizeof ev) { perror("input event write"); return -1; }
    return 0;
}
static int sync_record(int fd, int seq, const char *edge, int x, int y, int64_t scheduled) {
    int64_t before = now_ns(CLOCK_MONOTONIC), real = now_ns(CLOCK_REALTIME);
    int rc = emit(fd, EV_SYN, SYN_REPORT, 0);
    int64_t after = now_ns(CLOCK_MONOTONIC);
    printf("%d,%s,%d,%d,%lld,%lld,%lld,%lld,%d\n", seq, edge, x, y,
           (long long)scheduled, (long long)before, (long long)after, (long long)real, rc);
    return rc;
}
static int sleep_until(int64_t deadline) {
    while (!stopped) {
        int64_t left = deadline - now_ns(CLOCK_MONOTONIC);
        if (left <= 0) return 0;
        struct timespec t = {left / 1000000000LL, left % 1000000000LL};
        if (nanosleep(&t, NULL) && errno != EINTR) return -1;
    }
    return -1;
}
static int release(int fd) {
    int a = emit(fd, EV_ABS, ABS_MT_SLOT, 0);
    int b = emit(fd, EV_ABS, ABS_MT_TRACKING_ID, -1);
    int c = emit(fd, EV_KEY, BTN_TOUCH, 0);
    return a || b || c;
}
int main(int argc, char **argv) {
    int sequence = argc > 1 && !strcmp(argv[1], "--sequence");
    if (argc != (sequence ? 9 : 6)) {
        fprintf(stderr, "usage: %s DEV X Y COUNT GAP_MS\n"
                "       %s --sequence DEV X1 Y1 X2 Y2 COUNT PERIOD_MS\n", argv[0], argv[0]);
        return 2;
    }
    int base = sequence ? 2 : 1, x[2], y[2];
    x[0] = number(argv[base+1], 599); y[0] = number(argv[base+2], 799);
    x[1] = sequence ? number(argv[5], 599) : x[0];
    y[1] = sequence ? number(argv[6], 799) : y[0];
    int count = number(argv[sequence ? 7 : 4], 10000);
    int interval = number(argv[sequence ? 8 : 5], 60000);
    if (!count || (sequence && interval < 50)) {
        fprintf(stderr, "count must be positive; sequence period must be >=50ms\n"); return 2;
    }
    int fd = open(argv[base], O_WRONLY);
    if (fd < 0) { perror("open input"); return 1; }
    signal(SIGINT, stop); signal(SIGTERM, stop);
    puts("seq,edge,x,y,scheduled_mono_ns,before_mono_ns,after_mono_ns,realtime_ns,rc");
    int64_t next = now_ns(CLOCK_MONOTONIC);
    int rc = 0;
    for (int i = 0; i < count && !stopped; i++) {
        int j = i % 2;
        if (sleep_until(next)) { rc = 1; break; }
        if (emit(fd, EV_ABS, ABS_MT_SLOT, 0) ||
            emit(fd, EV_ABS, ABS_MT_TRACKING_ID, 100+i) ||
            emit(fd, EV_ABS, ABS_MT_POSITION_X, x[j]) ||
            emit(fd, EV_ABS, ABS_MT_POSITION_Y, y[j]) ||
            emit(fd, EV_KEY, BTN_TOUCH, 1) ||
            sync_record(fd, i+1, "down", x[j], y[j], next)) { rc = 1; break; }
        if (sleep_until(now_ns(CLOCK_MONOTONIC) + 30000000LL)) { rc = 1; break; }
        if (release(fd) || sync_record(fd, i+1, "up", x[j], y[j], 0)) { rc = 1; break; }
        if (sequence) {
            next += (int64_t)interval * 1000000;
            int64_t earliest = now_ns(CLOCK_MONOTONIC) + 1000000;
            if (next < earliest) next = earliest;
        } else next = now_ns(CLOCK_MONOTONIC) + (int64_t)interval * 1000000;
    }
    if (rc || stopped) { release(fd); emit(fd, EV_SYN, SYN_REPORT, 0); }
    close(fd);
    return rc || stopped ? 1 : 0;
}
