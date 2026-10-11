"""分析 assets/图标总览.png：找出每个图标的包围盒，供后续自动切图。

思路：图标是「白色 + alpha」画在透明底上，预览图里看不见。所以不看 RGB，
只看 alpha 通道，用投影法切成网格块。
"""
import sys
from PIL import Image
import numpy as np

SHEET = r"F:\Godot_project\涌线--crowd-line\assets\图标总览.png"

im = Image.open(SHEET)
print("mode =", im.mode, "size =", im.size)
im = im.convert("RGBA")
a = np.array(im)
alpha = a[:, :, 3]
print("alpha: min=%d max=%d mean=%.2f  非透明像素=%d (%.2f%%)" % (
    alpha.min(), alpha.max(), alpha.mean(),
    (alpha > 8).sum(), 100.0 * (alpha > 8).sum() / alpha.size))

rgb = a[:, :, :3].astype(np.int32)
lum = rgb.mean(axis=2)
print("RGB 亮度: min=%.0f max=%.0f mean=%.1f" % (lum.min(), lum.max(), lum.mean()))

# 有内容 = alpha 明显不为 0
mask = alpha > 8
rows = mask.any(axis=1)
cols = mask.any(axis=0)

def runs(flags, min_gap=6):
    out = []
    start = None
    gap = 0
    for i, v in enumerate(flags):
        if v:
            if start is None:
                start = i
            gap = 0
        else:
            if start is not None:
                gap += 1
                if gap >= min_gap:
                    out.append((start, i - gap))
                    start = None
                    gap = 0
    if start is not None:
        out.append((start, len(flags) - 1 - gap))
    return out

rr = runs(rows)
cc = runs(cols)
print("\n行带 %d 条:" % len(rr))
for s, e in rr:
    print("   y %4d..%4d  (高 %d)" % (s, e, e - s + 1))
print("\n列带 %d 条:" % len(cc))
for s, e in cc:
    print("   x %4d..%4d  (宽 %d)" % (s, e, e - s + 1))
