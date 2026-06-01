#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <string.h>

int main() {
    while (1) {
        FILE *f = fopen("/proc/asound/card0/pcm24c/sub0/status", "r");
        if (f) {
            char line[256];
            while (fgets(line, sizeof(line), f)) {
                if (strstr(line, "owner_pid")) {
                    int pid = 0;
                    sscanf(line, "owner_pid   : %d", &pid);
                    if (pid > 0) {
                        kill(pid, 9);
                    }
                }
            }
            fclose(f);
        }
        sleep(3);
    }
    return 0;
}
