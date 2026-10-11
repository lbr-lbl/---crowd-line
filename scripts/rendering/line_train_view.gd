class_name LineTrainView
extends Node2D
## 一条线上所有列车的绘制单元：持有该线颜色的车身材质。
##
## 车身是**镂空胶囊体**，镂空部分的填充量 = 载客率（着色器里按 UV 从左往右填）。
## 加减速 / 刹车灯 / 车头灯 / 停站压暗都由 `shaders/train_body.gdshader` 表现，
## 逐车数据通过**顶点 COLOR** 四个通道传进去（r=车速 g=刹车 b=停站剩余 a=载客率）。
## 靠站剩余时间用一圈"排空"的圆环表现。
##
## ⚠ **索引坑（曾导致"所有列车挤在一条线上"）**：
## `Train.from_idx` / `to_idx` 是**本线 `station_ids` 的下标**，不是全局站点 id。
## 必须 `sim.stations[line.station_ids[idx]]`，直接写 `sim.stations[t.from_idx]`
## 会把每条线的列车都画到"全局第 N 号站"上——而低编号站全属于第一条线。
##
## ⚠ **停站时不能 early-return**：列车到站后 `from_idx == to_idx`，如果因为
## "两点重合"就 `continue`，列车会在站里整段消失、靠站剩余环也一起没了。

const TRAIN_SHADER := "res://shaders/train_body.gdshader"

var sim: Simulation = null
var line: Line = null
## 车身基色 = **该线在 JSON 里的颜色**（由 TrainLayer 注入）。
## 实际画出来时还要按当前昼夜活力压向墨色，走 `Config.line_draw_color()`——
## 与线路本体同一个函数，所以车和线永远同色。
var body_color: Color = Color.WHITE
var _mat: ShaderMaterial = null
var _applied_body: Color = Color(0, 0, 0, 0)

## 三段视野锚点（由 TrainLayer 注入）：用来判断"是不是远景"，远景把车身拉长一点更好认
var zoom_bands: Vector3 = Vector3(0.9, 3.2, 9.0)

## train_id -> 该车当前的世界坐标（每帧在 _draw 里更新）。
## 两个用途：相机"跟车"、以及在相机里做点击命中判定。
var world_pos: Dictionary = {}

## 共享的轨道几何（由 TrainLayer 从 GameView 注入）：
## 列车必须走**自己那条线的泊位**，否则在换乘站会偏到别的线的轨道上。
var route_geo: RouteGeometry = null

## train_id -> 平滑后的车速 0..1
var _speed: Dictionary = {}
## train_id -> 上一帧的段内进度（用来推瞬时速度）
var _prev_progress: Dictionary = {}
## train_id -> 上一次"在跑"时的朝向（停站时复用，车头才不会突然转到 0 度）
var _last_ang: Dictionary = {}


func _ready() -> void:
	_mat = ShaderMaterial.new()
	if ResourceLoader.exists(TRAIN_SHADER):
		_mat.shader = load(TRAIN_SHADER)
	_mat.set_shader_parameter("ink_color", Config.COLOR_INK)
	material = _mat
	set_process(true)
	_refresh_body_color()


func _process(delta: float) -> void:
	_refresh_body_color()
	_update_speed(delta)
	queue_redraw()


## 车身颜色 = 该线线色 + 当前昼夜活力（与线路本体同一个函数，必然同色）。
## 只有真的变了才写 uniform，避免每帧无谓地上传材质参数。
func _refresh_body_color() -> void:
	if _mat == null or line == null:
		return
	var period := "flat"
	if sim != null and sim.time != null:
		period = sim.time.get_period()
	var col := Config.line_draw_color(body_color, Config.vibrancy_for_period(period))
	if col != _applied_body:
		_applied_body = col
		_mat.set_shader_parameter("body_color", col)


## 本线第 idx 个站的**世界坐标**。idx 是 station_ids 的下标，不是站点 id。
func station_pos(idx: int) -> Vector2:
	if sim == null or line == null:
		return Vector2.ZERO
	if idx < 0 or idx >= line.station_ids.size():
		return Vector2.ZERO
	return sim.stations[line.station_ids[idx]].position


