#!/usr/bin/env bash
# Build the eanab observe-only launcher by patching an official APK in smali.
# This does not compile the full KOReader launcher or touch the installed APK.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OFFICIAL_APK="${1:-}"
OUTPUT_APK="${2:-$ROOT_DIR/eanab-launcher/build/KOReader-eanab-debug.apk}"
APKTOOL_JAR="${APKTOOL_JAR:-$HOME/.local/share/apktool/apktool.jar}"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
BUILD_TOOLS="${BUILD_TOOLS:-$ANDROID_SDK_ROOT/build-tools/34.0.0}"
KEYSTORE="${KEYSTORE:-$HOME/.android/debug.keystore}"
KEY_ALIAS="${KEY_ALIAS:-androiddebugkey}"
PACKAGE_NAME="${PACKAGE_NAME:-org.koreader.launcher.eanab.debug}"
APP_LABEL="${APP_LABEL:-KOReader eanab debug}"

if [[ -z "$OFFICIAL_APK" || ! -f "$OFFICIAL_APK" ]]; then
    echo "usage: $0 /path/to/official-launcher.apk [output.apk]" >&2
    exit 2
fi
for required in "$APKTOOL_JAR" "$BUILD_TOOLS/zipalign" "$BUILD_TOOLS/apksigner" "$KEYSTORE"; do
    [[ -e "$required" ]] || { echo "missing: $required" >&2; exit 2; }
done

WORK_DIR="$(mktemp -d /tmp/eanab-direct-apk.XXXXXX)"
mkdir -p "$(dirname "$OUTPUT_APK")"

java -jar "$APKTOOL_JAR" d -f -o "$WORK_DIR/source" "$OFFICIAL_APK" >/dev/null

CONTROLLER_DIR="$WORK_DIR/source/smali/org/koreader/launcher/device/epd"
mkdir -p "$CONTROLLER_DIR"
cp "$ROOT_DIR/eanab-launcher/direct-apk/EanabEPDController.smali" \
    "$CONTROLLER_DIR/EanabEPDController.smali"
cp "$ROOT_DIR/eanab-launcher/direct-apk/AndEParcel.smali" \
    "$CONTROLLER_DIR/AndEParcel.smali"
mkdir -p "$WORK_DIR/source/lib/armeabi-v7a"
cp "$ROOT_DIR/eanab-launcher/direct-apk/lib/armeabi-v7a/libeanabparcel.so" \
    "$WORK_DIR/source/lib/armeabi-v7a/libeanabparcel.so"

python3 - "$WORK_DIR/source/smali/org/koreader/launcher/device/EPDFactory.smali" \
         "$WORK_DIR/source/AndroidManifest.xml" "$PACKAGE_NAME" "$APP_LABEL" <<'PY'
from pathlib import Path
import sys

factory = Path(sys.argv[1])
s = factory.read_text()
needle = '''    .locals 2\n\n    .line 1\n    sget-object v0, Lorg/koreader/launcher/device/DeviceInfo;->INSTANCE:Lorg/koreader/launcher/device/DeviceInfo;\n'''
insert = '''    .locals 2\n\n    # eanab observe-only controller: exact manufacturer/model/device match.\n    sget-object v0, Lorg/koreader/launcher/device/DeviceInfo;->INSTANCE:Lorg/koreader/launcher/device/DeviceInfo;\n    invoke-virtual {v0}, Lorg/koreader/launcher/device/DeviceInfo;->getMANUFACTURER()Ljava/lang/String;\n    move-result-object v0\n    const-string v1, "amazon"\n    invoke-static {v0, v1}, Lkotlin/jvm/internal/Intrinsics;->areEqual(Ljava/lang/Object;Ljava/lang/Object;)Z\n    move-result v0\n    if-eqz v0, :eanab_not_device\n\n    sget-object v0, Lorg/koreader/launcher/device/DeviceInfo;->INSTANCE:Lorg/koreader/launcher/device/DeviceInfo;\n    invoke-virtual {v0}, Lorg/koreader/launcher/device/DeviceInfo;->getMODEL()Ljava/lang/String;\n    move-result-object v0\n    const-string v1, "kfbjwi"\n    invoke-static {v0, v1}, Lkotlin/jvm/internal/Intrinsics;->areEqual(Ljava/lang/Object;Ljava/lang/Object;)Z\n    move-result v0\n    if-eqz v0, :eanab_not_device\n\n    sget-object v0, Lorg/koreader/launcher/device/DeviceInfo;->INSTANCE:Lorg/koreader/launcher/device/DeviceInfo;\n    invoke-virtual {v0}, Lorg/koreader/launcher/device/DeviceInfo;->getDEVICE()Ljava/lang/String;\n    move-result-object v0\n    const-string v1, "eanab"\n    invoke-static {v0, v1}, Lkotlin/jvm/internal/Intrinsics;->areEqual(Ljava/lang/Object;Ljava/lang/Object;)Z\n    move-result v0\n    if-eqz v0, :eanab_not_device\n\n    new-instance v0, Lorg/koreader/launcher/device/epd/EanabEPDController;\n    invoke-direct {v0}, Lorg/koreader/launcher/device/epd/EanabEPDController;-><init>()V\n    return-object v0\n\n:eanab_not_device\n    .line 1\n    sget-object v0, Lorg/koreader/launcher/device/DeviceInfo;->INSTANCE:Lorg/koreader/launcher/device/DeviceInfo;\n'''
if needle not in s:
    raise SystemExit("EPDFactory insertion point not found")
factory.write_text(s.replace(needle, insert, 1))

manifest = Path(sys.argv[2])
package_name = sys.argv[3]
app_label = sys.argv[4]
s = manifest.read_text()
s = s.replace('package="org.koreader.launcher"',
              'package="' + package_name + '"', 1)
s = s.replace('android:authorities="org.koreader.launcher.provider"',
              'android:authorities="' + package_name + '.provider"', 1)
s = s.replace('android:label="KOReader"',
              'android:label="' + app_label + '"', 1)
manifest.write_text(s)
PY

java -jar "$APKTOOL_JAR" b "$WORK_DIR/source" -o "$WORK_DIR/unsigned.apk" >/dev/null
"$BUILD_TOOLS/zipalign" -f -p 4 "$WORK_DIR/unsigned.apk" "$WORK_DIR/aligned.apk"
"$BUILD_TOOLS/apksigner" sign \
    --ks "$KEYSTORE" --ks-key-alias "$KEY_ALIAS" \
    --ks-pass pass:android --key-pass pass:android \
    --out "$OUTPUT_APK" "$WORK_DIR/aligned.apk"
"$BUILD_TOOLS/apksigner" verify --verbose "$OUTPUT_APK" >/dev/null
echo "$OUTPUT_APK"
