# 面板刷新耗时实测（2026-10-30，无需外部摄像设备）

> 结论先行：**一次真实翻页，面板被波形成功驱动了 449–450 ms（5/5 次，抖动 ±1 ms）**。
> 换波形可以把这段压到 **177 ms（DU）/ 118 ms（MXCFB 4）/ 272 ms（DU4）**。
> 软件侧"预绘下一页"能省的 30–50 ms 只占整次翻页（约 650 ms）的 5–7%，
> 而换波形省的 273 ms 占 **42%**。→ 优先级应改为"让系统那次提交换波形"。

---

## 1. 为什么以前测不出来

| 旧结论 | 实测真相 |
|---|---|
| "五档波形 wait 都是 7 ms，所以波形没区别" | `mxc_epdc_fb_wait_update_complete()` 里 marker 不在 pending 链表就**直接 return 0**；面板之后仍要驱动约 450 ms。该 ioctl 只能证明"任务已收下" |
| "DU/DU4/GL16/GC16/REAGL/A2 提交都被接受" | ioctl 返回 0 只是入队。提交结构体 `+36` 若为 0，驱动按**低温波形**跑（长度约 3 倍）；`PARTIAL` + 画面内容未变时，GC16 类波形**根本不产生 LUT**（DU 例外） |
| "A2(4) 存在" / "GL16=5 / REAGL=8 编号可能错" | 编号没错：MXCFB 4 → 驱动内部模式 6（118 ms，最快档）；5/6 → GL16；8 → REAGL。内部模式号（`mxc_epdc_waveform_modes` 里 du:1/gc16:2/gl16:3/reagl:4/reagld:5/du4:7）是**另一套命名空间**，不要混用 |
| "v8 补丁的 REAGL 周期清理有效" | v8 用 `wf=8 um=0`（REAGL + PARTIAL），提交时画面内容与已显示内容相同 → **实测完全不产生 LUT**。日志里每条 `wf=8 um=0 ret=0` 都是空转 |

另外：**写 framebuffer 时调用 `msync()` 会卡死**（本 fb 用 deferred-IO，进程永久停在
`fb_deferred_io_fsync`，不可 kill，只能重启）。造"内容变化"请走系统路径（真实翻页），
或只做 ioctl 提交、不碰 fb0（`tools/epdsub`）。

---

## 2. 测量方法（设备内自带，零外部硬件）

1. 读 `<epdc>/mxc_epdc_regs` 会让驱动把**整张 EPDC 寄存器表**打到内核日志
   （sysfs 读返回 0 字节，数据全进 printk）。
2. 边读边排空 `/dev/kmsg`（内核环形缓冲只有约 25 KB，不排空会丢行），
   只保留 `EPDC_STATUS_LUTS` —— 它是**波形引擎正在播放的 LUT 位图**，
   非 0 即"面板正在被驱动"。
3. printk 时间戳用 CLOCK_MONOTONIC，与 tapctl 的时间戳同一时钟，可直接对齐。

采样率约 1000–1400 次/秒（0.7–1 ms 分辨率）；`tools/epdprobe` 即此工具。

**降噪必做**：`echo 1 > /proc/sys/kernel/printk`（否则每次 dump 的 46 行会走串口，
采样周期退到 500 ms）。重启后复位为 7，需重设。

---

## 3. 提交结构体布局更正（早期文档中的 +28 temp 布局有误）

实测：**偏移 +36 = 4097（TEMP_USE_AMBIENT）**。填 0 会让驱动选到低温波形。

```
+0  left   +4 top   +8 width  +12 height
+16 waveform        +20 update_mode     +24 marker
+36 temp（必须 4097；早期笔记里的 "+28 temp"、"+36 dither" 是错的）
+44 alt_buffer(28B) +72 hist_bw         +76 hist_gray
```

对照实验（ioctl 提交，DU，FULL）：

| +36 | UPD_CTRL | LUT 时长 |
|---|---|---|
| 0 | 0x101 | 579 ms |
| 4097 | 0x101 | **177 ms** |

`+36=4097` 后 ioctl 与 sysfs（`mxc_epdc_update` 按名字触发）两条路的时间完全一致，
互为交叉验证。

---

## 4. 波形矩阵（FULL，temp=4097，2 次复现）