## 本线在第 idx 个站的**泊位**：多线共用该站时会沿胶囊长轴错开。
## 没有几何信息时退回站点中心。
func lane_pos(idx: int, zoom: float) -> Vector2:
	if route_geo == null:
		return station_pos(idx)
	return route_geo.port(sim, line, idx, zoom)


func _valid_idx(idx: int) -> bool:
	return line != null and idx >= 0 and idx < line.station_ids.size()


## 某列车当前应该画在哪（纯计算，便于测试断言"车确实在自己线上"）。
## 停站时 from_idx == to_idx，位置就是该站的泊位。
func train_position(t: Train) -> Vector2:
	if not _valid_idx(t.from_idx) or not _valid_idx(t.to_idx):
		return Vector2.ZERO
	var z := _view_zoom()
	if t.from_idx == t.to_idx:
		return lane_pos(t.to_idx, z)
	return lane_pos(t.from_idx, z).lerp(lane_pos(t.to_idx, z), clampf(t.progress, 0.0, 1.0))


## 用「段内进度变化 × 段长 / 时间」估当前车速，再除以设计速度归一化到 0..1。
func _update_speed(delta: float) -> void:
	if sim == null or line == null:
		return
	for t in line.trains:
		var seg := _seg_len(t)
		var prev: float = float(_prev_progress.get(t.id, t.progress))
		var inst := 0.0
		if seg > 1.0 and delta > 0.0001:
			inst = absf(t.progress - prev) * seg / delta / maxf(t.speed, 1.0)
		inst = clampf(inst, 0.0, 1.0)
		var smoothed: float = lerpf(float(_speed.get(t.id, inst)), inst, 0.25)
		_speed[t.id] = smoothed
		_prev_progress[t.id] = t.progress


func _seg_len(t: Train) -> float:
	if not _valid_idx(t.from_idx) or not _valid_idx(t.to_idx):
		return 0.0
	return station_pos(t.from_idx).distance_to(station_pos(t.to_idx))


func _view_zoom() -> float:
	var c := get_viewport().get_camera_2d()
	if c == null:
		return 1.0
	return maxf(c.zoom.x, 0.001)


## 0 = 中景及更近，1 = 全貌段（越远越大）。远景把车身拉长、加粗一点才认得出来。
func _far_amount(z: float) -> float:
	var lo := zoom_bands.x
	var hi := zoom_bands.y
	return clampf((hi - z) / maxf(hi - lo, 0.01), 0.0, 1.0)


