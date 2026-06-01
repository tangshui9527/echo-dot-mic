# 交接文档 — mic_guard 开机自启动

日期：2026-06-01

---

## 已处理问题：mic_guard 开机自启动不稳定

### 原始现象

每次 Echo Dot 重启后，`mic_guard` 守护进程没有自动启动，麦克风仍被 `mediaserver` 占用。需要手动运行以下命令才能释放麦克风：

```bash
adb shell "su -c 'kill -9 <mediaserver_pid>; /data/local/tmp/mic_guard &'"
```

### 已确认正常的部分

- `mic_guard` 二进制本身工作正常（手动启动后能持续杀掉 mediaserver，保持麦克风空闲）
- `echo_dot_mic.sh` 实时流功能正常（WiFi ADB + ffmpeg → BlackHole）
- 音频质量可用（8 麦克风混合，16kHz，语音识别够用）

### 本次修复

- `scripts/adb_tcp_append.sh` 改为后台子 shell，先等待 45 秒，再设置 tinymix、杀掉初始麦克风 owner，并用 `nohup` 启动 `/data/local/tmp/mic_guard`
- `setup.sh` 改为检查固定 marker：`Echo Dot mic_guard startup (managed by setup.sh)`，避免旧坏片段里出现 `mic_guard` 字样时误判为已安装
- `setup.sh` 会确保 `/data/adb/service.d/adb_tcp.sh` 存在且可执行
- `src/mic_guard.c` 改为只杀 `mediaserver`，不再杀正在录音的 `echo_mic`
- `scripts/echo_dot_mic.sh` 开始录音前用 `ctl.stop mediaserver`，退出时先停 `mic_guard` 再恢复 `mediaserver`
- `scripts/91-disable-mediaserver-mic.sh` 同步为同一套启动逻辑，作为独立 `service.d` fallback
- `README.md` 已改为推荐 `./setup.sh` 和追加到已知可执行的 `adb_tcp.sh`

### 历史尝试记录

**方案 1：独立 Magisk service.d 脚本（失败过）**

创建 `/data/adb/service.d/91-disable-mediaserver-mic.sh`，shebang 分别试过：
- `#!/system/bin/sh` → 不执行
- `#!/data/adb/magisk/busybox sh` → 不执行

手动 `sh` 执行该脚本完全正常，但 Magisk 开机时不触发它。原因未知，可能是该 Magisk 版本对 service.d 脚本有命名或格式限制。

**方案 2：追加到已有的 adb_tcp.sh（已加固）**

`adb_tcp.sh` 是设备上已有的、能正常执行的 Magisk service.d 脚本。本次修复继续使用这个路径，但追加的内容改成延迟后台启动 + `nohup` + 日志。

当前 `/data/adb/service.d/adb_tcp.sh` 末尾应该包含 marker：

```sh
# ---- Echo Dot mic_guard startup (managed by setup.sh) ----
```

### 下一步验证步骤

**步骤 1：重新安装启动片段**

```bash
./setup.sh
```

**步骤 2：确认 adb_tcp.sh 内容是否正确**

```bash
adb shell "su -c 'grep -n \"Echo Dot mic_guard startup\" /data/adb/service.d/adb_tcp.sh'"
```

如果没有输出，重新运行 `./setup.sh`。

**步骤 3：重启并等待 70 秒后检查**

```bash
adb shell "su -c 'reboot'"
# 等待 70 秒
adb connect 192.168.31.89:5555
adb shell "su -c 'cat /data/adb/mic_disable.log'"          # 看日志是否出现 BOOT 记录
adb shell "su -c 'ps | grep \"[m]ic_guard\"'"             # 看进程是否存在
adb shell "cat /proc/asound/card0/pcm24c/sub0/status"      # 看麦克风是否 closed
```

**步骤 4：如果 adb_tcp.sh 方案仍不行**

先看日志：

```bash
adb shell "su -c 'cat /data/adb/mic_disable.log'"
```

重点确认是否有 `startup begin`、`missing executable`、`status path not ready` 或 `launch requested`。

**步骤 5：备选方案 — 用 init.d**

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
adb shell "su -c 'kill -9 \$(cat /proc/asound/card0/pcm24c/sub0/status | grep owner_pid | cut -d: -f2 | tr -d \" \r\"); nohup /data/local/tmp/mic_guard >> /data/adb/mic_disable.log 2>&1 &'"
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
| `setup.sh` | 一键初始化（推送二进制 + 安装开机片段 + 启动 mic_guard） |
| `scripts/echo_dot_mic.sh` | 每次使用时运行，实时流到 BlackHole |
| `scripts/adb_tcp_append.sh` | 追加到 Magisk 开机脚本的内容 |
| `scripts/91-disable-mediaserver-mic.sh` | 独立 Magisk service.d fallback |
| `bin/echo_mic_arm64` | ALSA 录音工具（arm64 预编译） |
| `bin/mic_guard_arm64` | 麦克风守护进程（arm64 预编译） |
| `src/echo_mic.c` | echo_mic 源码 |
| `src/mic_guard.c` | mic_guard 源码 |
