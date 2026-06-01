# 交接文档 — 未解决问题

日期：2026-06-01

---

## 未解决问题：mic_guard 开机自启动不生效

### 现象

每次 Echo Dot 重启后，`mic_guard` 守护进程没有自动启动，麦克风仍被 `mediaserver` 占用。需要手动运行以下命令才能释放麦克风：

```bash
adb shell "su -c 'kill -9 <mediaserver_pid>; /data/local/tmp/mic_guard &'"
```

### 已确认正常的部分

- `mic_guard` 二进制本身工作正常（手动启动后能持续杀掉 mediaserver，保持麦克风空闲）
- `echo_dot_mic.sh` 实时流功能正常（WiFi ADB + ffmpeg → BlackHole）
- 音频质量可用（8 麦克风混合，16kHz，语音识别够用）

### 已尝试的自启动方案

**方案 1：独立 Magisk service.d 脚本（失败）**

创建 `/data/adb/service.d/91-disable-mediaserver-mic.sh`，shebang 分别试过：
- `#!/system/bin/sh` → 不执行
- `#!/data/adb/magisk/busybox sh` → 不执行

手动 `sh` 执行该脚本完全正常，但 Magisk 开机时不触发它。原因未知，可能是该 Magisk 版本对 service.d 脚本有命名或格式限制。

**方案 2：追加到已有的 adb_tcp.sh（待验证）**

`adb_tcp.sh` 是设备上已有的、能正常执行的 Magisk service.d 脚本。在其末尾追加了 mic_guard 启动命令。最后一次重启时被中断，尚未完成验证。

当前 `/data/adb/service.d/adb_tcp.sh` 末尾应该已经包含：

```sh
tinymix 92 60 60
tinymix 110 60 60
tinymix 128 60 60
tinymix 146 60 60
/data/local/tmp/mic_guard &
echo "[BOOT] mic-guard started at $(date)" >> /data/adb/mic_disable.log
```

### 下一步验证步骤

**步骤 1：确认 adb_tcp.sh 内容是否正确**

```bash
adb shell "su -c 'cat /data/adb/service.d/adb_tcp.sh'"
```

末尾应该有 mic_guard 相关内容。如果没有，重新追加：

```bash
adb push scripts/adb_tcp_append.sh /data/local/tmp/
adb shell "su -c 'cat /data/local/tmp/adb_tcp_append.sh >> /data/adb/service.d/adb_tcp.sh'"
```

**步骤 2：重启并等待 60 秒后检查**

```bash
adb shell "su -c 'reboot'"
# 等待 60 秒
adb connect 192.168.31.89:5555
adb shell "su -c 'cat /data/adb/mic_disable.log'"          # 看日志时间是否更新
adb shell "su -c 'ps | grep mic_guard | grep -v grep'"     # 看进程是否存在
adb shell "cat /proc/asound/card0/pcm24c/sub0/status"      # 看麦克风是否 closed
```

**步骤 3：如果 adb_tcp.sh 方案也不行**

可能是 `adb_tcp.sh` 里的 `sleep 25` 之后 mic_guard 启动时 ALSA 还没初始化，导致 mic_guard 内部的 `sleep 10` 结束后找不到 `/proc/asound/...` 而退出。

尝试在 mic_guard 里加更长的初始等待，或者在 adb_tcp.sh 里加 `sleep 15` 再启动 mic_guard：

```sh
sleep 15
/data/local/tmp/mic_guard &
```

**步骤 4：备选方案 — 用 init.d**

部分 Magisk 版本支持 `/system/etc/init.d/`，可以试试：

```bash
adb shell "su -c 'mount -o remount,rw /system'"
adb shell "su -c 'cp /data/local/tmp/adb_tcp_append.sh /system/etc/init.d/99-mic-guard && chmod 755 /system/etc/init.d/99-mic-guard'"
adb shell "su -c 'mount -o remount,ro /system'"
```

注意：修改 `/system` 有风险，OTA 更新会覆盖。

### 临时解决方案（当前可用）

每次重启后，运行一次 `setup.sh` 即可手动启动 mic_guard：

```bash
./setup.sh
```

或者直接：

```bash
adb connect 192.168.31.89:5555
adb shell "su -c 'kill -9 \$(cat /proc/asound/card0/pcm24c/sub0/status | grep owner_pid | cut -d: -f2 | tr -d \" \r\"); /data/local/tmp/mic_guard &'"
```

---

## 设备信息

| 项目 | 值 |
|------|----|
| 设备序列号 | G090LF0965021FUG |
| WiFi IP | 192.168.31.89 |
| ADB 端口 | 5555 |
| 系统 | Fire OS (Android 5.1, kernel 3.18.19) |
| Magisk | 已安装，service.d 路径 `/data/adb/service.d/` |
| echo_mic 路径 | `/data/local/tmp/echo_mic` |
| mic_guard 路径 | `/data/local/tmp/mic_guard` |

## 文件说明

| 文件 | 说明 |
|------|------|
| `setup.sh` | 一键初始化（推送二进制 + 启动 mic_guard） |
| `scripts/echo_dot_mic.sh` | 每次使用时运行，实时流到 BlackHole |
| `scripts/adb_tcp_append.sh` | 追加到 Magisk 开机脚本的内容 |
| `bin/echo_mic_arm64` | ALSA 录音工具（arm64 预编译） |
| `bin/mic_guard_arm64` | 麦克风守护进程（arm64 预编译） |
| `src/echo_mic.c` | echo_mic 源码 |
| `src/mic_guard.c` | mic_guard 源码 |
