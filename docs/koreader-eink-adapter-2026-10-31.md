# KOReader 电子墨水适配复核（2026-10-31）

## 新确认的事实

这次直接检查了设备上安装的 `org.koreader.launcher` v2026.07.1，而不是只看补丁源码。

- APK 的 `assets/android.lua` 已经包含完整的电子墨水入口：`android.isEink()`、`android.isEinkFull()`、`android.einkUpdate()` 和 `android.getEinkConstants()`。
- APK 的 `EPDFactory` 也包含 Freescale/NTX 控制器，但设备识别条件只覆盖 `freescale + evk_6sl_eink`、Nook/Tolino 等已知组合。当前设备属性是 `ro.hardware=freescale`、`ro.product.manufacturer=Amazon`、`ro.product.model=KFBJWI`、`ro.product.device=eanab`，因此落入 `FakeEPDController`，不会打开 KOReader 的五档刷新分支。
- `framebuffer_android.lua` 的五档策略仍然存在：普通正文、完整刷新、UI、快速刷新和部分 UI 更新分别走不同的 Android EPD 模式；只是 `isEink` 为 false 时这些调用被跳过。

## 系统已经在做什么

从实机 `logcat` 可以看到，SurfaceFlinger 每次接收 KOReader 的 600×800 缓冲后都会：

1. 询问 `AndEChoreographer` 当前图层的刷新决策；
2. 由 `gralloc.EANAB.so` 把 RGB565 转成灰度并提交 EPDC；
3. 当 KOReader 没有提供页面级 `AndEViewParcel` 时，日志中的 `listSize=0`，于是使用全局默认波形。

当前全局补丁把这个默认值从 `257(AUTO)` 改成了 `7(DU4)`，所以 KOReader 页面、系统菜单和其他应用都会受到同一改动影响。日志同时证明系统原本存在独立的全屏清理路径：系统 UI 触发时会返回 `update mode 2`，随后使用 `waveform:3, updatemode:1` 的白屏/全刷流程。

## 对方案的意义

这排除了“只能在 DU4 和 AUTO 之间二选一”的误解。更合理的目标是：

- 默认仍让系统使用 AUTO，保证菜单、图片、其他应用和复杂页面有合适的波形；
- 只给 KOReader 的阅读图层附加页面级刷新策略，正文使用 DU4 或其他实测档位；
- 章节切换、图片页、停止快速翻页后的清理沿用系统已有的全刷/高质量路径；
- 只有在确认不会产生第二次提交后，才让 KOReader 的 `android.einkUpdate()` 真正参与调度。

## “骗过识别”实验的边界

KOReader 的 Android 启动器是 MIT 开源项目。它把设备识别、`EPDFactory` 和 Java 到 Lua 的刷新桥接分开实现，因此可以维护一个只增加 `eanab` 支持的定制 APK，而不必复制整个阅读器。

但只在 Lua 中把 `android.isEink()` 改成 `true` 不够：Java 侧仍会返回 `FakeEPDController`，`einkUpdate()` 只是空调用；即便强行打开 Lua 分支，SurfaceFlinger 仍会先按自己的规则提交一次。

我们还检查了启动器现有的 Freescale/NTX 控制器。它依赖一个六参数的隐藏方法：
`View.postInvalidateDelayed(long, int, int, int, int, int)`。在本机用最小测试 APK 反射检查后，该方法不存在，因此不能直接把 `eanab` 映射到 `NookEPDController` 或 `TolinoEPDController`。

这意味着定制版本需要一个新的 `EanabEPDController`，调用本机真正存在的 Amazon/AndEChoreographer 接口，或者调用一个经过同步设计的 native helper。现有 NTX 控制器可以复用接口和刷新分类的框架，但不能直接复用实现。

## 下一步（顺序已调整）

第一阶段的 observe-only launcher 补丁已经写在 `eanab-launcher/`，并已用独立 debug 包启动验证。它不再是协议验证的前置步骤。接下来按这个顺序走：

1. 先用直接 Java Binder 或 native `constructParcel` 还原一个最小合法 `AndEViewParcel`；确认 `waveformList/updateModeList` 能改变指定 layer 的那一次 HAL 提交，并确认没有第二次提交。
2. 并行把软件链路 trace 补到当前实际使用的 `ReaderPaging`，对齐 `getevent → Lua → 分页 → 绘制 → post → HAL`。
3. Parcel 通过后，再用独立 applicationId 的 launcher 承接五类 KOReader 回调；控制器先保持日志/计数，随后才转换成真实的单次 Parcel。
4. 如果 layer 级配置不可用，再评估按 KOReader layer 名称分流的 SurfaceFlinger 条件补丁；这时 launcher 只保留为观察工具。

更具体地说，定制版的最小改动集中在三处：`DeviceInfo` 增加 `Amazon/KFBJWI/eanab`，`EPDFactory` 增加 `EanabEPDController`，再由该控制器承接 AndE parcel。排版、字体、书籍数据库和阅读逻辑都保持上游版本不变。单独把 `isEink()` 改成 true 不能作为最终方案，因为当前系统仍会自动提交一次，可能造成重复刷新。

## 当前结论

这两天的工作没有白费：已经测出了 DU/DU4/GC16 类波形的真实时间，确认了字体渲染侧的补偿方法，也找到了系统原有的按图层调度入口。需要调整的是作用范围：全局替换默认波形只是实验手段，最终应改成按图层、按页面类型选择波形。
