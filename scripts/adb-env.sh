#!/bin/bash
# Kindle 咪咕版（KFBJWI / eanab）adb 环境
# 用法：export KINDLE_SERIAL=<adb devices 里看到的序列号>; source scripts/adb-env.sh
# 之后所有脚本都用 adb -s "$SERIAL"（同时连着 USB 与 WiFi adb 时必须指定目标）。
# 未设置 KINDLE_SERIAL 时，若只连了一台设备则自动选用。

export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
export PATH="$ANDROID_SDK_ROOT/platform-tools:$PATH"

if [ -z "${KINDLE_SERIAL:-}" ]; then
  KINDLE_SERIAL="$(adb devices | awk 'NR>1 && $2=="device"{print $1}' | head -n1)"
fi
SERIAL="$KINDLE_SERIAL"
ADB="adb -s $SERIAL"

kindle_check() {
  if [ -z "$SERIAL" ] || ! adb -s "$SERIAL" get-state >/dev/null 2>&1; then
    echo "设备 ${SERIAL:-（未指定）} 不在线。当前目标："
    adb devices -l
    return 1
  fi
  echo "已连接：$(adb -s "$SERIAL" shell getprop ro.product.model | tr -d '\r') ($SERIAL)"
}

kindle_check
