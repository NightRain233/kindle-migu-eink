# eanab KOReader 启动器适配

让 KOReader 把本机识别为电子墨水设备（`Amazon/KFBJWI/eanab`），并把每次刷新的意图通过亚马逊 AndE 协议交给系统，
使系统那一次提交直接采用指定的波形（不追加第二次提交）。

## 现状（2026-11-01，基于官方 KOReader v2026.07.1）

| 包名 | 用途 |
|---|---|
| `org.koreader.launcher.eanab`（桌面名 `KOReader eanab candidate`） | 本目录构建出的适配包，日常使用 |
| `org.koreader.launcher` | 官方包，不改动，可与适配包并存作后备（两者共用 `/sdcard/koreader/`） |

本仓库不分发 APK：请从 KOReader 官方 Release 下载 `armeabi-v7a` 安装包，按下文自行构建。

刷新类别与下发参数（`waveform/updateMode`）：

| KOReader 类别 | 下发 | 场景 |
|---|---|---|
| PARTIAL | `7/0` DU4 | 正文翻页 |
| FAST | `1/0` DU | 点按高亮等小区域 |
| FULL_UI / PARTIAL_UI | `257/0` AUTO | 菜单、书库、封面 |
| FULL | `2/1` GC16 全刷 | 周期清残影 |
| 其他 mode | 原样透传，`updateMode=0` | `koreader-ui/patches/2-eink-settle.lua` 用它发 GL16 `5/0` 补刷 |

实测（全局波形为原厂 AUTO 时同样成立）：正文和快速刷新每次 1 次 HAL 提交；菜单 257；全刷 2/1；
layer 名在回桌面、熄屏、进程重启下恒为 `<包名>/org.koreader.launcher.MainActivity_1_1`。

## 两个重要的配套修复（在 `koreader-ui/` 的 Lua 补丁里）

1. **刷新顺序**：原版 `ffi/framebuffer_android.lua` 先 `_updateWindow()` 再 `einkUpdate()`，SurfaceFlinger 比 parcel 早约 2 ms 拿到画面，
   于是每帧都沿用上一次的波形（菜单后的翻页走 257、翻页后的菜单走 7）。`2-eink-ande-order.lua` 在候选包下改为先发 parcel。
2. **配置是一次性的**：code 200 的配置只作用于该 layer 的下一帧，所以必须每次刷新前都发（候选包正是如此）。

## 为什么要独立写控制器

- 官方 APK 已包含 `android.isEink()`、`einkUpdate()`、`getEinkConstants()` 与 Freescale/NTX 控制器，但 `EPDFactory` 不认识 eanab，
  返回 `FakeEPDController`，Lua 侧 `isEink()` 为 false，五类刷新全被跳过。
- NTX/Nook/Tolino 控制器依赖隐藏方法 `View.postInvalidateDelayed(long,int,int,int,int,int)`，本机框架中不存在，不能冒充这些设备。
- 波形号必须用本机实测命名空间：`4` 是 118 ms 的 1-bit 档（上游 NTX 注释把它叫 AUTO），真正 AUTO 是 `257`，`5` 是 GL16。

## 构建（APK 级路线，无需完整编译 KOReader）

```sh
APKTOOL_JAR=~/.local/share/apktool/apktool.jar \
PACKAGE_NAME=org.koreader.launcher.eanab \
APP_LABEL='KOReader eanab candidate' \
  scripts/build-eanab-direct-apk.sh /path/to/official/base.apk \
  eanab-launcher/build/KOReader-eanab-candidate.apk
```

脚本用 apktool 解包官方 APK，在 `EPDFactory` 前插入精确的三字段判断（`amazon`/`kfbjwi`/`eanab`），加入
`direct-apk/EanabEPDController.smali`、`direct-apk/AndEParcel.smali` 与 `direct-apk/lib/armeabi-v7a/libeanabparcel.so`
（源码 `direct-apk/native/eanabparcel.cpp`，`direct-apk/native/build.sh` 用 NDK 17 编译），改包名后用本地测试 keystore 重签。


## 已知问题

- JNI 每次刷新都重新构造 `AndEViewConfig` 且不析构，有少量内存泄漏（每页一次，可忽略）。修法见 `wave-helper/native/eanabwave.cpp`
  （构造一次，之后用 `clearConfig` 复用）；重编候选包时一并修。
- 仍使用本地测试签名；正式发布需另定签名与数据迁移方式。

## 回滚

`adb uninstall org.koreader.launcher.eanab`（书籍、进度、设置都在 `/sdcard/koreader/`，不受影响）。
