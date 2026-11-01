#!/usr/bin/env bash
# 部署 eanab 界面美化：补丁、字体、加粗图标、设置项。可重复运行。
# 回滚：koreader-ui/rollback.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../scripts/adb-env.sh" >/dev/null
A=(adb -s "$SERIAL")
KO=/sdcard/koreader
PKG=org.koreader.launcher
# 官方版与候选包共用 /sdcard/koreader，两个都要停，否则退出时会回写旧设置
PKGS=(org.koreader.launcher org.koreader.launcher.eanab)
APP_FILES=/data/data/$PKG/files
ORIG="$KO/eanab-ui-orig-settings.lua"
FONTS_DIR="$HERE/fonts"
FONT_URL=https://github.com/notofonts/noto-cjk/raw/main/Sans/OTF/SimplifiedChinese
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== 语法检查"
for f in "$HERE"/patches/*.lua; do
  luajit -e "assert(loadfile('$f'))"
done

echo "== 字体"
mkdir -p "$FONTS_DIR"
for w in Medium Bold; do
  f="$FONTS_DIR/NotoSansCJKsc-$w.otf"
  [ -s "$f" ] || curl -fsSL -o "$f" "$FONT_URL/NotoSansCJKsc-$w.otf"
done

echo "== 停止 KOReader（运行中会回写设置）"
for p in "${PKGS[@]}"; do "${A[@]}" shell am force-stop "$p"; done
sleep 1

echo "== 设置项"
"${A[@]}" pull "$KO/settings.reader.lua" "$WORK/settings.reader.lua" >/dev/null
if "${A[@]}" shell "[ -f $ORIG ] && echo yes" | grep -q yes; then
  "${A[@]}" pull "$ORIG" "$WORK/orig.lua" >/dev/null
fi
luajit "$HERE/tools/settings.lua" apply "$WORK/settings.reader.lua" "$WORK/orig.lua"
luajit -e "assert(loadfile('$WORK/settings.reader.lua'))"
"${A[@]}" push "$WORK/settings.reader.lua" "$KO/settings.reader.lua" >/dev/null
"${A[@]}" push "$WORK/orig.lua" "$ORIG" >/dev/null

echo "== 补丁与字体"
"${A[@]}" shell mkdir -p "$KO/patches" "$KO/fonts" "$KO/icons"
# 先快后清默认关闭（删掉这个文件即启用）
"${A[@]}" shell "[ -f $KO/eanab-settle.on ] || touch $KO/eanab-settle.off"
for f in "$HERE"/patches/*.lua; do
  "${A[@]}" push "$f" "$KO/patches/" >/dev/null
done
for w in Medium Bold; do
  "${A[@]}" push "$FONTS_DIR/NotoSansCJKsc-$w.otf" "$KO/fonts/" >/dev/null
done

echo "== 加粗图标（以设备上这一版 KOReader 自带图标为底）"
"${A[@]}" shell su -c "'rm -rf /sdcard/.eanab-icons; cp -r $APP_FILES/resources/icons/mdlight /sdcard/.eanab-icons'"
"${A[@]}" pull /sdcard/.eanab-icons "$WORK/mdlight" >/dev/null
"${A[@]}" shell rm -rf /sdcard/.eanab-icons
python3 -I "$HERE/tools/thicken-icons.py" "$WORK/mdlight" "$WORK/icons" 1.5
touch "$WORK/icons/.eanab-ui"
"${A[@]}" shell "rm -f $KO/icons/*.svg"
"${A[@]}" push "$WORK/icons/." "$KO/icons/" >/dev/null

echo "== 启动 KOReader"
"${A[@]}" shell input keyevent KEYCODE_WAKEUP
"${A[@]}" shell am start -n $PKG/.MainActivity >/dev/null
echo "完成"
