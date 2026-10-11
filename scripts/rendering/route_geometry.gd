class_name RouteGeometry
extends RefCounted
## 线路"轨道几何"：把共用同一个站点的多条线在站点处**错开**，避免两条线互相覆盖；
## 站点因此画成**长条胶囊体**（长轴 = 各线错开的方向），每条线接到自己的"泊位"上。
##
## 为什么必须单独抽成一份共享几何：
##   · `GameView._draw_lines` 要用它决定折线怎么拐；
##   · `LineTrainView` 要用它决定列车在哪（车必须沿**自己那条线**的泊位走，否则会偏到别人的轨道上）；
##   · `PassengerLayer` 要用它决定乘客点簇离站点多远（免得糊在胶囊体上）。
## 三处各算一遍一定会错位，所以只有这一个真源。
##
## 泊位间距是"屏幕像素"，用 `Config.view_px()` 换算——放大时站点间距被拉开，
## 但两条线的视觉间距要保持一致。

const LANE_GAP_PX := 7.0   # 相邻两条线在站点处的间距（屏幕像素）

var _axis: Dictionary = {}   # station_id -> Vector2 胶囊长轴（单位向量）
var _lane: Dictionary = {}   # "line_id:stop_idx" -> float 泊位序号（-k..k）
var _span: Dictionary = {}   # station_id -> int 该站有几条线经过
var _stamp: String = ""


## 线路/站点数量变了就重建（无限模式每波加线，所以这是每帧调用、内部自判）
func rebuild_if_needed(sim: Simulation) -> void:
	if sim == null:
		return
	var stamp := "%d/%d" % [sim.lines.size(), sim.stations.size()]
	if stamp == _stamp:
		return
	_stamp = stamp
	rebuild(sim)


func rebuild(sim: Simulation) -> void:
	_axis.clear()
	_lane.clear()
	_span.clear()
	if sim == null:
		return
	# 1) 收集：每个站点上有哪些线、以及各线"离开该站"的方向
	var by_station: Dictionary = {}
	for ln in sim.lines:
		for i in range(ln.station_ids.size()):
			var sid: int = ln.station_ids[i]
			if not by_station.has(sid):
				by_station[sid] = []
			by_station[sid].append([ln.id, _out_dir(sim, ln, i), i])
	# 2) 长轴 = 与"各线平均方向"垂直；泊位按 line_id 稳定排序后均匀分配
	for sid in by_station.keys():
		var list: Array = by_station[sid]
		var mean := Vector2.ZERO
		for e in list:
			mean += e[1]
		var dir: Vector2 = mean.normalized() if mean.length() > 0.001 else list[0][1]
		if dir.length() < 0.001:
			dir = Vector2.RIGHT
		var ax := Vector2(-dir.y, dir.x).normalized()
		_axis[sid] = ax
		_span[sid] = list.size()
		list.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
		var n := list.size()
		for k in range(n):
			_lane["%d:%d" % [int(list[k][0]), int(list[k][2])]] = float(k) - float(n - 1) * 0.5


## 离开第 i 站的方向（沿线走向；端点站用反向）
func _out_dir(sim: Simulation, ln: Line, i: int) -> Vector2:
	var n := ln.station_ids.size()
	if n < 2:
		return Vector2.RIGHT
	var here: Vector2 = sim.stations[ln.station_ids[i]].position
	if i < n - 1:
		var nxt: Vector2 = sim.stations[ln.station_ids[i + 1]].position
		var d := nxt - here
		if d.length() > 0.001:
			return d.normalized()
	if i > 0:
		var prv: Vector2 = sim.stations[ln.station_ids[i - 1]].position
		var d2 := here - prv
		if d2.length() > 0.001:
			return d2.normalized()
	return Vector2.RIGHT


func axis(sid: int) -> Vector2:
	return _axis.get(sid, Vector2.ZERO)


func span(sid: int) -> int:
	return int(_span.get(sid, 1))


## 该线在第 stop_idx 个站的**泊位**（世界坐标）。单线经过时就是站点中心。
func port(sim: Simulation, ln: Line, stop_idx: int, zoom: float) -> Vector2:
	if sim == null or ln == null:
		return Vector2.ZERO
	if stop_idx < 0 or stop_idx >= ln.station_ids.size():
		return Vector2.ZERO
	var sid: int = ln.station_ids[stop_idx]
	var base: Vector2 = sim.stations[sid].position
	var off: float = float(_lane.get("%d:%d" % [ln.id, stop_idx], 0.0))
	if is_zero_approx(off):
		return base
	return base + axis(sid) * off * Config.view_px(LANE_GAP_PX, zoom)


## 站点胶囊体：[中心, 半长, 半宽]（世界单位）。长轴方向取 `axis(sid)`。
## `base_half_px` 是"单线站点"的半径（像素），多线时沿长轴加长以容纳所有泊位。
func capsule(sim: Simulation, sid: int, base_half_px: float, zoom: float) -> Array:
	var extra := maxf(0.0, float(span(sid) - 1) * 0.5) * LANE_GAP_PX
	return [
		sim.stations[sid].position,
		Config.view_px(base_half_px + extra, zoom),
		Config.view_px(base_half_px, zoom),
	]


## 乘客点簇需要的最小半径：要能躲开胶囊体
func cluster_radius(sim: Simulation, sid: int, base_half_px: float, zoom: float) -> float:
	var c := capsule(sim, sid, base_half_px, zoom)
	return maxf(float(c[1]), float(c[2]))
