class_name PassengerLayer
extends Node2D
## 站台上的乘客小点。点走 shaders/passenger_dot.gdshader（呼吸 + 涟漪），
## 相位由点在世界里的位置推出，所以不会整齐划一地闪。
## 全貌段（云段）不画点：那一段由 GameView 画成分云。

const GOLDEN_ANGLE := 2.39996323
const DOT_TEXTURE := "res://assets/icons/passenger_dot.png"
const DOT_SHADER := "res://shaders/passenger_dot.gdshader"

var sim: Simulation = null
var camera: Camera2D = null
var game_view: GameView = null

## 贴图可以在场景里指定；为空时按 DOT_TEXTURE 兜底加载。
@export var dot_texture: Texture2D = null

var _cloud_zoom_lo := 0.6
var _cloud_zoom_hi := 0.95


func _ready() -> void:
	# 动效的关键：着色器必须挂在 CanvasItem 上。`_draw()` 里单次 `draw_*` 是没法
	# 各自带材质的，但**整个层的材质会作用于这一层的每一次绘制**——所以每个点的
	# UV（贴图内归一化坐标）、COLOR（modulate）、VERTEX（点在世界里的位置）依然各自独立，
	# 涟漪相位由 VERTEX 推出，同屏的点不会齐刷刷一起闪。
	if ResourceLoader.exists(DOT_SHADER):
		var mat := ShaderMaterial.new()
		mat.shader = load(DOT_SHADER)
		material = mat
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null or sim.time == null:
		return
	var zoom := camera.zoom.x if camera != null else 1.0
	var cloud := _cloud_blend(zoom)
	var alpha := 1.0 - cloud
	if alpha <= 0.01:
		return
	var tex := _texture()
	if tex == null:
		return

	var detail := _detail(zoom)
	# 尺寸补偿的两条不同规则（对应"放大 = 把东西拉开，而不是画大"）：
	#   · 符号本身（点的大小）和"贴住站环"的基准偏移 → `view_px`，屏幕上恒定大小
	#   · 人群的散布半径 → `view_spread`（√zoom），屏幕上缓慢拉开：
	#     放大能看清一个个乘客，但人还围着本站，不会撒得满屏都是、看不出谁在哪等车
	var z := maxf(zoom, 0.001)
	# 站的尺寸要与 GameView._draw_stations 一致，点才落在站里
	for st in sim.stations:
		if st.queue.is_empty():
			continue
		var base_half := clampf(6.0 + st.effective_capacity() / 40.0, 7.0, 16.0)
		var base_r := Config.view_px(base_half, z)
		if game_view != null:
			# 站点可能是**长条胶囊体**（多线共用的站），点簇要躲开它，
			# 半径必须用同一份轨道几何算，否则点会糊在胶囊上
			base_r = game_view.route_geo.cluster_radius(sim, st.id, base_half, z)
		var spread := Config.view_spread(lerpf(3.0, 4.2, detail), z)
		var max_r := Config.view_spread(
			lerpf(34.0, 46.0, detail) + clampf(st.overflow_ratio(), 0.0, 2.0) * 14.0, z)
		var dot_r := Config.view_px(lerpf(3.0, 3.6, detail), z)
		var i := 0
		for p in st.queue:
			if p.state != Passenger.State.WAITING:
				i += 1
				continue
			var ang := float(i) * GOLDEN_ANGLE
			var off := Vector2(cos(ang), sin(ang)) * minf(
				base_r + Config.view_px(8.0, z) + sqrt(float(i)) * spread, max_r)
			var col := _dot_color(p, st)
			col.a = alpha
			var side := dot_r * 2.3
			draw_texture_rect(tex, Rect2(st.position + off - Vector2(side, side) * 0.5, Vector2(side, side)), false, col)
			i += 1


func _texture() -> Texture2D:
	if dot_texture != null:
		return dot_texture
	if ResourceLoader.exists(DOT_TEXTURE):
		dot_texture = load(DOT_TEXTURE)
	return dot_texture


func _cloud_blend(zoom: float) -> float:
	if game_view != null:
		return game_view.cloud_blend_for(zoom)
	if zoom <= _cloud_zoom_lo:
		return 1.0
	if zoom >= _cloud_zoom_hi:
		return 0.0
	return clampf(1.0 - (zoom - _cloud_zoom_lo) / maxf(_cloud_zoom_hi - _cloud_zoom_lo, 0.0001), 0.0, 1.0)


func _detail(zoom: float) -> float:
	if game_view == null:
		return 0.0
	return clampf((zoom - game_view.mid_zoom) / maxf(game_view.fore_zoom - game_view.mid_zoom, 0.0001), 0.0, 1.0)


## 乘客点是画面主体，要"饱和可辨"。
## 注意 `Config.ink(c, amount)` 的 amount 是**往墨色 #182236 里兑多少**（不是透明度）：
## 云用 0.18~0.30 是想要淡雅，但点用同样档位会把黄兑成橄榄、绿兑成灰绿，看着发脏。
## 这里只兑一点点去刺眼，层次交给 shader 的软芯/涟漪和下面的 alpha。
func _dot_color(p: Passenger, st: Station) -> Color:
	if st.panic > 0.5:
		return Config.ink(Config.COLOR_PANIC, 0.08)
	if p.patience < 0.3:
		return Config.ink(Config.COLOR_CROWDED, 0.08)
	if p.patience < 0.6:
		return Config.ink(Config.COLOR_WAITING, 0.08)
	return Config.ink(Config.COLOR_NORMAL, 0.08)
