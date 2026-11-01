// 为任意窗口（按 SurfaceFlinger layer 名）生成 AndE 刷新配置报文。
// 由 eanab-launcher/direct-apk/native/eanabparcel.cpp 改写：layer 名改为参数，其余报文构造完全相同
// （设备自带 libandechoreographer.so 的 AndEViewConfig 序列化器，格式见
// docs/ande-parcel-format-2026-10-31.md）。
#include <jni.h>
#include <android/log.h>
#include <dlfcn.h>
#include <stdint.h>
#include <string.h>

namespace {
struct Rect { int left, top, right, bottom; };
// Android 5.1 VectorImpl：vtable、storage、count、flags、itemSize，共 20 字节
struct VectorInt {
    void *vtable;
    int *data;
    uint32_t count;
    uint32_t flags;
    uint32_t itemSize;
};
using VectorCtor = void (*)(void *, unsigned int, unsigned int);
using VectorDtor = void (*)(void *);
using ConfigCtor = void (*)(void *);
using ConfigClear = void (*)(void *);
using ConfigUpdate = void (*)(void *, Rect, int, int, int, int, int, int, int, int);
using ConfigConstruct = void (*)(void *, void *, const VectorInt *, const VectorInt *, const VectorInt *);
using String8SetTo = void (*)(void *, const char *);

struct Api {
    ConfigCtor ctor;
    ConfigClear clear;
    ConfigUpdate update;
    ConfigConstruct construct;
    VectorCtor vectorCtor;
    VectorDtor vectorDtor;
    String8SetTo string8SetTo;
    bool ready;
};

Api &api() {
    static Api a{};
    if (a.ready) return a;
    void *h = dlopen("/system/lib/libandechoreographer.so", RTLD_NOW);
    void *u = dlopen("/system/lib/libutils.so", RTLD_NOW);
    if (!h || !u) {
        __android_log_print(ANDROID_LOG_ERROR, "EanabWave", "dlopen failed: %s", dlerror());
        return a;
    }
    a.ctor = reinterpret_cast<ConfigCtor>(dlsym(h, "_ZN7android14AndEViewConfigC1Ev"));
    a.clear = reinterpret_cast<ConfigClear>(dlsym(h, "_ZN7android14AndEViewConfig11clearConfigEv"));
    a.update = reinterpret_cast<ConfigUpdate>(dlsym(h, "_ZN7android14AndEViewConfig23updateViewConfigVectorsENS_4RectEiiiiiiii"));
    a.construct = reinterpret_cast<ConfigConstruct>(dlsym(h, "_ZN7android14AndEViewConfig15constructParcelERNS_6ParcelENS_6VectorIiEES4_S4_"));
    a.vectorCtor = reinterpret_cast<VectorCtor>(dlsym(u, "_ZN7android10VectorImplC2Ejj"));
    a.vectorDtor = reinterpret_cast<VectorDtor>(dlsym(u, "_ZN7android10VectorImplD2Ev"));
    a.string8SetTo = reinterpret_cast<String8SetTo>(dlsym(u, "_ZN7android7String85setToEPKc"));
    a.ready = a.ctor && a.clear && a.update && a.construct && a.vectorCtor && a.string8SetTo;
    return a;
}
}

extern "C" JNIEXPORT jboolean JNICALL
Java_EanabWaveHelper_nativePopulate(JNIEnv *env, jclass, jobject parcel, jstring layer,
                                    jint waveform, jint updateMode,
                                    jint left, jint top, jint width, jint height) {
    Api &a = api();
    if (!a.ready || !parcel || !layer) return JNI_FALSE;
    jclass parcelClass = env->GetObjectClass(parcel);
    jfieldID nativePtr = env->GetFieldID(parcelClass, "mNativePtr", "J");
    if (!nativePtr) { env->ExceptionClear(); return JNI_FALSE; }
    void *parcelNative = reinterpret_cast<void *>(static_cast<uintptr_t>(env->GetLongField(parcel, nativePtr)));
    if (!parcelNative) return JNI_FALSE;

    // 配置对象只构造一次，之后每次 clearConfig 复用。原 eanab-launcher 代码每次 memset+构造、从不析构，
    // 会泄漏 8 个列表的堆内存；助手每秒发送数十次，必须复用。
    static uint8_t storage[224] __attribute__((aligned(8)));
    static bool constructed = false;
    if (!constructed) {
        memset(storage, 0, sizeof(storage));
        a.ctor(storage);
        constructed = true;
    } else {
        a.clear(storage);
    }
    const char *name = env->GetStringUTFChars(layer, nullptr);
    if (!name) return JNI_FALSE;
    a.string8SetTo(storage, name);  // layer 名在 AndEViewConfig 偏移 0 的 String8
    env->ReleaseStringUTFChars(layer, name);

    Rect rect{left, top, left + width, top + height};
    // 第 1 个整数 → waveform 列表，第 6 个 → updateMode 列表；
    // updateViewConfigVectors 会让包括 skip 列表在内的 8 个列表等长，避免 SF 越界读
    a.update(storage, rect, waveform, 0, 0, 0, 0, updateMode, 0, 0);
    VectorInt v1{}, v2{}, v3{};
    a.vectorCtor(&v1, sizeof(int), 7);
    a.vectorCtor(&v2, sizeof(int), 7);
    a.vectorCtor(&v3, sizeof(int), 7);
    a.construct(storage, parcelNative, &v1, &v2, &v3);
    if (a.vectorDtor) { a.vectorDtor(&v3); a.vectorDtor(&v2); a.vectorDtor(&v1); }
    return JNI_TRUE;
}
