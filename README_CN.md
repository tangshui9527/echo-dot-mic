# Echo Dot 2 变身电脑麦克风

用一台已 root 的 Amazon Echo Dot 2 代替电脑麦克风，实时通过 ADB 把 8 麦克风阵列的音频流到 Mac，让任何 App 都能把它当麦克风用。

---

## 核心思路

### 问题是什么

Echo Dot 2 有一个 8 麦克风阵列（TI TLV320AIC3101 芯片），音质远超普通麦克风。但它被 Amazon 的 `mediaserver` 进程永久占用，用来做 Alexa 唤醒词检测。

我们想把这个麦克风阵列的音频实时传到电脑，让电脑把它当系统麦克风用。

### 第一性原理分析

把问题拆解到最底层：

```
目标：手机/音箱麦克风 → 电脑系统麦克风
本质：一个设备产生 PCM 音频数据 → 通过某种管道 → 写入电脑的虚拟音频设备
最短路径：ADB 本身就是一条数据管道，不需要任何额外软件
```

所以整条链路是：

```
Echo Dot 麦克风硬件
    → 自编译的 echo_mic 工具直接读 ALSA 设备（绕过 Android 权限框架）
    → stdout 输出 raw PCM
    → adb exec-out 管道传到 Mac（零额外软件）
    → ffmpeg 混合 8 路信号 + 放大 + 重采样到 48kHz
    → BlackHole 2ch 虚拟音频设备
    → 系统麦克风输入（任何 App 都能用）
```

### 为什么不用现成工具

- **tinycap**（设备自带）：不支持 `S24_3LE` 格式（Echo Dot 麦克风的硬件格式），只支持 16-bit
- **AndroidMic App**：需要在手机上安装 App，Echo Dot 没有 Google Play
- **scrcpy --audio-source=mic**：理论可行，但输出到扬声器而不是虚拟音频设备，需要额外处理

所以我们自己写了一个 100 行的 C 程序，直接用 Linux ALSA ioctl 读取麦克风数据。

---

## 硬件信息

| 项目 | 详情 |
|------|------|
| 设备 | Amazon Echo Dot 2nd Gen（代号 biscuit，型号 AEOBC） |
| 主控 | MediaTek MT8163 |
| 麦克风芯片 | TLV320AIC3101 × 4（德州仪器） |
| 麦克风数量 | 8 个（环形阵列 7 个 + 中心 1 个）+ 1 个参考通道 |
| ALSA 设备 | card 0, device 24（`/dev/snd/pcmC0D24c`） |
| 音频格式 | S24_3LE（24-bit，3字节，小端序） |
| 采样率 | 16000 Hz（硬件固定，无法更改） |
| 通道数 | 9（8 麦克风 + 1 参考） |

---

## 前置条件

