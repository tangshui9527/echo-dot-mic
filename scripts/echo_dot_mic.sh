#!/bin/bash
set -euo pipefail

# ============================================================
# Echo Dot 2 麦克风阵列 → Mac 虚拟麦克风 (BlackHole 2ch)
# 用法: ./echo_dot_mic.sh
# 停止: Ctrl+C (自动恢复 Echo Dot 的 media 服务)
# ============================================================

SERIAL="G090LF0965021FUG"
ECHO_IP="192.168.31.89"
ADB_PORT="5555"
DEVICE_BIN="/data/local/tmp/echo_mic"
GAIN=10                    # 音量放大倍数
BLACKHOLE_INDEX=1          # BlackHole 的 audiotoolbox 设备索引
STREAM_PID=""

adb_ok() {
    adb -s "$1" shell "echo ok" >/dev/null 2>&1
}

# Kill a process on the device by matching its full path
device_kill() {
    local match="$1"
    # Extract just the filename without basename command
    local name="${match##*/}"
    adb -s "$SERIAL" shell "su -c '/data/adb/magisk/busybox killall -9 $name 2>/dev/null; true'" 2>/dev/null || true
}

kill_mic_guard() { device_kill "/data/local/tmp/mic_guard"; }
kill_echo_mic()  {
    # Also kill via PCM owner_pid (most reliable)
    local owner
    owner=$(adb -s "$SERIAL" shell "cat /proc/asound/card0/pcm24c/sub0/status 2>/dev/null" | grep owner_pid | cut -d: -f2 | tr -d ' \r' || true)
    [ -n "$owner" ] && [ "$owner" -gt 1 ] 2>/dev/null && \
        adb -s "$SERIAL" shell "su -c 'kill -9 $owner'" 2>/dev/null || true
    device_kill "/data/local/tmp/echo_mic"
}

kill_mediaserver() {
    adb -s "$SERIAL" shell "su -c 'stop media; setprop ctl.stop media'" 2>/dev/null || true
    local owner
    owner=$(adb -s "$SERIAL" shell "cat /proc/asound/card0/pcm24c/sub0/status 2>/dev/null" | grep owner_pid | cut -d: -f2 | tr -d ' \r' || true)
    [ -n "$owner" ] && [ "$owner" -gt 1 ] 2>/dev/null && \
        adb -s "$SERIAL" shell "su -c 'kill -9 $owner'" 2>/dev/null || true
}

wait_for_mic_closed() {
    local status owner
    for i in $(seq 1 30); do
        status=$(adb -s "$SERIAL" shell "cat /proc/asound/card0/pcm24c/sub0/status 2>&1")
        if echo "$status" | grep -q closed; then
            return 0
        fi

        owner=$(echo "$status" | grep owner_pid | cut -d: -f2 | tr -d ' \r' || true)
        if [ -n "$owner" ] && [ "$owner" -gt 1 ] 2>/dev/null; then
            echo "[*] Microphone busy, owner thread PID $owner; stopping media service..."
        fi
        adb -s "$SERIAL" shell "su -c 'setprop ctl.stop media; stop media'" 2>/dev/null || true
        kill_mediaserver
        sleep 1
    done

    status=$(adb -s "$SERIAL" shell "cat /proc/asound/card0/pcm24c/sub0/status 2>&1")
    echo "ERROR: Microphone is still busy; refusing to start empty stream." >&2
    echo "$status" >&2
    return 1
}

# Prefer USB if the cable is connected; fall back to WiFi ADB.
USB_SERIAL="G090LF0965021FUG"
WIFI_SERIAL="$ECHO_IP:$ADB_PORT"
if adb_ok "$USB_SERIAL"; then
    SERIAL="$USB_SERIAL"
    echo "[*] Using USB connection ($SERIAL)"
else
    echo "[*] USB not available; connecting WiFi ADB ($WIFI_SERIAL)..."
    adb connect "$WIFI_SERIAL" >/dev/null 2>&1 || true
    sleep 1
    if adb_ok "$WIFI_SERIAL"; then
        SERIAL="$WIFI_SERIAL"
        echo "[*] Using WiFi connection ($SERIAL)"
    else
        echo "ERROR: Cannot connect to Echo Dot via USB or WiFi" >&2
        exit 1
    fi