| MXCFB 值 | 驱动内部模式 | UPD_CTRL | LUT 时长 |
|---:|---:|---|---:|
| 0 | 0 INIT | 0x001 | 863 ms |
| 1 | 1 DU | 0x101 | **176 / 177 / 177 / 178 ms** |
| 2 | 2 GC16 | 0x201 | 449 / 450 ms |
| 3 | 2（GC4 不存在，回落 GC16） | 0x201 | 450 ms |
| 4 | 6（最快档，疑似 A2/GC4 类） | 0x601 | **118 ms** |
| 5 | 3 GL16 | 0x301 | 449 ms |
| 6 | 3 GL16 | 0x301 | 449 ms |
| 7 | 7 DU4 | 0x701 | **272 / 272 / 271 ms** |
| 8 | 4 REAGL | 0x401 | 449 / 451 ms |
| 257 | AUTO | — | 与 GC16 类同 |

PARTIAL 模式：`wf=1` 仍产生 177 ms LUT（UPD_CTRL 0x100）；`wf=2`、`wf=8`
**不产生 LUT**（画面无变化时驱动直接跳过）。这正是 v8 补丁空转的原因。

---

## 5. 真实翻页基线（KOReader，HAL 自己提交 AUTO+PARTIAL）

5 次点击，间隔 2.4 s，`tapctl` 注入 `/dev/input/event2`（500,400）：

| 点击序号 | 手指按下 → LUT 开始 | LUT 时长 |
|---:|---:|---:|
| 1 | 225.5 ms | 449 ms |
| 2 | 202.5 ms | 449 ms |
| 3 | 221.5 ms | 449 ms |
| 4 | 189.5 ms | 450 ms |
| 5 | 187.5 ms | 450 ms |

一次翻页的完整预算：**约 200 ms 软件链 + 450 ms 面板 ≈ 650 ms**。
（软件链与 codex 侧的分段计时量级一致：绘制 17–46 ms + 拷贝 11 ms + 合成/提交）

---

## 6. 决策含义

| 方案 | 省下的时间 | 占一次翻页（650 ms） |
|---|---:|---:|
| 预绘下一页（codex 线） | 30–50 ms | 5–7% |
| 波形换 DU4(7) | 178 ms | 27% |
| 波形换 DU(1) | 273 ms | 42% |
| 波形换 MXCFB 4 | 332 ms | 51% |

代价是画质：DU / MXCFB 4 是"差异波形"，整页文字更新会有残影累积，
DU4 是折中档。**画质只能用眼睛判**，但"值不值得试"现在有了明确的量化上限。

---

## 7. 复跑

```bash
source scripts/adb-env.sh
adb -s "$SERIAL" shell "su -c 'echo 1 > /proc/sys/kernel/printk'"   # 降低串口打印开销
adb -s "$SERIAL" push tools/build/epdprobe /data/local/tmp/epdprobe
adb -s "$SERIAL" push tools/build/epdsub   /data/local/tmp/epdsub
adb -s "$SERIAL" shell "su -c 'chmod 755 /data/local/tmp/epdprobe /data/local/tmp/epdsub'"

D=/sys/devices/soc0/soc.2/2000000.aips-bus/20f4000.epdc
# 真实翻页基线：0.8/2.5/4.2 s 各点一次，看 LUT 窗口
adb -s "$SERIAL" shell "su -c '(busybox sleep 0.8; /data/local/tmp/tapctl /dev/input/event2 500 400 1 0) & \
  KEEP=EPDC_STATUS_LUTS /data/local/tmp/epdprobe $D/mxc_epdc_regs $D/mxc_epdc_update 3.5 99 gc16 0 0 0 600 800 1 1.0'"
# 单个波形：DU（预期 177 ms）
adb -s "$SERIAL" shell "su -c '(sleep 0.6; DITH=4097 /data/local/tmp/epdsub 1 1 0 0 0) & \
  KEEP=EPDC_STATUS_LUTS /data/local/tmp/epdprobe $D/mxc_epdc_regs $D/mxc_epdc_update 1.9 99 gc16 0 0 0 600 800 1 1.0'"
```

编译：`zig cc -target arm-linux-musleabihf -static -O2 -o tools/build/epdprobe tools/epdprobe.c`

---

## 8. 下一步（当时计划，已由 §9–§10 完成或替代）

