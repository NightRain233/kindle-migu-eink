# Kindle 咪咕版（KFBJWI / eanab）墨水屏安卓调优

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android%205.1.1%20(Kindle)-blue.svg)](#前提)
[![Target](https://img.shields.io/badge/Target-KOReader%20%7C%20微信读书-green.svg)](#效果)

把一台 2016 年的 Kindle 咪咕版（第八代 Kindle 硬件 + 亚马逊为中国市场定制的 Android 5.1.1）调成“又快又清楚”的阅读器：
KOReader 认出墨水屏并按场景选刷新方式、界面美化、微信读书快刷。

本项目不仅提供可直接落地的补丁与工具，还附带一份**写给 AI Coding Agent 的排查与调优手册**（[`AGENTS.md`](AGENTS.md) 与 [`skills/`](skills/)）。如果你手头有其它基于 i.MX 的老墨水屏安卓设备，也可以直接让你的 Agent 参照本项目的方法论进行排查。

> [English summary](#english-summary) at the bottom.

---

## 效果实测

| 场景 | 原厂 / 官方版 | 调优后 | 优化原理 |
|---|---|---|---|
| **KOReader 正文翻页**<br>(面板驱动耗时) | 约 **450 ms**<br>(官方版无法识别墨水屏，走系统全刷且从不清残影) | **约 272 ms** ⚡<br>(DU4 4 级灰快刷) | 逆向亚马逊 AndE 协议，每 10 页全刷一次清残影 |
| **KOReader 菜单 / 书库** | 系统 AUTO | 维持 AUTO（保清晰度） | 按窗口与交互场景动态分发波形 |
| **KOReader 界面观感** | 原版书库与细线条图标 | “继续阅读”卡片、按最近阅读排序书架、思源黑体、加粗图标、4 级灰调色板、中文底栏 | Lua 用户补丁，免重编 APK |
| **微信读书墨水屏版** | 约 450 ms | **约 272 ms** ⚡ | 后台守护进程（`wave-helper`）指定 DU4 快刷 |

> 📊 **注**：所有耗时均为设备端直读 i.MX EPDC 寄存器测得（无需高速相机，测量方法见 [`docs/panel-timing-2026-10-30.md`](docs/panel-timing-2026-10-30.md)）。

---

## 🤖 让 AI Agent 帮你操作（推荐）

如果你不想手动配 NDK/apktool 环境或敲一大堆命令，**推荐直接把已开启 ADB 的设备连上电脑，并将以下 Prompt 复制给你的 AI Agent（如 Claude Code, Cursor, Windsurf, Aider 等）**：

### 场景 1：把手上的 Kindle 咪咕版一键调优

<details open>
<summary>📋 <b>点击展开 / 复制 Prompt</b></summary>

```text
我有一台已 Root 的 Kindle 咪咕版（KFBJWI / eanab，Android 5.1.1），当前已通过 USB 连接并开启了 ADB。
请阅读当前仓库的 README.md、AGENTS.md 以及 docs/pitfalls.md。

请严格遵守其工作原则与红线，帮我一步步完成调优：
1. 先检查设备连接状态（getprop 确认 ro.product.device=eanab、确认 root 权限与 adb 环境）；
2. 了解我的需求后，按需执行部署：
   - 若我想美化 KOReader：运行 koreader-ui/deploy.sh；
   - 若我想让微信读书快刷：构建并安装 wave-helper；
   - 若我想让 KOReader 支持 DU4 快刷：按 eanab-launcher/ 指引制作适配包；
3. 执行每项改动前告知我作用与回滚方式，严格避开 pitfalls.md 中的系统红线（如严禁 ioctl 0x4601、严禁对 fb0 的 mmap 调 msync）；
4. 操作完成后，指导我如何在墨水屏上肉眼验收翻页速度与字迹清晰度。
```

</details>

### 场景 2：把本项目的调优经验迁移到其它老墨水屏设备

<details>
<summary>📋 <b>点击展开 / 复制 Prompt</b></summary>

```text
我有一台基于 i.MX / Android 系统的老旧墨水屏设备，想要改善其翻页刷新延迟和阅读器显示效果。
请参考开源项目 https://github.com/NightRain233/kindle-migu-eink 中的 AGENTS.md、docs/panel-timing-2026-10-30.md 和 docs/pitfalls.md。

请严格遵守“先测量、后优化，一次只改一个变量”的原则：
1. 通过 adb 查看设备属性、SurfaceFlinger、内核日志与 EPDC 节点，摸清其刷新机制与私有协议；
2. 参考 tools/epdprobe.c 的原理帮助我实测各波形驱动耗时；
3. 评估是否存在可调用的波形接口或第三方快刷方案，并给出低风险的调优建议。
```

</details>

---

## 快速指引：按需选择方案

根据你的折腾意愿和阅读习惯，选择最适合的路径：

| 你的目标 | 所需步骤 | 复杂度 | 是否改系统/APK |
|---|---|:---:|:---:|
| **仅美化 KOReader 界面与字体** | 装官方 KOReader 后，执行 `koreader-ui/deploy.sh` | 🟢 极简 (5分钟) | ❌ 仅用户目录 Lua 补丁 |
| **让微信读书等 App 享受快刷** | 进入 `wave-helper/`，执行 `build.sh && install.sh` | 🟡 简易 (10分钟) | ❌ 仅后台辅助进程 |
| **KOReader 完美快刷 + 清残影** | 参考 [`eanab-launcher/README.md`](eanab-launcher/README.md) 打 smali 补丁 | 🔴 进阶 (需 apktool) | 仅打补丁重签 APK |
| **彻底排查 / 移植其它设备** | 查阅 [`AGENTS.md`](AGENTS.md) 与 [`tools/`](tools/) 自测工具 | 🟣 极客 | 视方案而定 |

> 所有方案均自带干净的回滚方案（`koreader-ui/rollback.sh`、`wave-helper/uninstall.sh`、卸载重装原版 APK）。

---

## 前提条件

- **设备**：Kindle 咪咕版（`ro.product.model=KFBJWI`，`ro.product.device=eanab`），**已获取 root**（推荐 Magisk 23）
- **电脑环境**：Mac / Linux，装有 `adb`
- **可选依赖**（按需）：
  - 界面补丁语法检查：`luajit`
  - 快刷/工具编译：Android NDK r17c、apktool、zig
- **快速连接**：
  ```bash
  export KINDLE_SERIAL=<你的设备序列号>
  source scripts/adb-env.sh
  ```

---

## 关键技术结论

1. **刷新方式决定速度**：
   - 面板驱动硬件耗时：**DU（黑白）177 ms**、**DU4（4 级灰）272 ms**、**GC16/AUTO（16 级灰）约 450 ms**。
   - 软件链路（触摸到帧提交）仅约 110 ms，因此**“选对波形”远比单纯优化应用层代码更见效**。
2. **亚马逊 AndE 私有协议可免权限外部调用**：
   - 任意进程均可通过 SurfaceFlinger transaction 200，按 Layer 名字为下一帧指定波形。
   - 该配置是一次性的，且**必须在画面提交前发送**（详解见 [`docs/ande-parcel-format-2026-10-31.md`](docs/ande-parcel-format-2026-10-31.md)）。
3. **修复 KOReader 安卓版刷新顺序缺陷**：
   - 原版先将画面交给窗口、后发刷新参数，导致每一帧都在沿用上一次的刷新模式。本项目在 Lua 层将时序调整为“先发波形参数、再交画”。
4. **DU4 快刷下的字体发虚治理**：
   - 字体抗锯齿边缘落在 4 级灰之间会被随机量化；在渲染管线中先把画面量化到 4 级并适当加深，文字立刻恢复实心清晰（见 [`docs/font-clarity-2026-10-31.md`](docs/font-clarity-2026-10-31.md)）。
5. **系统红线（防踩坑必读）**：
   - ❌ 严禁调用 ioctl `0x4601`（会导致内核崩掉或驱动死锁）；
   - ❌ 严禁对 `/dev/graphics/fb0` 的 mmap 调用 `msync()`；
   - ⚠️ 直接提交刷新结构体时偏移 +36 必须写入 4097。详见 [`docs/pitfalls.md`](docs/pitfalls.md)。

---

## 目录索引

| 路径 | 内容说明 |
|---|---|
| [`AGENTS.md`](AGENTS.md) | **给 AI Agent 的排查手册**：调优流程、测量标准、决策原则 |
| [`docs/pitfalls.md`](docs/pitfalls.md) | **避坑指南**：现象 → 根因 → 验证方法 → 解决方案 |
| [`docs/case-study.md`](docs/case-study.md) | Kindle 咪咕版从头到尾的真实调优案例复盘 |
| [`docs/`](docs/) | 专题硬核文档：面板寄存器测速、AndE 序列化报文、字体清晰度、渲染链路分析 |
| [`eanab-launcher/`](eanab-launcher/) | KOReader 深度适配：smali 补丁 + JNI，动态调度 AndE 波形 |
| [`koreader-ui/`](koreader-ui/) | KOReader 免编译体验补丁：现代书库、字体、加粗图标、DU4 预量化 |
| [`wave-helper/`](wave-helper/) | 通用刷新助手：为微信读书等不能改源码的 App 注入快刷模式 |
| [`tools/`](tools/) | 设备端原生 C 工具：`epdprobe`（寄存器级测速）、`einkctl`、`tapctl` |
| [`scripts/`](scripts/) | 辅助自动化脚本：ADB 环境配置、APK 构建、逆向分析工具 |

---

## 声明与边界

- **不分发专利固件**：本项目不包含任何亚马逊官方系统专有二进制、固件或反汇编片段；协议定义均来自动态实测与黑盒逆向笔记。
- **不分发 KOReader APK**：用户需从官方渠道下载原始 APK 并使用本仓库脚本构建适配包（KOReader 基于 AGPL-3.0）。
- **风险提示**：除 `scripts/du-waveform.py` 会动及 `/system` 分区（自带校验与备份机制）外，绝大部分组件均工作在用户空间。动手前请务必做好数据备份。

## License

本项目原创代码与技术文档均采用 [MIT License](LICENSE) 开源。第三方组件（KOReader、Android 及亚马逊组件等）版权归各自权利人所有。

---

## English summary

Tuning notes and tools for the **Kindle Migu edition (`KFBJWI` / `eanab`)**, an 8th-gen Kindle board running Amazon's customized Android 5.1.1 build for China.

- **Objective performance without a high-speed camera**: Direct on-device polling of i.MX EPDC registers (`tools/epdprobe.c`); panel times: DU (1-bit) ~177 ms, DU4 (4-level) ~272 ms, GC16/AUTO ~450 ms.
- **Amazon AndE protocol leveraged from userspace**: SurfaceFlinger transaction 200 accepts per-layer, one-shot waveform configurations without root privilege.
- **KOReader tuning**: Smali + JNI patches enable native e-ink detection and per-action waveform dispatching; Lua patches fix frame submission ordering and anti-aliasing quantization on DU4.
- **Agent Playbook**: Includes [`AGENTS.md`](AGENTS.md) and [`skills/`](skills/), designed for AI coding agents to replicate the diagnostic and tuning process on other vintage Android e-ink devices.