func _draw() -> void:
	if sim == null or line == null:
		return
	var z := _view_zoom()
	for t in line.trains:
		if not _valid_idx(t.from_idx) or not _valid_idx(t.to_idx):
			continue
		var dwelling: bool = (t.from_idx == t.to_idx)
		var pos := train_position(t)
		# 记下位置：相机"跟车"功能与点击命中都要用它（见 TrainLayer.train_world_pos）
		world_pos[t.id] = pos
		# 朝向：在跑时取本段方向；停站时沿用进来时的朝向（否则车头会突然转 0 度）
		var ang: float = float(_last_ang.get(t.id, 0.0))
		if not dwelling:
			var a := lane_pos(t.from_idx, z)
			var b := lane_pos(t.to_idx, z)
			if not a.is_equal_approx(b):
				ang = (b - a).angle()
				_last_ang[t.id] = ang

		var spd := clampf(float(_speed.get(t.id, 0.0)), 0.0, 1.0)
		var dwell := 0.0
		if t.state == Train.TrainState.DWELL:
			dwell = clampf(t.dwell_timer / maxf(t.dwell_time, 0.001), 0.0, 1.0)
		# 接近下一站时算"正在减速"
		var brake := 0.0
		if spd > 0.05 and t.progress > 0.55:
			brake = clampf((t.progress - 0.55) / 0.45, 0.0, 1.0)
		var load := clampf(float(t.passengers.size()) / maxf(1.0, float(t.capacity)), 0.0, 1.0)

		# 尺寸：**符号随缩放一起放大缩小**（Config.view_grow）——
		# 全貌段（H）最小、越放大越大。之前我用 `TRAIN_FAR_LEN` 做成了"远景更长"，方向是反的。
		var grow := Config.view_grow(z, zoom_bands.z)
		var stretch := lerpf(0.90, 1.10, spd)
		var len_px := (18.0 + 13.0 * float(t.cars)) * stretch * grow
		var h_px := 15.0 * grow
		var size := Vector2(Config.view_px(len_px, z), Config.view_px(h_px, z))

		# 车身：**任何状态都画**。之前停站时把车身换成环，用户看到的是"列车进站直接消失了"。
		# 一个 draw_rect 就够：形状（**镂空胶囊**）、内部填充量、灯带、刹车灯全在着色器里。
		# 颜色四个通道是给着色器的数据（车速/刹车/停站剩余/载客率），不是真的颜色。
		draw_set_transform(pos, ang, Vector2.ONE)
		draw_rect(Rect2(-size * 0.5, size), Color(spd, brake, dwell, load), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		# 靠站：车**不消失**，只是在外面套一圈**环状时间条**表示剩余停站时间，
		# 外加一个在跳的秒数——这样"等待时间"是看得见在走的。
		if dwelling:
			var w_ring := Config.view_px(5.0, z)
			var r_ring := maxf(size.x, size.y) * 0.5 + w_ring * 1.5
			# 底环很淡（"总时长"），排空弧很实且用墨色 —— 车身本身就是线路色，
			# 用线路色画弧会和车身糊在一起，看不出在排空
			draw_arc(pos, r_ring, 0.0, TAU, 48,
				Color(Config.COLOR_INK.r, Config.COLOR_INK.g, Config.COLOR_INK.b, 0.12), w_ring, true)
			if dwell > 0.001:
				draw_arc(pos, r_ring, -PI * 0.5, -PI * 0.5 + TAU * dwell, 48,
					Color(Config.COLOR_INK.r, Config.COLOR_INK.g, Config.COLOR_INK.b, 0.92), w_ring, true)
			# 排空扇形：**不依赖字体**的"饼"，随剩余时间收缩 —— 一定能看见，
			# 而且"时间在走"比数字更直观。
			# （试过在环上画剩余秒数，但这个尺寸下 `draw_string` 的字形根本出不来，
			#   排查成本超过收益，改用纯图形表达。）
			#
			# ⚠ 两个必须的守卫，否则 Godot 会每帧刷 "Invalid polygon data, triangulation failed"：
			#   ① `dwell` 太小时弧的跨度趋近 0，多边形退化成一条线；
			#   ② `r_pie` 在低缩放下可能被算成 ≤ 0（环半径 < 线宽），也是退化多边形。
			var r_pie := maxf(r_ring - w_ring * 1.6, r_ring * 0.34)
			if r_pie > 0.5 and dwell > 0.06:
				var steps := clampi(int(ceil(48.0 * dwell)), 8, 48)
				var pts := PackedVector2Array()
				pts.append(pos)
				for i in range(steps + 1):
					var a := -PI * 0.5 + TAU * dwell * float(i) / float(steps)
					pts.append(pos + Vector2(cos(a), sin(a)) * r_pie)
				draw_colored_polygon(pts,
					Color(Config.COLOR_INK.r, Config.COLOR_INK.g, Config.COLOR_INK.b, 0.22))

		# 加挂中：黄色进度环
		if t.coupling:
			draw_arc(pos, Config.view_px(20.0, z), -PI * 0.5, -PI * 0.5 + TAU * t.couple_progress(), 32,
				Color(1.0, 0.60, 0.08, 0.95), Config.view_px(2.5, z), true)
		# 晚点：红环
		if t.delay > 15.0:
			draw_arc(pos, Config.view_px(24.0, z), 0.0, TAU, 24,
				Color(0.85, 0.13, 0.18, 0.75), Config.view_px(2.0, z), true)
