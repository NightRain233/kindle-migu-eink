import android.content.ComponentName;
import android.os.IBinder;
import android.os.Parcel;

import java.io.File;
import java.io.FileWriter;
import java.lang.reflect.Method;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 按应用指定墨水屏刷新方式（以 root 通过 app_process 运行，无需安装 APK）。
 *
 *   once   <layer 名> <waveform> [updateMode]   给一个 SurfaceFlinger layer 发一次配置
 *   daemon <配置文件>                            后台轮询前台 Activity，命中规则就为其窗口发配置
 *
 * 配置文件每行 "包名 waveform"，例如 "com.tencent.weread.eink 7"；# 开头为注释。
 * SurfaceFlinger 按 layer 名保存配置，但配置是**一次性**的（只作用于该 layer 的下一帧），
 * 所以目标应用在前台且亮屏时持续重发。layer 名会随窗口重建变化（如 _2_2 → _3_1），
 * 从 dumpsys SurfaceFlinger 读取真实名字。
 * 紧急开关：存在 /sdcard/koreader/eanab-wave.off 时 daemon 不发送任何配置。
 */
public final class EanabWaveHelper {
    private static final int FULL_W = 600;
    private static final int FULL_H = 800;
    private static final String OFF_FILE = "/sdcard/koreader/eanab-wave.off";
    private static final String LOG_FILE = "/sdcard/koreader/eanab-wave.log";

    static { System.load("/data/local/tmp/eanab-wave/libeanabwave.so"); }

    private static native boolean nativePopulate(Parcel parcel, String layer, int waveform,
                                                 int updateMode, int left, int top, int width, int height);

    private static IBinder surfaceFlinger() throws Exception {
        Class<?> sm = Class.forName("android.os.ServiceManager");
        Method get = sm.getMethod("getService", String.class);
        return (IBinder) get.invoke(null, "SurfaceFlinger");
    }

