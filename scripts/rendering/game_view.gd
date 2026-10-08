class_name GameView
extends Node2D
## 渲染层：绘制背景、热力图、线路、站点、列车、乘客 / 成分云。

const GOLDEN_ANGLE := 2.39996323  # 137.5°

var sim: Simulation
var camera: Camera2D

var heat_tex: GradientTexture2D

# 成分云 / 圆点切换的缩放阈值（兜底值；正常情况下由相机三段视野驱动）
const CLOUD_ZOOM := 0.6
const DOT_ZOOM := 0.95

# 相机三段视野锚点（由 Game 在相机 setup 后注入）
#   全貌段 H：乘客聚合成半透明"成分云"
#   中景段 M：云 → 点交叉淡化
#   近景段 L：单个乘客清晰可辨
var overview_zoom: float = 0.0
var mid_zoom: float = 0.0
var fore_zoom: float = 0.0
var bands_ready: bool = false

# 相机是否已稳定停在某个视野段（由 Game 每帧同步），用于"站点涂黑 ○→●"
var camera_settled: bool = true


## 由 Game 在相机 setup 后调用：把三段视野锚点注入渲染层。
func set_zoom_bands(p_overview: float, p_mid: float, p_fore: float) -> void:
	overview_zoom = maxf(p_overview, 0.0001)
	mid_zoom = maxf(p_mid, overview_zoom + 0.0001)
	fore_zoom = maxf(p_fore, mid_zoom + 0.0001)
	bands_ready = true


func _ready() -> void:
	heat_tex = _make_heat_texture()
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _make_heat_texture() -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 0.5),
		Color(1, 1, 1, 0.18),
		Color(1, 1, 1, 0.0),
	])
	tex.gradient = grad
	return tex


func _draw() -> void:
	if sim == null:
		return

	var bg := sim.time.display_bg if sim.time else Config.COLOR_BG_BASE

	# 背景
	draw_rect(Rect2(Vector2(-60000, -60000), Vector2(120000, 120000)), bg)

	# 云 → 点混合系数（全貌段为全云，中景及更近为全点）
	var cloud := _cloud_blend()

	# 热力图（站点密度光晕）——云段淡出，避免与成分云糊在一起
	_draw_heatmap(1.0 - cloud * 0.75)

	# 成分云（全貌段 H）——压在线路之下，避免糊掉线网
	if cloud > 0.001:
		_draw_clouds(cloud)

	# 线路
	_draw_lines()

	# 站点
	_draw_stations()

	# 列车
	_draw_trains()

	# 乘客圆点（中景 M / 近景 L 段）——画在最上层
	var dots_alpha := 1.0 - cloud
	if dots_alpha > 0.001:
		_draw_dots(dots_alpha)


## 云 → 点的混合系数：1.0 = 全云（全貌段），0.0 = 全点（中景及更近）。
## 优先用相机三段锚点；未注入时退回写死的兜底阈值。
func _cloud_blend() -> float:
	var zoom := camera.zoom.x if camera else 1.0
	if bands_ready:
		if zoom <= overview_zoom:
			return 1.0
		if zoom >= mid_zoom:
			return 0.0
		return 1.0 - (zoom - overview_zoom) / maxf(mid_zoom - overview_zoom, 0.0001)
	if zoom < CLOUD_ZOOM:
		return 1.0
	if zoom < DOT_ZOOM:
		return 1.0 - (zoom - CLOUD_ZOOM) / (DOT_ZOOM - CLOUD_ZOOM)
	return 0.0


func _vibrancy() -> float:
	var p := sim.time.get_period() if sim.time else "flat"
	match p:
		"morning_peak", "evening_peak":
			return 1.0
		"night", "late_night":
			return 0.55
		_:
			return 0.8


func _tint_line(c: Color) -> Color:
	var v := _vibrancy()
	return c.lerp(Color(0.5, 0.5, 0.62), 1.0 - v)


func _draw_heatmap(scale: float = 1.0) -> void:
	if scale <= 0.001:
		return
	for st in sim.stations:
		var d := st.display_density
		if d < 0.05:
			continue
		var alpha := clampf(d * 0.8, 0.0, 0.9) * scale
		var col := Config.heat_color(d)
		col.a = alpha
		var r := 22.0 + d * 40.0
		draw_texture_rect(heat_tex, Rect2(st.position - Vector2(r, r), Vector2(r * 2, r * 2)), false, col)


