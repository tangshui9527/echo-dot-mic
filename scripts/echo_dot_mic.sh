#!/bin/bash
set -euo pipefail

# ============================================================
# Echo Dot 2 麦克风阵列 → Mac 虚拟麦克风 (BlackHole 2ch)
# 用法: ./echo_dot_mic.sh
# 停止: Ctrl+C (自动恢复 Echo Dot 的 mediaserver)
# ============================================================

SERIAL="G090LF0965021FUG"
ECHO_IP="192.168.31.89"
ADB_PORT="5555"
DEVICE_BIN="/data/local/tmp/echo_mic"
GAIN=10                    # 音量放大倍数
BLACKHOLE_INDEX=1          # BlackHole 的 audiotoolbox 设备索引

# Connect via WiFi ADB
echo "[*] Connecting WiFi ADB ($ECHO_IP:$ADB_PORT)..."
adb connect "$ECHO_IP:$ADB_PORT" >/dev/null 2>&1
sleep 1
SERIAL="$ECHO_IP:$ADB_PORT"

if ! adb -s "$SERIAL" shell "echo ok" >/dev/null 2>&1; then
    # Fallback to USB
    SERIAL="G090LF0965021FUG"
    if ! adb -s "$SERIAL" shell "echo ok" >/dev/null 2>&1; then
        echo "ERROR: Cannot connect to Echo Dot via WiFi or USB" >&2
        exit 1
    fi
    echo "[*] Using USB connection"
else
    echo "[*] Using WiFi connection"
fi

cleanup() {
    echo ""
    echo "Stopping stream..."
    kill $STREAM_PID 2>/dev/null || true
    adb -s "$SERIAL" shell "su -c 'setprop ctl.start mediaserver'" 2>/dev/null || true
    echo "Done. mediaserver restored."
}
trap cleanup EXIT INT TERM

echo "╔══════════════════════════════════════════╗"
echo "║  Echo Dot 2 → Mac Microphone (BlackHole) ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# Boost hardware mic gain BEFORE killing mediaserver
adb -s "$SERIAL" shell "su -c 'tinymix 92 60 60; tinymix 110 60 60; tinymix 128 60 60; tinymix 146 60 60'" 2>/dev/null

# Ensure mic_guard is running (kills mediaserver if it grabs the mic)
if ! adb -s "$SERIAL" shell "su -c 'ps | grep mic_guard | grep -v grep'" | grep -q mic_guard; then
    MSPID=$(adb -s "$SERIAL" shell "ps | grep '/system/bin/mediaserver' | grep -v grep" | awk '{print $2}' | tr -d '\r')
    [ -n "$MSPID" ] && adb -s "$SERIAL" shell "su -c 'kill -9 $MSPID'"
    adb -s "$SERIAL" shell "su -c '/data/local/tmp/mic_guard &'"
fi

# Wait for mic to be free
echo "[*] Waiting for microphone..."
for i in $(seq 1 10); do
    if adb -s "$SERIAL" shell "cat /proc/asound/card0/pcm24c/sub0/status 2>&1" | grep -q closed; then
        break
    fi
    sleep 2
done

# Stream: Echo Dot mic → ADB → ffmpeg → BlackHole
echo "[*] Streaming 8-mic array (beamformed) → BlackHole 2ch (volume x${GAIN})"
echo "[*] Select 'BlackHole 2ch' as microphone in your apps"
echo "[*] Press Ctrl+C to stop"
echo ""

# pan filter: average channels 0-7 (8 mics), skip channel 8 (reference)
adb -s "$SERIAL" exec-out "su -c '$DEVICE_BIN 0'" | \
ffmpeg -hide_banner -loglevel warning \
    -f s24le -ar 16000 -ac 9 -i pipe:0 \
    -filter_complex "pan=mono|c0=0.125*c0+0.125*c1+0.125*c2+0.125*c3+0.125*c4+0.125*c5+0.125*c6+0.125*c7,volume=${GAIN},aresample=48000,aformat=sample_fmts=s16:channel_layouts=stereo" \
    -f audiotoolbox -audio_device_index "$BLACKHOLE_INDEX" - &
STREAM_PID=$!

wait $STREAM_PID
