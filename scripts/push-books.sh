#!/bin/bash
# 把本地书推送到 Kindle 的 /sdcard/Books（KOReader 的默认书库目录）
# 用法：
#   ./scripts/push-books.sh ~/Downloads/books
#   ./scripts/push-books.sh a.epub b.mobi c.pdf
#   ./scripts/push-books.sh ~/books --wipe     # 先清空设备书库再推
#
# 支持格式（KOReader 原生）：epub mobi azw3 fb2 fb2.zip txt html cbz cbr pdf djvu
# 大 TXT 建议先在 Mac 上转成 EPUB（KOReader 读 TXT 也能用，但章节/目录差）

set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/adb-env.sh >/dev/null

WIPE=0
ARGS=()
for a in "$@"; do
  [[ "$a" == "--wipe" ]] && WIPE=1 || ARGS+=("$a")
done

if [[ ${#ARGS[@]} -eq 0 ]]; then
  echo "用法: $0 <目录|文件...> [--wipe]"; exit 1
fi

adb -s "$SERIAL" shell "mkdir -p /sdcard/Books"
if [[ $WIPE -eq 1 ]]; then
  echo "清空 /sdcard/Books ..."
  adb -s "$SERIAL" shell "rm -rf /sdcard/Books/*"
fi

for src in "${ARGS[@]}"; do
  if [[ -d "$src" ]]; then
    echo "推送目录：$src"
    adb -s "$SERIAL" push "$src/." /sdcard/Books/ | tail -3
  elif [[ -f "$src" ]]; then
    echo "推送文件：$src"
    adb -s "$SERIAL" push "$src" /sdcard/Books/ | tail -1
  else
    echo "跳过（不存在）：$src"
  fi
done

echo "--- 设备上的书籍 ---"
adb -s "$SERIAL" shell 'ls -l /sdcard/Books' | tail -n +2
echo "--- 剩余空间 ---"
adb -s "$SERIAL" shell 'df /data'
