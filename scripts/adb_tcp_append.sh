
# ---- Echo Dot 麦克风守护进程 (由 setup.sh 追加) ----
tinymix 92 60 60
tinymix 110 60 60
tinymix 128 60 60
tinymix 146 60 60
/data/local/tmp/mic_guard &
echo "[BOOT] mic-guard started at $(date)" >> /data/adb/mic_disable.log
