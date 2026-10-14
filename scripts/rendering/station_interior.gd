class_name StationInterior
extends CanvasLayer
## L 视野的「站台内部」视图。
##
## 需求原文：「站点展开为全屏那样嘛，就像进到了站台里，然后线路把它捋直像站台里那样子」
##
## 设计要点（每条都对应一次用户反馈）：
##   · 挂在 CanvasLayer 上 -> **屏幕固定**，不随相机平移缩放，读起来才是"进到站里了"；
##   · 再从该站的屏幕坐标**缩放推进**（1.5x -> 1.0x）而不是单纯淡入，才有"走进去"的感觉；
##   · 每条经过该站的线画成一条**水平直线轨道**（线路被"捋直"），按 line.id 从上到下堆叠；
##   · 站台 + 闸机沿直线排布；闸机**每侧两个、且平行于线路**（短横线）；
##   · **列车按"沿线路的累计弧长"映射到直线上**（详见 `_train_screen_x()` 的注释）；
##   · 只在近景 L 淡入 -> 对地图视图零影响。
##
## 展开哪一站：优先**选中的站点**；没选中就取离相机中心最近的那一站。

## 内层画板：`_draw` 不能写在 CanvasLayer 上，所以用一个 Control 转调
class Board extends Control:
	var fx: StationInterior = null

	func _draw() -> void:
		if fx != null:
			fx.draw_board(self)


const FADE_LO := 0.30       # 展开度到这个值开始淡入（给足过渡带 -> 更平滑）
const FADE_HI := 0.95
const FADE_RATE := 4.2      # 淡入淡出速度（比原来慢，避免"啪"地跳出来）
const TRACKS_MAX := 4

var sim: Simulation = null
var camera: Camera2D = null
var zoom_bands: Vector3 = Vector3(0.9, 3.2, 9.0)

var _board: Board = null
var _alpha: float = 0.0
var _gate: Dictionary = {}       # "line:station" -> 0..1
var _train_x: Dictionary = {}    # train_id -> 平滑后的屏幕 x


func _ready() -> void:
	layer = 6                  # 世界(0/1)之上、HUD(10)之下、氛围层(5)之上
	process_mode = Node.PROCESS_MODE_ALWAYS
	_board = Board.new()
	_board.fx = self
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_board)
	visible = false


func is_active() -> bool:
	return _alpha > 0.5


func _process(delta: float) -> void:
	if sim == null or camera == null or _board == null:
		return
	var z := camera.zoom.x
	var u := clampf((z - zoom_bands.y) / maxf(zoom_bands.z - zoom_bands.y, 0.0001), 0.0, 1.0)
	var want := clampf((u - FADE_LO) / maxf(FADE_HI - FADE_LO, 0.0001), 0.0, 1.0)
	_alpha = lerpf(_alpha, want, 1.0 - exp(-FADE_RATE * delta))
	visible = _alpha > 0.01
	if visible:
		_update_gates(delta)
		# "走进去"的推进感：缩放**画板本身**（绕该站的屏幕坐标），而不是在 _draw 里
		# 用 `draw_set_transform(pos, ...)` —— 那个 API 会把**绘制原点一起搬走**，
		# 结果整块内容被推到右下角（第一版就是这么错的）。
		# 改 Control 的 pivot_offset/scale，绘制坐标完全不用动。
		var st0 := focus_station()
		if st0 != null and camera != null:
			_board.pivot_offset = camera.get_canvas_transform() * st0.position
		var s := lerpf(1.55, 1.0, _ease(_alpha))
		_board.scale = Vector2(s, s)
		_board.queue_redraw()


func focus_station() -> Station:
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


func _update_gates(delta: float) -> void:
	var want: Dictionary = {}
	for ln in sim.lines:
		for sid in ln.station_ids:
			want["%d:%d" % [ln.id, sid]] = 0.0
	for t in sim.trains:
		if t.from_idx != t.to_idx:
			continue
		var ln2: Line = sim.lines[t.line_id]
		if t.to_idx < ln2.station_ids.size():
			want["%d:%d" % [ln2.id, ln2.station_ids[t.to_idx]]] = 1.0
	for k in want.keys():
		_gate[k] = lerpf(float(_gate.get(k, 0.0)), float(want[k]), 1.0 - exp(-6.5 * delta))


