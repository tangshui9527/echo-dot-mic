#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <string.h>

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
                        if (pid > 1) {
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
