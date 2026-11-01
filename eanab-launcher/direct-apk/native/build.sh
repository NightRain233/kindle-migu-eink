#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
NDK=${ANDROID_NDK_ROOT:-$HOME/Library/Android/sdk/ndk/17.2.4988734}
CLANG="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/clang++"
SYS="$NDK/platforms/android-22/arch-arm"
TOOLCHAIN="$NDK/toolchains/arm-linux-androideabi-4.9/prebuilt/darwin-x86_64"
"$CLANG" --target=armv7a-linux-androideabi22 --gcc-toolchain="$TOOLCHAIN" --sysroot="$SYS" -D__ANDROID_API__=22 -std=c++11 -fPIC -shared -O2 -fno-exceptions -fno-rtti -Wl,-soname,libeanabparcel.so \
  -I"$NDK/sources/android/support/include" -I"$NDK/sysroot/usr/include/arm-linux-androideabi" -I"$NDK/sysroot/usr/include" \
  -o "$ROOT/eanab-launcher/direct-apk/lib/armeabi-v7a/libeanabparcel.so" \
  "$ROOT/eanab-launcher/direct-apk/native/eanabparcel.cpp" -llog -ldl
