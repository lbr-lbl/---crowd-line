"""打印图标 PNG 的 alpha 结构（低分辨率 ASCII 图），用于给着色器定 UV 逻辑。"""
import os
from PIL import Image

ICON_DIR = r"F:\Godot_project\涌线--crowd-line\assets\icons"
NAMES = ["train_body.png", "passenger_dot.png", "station_ring.png",
         "icon_limit.png", "icon_pause.png", "badge_A.png", "icon_log.png"]

CHARS = " .:-=+*#%@"


def show(path, cols=56):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    rows = max(1, int(cols * h / w / 2.1))
    small = im.resize((cols, rows), Image.LANCZOS)
    px = small.load()
    print("\n=== %s  (%dx%d) ===" % (os.path.basename(path), w, h))
    for y in range(rows):
        line = ""
        for x in range(cols):
            a = px[x, y][3]
            line += CHARS[min(len(CHARS) - 1, int(a / 256.0 * len(CHARS)))]
        print(line)


for n in NAMES:
    p = os.path.join(ICON_DIR, n)
    if os.path.exists(p):
        show(p)
    else:
        print("missing", n)
