# Cross-compile for arm64 Android using NDK
# Usage: make NDK=/path/to/ndk

NDK ?= $(HOME)/Library/Android/sdk/ndk/21.1.6352462
CC   = $(NDK)/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android21-clang
CFLAGS = -static -O2

all: bin/echo_mic_arm64 bin/mic_guard_arm64

bin/echo_mic_arm64: src/echo_mic.c
	$(CC) $(CFLAGS) -o $@ $<

bin/mic_guard_arm64: src/mic_guard.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f bin/echo_mic_arm64 bin/mic_guard_arm64

.PHONY: all clean
