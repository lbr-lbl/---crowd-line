class_name GameView
extends Node2D
## 渲染层：绘制背景兜底、热力图、成分云、线路、车辆段、站点。
## 乘客小点与列车分别在 PassengerLayer / TrainLayer（它们各自带着色器），
## 这样"点"和"车"能各自做动画，也免得一个 CanvasItem 只有一个材质。

const GOLDEN_ANGLE := 2.39996323  # 137.5°

var sim: Simulation
var camera: Camera2D

var heat_tex: GradientTexture2D

## 场景里已有 BackgroundLayer（亮色图纸底）时置 false，免得盖住它
@export var paint_background: bool = true

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

## 轨道几何（共端点的多条线在站点处错开 + 站点胶囊体）。## **全渲染层共用这一份**：线路折线、列车位置、乘客点簇都从它取，否则三处会错位。
## 由 GameView 持有并在 `_process` 里按需重建，Game 会把它注入 PassengerLayer / TrainLayer。
var route_geo: RouteGeometry = RouteGeometry.new()


## 由 Game 在相机 setup 后调用：把三段视野锚点注入渲染层。
func set_zoom_bands(p_overview: float, p_mid: float, p_fore: float) -> void:
	overview_zoom = maxf(p_overview, 0.0001)
	mid_zoom = maxf(p_mid, overview_zoom + 0.0001)
	fore_zoom = maxf(p_fore, mid_zoom + 0.0001)
	bands_ready = true


func _ready() -> void:
	heat_tex = _make_heat_texture()
	set_process(true)
	EventBus.camera_focus.connect(_on_camera_focus)


## 镜头飞到某站时的短暂高亮脉冲（会自己衰减）
var _focus_sid: int = -1
var _focus_t: float = 0.0


func _on_camera_focus(_world: Vector2, station_id: int) -> void:
	_focus_sid = station_id
	_focus_t = 1.0


func _process(_delta: float) -> void:
	if sim != null:
		route_geo.rebuild_if_needed(sim)
	if _focus_t > 0.0:
		_focus_t = maxf(0.0, _focus_t - _delta / 1.1)
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

	# 背景兜底：场景里没有 BackgroundLayer 时，这里铺一层时段底色
	if paint_background:
		var bg := sim.time.display_bg if sim.time else Config.COLOR_BG_BASE
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

	# 车辆段（在建标记 / 已建棚位）——压在线路之上、站点之下
	_draw_depots()

	# 站点
	_draw_stations()


## 云 → 点的混合系数：1.0 = 全云（全貌段），0.0 = 全点（中景及更近）。
## 优先用相机三段锚点；未注入时退回写死的兜底阈值。
func _cloud_blend() -> float:
	return cloud_blend_for(camera.zoom.x if camera else 1.0)


## 给定缩放值算云量（纯函数：便于单测，也便于别处复用同一套档位逻辑）
func cloud_blend_for(zoom: float) -> float:
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


## 时段 -> 画面"鲜艳度"：高峰最艳，深夜最沉。
## 浅色底上这个值用来决定颜色往墨色里压多深。
func _vibrancy() -> float:
	return Config.vibrancy_for_period(sim.time.get_period() if sim.time else "flat")


## 线路实际画出来的颜色。**与列车同源**（Config.line_draw_color），保证车线同色。
func _tint_line(c: Color) -> Color:
	return Config.line_draw_color(c, _vibrancy())


func _draw_heatmap(scale: float = 1.0) -> void:
	if scale <= 0.001 or heat_tex == null:
		return
	var z := _z()
	for st in sim.stations:
		var d := st.display_density
		if d < 0.05:
			continue
		var alpha := clampf(d * 0.62, 0.0, 0.72) * scale
		var col := Config.ink(Config.heat_color(d), 0.10)
		col.a = alpha
		var r := Config.view_px(22.0 + d * 40.0, z)
		draw_texture_rect(heat_tex, Rect2(st.position - Vector2(r, r), Vector2(r * 2, r * 2)), false, col)


## 视野尺寸补偿用的当前缩放
func _z() -> float:
	if camera == null:
		return 1.0
	return maxf(camera.zoom.x, 0.001)


## （虚线辅助函数已移除：线路按用户要求改回一笔实线，并且不要白色轮廓）


func _draw_lines() -> void:
	var z := _z()
	for ln in sim.lines:
		# 折线走"泊位"而不是站点中心：共端点的多条线因此在站点处上下分开，
		# 不会两条叠在一起（几何来自共享的 RouteGeometry）
		var pts := PackedVector2Array()
		for i in range(ln.station_ids.size()):
			pts.append(route_geo.port(sim, ln, i, z))
		# 实线、无白色轮廓：一笔画完，只留线路色（用户要求）
		# 选中某条线时**凸显它、淡化其它线**（需求："点击线路则凸显该线路、其它线路淡化"）
		var col := _tint_line(ln.color)
		if sim.selected_line_id >= 0 and ln.id != sim.selected_line_id:
			col = Color(col.r, col.g, col.b, 0.22)
		draw_polyline(pts, col, Config.view_px(6.0, z), true)


