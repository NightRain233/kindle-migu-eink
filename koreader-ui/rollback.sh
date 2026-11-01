#!/usr/bin/env bash
# 撤销 eanab 界面美化：删除补丁、字体、图标，设置项恢复为部署前的原值。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../scripts/adb-env.sh" >/dev/null
A=(adb -s "$SERIAL")
KO=/sdcard/koreader
PKG=org.koreader.launcher
# 官方版与候选包共用 /sdcard/koreader，两个都要停，否则退出时会回写旧设置
PKGS=(org.koreader.launcher org.koreader.launcher.eanab)
ORIG="$KO/eanab-ui-orig-settings.lua"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for p in "${PKGS[@]}"; do "${A[@]}" shell am force-stop "$p"; done
sleep 1

for f in "$HERE"/patches/*.lua; do
  "${A[@]}" shell rm -f "$KO/patches/$(basename "$f")"
done
"${A[@]}" shell rm -f "$KO/fonts/NotoSansCJKsc-Medium.otf" "$KO/fonts/NotoSansCJKsc-Bold.otf"
if "${A[@]}" shell "[ -f $KO/icons/.eanab-ui ] && echo yes" | grep -q yes; then
  "${A[@]}" shell rm -rf "$KO/icons"
fi

if "${A[@]}" shell "[ -f $ORIG ] && echo yes" | grep -q yes; then
  "${A[@]}" pull "$KO/settings.reader.lua" "$WORK/settings.reader.lua" >/dev/null
  "${A[@]}" pull "$ORIG" "$WORK/orig.lua" >/dev/null
  luajit "$HERE/tools/settings.lua" restore "$WORK/settings.reader.lua" "$WORK/orig.lua"
  luajit -e "assert(loadfile('$WORK/settings.reader.lua'))"
  "${A[@]}" push "$WORK/settings.reader.lua" "$KO/settings.reader.lua" >/dev/null
  "${A[@]}" shell rm -f "$ORIG"
fi

"${A[@]}" shell am start -n $PKG/.MainActivity >/dev/null
echo "已回滚"
