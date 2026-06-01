/* Echo Dot 2 mic capture */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sound/asound.h>

#define NUM_MASKS (SNDRV_PCM_HW_PARAM_LAST_MASK - SNDRV_PCM_HW_PARAM_FIRST_MASK + 1)
#define NUM_INTERVALS (SNDRV_PCM_HW_PARAM_LAST_INTERVAL - SNDRV_PCM_HW_PARAM_FIRST_INTERVAL + 1)

static volatile int running = 1;
static void sighandler(int s) { (void)s; running = 0; }

int main(int argc, char **argv) {
    int duration = argc > 1 ? atoi(argv[1]) : 0;
    const char *dev = "/dev/snd/pcmC0D24c";
    int channels = 9, rate = 16000;
    int period_size = 256, periods = 10;

    int fd = open(dev, O_RDONLY);
    if (fd < 0) { perror("open"); return 1; }

    struct snd_pcm_hw_params hw;
    memset(&hw, 0, sizeof(hw));

    for (int i = 0; i < NUM_MASKS; i++)
        memset(&hw.masks[i], 0xff, sizeof(hw.masks[i]));
    for (int i = 0; i < NUM_INTERVALS; i++) {
        hw.intervals[i].min = 0;
        hw.intervals[i].max = ~0U;
    }

    /* Access: RW_INTERLEAVED */
    int mi = SNDRV_PCM_HW_PARAM_ACCESS - SNDRV_PCM_HW_PARAM_FIRST_MASK;
    memset(&hw.masks[mi], 0, sizeof(struct snd_mask));
    hw.masks[mi].bits[SNDRV_PCM_ACCESS_RW_INTERLEAVED / 32] = 1u << (SNDRV_PCM_ACCESS_RW_INTERLEAVED % 32);

    /* Format: S24_3LE */
    mi = SNDRV_PCM_HW_PARAM_FORMAT - SNDRV_PCM_HW_PARAM_FIRST_MASK;
    memset(&hw.masks[mi], 0, sizeof(struct snd_mask));
    hw.masks[mi].bits[SNDRV_PCM_FORMAT_S24_3LE / 32] = 1u << (SNDRV_PCM_FORMAT_S24_3LE % 32);

    /* Intervals */
    #define SET_INTERVAL(param, val) do { \
        int idx = (param) - SNDRV_PCM_HW_PARAM_FIRST_INTERVAL; \
        hw.intervals[idx].min = (val); \
        hw.intervals[idx].max = (val); \
        hw.intervals[idx].integer = 1; \
    } while(0)

    SET_INTERVAL(SNDRV_PCM_HW_PARAM_CHANNELS, channels);
    SET_INTERVAL(SNDRV_PCM_HW_PARAM_RATE, rate);
    SET_INTERVAL(SNDRV_PCM_HW_PARAM_PERIOD_SIZE, period_size);
    SET_INTERVAL(SNDRV_PCM_HW_PARAM_PERIODS, periods);

    hw.rmask = ~0U;

    if (ioctl(fd, SNDRV_PCM_IOCTL_HW_PARAMS, &hw) < 0) {
        perror("HW_PARAMS");
        close(fd);
        return 1;
    }

    struct snd_pcm_sw_params sw;
    memset(&sw, 0, sizeof(sw));
    sw.start_threshold = 1;
    sw.stop_threshold = period_size * periods;
    sw.avail_min = period_size;

    if (ioctl(fd, SNDRV_PCM_IOCTL_SW_PARAMS, &sw) < 0) {
        perror("SW_PARAMS");
        close(fd);
        return 1;
    }

    if (ioctl(fd, SNDRV_PCM_IOCTL_PREPARE, 0) < 0) {
        perror("PREPARE");
        close(fd);
        return 1;
    }

    signal(SIGINT, sighandler);
    signal(SIGTERM, sighandler);

    int frame_bytes = channels * 3;
    int buf_size = period_size * frame_bytes;
    unsigned char *buf = malloc(buf_size);
    long total = duration > 0 ? (long)rate * duration : 0;
    long captured = 0;

    fprintf(stderr, "Recording %dch %dHz S24_3LE from %s\n", channels, rate, dev);

    while (running) {
        struct snd_xferi xfer;
        xfer.buf = buf;
        xfer.frames = period_size;
        xfer.result = 0;

        if (ioctl(fd, SNDRV_PCM_IOCTL_READI_FRAMES, &xfer) < 0) {
            if (ioctl(fd, SNDRV_PCM_IOCTL_PREPARE, 0) < 0) break;
            continue;
        }
        if (xfer.result > 0) {
            write(STDOUT_FILENO, buf, xfer.result * frame_bytes);
            captured += xfer.result;
        }
        if (total > 0 && captured >= total) break;
    }

    fprintf(stderr, "Done: %ld frames\n", captured);
    close(fd);
    free(buf);
    return 0;
}