func _draw_lines() -> void:
	for ln in sim.lines:
		var pts := PackedVector2Array()
		for sid in ln.station_ids:
			pts.append(sim.stations[sid].position)
		var col := _tint_line(ln.color)
		# 外发光
		var glow := col
		glow.a = 0.25
		draw_polyline(pts, glow, 14.0, true)
		# 主线
		draw_polyline(pts, col, 7.0, true)


func _draw_stations() -> void:
	for st in sim.stations:
		var r := 6.0 + float(st.effective_capacity()) / 40.0
		r = clampf(r, 7.0, 16.0)
		var outline := Color.WHITE
		if st.closed:
			outline = Color(1.0, 0.4, 0.4)
		elif st.skip_trains:
			outline = Color(1.0, 0.7, 0.3)
		# 外圈
		draw_circle(st.position, r, outline, false, 2.5, true)
		# 内部填充（换乘站亮色）
		# 视野稳定在某段锚点后"站点涂黑"（●）；缩放过程中保持空心（○）
		var core := Color(0.15, 0.16, 0.22)
		if camera_settled:
			core = Color(0.34, 0.38, 0.5)
		if st.is_interchange():
			var hub_a := 0.9 if camera_settled else 0.62
			draw_circle(st.position, r * 0.55, Color(0.9, 0.9, 1.0, hub_a))
			draw_circle(st.position, r * 0.3, Color(0.2, 0.2, 0.3))
		else:
			draw_circle(st.position, r * 0.55, core)
		# 恐慌高亮
		if st.panic > 0.5:
			draw_arc(st.position, r + 5.0, 0.0, TAU, 40, Color(1.0, 0.3, 0.7, st.panic), 3.0, true)
		# 站台超容：人群已溢出到站外，画一圈橙色外扩告警环
		var ov := st.overflow_ratio()
		if ov > 0.0:
			var orad := r + 6.0 + clampf(ov, 0.0, 2.0) * 4.0
			draw_arc(st.position, orad, 0.0, TAU, 36,
				Color(1.0, 0.55, 0.25, clampf(0.25 + ov * 0.35, 0.0, 0.85)), 2.0, true)
		# 选中高亮
		if sim.selected_station_id == st.id:
			draw_arc(st.position, r + 8.0, 0.0, TAU, 48, Color.WHITE, 2.0, true)


func _draw_trains() -> void:
	for t in sim.trains:
		var ln: Line = sim.lines[t.line_id]
		var pos := sim.train_world_position(t)
		var col := _tint_line(ln.color)
		# 车体
		var dir_angle := Vector2.RIGHT.angle_to(
			(sim.stations[ln.station_ids[t.to_idx]].position -
			 sim.stations[ln.station_ids[t.from_idx]].position).normalized()
		)
		var half := Vector2(11.0, 6.0)
		var corners := [
			pos + Vector2(-half.x, -half.y).rotated(dir_angle),
			pos + Vector2(half.x, -half.y).rotated(dir_angle),
			pos + Vector2(half.x, half.y).rotated(dir_angle),
			pos + Vector2(-half.x, half.y).rotated(dir_angle),
		]
		draw_colored_polygon(PackedVector2Array(corners), col)
		draw_circle(pos, 4.0, Color(0.1, 0.1, 0.15))
		# 满载指示
		var fill := float(t.passengers.size()) / float(t.capacity)
		if fill > 0.6:
			draw_circle(pos, 3.0, Config.heat_color(fill))
		# 延误标记
		if t.delay > 15.0:
			draw_arc(pos, 14.0, 0.0, TAU, 24, Color(1.0, 0.3, 0.3, 0.9), 2.0, true)


