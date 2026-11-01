#!/usr/bin/env python3
"""du-waveform — 把 SurfaceFlinger 的默认刷新波形从 AUTO(257) 改成指定波形。

原理
----
libsurfaceflinger.so 里只有一处写入 257（AUTO），位于默认视图配置的构造路径：
    vaddr 0x2e8dc:  movw r0, #257     (40 f2 01 10)
改成 `movw r0, #N`（N 为 MXCFB 波形号）即可。

各档位实测（见 docs/panel-timing-2026-10-30.md）
    N=1  DU     177 ms   ← 默认，最快且仍可读
    N=7  DU4    272 ms   ← 折中
    N=4  内部模式6 118 ms  ← 最快，画质风险最大
    原厂 257(AUTO)：翻页走 GC16 类，449–450 ms

副作用：快档"只擦变化处"，整页换字会累积残影；系统的周期全刷（update_mode=FULL）
仍会强制回落 GC16，所以残影会被定期清掉。

用法
    python3 scripts/du-waveform.py status
    python3 scripts/du-waveform.py on  [--waveform 1|4|7] [--reboot]
    python3 scripts/du-waveform.py off [--reboot]

本文件不含任何厂商二进制；补丁在设备原文件上就地生成。
"""
import argparse
import hashlib
import os
import subprocess
import sys

SERIAL = os.environ.get("SERIAL") or os.environ.get("KINDLE_SERIAL", "")
TARGET = "/system/lib/libsurfaceflinger.so"
BACKUP = "/sdcard/libsurfaceflinger.so.orig"
PATCH_OFFSET = 0x2E8DC
ORIG_BYTES = bytes.fromhex("40f20110")      # movw r0, #257
ORIG_SHA = "f1a2e731081343596d40c2104a2d69d2e13198832b53b29a004a6491baa5b077"
KNOWN = {1: "DU 177ms", 4: "MODE6 118ms", 7: "DU4 272ms"}


def sh(cmd):
    r = subprocess.run(["adb", "-s", SERIAL, "shell", "su", "-c", cmd],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"命令失败: {cmd}\n{r.stdout}{r.stderr}")
    return r


def sha_remote(path):
    out = sh(f"busybox sha256sum {path}").stdout.strip()
    return out.split()[0] if out else ""


def pull(remote, local):
    subprocess.run(["adb", "-s", SERIAL, "pull", remote, local],
                   check=True, capture_output=True)


def fetch_current():
    local = "/tmp/lsf.current"
    pull(TARGET, local)
    return bytearray(open(local, "rb").read())


def patched(data, n):
    d = bytearray(data)
    assert bytes(d[PATCH_OFFSET:PATCH_OFFSET + 4]) == ORIG_BYTES, "补丁点不是预期指令"
    d[PATCH_OFFSET:PATCH_OFFSET + 4] = bytes([0x40, 0xF2, n & 0xFF, 0x00])
    return d


def sha_of(data):
    return hashlib.sha256(bytes(data)).hexdigest()


def replace_with(data):
    """原子替换：写临时文件再 mv，避免截断正被 mmap 的旧 inode。"""
    sh("busybox mount -o rw,remount /system")
    local = "/tmp/lsf.new"
    open(local, "wb").write(bytes(data))
    subprocess.run(["adb", "-s", SERIAL, "push", local, "/data/local/tmp/.lsf.new"],
                   check=True, capture_output=True)
    sh("cp /data/local/tmp/.lsf.new /system/lib/.lsf.new")
    sh("busybox chmod 644 /system/lib/.lsf.new")
    sh("busybox mv /system/lib/.lsf.new " + TARGET)
    sh("busybox sync")
    return sha_remote(TARGET)


def identify(cur):
    """返回 (描述, 原厂数据或 None)。"""
    if sha_of(cur) == ORIG_SHA:
        return "原厂（AUTO/257，翻页约 450 ms）", cur
    base = ORIG_DATA if ORIG_DATA is not None else None
    if base is not None:
        for n, desc in KNOWN.items():
            if sha_of(patched(base, n)) == sha_of(cur):
                return f"已改为 waveform={n}（{desc}）", base
    return f"未知内容（sha256 {sha_of(cur)}）", None


def reboot():
    print("重启中…")
    subprocess.run(["adb", "-s", SERIAL, "reboot"], capture_output=True)
    subprocess.run(["adb", "-s", SERIAL, "wait-for-device"], capture_output=True)
    print("设备已重新连接；改动已生效")


def ensure_backup():
    """保证设备上有可用的原厂备份；必要时用已知原厂镜像重建。"""
    if sha_remote(BACKUP) == ORIG_SHA:
        return
    print("备份缺失或损坏：用已知原厂镜像重建")
    open("/tmp/lsf.orig.rebuild", "wb").write(bytes(ORIG_DATA))
    subprocess.run(["adb", "-s", SERIAL, "push", "/tmp/lsf.orig.rebuild", "/data/local/tmp/.lsf.orig"],
                   check=True, capture_output=True)
    sh(f"cp /data/local/tmp/.lsf.orig {BACKUP}")
    if sha_remote(BACKUP) != ORIG_SHA:
        sys.exit("备份重建校验失败，中止")


ORIG_DATA = None


def main():
    global ORIG_DATA
    ap = argparse.ArgumentParser()
    ap.add_argument("action", choices=["status", "on", "off"])
    ap.add_argument("--waveform", type=int, default=1, choices=sorted(KNOWN))
    ap.add_argument("--reboot", action="store_true")
    a = ap.parse_args()

    # 取一份原厂数据：优先用设备备份，其次用外网/仓库归档
    if sha_remote(BACKUP) == ORIG_SHA:
        pull(BACKUP, "/tmp/lsf.orig")
        ORIG_DATA = bytearray(open("/tmp/lsf.orig", "rb").read())
    else:
        here = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "..", "libs", "libsurfaceflinger.so")
        if os.path.exists(here):
            d = bytearray(open(here, "rb").read())
            if sha_of(d) == ORIG_SHA:
                ORIG_DATA = d

    cur = fetch_current()
    desc, orig = identify(cur)

    if a.action == "status":
        print("状态：" + desc)
        print(f"备份 {BACKUP}: {sha_remote(BACKUP) or '不存在'}")
        return

    if ORIG_DATA is None:
        sys.exit("拿不到原厂镜像（备份缺失且仓库归档不匹配），无法安全操作")

    if a.action == "on":
        want = patched(ORIG_DATA, a.waveform)
        if sha_of(cur) == sha_of(want):
            print(f"已经是 waveform={a.waveform}，无需操作")
            return
        if orig is None:
            sys.exit("当前文件是未知内容，先跑 off 确认再操作")
        ensure_backup()
        got = replace_with(want)
        if got != sha_of(want):
            sys.exit("写入后校验失败！请立刻执行 off")
        print(f"已写入 waveform={a.waveform}（{KNOWN[a.waveform]}），{got}")
        if a.reboot:
            reboot()
        else:
            print("说明：改动需重启才生效")
        return

    # off
    if sha_of(cur) == ORIG_SHA:
        print("已经是原厂版本，无需操作")
        return
    got = replace_with(ORIG_DATA)
    if got != ORIG_SHA:
        sys.exit("还原后校验失败！")
    print("已还原为原厂版本")
    if a.reboot:
        reboot()
    else:
        print("说明：改动需重启才生效")


if __name__ == "__main__":
    main()
