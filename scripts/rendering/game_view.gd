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

## **M 视野的预选站**（由 Game 每帧从相机同步过来）：画一圈细环，
## 表示"不横移的话相机就会吸附到这个站"。
var preselect_sid: int = -1
## 显示用的载客率（逐车、平滑过）。与 `line_train_view` 同理：
## 模拟层到站是一次性卸完乘客的，不平滑就会看到车色**跳变**（用户要求"先平滑变淡"）。
var _train_load_shown: Dictionary = {}


func _on_camera_focus(_world: Vector2, station_id: int) -> void:
	_focus_sid = station_id
	_focus_t = 1.0


func _process(_delta: float) -> void:
	if sim != null:
		route_geo.rebuild_if_needed(sim)
		_update_gates(_delta)
	# 站台展开度：中景及更远 = 0（正常线网），近景 L = 1（只剩站台）
	if bands_ready:
		var z := _z()
		var u := (z - mid_zoom) / maxf(fore_zoom - mid_zoom, 0.0001)
		unfold = lerpf(unfold, clampf((u - 0.35) / 0.60, 0.0, 1.0), 1.0 - exp(-4.5 * _delta))
	if _focus_t > 0.0:
		_focus_t = maxf(0.0, _focus_t - _delta / 1.1)
	queue_redraw()


# ---- 站台闸门（L 视野）----
# 闸门开合做成"平滑趋近"而不是硬切：车一进站门滑开，出站滑上。
# 键是 "line_id:station_id"，因为闸门属于**某条线在某站的站台**。
var _gate: Dictionary = {}


func _update_gates(delta: float) -> void:
	var want: Dictionary = {}
	for ln in sim.lines:
		for sid in ln.station_ids:
			want["%d:%d" % [ln.id, sid]] = 0.0
	# 有车正停在这一站 -> 这组门要开
	for t in sim.trains:
		if t.from_idx != t.to_idx:
			continue
		var ln2: Line = sim.lines[t.line_id]
		if t.to_idx < ln2.station_ids.size():
			want["%d:%d" % [ln2.id, ln2.station_ids[t.to_idx]]] = 1.0
	for k in want.keys():
		var cur := float(_gate.get(k, 0.0))
		_gate[k] = lerpf(cur, float(want[k]), 1.0 - exp(-6.5 * delta))


func _gate_open(ln: Line, sid: int) -> float:
	return float(_gate.get("%d:%d" % [ln.id, sid], 0.0))


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

	# L 视野「站台内部」：画在**世界空间**（所以拖动/缩放天然作用于它），压在最后
	_draw_station_interior()


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
	# 站台展开度：中景及更远 = 0（只画最小符号），近景 L = 1（展开成站台 + 闸门）
	var unfold := clampf((z - mid_zoom) / maxf(fore_zoom - mid_zoom, 0.0001), 0.0, 1.0)
	# 每个站被哪些线的第几站经过：一趟扫完，别在站点循环里反复扫
	var plat: Dictionary = {}
	for ln0 in sim.lines:
		for i0 in range(ln0.station_ids.size()):
			var sid0: int = ln0.station_ids[i0]
			if not plat.has(sid0):
				plat[sid0] = []
			plat[sid0].append({"ln": ln0, "i": i0})
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
		# 预选站（M 视野吸附目标）：一圈更细更淡的环，和"已选中"区分开
		elif st.id == preselect_sid:
			var p4 := Config.view_px(11.0, z) * grow
			_capsule_outline(hl + p4, hw + p4,
				Color(Config.COLOR_INK.r, Config.COLOR_INK.g, Config.COLOR_INK.b, 0.42),
				Config.view_px(1.6, z) * grow)
		# 镜头飞到本站时的短暂脉冲（从中心向外扩散一圈并淡出）
		if st.id == _focus_sid and _focus_t > 0.0:
			var pf := Config.view_px(8.0 + (1.0 - _focus_t) * 44.0, z) * grow
			_capsule_outline(hl + pf, hw + pf,
				Color(Config.COLOR_INK.r, Config.COLOR_INK.g, Config.COLOR_INK.b, _focus_t * 0.85),
				Config.view_px(2.6, z) * grow)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 近景：把站展开成"站台 + 闸门"（见 _draw_platforms）
		if unfold > 0.02 and plat.has(st.id):
			_draw_platforms(st, plat[st.id], z, unfold, grow)


