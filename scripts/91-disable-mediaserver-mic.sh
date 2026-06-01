#!/data/adb/magisk/busybox sh

# Wait for system to fully boot
sleep 30

# Set mic gain
tinymix 92 60 60
tinymix 110 60 60
tinymix 128 60 60
tinymix 146 60 60

# Start mic guard daemon (keeps mediaserver away from the mic array)
/data/local/tmp/mic_guard &

echo "[BOOT] mic-guard started at $(date)" >> /data/adb/mic_disable.log