func _gate_open(ln: Line, sid: int) -> float:
	return float(_gate.get("%d:%d" % [ln.id, sid], 0.0))


func _lines_at(st: Station) -> Array:
	var out: Array = []
	for ln in sim.lines:
		if st.id in ln.station_ids:
			out.append(ln)
	out.sort_custom(func(a: Line, b: Line) -> bool: return a.id < b.id)
	if out.size() > TRACKS_MAX:
		out = out.slice(0, TRACKS_MAX)
	return out


## 线路的累计弧长（沿真实站点位置量），用于把列车映射到直线上。
## `out[i]` = 从首站到第 i 站的路径长度。
func _cum_len(ln: Line) -> Array:
	var out: Array = [0.0]
	for i in range(1, ln.station_ids.size()):
		var a: Vector2 = sim.stations[ln.station_ids[i - 1]].position
		var b: Vector2 = sim.stations[ln.station_ids[i]].position
		out.append(float(out[i - 1]) + a.distance_to(b))
	return out


static func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 2.2)


func draw_board(b: Control) -> void:
	var st := focus_station()
	if st == null:
		return
	var w := b.size.x
	var h := b.size.y
	var a := _alpha
	var ink := Color(Config.COLOR_INK.r, Config.COLOR_INK.g, Config.COLOR_INK.b, a)
	var lines_at := _lines_at(st)
	if lines_at.is_empty():
		return

	# 磨砂底：把地图压到后面（缩放推进由 _process 改画板的 scale 完成，这里不碰变换）
	b.draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Color(0.965, 0.972, 0.985, 0.955 * a))

	var font := ThemeDB.fallback_font
	# 站名写在 HUD 顶栏下方，避免和时钟/暂停键撞在一起（用户反馈"UI 错乱"）
	var title := "%s　等车 %d / 容量 %d" % [st.name, st.queue_size(), st.effective_capacity()]
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	b.draw_string(font, Vector2((w - tw) * 0.5, h * 0.17), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)

	var n := lines_at.size()
	var left := w * 0.10
	var right := w * 0.90
	var span := right - left
	var top := h * 0.30
	var bottom := h * 0.82
	var step := (bottom - top) / maxf(float(n), 1.0)

	for k in range(n):
		var ln: Line = lines_at[k]
		var cy := top + step * (float(k) + 0.5)
		var col := Config.line_draw_color(ln.color, _vibrancy())
		var half_w := 18.0 * a

		# 轨道：贯穿整屏的直线（"线路被捋直"）
		b.draw_line(Vector2(0.0, cy), Vector2(w, cy), col, 5.0 * a, true)
		# 站台：白底 + 线路色描边
		var box := Rect2(left, cy - half_w, span, half_w * 2.0)
		b.draw_rect(box, Color(1.0, 1.0, 1.0, 0.96 * a))
		b.draw_rect(box, Color(col.r, col.g, col.b, 0.9 * a), false, 2.0 * a)
		# 本站中心标记
		b.draw_line(Vector2(w * 0.5, cy - half_w - 12.0), Vector2(w * 0.5, cy + half_w + 12.0),
			Color(ink.r, ink.g, ink.b, 0.45 * a), 2.0 * a)

		# 闸机：**每侧两个**（左 0.30/0.40、右 0.60/0.70），而且是**平行于线路的短横线**
		# （之前画成垂直于线路的竖线，读起来像栅栏）。`open` 越高，靠中间的先让开。
		var open := _gate_open(ln, st.id)
		var gpos := [0.30, 0.40, 0.60, 0.70]
		var gl := span * 0.06
		for t in gpos:
			var near := absf(t - 0.5) * 2.0          # 0 = 正中，1 = 最外
			if open > 1.0 - near * 0.85:
				continue
			var x: float = lerpf(left, right, t)
			var gcol := Color(ink.r, ink.g, ink.b, 0.8 * a)
			b.draw_line(Vector2(x - gl * 0.5, cy - half_w), Vector2(x + gl * 0.5, cy - half_w), gcol, 3.0 * a)
			b.draw_line(Vector2(x - gl * 0.5, cy + half_w), Vector2(x + gl * 0.5, cy + half_w), gcol, 3.0 * a)

		_draw_trains(b, ln, cy, a, col, w, left, span)

	# 底部提示
	var hint := "近景站台视图　缩回中景可回到线网"
	var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	b.draw_string(font, Vector2((w - hw) * 0.5, h - 24.0), hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(ink.r, ink.g, ink.b, 0.55 * a))


