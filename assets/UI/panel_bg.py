from PIL import Image, ImageDraw

# 4倍超采样，缩小后抗锯齿
scale = 4
size = 64
radius = 12
img = Image.new('RGBA', (size*scale, size*scale), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# 深色半透明填充
fill_color = (26, 26, 26, 180)  # #1A1A1A，不透明度约70%
draw.rounded_rectangle(
    [0, 0, size*scale - 1, size*scale - 1],
    radius=radius*scale,
    fill=fill_color
)

# 缩小回目标尺寸
img = img.resize((size, size), Image.LANCZOS)
img.save('panel_bg.png')