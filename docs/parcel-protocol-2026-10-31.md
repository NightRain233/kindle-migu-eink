# AndEViewParcel 协议验证记录（2026-10-31）

## 已经确认的部分

- `SurfaceFlinger` transaction `200` 可以由普通 APK 通过 Java 反射取得 `SurfaceFlinger` Binder 后直接调用。一次调用在设备上约几毫秒内返回 `transact ok=true`，没有权限拒绝，也没有卡死。
- `service call SurfaceFlinger 200 ...` 不能作为这个实验的可靠工具。它会自动加入 shell 侧的 Binder 处理内容；实测会得到 `Failed to parse AndEViewParcel due to exceptions`。直接 `IBinder.transact(200, data, reply, 0)` 才能控制原始 Parcel。
- 全零测试 Parcel（60 个 `int32`，240 字节）能进入厂商解析路径，日志出现 `CUSTOM WINDOW PARCEL layer name undefined`，设备没有崩溃。说明 transaction 入口和异常保护都是真的。
- 加入字符串或接口令牌后，调用仍然能返回，但字段顺序不对时会出现 `Failed to parse AndEViewParcel`，说明现在的主要问题是报文布局，不是 Binder 通道本身。
- 已在独立 stage2 APK 中加入一个隔离的 JNI 探针：它通过系统
  `libandechoreographer.so` 的 `AndEViewConfig` 构造器、`updateViewConfigVectors`
  和 `constructParcel` 生成报文。过程中修正了 Android 5.1 `VectorImpl` 的 20 字节
  布局，并确认 `updateViewConfigVectors` 的第 1 个整数是 waveform 列表，第 6 个
  整数才是 updateMode 列表。
- 2026-10-31 的实机对照实验固定请求 `waveform=2`、`updateMode=1`。日志显示
  `org.koreader.launcher.eanab.stage2/...MainActivity_1_1` 被 SurfaceFlinger 识别，
  紧接着的 HAL 提交变成请求的区域和参数，例如
  `Rect[Left:68 Top:373 Width:532 Height:427], waveform:2, updatemode:1`。
  这证明第三方 APK 发出的合法 Parcel 已经能让系统那一次提交采用指定波形，
  不是额外追加一张“补刷”。
- 日志里仍会出现少量 `Reading a NULL string not supported here`，但没有
  `Failed to parse AndEViewParcel`、`Binder transmission error` 或进程卡死；这些
  目前看是厂商解析器对可选字符串的噪声，不能作为协议失败的依据。
- 当前 stage2 与稳定候选包都已接入真实刷新类别映射；native 层按当前包名生成
  layer key，固定的 Activity 后缀仍是 `_1_1`，Activity 重建后的后缀变化需要继续验证。

## 尚未证明的部分

协议的最高风险已经解除，候选控制器也已经接入 KOReader 的真实刷新类别。页面级窗口
已分别看到正文 `7/0`、快速 `1/0`、菜单 UI `257/0`、全屏清理 `2/1`；剩下的是
书库/封面启动过渡的多帧行为、Activity 重建后的 layer 后缀、配置持续时间、画质和
残影。这些属于策略和回归问题，不再是 Binder/Parcel 通道是否可行的问题。

离线反汇编给出的关键边界仍然保留：`libandechoreographer.so` 同时导出了
`AndEViewConfig(Parcel const&)`、`constructParcel(...)`、`addIntVectorToParcel(...)`
和 `updateViewConfigVectors(...)`；SurfaceFlinger 的 code 200 会把 Parcel 送入这条路径。

## 当前结论

Parcel 方案已经通过最高风险的第一道门：第三方进程可以直接触达 code 200，
合法报文能让目标图层的那一次 HAL 提交采用指定 waveform/updateMode，且没有因为
探针产生第二次同区域提交。真实刷新类别已经接入候选控制器，正文和快速单次窗口的
HAL 计数均为 1；下一步是确认配置持续时间、Activity 重建后的 layer 后缀，以及书库
和封面启动过渡的画质、延迟和残影。