## 近景（L）下把站点展开成站台。
##
## **每条经过该站的线各有一个站台** —— 泊位偏移由 `RouteGeometry` 提供，
## 所以"多条线 = 多个站台"不需要新的几何计算，只是把原来画成一个胶囊的东西分开画。
## 站台长度按 `effective_capacity()` 缩放（扩容 -> 站台变长）。
## 闸门开合由 `_gate_open()` 驱动（车停站时从中间让开缺口）。
func _draw_platforms(st: Station, entries: Array, z: float, unfold: float, grow: float) -> void:
	# 容量 -> 站台尺寸：130 人是基准，扩容后明显变长
	var cap_k := clampf(float(st.effective_capacity()) / 130.0, 0.7, 2.4)
	var ink := Color(Config.COLOR_INK.r, Config.COLOR_INK.g, Config.COLOR_INK.b, 0.85)
	# **近景把线路"张开"成水平直线，闸机沿这条直线排布**（用户要求）。
	# 之前站台跟着该线在本站的局部走向旋转，遇到拐弯的站就会歪成交叉状，很乱。
	# 现在：站台一律水平、按线序上下叠放；每条线的轨道从站台正中**笔直穿过**。
	var n := entries.size()
	if n <= 0:
		return
	var half_len := Config.view_px(30.0 * cap_k, z) * grow * unfold
	var half_w := Config.view_px(7.0, z) * grow * unfold
	var track_over := Config.view_px(16.0, z) * grow * unfold
	var gap := half_w * 2.8
	var cx := st.position.x + half_len + Config.view_px(18.0, z) * grow
	var base_y := st.position.y - gap * (float(n) - 1.0) * 0.5
	# 从站点符号引一条细线到站台组，表示"这一站有这几个站台"
	draw_line(st.position, Vector2(cx - half_len - track_over, st.position.y), ink,
		Config.view_px(1.2, z) * grow * unfold)
	for k in range(n):
		var e: Dictionary = entries[k]
		var ln: Line = e["ln"]
		var cy := base_y + gap * float(k)
		var line_col := _tint_line(ln.color)
		# 角度恒为 0 -> 站台与闸机都在一条水平直线上
		draw_set_transform(Vector2(cx, cy), 0.0, Vector2.ONE)
		var box := Rect2(-half_len, -half_w, half_len * 2.0, half_w * 2.0)
		draw_rect(box, Color(1.0, 1.0, 1.0, 0.94))
		draw_rect(box, Color(line_col.r, line_col.g, line_col.b, 0.9), false,
			Config.view_px(1.6, z) * grow * unfold)
		# 轨道：一条笔直的线从站台正中穿过，并往两端延伸
		draw_line(Vector2(-half_len - track_over, 0.0), Vector2(half_len + track_over, 0.0),
			line_col, Config.view_px(3.0, z) * grow * unfold, true)
		# 闸机：沿这条直线排布；`open` 越高，越靠中间的闸机先让开 -> 读成"中间开门"
		var open := _gate_open(ln, st.id)
		var cnt := 7
		var lw := Config.view_px(1.5, z) * grow * unfold
		var tick := Config.view_px(5.0, z) * grow * unfold
		for g in range(cnt):
			var t := (float(g) + 0.5) / float(cnt)
			var gapf := pow(absf(t - 0.5) * 2.0, 1.4)
			if open > gapf:
				continue
			var x := lerpf(-half_len, half_len, t)
			draw_line(Vector2(x, -half_w - tick), Vector2(x, half_w + tick), ink, lw)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 车辆段棚位相对所属站点的偏移。