## 本站相邻那一段的长度（用于把"距本站多远"折算成"几段"）
func _seg_len(ln: Line, si: int) -> float:
	var cum := _cum_len(ln)
	if cum.size() < 2:
		return 1.0
	var i: int = clampi(si, 0, cum.size() - 2)
	return maxf(float(cum[i + 1]) - float(cum[i]), 1.0)


## 站台里只画「正在本站」的列车：**进站 → 停站 → 出站加速淡出消失**。
##
## 第一版画"本站附近一个窗口内的所有车"，于是车出站以后还在站台上慢慢滑 ——
## 用户反馈："列车出站了就让它加速消失呗，为什么还要在站内显示。"
##
## 现在改成用**有符号的段数偏移** `rel`（0 = 正好在本站，±1 = 前后一站）：
##   · 位置用缓动压向站台两端（`pow(|rel|, 0.62)`）-> 离开本站时越走越快，读成"加速出站"；
##   · 透明度随 `|rel|` 快速衰减 -> 到站台边缘就彻底消失；
##   · 掉头（终点站）时 rel 从 0 往另一侧走，同样是"开走并消失"，不会穿屏。
func _draw_trains(b: Control, ln: Line, cy: float, a: float, col: Color, w: float, left: float, span: float) -> void:
	var cum := _cum_len(ln)
	var si := ln.station_ids.find(focus_station().id)
	if si < 0 or cum.is_empty():
		return
	var seg := _seg_len(ln, si)
	var d_here := float(cum[clampi(si, 0, cum.size() - 1)])
	var cx := left + span * 0.5
	var frame := get_process_delta_time()
	for t in sim.trains:
		if t.line_id != ln.id:
			continue
		var fi: int = clampi(t.from_idx, 0, cum.size() - 1)
		var d := float(cum[fi])
		var moving := t.from_idx != t.to_idx
		if moving and t.to_idx >= 0 and t.to_idx < cum.size():
			d = lerpf(d, float(cum[t.to_idx]), clampf(t.progress, 0.0, 1.0))
		var rel := (d - d_here) / seg
		var away := clampf(absf(rel), 0.0, 1.0)
		if away >= 1.0:
			_train_x.erase(t.id)
			continue
		var target := cx + signf(rel) * pow(away, 0.62) * span * 0.5
		var shown := float(_train_x.get(t.id, target))
		shown = lerpf(shown, target, 1.0 - exp(-16.0 * maxf(frame, 0.0001)))
		_train_x[t.id] = shown
		var fade := 1.0 - pow(away, 1.4)
		if fade <= 0.03:
			continue
		var al := a * fade
		var tw := span * 0.18
		var th := 20.0 * al
		b.draw_rect(Rect2(shown - tw * 0.5, cy - th * 0.5, tw, th), Color(col.r, col.g, col.b, 0.95 * al))
		b.draw_rect(Rect2(shown - tw * 0.5, cy - th * 0.5, tw, th),
			Color(Config.COLOR_INK.r, Config.COLOR_INK.g, Config.COLOR_INK.b, 0.8 * al), false, 2.0 * al)
		# 停站：一圈环表示门开着
		if not moving:
			b.draw_arc(Vector2(shown, cy), th * 0.85, 0.0, TAU, 24,
				Color(Config.COLOR_INK.r, Config.COLOR_INK.g, Config.COLOR_INK.b, 0.45 * al), 2.0 * al, true)


func _vibrancy() -> float:
	return Config.vibrancy_for_period(sim.time.get_period()) if sim != null and sim.time != null else 1.0
