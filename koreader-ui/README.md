# KOReader 界面美化（eanab）

只用 KOReader 的用户补丁机制（`koreader/patches/*.lua`）、用户图标目录和设置项实现，
**不改 APK、不改 `/data/data/.../files` 里的源码**。官方包和 `eanab-launcher/` 适配包都能用；
标“仅候选包”的补丁只在适配包里生效（依赖 `android.isEinkFull()`）。

## 内容

| 文件 | 作用 |
|---|---|
| `patches/1-eink-palette.lua` | 界面灰色常量收敛到 `0x00/0x55/0xAA/0xFF`（DU4 精确灰阶，GC16/GL16 下也落在色阶上） |
| `patches/1-eink-fontmap.lua` | 界面字体统一为思源黑体：常规 Medium、标题 Bold；等宽字体不变 |
| `patches/2-eink-ui.lua` | Medium→Bold 真粗体登记；开关选中态纯黑；所有列表单页时隐藏翻页栏；底栏“本章还剩 N 页”、低电量才显示电量 |
| `patches/2-eink-ande-order.lua` | **刷新顺序修复**（仅候选包）：先下发 AndE parcel 再把画面交给窗口。原版顺序相反，导致每帧都沿用上一次的波形（菜单后的翻页走 257、翻页后的菜单走 7） |
| `patches/2-eink-settle.lua` | **先快后清**（仅候选包，**默认关闭**：`deploy.sh` 会创建 `koreader/eanab-settle.off`，删掉即启用；实际使用中“1 秒后画面再变一次”比不补更让人分心）：翻页走 DU4+预量化；停留 1.0 s 无新刷新则重绘本页（不量化）并以 GL16(5) 局部补刷，恢复 16 级灰。任何刷新都会取消待补刷。开关 `koreader/eanab-settle.off` |
| `patches/2-eink-du4-quantize.lua` | **DU4 预量化**：交给窗口前把刷新区域换算成 4 个灰阶，分界偏深让笔画更实。官方包下处理所有刷新；候选包（`android.isEinkFull()`）下只处理走 DU4 的正文翻页（`refreshPartialImp`），菜单/书库（AUTO）和全刷（GC16）保留 16 级灰。紧急开关 `koreader/eanab-quant.off`，耗时日志 `koreader/eanab-quant.log` |
| `patches/2-eink-library.lua` | 书库：左对齐“书库”标题 + 藏书数；主目录第一页“继续阅读”卡片；按最近阅读排序的书架行；封面 4 级有序抖动（`DITHER_COVERS`） |
| `tools/thicken-icons.py` | 以设备上自带 `mdlight` 图标为底，线宽 ×1.5，输出到 `koreader/icons/` |
| `tools/settings.lua` | 改/还原 `settings.reader.lua`（主目录真实路径、隐藏 `../`、底栏布局）；首次部署时把原值存到设备 `koreader/eanab-ui-orig-settings.lua` |
| `deploy.sh` / `rollback.sh` | 一键部署 / 回滚 |

字体文件（`fonts/`，约 33 MB）不进 git，`deploy.sh` 缺失时自动从 notofonts/noto-cjk 下载。

## 部署与回滚

```sh
koreader-ui/deploy.sh     # 停 KOReader → 改设置 → 推补丁/字体/图标 → 启动
koreader-ui/rollback.sh   # 删补丁/字体/图标，设置键恢复原值
```

**注意**：设备上有两个 KOReader 包——官方 `org.koreader.launcher` 和候选包 `org.koreader.launcher.eanab`，
共用 `/sdcard/koreader/`。任何一个在运行时都会在退出时回写内存里的旧设置，所以两个脚本都会先把它们都 force-stop。

## 验证状态（2026-10-31，已部署）

真机确认：标题栏“书库 / 共 N 本”、“继续阅读”卡片（点按打开书）、按最近阅读排序的书架、
隐藏 `../`、单页隐藏翻页栏、封面 4 级抖动、思源黑体、开关选中态纯黑、阅读底栏
（进度条在上；左“本章还剩 N 页”，右时间；电量 ≤20% 或充电时才显示）。部署后无报错。

安全网：书库排版任何一步出错，会把堆栈写入 `/sdcard/koreader/eanab-ui-error.log`，
并自动退回原版列表（本机 logcat 里看不到 KOReader 的 Lua 日志，排查靠这个文件）。

待肉眼确认（截图拿到的是帧缓冲，看不到 DU4 刷到面板上的真实效果）：
- 小封面抖动是否太粗糙：不好看就把 `2-eink-library.lua` 顶部 `DITHER_COVERS` 改为 `false`，重新部署
- 加粗图标的粗细是否合适：调 `deploy.sh` 里 `thicken-icons.py` 的倍数（当前 1.5）

### DU4 预量化实测（2026-10-31，候选包 `org.koreader.launcher.eanab`）

- 启动日志 `eink_full=true targets=refreshPartialImp`，只处理正文翻页；
- 49 次翻页：44 次 HAL `waveform:7/updatemode:0` + 5 次周期 GC16 `2/1`，**每页仍只 1 次提交**；
- 量化耗时：整屏 480000 像素，40 次平均 **11.0 ms**，最大 30.6 ms（首次 JIT 预热）；
- 截图统计：正文只剩 4 个灰阶（RGB565 后为 0/84/171/255），其余零星像素来自右缘系统悬浮条；
- 深浅调节：补丁开头 `T_BLACK/T_DARK/T_LIGHT`（当前 0x50/0x9A/0xE0），数值越大越深。

**测试注意**：adb 点按翻页请用屏幕中部（如 `input tap 420 400` 前进、`100 400` 后退）。
y≈650 会落进底部菜单触发区，曾因此误触“屏幕方向”把书转成横屏（已从 `metadata.epub.lua`
的 `copt_rotation_mode` 改回 0）；右缘 x>575、y≈440–490 是 e3os 系统悬浮条。

### 先快后清与刷新顺序（2026-10-31，候选包）

- 刷新顺序修复前：HAL 提交比 parcel 早约 2 ms，每帧使用上一次的配置；修复后 REQ 与 HAL 一一对应
  （翻页 7/0、菜单 257/0、全刷 2/1），parcel 构造 <1 ms；
- 先快后清：翻页 7/0 后约 1.0 s 出现 `5/0` 整页补刷，只改变约 4.5 万个边缘像素，截图灰阶 42→77；
  tapctl 400/700 ms 连翻时中途零补刷，停下后补 1 次；
- 界面走查（书库、长按菜单、顶部 6 标签、底部 6 标签、目录、历史、搜索+键盘、对话框）无错位，错误日志为空。

各参数怎么调见上文与 `docs/case-study.md`。

