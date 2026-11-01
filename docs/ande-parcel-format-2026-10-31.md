# SurfaceFlinger code 200 / AndEViewParcel 报文格式（离线反汇编，2026-10-31）

> 报文布局结论来自离线反汇编；后续 JNI 探针已在设备上用真实 Binder 调用验证最小报文。
> 来源：设备 `/system/lib/libsurfaceflinger.so`（sha256 `f1a2e731…`）、`/system/lib/libandechoreographer.so`（sha256 `a104cd52…`），本仓库不附带这些文件。
> 工具：`xcrun llvm-objdump` + pyelftools 解析 PLT（脚本：`scripts/re/arm-plt-symbols.py`、`scripts/re/arm-call-flow.py`）。

## 结论（对应第二阶段的两条报错）

1. **SurfaceFlinger 对 code 200 没有任何“外层”格式。** `SurfaceFlingerExtended::onTransact`
   收到 200 后直接 `AndEViewConfig cfg(data)`，把整个 data Parcel 交给
   `AndEViewConfig::AndEViewConfig(Parcel const&)` 解析；没有 interface token、没有外层 layer map。
   “layer map” 是 SF 内部的 `SortedVector<key_value_pair_t<String8, AndEViewConfig>>`
   （`this+5536+16`），键就是从报文里解析出的 layer 名。
2. **`Failed to parse AndEViewParcel due to exceptions`**：解析器第一步是
   `Parcel::readExceptionCode()`（这个解析器原本用来解析调 AndEChoreographerService 的 **AIDL 应答**，
   日志字符串 `[getLastParcel] After receiving the parcel data from AndEChoreographerService` 可证）。
   第一个 int32 不是 0 就走异常分支。**报文前面加了 interface token（或任何前缀）必然触发这条。**
3. **`CUSTOM WINDOW PARCEL layer name undefined`**：解析成功后，SF 检查 `cfg` 偏移 0 处的 String8，
   判断条件是底层 SharedBuffer 长度 `== 1`，也就是**空字符串**。layer 名来自报文里
   waitForCompletion 列表之后的**第二个** String16。
   用 `AndEViewConfig()` + `updateViewConfigVectors(...)` 构造的对象**从不设置 layer 名**，
   `constructParcel` 会把这个空名字原样写两遍，所以 SF 必然报 undefined。
   全零 60×int32 的探针报文同理（两个字符串都是空）。

`constructParcel` 本身的写出顺序与解析器完全对称（开头就是 `int32 0`、`int32 0`），
**序列化器没问题，问题在于：① 前面不能加任何东西；② 必须先把 layer 名写进对象偏移 0。**

## 报文格式（按解析器读取顺序）

记号：`list<int>` = `int32 count` + `count × int32`；`list<str>` = `int32 count` + `count × String16`。

| # | 字段 | 类型 | 存入 AndEViewConfig | 备注 |
|---|---|---|---|---|
| 1 | exception code | int32 | — | **必须为 0** |
| 2 | binder status | int32 | — | 只打日志 |
| 3 | waveformSkipList | list<int> | +92 | **长度必须 ≥ 后面所有逐项列表的长度**（见安全事项） |
| 4 | ViewTypeList | list<str> | 丢弃 | 可写 count=0 |
| 5 | ViewFlagsList | list<str> | 丢弃 | 可写 count=0 |
| 6 | ViewIdList | list<int> | 丢弃 | 可写 count=0 |
| 7 | rectList | int32 count + 每项 `int32 非空标志, l, t, r, b` | +12 `Vector<Rect>` | 标志为 0 时该项只占 1 个 int；skip[i]≠0 时跳过 |
| 8 | waveformList | list<int> | +32 | 逐项受 skip[i] 控制 |
| 9 | updateModeList | list<int> | +132 | 同上 |
| 10 | waitForCompletionList | list<int> | +112 | 同上 |
| 11 | appName | String16 | 丢弃 | |
| 12 | **layer 名** | String16 | **+0 String8** | 必须与 SF 的 layer 名逐字一致 |
| 13 | refresh signal | int32 | +8 | |
| 14 | global update mode | int32 | +208 | |
| 15 | （未知字符串） | String16 | 丢弃 | constructParcel 写空串 |
| 16 | content insets | 4 × int32 | +192..+204 | |
| 17 | list A | list<int> | +52 | 逐项受 skip[i] 控制 |
| 18 | list B | list<int> | +72 | 同上 |
| 19 | list C | list<int> | +152 | 同上 |
| 20 | （单值） | int32 | +212 | |
| 21 | list D | list<int> | +172 | 同上 |

