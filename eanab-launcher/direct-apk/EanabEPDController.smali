.class public final Lorg/koreader/launcher/device/epd/EanabEPDController;
.super Ljava/lang/Object;
.source "EanabEPDController.java"

# interfaces
.implements Lorg/koreader/launcher/device/EPDInterface;


# static fields
.field private static final FULL_HEIGHT:I = 0x320

.field private static final FULL_WIDTH:I = 0x258

.field private static final TAG:Ljava/lang/String; = "EanabEPD"

.field public static final WAVEFORM_AUTO:I = 0x101

.field private static final WAVEFORM_DELAY:I = 0x0

.field public static final WAVEFORM_DU:I = 0x1

.field public static final WAVEFORM_DU4:I = 0x7

.field public static final WAVEFORM_GC16:I = 0x2


# instance fields
.field private final counts:[I


# direct methods
.method public constructor <init>()V
    .locals 1

    .line 9
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    .line 18
    const/4 v0, 0x6

    new-array v0, v0, [I

    iput-object v0, p0, Lorg/koreader/launcher/device/epd/EanabEPDController;->counts:[I

    return-void
.end method

.method private className(I)Ljava/lang/String;
    .locals 0

    .line 59
    packed-switch p1, :pswitch_data_0

    .line 65
    const-string p1, "UNKNOWN"

    return-object p1

    .line 64
    :pswitch_0
    const-string p1, "FAST"

    return-object p1

    .line 63
    :pswitch_1
    const-string p1, "PARTIAL_UI"

    return-object p1

    .line 62
    :pswitch_2
    const-string p1, "FULL_UI"

    return-object p1

    .line 61
    :pswitch_3
    const-string p1, "PARTIAL"

    return-object p1

    .line 60
    :pswitch_4
    const-string p1, "FULL"

    return-object p1

    nop

    :pswitch_data_0
    .packed-switch 0x0
        :pswitch_4
        :pswitch_3
        :pswitch_2
        :pswitch_1
        :pswitch_0
    .end packed-switch
.end method

.method private classify(IIIIILjava/lang/String;)I
    .locals 4

    .line 42
    const-string v0, "EPD_FULL"

    invoke-virtual {v0, p6}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v0

    const/4 v1, 0x0

    if-eqz v0, :cond_0

    return v1

    .line 43
    :cond_0
    const-string v0, "EPD_PART"

    invoke-virtual {v0, p6}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v0

    const/4 v2, 0x1

    if-eqz v0, :cond_1

    return v2

    .line 44
    :cond_1
    const-string v0, "EPD_A2"

    invoke-virtual {v0, p6}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v0

    const/4 v3, 0x4

    if-eqz v0, :cond_2

    return v3

    .line 45
    :cond_2
    const-string v0, "EPD_AUTO"

    invoke-virtual {v0, p6}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result p6

    const/4 v0, 0x2

    if-eqz p6, :cond_3

    return v0

    .line 46
    :cond_3
    if-ne p1, v0, :cond_4

    return v1

    .line 47
    :cond_4
    const/4 p6, 0x7

    if-ne p1, p6, :cond_5

    return v2

    .line 48
    :cond_5
    if-ne p1, v2, :cond_6

    return v3

    .line 49
    :cond_6
    const/16 p6, 0x101

    if-ne p1, p6, :cond_8

    invoke-direct {p0, p2, p3, p4, p5}, Lorg/koreader/launcher/device/epd/EanabEPDController;->fullScreen(IIII)Z

    move-result p1

    if-eqz p1, :cond_7

    goto :goto_0

    :cond_7
    const/4 v0, 0x3

    :goto_0
    return v0

    .line 50
    :cond_8
    const/4 p1, 0x5

    return p1
.end method

.method private fullScreen(IIII)Z
    .locals 0

    .line 54
    if-nez p1, :cond_0

    if-nez p2, :cond_0

    if-nez p3, :cond_0

    if-eqz p4, :cond_1

    :cond_0
    if-nez p1, :cond_2

    if-nez p2, :cond_2

    const/16 p1, 0x258

    if-lt p3, p1, :cond_2

    const/16 p1, 0x320

    if-lt p4, p1, :cond_2

    :cond_1
    const/4 p1, 0x1

    goto :goto_0

    :cond_2
    const/4 p1, 0x0

    :goto_0
    return p1
.end method


# virtual methods
.method public getMode()Ljava/lang/String;
    .locals 1

    .line 21
    const-string v0, "all"

    return-object v0
.end method

.method public getPlatform()Ljava/lang/String;
    .locals 1

    .line 20
    const-string v0, "eanab"

    return-object v0
.end method

.method public getWaveformDelay()I
    .locals 1

    .line 27
    const/4 v0, 0x0

    return v0
.end method

.method public getWaveformDelayFast()I
    .locals 1

    .line 29
    const/4 v0, 0x0

    return v0
.end method

.method public getWaveformDelayUi()I
    .locals 1

    .line 28
    const/4 v0, 0x0

    return v0
.end method

.method public getWaveformFast()I
    .locals 1

    .line 26
    const/4 v0, 0x1

    return v0
.end method

.method public getWaveformFull()I
    .locals 1

    .line 22
    const/4 v0, 0x2

    return v0
.end method

.method public getWaveformFullUi()I
    .locals 1

    .line 24
    const/16 v0, 0x101

    return v0
.end method

.method public getWaveformPartial()I
    .locals 1

    .line 23
    const/4 v0, 0x7

    return v0
.end method

.method public getWaveformPartialUi()I
    .locals 1

    .line 25
    const/16 v0, 0x101

    return v0
.end method

.method public needsView()Z
    .locals 1

    .line 30
    const/4 v0, 0x0

    return v0
.end method

.method public pause()V
    .locals 2

    .line 70
    const-string v0, "EanabEPD"

    const-string v1, "pause (observe-only)"

    invoke-static {v0, v1}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I

    return-void
.end method

.method public resume()V
    .locals 2

    .line 69
    const-string v0, "EanabEPD"

    const-string v1, "resume (observe-only)"

    invoke-static {v0, v1}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I

    return-void
.end method

.method public declared-synchronized setEpdMode(Landroid/view/View;IJIIIILjava/lang/String;)V
    .locals 9

    move-object v8, p0

    monitor-enter p0

    .line 34
    move-object v1, p0

    move v2, p2

    move v3, p5

    move v4, p6

    move/from16 v5, p7

    move/from16 v6, p8

    move-object/from16 v7, p9

    :try_start_0
    invoke-direct/range {v1 .. v7}, Lorg/koreader/launcher/device/epd/EanabEPDController;->classify(IIIIILjava/lang/String;)I

    move-result v0

    .line 35
    iget-object v1, v8, Lorg/koreader/launcher/device/epd/EanabEPDController;->counts:[I

    aget v2, v1, v0

    const/4 v3, 0x1

    add-int/2addr v2, v3

    aput v2, v1, v0

    .line 36
    const-string v1, "EanabEPD"

    sget-object v4, Ljava/util/Locale;->US:Ljava/util/Locale;

    const-string v5, "refresh class=%s mode=%d delay=%d rect=[%d,%d %dx%d] count=%d (observe-only)"

    const/16 v6, 0x8

    new-array v6, v6, [Ljava/lang/Object;

    .line 38
    invoke-direct {p0, v0}, Lorg/koreader/launcher/device/epd/EanabEPDController;->className(I)Ljava/lang/String;

    move-result-object v0

    const/4 v7, 0x0

    aput-object v0, v6, v7

    invoke-static {p2}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v0

    aput-object v0, v6, v3

    invoke-static {p3, p4}, Ljava/lang/Long;->valueOf(J)Ljava/lang/Long;

    move-result-object v0

    const/4 v3, 0x2

    aput-object v0, v6, v3

    invoke-static {p5}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v0

    const/4 v3, 0x3

    aput-object v0, v6, v3

    invoke-static {p6}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v0

    const/4 v3, 0x4

    aput-object v0, v6, v3

    invoke-static/range {p7 .. p7}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v0

    const/4 v3, 0x5

    aput-object v0, v6, v3

    invoke-static/range {p8 .. p8}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v0

    const/4 v3, 0x6

    aput-object v0, v6, v3

    invoke-static {v2}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v0

    const/4 v2, 0x7

    aput-object v0, v6, v2

    .line 36
    invoke-static {v4, v5, v6}, Ljava/lang/String;->format(Ljava/util/Locale;Ljava/lang/String;[Ljava/lang/Object;)Ljava/lang/String;

    move-result-object v0

    invoke-static {v1, v0}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    # Stage 2: pass the same intent to the system's AndE layer. The native
    # probe uses the vendor serializer and Binder code 200; failures are
    # contained so the observe-only logging path remains usable.
    :try_start_parcel
    const/4 v3, 0x0
    # GC16 full cleanup uses the system's full-update mode; all other
    # categories leave updateMode at the normal partial value 0.
    const/4 v6, 0x2
    if-ne p2, v6, :parcel_update_mode_ready
    const/4 v3, 0x1
    :parcel_update_mode_ready
    move v0, p2
    move v1, v3
    move v2, p5
    move v3, p6
    move/from16 v4, p7
    move/from16 v5, p8
    invoke-static/range {v0 .. v5}, Lorg/koreader/launcher/device/epd/AndEParcel;->submit(IIIIII)Z
    move-result v0
    :try_end_parcel
    .catch Ljava/lang/Throwable; {:try_start_parcel .. :try_end_parcel} :catch_parcel
    goto :parcel_done

    :catch_parcel
    move-exception v0
    const-string v1, "EanabEPD"
    invoke-virtual {v0}, Ljava/lang/Throwable;->toString()Ljava/lang/String;
    move-result-object v0
    invoke-static {v1, v0}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;)I

    :parcel_done

    :try_end_0
    .catchall {:try_start_0 .. :try_end_0} :catchall_0

    .line 39
    monitor-exit p0

    return-void

    .line 33
    :catchall_0
    move-exception v0

    monitor-exit p0

    throw v0
.end method
