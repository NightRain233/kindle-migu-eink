#!/usr/bin/env bash
# 卸载按应用刷新助手：停进程、删开机脚本和文件
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../scripts/adb-env.sh" >/dev/null
A=(adb -s "$SERIAL")
"${A[@]}" shell su -c "'[ -f /data/local/tmp/eanab-wave/pid ] && kill \$(cat /data/local/tmp/eanab-wave/pid) 2>/dev/null; rm -f /data/adb/service.d/eanab-wave.sh; rm -rf /data/local/tmp/eanab-wave'"
echo "已卸载"
