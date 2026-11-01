# APK 级补丁素材

`scripts/build-eanab-direct-apk.sh` 用到的文件：

| 文件 | 作用 |
|---|---|
| `EanabEPDController.smali` | 控制器：分类五种刷新、记日志，并经 `AndEParcel.submit` 下发 parcel（mode=2 时 updateMode=1，其余 0；非标准 mode 原样透传） |
| `AndEParcel.smali` | 取 SurfaceFlinger Binder，`transact(200, …)` |
| `native/eanabparcel.cpp` → `lib/armeabi-v7a/libeanabparcel.so` | JNI：调用设备自带 `libandechoreographer.so` 的 `AndEViewConfig` 序列化器；layer 名为 `<当前包名>/org.koreader.launcher.MainActivity_1_1` |
| `native/build.sh` | NDK 17 编译 JNI |

构建命令与现状见上一级 [`../README.md`](../README.md)。默认输出 debug 包 `org.koreader.launcher.eanab.debug`；
设置 `PACKAGE_NAME`、`APP_LABEL` 生成候选包。签名默认用本地 debug keystore（`KEYSTORE`、`KEY_ALIAS` 可覆盖）。
