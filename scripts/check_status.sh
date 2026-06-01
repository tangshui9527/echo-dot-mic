#!/bin/bash
# Echo Dot 2 状态检查脚本
# 检查 mic_guard 是否运行、麦克风是否空闲、开机脚本是否正确

ECHO_IP="192.168.31.89"
ADB_PORT="5555"

# 连接
adb connect "$ECHO_IP:$ADB_PORT" >/dev/null 2>&1
SERIAL="$ECHO_IP:$ADB_PORT"
if ! adb -s "$SERIAL" shell "echo ok" >/dev/null 2>&1; then
    SERIAL=$(adb devices | grep -v "List\|emulator\|^$" | awk '{print $1}' | head -1)
fi
echo "设备: $SERIAL"
echo ""

echo "=== [1] PCM24 麦克风状态 ==="
STATUS=$(adb -s "$SERIAL" shell "cat /proc/asound/card0/pcm24c/sub0/status 2>&1")
echo "$STATUS"
if echo "$STATUS" | grep -q "closed"; then
    echo "✅ 麦克风空闲"
else
    OWNER=$(echo "$STATUS" | grep owner_pid | tr -d '\r' | awk '{print $3}')
    PROC=$(adb -s "$SERIAL" shell "cat /proc/$OWNER/cmdline 2>/dev/null" | tr -d '\0')
    echo "⚠️  被占用 — PID $OWNER ($PROC)"
fi

echo ""
echo "=== [2] mic_guard 进程 ==="
GUARD=$(adb -s "$SERIAL" shell "su -c 'ps | grep mic_guard | grep -v grep'")
if [ -n "$GUARD" ]; then
    echo "✅ mic_guard 运行中"
    echo "$GUARD"
else
    echo "❌ mic_guard 未运行"
fi

echo ""
echo "=== [3] 开机脚本内容 ==="
adb -s "$SERIAL" shell "su -c 'grep -n \"Echo Dot mic_guard startup\" /data/adb/service.d/adb_tcp.sh 2>/dev/null || echo \"❌ 未找到 managed 启动片段，请运行 ./setup.sh\"'"
echo ""
echo "--- mic_guard 相关片段 ---"
adb -s "$SERIAL" shell "su -c 'grep -En \"mic_guard|mic-guard\" /data/adb/service.d/adb_tcp.sh 2>/dev/null || true'"

echo ""
echo "=== [4] 开机日志 ==="
adb -s "$SERIAL" shell "su -c 'cat /data/adb/mic_disable.log 2>/dev/null || echo 无日志'"

echo ""
echo "=== [5] 二进制文件 ==="
adb -s "$SERIAL" shell "su -c 'ls -la /data/local/tmp/echo_mic /data/local/tmp/mic_guard 2>&1'"

if ! echo "$STATUS" | grep -q "closed" && [ -n "$GUARD" ]; then
    echo ""
    echo "=== 诊断 ==="
    echo "⚠️  mic_guard 进程存在但麦克风仍被占用。先运行 ../setup.sh 重新安装 managed 启动片段；如果仍复现，查看 /data/adb/mic_disable.log。"
fi
