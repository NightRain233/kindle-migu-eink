#!/bin/bash
# 用 Android NDK 编译 einkctl（armv7 静态可执行，可直接 adb push 到 /data/local/tmp 运行）
# 用法: ./scripts/build-einkctl.sh [NDK 路径]
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
NDK="${1:-$(ls -d "$SDK"/ndk/* 2>/dev/null | sort -V | tail -1)}"
[ -n "${NDK:-}" ] && [ -d "$NDK" ] || { echo "找不到 NDK，请先安装或传入路径"; exit 1; }

HOST=$(uname -s | tr 'A-Z' 'a-z')
case "$HOST" in darwin*) HOSTTAG=darwin-x86_64 ;; linux*) HOSTTAG=linux-x86_64 ;; *) echo "unsupported host"; exit 1 ;; esac
CC="$NDK/toolchains/llvm/prebuilt/$HOSTTAG/bin/armv7a-linux-androideabi21-clang"
[ -x "$CC" ] || CC="$NDK/toolchains/llvm/prebuilt/$HOSTTAG/bin/armv7a-linux-androideabi23-clang"
[ -x "$CC" ] || { echo "找不到 armv7a clang in $NDK"; exit 1; }

echo "NDK: $NDK"
echo "CC : $CC"
mkdir -p tools/build
"$CC" -static -O2 -Wall -Wextra -o tools/build/einkctl tools/einkctl.c

file tools/build/einkctl 2>/dev/null | head -1
ls -l tools/build/einkctl
echo "OK -> tools/build/einkctl"
