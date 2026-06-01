# Echo Dot 2 as PC Microphone

Use a **rooted Amazon Echo Dot 2nd Gen** as a real-time microphone for your Mac/PC via ADB — no app install required on the device.

The Echo Dot 2 has an 8-microphone array (TLV320AIC3101, 4 chips × 2 channels). This project captures all 8 channels, mixes them for better SNR, and streams the audio to a virtual audio device (BlackHole) so any app can use it as a microphone.

---

## How It Works

### The Problem

The Echo Dot's mic array is permanently held by Amazon's `mediaserver` process (via `AudioRecord`). The ALSA PCM device (`pcmC0D24c`) only has 1 subdevice, so no other process can open it while `mediaserver` is running.

### The Solution (First Principles)

```
Echo Dot mic array (S24_3LE, 9ch, 16kHz)
    → echo_mic binary reads ALSA device directly via ioctl
    → stdout raw PCM
    → adb exec-out pipes it to Mac (zero extra software)
    → ffmpeg: mix 8 channels + amplify + resample to 48kHz
    → BlackHole 2ch virtual audio device
    → System microphone input (any app can use it)
```

**mic_guard** is a daemon that runs on the Echo Dot and continuously kills any process that grabs `pcmC0D24c`, keeping the mic free for `echo_mic`.
It only kills `mediaserver`; it does not kill this project's own `echo_mic` recorder.

### Why `tinycap` Doesn't Work

The Echo Dot's mic array uses `S24_3LE` format (24-bit, 3 bytes per sample, little-endian). The stock `tinycap` binary on the device only supports `S16_LE` and `S24_LE` (4-byte padded). Our custom `echo_mic` binary uses raw ALSA ioctls with the correct format.

### Audio Pipeline Details

| Stage | Detail |
|-------|--------|
| Hardware | TLV320AIC3101 × 4 (ADC_A/B/C/D), 8 mics + 1 reference |
| ALSA device | `pcmC0D24c` (card 0, device 24, capture) |
| Format | `S24_3LE`, 9 channels, 16000 Hz |
| Frame size | 27 bytes (9 × 3) |
| Mixing | Average of channels 0–7 (ch8 = reference, skipped) |
| Gain | Hardware MICPGA = 60 (from default 40), software 10× |
| Output | 48000 Hz, stereo, S16LE → BlackHole 2ch |

---

## Requirements