**Mac 端：**
- [BlackHole 2ch](https://existential.audio/blackhole/) 虚拟音频驱动
- `ffmpeg`（`brew install ffmpeg`）
- ADB（`brew install android-platform-tools`）

**Echo Dot 端：**
- 已 root（Magisk），参考 [XDA 教程](https://xdaforums.com/t/unlock-root-twrp-unbrick-amazon-echo-dot-2nd-gen-2016-biscuit.4761416/)
- WiFi ADB 已开启（TCP 5555 端口）

---

## 一步步操作

### 第一步：首次初始化（只需做一次）

```bash
cd EchoDotMic
./setup.sh
```

这个脚本会自动完成：
1. 连接 ADB（WiFi 优先，USB 备用）
2. 把 `echo_mic` 和 `mic_guard` 推送到设备
3. 在 Magisk 开机脚本里追加 mic_guard 自启动
4. 立即启动 mic_guard，释放麦克风

### 第二步：每次使用

```bash
./scripts/echo_dot_mic.sh
```

然后在任何 App（微信、Discord、Zoom、Typeless 语音输入等）里，把麦克风输入选成 **BlackHole 2ch** 即可。

按 `Ctrl+C` 停止，mediaserver 自动恢复。

---

## 关键技术细节

### 为什么 mediaserver 会一直重启

Android 的 `init` 进程管理所有系统服务。`mediaserver` 在 `/init.base.rc` 里定义为 `class main`，被杀后 `init` 会在约 1 秒内自动重启它，重启后它会立刻重新打开麦克风设备。

### mic_guard 的作用

`mic_guard` 是一个常驻守护进程，每 2 秒检查一次 `/proc/asound/card0/pcm24c/sub0/status`，如果发现麦克风被占用（`state: RUNNING`），就读取 `owner_pid` 并 kill 掉那个进程。

这样 mediaserver 虽然会不断重启，但每次抢到麦克风后 2 秒内就会被杀掉，麦克风始终保持空闲。

### 为什么用 8 路混合而不是单通道

8 个麦克风同时录音，对同一个声源的信号做平均，可以：
- 信噪比提升约 9dB（约 3 倍）
- 抑制随机噪声
- 效果相当于一个全向波束成形

通道 8（参考通道）是扬声器的回声参考信号，不是麦克风，所以跳过。

### 音频格式转换链

```
S24_3LE, 9ch, 16kHz（硬件原始）
    → ffmpeg pan filter: 8路平均 → mono
    → volume 10x（硬件增益已调到 60/127）
    → aresample: 16kHz → 48kHz
    → S16LE, stereo, 48kHz（BlackHole 输入）
```

---

## 调试

### 检查麦克风是否空闲

```bash
adb shell "cat /proc/asound/card0/pcm24c/sub0/status"
# closed = 空闲，RUNNING = 被占用
```

### 查看谁在占用麦克风

```bash
# 找到 owner_pid
adb shell "cat /proc/asound/card0/pcm24c/sub0/status"
# 查看是什么进程
adb shell "cat /proc/<owner_pid>/cmdline"
```

### 手动释放麦克风

```bash
adb shell "su -c 'kill -9 <owner_pid>'"
```

### 测试录音（不启动实时流）

```bash
# 录 10 秒
adb shell "su -c '/data/local/tmp/echo_mic 10'" > /tmp/test.raw

# 转换并播放
ffmpeg -f s24le -ar 16000 -ac 9 -i /tmp/test.raw \
  -filter_complex "pan=mono|c0=0.125*c0+0.125*c1+0.125*c2+0.125*c3+0.125*c4+0.125*c5+0.125*c6+0.125*c7,volume=10" \
  /tmp/test.wav && afplay /tmp/test.wav
```

### 调整音量

软件增益：修改 `scripts/echo_dot_mic.sh` 里的 `GAIN=10`

硬件增益（MICPGA，范围 0-127，默认 40，我们用 60）：
```bash
adb shell "su -c 'tinymix 92 80 80'"   # ADC_A（麦克风 1-2）
adb shell "su -c 'tinymix 110 80 80'"  # ADC_B（麦克风 3-4）
adb shell "su -c 'tinymix 128 80 80'"  # ADC_C（麦克风 5-6）
adb shell "su -c 'tinymix 146 80 80'"  # ADC_D（麦克风 7-8）
```

---

## 恢复

如果出现任何问题，重启 Echo Dot 即可恢复所有 Amazon 服务：

```bash
adb shell "su -c 'reboot'"
```

我们没有修改任何系统分区（`/system` 是只读的）。所有文件都在 `/data/local/tmp/`（二进制）和 `/data/adb/service.d/`（Magisk 脚本），删除这些文件并重启即可完全还原。

---

## 局限性

- **采样率固定 16kHz**：硬件限制，适合语音，不适合音乐
- **需要 root**：无法在未 root 的设备上使用
- **Alexa 功能暂停**：使用麦克风期间 Alexa 语音功能不可用，停止后自动恢复
- **WiFi 延迟**：约 20-50ms，语音输入完全够用
