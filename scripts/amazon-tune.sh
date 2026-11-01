#!/bin/bash
# 精简 / 恢复这台 Kindle 咪咕版上的 Amazon 后台组件
#   ./scripts/amazon-tune.sh status     # 看当前禁用了哪些
#   ./scripts/amazon-tune.sh disable    # 禁用（默认）
#   ./scripts/amazon-tune.sh enable     # 全部恢复
#
# 需要 root（Magisk 已装，su 可用）。
# 说明：pm disable 只是让系统不再启动这些组件，不删任何文件，随时 enable 回来。

set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/adb-env.sh >/dev/null

# 本次禁用清单（Amazon 后台/遥测/同步，与离线看书无关）
BLOAT=(
  com.amazon.tcomm                    # 设备消息通道
  com.amazon.imp                      # 内部消息推送
  com.amazon.platform.fdrw            # 恢复出厂白名单
  com.amazon.device.sync              # 内容同步
  com.amazon.device.messaging         # ADM 推送
  com.amazon.kindleautomatictimezone  # 自动时区（本机无定位，纯浪费 8MB）
)

su_do() { adb -s "$SERIAL" shell "su -c '$*'"; }

cmd="${1:-disable}"

case "$cmd" in
  status)
    echo "--- 已禁用 ---"
    adb -s "$SERIAL" shell 'pm list packages -d' | sed 's/package://' | sort
    echo "--- 仍在运行 ---"
    adb -s "$SERIAL" shell 'ps' | grep -c com.amazon
    adb -s "$SERIAL" shell 'cat /proc/meminfo' | sed -n '1,3p'
    ;;
  disable)
    for p in "${BLOAT[@]}"; do
      printf '%-38s %s\n' "$p" "$(su_do pm disable "$p" | tr -d '\r')"
    done
    ;;
  enable)
    for p in "${BLOAT[@]}"; do
      printf '%-38s %s\n' "$p" "$(su_do pm enable "$p" | tr -d '\r')"
    done
    ;;
  *)
    echo "用法: $0 {status|disable|enable}"; exit 1;;
esac
