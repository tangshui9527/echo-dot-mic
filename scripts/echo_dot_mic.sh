#!/bin/bash
set -uo pipefail
# Note: no -e, we handle errors explicitly

ECHO_IP="192.168.31.89"
ADB_PORT="5555"
DEVICE_BIN="/data/local/tmp/echo_mic"
GAIN=10
BLACKHOLE_INDEX=1
TCP_PORT=54399
STREAM_PID=""
SERIAL=""

adb_ok() { adb -s "$1" shell "echo ok" >/dev/null 2>&1; }

device_kill() {
    local name="${1##*/}"
    adb -s "$SERIAL" shell "su -c '/data/adb/magisk/busybox killall -9 $name 2>/dev/null; true'" 2>/dev/null || true
}

kill_echo_mic() {
    local owner
    owner=$(adb -s "$SERIAL" shell "cat /proc/asound/card0/pcm24c/sub0/status 2>/dev/null" \
            | grep owner_pid | cut -d: -f2 | tr -d ' \r' || true)
    if [ -n "$owner" ] && [ "$owner" -gt 1 ] 2>/dev/null; then
        adb -s "$SERIAL" shell "su -c 'kill -9 $owner'" 2>/dev/null || true
    fi
    device_kill "/data/local/tmp/echo_mic"
}

kill_mic_guard() { device_kill "/data/local/tmp/mic_guard"; }

free_mic() {
    adb -s "$SERIAL" shell "su -c 'stop media; setprop ctl.stop media'" 2>/dev/null || true
    kill_echo_mic
}

wait_for_mic_closed() {
    for i in $(seq 1 20); do
        local s
        s=$(adb -s "$SERIAL" shell "cat /proc/asound/card0/pcm24c/sub0/status 2>/dev/null" || true)
        if echo "$s" | grep -qE "^state: (closed|OPEN)$"; then
            return 0
        fi
        free_mic
        sleep 1
    done
    echo "ERROR: mic still busy after 20s" >&2
    return 1
}

cleanup() {
    echo ""
    echo "Stopping..."
    [ -n "$STREAM_PID" ] && kill "$STREAM_PID" 2>/dev/null || true
    pkill -f "nc.*$TCP_PORT" 2>/dev/null || true
    kill_echo_mic
    kill_mic_guard
    adb -s "$SERIAL" shell "su -c 'start media; setprop ctl.start media'" 2>/dev/null || true
    echo "Done."
}
trap cleanup EXIT INT TERM

# --- Connect ---
USB_SERIAL="G090LF0965021FUG"
WIFI_SERIAL="$ECHO_IP:$ADB_PORT"
if adb_ok "$USB_SERIAL"; then
    SERIAL="$USB_SERIAL"
    echo "[*] Using USB ($SERIAL)"
else
    echo "[*] Connecting WiFi ADB ($WIFI_SERIAL)..."
    adb connect "$WIFI_SERIAL" >/dev/null 2>&1 || true
    sleep 1
    if adb_ok "$WIFI_SERIAL"; then
        SERIAL="$WIFI_SERIAL"
        echo "[*] Using WiFi ($SERIAL)"
    else
        echo "ERROR: Cannot connect" >&2; exit 1
    fi
fi

echo "╔══════════════════════════════════════════╗"
echo "║  Echo Dot 2 → Mac Microphone (BlackHole) ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# Clean up any leftovers from previous run
pkill -f "nc.*$TCP_PORT" 2>/dev/null || true
kill_echo_mic
kill_mic_guard

# Set mic gain
adb -s "$SERIAL" shell "su -c 'tinymix 92 60 60; tinymix 110 60 60; tinymix 128 60 60; tinymix 146 60 60'" 2>/dev/null || true

# Free the mic
free_mic

echo "[*] Waiting for microphone..."
wait_for_mic_closed || exit 1

echo "[*] Streaming 8-mic array → BlackHole 2ch (volume x${GAIN})"
echo "[*] Select 'BlackHole 2ch' as microphone in your apps"
echo "[*] Press Ctrl+C to stop"
echo ""

FFMPEG_FILTER="pan=mono|c0=0.125*c0+0.125*c1+0.125*c2+0.125*c3+0.125*c4+0.125*c5+0.125*c6+0.125*c7,volume=${GAIN},aresample=48000,aformat=sample_fmts=s16:channel_layouts=stereo"

if [ "$SERIAL" = "$WIFI_SERIAL" ]; then
    LOCAL_IP=$(ipconfig getifaddr en1 2>/dev/null || ipconfig getifaddr en0 2>/dev/null || true)
    echo "[*] WiFi mode: Echo Dot → TCP $LOCAL_IP:$TCP_PORT → BlackHole"
    nc -l "$TCP_PORT" | \
    ffmpeg -hide_banner -loglevel warning \
        -f s24le -ar 16000 -ac 9 -i pipe:0 \
        -filter_complex "$FFMPEG_FILTER" \
        -f audiotoolbox -audio_device_index "$BLACKHOLE_INDEX" - &
    STREAM_PID=$!
    # Wait for nc to be listening
    for i in $(seq 1 10); do
        lsof -nP -iTCP:$TCP_PORT -sTCP:LISTEN >/dev/null 2>&1 && break
        sleep 0.5
    done
    adb -s "$SERIAL" shell "su -c '$DEVICE_BIN $LOCAL_IP $TCP_PORT 0'" &
else
    echo "[*] USB mode: exec-out → BlackHole"
    adb -s "$SERIAL" exec-out "su -c '$DEVICE_BIN stdout 0'" | \
    ffmpeg -hide_banner -loglevel warning \
        -f s24le -ar 16000 -ac 9 -i pipe:0 \
        -filter_complex "$FFMPEG_FILTER" \
        -f audiotoolbox -audio_device_index "$BLACKHOLE_INDEX" - &
    STREAM_PID=$!
fi

wait $STREAM_PID
