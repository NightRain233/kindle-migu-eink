#!/system/bin/sh
# 开机启动“按应用刷新助手”（Magisk service.d）。源码：wave-helper/
# 卸载：wave-helper/uninstall.sh
DIR=/data/local/tmp/eanab-wave
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
sleep 10
CLASSPATH=$DIR/eanab-wave.dex nohup app_process /system/bin EanabWaveHelper daemon $DIR/rules.txt >/dev/null 2>&1 &
