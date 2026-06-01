#!/bin/bash
# ============================================================
# Echo Dot 2 麦克风 — 一键初始化脚本
# 首次使用时运行一次，之后直接用 echo_dot_mic.sh 即可
# ============================================================
set -euo pipefail

ECHO_IP="192.168.31.89"
ADB_PORT="5555"
SERIAL="${ECHO_IP}:${ADB_PORT}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔══════════════════════════════════════════╗"
echo "║     Echo Dot 2 麦克风 — 一键初始化       ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# 1. ADB 连接
echo "[1/5] 连接 ADB..."
adb connect "$SERIAL" >/dev/null 2>&1 || true
sleep 1
if ! adb -s "$SERIAL" shell "echo ok" >/dev/null 2>&1; then
    echo "WiFi ADB 失败，尝试 USB..."
    SERIAL=$(adb devices | grep -v "List\|emulator\|^$" | awk '{print $1}' | head -1)
    [ -z "$SERIAL" ] && { echo "ERROR: 找不到设备，请检查 ADB 连接"; exit 1; }
fi
echo "    已连接: $SERIAL"

# 2. 推送二进制文件
echo "[2/5] 推送 echo_mic 和 mic_guard 到设备..."
adb -s "$SERIAL" push "$SCRIPT_DIR/bin/echo_mic_arm64" /data/local/tmp/echo_mic
adb -s "$SERIAL" push "$SCRIPT_DIR/bin/mic_guard_arm64" /data/local/tmp/mic_guard
adb -s "$SERIAL" shell "su -c 'chmod 755 /data/local/tmp/echo_mic /data/local/tmp/mic_guard'"

# 3. 安装 Magisk 开机脚本（追加到已有的 adb_tcp.sh）
echo "[3/5] 安装开机自启动脚本..."
BOOT_SCRIPT="/data/adb/service.d/adb_tcp.sh"
# 检查是否已经安装过
if adb -s "$SERIAL" shell "su -c 'grep -q mic_guard $BOOT_SCRIPT 2>/dev/null && echo yes || echo no'" | grep -q "yes"; then
    echo "    开机脚本已存在，跳过"
else
    adb -s "$SERIAL" push "$SCRIPT_DIR/scripts/adb_tcp_append.sh" /data/local/tmp/
    adb -s "$SERIAL" shell "su -c 'cat /data/local/tmp/adb_tcp_append.sh >> $BOOT_SCRIPT'"
    echo "    已追加到 $BOOT_SCRIPT"
fi

# 4. 立即启动 mic_guard（无需重启）
echo "[4/5] 启动 mic_guard 守护进程..."
adb -s "$SERIAL" shell "su -c 'tinymix 92 60 60; tinymix 110 60 60; tinymix 128 60 60; tinymix 146 60 60'"
# Kill mediaserver first
MSPID=$(adb -s "$SERIAL" shell "ps | grep '/system/bin/mediaserver' | grep -v grep" | awk '{print $2}' | tr -d '\r')
[ -n "$MSPID" ] && adb -s "$SERIAL" shell "su -c 'kill -9 $MSPID'" 2>/dev/null || true
adb -s "$SERIAL" shell "su -c '/data/local/tmp/mic_guard'" &
sleep 6

# 5. 验证
echo "[5/5] 验证..."
STATUS=$(adb -s "$SERIAL" shell "cat /proc/asound/card0/pcm24c/sub0/status 2>&1")
if echo "$STATUS" | grep -q "closed"; then
    echo "    ✅ 麦克风已释放，mic_guard 运行正常"
else
    echo "    ⚠️  麦克风状态: $(echo "$STATUS" | head -1)"
    echo "    请等待几秒后重试，或手动运行: adb shell 'su -c /data/local/tmp/mic_guard &'"
fi

echo ""
echo "初始化完成！现在可以运行:"
echo "  ./scripts/echo_dot_mic.sh"
echo ""
echo "在任何 App 里选择 'BlackHole 2ch' 作为麦克风即可使用。"
