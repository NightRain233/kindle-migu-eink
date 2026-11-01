#!/usr/bin/env bash
# 构建按应用刷新助手：JNI 库（NDK 17）+ Java 主程序（javac 1.8 → dx）
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SDK="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
NDK="${ANDROID_NDK_ROOT:-$SDK/ndk/17.2.4988734}"
OUT="$HERE/build"
mkdir -p "$OUT/classes"

CLANG="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/clang++"
"$CLANG" --target=armv7a-linux-androideabi22 \
  --gcc-toolchain="$NDK/toolchains/arm-linux-androideabi-4.9/prebuilt/darwin-x86_64" \
  --sysroot="$NDK/platforms/android-22/arch-arm" -D__ANDROID_API__=22 \
  -std=c++11 -fPIC -shared -O2 -fno-exceptions -fno-rtti \
  -I"$NDK/sysroot/usr/include/arm-linux-androideabi" -I"$NDK/sysroot/usr/include" \
  -o "$OUT/libeanabwave.so" "$HERE/native/eanabwave.cpp" -llog -ldl

javac -source 1.7 -target 1.7 -encoding UTF-8 \
  -bootclasspath "$SDK/platforms/android-26/android.jar" \
  -d "$OUT/classes" "$HERE/src/EanabWaveHelper.java" 2>&1 | grep -v "bootstrap classpath" || true
"$SDK/build-tools/27.0.1/dx" --dex --output="$OUT/eanab-wave.dex" "$OUT/classes"
ls -l "$OUT/libeanabwave.so" "$OUT/eanab-wave.dex"
