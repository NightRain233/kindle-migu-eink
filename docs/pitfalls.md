# 坑点清单

每条按“现象 → 原因 → 怎么验证 → 怎么解决”写。标 **[本机]** 的只在 Kindle 咪咕版（i.MX6SL / e3os）上验证过，别的设备请先复核。

## 一、测量

### 1. ioctl 返回 0 不代表屏幕刷了
- 现象：各种波形提交都“成功”，等待完成的 ioctl 都是约 7 ms，看起来波形没区别。
- 原因：i.MX `mxc_epdc_fb_wait_update_complete()` 在 marker 不在等待队列时直接返回 0；提交只代表入队。
- 验证：同时轮询 `EPDC_STATUS_LUTS`，看有没有 LUT 窗口、多长。
- 解决：只用面板侧证据计时（`tools/epdprobe.c`，方法见 `panel-timing-2026-10-30.md` §2）。

### 2. 画面没变的局部刷新会被跳过
- 现象：一个“定期清残影”的补丁日志里每次都 `ret=0`，屏幕却没反应。
- 原因：PARTIAL 模式下像素没有变化时，GC16 / GL16 / REAGL 不产生 LUT（DU 例外）。
- 验证：同上，看 LUT 窗口。
- 解决：要清残影就用 FULL 模式；要补刷就先让像素真的变化（比如从 4 级灰重画成 16 级灰）。

### 3. 测量时内核日志走串口，采样率掉到 2 Hz
- 原因：寄存器 dump 每次 46 行，printk 级别高时同步写串口。
- 解决：`echo 1 > /proc/sys/kernel/printk`；重启后会复位。

### 4. 截图看不到墨水屏的真实效果
- `screencap` 读的是帧缓冲。DU4 的灰阶损失、残影、闪烁都只在面板上。截图只能用来确认内容（排版、灰阶分布），观感要人看。

### 5. 旧记录不一定可比
- 现象 **[本机]**：一条旧记录说原厂翻页是 `0x201`（GC16 全刷，每页闪），复测怎么也复现不出（现在是 `0x304` GL16 局部不闪）。
- 教训：用来下结论的对比，最好在同一天、同一工具、同一手法下重新测；旧数据只作线索。

## 二、驱动与系统

### 6. 波形编号每台设备都不一样
- 现象 **[本机]**：上游 KOReader NTX 代码把 4 叫 AUTO；本机 4 是 118 ms 的黑白档，真正的 AUTO 是 257，5 是 GL16。
- 另外驱动内部模式号（`mxc_epdc_waveform_modes`：du:1 / gc16:2 / gl16:3 / reagl:4 / du4:7）是另一套编号，和提交用的 MXCFB 值不同。
- 解决：逐个波形号提交并计时，自己建表（`panel-timing-2026-10-30.md` §4）。

### 7. 提交结构体 +36 填 0 会慢 3 倍 **[本机]**
- 原因：+36 是温度字段，0 被当作低温，选到长波形。填 `TEMP_USE_AMBIENT`（4097）。

### 8. 危险调用 **[本机]**
- ioctl `0x4601`：把 fb 几何改成 800×600，整屏刷新被丢弃、黑灰分屏，只能重启。
- 对 fb0 的 mmap 调 `msync()`：deferred-IO，进程永久卡在 `fb_deferred_io_fsync`，kill 不掉。

### 9. dirty rect 缩不小刷新区域 **[本机]**
- `ANativeWindow_lock` 的 dirty rect 不影响 SurfaceFlinger 的 damage，HAL 总是整屏提交。想要局部刷新得走厂商协议里的矩形。

### 10. 开机脚本不一定会执行 **[本机]**
- Magisk 23 的 post-fs-data 卡在 “Loading modules”，`/data/adb/service.d/` 从不执行。装完开机脚本要重启验证一次。

### 11. adb 启动的后台进程会随断开退出
- 现象：`su -c 'nohup app_process … &'` 起来的守护进程，adb 一断就没了。
- 解决：`busybox setsid sh -c "exec app_process … </dev/null >/dev/null 2>&1" &`，确认父进程是 1。

## 三、厂商协议（亚马逊 AndE，**[本机]**）

