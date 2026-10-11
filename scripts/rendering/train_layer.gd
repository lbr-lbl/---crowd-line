class_name TrainLayer
extends Node2D
## 列车渲染层：每条线一个子节点 LineTrainView（各自持有该线颜色的车身材质），
## 线是动态增删的（无限模式每波加线），所以这里负责同步子节点。

var sim: Simulation = null

## 三段视野锚点（Game 注入），会下发给每个 LineTrainView：远景据此把车身拉长
var zoom_bands: Vector3 = Vector3(0.9, 3.2, 9.0)

## 共享轨道几何（Game 注入，实际是 GameView 持有的那一份）：
## 列车靠它走"自己那条线的泊位"，在换乘站才不会偏到别的线轨道上
var route_geo: RouteGeometry = null

var _views: Dictionary = {}  # line_id -> LineTrainView


func _process(_delta: float) -> void:
	if sim == null:
		return
	_sync_views()


func _sync_views() -> void:
	for ln in sim.lines:
		if not _views.has(ln.id):
			_views[ln.id] = _make_view(ln)
	var stale: Array = []
	for lid in _views.keys():
		var alive := false
		for ln in sim.lines:
			if ln.id == lid:
				alive = true
				break
		if not alive:
			stale.append(lid)
	for lid in stale:
		var v: Node = _views[lid]
		v.queue_free()
		_views.erase(lid)


func _make_view(ln: Line) -> LineTrainView:
	var v := LineTrainView.new()
	v.name = "LineTrains_%d" % ln.id
	v.sim = sim
	v.line = ln
	# 用 **JSON 里的线色**作基色（不是调色板按序号取），这样车和它那条线必然同色
	v.body_color = ln.color
	v.zoom_bands = zoom_bands
	v.route_geo = route_geo
	add_child(v)
	return v


## 由 Game 在相机三段锚点算好后注入：LineTrainView 用它判断"是不是远景"，
## 远景把车身拉长一点才认得出来。
## （车身材质早已改成程序化胶囊，`assets/icons/train_body.png` 现在没有代码引用了。）
func set_zoom_bands(overview: float, mid: float, fore: float) -> void:
	zoom_bands = Vector3(overview, mid, fore)
	for lid in _views:
		var v: LineTrainView = _views[lid]
		if v != null:
			v.zoom_bands = zoom_bands


## 供相机"跟车"查询：某列车当前的世界坐标（车不存在时返回 null）。
## 位置由各 LineTrainView 在 `_draw` 里记下（它本来就每帧算一遍）。
func train_world_pos(train_id: int) -> Variant:
	for lid in _views:
		var v: LineTrainView = _views[lid]
		if v != null and v.world_pos.has(train_id):
			return v.world_pos[train_id]
	return null