以下内容是测量完成当时列出的计划，保留用于解释决策过程；最终方案以 §9–§12 和仓库 README 为准。

1. **让系统那次提交就换波形**（这才是省钱的地方）：HAL / `libsurfaceflinger` 里
   `AndEViewParcel` 的 waveform 默认值是 257(AUTO)，改成 1(DU)/7(DU4) 是**单个常量**的
   patch。验收判据：`EPDC_STATUS_LUTS` 的翻页窗口从 450 ms 变成 177/272 ms，
   且 `EPDC_UPD_CTRL` 从 0x201 类变成 0x101/0x701。
2. 同步看画质：同样 10 页用 DU，与 AUTO 做肉眼 A/B，决定是否配"每 N 页 GC16 清洗"。这部分已由 DU4 + 字体补偿实验继续收敛。
3. v8 补丁可以停用（空转），或改成 DU/PARTIAL（那是唯一在"无内容变化"下还能跑的模式）；实际已选择停用并恢复原厂 Lua 文件。

---

## 9. 换档位验证结果（同日完成，代码已落地）

### 9.1 改动

`/system/lib/libsurfaceflinger.so` 里**全文件唯一一处**写入 257(AUTO) 的指令：

```
vaddr 0x2e8dc:  movw r0, #257   (40 f2 01 10)   ← 默认视图配置的波形
                ↓
vaddr 0x2e8dc:  movw r0, #1     (40 f2 01 00)   ← DU
```

- 原文件 sha256 `f1a2e731…`，补丁版 `f73ca823…`，备份在 `/sdcard/libsurfaceflinger.so.orig`
- 一键开关：`python3 scripts/du-waveform.py on|off|status`（改完需重启）
- 该机器 SELinux 已关闭、`/system`(ext4) 可 remount rw，因此就地原子替换（写临时文件再 `mv`）即可

### 9.2 实测（同一支 epdprobe，`KEEP=EPDC_STATUS_LUTS,EPDC_UPD_CTRL`）

| 场景 | LUT 时长 | `EPDC_UPD_CTRL` | 含义 |
|---|---|---|---|
| 改前·翻页 ×5 | 449/449/449/450/450 ms | `0x201` | GC16 类 + FULL |
| 改后·翻页 ×3 | 177/178/177 ms | `0x100` | DU + PARTIAL |
| 改后·连翻 12 页 | 11×177 + **1×453** | `0x100` ×11，`0x201` ×1 | 周期全刷仍在 |

- 静置 6 s：0 个 LUT 窗口（无残余刷新，测量本身干净）
- 点击 → LUT 开始：187–226 ms（软件链，未变）
- 12 页面板驱动总时间：**2404 ms**（改前同口径约 5400 ms）→ **−55%**

关键一点：**periodic full refresh 仍然生效**，而且它的 `update_mode=FULL` 会让驱动/ HAL
强制回落到 GC16（453 ms）。也就是说"平时 DU 快档 + 每 N 页 GC16 擦一次"这个策略
**不需要额外实现**，KOReader 的 full_refresh_count 已经在做。

### 9.3 翻页预算对比

| 版本 | 软件链 | 面板 | 合计 |
|---|---:|---:|---:|
| 原厂 | ~200 ms | 450 ms | **~650 ms** |
| DU 补丁 | ~200 ms | 177 ms | **~380 ms** |

### 9.4 未验证（需要人看屏幕）

- DU 在整页文字翻页上的残影是否可接受（这是唯一剩下的判断）
- 其他 App（微信读书、启动器、菜单）走 DU 后的观感
- 低电量/低温环境下 DU 的表现

### 9.5 产物

- `scripts/du-waveform.py`：on/off/status，自动校验原厂与补丁版 sha256，双向均已实跑验证
- `tools/epdprobe.c` / `tools/epdsub.c`：测量工具（编译命令见 §7）

### 9.6 补充：小范围刷新 / "按区域分档"是否必要

对同一组 UI 事件（开菜单、关菜单、翻页、再开菜单）各测一遍原厂与 DU 版：

