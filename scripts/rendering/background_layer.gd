class_name BackgroundLayer
extends ColorRect
## 全屏亮色"图纸"底。材质是 res://shaders/bg_paper.gdshader，
## 时段底色由 TimeSystem.display_bg 平滑驱动，所以昼夜变化是连续的。

var sim: Simulation = null
var camera: Camera2D = null

var _mat: ShaderMaterial = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(1, 1, 1, 1)
	_mat = material as ShaderMaterial
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(true)


func _process(_delta: float) -> void:
	if _mat == null:
		_mat = material as ShaderMaterial
		if _mat == null:
			return
	if sim == null or sim.time == null:
		return
	var base := sim.time.display_bg
	_mat.set_shader_parameter("top_color", Config.paper_top(base))
	_mat.set_shader_parameter("bottom_color", Config.paper_bottom(base))
	_mat.set_shader_parameter("grid_color", Config.ink(base, 0.55))
	if camera != null:
		_mat.set_shader_parameter("cam_offset", camera.global_position)
	# 正午最亮、深夜最沉 -> 网格与光泽强度跟着走
	var h := sim.time.get_hour()
	var mood := clampf(1.0 - absf(h - 12.0) / 13.0, 0.0, 1.0)
	_mat.set_shader_parameter("mood", mood)
	_mat.set_shader_parameter("drift", fmod(sim.elapsed * 0.02, 1.0))
