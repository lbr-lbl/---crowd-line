class_name ViewSlider
extends Control
## 视野调整滑钮（需求 ⑪⑬）。
##
## 外形是一段**竖直轨道**，轨道上有 **3 个站点**（对应三段视野锚点），
## 站点上下各多出一小段轨道 —— 表示"还能再放大/缩小一点"（相机确实允许越界回弹）；
## 轨道上那枚**列车**表示当前视野位置。平时半透明，鼠标悬浮或拖动时不透明。
##
## 值域是 0..1（0 = 最远），映射用**对数**：三段锚点本身是几何级数（各自 ×1.3），
## 只有对数映射才能让三个站点在轨道上**等距**，也才符合"缩放是乘法"的手感。

signal view_changed(t: float)

var min_zoom: float = 0.63
var max_zoom: float = 13.5
var bands: Vector3 = Vector3(0.9, 3.2, 9.0)   # overview / mid / fore

var value: float = 0.0
var _dragging: bool = false
var _hover: bool = false

const IDLE_ALPHA := 0.45
const PAD := 16.0      # 轨道两端留白：这段就是"还能再走一点"的余量


func _ready() -> void:
	custom_minimum_size = Vector2(46, 320)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())


## 由 Game 在相机锚点算好后注入
func configure(p_min: float, p_max: float, p_overview: float, p_mid: float, p_fore: float) -> void:
	min_zoom = maxf(p_min, 0.01)
	max_zoom = maxf(p_max, min_zoom * 1.01)
	bands = Vector3(p_overview, p_mid, p_fore)
	queue_redraw()


# ---- 0..1 <-> 缩放（对数） ----

func t_of_zoom(z: float) -> float:
	var lo := log(max_zoom / min_zoom)
	if lo <= 0.0001:
		return 0.0
	return clampf(log(clampf(z, min_zoom, max_zoom) / min_zoom) / lo, 0.0, 1.0)


func zoom_of_t(t: float) -> float:
	return min_zoom * pow(max_zoom / min_zoom, clampf(t, 0.0, 1.0))


## 由相机当前缩放同步滑块位置（滚轮缩放也让"列车"跟着动）
func set_from_zoom(z: float) -> void:
	var t := t_of_zoom(z)
	if absf(t - value) > 0.001:
		value = t
		queue_redraw()


func _alpha() -> float:
	return 1.0 if (_hover or _dragging) else IDLE_ALPHA


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_update_from_y(event.position.y)
		queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_update_from_y(event.position.y)
		accept_event()


func _update_from_y(y: float) -> void:
	var top := PAD
	var bottom := size.y - PAD
	value = clampf((y - top) / maxf(bottom - top, 1.0), 0.0, 1.0)
	view_changed.emit(value)
	queue_redraw()


func _draw() -> void:
	var a := _alpha()
	var ink := Color(Config.COLOR_INK.r, Config.COLOR_INK.g, Config.COLOR_INK.b, a)
	var cx := size.x * 0.5
	var top := PAD
	var bottom := size.y - PAD
	var span := bottom - top

	# 轨道（两端各多出一小段，表示还能继续放大/缩小）
	draw_line(Vector2(cx, top), Vector2(cx, bottom), Color(ink.r, ink.g, ink.b, 0.5 * a), 3.0, true)

	# 三个站点 = 三段视野锚点
	var marks := [bands.x, bands.y, bands.z]
	for i in range(3):
		var y := top + span * t_of_zoom(float(marks[i]))
		draw_circle(Vector2(cx, y), 6.0, Color(1, 1, 1, 0.92 * a))
		draw_circle(Vector2(cx, y), 6.0, ink, false, 2.0, true)

	# 当前视野：一枚小列车（横向胶囊）
	var my := top + span * clampf(value, 0.0, 1.0)
	var w := 22.0
	var h := 10.0
	var body := Color(Config.COLOR_INK.r, Config.COLOR_INK.g, Config.COLOR_INK.b, a)
	draw_rect(Rect2(cx - w * 0.5, my - h * 0.5, w, h), body)
	draw_circle(Vector2(cx - w * 0.5 + h * 0.5, my), h * 0.5, body)
	draw_circle(Vector2(cx + w * 0.5 - h * 0.5, my), h * 0.5, body)
	# 车头一点白，指示"往近景方向"
	draw_circle(Vector2(cx + w * 0.5 - h * 0.5, my), h * 0.22, Color(1, 1, 1, 0.85 * a))
