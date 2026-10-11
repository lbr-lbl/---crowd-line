"""从 assets/图标总览.png 中裁出每个图标，存到 assets/icons/，并生成核对用的拼图。

总览图是「白色 + alpha」画在透明底上（白底看图器里完全看不见），
所以这里只看 alpha 通道做投影切分，保留原始 RGBA（白色图标 + alpha），
游戏里再用 modulate 上色。
"""
import os
from PIL import Image, ImageDraw, ImageFont
import numpy as np

ROOT = r"F:\Godot_project\涌线--crowd-line"
SHEET = os.path.join(ROOT, "assets", "图标总览.png")
OUTDIR = os.path.join(ROOT, "assets", "icons")
CHECK = os.path.join(ROOT, "tools", "_icons_check.png")

# (区块名, 图标行的 y 区间, 该行从左到右的名字；"" 表示这一块不导出)
# 注意：
#  - 操作栏最后一个喇叭被切成了「喇叭本体 + 声波」两块，需要合并；
#  - UI 框架第一块是 panel_bg 的 9-slice 预览，已有 assets/panel_bg.png，不再导出。
SECTIONS = [
    ("操作栏", (86, 275),
     ["icon_limit", "icon_add_train", "icon_close", "icon_skip", "icon_broadcast"], True),
    ("天气粒子", (419, 541),
     ["rain_drop", "snow_flake", "fog_puff", "cloud_soft", "ground_snow"], False),
    ("UI 框架", (686, 789),
     ["", "icon_log", "icon_pause", "icon_play", "icon_fast",
      "badge_S", "badge_A", "badge_B", "badge_C", "badge_D"], False),
    ("可选质感", (907, 964),
     ["passenger_dot", "train_body", "station_ring"], False),
]


def runs(flags, min_gap=8):
    out, start, gap = [], None, 0
    for i, v in enumerate(flags):
        if v:
            if start is None:
                start = i
            gap = 0
        elif start is not None:
            gap += 1
            if gap >= min_gap:
                out.append((start, i - gap))
                start, gap = None, 0
    if start is not None:
        out.append((start, len(flags) - 1 - gap))
    return out


im = Image.open(SHEET).convert("RGBA")
alpha = np.array(im)[:, :, 3]

# 只清掉本脚本自己产出的那批 png，避免上一轮的错名残留
if os.path.isdir(OUTDIR):
    for f in os.listdir(OUTDIR):
        if f.lower().endswith(".png"):
            os.remove(os.path.join(OUTDIR, f))
os.makedirs(OUTDIR, exist_ok=True)

done = []
for sec, (y0, y1), names, merge_tail in SECTIONS:
    band = alpha[y0:y1 + 1, :] > 8
    colruns = runs(band.any(axis=0), min_gap=10)
    if merge_tail and len(colruns) > len(names):
        tail = colruns[len(names) - 1:]
        colruns = colruns[:len(names) - 1] + [(tail[0][0], tail[-1][1])]
    print("== %s：列块 %d，名单 %d" % (sec, len(colruns), len(names)))
    if len(colruns) != len(names):
        print("   !! 数量不匹配，跳过这一段，请人工核对")
        continue
    for idx, (cx0, cx1) in enumerate(colruns):
        name = names[idx]
        sub = band[:, cx0:cx1 + 1]
        rrows = np.where(sub.any(axis=1))[0]
        cy0, cy1 = y0 + int(rrows[0]), y0 + int(rrows[-1])
        if not name:
            print("   (跳过 x %d..%d  y %d..%d)" % (cx0, cx1, cy0, cy1))
            continue
        crop = im.crop((cx0, cy0, cx1 + 1, cy1 + 1))
        crop.save(os.path.join(OUTDIR, name + ".png"))
        done.append((name, crop))
        print("   %-16s %3d x %3d" % (name, crop.size[0], crop.size[1]))

print("\n导出 %d 个图标 -> %s" % (len(done), OUTDIR))

# ---- 核对拼图：把裁出来的图标放到深色底上，按名字排 ----
COLS = 6
CELL = 150
rows = (len(done) + COLS - 1) // COLS
sheet = Image.new("RGB", (COLS * CELL, rows * (CELL + 22)), (16, 18, 32))
d = ImageDraw.Draw(sheet)
try:
    font = ImageFont.load_default(size=13)
except TypeError:
    font = ImageFont.load_default()
for i, (name, img) in enumerate(done):
    gx, gy = (i % COLS) * CELL, (i // COLS) * (CELL + 22)
    w, h = img.size
    s = min((CELL - 20) / w, (CELL - 26) / h, 2.0)
    thumb = img.resize((max(1, int(w * s)), max(1, int(h * s))), Image.LANCZOS)
    layer = Image.new("RGBA", thumb.size, (0, 0, 0, 0))
    layer.alpha_composite(thumb)
    sheet.paste(layer, (gx + (CELL - thumb.size[0]) // 2,
                        gy + (CELL - thumb.size[1]) // 2), layer)
    d.text((gx + 6, gy + CELL + 3), "%s  %dx%d" % (name, w, h),
           fill=(200, 205, 225), font=font)
sheet.save(CHECK)
print("核对拼图 ->", CHECK)