## **必须跟着 `grow` 一起缩放**：站点现在随缩放变大变小，如果这个偏移是固定屏幕距离，
## 全貌段站点很小、车辆段却仍在 26px 外（显得被推远了），放大时又会贴到站上 ——
## 用户反馈"车辆段和站点之间间隔也会变化"就是这个。
func _depot_mark_offset(z: float, grow: float) -> Vector2:
	return Vector2(0.0, Config.view_px(-26.0, z) * grow)


## 车辆段：未建 = 墨色虚线框（规划位置），已建 = 线路色棚位 + 段内股道
# ================= L 视野「站台内部」（世界空间）=================
#
# 关键取舍：**画在世界空间里，不是屏幕固定的 UI 覆盖层**（用户要求："站台就是实际画面，可以拖动着看"）。
# 好处是完全不用自己写交互：
#   · "拖动查看"= 相机平移（现成能力）；"放大"= 相机缩放，自然作用于站台；
#   · 站台不再是叠在画面上的一层，而是场景里真实存在的一大块东西。
#
# 站点在近景被"**捋直**"：所有站台与轨道都画成**水平直线**，不再跟随线路在地图上的转折。

## 站台展开度：0 = 正常线网，1 = 只剩站台（由相机缩放插值）
var unfold: float = 0.0

## 站台长度（世界单位）：**故意做得极长**，于是任何位置都看不到它的端点。
## 用户要求：「像站台和轨道间那两个平行的隔板是始终看不到端点的」「拖动不能离开站点，
## 至少轨道是能看见的」—— 这两条靠**把结构做长**就能满足，不需要去夹相机。
const PLAT_LEN := 6000.0
const TRACK_SPAN := 7000.0   # 轨道半长：比站台更长，任何位置都能看到轨道
# ---- 站台尺寸的标定依据 ----
# 近景锚点缩放约 9 -> 1 世界单位 ≈ 9 像素；屏幕 1280×720 -> 可见范围约 **142 × 80 世界单位**。
# 一个站要放"2 条线 × (2 轨 + 2 台)" = 4 台 4 槽，几何上**装不进 80 世界单位**。
# 所以站台视图**一次只显示一条线**（用户选定），由左上角的线色圆点切换。
# 下面这组数值的总高 = 6+20+7+5+7+20+6 ≈ 71 世界单位，留出上下余量。
const PLAT_W := 26.0         # 站台厚度（世界单位）：用户要求加宽，好让人站得开
const TRENCH_H := 7.0        # 轨道槽高度
const TRACK_GAP := 5.0       # 双向两条轨道槽之间的净空
const PLAT_EDGE_GAP := 2.0   # 站台边缘与轨道之间的净空
const GAUGE := 1.8           # 钢轨相对轨道中心的偏移（一半轨距）
const TACTILE_H := 2.4       # 盲道 / 警戒带宽度
const TRACK_DY := 6.0        # 每条轨道相对线路中心的偏移（= (槽高+净空)/2 再留一点）
## 闸机相对本站中心的偏移（世界单位）。**4 道、跨度 ±42**。
## ⚠ 上一轮我加到了 8 道 ±70、开口也大，结果**完全不挤了** —— 墙上洞太多太大，
## 人就直着走过去了。现在道数少、开口小（见下面 gap_half），人流才会形成瓶颈。
const GATE_X := [-42.0, -14.0, 14.0, 42.0]
## 归一化用的最大偏移，**必须与 GATE_X 的最大值一致**
const GATE_MAX := 42.0
## 列车长度（屏幕约 1080px @ 近景）。用户要求再加长。
const TRAIN_LEN := 120.0
## 列车出站行程：要"加速冲出整个站点"，远大于一屏可见范围
const TRAIN_REACH := 320.0


## 站台视图里**当前显示的那条线**（由左上角线色圆点切换）。-1 = 用第一条。
var interior_line: int = -1