## 横向胶囊填充（调用前请自行 draw_set_transform 到中心并旋转到长轴）
func _capsule_fill(half_len: float, half_w: float, col: Color) -> void:
	var band := maxf(half_len - half_w, 0.0)
	if band > 0.001:
		draw_rect(Rect2(-band, -half_w, band * 2.0, half_w * 2.0), col)
	draw_circle(Vector2(-band, 0.0), half_w, col)
	draw_circle(Vector2(band, 0.0), half_w, col)


## 横向胶囊描边
func _capsule_outline(half_len: float, half_w: float, col: Color, width: float) -> void:
	var band := maxf(half_len - half_w, 0.0)
	if band > 0.001:
		draw_line(Vector2(-band, -half_w), Vector2(band, -half_w), col, width, true)
		draw_line(Vector2(-band, half_w), Vector2(band, half_w), col, width, true)
	draw_arc(Vector2(band, 0.0), half_w, -PI * 0.5, PI * 0.5, 20, col, width, true)
	draw_arc(Vector2(-band, 0.0), half_w, PI * 0.5, PI * 1.5, 20, col, width, true)


func _draw_stations() -> void:
	var z := _z()
	# 站点与列车**一起**随缩放放大缩小：全貌段最小、越放大越大（需求）
	var grow := Config.view_grow(z, fore_zoom)
	for st in sim.stations:
		# 站点是**长条胶囊体**：长轴 = 该站各线的错开方向，长度按经过的线数加长，
		# 于是同一个站上的两条线各自接在胶囊的上下两端，不会互相覆盖。
		var base_half := clampf(6.0 + float(st.effective_capacity()) / 40.0, 7.0, 16.0) * grow
		var cap := route_geo.capsule(sim, st.id, base_half, z)
		var center: Vector2 = cap[0]
		var hl: float = cap[1]
		var hw: float = cap[2]
		var ax: Vector2 = route_geo.axis(st.id)
		var ang: float = ax.angle() if ax.length() > 0.001 else 0.0

		var outline := Config.COLOR_INK
		if st.closed:
			outline = Color(0.78, 0.16, 0.22)
		elif st.skip_trains:
			outline = Color(0.85, 0.48, 0.08)

		draw_set_transform(center, ang, Vector2.ONE)
		# 站点画法参考地铁线路图惯例（用户给的参考是 metroman/线路通）：
		# **白底 + 细墨环**。换乘站是长条胶囊（需要它把共端点的两条线上下分开），
		# 站内不再画"实心深色块 + 白圈"那套同心圆 —— 那会读成一个靶心，形状很怪。
		_capsule_fill(hl, hw, Color(1.0, 1.0, 1.0, 0.97))
		_capsule_outline(hl, hw, outline, Config.view_px(2.4, z) * grow)
		if st.is_interchange():
			# 换乘站：再加一圈细同心环表意"可换乘"
			_capsule_outline(hl * 0.58, hw * 0.58,
				Color(Config.COLOR_INK.r, Config.COLOR_INK.g, Config.COLOR_INK.b,
					0.55 if camera_settled else 0.28),
				Config.view_px(1.8, z) * grow)
		# 恐慌高亮
		if st.panic > 0.5:
			var p1 := Config.view_px(5.0, z) * grow
			_capsule_outline(hl + p1, hw + p1,
				Color(Config.COLOR_PANIC.r, Config.COLOR_PANIC.g, Config.COLOR_PANIC.b, st.panic),
				Config.view_px(3.0, z) * grow)
		# 站台超容：人群已溢出到站外，画一圈橙色外扩告警环
		var ov := st.overflow_ratio()
		if ov > 0.0:
			var p2 := Config.view_px(6.0 + clampf(ov, 0.0, 2.0) * 4.0, z) * grow
			_capsule_outline(hl + p2, hw + p2,
				Color(0.92, 0.36, 0.06, clampf(0.30 + ov * 0.40, 0.0, 0.9)),
				Config.view_px(2.0, z) * grow)
		# 选中高亮
		if sim.selected_station_id == st.id:
			var p3 := Config.view_px(8.0, z) * grow
			_capsule_outline(hl + p3, hw + p3, Config.COLOR_INK, Config.view_px(2.0, z) * grow)
		# 镜头飞到本站时的短暂脉冲（从中心向外扩散一圈并淡出）
		if st.id == _focus_sid and _focus_t > 0.0:
			var pf := Config.view_px(8.0 + (1.0 - _focus_t) * 44.0, z) * grow
			_capsule_outline(hl + pf, hw + pf,
				Color(Config.COLOR_INK.r, Config.COLOR_INK.g, Config.COLOR_INK.b, _focus_t * 0.85),
				Config.view_px(2.6, z) * grow)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 车辆段棚位相对所属站点的偏移。
