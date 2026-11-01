.class public final Lorg/koreader/launcher/device/epd/AndEParcel;
.super Ljava/lang/Object;
.source "AndEParcel.java"

.method static constructor <clinit>()V
    .locals 1
    const-string v0, "eanabparcel"
    invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V
    return-void
.end method

.method private constructor <init>()V
    .locals 0
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V
    return-void
.end method

.method public static native nativePopulate(Landroid/os/Parcel;IIIIII)Z
.end method

.method public static submit(IIIIII)Z
    .locals 8
    .param p0, "waveform"    # I
    .param p1, "updateMode"   # I
    .param p2, "left"         # I
    .param p3, "top"          # I
    .param p4, "width"        # I
    .param p5, "height"       # I

    invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
    move-result-object v0
    move-object v7, v0
    move-object v0, v7
    move v1, p0
    move v2, p1
    move v3, p2
    move v4, p3
    move v5, p4
    move v6, p5
    invoke-static/range {v0 .. v6}, Lorg/koreader/launcher/device/epd/AndEParcel;->nativePopulate(Landroid/os/Parcel;IIIIII)Z
    move-result v1
    if-eqz v1, :cleanup

    const-string v2, "SurfaceFlinger"
    invoke-static {v2}, Landroid/os/ServiceManager;->getService(Ljava/lang/String;)Landroid/os/IBinder;
    move-result-object v2
    if-eqz v2, :cleanup

    invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
    move-result-object v3
    const/16 v4, 0xc8
    const/4 v5, 0x0
    :try_start
    invoke-interface {v2, v4, v0, v3, v5}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
    move-result v6
    invoke-virtual {v3}, Landroid/os/Parcel;->recycle()V
    invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
    return v6
    :try_end
    .catch Ljava/lang/Throwable; {:try_start .. :try_end} :catch

    :catch
    move-exception v6
    invoke-virtual {v3}, Landroid/os/Parcel;->recycle()V
    invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
    const-string v7, "EanabParcel"
    invoke-virtual {v6}, Ljava/lang/Throwable;->toString()Ljava/lang/String;
    move-result-object v6
    invoke-static {v7, v6}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;)I
    const/4 v6, 0x0
    return v6

    :cleanup
    invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
    const/4 v2, 0x0
    return v2
.end method
