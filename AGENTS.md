# 墨水屏安卓设备调优：给 agent 的排查手册

> 读者：帮用户优化**老款墨水屏安卓设备**（阅读器、改装 Kindle、Boyue/Onyx/Nook/Tolino 等 i.MX 平台）的 coding agent。
> 本手册来自 Kindle 咪咕版（KFBJWI / eanab，i.MX6SL，Android 5.1.1）的完整调优过程；通用部分在前，本机数字只作示例。
> 坑点细节见 [`docs/pitfalls.md`](docs/pitfalls.md)，完整案例见 [`docs/case-study.md`](docs/case-study.md)。

## 0. 工作原则

1. **先测量，后优化。** 每个结论都要有前后对比的实测数据。旧记录、网上注释、上游代码里的命名都可能是错的
   （本项目里“波形 4 = AUTO”的上游注释、一条“改前每页 GC16 全刷”的旧记录，复测后都不成立）。
2. **一次只改一个变量**，改完立刻测，测完记录；改动前记下如何撤销。
3. **ioctl 返回 0 ≠ 屏幕刷了。** 墨水屏驱动的提交和等待都可能“接受但不执行”。只信面板侧的证据（见 §2）。
4. **截图看不到墨水屏的真实效果。** `screencap` 拿到的是帧缓冲；快刷的灰阶损失、残影只有人眼能看到。
   涉及观感的结论，最后必须请用户肉眼验收，并给出具体的“看什么、不满意改哪个参数”。
5. **能不编译就不编译。** 老设备的 App 多半能用用户补丁（KOReader `patches/*.lua`）、APK 级 smali 补丁或独立小程序解决，
   不必搭完整构建环境。
6. **设备是共享的。** 用户可能同时开着别的会话或 App；改应用设置前先停掉所有会回写设置的进程。

## 1. 摸清设备（30 分钟）

```sh
adb shell getprop | grep -E 'ro.product|ro.build|ro.hardware|ro.board'
adb shell cat /proc/cpuinfo /proc/meminfo
adb shell ls /sys/class/graphics/fb0/ /dev/graphics/
adb shell ls -d /sys/devices/soc*/**/*epdc* 2>/dev/null   # i.MX EPDC
adb shell dmesg | grep -i -E 'epdc|waveform|mxcfb'
adb shell ls /system/lib | grep -i -E 'eink|epd|ande|surfaceflinger|gralloc'
adb shell dumpsys SurfaceFlinger | head -50
```

要回答的问题：

- 屏幕控制器是什么（i.MX EPDC / 全志 / RK EBC / 厂商私有）？驱动有哪些 sysfs 节点？
- 刷新由谁决定：App 自己（ioctl / 厂商 API）、SurfaceFlinger、还是 HAL？厂商有没有自己的协议（亚马逊 AndE、Onyx、Tolino 的 `postInvalidateDelayed` 变体）？
- 有没有 root？`/system` 能否 remount？SELinux 状态？开机脚本机制是否真的会执行（本机 Magisk `service.d` 从不执行）？

## 2. 测量：面板到底花了多少时间

**最重要的一步。** i.MX EPDC 上不用摄像机就能测：

1. 读 `<epdc>/mxc_epdc_regs` 会把整张寄存器表打进内核日志；边读边排空 `/dev/kmsg`。
2. 只看 `EPDC_STATUS_LUTS`：非 0 就是面板正在被驱动。LUT 窗口的长度 = 这次刷新的面板驱动时间。
3. 同时记 `EPDC_UPD_CTRL`：高字节是驱动内部波形模式，低位是 FULL/PARTIAL。
4. 先 `echo 1 > /proc/sys/kernel/printk`，否则寄存器 dump 走串口，采样退到 500 ms 一次。

工具：[`tools/epdprobe.c`](tools/epdprobe.c)（zig / NDK 交叉编译，见 `scripts/build-*.sh`）。
配合 [`tools/tapctl.c`](tools/tapctl.c) 往触摸设备注入点击，就能做“固定节奏翻 N 页 + 记录每次刷新”的可复现基准。

本机测得（参考量级）：

| 波形 | 面板时间 | 灰阶 |
|---|---|---|
| DU | 177 ms | 2 |
| MXCFB 4（驱动内部 6） | 118 ms | 2，正文明显变淡 |
| DU4 | 272 ms | 4 |
| GC16 / GL16 / REAGL / AUTO | 约 450 ms | 16 |

