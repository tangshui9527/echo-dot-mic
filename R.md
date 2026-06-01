# Resolution Report — mic_guard Boot Startup

Date: 2026-06-01

## Problem

`mic_guard` did not reliably start after Echo Dot reboot, so `mediaserver` reclaimed `/proc/asound/card0/pcm24c/sub0/status` and kept the microphone busy until `mic_guard` was started manually.

## Root Cause

The repository had two weak assumptions:

- `setup.sh` skipped boot installation whenever `/data/adb/service.d/adb_tcp.sh` contained any `mic_guard` text, including stale or broken snippets.
- The boot snippet started `/data/local/tmp/mic_guard &` directly, without delaying long enough for audio initialization or detaching the daemon from service shell lifetime.
- `mic_guard` killed any process that owned the mic PCM device, so it also killed this project's own `echo_mic` process during streaming.

## Fix

- `scripts/adb_tcp_append.sh` now runs a background startup block that waits 45 seconds, sets tinymix gain, kills the initial mic owner if present, and starts `mic_guard` with `nohup`.
- `setup.sh` now checks for a fixed marker, ensures `/data/adb/service.d/adb_tcp.sh` exists and is executable, and appends the managed block only when missing.
- `setup.sh` starts `mic_guard` immediately with `nohup` and avoids launching duplicates.
- `scripts/91-disable-mediaserver-mic.sh` now uses the same robust startup logic as a fallback.
- `src/mic_guard.c` now kills only `mediaserver`, not `echo_mic` or other non-mediaserver owners.
- `scripts/echo_dot_mic.sh` now stops `mediaserver` cleanly before streaming and stops `mic_guard` before restoring `mediaserver` on exit.
- `README.md` and `HANDOVER.md` now describe the current install and verification flow.

## Verify

```bash
./setup.sh
adb shell "su -c 'reboot'"
# wait 70 seconds
adb connect 192.168.31.89:5555
adb shell "su -c 'grep -n \"Echo Dot mic_guard startup\" /data/adb/service.d/adb_tcp.sh'"
adb shell "su -c 'cat /data/adb/mic_disable.log'"
adb shell "su -c 'ps | grep \"[m]ic_guard\"'"
adb shell "cat /proc/asound/card0/pcm24c/sub0/status"
```

Expected result: `mic_guard` is running and microphone status is `closed` unless an active stream is using it.

## Stream Validation

```bash
adb -s 192.168.31.89:5555 shell "su -c 'setprop ctl.stop mediaserver'"
adb -s 192.168.31.89:5555 exec-out "su -c '/data/local/tmp/echo_mic 1'" | wc -c
```

Expected result: roughly 432,000 bytes for 1 second of 9-channel, 16 kHz, 24-bit PCM.
