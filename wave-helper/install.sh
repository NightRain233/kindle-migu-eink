#!/usr/bin/env bash
# 安装/更新按应用刷新助手：推送文件、装开机脚本、立即（重新）启动
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../scripts/adb-env.sh" >/dev/null
A=(adb -s "$SERIAL")
DIR=/data/local/tmp/eanab-wave
"$HERE/build.sh" >/dev/null
"${A[@]}" shell mkdir -p $DIR
for f in build/eanab-wave.dex build/libeanabwave.so rules.txt eanab-wave.sh; do
  "${A[@]}" push "$HERE/$f" $DIR/ >/dev/null
done
"${A[@]}" shell chmod 755 $DIR $DIR/libeanabwave.so $DIR/eanab-wave.sh
"${A[@]}" shell chmod 644 $DIR/eanab-wave.dex $DIR/rules.txt
"${A[@]}" shell su -c "'cp $DIR/eanab-wave.sh /data/adb/service.d/eanab-wave.sh; chmod 755 /data/adb/service.d/eanab-wave.sh'"
"${A[@]}" shell su -c "'[ -f $DIR/pid ] && kill \$(cat $DIR/pid) 2>/dev/null; /data/adb/magisk/busybox setsid sh -c \"CLASSPATH=$DIR/eanab-wave.dex exec app_process /system/bin EanabWaveHelper daemon $DIR/rules.txt >/dev/null 2>&1 </dev/null\" &'"
sleep 2
"${A[@]}" shell "ps | grep app_process"
echo "已安装；日志 /sdcard/koreader/eanab-wave.log，临时停用：建 /sdcard/koreader/eanab-wave.off"