    static boolean send(String layer, int waveform, int updateMode) {
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            if (!nativePopulate(data, layer, waveform, updateMode, 0, 0, FULL_W, FULL_H)) return false;
            IBinder sf = surfaceFlinger();
            return sf != null && sf.transact(200, data, reply, 0);
        } catch (Throwable t) {
            log("send failed: " + t);
            return false;
        } finally {
            reply.recycle();
            data.recycle();
        }
    }

    private static Object activityManager() throws Exception {
        Class<?> amn = Class.forName("android.app.ActivityManagerNative");
        return amn.getMethod("getDefault").invoke(null);
    }

    @SuppressWarnings("unchecked")
    private static ComponentName topActivity(Object am) throws Exception {
        Method getTasks = am.getClass().getMethod("getTasks", int.class, int.class);
        List<Object> tasks = (List<Object>) getTasks.invoke(am, 1, 0);
        if (tasks == null || tasks.isEmpty()) return null;
        Object info = tasks.get(0);
        return (ComponentName) info.getClass().getField("topActivity").get(info);
    }

    private static Map<String, Integer> loadRules(String path) throws Exception {
        Map<String, Integer> rules = new HashMap<String, Integer>();
        java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(path));
        try {
            String line;
            while ((line = r.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                String[] p = line.split("\\s+");
                if (p.length >= 2) rules.put(p[0], Integer.parseInt(p[1]));
            }
        } finally {
            r.close();
        }
        return rules;
    }

    static void log(String msg) {
        try {
            File f = new File(LOG_FILE);
            if (f.length() > 64 * 1024) f.delete();
            FileWriter w = new FileWriter(f, true);
            w.write(new SimpleDateFormat("MM-dd HH:mm:ss").format(new Date()) + " " + msg + "\n");
            w.close();
        } catch (Throwable ignored) {
        }
    }

    private static boolean screenOn() {
        try {
            Class<?> sm = Class.forName("android.os.ServiceManager");
            IBinder b = (IBinder) sm.getMethod("getService", String.class).invoke(null, "power");
            Object pm = Class.forName("android.os.IPowerManager$Stub")
                    .getMethod("asInterface", IBinder.class).invoke(null, b);
            return (Boolean) pm.getClass().getMethod("isInteractive").invoke(pm);
        } catch (Throwable t) {
            return true;
        }
    }

    /** 从 dumpsys SurfaceFlinger 取出某个包当前可见的 layer 名（"+ Layer 0x... (名字)"）。 */
    private static java.util.List<String> layersOf(String pkg) {
        java.util.List<String> out = new java.util.ArrayList<String>();
        try {
            Process p = Runtime.getRuntime().exec(new String[]{"dumpsys", "SurfaceFlinger"});
            java.io.BufferedReader r = new java.io.BufferedReader(new java.io.InputStreamReader(p.getInputStream()));
            String line;
            String prefix = pkg + "/";
            while ((line = r.readLine()) != null) {
                if (!line.startsWith("+ Layer ")) continue;
                int a = line.indexOf('('), b = line.lastIndexOf(')');
                if (a < 0 || b <= a) continue;
                String name = line.substring(a + 1, b);
                if (name.startsWith(prefix)) out.add(name);
            }
            r.close();
            p.waitFor();
        } catch (Throwable t) {
            log("dumpsys failed: " + t);
        }
        return out;
    }

    /**
     * SurfaceFlinger 的自定义配置是一次性的（只作用于该 layer 的下一帧），外部无法预知目标应用何时出帧，
     * 所以目标应用在前台且亮屏时每 BURST_MS 重发一次；其余时间每秒检查一次前台。
     */
    private static final long BURST_MS = 40;
    private static final long IDLE_MS = 1000;
    private static final long RESCAN_MS = 20000;
    private static final long[] RESCAN_AFTER_CHANGE = {500, 1500, 3000};

    private static void daemon(String rulesPath) throws Exception {
        Map<String, Integer> rules = loadRules(rulesPath);
        log("daemon start rules=" + rules + " pid=" + android.os.Process.myPid());
        try {
            FileWriter pw = new FileWriter("/data/local/tmp/eanab-wave/pid");
            pw.write(String.valueOf(android.os.Process.myPid()));
            pw.close();
        } catch (Throwable ignored) {
        }
        Object am = activityManager();
        String lastTop = null;
        long topSince = 0, lastScan = 0, lastCheck = 0;
        int rescanIdx = 0;
        boolean active = false;
        Integer wf = null;
        java.util.List<String> layers = new java.util.ArrayList<String>();
        while (true) {
            long now = System.currentTimeMillis();
            try {
                if (now - lastCheck >= IDLE_MS || !active) {
                    lastCheck = now;
                    ComponentName top = topActivity(am);
                    String topKey = top == null ? null : top.flattenToString();
                    wf = top == null ? null : rules.get(top.getPackageName());
                    boolean on = screenOn();
                    boolean wasActive = active;
                    active = wf != null && on && !new File(OFF_FILE).exists();
                    if (topKey != null && !topKey.equals(lastTop) || (active && !wasActive)) {
                        lastTop = topKey;
                        topSince = now;
                        rescanIdx = 0;
                        layers.clear();
                    }
                    if (active) {
                        boolean due = rescanIdx < RESCAN_AFTER_CHANGE.length
                                ? now - topSince >= RESCAN_AFTER_CHANGE[rescanIdx]
                                : now - lastScan >= RESCAN_MS;
                        if (due) {
                            java.util.List<String> found = layersOf(top.getPackageName());
                            if (!found.equals(layers)) log("layers " + found + " waveform=" + wf);
                            layers = found;
                            lastScan = now;
                            if (rescanIdx < RESCAN_AFTER_CHANGE.length) rescanIdx++;
                        }
                    }
                }
                if (active) {
                    for (String layer : layers) send(layer, wf, 0);
                }
            } catch (Throwable t) {
                log("loop error: " + t);
                am = activityManager();
                active = false;
            }
            Thread.sleep(active ? BURST_MS : IDLE_MS);
        }
    }

    public static void main(String[] args) throws Exception {
        if (args.length >= 3 && "once".equals(args[0])) {
            int um = args.length >= 4 ? Integer.parseInt(args[3]) : 0;
            boolean ok = send(args[1], Integer.parseInt(args[2]), um);
            System.out.println("send " + args[1] + " wf=" + args[2] + " um=" + um + " ok=" + ok);
        } else if (args.length >= 5 && "burst".equals(args[0])) {
            // 实验：每 interval_ms 毫秒重发一次，持续 duration_s 秒（配置是一次性的）
            int wf = Integer.parseInt(args[2]);
            long interval = Long.parseLong(args[3]);
            long end = System.currentTimeMillis() + Long.parseLong(args[4]) * 1000L;
            int n = 0;
            while (System.currentTimeMillis() < end) {
                send(args[1], wf, 0);
                n++;
                Thread.sleep(interval);
            }
            System.out.println("burst sent " + n);
        } else if (args.length >= 2 && "daemon".equals(args[0])) {
            daemon(args[1]);
        } else {
            System.out.println("usage: once <layer> <waveform> [updateMode] | daemon <rules>");
        }
    }
}