## 当前站台视图可切换的线路（供 HUD 做线色圆点）
func interior_lines() -> Array:
	var st := _interior_station()
	return _lines_at_station(st) if st != null else []


func set_interior_line(lid: int) -> void:
	interior_line = lid


func interior_active() -> bool:
	return unfold > 0.5


## 展开哪一站：优先选中的，否则取离相机中心最近的
func _interior_station() -> Station:
	if sim == null or sim.stations.is_empty():
		return null
	if sim.selected_station_id >= 0:
		var sel: Station = sim.get_station(sim.selected_station_id)
		if sel != null:
			return sel
	var c := camera.position if camera != null else Vector2.ZERO
	var best: Station = null
	var bd := INF
	for st in sim.stations:
		var d := st.position.distance_squared_to(c)
		if d < bd:
			bd = d
			best = st
	return best


func _lines_at_station(st: Station) -> Array:
	var out: Array = []
	for ln in sim.lines:
		if st.id in ln.station_ids:
			out.append(ln)
	out.sort_custom(func(a: Line, b: Line) -> bool: return a.id < b.id)
	if out.size() > 4:
		out = out.slice(0, 4)
	return out


## 世界空间的「站台内部」：每条经过该站的线一条水平站台 + 笔直轨道 + 闸机 + 列车
func _draw_station_interior() -> void:
	if sim == null or unfold <= 0.001:
		return
	var st := _interior_station()
	if st == null:
		return
	var lines_at := _lines_at_station(st)
	if lines_at.is_empty():
		return
	# **只显示一条线**。未指定时用第一条。
	# ⚠ 原来是 `if interior_line < 0 or ln0.id == interior_line: show.append(ln0)` ——
	# `interior_line < 0` 会让**所有线都通过**，于是多线站的站台全部画在同一个 y 上，
	# 刚进站时看到的就是"两条线重叠"（用户反馈）。
	var show: Array = [lines_at[0]]
	for ln0 in lines_at:
		if ln0.id == interior_line:
			show = [ln0]
			break
	lines_at = show
	var a := unfold
	var n := lines_at.size()
	var cx := st.position.x
	var cy0 := st.position.y
	var half := PLAT_LEN * 0.5
	var ink := Color(Config.COLOR_INK.r, Config.COLOR_INK.g, Config.COLOR_INK.b)
	# **把站台"放大铺开"到远超一屏**：近景下无论看向哪里都是白的。
	# 这样不用做任何淡出/遮罩，白底自然就把地图盖住了，读起来就是"进到站点里了"。
	# 尺寸随 unfold 从 0 涨到 3200 世界单位（近景一屏约 116 世界单位宽，远小于它）。
	var floor := lerpf(0.0, 3200.0, a)
	if floor > 4.0:
		var fh := floor * 0.5
		draw_rect(Rect2(cx - fh, st.position.y - fh, floor, floor), Color(1.0, 1.0, 1.0, a))
	for k in range(n):
		var ln: Line = lines_at[k]
		# 一次只画一条线 -> 以站点为垂直中心（多线时的堆叠间距已不需要）
		var cy := cy0
		var col := _tint_line(ln.color)
		# ⚠ 世界空间里的**线宽必须走 `Config.view_px()`（即除以缩放）**，否则近景下全是粗条：
		# 这里写 2.6 世界单位，在 11 倍缩放下就是 29 像素 —— 站台会被自己的边框盖住，
		# 看起来像"两条黑带"而不是站台（实测就是这样）。
		# 规则：**位置/尺寸用世界单位**（要跟着缩放变大变小），**线宽用 view_px**（要恒定细）。
		var zz := _z()
		var half_len := PLAT_LEN * 0.5
		var edge := Color(ink.r, ink.g, ink.b, 0.85 * a)
		# **同一条线双向两条轨道**，且**各自单侧开门**（用户要求）：
		# 上轨的站台在轨道上方、下轨的站台在轨道下方 —— 门只朝自己那一侧开，和真实车站一样。
		var cy_up := cy - TRACK_DY
		var cy_dn := cy + TRACK_DY
		# **轨道槽 + 钢轨**：槽比站台暗一档，两条细亮线是钢轨。
		# 这是"这是轨道"最认得出的特征（原来只画一条线路色的粗线，读不出是轨道）。
		for tc in [cy_up, cy_dn]:
			draw_rect(Rect2(cx - half_len, tc - TRENCH_H * 0.5, PLAT_LEN, TRENCH_H),
				Color(0.30, 0.31, 0.34, 0.80 * a))
			for g in [-GAUGE, GAUGE]:
				draw_line(Vector2(cx - TRACK_SPAN, tc + g), Vector2(cx + TRACK_SPAN, tc + g),
					Color(0.80, 0.82, 0.86, 0.95 * a), Config.view_px(1.6, zz), true)
		# 单侧站台：上轨的在上方、下轨的在下方。
		# **中灰水泥色**是关键 —— 原来 0.905 几乎等于白，和底分不开，所以"站台读不出来"。
		# 单侧站台：上轨的在上方、下轨的在下方。
		# 站台底边要**让开轨道槽**（否则和槽重叠），所以用槽半高 + 净空来算。
		var y_up := cy_up - TRENCH_H * 0.5 - PLAT_EDGE_GAP - PLAT_W
		var y_dn := cy_dn + TRENCH_H * 0.5 + PLAT_EDGE_GAP
		for e in [[y_up, y_up + PLAT_W, true], [y_dn, y_dn + PLAT_W, false]]:
			var py0: float = e[0]
			var py1: float = e[1]
			var is_up: bool = bool(e[2])
			draw_rect(Rect2(cx - half_len, py0, PLAT_LEN, py1 - py0),
				Color(0.72, 0.74, 0.775, 0.98 * a))
			# 站台外侧沿（背向轨道那侧）：深一点，站台有"厚度"
			var outer_y: float = py0 if is_up else py1
			draw_line(Vector2(cx - half_len, outer_y), Vector2(cx + half_len, outer_y),
				Color(0.42, 0.44, 0.48, 0.9 * a), Config.view_px(2.2, zz))
			# **轨道与站台之间用黑线隔开**，而**闸机就是这条黑线上的开口**（用户要求）：
			#   关着 = 线连续（一道墙）；开着 = 线断开（缺口）。
			# 缺口宽度随开度**平滑变化**，所以"开合"直接读成这条线的开口闭合，
			# 不再画门框/门扇那套家具 —— 家具会和站台沿混在一起，反而不如一道断口清楚。
			# 关着时也留一道 0.5 世界单位的小缝，作为"闸机装在这里"的位置提示。
			var open_y: float = py1 if is_up else py0
			var black := Color(0.05, 0.05, 0.06, 0.96 * a)
			var side_i: int = 0 if is_up else 1
			var open_amt: float = gate_open_side(ln, st, side_i)
			var x_cursor := cx - half_len
			var cuts: Array = GATE_X.duplicate()
			cuts.sort()
			for t in cuts:
				var near := 1.0 - absf(float(t)) / GATE_MAX
				var thr := 0.55 - near * 0.35
				var vis := clampf(1.0 - (open_amt - thr) / 0.30, 0.0, 1.0)
				# 开口要**小**：全开时半宽只有 3.2 世界单位（洞宽 6.4），
				# 而一个人的碰撞直径约 3.8 世界单位 —— 一次只能过一个多，
				# 于是人流被卡在洞口，才会"挤"（用户反馈：开口大了完全不挤）。
				var gap_half: float = 0.4 + 2.8 * (1.0 - vis)
				var cut_a: float = cx + float(t) - gap_half
				var cut_b: float = cx + float(t) + gap_half
				if cut_a > x_cursor:
					draw_line(Vector2(x_cursor, open_y), Vector2(cut_a, open_y), black,
						Config.view_px(3.0, zz))
				x_cursor = maxf(x_cursor, cut_b)
			if x_cursor < cx + half_len:
				draw_line(Vector2(x_cursor, open_y), Vector2(cx + half_len, open_y), black,
					Config.view_px(3.0, zz))
			# **盲道 / 警戒带**：往里让开一点，别和上面那条黑线叠在一起
			var tac_y: float = open_y - (TACTILE_H * 0.5 + 1.4) if is_up \
				else open_y + (TACTILE_H * 0.5 + 1.4)
			draw_rect(Rect2(cx - half_len, tac_y - TACTILE_H * 0.5, PLAT_LEN, TACTILE_H),
				Color(0.93, 0.72, 0.22, 0.95 * a))
		# 闸机不再单独画：**它就是上面那条黑线上的开口**（见站台绘制处）。
		_draw_interior_trains(ln, st, cx, cy_up, cy_dn, a, col)


