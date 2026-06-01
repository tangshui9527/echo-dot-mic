/* Echo Dot 2 mic capture — sends raw PCM via TCP to a remote host */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sound/asound.h>

#define NUM_MASKS     (SNDRV_PCM_HW_PARAM_LAST_MASK - SNDRV_PCM_HW_PARAM_FIRST_MASK + 1)
#define NUM_INTERVALS (SNDRV_PCM_HW_PARAM_LAST_INTERVAL - SNDRV_PCM_HW_PARAM_FIRST_INTERVAL + 1)

static volatile int running = 1;
static void sighandler(int s) { (void)s; running = 0; }

/* usage: echo_mic <host> <port> [duration_seconds]
 *        echo_mic stdout [duration_seconds]   -- write to stdout (USB ADB)
 */
int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "Usage: %s <host> <port> [seconds]\n", argv[0]);
        fprintf(stderr, "       %s stdout [seconds]\n", argv[0]);
        return 1;
    }

    int use_stdout = (strcmp(argv[1], "stdout") == 0);
    const char *host = use_stdout ? NULL : argv[1];
    int port         = use_stdout ? 0 : atoi(argv[2]);
    int duration     = argc > (use_stdout ? 2 : 3) ? atoi(argv[use_stdout ? 2 : 3]) : 0;

    const char *dev = "/dev/snd/pcmC0D24c";
    int channels = 9, rate = 16000;
    int period_size = 256, periods = 10;

    /* Open ALSA device */
    int fd = open(dev, O_RDONLY);
    if (fd < 0) { perror("open pcm"); return 1; }

    struct snd_pcm_hw_params hw;
    memset(&hw, 0, sizeof(hw));
    for (int i = 0; i < NUM_MASKS; i++)
        memset(&hw.masks[i], 0xff, sizeof(hw.masks[i]));
    for (int i = 0; i < NUM_INTERVALS; i++) {
        hw.intervals[i].min = 0;
        hw.intervals[i].max = ~0U;
    }

    int mi = SNDRV_PCM_HW_PARAM_ACCESS - SNDRV_PCM_HW_PARAM_FIRST_MASK;
    memset(&hw.masks[mi], 0, sizeof(struct snd_mask));
    hw.masks[mi].bits[SNDRV_PCM_ACCESS_RW_INTERLEAVED / 32] = 1u << (SNDRV_PCM_ACCESS_RW_INTERLEAVED % 32);

    mi = SNDRV_PCM_HW_PARAM_FORMAT - SNDRV_PCM_HW_PARAM_FIRST_MASK;
    memset(&hw.masks[mi], 0, sizeof(struct snd_mask));
    hw.masks[mi].bits[SNDRV_PCM_FORMAT_S24_3LE / 32] = 1u << (SNDRV_PCM_FORMAT_S24_3LE % 32);

#define SET_IV(param, val) do { \
    int idx = (param) - SNDRV_PCM_HW_PARAM_FIRST_INTERVAL; \
    hw.intervals[idx].min = hw.intervals[idx].max = (val); \
    hw.intervals[idx].integer = 1; } while(0)

    SET_IV(SNDRV_PCM_HW_PARAM_CHANNELS, channels);
    SET_IV(SNDRV_PCM_HW_PARAM_RATE, rate);
    SET_IV(SNDRV_PCM_HW_PARAM_PERIOD_SIZE, period_size);
    SET_IV(SNDRV_PCM_HW_PARAM_PERIODS, periods);
    hw.rmask = ~0U;

    if (ioctl(fd, SNDRV_PCM_IOCTL_HW_PARAMS, &hw) < 0) { perror("HW_PARAMS"); close(fd); return 1; }

    struct snd_pcm_sw_params sw;
    memset(&sw, 0, sizeof(sw));
    sw.start_threshold = 1;
    sw.stop_threshold  = period_size * periods;
    sw.avail_min       = period_size;
    if (ioctl(fd, SNDRV_PCM_IOCTL_SW_PARAMS, &sw) < 0) { perror("SW_PARAMS"); close(fd); return 1; }
    if (ioctl(fd, SNDRV_PCM_IOCTL_PREPARE, 0) < 0)     { perror("PREPARE");   close(fd); return 1; }

    /* Open output: TCP socket or stdout */
    int out_fd;
    if (use_stdout) {
        out_fd = STDOUT_FILENO;
    } else {
        int sock = socket(AF_INET, SOCK_STREAM, 0);
        if (sock < 0) { perror("socket"); close(fd); return 1; }
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_port   = htons(port);
        inet_pton(AF_INET, host, &addr.sin_addr);
        if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            perror("connect"); close(sock); close(fd); return 1;
        }
        out_fd = sock;
    }

    signal(SIGINT, sighandler);
    signal(SIGTERM, sighandler);

    int frame_bytes = channels * 3;
    int buf_size    = period_size * frame_bytes;
    unsigned char *buf = malloc(buf_size);
    long total    = duration > 0 ? (long)rate * duration : 0;
    long captured = 0;

    fprintf(stderr, "Recording %dch %dHz S24_3LE → %s\n",
            channels, rate, use_stdout ? "stdout" : host);

    while (running) {
        struct snd_xferi xfer;
        xfer.buf    = buf;
        xfer.frames = period_size;
        xfer.result = 0;
        if (ioctl(fd, SNDRV_PCM_IOCTL_READI_FRAMES, &xfer) < 0) {
            if (ioctl(fd, SNDRV_PCM_IOCTL_PREPARE, 0) < 0) break;
            continue;
        }
        if (xfer.result > 0) {
            int bytes = xfer.result * frame_bytes;
            if (write(out_fd, buf, bytes) != bytes) break; /* connection closed */
            captured += xfer.result;
        }
        if (total > 0 && captured >= total) break;
    }

    fprintf(stderr, "Done: %ld frames\n", captured);
    close(fd);
    if (!use_stdout) close(out_fd);
    free(buf);
    return 0;
}
