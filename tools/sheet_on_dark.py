"""把图标总览合成到深色底上，让白色图标可见（原图是白+alpha，直接看是一片白）。"""
from PIL import Image

SHEET = r"F:\Godot_project\涌线--crowd-line\assets\图标总览.png"
OUT = r"F:\Godot_project\涌线--crowd-line\tools\_sheet_dark.png"

im = Image.open(SHEET).convert("RGBA")
bg = Image.new("RGBA", im.size, (16, 18, 32, 255))
bg.alpha_composite(im)
bg.convert("RGB").save(OUT)
print("saved", OUT, bg.size)
