# Echo Dot 2 (AEOBC) Device State Backup
# Date: 2026-05-31
# Serial: G090LF0965021FUG
# Model: AEOBC (Echo Dot 2nd Gen)
# Build: LVY48F (Fire OS, Android 5.1 based)

## Audio Hardware
- Sound card: mt-snd-card (MediaTek)
- Mic array: TLV320AIC3101 (4x TI ADC chips = 8 mics + 1 ref = 9 channels)
- PCM device: card 0, device 24, capture
- Format: S24_3LE, 9 channels, 16000 Hz
- Owner PID: mediaserver (AudioIn_E thread)

## Key Processes Using Audio
- PID 261: /system/bin/mediaserver
- PID 944: amazon.speech.sim (Alexa voice/wakeword)
- PID 1255: amazon.speech.davs.davcservice
- PID 2331: com.amazon.device.echoaudioservice
- PID 2134: audio_overrun_m (kernel)

## Recovery Commands
# If anything goes wrong, reboot the device:
#   adb -s G090LF0965021FUG reboot
#
# All services are system services and will restart on reboot.
# We are NOT modifying any files on the device, only stopping/starting services.

## Tinymix Key Settings (for recovery reference)
# ADC_A through ADC_D are the 4 TLV320AIC3101 chips (2 channels each = 8 mics)
# All ADC_x Left Mute: Off
# All ADC_x Right Mute: Off
# All ADC_x MICPGA Volume Ctrl: 40
# All ADC_x Digital Volume Control: 88
# Board Channel Config: MonoRight
