#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <string.h>

static int is_mediaserver(int pid) {
    char path[64];
    char cmdline[256];
    FILE *f;
    size_t n;

    snprintf(path, sizeof(path), "/proc/%d/cmdline", pid);
    f = fopen(path, "r");
    if (!f) {
        return 0;
    }

    n = fread(cmdline, 1, sizeof(cmdline) - 1, f);
    fclose(f);
    if (n == 0) {
        return 0;
    }

    cmdline[n] = '\0';
    return strstr(cmdline, "/system/bin/mediaserver") != NULL ||
           strstr(cmdline, "mediaserver") != NULL;
}

int main() {
    /* Wait for ALSA to initialize */
    sleep(10);

    while (1) {
        FILE *f = fopen("/proc/asound/card0/pcm24c/sub0/status", "r");
        if (f) {
            char line[256];
            while (fgets(line, sizeof(line), f)) {
                if (strstr(line, "owner_pid")) {
                    char *colon = strchr(line, ':');
                    if (colon) {
                        int pid = atoi(colon + 1);
                        if (pid > 1 && is_mediaserver(pid)) {
                            kill(pid, 9);
                        }
                    }
                }
            }
            fclose(f);
        }
        sleep(2);
    }
    return 0;
}
