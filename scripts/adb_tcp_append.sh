
# ---- Echo Dot mic_guard startup (managed by setup.sh) ----
(
    LOG=/data/adb/mic_disable.log
    MIC_GUARD=/data/local/tmp/mic_guard
    STATUS=/proc/asound/card0/pcm24c/sub0/status

    echo "[BOOT] mic_guard startup begin at $(date)" >> "$LOG"
    sleep 45

    tinymix 92 60 60 >> "$LOG" 2>&1
    tinymix 110 60 60 >> "$LOG" 2>&1
    tinymix 128 60 60 >> "$LOG" 2>&1
    tinymix 146 60 60 >> "$LOG" 2>&1

    if [ ! -x "$MIC_GUARD" ]; then
        echo "[BOOT] missing executable: $MIC_GUARD" >> "$LOG"
        exit 1
    fi

    if ps | grep '[m]ic_guard' >/dev/null 2>&1; then
        echo "[BOOT] mic_guard already running at $(date)" >> "$LOG"
        exit 0
    fi

    if [ -r "$STATUS" ]; then
        owner_pid=$(grep owner_pid "$STATUS" 2>/dev/null | cut -d: -f2 | tr -d ' \r')
        if [ -n "$owner_pid" ] && [ "$owner_pid" -gt 1 ] 2>/dev/null; then
            kill -9 "$owner_pid" >> "$LOG" 2>&1 || true
            echo "[BOOT] killed initial mic owner pid=$owner_pid" >> "$LOG"
        fi
    else
        echo "[BOOT] status path not ready: $STATUS" >> "$LOG"
    fi

    if [ -x /data/adb/magisk/busybox ]; then
        /data/adb/magisk/busybox nohup "$MIC_GUARD" >> "$LOG" 2>&1 &
    else
        nohup "$MIC_GUARD" >> "$LOG" 2>&1 &
    fi
    echo "[BOOT] mic_guard launch requested at $(date)" >> "$LOG"
) >> /data/adb/mic_disable.log 2>&1 &
# ---- end Echo Dot mic_guard startup ----