| 事件 | 原厂 | DU 版 |
|---|---|---|
| 菜单打开（画面大改） | `0x304` 456 ms（GL16 类） | `0x100` 178 ms |
| 列表/小范围重绘 | `0x104` 177–180 ms（**本来就已经是 DU**） | `0x100` 173–178 ms |
| 翻页 | `0x201` 449–450 ms | `0x100` 177 ms |
| 整屏彻底刷新（App 启动 / 每 N 页） | `0x201`/`0x304` 440–470 ms | 仍是 `0x201` 443–468 ms |

两个结论：

1. **系统本来就会按"变化大小"选档**：小改动已经走 DU（`0x104`），大改动才走 GL16/GC16。
   所以把默认值改成 DU **不会让小更新变慢**，只是把"大改动"也拉到 DU。
2. **"按区域分档"在这台机器上做不了也没必要**：HAL 每次提交的矩形**恒为整屏
   `600×800`**（`EPDC_UPD_CORD=0`、`EPDC_UPD_SIZE=0x0320_0258`），dirty rect 根本不下传
   （与 §"ANativeWindow dirty bounds 不缩小 EPDC 区域"一致）。判断"改动大小"发生在
   HAL 内部的图像差异分析，不在我们可控的矩形里。

`0x104` 的 bit2（`0x4`）含义未深究，推测与 collision/auto-waveform 标志有关。

### 9.7 收尾状态（2026-10-30）

- `libsurfaceflinger.so` = DU 版（`--waveform 1`），已重启生效
- KOReader `framebuffer_android.lua` 恢复原厂（v8 空转，已停用）；v8 备份在
  `/sdcard/koreader/framebuffer_android.v8.bak`
- 停用 v8 后复测：单击一次 → 画面变化 15.8% → **1 个 LUT 窗口，176 ms，`0x100`**
  （证明翻页加速来自 SF 补丁，与 KOReader 补丁无关）

### 9.8 最终选择：DU4（waveform=7）

DU（177 ms）速度最快，但只有黑白两级，KOReader 排版的抗锯齿灰边无法表达，
正文观感"字变淡"。实测这台机器上：

- KOReader 的 `copt_font_gamma`（Contrast）**是空转的**：改成 10/25，截图 0 像素变化
  （同期翻页截图差异 21%，证明截图管线正常）
- 直接写 `copt_font_base_weight` 会被 KOReader 重启时丢弃

因此改用 **DU4（272 ms，4 级灰度）**：`EPDC_UPD_CTRL=0x700`，实测 222–281 ms，
比原厂 450 ms 仍快约 40%，且能表达文字边缘的中间灰。

| 档位 | 面板时间 | 观感 |
|---|---:|---|
| DU (1) | 177 ms | 最快，正文偏淡 |
| **DU4 (7)** | **272 ms** | 当前选择，笔画更实 |
| GC16/GL16 类 | 449–451 ms | 原厂，最干净 |

---

## 10. 观感补偿实验（同日，用户反馈"翻页后字很淡"）

### 10.1 现象拆解

"淡"有两个来源，必须分开处理：

1. **渲染层**：KOReader 排出的字带抗锯齿灰边；DU 只有黑白两级、DU4 只有 4 级，
   中间灰被量化掉 → 笔画变细
2. **驱动层**：快档脉冲短，整页换字时粒子未必被推到"最黑"位置 → 整体对比度下降。
   这一层只有 GC16（会闪、450 ms）能保证

### 10.2 旧结论更正：先让 CR3 缓存失效

| 尝试 | 结果 |
|---|---|
| 直接改 gamma/base weight、保留原 `.cr3` | 页面继续命中旧字形缓存，看起来不变 |
| 删除对应 `.cr3` 后重开 | gamma 与 base weight 均生效 |
| `font_base_weight=+3` | 笔画过重，并改变分页 |

所以之前“Contrast 空转、base weight 被丢弃”的结论是缓存造成的误判。

### 10.3 有效的路：换字体

`<book>.sdr/metadata.epub.lua` 里的 `font_face` 是每本独立的；全局默认在
`settings.reader.lua` 的 `cre_font`。必须使用 FontList 的家族名：

`LXGW WenKai`、`STBShusong`、`STBShusong-Bold`、`MYing Hei T`

用同一页截图做量化验证（暗像素越多，字越实）：

| gamma | base weight | 暗像素 |
|---:|---:|---:|
| 10 | +1 | 32,651 |
| 15 | +1 | 35,320 |
| 25 | +1 | 39,377 |
| 30 | +1 | **41,992** |
| 36 | +1 | 44,166 |

