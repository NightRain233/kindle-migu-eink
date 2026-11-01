# 翻页软件链路拆分记录（2026-10-31）

## 本轮真实采样

原始日志未公开（体积大且含设备信息）。用 `tapctl` 在正文页注入 4 次、间隔 1 秒的左右交替点击，同时记录设备 `getevent`、二进制 logcat 和 SurfaceFlinger/HAL 日志。

- 注入按下到 HAL `Sending display buffer` 日志：中位 **110.9 ms**，范围 **105.0–136.3 ms**。
- 注入抬起到 HAL 日志：中位 **80.6 ms**，范围 **74.7–98.6 ms**。
- 每个时间窗都只找到一次 HAL 提交，波形均为当前全局实验值 `7/0`。
- 这不是光学延迟，也不是面板驱动完成时间；HAL 日志只是“系统开始把这一帧送往 EPDC”的时间点。它说明软件侧确实可能已经在约 100–140 ms 内走到提交，但不能把这段数字直接叫作用户看到画面的时间。

## 分段计时目前能看到什么

KOReader 的 trace 工具能记录输入处理、布局、绘制、文档拷贝、窗口拷贝和 `unlockAndPost`。本轮临时启用 trace 时发现当前书籍走的是 `ReaderPaging`，而旧工具只埋了 `ReaderRolling` 的翻页回调，所以分析器没有得到可信的 page-turn 链。临时加入 `ReaderPaging` 探针后已完整恢复设备文件；这次尝试没有留下运行时改动。

已有有效的局部事实仍然成立：窗口拷贝约 11 ms，`unlockAndPost` 本身不到 1 ms；更早的有效 trace 中，新页绘制约 46 ms、旧页约 17 ms、文档拷贝约 3–4 ms。下一轮应把 `ReaderPaging` 作为主路径，并在同一轮中对齐：

`getevent 按下 → Lua 收到事件 → 手势判定 → ReaderPaging 翻页 → paint/draw → lock/blit → unlockAndPost → SurfaceFlinger/HAL`。

## 当前判断

约 150 ms 还不能全部归因于波形或面板。现有采样已经把“tapctl 写入”和“HAL 开始提交”之间的量级压到了约 105–136 ms；剩下的关键未知是手势/分页调度、是否等待抬起或双击窗口，以及 SurfaceFlinger 合成前的排队。先把 active reader path 的 trace 对齐，再讨论优化哪一段。