### 12. 报文格式错一点就失败，或者直接让 SurfaceFlinger 崩溃
- `transaction 200` 的 data 必须直接是 `AndEViewConfig::constructParcel` 的输出：首个 int32 是 0（异常码），**不能**加 interface token。
- layer 名为空会报 `CUSTOM WINDOW PARCEL layer name undefined`；skip 列表比其他列表短时解析器越界，SurfaceFlinger 空指针崩溃。
- 解决：用设备自带 `libandechoreographer.so` 的序列化器生成报文（`eanab-launcher/direct-apk/native/eanabparcel.cpp`），不要手拼。

### 13. 配置是一次性的
- 只作用于该 layer 的**下一帧**。要持续生效就每次刷新前都发（适配包），或在前台时高频重发（助手每 40 ms）。

### 14. layer 名会变
- 格式 `包名/Activity全类名_A_B`。微信读书实测从 `_2_2` 变成 `_3_1`；KOReader 恒为 `_1_1`。从 `dumpsys SurfaceFlinger` 的 `+ Layer 0x… (名字)` 读。

## 四、KOReader

### 15. 刷新顺序：先交画面、后发参数，会让每帧沿用上一次的波形
- 现象：菜单之后的第一次翻页走了菜单的 AUTO，翻页之后的菜单走了 DU4。
- 原因：`ffi/framebuffer_android.lua` 先 `_updateWindow()` 再 `einkUpdate()`；SurfaceFlinger 比参数早约 2 ms 拿到画面。
- 验证：同时看 HAL 日志的波形与 App 发出的参数，是否一一对应。
- 解决：先发参数再交画面（`koreader-ui/patches/2-eink-ande-order.lua`）。

### 16. 不认识设备时，KOReader 的墨水屏逻辑全部不运行
- `EPDFactory` 不认识设备就返回 `FakeEPDController`，`isEink()` 为 false：不分场景选刷新方式，也不做周期全刷，残影只会累积。
- 不能冒充别的设备：NTX / Nook / Tolino 控制器依赖本机没有的隐藏方法 `View.postInvalidateDelayed(long,int,int,int,int,int)`。

### 17. 字体名写错会静默回退
- `font_face` 必须是 FontList 里的家族名（如 `LXGW WenKai`），写文件名（`LXGWWenKai-Regular`）不报错，直接回退到默认细字体。
- 改了 metadata 记得删该书的 `.cr3` 排版缓存。

### 18. 多个 KOReader 包共用 `/sdcard/koreader/`
- 任何一个在运行，退出时都会把内存里的旧设置写回去，覆盖你的修改。改设置前停掉所有包。

### 19. 按“最近修改时间”找当前书会找错
- KOReader 被强制停止或重开时会改写别的书的 metadata。当前书以 `history.lua` 的第一项为准。

### 20. 每本书的设置优先于全局
- `<书>.sdr/metadata.*.lua` 的 `copt_*` 一旦存在就覆盖 `settings.reader.lua` 的 `cre_*`；排查排版先看 sdr。
- 行距是乘法：书的 CSS 自带 `line-height: 1.5` 时再乘 145% 会过散。
- 中文 epub 常用正文里的全角空格做缩进，和 CSS 的 2em 叠加成 4 字缩进；缩进只留一个来源。

### 21. Lua 补丁的小坑
- 语法错误会让 KOReader 启动即崩：部署前 `luajit -e 'assert(loadfile("x.lua"))'`。
- 不要自己 `ffi.cdef clock_gettime`（与 KOReader 冲突），用 `ffi/util.gettime()`。
- 安卓上 logcat 看不到 Lua 日志时，自己写文件（本仓库补丁出错会写 `koreader/eanab-ui-error.log` 并退回原版）。
- 可以在 `koreader/patches/` 放 `.patches_disabled` 临时停用全部补丁，做对照很方便。

### 22. adb 点按测试的坑 **[本机]**
- 屏幕下部（y≈650）会唤出底部菜单，曾误触“屏幕方向”把书转成横屏；四个角是手势区。翻页点屏幕中部。

## 五、体验设计

### 23. “先快后清”数据好看，用起来分心
- 翻页用 DU4、停 1 秒后自动 GL16 补刷恢复 16 级灰。技术上成立，但用户感受到的是“刚开始读，画面又动了一下”。已默认关闭。
- 教训：会产生第二次可见变化的优化，先让用户实际用一段时间再定。

### 24. 不闪 ≠ 快
- GL16 局部刷新和 GC16 全刷的面板时间一样（约 450 ms），但前者不闪黑，主观上快很多。评估“快不快”时把面板时间和闪不闪分开记。