## 站台里的列车：**进站 → 停站 → 出站加速淡出消失**。
## 用有符号的**段数偏移** `rel`（0 = 正好在本站，±1 = 前后一站）：
## 位置用缓动压向两端（离开本站时越走越快 -> "加速出站"），透明度随 |rel| 衰减 -> 到边缘消失。
func _draw_interior_trains(ln: Line, st: Station, cx: float, cy_up: float, cy_dn: float, a: float, col: Color) -> void:
	var si := ln.station_ids.find(st.id)
	if si < 0 or ln.station_ids.size() < 2:
		return
	var cum := _line_cum_len(ln)
	var i0: int = clampi(si, 0, cum.size() - 2)
	var seg := maxf(float(cum[i0 + 1]) - float(cum[i0]), 1.0)
	var d_here := float(cum[clampi(si, 0, cum.size() - 1)])
	var ink := Color(Config.COLOR_INK.r, Config.COLOR_INK.g, Config.COLOR_INK.b)
	for t in sim.trains:
		if t.line_id != ln.id:
			continue
		var fi: int = clampi(t.from_idx, 0, cum.size() - 1)
		var d := float(cum[fi])
		var moving := t.from_idx != t.to_idx
		if moving and t.to_idx >= 0 and t.to_idx < cum.size():
			d = lerpf(d, float(cum[t.to_idx]), clampf(t.progress, 0.0, 1.0))
		var rel := (d - d_here) / seg
		# **只画"正在本站"的列车**（用户反馈：有些站的车不是加速出站，而是在本站轨道上开开停停）。
		# 根因：这里原来把**整条线的所有列车**都按"到本站的弧长"映射到本站轨道上，
		# 于是停在邻站的车、被堵在半路的车都被画了出来，看起来就是走走停停。
		# 判据：停站中 -> 必须就停在本站；行驶中 -> 必须在本站相邻的那一段里。
		if not moving:
			if absf(d - d_here) > 1.0:
				continue
		elif t.from_idx != si and t.to_idx != si:
			continue
		var away := clampf(absf(rel), 0.0, 1.0)
		if away >= 1.0:
			continue
		# **不淡出，直接加速冲出整个站点**（用户要求）。
		# 指数 > 1：开始时几乎不动，越到后面越快 -> 读成"起步后加速出站"。
		# 行程 `TRAIN_REACH = 700` 远大于屏幕可见范围（近景一屏约 116 世界单位），
		# 所以列车是真的跑出整个站点，而不是在站台中间消失。
		var x := cx + signf(rel) * pow(away, 1.75) * TRAIN_REACH
		var al := a
		var tw := TRAIN_LEN
		# 车身做**细**：高度跟着**轨道槽**（7 世界单位），不再比槽高一截 ——
		# 原来 11 高会把站台沿上的**闸机整条盖住**（用户反馈）。
		var th := 7.0
		# 双向各走自己的轨道（上轨往索引减小方向、下轨往增大方向）
		var cy: float = cy_dn if t.direction > 0 else cy_up
		# **载客率 = 车身内部的不透明度**（用户选定：不要"液体"）。
		# 空车几乎透明（只剩外壳），越挤内部越实。
		var zw := Config.view_px(2.2, _z())
		var half_l := tw * 0.5 - th * 0.5
		var raw_load := clampf(float(t.passengers.size()) / maxf(1.0, float(t.capacity)), 0.0, 1.0)
		var shown_load: float = float(_train_load_shown.get(t.id, raw_load))
		var lrate: float = 8.0 if raw_load > shown_load else 3.0
		shown_load = lerpf(shown_load, raw_load, 1.0 - exp(-lrate * get_process_delta_time()))
		_train_load_shown[t.id] = shown_load
		var load := shown_load
		var inner_a: float = lerpf(0.14, 1.0, load)
		draw_set_transform(Vector2(x, cy), 0.0, Vector2.ONE)
		_capsule_fill(half_l, th * 0.5, Color(col.r, col.g, col.b, inner_a * al))
		# 描边：只比线路深一点、别太粗（用户反馈 H/M 下过深过粗）
		var oc := Color(
			lerpf(col.r, ink.r, 0.25), lerpf(col.g, ink.g, 0.25), lerpf(col.b, ink.b, 0.25), 0.95 * al)
		_capsule_outline(half_l, th * 0.5, oc, zw)
		# 车里的人：白色小点，按载客率决定亮度（挤的时候看得见人）
		var n_pax: int = t.passengers.size()
		var dot_r: float = th * 0.15
		for ci in range(mini(n_pax, 24)):
			var ccx: float = x - tw * 0.5 + th * 0.75 + float(ci % 6) * (tw - th * 1.5) / 6.0
			var ccy: float = cy - th * 0.18 + float(ci / 6) * th * 0.36
			draw_circle(Vector2(ccx, ccy), dot_r, Color(1.0, 1.0, 1.0, 0.40 * load * al))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if not moving:
			draw_arc(Vector2(x, cy), th * 0.9, 0.0, TAU, 28, Color(ink.r, ink.g, ink.b, 0.45 * al), zw, true)


