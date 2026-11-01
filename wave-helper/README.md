# 按应用刷新助手（eanab-wave）

让**不能修改源码的应用**（目前是微信读书 `com.tencent.weread.eink`）使用指定的墨水屏刷新方式，
其他应用和系统界面保持原厂 AUTO。KOReader 候选包会自己按场景指定，不经过这个助手。

## 原理

- SurfaceFlinger 的 code 200 接受任意进程按 **layer 名**提交 AndE 刷新配置（报文格式见
  `docs/ande-parcel-format-2026-10-31.md`），能覆盖系统对普通应用的默认决定；
- 但配置是**一次性的**：只作用于该 layer 的下一帧。外部无法预知应用何时出帧，所以目标应用在前台且亮屏时
  每 40 ms 重发一次；其余时间每秒检查一次前台，不发送；
- layer 名会随窗口重建变化（实测 `…ReaderFragmentActivity_2_2` → `_3_1`），从 `dumpsys SurfaceFlinger` 读取真实名字：
  前台切换后 0.5/1.5/3 s 各查一次，之后每 20 s 一次。

## 实测（2026-10-31，全局已恢复 AUTO）

| 场景 | 结果 |
|---|---|
| 微信读书翻页 6 次 | 17 帧全部 `waveform:7`（DU4），未装助手时为 `257`（AUTO） |
| 微信读书的菜单/弹窗 | 是独立 layer（`PopupWindow:…`），不受影响，仍走系统决定（AUTO/GC16），更清楚 |
| 桌面、其他应用 | `257`（AUTO），助手不发送，CPU 0% |
| KOReader 候选包 | 不受影响（翻页 7/0 + 停下 5/0） |
| 熄屏（微信读书仍在前台） | 不发送，CPU 0% |
| 资源 | 微信读书前台时助手约 2–3% CPU；内存稳定约 27 MB（JNI 复用配置对象，无泄漏） |

## 文件与用法

| 文件 | 作用 |
|---|---|
| `src/EanabWaveHelper.java` | 主程序：`once <layer> <wf>`、`burst …`（实验）、`daemon <rules>` |
| `native/eanabwave.cpp` | JNI：用设备自带序列化器生成报文（改写自 eanab-launcher `eanabparcel.cpp`，layer 名参数化、修复每次发送的内存泄漏） |
| `rules.txt` | 规则：每行 `包名 波形号`（7=DU4，1=DU，257=AUTO） |
| `build.sh` / `install.sh` / `uninstall.sh` | 构建 / 安装并启动 / 卸载 |
| `eanab-wave.sh` | 开机脚本（Magisk `service.d`）——**目前不会被执行**，见下 |

- 日志：`/sdcard/koreader/eanab-wave.log`；临时停用：建 `/sdcard/koreader/eanab-wave.off`
- 手动启动：`adb shell su -c '/data/adb/magisk/busybox setsid sh -c "CLASSPATH=/data/local/tmp/eanab-wave/eanab-wave.dex exec app_process /system/bin EanabWaveHelper daemon /data/local/tmp/eanab-wave/rules.txt >/dev/null 2>&1 </dev/null" &'`（只用 `nohup … &` 时 adb 断开后进程会被带走，2026-11-01 实测）

## 已知问题：开机不会自动启动

这台设备上 Magisk 的开机流程停在“Loading modules”，**`/data/adb/service.d/` 下的脚本都不会执行**
（原有的 `fb0_perm.sh` 也一直没生效，`/dev/graphics/fb0` 开机后仍是 660）。所以重启后助手不会自己起来，
需要手动启动或另选自启方式（待用户决定：做一个开机广播小应用，或修 Magisk）。