`updateViewConfigVectors(Rect, a1..a8)` 的参数到字段的映射（由偏移推出）：
`a1→+32 waveform`、`a2→+52 listA`、`a3→+72 listB`、`a4→+92 skip`、
`a5→+112 waitForCompletion`、`a6→+132 updateMode`、`a7→+152 listC`、`a8→+172 listD`。
每调用一次，8 个列表各追加一项、Rect 列表追加一项，长度天然一致。

## layer 名

只读 logcat 里 SF 用的名字（`Contacting AndEChoreographer to get info for the update from …`）：

```text
org.koreader.launcher.eanab.stage2/org.koreader.launcher.MainActivity_1_1
```

即 `包名/Activity 全类名` + 窗口序号后缀。后缀（`_1_1`）可能随 Activity 重建变化，
**不要写死**：实测时先从 logcat 取当前名字，正式实现需要找到稳定的获取方式。

## SF 怎么用这份配置

`SurfaceFlingerExtended::notifyBufferArrival` 在某个 layer 有新 buffer 时，用 layer 名在上述
map 里 `SortedVectorImpl::indexOf`；命中则用该配置走 `postFbParamsIfNeeded`。
`SortedVector::add` 对同名键是替换，所以**同一 layer 再发一次就覆盖旧配置**。
是否“用一次就清除”、layer 移除时是否清理（`removeLayer` 附近有访问），**尚未确认，需实测**。

## 安全事项（会让 SurfaceFlinger 崩溃）

解析器对 rect/waveform/updateMode/waitForCompletion/listA–D 的每一项都执行
`skip = skipVector.data[i]`，**没有边界检查**。skip 列表为空时 data 指针为 NULL，
只要后面任一列表非空就会空指针解引用，SurfaceFlinger 崩溃 → 整个界面重启。

- 手工拼报文时，skip 列表长度必须 ≥ 其余逐项列表的最大长度，值填 0；
- 用 `updateViewConfigVectors` 构造则天然满足。

## 建议的最小验证（一次只改一个变量）

1. 用 JNI：`AndEViewConfig cfg; cfg.updateViewConfigVectors(Rect(0,0,600,800), 7, 0,0, 0, 0, 0, 0,0);`
2. 用 libutils 的 `String8::setTo(const char*)` 把 `*(String8*)&cfg`（偏移 0）设为 logcat 里的当前 layer 名；
3. `constructParcel` 写入 native Parcel，把原始字节（`data()/dataSize()`）交回 Java，
   `Parcel.unmarshall` 后 **直接** `IBinder.transact(200, data, reply, 0)`，**不要** `writeInterfaceToken`；
4. 判据：日志不再出现上面两条报错；该 layer 下一次提交的 HAL 日志 `waveform:` 变为 7
   （为排除全局补丁的干扰，可选一个与全局默认不同的值，如 2/GC16），且提交仍只有一次；
5. 再发一次不同 waveform，确认替换生效；观察后续几次提交，确认配置是否持续有效。

## 实机验证结果（2026-10-31）

上述最小验证已经完成：JNI 通过厂商 `AndEViewConfig` 序列化器构造报文，动态写入
当前 APK 的 layer 名，并直接调用 `IBinder.transact(200, ...)`。固定请求
`waveform=2/updateMode=1` 后，目标 layer 的下一次 HAL 日志出现相同的区域、波形和
updateMode，且没有额外的同区域提交。由此确认 code 200 的 Parcel 路径可用；候选
控制器已经把 KOReader 刷新类别接入该路径，剩余工作是确认配置的持续时间、清理策略
以及各类页面的画质、延迟和残影。

## 附：逆向方法

- PLT 解析：读取 `.rel.plt` 的 GOT 偏移 → 符号名，再按 ARM PLT 三条指令
  （`add ip, pc, #…; add ip, ip, #…; ldr pc, [ip, #…]!`）算出每个 stub 对应的 GOT 槽位。
- 日志字符串：对每个 `lab126_log_write` 调用，追踪 r3 的 `ldr rX,[pc,#imm]` + `add rX, pc`，
  得到格式字符串地址，借此给每个 `readInt32/readString16` 命名。