fi

cleanup() {
    echo ""
    echo "Stopping stream..."
    [ -n "$STREAM_PID" ] && kill "$STREAM_PID" 2>/dev/null || true
    kill_echo_mic
    kill_mic_guard
    adb -s "$SERIAL" shell "su -c 'setprop ctl.start media; start media'" 2>/dev/null || true
    echo "Done. media service restored."
}
trap cleanup EXIT INT TERM

echo "╔══════════════════════════════════════════╗"
echo "║  Echo Dot 2 → Mac Microphone (BlackHole) ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# Kill any leftover processes from a previous run
pkill -f "nc.*54399" 2>/dev/null || true
kill_echo_mic
kill_mic_guard

# Boost hardware mic gain BEFORE stopping media service
adb -s "$SERIAL" shell "su -c 'tinymix 92 60 60; tinymix 110 60 60; tinymix 128 60 60; tinymix 146 60 60'" 2>/dev/null

# Clear stale capture processes left by interrupted shell/ADB sessions.
kill_echo_mic

# Stop the Android media service cleanly while using the mic. It is not a kernel-critical
# process, but Alexa/system audio will be unavailable until cleanup restores it.
adb -s "$SERIAL" shell "su -c 'setprop ctl.stop media; stop media'" 2>/dev/null || true
kill_mediaserver

# Wait for mic to be free
echo "[*] Waiting for microphone..."
wait_for_mic_closed

# Stream: Echo Dot mic → ADB → ffmpeg → BlackHole
echo "[*] Streaming 8-mic array (beamformed) → BlackHole 2ch (volume x${GAIN})"
echo "[*] Select 'BlackHole 2ch' as microphone in your apps"
echo "[*] Press Ctrl+C to stop"
echo ""

FFMPEG_FILTER="pan=mono|c0=0.125*c0+0.125*c1+0.125*c2+0.125*c3+0.125*c4+0.125*c5+0.125*c6+0.125*c7,volume=${GAIN},aresample=48000,aformat=sample_fmts=s16:channel_layouts=stereo"

if [ "$SERIAL" = "$ECHO_IP:$ADB_PORT" ]; then
    # WiFi: echo_mic connects directly to Mac via TCP (bypasses ADB exec-out bottleneck)
    LOCAL_IP=$(ipconfig getifaddr en1 2>/dev/null || ipconfig getifaddr en0 2>/dev/null)
    TCP_PORT=54399
    echo "[*] WiFi mode: Echo Dot → TCP $LOCAL_IP:$TCP_PORT → ffmpeg"
    # Start nc listener + ffmpeg pipeline FIRST, then start echo_mic on device
    nc -l "$TCP_PORT" | \
    ffmpeg -hide_banner -loglevel warning \
        -f s24le -ar 16000 -ac 9 -i pipe:0 \
        -filter_complex "$FFMPEG_FILTER" \
        -f audiotoolbox -audio_device_index "$BLACKHOLE_INDEX" - &
    STREAM_PID=$!
    # Wait until nc is actually listening before telling device to connect
    for i in $(seq 1 10); do
        lsof -nP -iTCP:$TCP_PORT -sTCP:LISTEN >/dev/null 2>&1 && break
        sleep 0.5
    done
    adb -s "$SERIAL" shell "su -c '$DEVICE_BIN $LOCAL_IP $TCP_PORT 0'" &
else
    # USB: exec-out is fast and reliable
    echo "[*] USB mode: exec-out → ffmpeg"
    adb -s "$SERIAL" exec-out "su -c '$DEVICE_BIN stdout 0'" | \
    ffmpeg -hide_banner -loglevel warning \
        -f s24le -ar 16000 -ac 9 -i pipe:0 \
        -filter_complex "$FFMPEG_FILTER" \
        -f audiotoolbox -audio_device_index "$BLACKHOLE_INDEX" - &
    STREAM_PID=$!
fi

wait $STREAM_PID