## **必须跟着 `grow` 一起缩放**：站点现在随缩放变大变小，如果这个偏移是固定屏幕距离，
## 全貌段站点很小、车辆段却仍在 26px 外（显得被推远了），放大时又会贴到站上 ——
## 用户反馈"车辆段和站点之间间隔也会变化"就是这个。
func _depot_mark_offset(z: float, grow: float) -> Vector2:
	return Vector2(0.0, Config.view_px(-26.0, z) * grow)


## 车辆段：未建 = 墨色虚线框（规划位置），已建 = 线路色棚位 + 段内股道
func _draw_depots() -> void:
	var z := _z()
	var grow := Config.view_grow(z, fore_zoom)
	for ln in sim.lines:
		var sid := ln.depot_station_id()
		if sid < 0:
			continue
		var st: Station = sim.stations[sid]
		var base: Vector2 = st.position + _depot_mark_offset(z, grow)
		var col := _tint_line(ln.color)
		var w := Config.view_px(22.0, z) * grow
		var h := Config.view_px(14.0, z) * grow
		var r := Rect2(base - Vector2(w, h) * 0.5, Vector2(w, h))
		if ln.depot_built:
			draw_rect(r, Color(col.r, col.g, col.b, 0.35))
			draw_rect(r, Color(col.r, col.g, col.b, 0.95), false, Config.view_px(1.5, z) * grow)
			for i in range(3):
				var y := base.y - h * 0.26 + h * 0.26 * float(i)
				draw_line(Vector2(base.x - w * 0.34, y), Vector2(base.x + w * 0.34, y),
					Color(1, 1, 1, 0.65), Config.view_px(1.0, z) * grow)
			# 有没兑现的加挂指令：黄色脉冲环，提示"下一列车停这儿会多停几秒"
			if ln.pending_couples > 0:
				var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.006)
				draw_arc(base, Config.view_px(17.0 + pulse * 3.0, z) * grow, 0.0, TAU, 28,
					Color(0.95, 0.52, 0.05, 0.45 + 0.45 * pulse), Config.view_px(1.8, z) * grow, true)
		else:
			# 未建：只画虚框。**不要白色填充**——亮色"纸面"主题下，白填充会读成
			# "没加载出来的空占位图"，看起来像 bug。用墨色虚线表达"规划中"，
			# 与"已建成"的线路色实线形成语义区分。
			var ink := Color(Config.COLOR_INK.r, Config.COLOR_INK.g, Config.COLOR_INK.b, 0.45)
			var dash := Config.view_px(3.5, z) * grow
			var lw := Config.view_px(1.4, z) * grow
			draw_dashed_line(Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), ink, lw, dash)
			draw_dashed_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), ink, lw, dash)
			draw_dashed_line(Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y), ink, lw, dash)
			draw_dashed_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y), ink, lw, dash)
			draw_circle(base, Config.view_px(1.6, z) * grow, ink)


func _draw_clouds(alpha: float) -> void:
	if alpha <= 0.001 or heat_tex == null:
		return
	var z := _z()
	# 四种乘客状态各画一坨软斑，按黄金角错开叠加 -> "成分云"
	var state_colors := PackedColorArray([
		Config.ink(Config.COLOR_NORMAL, 0.18),
		Config.ink(Config.COLOR_WAITING, 0.22),
		Config.ink(Config.COLOR_CROWDED, 0.14),
		Config.ink(Config.COLOR_PANIC, 0.16),
	])
	for st in sim.stations:
		var buckets := _cloud_buckets(st)
		var total: int = buckets[0] + buckets[1] + buckets[2] + buckets[3]
		if total <= 0:
			continue
		# 云团基准半径随人数增长（sqrt 抑制极端值），并受显示密度平滑。
		# 尺寸同样走 view_px 补偿：放大时云团不变大，只是站与站之间被拉开。
		var dens := clampf(st.display_density, 0.0, 1.5)
		var base_r := Config.view_px(clampf(16.0 + sqrt(float(total)) * 5.0, 18.0, 96.0), z)
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
			col.a = clampf(0.45 + share * 0.85, 0.0, 1.1) * alpha
			draw_texture_rect(
				heat_tex,
				Rect2(st.position + off - Vector2(r, r), Vector2(r * 2.0, r * 2.0)),
				false, col)
		# 外圈：让云团仍能定位到站点
		draw_arc(st.position, base_r * 1.05, 0.0, TAU, 36,
			Color(Config.COLOR_INK.r, Config.COLOR_INK.g, Config.COLOR_INK.b, 0.16 * alpha),
			Config.view_px(1.5, z), true)
		# 恐慌：紫色告警环
		if st.panic > 0.5:
			draw_arc(st.position, base_r * 1.18, 0.0, TAU, 40,
				Color(0.62, 0.24, 0.85, st.panic * 0.8 * alpha), Config.view_px(3.0, z), true)


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
