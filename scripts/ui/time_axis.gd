class_name TimeAxis
extends Control
## 竖直时间轴（需求 ⑧）。
##
## 时间不再是横条，而是**一条竖线**：进度条从顶端**向下降**，颜色随时段变化
## （清晨粉 → 白天蓝 → 傍晚橙 → 夜间深蓝），**顶端那枚图标表示当前的天气**：
## 平时是白天的太阳 / 夜晚的月亮，特殊天气则换成对应的图标。
##
## 天气图示**就地矢量绘制**，不用贴图。
##
## 为什么不用贴图：先用 Tabler Icons（MIT）下载的 SVG 被 Godot/ThorVG 光栅化成了**纯白方块**
## （连本地生成的、采样确认 alpha 正确的 PNG 走 `draw_texture_rect` 也画成白块），
## 排查成本已经超过收益。所以这里直接用 `draw_*` 画，颜色也跟着墨色走，风格统一。
## 下载过的 SVG/PNG 与许可证仍留在 assets/ 里备查，见 `素材应用表.md`。
const INK_GLYPH_SIZE := 26.0

var sim: Simulation = null

## 每个时段填充条的颜色（时间"会变色"就靠它）
const PERIOD_FILL: Dictionary = {
	"dawn": Color("#f9a8c0"),
	"morning_peak": Color("#3b82f6"),
	"flat": Color("#38bdf8"),
	"afternoon": Color("#f59e0b"),
	"evening_peak": Color("#f97316"),
	"night": Color("#4338ca"),
	"late_night": Color("#1e1b4b"),
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null or sim.time == null:
		return
	var period := sim.time.get_period()
	var is_night := period == "night" or period == "late_night"
	var fill: Color = PERIOD_FILL.get(period, Color("#38bdf8"))

	var h := size.y
	var cx := size.x * 0.5
	var top := 10.0
	var bottom := h - 10.0
	var span := maxf(bottom - top, 1.0)

	# 轨道
	draw_rect(Rect2(cx - 5.0, top, 10.0, span), Color(Config.COLOR_INK.r, Config.COLOR_INK.g, Config.COLOR_INK.b, 0.10))
	draw_rect(Rect2(cx - 5.0, top, 10.0, span),
		Color(Config.COLOR_INK.r, Config.COLOR_INK.g, Config.COLOR_INK.b, 0.30), false, 1.0)

	# 进度：从顶端**向下**长。无限模式没有总时长，用"下一波"进度代替
	var p := 0.0
	if sim.infinite_mode and sim.director != null:
		p = clampf(sim.director.progress(), 0.0, 1.0)
	elif sim.duration > 0.0:
		p = clampf(sim.elapsed / sim.duration, 0.0, 1.0)
	var filled := span * p
	if filled > 0.5:
		draw_rect(Rect2(cx - 5.0, top, 10.0, filled), fill)
	# 昼夜分界刻度：每 6 小时一道，让"一天走到哪了"看得见
	for k in range(1, 4):
		var y := top + span * (float(k) / 4.0)
		draw_line(Vector2(cx - 8.0, y), Vector2(cx + 8.0, y),
			Color(Config.COLOR_INK.r, Config.COLOR_INK.g, Config.COLOR_INK.b, 0.22), 1.0)

	# **天气图示就画在"当前时间点"上**（用户要求）：一枚白盘 + 里面的天气图形。
	# 具体时刻不在这里画了 —— 挪到屏幕顶端居中（像手机状态栏），见 hud.tscn 的 TimePanel。
	var my := top + filled
	draw_circle(Vector2(cx, my), 15.0, Color(1, 1, 1, 0.96))
	draw_circle(Vector2(cx, my), 15.0, Config.COLOR_INK, false, 2.0, true)
	_draw_weather_glyph(Vector2(cx, my), is_night, 9.5)


## 就地画天气图示。`r` 是图形半径（放在时间点上时会传得小一些）
func _draw_weather_glyph(c: Vector2, is_night: bool, r: float = INK_GLYPH_SIZE * 0.5) -> void:
	var w := sim.weather.get_weather()
	# 晴 / 酷热 在夜里画月亮
	if is_night and (w == "clear" or w == "heatwave"):
		w = "clear_night"
	var ink := Config.COLOR_INK
	match w:
		"clear_night":
			_draw_crescent(c, r * 0.78, ink)
		"clear", "heatwave":
			# 太阳：实心圆 + 8 道光线（酷热加一圈暖色）
			var disc := ink
			if w == "heatwave":
				disc = Color("#c2410c")
			draw_circle(c, r * 0.42, disc)
			for i in range(8):
				var a := float(i) * PI / 4.0
				var dir := Vector2(cos(a), sin(a))
				draw_line(c + dir * (r * 0.62), c + dir * (r * 0.98), disc, 2.0, true)
		"overcast":
			_draw_cloud(c, ink)
		"light_rain", "heavy_rain":
			_draw_cloud(c + Vector2(0, -r * 0.22), ink)
			for i in range(3):
				var x := c.x - r * 0.42 + float(i) * r * 0.42
				draw_line(Vector2(x, c.y + r * 0.34), Vector2(x - 2.0, c.y + r * 0.78), ink, 2.0, true)
		"thunderstorm":
			_draw_cloud(c + Vector2(0, -r * 0.24), ink)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-1.0, r * 0.16), c + Vector2(-r * 0.42, r * 0.62),
				c + Vector2(-r * 0.06, r * 0.62), c + Vector2(-r * 0.30, r * 1.00),
				c + Vector2(r * 0.42, r * 0.44), c + Vector2(r * 0.04, r * 0.44),
			]), Color("#c2410c"))
		"typhoon":
			# 台风：两道反向的旋臂
			for s in [-1.0, 1.0]:
				draw_arc(c, r * 0.66, 0.0, PI * 1.25, 18, ink, 2.4, true)
				draw_circle(c + Vector2(s * r * 0.66, 0.0), 2.0, ink)
		"fog":
			for i in range(3):
				var y := c.y - r * 0.42 + float(i) * r * 0.42
				var half := r * (0.95 - 0.18 * float(i))
				draw_line(Vector2(c.x - half, y), Vector2(c.x + half, y), ink, 2.4, true)
		"snow":
			for i in range(3):
				var a := float(i) * PI / 3.0
				var dir := Vector2(cos(a), sin(a))
				draw_line(c - dir * r * 0.8, c + dir * r * 0.8, ink, 2.2, true)
		_:
			_draw_cloud(c, ink)


func _draw_cloud(c: Vector2, ink: Color) -> void:
	draw_circle(c + Vector2(-5.0, 2.0), 5.0, ink)
	draw_circle(c + Vector2(3.0, -1.0), 6.5, ink)
	draw_circle(c + Vector2(9.0, 2.5), 4.5, ink)
	draw_rect(Rect2(c.x - 8.0, c.y + 1.0, 18.0, 4.0), ink)


## 月牙：外弧 + 内弧拼成的多边形
func _draw_crescent(c: Vector2, r: float, ink: Color) -> void:
	var pts := PackedVector2Array()
	var n := 22
	for i in range(n + 1):
		var a := deg_to_rad(-62.0 + 304.0 * float(i) / float(n))
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	for i in range(n + 1):
		var a2 := deg_to_rad(242.0 - 304.0 * float(i) / float(n))
		pts.append(c + Vector2(cos(a2) * 0.90, sin(a2) * 0.90) * r + Vector2(r * 0.26, -r * 0.10))
	draw_colored_polygon(pts, ink)
