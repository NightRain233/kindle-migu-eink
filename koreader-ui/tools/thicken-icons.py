#!/usr/bin/env python3
"""把 KOReader 自带的 mdlight 线条图标统一加粗，输出到 koreader/icons/ 覆盖原图标。

用法: thicken-icons.py <原 icons/mdlight 目录> <输出目录> [倍数，默认 1.5]

只改 stroke-width（style 内联写法和属性写法都处理）；没有描边的图标不输出，
KOReader 会继续用自带版本。线宽是相对各自坐标系的，所以按倍数放大对
带 transform 的图标同样成立。
"""
import re
import sys
from pathlib import Path

STYLE_RE = re.compile(r"(stroke-width\s*:\s*)([0-9.]+)")
ATTR_RE = re.compile(r'(stroke-width\s*=\s*")([0-9.]+)(")')


def scale(match, factor, has_tail=False):
    value = float(match.group(2)) * factor
    text = f"{value:.4g}"
    return match.group(1) + text + (match.group(3) if has_tail else "")


def main():
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    factor = float(sys.argv[3]) if len(sys.argv) > 3 else 1.5
    dst.mkdir(parents=True, exist_ok=True)
    written = 0
    for svg in sorted(src.glob("*.svg")):
        text = svg.read_text(encoding="utf-8")
        new, n1 = STYLE_RE.subn(lambda m: scale(m, factor), text)
        new, n2 = ATTR_RE.subn(lambda m: scale(m, factor, True), new)
        if n1 + n2 == 0:
            continue
        (dst / svg.name).write_text(new, encoding="utf-8")
        written += 1
    print(f"{written} icons written to {dst} (x{factor})")


if __name__ == "__main__":
    main()
