# Kindle 咪咕版（KFBJWI / eanab）墨水屏安卓调优

把一台 2016 年的 Kindle 咪咕版（第八代 Kindle 硬件 + 亚马逊为中国市场定制的 Android 5.1.1）调成“又快又清楚”的阅读器：
KOReader 认出墨水屏并按场景选刷新方式、界面美化、微信读书快刷。

除了能直接用的补丁，这里还有一份**写给 AI agent 的排查手册**（[`AGENTS.md`](AGENTS.md)）：
怎么测量墨水屏刷新、踩过哪些坑、怎么一步步验证。手上是别的老墨水屏安卓设备，也可以让你的 agent 读它照着做。

> English summary at the bottom.

## 效果

| 场景 | 原厂 | 调优后 |
|---|---|---|
| KOReader 正文翻页（面板驱动时间） | 约 450 ms，官方 KOReader 不知道自己在墨水屏上，从不清残影 | **约 272 ms**（DU4 快刷），每 10 页一次全刷清残影 |
| KOReader 菜单 / 书库 | 系统 AUTO | 仍走 AUTO（清晰） |
| KOReader 界面 | 原版书库与图标 | “继续阅读”卡片 + 按最近阅读排序的书架、思源黑体、加粗图标、4 级灰调色板、中文底栏 |
| 微信读书墨水屏版 | 约 450 ms | 后台助手让它走 DU4 快刷，其他应用不受影响 |

所有数字都是设备内读 EPDC 寄存器实测的（方法见 [`docs/panel-timing-2026-10-30.md`](docs/panel-timing-2026-10-30.md)）。

## 目录

| 路径 | 内容 |
|---|---|
| [`AGENTS.md`](AGENTS.md) | **给 agent 的排查手册**：流程、测量方法、决策原则 |
| [`docs/pitfalls.md`](docs/pitfalls.md) | **坑点清单**：现象 → 原因 → 验证 → 解决 |
| [`docs/case-study.md`](docs/case-study.md) | 本机从头到尾的过程（示范案例） |
| [`docs/`](docs/) | 专题记录：面板计时、AndE 报文格式、字体清晰度、软件链路 |
| [`eanab-launcher/`](eanab-launcher/) | KOReader 设备适配：APK 级 smali 补丁 + JNI，让 KOReader 识别本机为墨水屏，并经亚马逊 AndE 协议按刷新类别指定波形 |
| [`koreader-ui/`](koreader-ui/) | KOReader 用户补丁（无需编译）：书库、字体、调色板、DU4 预量化、刷新顺序修复；一键部署 / 回滚 |
| [`wave-helper/`](wave-helper/) | 按应用刷新助手：给不能改源码的应用（微信读书）指定刷新方式 |
| [`tools/`](tools/) | 设备端 C 小工具：`epdprobe`（面板计时）、`epdsub`、`einkctl`（EPDC 查询/提交）、`tapctl`（触摸注入） |
| [`scripts/`](scripts/) | adb 环境、全局默认波形开关、单本书字体参数、APK 构建、逆向辅助 |

## 前提

- Kindle 咪咕版（`ro.product.model=KFBJWI`，`ro.product.device=eanab`），已 root（作者用 Magisk 23）
- Mac / Linux，`adb`；按需：`luajit`（检查补丁语法）、Android NDK 17、apktool、zig（交叉编译工具）
- 先 `export KINDLE_SERIAL=<序列号>; source scripts/adb-env.sh`

**只想美化 KOReader 界面**：装官方 KOReader，运行 `koreader-ui/deploy.sh`（需要 root 只是为了从应用目录复制原版图标来加粗），不改系统、不改 APK。
**想要快刷**：按 [`eanab-launcher/README.md`](eanab-launcher/README.md) 构建适配包。
**微信读书快刷**：[`wave-helper/README.md`](wave-helper/README.md)。

每个组件都有回滚方法（`koreader-ui/rollback.sh`、卸载适配包、`wave-helper/uninstall.sh`）。

## 关键结论

1. **刷新方式决定速度**：面板驱动时间 DU 177 ms（黑白）、DU4 272 ms（4 级灰）、GC16 / GL16 / REAGL / AUTO 约 450 ms（16 级灰）。
   软件链路（触摸到提交）约 110 ms，所以“选对刷新方式”比优化软件更有效。
2. **亚马逊 AndE 协议可以从外部使用**：任何进程都能经 SurfaceFlinger transaction 200，按 layer 名为下一帧指定波形。
   配置是一次性的，且必须在画面提交前发（[`docs/ande-parcel-format-2026-10-31.md`](docs/ande-parcel-format-2026-10-31.md)）。
3. **KOReader 安卓版刷新顺序**：先把画面交给窗口、后发刷新参数，会让每帧沿用上一次的刷新方式；本仓库在 Lua 层改为先发参数。
4. **DU4 下字虚**：抗锯齿边缘落在 4 级灰之间被随机量化；先把画面量化到 4 级并偏深，字就实了。
5. **几条红线**：不要调 ioctl `0x4601`；不要对 fb0 的 mmap 调 `msync()`；直接提交时结构体 +36 必须填 4097。详见 [`docs/pitfalls.md`](docs/pitfalls.md)。

## 不包含什么

- 亚马逊的系统文件、固件、反汇编摘录：不分发。协议格式是根据实测和逆向写成的文字说明。
- KOReader APK：请从官方下载后自行构建适配包（KOReader 以 AGPL-3.0 发布）。
- 字体文件：`koreader-ui/deploy.sh` 自动从 notofonts 下载。

## 风险

改的是一台老设备的系统行为。`scripts/du-waveform.py` 会替换 `/system/lib/libsurfaceflinger.so`（自带 sha256 校验和备份），
其余组件都不改系统分区。动手前请备份，后果自负。

## License

本仓库中作者编写的代码与文档以 MIT 发布（见 [`LICENSE`](LICENSE)）。KOReader 及其启动器、亚马逊系统组件归各自权利人所有。

---

## English summary

Tuning notes and tools for the Kindle Migu edition (`KFBJWI` / `eanab`), an 8th-gen Kindle board running Amazon's Android 5.1.1 build for China.

- **Measure e-ink refresh without a camera**: poll the i.MX EPDC registers on-device (`tools/epdprobe.c`); per-waveform panel times: DU 177 ms, DU4 272 ms, GC16/GL16/AUTO ~450 ms.
- **Amazon AndE protocol from third-party apps**: SurfaceFlinger transaction 200 accepts a per-layer, one-shot waveform config built with the device's own `libandechoreographer.so` serializer.
- **KOReader adapter**: APK-level smali patch so KOReader treats the device as e-ink and picks a waveform per refresh class (DU4 page turns, AUTO for menus, GC16 periodic full refresh); user patches for UI, DU4 pre-quantization and a refresh-ordering fix.
- **`AGENTS.md`**: a troubleshooting playbook meant to be read by coding agents working on other old Android e-ink devices.
