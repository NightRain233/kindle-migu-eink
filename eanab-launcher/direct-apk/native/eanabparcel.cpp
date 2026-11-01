#include <jni.h>
#include <android/log.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

namespace {
struct Rect { int left, top, right, bottom; };
// Android 5.1 VectorImpl layout: vtable, storage pointer, size, flags,
// and item size. It is a 20-byte object on this firmware. A 12-byte
// approximation crashes when the vendor serializer copies a vector.
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
    void *handle;
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
    a.handle = dlopen("/system/lib/libandechoreographer.so", RTLD_NOW);
    if (!a.handle) {
        __android_log_print(ANDROID_LOG_ERROR, "EanabParcel", "dlopen failed: %s", dlerror());
        return a;
    }
#define SYM(name, type) reinterpret_cast<type>(dlsym(a.handle, name))
    a.ctor = SYM("_ZN7android14AndEViewConfigC1Ev", ConfigCtor);
    a.clear = SYM("_ZN7android14AndEViewConfig10clearConfigEv", ConfigClear);
    a.update = SYM("_ZN7android14AndEViewConfig23updateViewConfigVectorsENS_4RectEiiiiiiii", ConfigUpdate);
    a.construct = SYM("_ZN7android14AndEViewConfig15constructParcelERNS_6ParcelENS_6VectorIiEES4_S4_", ConfigConstruct);
    a.vectorCtor = reinterpret_cast<VectorCtor>(dlsym(RTLD_DEFAULT, "_ZN7android10VectorImplC2Ejj"));
    a.vectorDtor = reinterpret_cast<VectorDtor>(dlsym(RTLD_DEFAULT, "_ZN7android10VectorImplD2Ev"));
    a.string8SetTo = reinterpret_cast<String8SetTo>(dlsym(RTLD_DEFAULT, "_ZN7android7String85setToEPKc"));
    if (!a.vectorCtor || !a.string8SetTo) {
        void *utils = dlopen("/system/lib/libutils.so", RTLD_NOW);
        if (utils) {
            if (!a.vectorCtor) a.vectorCtor = reinterpret_cast<VectorCtor>(dlsym(utils, "_ZN7android10VectorImplC2Ejj"));
            if (!a.vectorDtor) a.vectorDtor = reinterpret_cast<VectorDtor>(dlsym(utils, "_ZN7android10VectorImplD2Ev"));
            if (!a.string8SetTo) a.string8SetTo = reinterpret_cast<String8SetTo>(dlsym(utils, "_ZN7android7String85setToEPKc"));
        }
    }
#undef SYM
    a.ready = a.ctor && a.update && a.construct && a.vectorCtor && a.string8SetTo;
    __android_log_print(ANDROID_LOG_INFO, "EanabParcel", "api ready=%d ctor=%p clear=%p update=%p construct=%p", a.ready, a.ctor, a.clear, a.update, a.construct);
    return a;
}

void *config(JNIEnv *env) {
    static uint8_t storage[224] __attribute__((aligned(8)));
    Api &a = api();
    if (!a.ready) return nullptr;
    // Reinitialize the fixed-size config for every call. The controller only
    // emits a small number of entries per frame; this keeps the ABI simple
    // while the factory's VectorImpl owns its own storage.
    memset(storage, 0, sizeof(storage));
    a.ctor(storage);
    // AndEViewConfig stores the target layer name in its String8 at offset 0.
    // constructParcel writes that name into the payload; without it the
    // framework parses the values but reports "layer name undefined". Resolve
    // the package at runtime so the same probe works for debug/candidate APKs.
    const char *fallback =
        "org.koreader.launcher.eanab.stage2/org.koreader.launcher.MainActivity_1_1";
    char layerName[256];
    snprintf(layerName, sizeof(layerName), "%s", fallback);
    jclass threadClass = env->FindClass("android/app/ActivityThread");
    if (threadClass) {
        jmethodID packageMethod = env->GetStaticMethodID(
            threadClass, "currentPackageName", "()Ljava/lang/String;");
        if (packageMethod) {
            jstring packageName = static_cast<jstring>(
                env->CallStaticObjectMethod(threadClass, packageMethod));
            if (packageName) {
                const char *packageChars = env->GetStringUTFChars(packageName, nullptr);
                if (packageChars && packageChars[0] != '\0') {
                    snprintf(layerName, sizeof(layerName),
                             "%s/org.koreader.launcher.MainActivity_1_1", packageChars);
                }
                if (packageChars) env->ReleaseStringUTFChars(packageName, packageChars);
                env->DeleteLocalRef(packageName);
            }
        }
        env->DeleteLocalRef(threadClass);
    }
    if (env->ExceptionCheck()) env->ExceptionClear();
    a.string8SetTo(storage, layerName);
    return storage;
}
}

extern "C" JNIEXPORT jboolean JNICALL
Java_org_koreader_launcher_device_epd_AndEParcel_nativePopulate(
        JNIEnv *env, jclass, jobject parcel, jint waveform, jint updateMode,
        jint left, jint top, jint width, jint height) {
    Api &a = api();
    void *cfg = config(env);
    if (!cfg || !parcel) return JNI_FALSE;
    jclass parcelClass = env->GetObjectClass(parcel);
    jfieldID nativePtr = env->GetFieldID(parcelClass, "mNativePtr", "J");
    if (!nativePtr) {
        env->ExceptionClear();
        nativePtr = env->GetFieldID(parcelClass, "mNativePtr", "I");
    }
    if (!nativePtr) {
        __android_log_print(ANDROID_LOG_ERROR, "EanabParcel", "Parcel native pointer field unavailable");
        return JNI_FALSE;
    }
    void *parcelNative = reinterpret_cast<void *>(static_cast<uintptr_t>(env->GetLongField(parcel, nativePtr)));
    if (!parcelNative) return JNI_FALSE;

    Rect rect{left, top, left + width, top + height};
    // The native helper owns the exact Vector ABI. The auxiliary vectors are
    // kept deliberately conservative: a single generic view and no skip list.
    __android_log_print(ANDROID_LOG_DEBUG, "EanabParcel", "before update cfg=%p parcel=%p", cfg, parcelNative);
    // updateViewConfigVectors stores its first integer argument in the
    // waveform-list vector (the field consumed by SurfaceFlinger after the
    // rectangle list). The earlier probe put the waveform in the skip-list
    // slot, so the parser treated 257 as a list length.
    // The vendor's update-mode list is the sixth integer slot, not the
    // second one. The second slot is a separate per-view list and is ignored
    // by the EPDC parameter selection.
    a.update(cfg, rect, waveform, 0, 0, 0, 0, updateMode, 0, 0);
    __android_log_print(ANDROID_LOG_DEBUG, "EanabParcel", "after update cfg=%p", cfg);
    VectorInt v1{}, v2{}, v3{};
    a.vectorCtor(&v1, sizeof(int), 7);
    a.vectorCtor(&v2, sizeof(int), 7);
    a.vectorCtor(&v3, sizeof(int), 7);
    // The serializer accepts empty auxiliary vectors for a single view.
    a.construct(cfg, parcelNative, &v1, &v2, &v3);
    if (a.vectorDtor) {
        a.vectorDtor(&v3);
        a.vectorDtor(&v2);
        a.vectorDtor(&v1);
    }
    __android_log_print(ANDROID_LOG_DEBUG, "EanabParcel", "after construct");
    __android_log_print(ANDROID_LOG_DEBUG, "EanabParcel", "serialized wf=%d um=%d rect=%d,%d %dx%d", waveform, updateMode, left, top, width, height);
    return JNI_TRUE;
}