func _draw_dots(alpha: float) -> void:
	if alpha <= 0.001:
		return
	# 近景程度：0 = 中景（M 段），1 = 近景（L 段）
	var detail := 0.0
	if bands_ready:
		var zoom := camera.zoom.x if camera else mid_zoom
		detail = clampf((zoom - mid_zoom) / maxf(fore_zoom - mid_zoom, 0.0001), 0.0, 1.0)
	for st in sim.stations:
		var i := 0
		# 站台超容时人群"胀"到站外：允许摊得更开，视觉上直接看出哪站堵死
		var spill := clampf(st.overflow_ratio(), 0.0, 2.0) * 14.0
		for p in st.queue:
			if p.state != Passenger.State.WAITING:
				continue
			var ang := i * GOLDEN_ANGLE
			# 近景把站台人群摊开一些，方便数清单个乘客
			var spread := lerpf(3.0, 4.2, detail)
			var r := 8.0 + sqrt(float(i)) * spread
			r = minf(r, lerpf(34.0, 46.0, detail) + spill)
			var off := Vector2(cos(ang), sin(ang)) * r
			var col := _dot_color(p, st)
			col.a = alpha
			var dot_r := lerpf(3.0, 3.6, detail)
			draw_circle(st.position + off, dot_r, col)
			# 近景：不耐烦的乘客加一圈耐心环，个体状态可读
			if detail > 0.5 and p.patience < 0.7:
				draw_arc(st.position + off, dot_r + 2.5,
					-PI * 0.5, -PI * 0.5 + TAU * clampf(p.patience, 0.0, 1.0), 16,
					Color(1, 1, 1, 0.55 * alpha * detail), 1.2, true)
			i += 1


func _dot_color(p: Passenger, st: Station) -> Color:
	if st.panic > 0.5:
		return Config.COLOR_PANIC
	if p.patience < 0.3:
		return Config.COLOR_CROWDED
	if p.patience < 0.6:
		return Config.COLOR_WAITING
	return Config.COLOR_NORMAL


func _draw_clouds(alpha: float) -> void:
	if alpha <= 0.001:
		return
	# 四种乘客状态各画一坨软斑，按黄金角错开叠加 -> "成分云"
	var state_colors := PackedColorArray([
		Config.COLOR_NORMAL,
		Config.COLOR_WAITING,
		Config.COLOR_CROWDED,
		Config.COLOR_PANIC,
	])
	for st in sim.stations:
		var buckets := _cloud_buckets(st)
		var total: int = buckets[0] + buckets[1] + buckets[2] + buckets[3]
		if total <= 0:
			continue
		# 云团基准半径随人数增长（sqrt 抑制极端值），并受显示密度平滑
		var dens := clampf(st.display_density, 0.0, 1.5)
		var base_r := clampf(16.0 + sqrt(float(total)) * 5.0, 18.0, 96.0)
		base_r *= 0.75 + 0.35 * clampf(dens, 0.0, 1.0)
		for bi in range(4):
			var n: int = buckets[bi]
			if n <= 0:
				continue
			var share := float(n) / float(total)
			var ang := float(bi) * GOLDEN_ANGLE
			var off := Vector2(cos(ang), sin(ang)) * base_r * 0.42
			var r := base_r * (0.55 + 0.45 * sqrt(share))
			var col: Color = state_colors[bi]
			col.a = clampf(0.35 + share * 0.9, 0.0, 1.2) * alpha
			draw_texture_rect(
				heat_tex,
				Rect2(st.position + off - Vector2(r, r), Vector2(r * 2.0, r * 2.0)),
				false, col)
		# 外圈：让云团仍能定位到站点
		draw_arc(st.position, base_r * 1.05, 0.0, TAU, 36,
			Color(1, 1, 1, 0.10 * alpha), 1.5, true)
		# 恐慌：紫色告警环
		if st.panic > 0.5:
			draw_arc(st.position, base_r * 1.18, 0.0, TAU, 40,
				Color(1.0, 0.3, 0.7, st.panic * 0.8 * alpha), 3.0, true)


func _cloud_buckets(st: Station) -> Array:
	var b := [0, 0, 0, 0]  # normal, waiting, crowded, panic
	for p in st.queue:
		if p.state != Passenger.State.WAITING:
			continue
		if st.panic > 0.5:
			b[3] += 1
		elif p.patience < 0.3:
			b[2] += 1
		elif p.patience < 0.6:
			b[1] += 1
		else:
			b[0] += 1
	return b