当前采用 DU4 + `font_base_weight=1` + `font_gamma=30` + `font_hinting=1`。

### 10.4 注意事项（踩过的坑）

- **不要用"最新修改时间的 .sdr"来定位当前书**：KOReader 被 force-stop / 重开时
  会把不同书的 metadata 写成最新，脚本会改错书。正确做法是先读
  `/sdcard/koreader/history.lua` 的 `[1].file`，再按文件名精确定位。
  （本次就因此把字体改到了《13.67》而不是《挽救计划》。）
- 频繁 `am force-stop` + 重启会让阅读位置漂移；改设置前后要记录并恢复
  `last_xpointer`（备份文件同目录 `metadata.epub.lua.bak-*`）。

## 11. 当前最终配置（2026-10-30 收尾）

| 项 | 值 |
|---|---|
| 面板档位 | **DU4（waveform=7）**，翻页 272 ms（原厂 450 ms，仍快 40%） |
| 驱动读数 | `EPDC_UPD_CTRL = 0x700`（DU4 + PARTIAL） |
| 周期全刷 | 保留，`0x201` / 448–452 ms，约每 10 页 |
| KOReader 直连补丁 | 已停用（原厂 `92ea6de0…`） |
| 字体 | 《13.67》已改 `STSongBold`；其余书仍是霞鹜文楷，需逐本改或改全局 `cre_font` |
| 一次翻页总预算 | 约 200 ms 软件 + 272 ms 面板 ≈ **470 ms** |

## 12. 复测：官方包为何“变快”、候选包对比（2026-11-01，全局已恢复原厂 AUTO）

同一本书（《情绪急救》）、同一手法（tapctl 前进 3 页 + 后退 3 页，间隔 2.5 s），`settle` 关闭：

| 场景 | 面板时间 | `EPDC_UPD_CTRL` | 观感 |
|---|---|---|---|
| A 官方包 + 全部补丁 + 预量化 | 447–451 ms ×6 | `0x304` | 不闪，GL16 局部 |
| B 官方包 + 补丁、预量化关 | 446–450 ms ×6 | `0x304` | 同上 |
| C 官方包、**全部补丁停用** | 448–453 ms ×6 | `0x304` | 同上（用户实测：不慢但残影重） |
| D 候选包 + 补丁 + 预量化 | 271–274 ms ×6 | `0x700` | DU4 局部，每 10 页一次 `2/1` 全刷 |

- 第 10 节“改前”的官方翻页是 `0x201`（GC16 全刷，每页黑白闪）；现在同样是 AUTO，驱动改挑 `0x304`（GL16 局部，不闪）。
  面板时间没变（约 450 ms），**变快是因为不再每页闪黑**。C 说明这与我们的补丁无关；为何 AUTO 改挑档位未确证
  （可能与字体/字重改动后画面灰阶分布变化有关）。
- GL16 不清残影，官方包又不知道自己是墨水屏（`FakeEPDController`），永远不发周期全刷，所以残影只会累积。
- 候选包仍快约 40%（272 vs 450 ms），且每 10 页清一次残影，保持为日常主力；`settle` 补刷因“第二次可见变化”体验差，默认关闭。

追查“改前为何是 `0x201`”（同书同手法，均为官方包）：

| 还原的条件 | 结果 |
|---|---|
| E 停用全部补丁 + 字体参数改回原样（`LXGWWenKai-Regular` 无效名→回落默认字体、gamma 15、字重 0、hinting 2） | 449–451 ms，全部 `0x304` |
| F 再装回 v8 直连补丁（`framebuffer_android.v8.bak`） | 449–451 ms，全部 `0x304` |
| G 再停掉按应用刷新助手 | 翻页仍全部 `0x304`；另出现 2 次与翻页无关的 `0x201`（约 450 ms） |

结论：字体、v8、刷新助手都不能让翻页回到 `0x201`，当天的条件无法复现。第 10 节的 `0x201` 很可能不可比
（当时只记录了 LUT 开始前最后一次非零的 `UPD_CTRL`，可能被别的提交覆盖；当天的软件链也不同）。
确定的是：**原厂 AUTO 下官方包翻页的面板时间始终约 450 ms**，现在为不闪的 GL16 局部刷新。测试后已全部还原。