**On Mac:**
- [BlackHole 2ch](https://existential.audio/blackhole/) virtual audio driver
- `ffmpeg` (`brew install ffmpeg`)
- Android NDK 21+ (for compiling, or use prebuilt binaries in `bin/`)
- ADB (`brew install android-platform-tools`)

**On Echo Dot:**
- Amazon Echo Dot 2nd Gen (codename: `biscuit`, model `AEOBC`)
- Rooted with Magisk (see [XDA thread](https://xdaforums.com/t/unlock-root-twrp-unbrick-amazon-echo-dot-2nd-gen-2016-biscuit.4761416/))
- ADB over WiFi enabled (TCP port 5555)

---

## Setup

### Step 1: Run Setup

```bash
./setup.sh
```

This pushes `echo_mic` and `mic_guard`, installs the Magisk boot startup snippet, sets mic gain, and starts `mic_guard` immediately.

The boot snippet is appended to `/data/adb/service.d/adb_tcp.sh`, because that script is known to run on this Echo Dot/Magisk build. The standalone `scripts/91-disable-mediaserver-mic.sh` is kept as a fallback for Magisk builds that execute independent `service.d` scripts reliably.

### Step 2: Configure the Mac Script

Edit `scripts/echo_dot_mic.sh` and set your Echo Dot's IP:

```bash
ECHO_IP="192.168.31.89"   # ← change this
```

### Step 3: Run

```bash
chmod +x scripts/echo_dot_mic.sh
./scripts/echo_dot_mic.sh
```

Then in any app (Discord, Zoom, Typeless, etc.), select **BlackHole 2ch** as the microphone input.

Press `Ctrl+C` to stop. The script stops `mic_guard` first, then restores `mediaserver`.

### Manual Install

```bash
adb connect <ECHO_DOT_IP>:5555
adb push bin/echo_mic_arm64 /data/local/tmp/echo_mic
adb push bin/mic_guard_arm64 /data/local/tmp/mic_guard
adb shell "su -c 'chmod 755 /data/local/tmp/echo_mic /data/local/tmp/mic_guard'"
adb push scripts/adb_tcp_append.sh /data/local/tmp/
adb shell "su -c 'touch /data/adb/service.d/adb_tcp.sh && chmod 755 /data/adb/service.d/adb_tcp.sh && cat /data/local/tmp/adb_tcp_append.sh >> /data/adb/service.d/adb_tcp.sh'"
```

After reboot, the managed boot snippet waits 45 seconds, sets mic gain, kills the initial mic owner if present, and launches `mic_guard` with `nohup`.

Verify boot startup:

```bash
adb shell "su -c 'cat /data/adb/mic_disable.log'"
adb shell "su -c 'ps | grep \"[m]ic_guard\"'"
adb shell "cat /proc/asound/card0/pcm24c/sub0/status"
```

---

## Building from Source

Requires Android NDK 21+.

```bash
# macOS (NDK auto-detected from ~/Library/Android/sdk)
make

# Custom NDK path
make NDK=/path/to/ndk

# Output
bin/echo_mic_arm64
bin/mic_guard_arm64
```

---

## File Structure

```
EchoDotMic/
├── src/
│   ├── echo_mic.c          # ALSA capture tool (S24_3LE, 9ch)
│   └── mic_guard.c         # Daemon: keeps mediaserver off the mic
├── bin/
│   ├── echo_mic_arm64      # Prebuilt for arm64 Android
│   └── mic_guard_arm64     # Prebuilt for arm64 Android
├── scripts/
│   ├── echo_dot_mic.sh     # Mac: one-key stream to BlackHole
│   ├── adb_tcp_append.sh   # Magisk startup snippet appended by setup.sh
│   └── 91-disable-mediaserver-mic.sh  # Magisk boot script
├── setup.sh                # One-key install/start script
└── Makefile
```

---

## Debugging

### Check if mic is free

```bash
adb shell "cat /proc/asound/card0/pcm24c/sub0/status"
# "closed" = free, "RUNNING" = occupied
```

### Find who is holding the mic

```bash
adb shell "cat /proc/asound/card0/pcm24c/sub0/status"
# Look for "owner_pid: XXXX"
adb shell "cat /proc/XXXX/cmdline"
```

### Manually free the mic

```bash
adb shell "su -c 'kill -9 $(cat /proc/asound/card0/pcm24c/sub0/status | grep owner_pid | tr -s \" \" | cut -d\" \" -f3)'"
```

### Test recording without streaming

```bash
# Record 5 seconds to a file
adb shell "su -c '/data/local/tmp/echo_mic 5'" > /tmp/test.raw

# Convert and play
ffmpeg -f s24le -ar 16000 -ac 9 -i /tmp/test.raw \
  -filter_complex "pan=mono|c0=0.125*c0+0.125*c1+0.125*c2+0.125*c3+0.125*c4+0.125*c5+0.125*c6+0.125*c7,volume=10" \
  /tmp/test.wav && afplay /tmp/test.wav
```

### Check mic_guard is running

```bash
adb shell "su -c 'ps | grep mic_guard'"
```

### Adjust mic volume

In `scripts/echo_dot_mic.sh`, change `GAIN=10` (software multiplier).

For hardware gain, adjust MICPGA (0–127, default 40, we use 60):

```bash
adb shell "su -c 'tinymix 92 80 80'"   # ADC_A
adb shell "su -c 'tinymix 110 80 80'"  # ADC_B
adb shell "su -c 'tinymix 128 80 80'"  # ADC_C
adb shell "su -c 'tinymix 146 80 80'"  # ADC_D
```

### Check all tinymix controls

```bash
adb shell "su -c 'tinymix'"
```

### WiFi ADB not connecting

```bash
# Reconnect
adb disconnect <IP>:5555
adb connect <IP>:5555

# If still failing, reconnect via USB first
adb -s <USB_SERIAL> shell "su -c 'setprop service.adb.tcp.port 5555 && stop adbd && start adbd'"
```

### Boot startup did not run

```bash
adb shell "su -c 'grep -n \"Echo Dot mic_guard startup\" /data/adb/service.d/adb_tcp.sh'"
adb shell "su -c 'cat /data/adb/mic_disable.log'"
```

If the marker is missing, rerun `./setup.sh`. If the log shows `missing executable`, rerun setup to push `/data/local/tmp/mic_guard`.

### mediaserver keeps restarting too fast

The `mic_guard` daemon polls every 2 seconds. If `mediaserver` restarts and grabs the mic within that window, there's a brief gap. This is normal — `mic_guard` will kill `mediaserver` again within 2 seconds.

If you need the mic immediately (e.g., in the script), the script waits up to 20 seconds for `closed` status before starting the stream.

---

## Hardware Reference

| Component | Detail |
|-----------|--------|
| SoC | MediaTek MT8163 |
| Audio codec | TLV320AIC3101 × 4 (Texas Instruments) |
| Mic array | 7 mics in ring + 1 center = 8 total |
| Reference ch | Channel 8 (echo cancellation reference) |
| ALSA card | `mt-snd-card` |
| PCM device | card 0, device 24 |
| Format | S24_3LE (24-bit, 3 bytes, little-endian) |
| Sample rate | 16000 Hz (fixed, hardware limitation) |
| Channels | 9 (8 mic + 1 ref) |

---

## Limitations

- **16 kHz sample rate** — hardware fixed, cannot be changed. Sufficient for voice (speech recognition, calls), not for music.
- **Requires root + Magisk** on the Echo Dot.
- **mediaserver is killed** while mic is in use — Alexa voice features stop working. Restore with `setprop ctl.start mediaserver`.
- **WiFi latency** ~20–50ms over local network. Fine for voice input.

---

## Recovery

If anything goes wrong, simply reboot the Echo Dot:

```bash
adb shell "su -c 'reboot'"
```

All Amazon services restart automatically. No permanent changes are made to system partitions — only `/data/local/tmp/` (binaries) and `/data/adb/service.d/` (Magisk script).

To fully remove: delete those files and reboot.

---

## Credits

- Rooting method: [XDA — Echo Dot 2nd Gen unlock/root/TWRP](https://xdaforums.com/t/unlock-root-twrp-unbrick-amazon-echo-dot-2nd-gen-2016-biscuit.4761416/)
- Audio streaming concept inspired by [scrcpy](https://github.com/Genymobile/scrcpy) and [sndcpy](https://github.com/rom1v/sndcpy)
- [BlackHole](https://existential.audio/blackhole/) virtual audio driver by Existential Audio