## 某一侧闸机的开度。**只有停站列车所在那一侧才开**。
##
## ⚠ 原来两侧共用同一个 `_gate_open()`，于是"上面的车到站、下侧闸机也开、下侧乘客也上"
## （用户反馈）。方向与站台的对应关系必须和列车的轨道分配一致：
##   `direction > 0`（往索引增大方向）走**下轨** -> 用下站台；
##   `direction < 0` 走**上轨** -> 用上站台。
func gate_open_side(ln: Line, st: Station, side: int) -> float:
	var si := ln.station_ids.find(st.id)
	if si < 0:
		return 0.0
	for tr in sim.trains:
		if tr.line_id != ln.id or tr.from_idx != tr.to_idx or tr.from_idx != si:
			continue
		if (tr.direction > 0 and side == 1) or (tr.direction <= 0 and side == 0):
			return _gate_open(ln, st.id)
	return 0.0


## 某道闸机当前**能不能过人**（给渲染层做"挤着过闸机"用）。
##
## 语义：站台沿是一道墙，**只有开着的闸机**能过人。车停站时中间的先开，
## 所以乘客会朝开着的闸机收拢、从那里挤过去 —— 这样闸机才"有作用"。
## `side`：0 = 上站台（上轨那侧），1 = 下站台。
func gate_passable(ln: Line, st: Station, t: float, side: int) -> bool:
	var near := 1.0 - absf(t) / GATE_MAX
	var thr := 1.0 - near * 0.85
	var vis := clampf(1.0 - (gate_open_side(ln, st, side) - thr) / 0.30, 0.0, 1.0)
	return vis < 0.5


## 线路的累计弧长（沿真实站点位置量）
func _line_cum_len(ln: Line) -> Array:
	var out: Array = [0.0]
	for i in range(1, ln.station_ids.size()):
		var a: Vector2 = sim.stations[ln.station_ids[i - 1]].position
		var b: Vector2 = sim.stations[ln.station_ids[i]].position
		out.append(float(out[i - 1]) + a.distance_to(b))
	return out


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