再测软件链路（触摸 → 提交到 HAL）。本机中位约 110 ms，远小于面板时间。结论通常是：**换刷新方式的收益远大于优化软件**。

其他平台：没有 EPDC 寄存器时，找驱动的状态节点、`/proc/interrupts` 里 EPD 中断计数的变化，或在驱动打印里找 update/complete 日志；
实在没有，再用手机慢动作录像（240 fps 足够分辨 100 ms 级差异）。

## 3. 找到“谁决定波形”

按顺序排查：

1. **App 层**：App 是否已有墨水屏支持（KOReader 的 `EPDFactory`、阅读器自带的刷新设置）？没识别出设备时往往会退回“假控制器”，什么都不做。
2. **框架层**：厂商是否在 View / Window 上提供 tag、隐藏方法或 Binder 接口？用 `dumpsys`、`service list`、反编译 framework.jar 找。
   本机：亚马逊 `AndEChoreographerService` + SurfaceFlinger transaction 200。
3. **SurfaceFlinger / HAL**：默认波形写死在哪里？本机是 `libsurfaceflinger.so` 里一条 `movw r0,#257`。
4. **驱动层**：直接对 fb ioctl 提交。可用于测量和实验，但和系统提交并存时容易互相覆盖，不适合做正式方案。

逆向工具：`llvm-objdump` + pyelftools（[`scripts/re/`](scripts/re/) 有 PLT 符号解析和调用流还原两个辅助脚本）。
先找日志字符串（`logcat` 里出现的报错原文），再顺着字符串找函数，比从入口读起快得多。

## 4. 选方案：全局 vs 按应用

| 方案 | 优点 | 代价 |
|---|---|---|
| 改全局默认波形（patch 系统库） | 所有应用立刻变快 | 一刀切：菜单、图片、系统界面也变虚；要改系统分区 |
| App 自己按场景选（适配包 / 补丁） | 翻页快、菜单清晰、能定期全刷清残影 | 每个 App 单独做 |
| 外部助手按应用指定 | 能照顾改不了源码的 App | 要常驻进程；layer 名会变 |

本项目最终：全局恢复原厂，KOReader 用适配包自己选，微信读书用助手指定。

## 5. 改善观感（快刷之后）

- **快刷字虚**：DU4 只有 4 级灰，抗锯齿边缘被随机量化。在 App 交出画面前先量化到 4 级、阈值偏深（[`koreader-ui/patches/2-eink-du4-quantize.lua`](koreader-ui/patches/2-eink-du4-quantize.lua)），整屏约 11 ms。
- **字太细**：调字重 / gamma 比换波形便宜；确认字体名真的生效（见坑点“字体名写错会静默回退”）。
- **界面灰色**：把 UI 灰色常量收敛到 4 级灰（0x00/0x55/0xAA/0xFF），快刷和慢刷下都精确。
- **残影**：GL16 / DU 都不清残影；必须有周期性 GC16 全刷。App 不知道自己在墨水屏上时，永远不会全刷。
- **“先快后清”（翻页快刷，停 1 秒后 16 级灰补刷）**：技术上可行，但第二次可见变化让人分心，本项目用户验收后关闭。
  这类设计一定要让用户实际用过再定。

## 6. 验证与交付

- 每项改动配一个开关文件或回滚脚本，并写进交付说明。
- 交付时给用户一张验收清单：怎么操作 → 看什么 → 不满意改哪个参数 → 怎么撤销。
- 记录最终设备状态：改了哪些文件、sha256、如何恢复。

## 7. 安全红线（本机实测，同类设备请先验证）

1. 不要调用 fb ioctl `0x4601`：本机会把 fb 几何改坏（800×600），只能重启恢复。
2. 不要对 fb0 的 mmap 调 `msync()`：deferred-IO 设备会让进程永久卡死在内核里。
3. 直接提交 EPDC 更新时，结构体 +36（temp）填 `TEMP_USE_AMBIENT`（4097），填 0 会选低温波形，慢约 3 倍。
4. 往 SurfaceFlinger 发私有 Binder 报文前，先离线读懂解析器：本机解析器不查越界，格式错一个字段就能让 SurfaceFlinger 崩溃重启。
5. 改系统库：先备份、校验 sha256、原子替换（写临时文件再 `mv`），并写好一键还原。
