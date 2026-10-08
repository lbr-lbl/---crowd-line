class_name TutorialOverlay
extends Control
## 教程覆盖层：分步讲解玩家的操作、要完成的目标、以及会遇到的阻碍。
## 只在"教程线路池"里出现，读 sim 的实时目标/进度。

var sim: Simulation = null

var step: int = 0
var title_label: Label
var body_label: Label
var next_button: Button
var close_button: Button
var progress_label: Label

const STEPS: Array[Dictionary] = [
	{
		"title": "欢迎来到《涌线 -- crowd line》",
		"body": "你是一名地铁调度员。\n\n画面上的圆点是站点，连成的彩色线是线路，线上跑的是列车，站点周围的小点是等待的乘客。\n\n你**不直接控制**乘客，而是通过调整规则让系统顺畅运转。",
	},
	{
		"title": "① 操作：观察视角",
		"body": "· 滚轮缩放（三段视野：全貌→一段线路→单个站点）\n· 拖拽平移画面\n· 点击站点或线路选择它\n· 点空白处取消选择",
	},
	{
		"title": "② 操作：你的指挥",
		"body": "选中一个**站点**后，底部会亮起：\n\"限流\"——降低进站节奏；\"封站\"——临时关闭；\"跳站\"——列车不停。\n\n选中一条**线路**后：\"加车\"——增加列车。\n\n还有全局的\"广播\"——引导乘客改道。",
	},
	{
		"title": "③ 目标：运送乘客",
		"body": "乘客会根据最短路径找车，去往目的地。\n\n你要让列车准时、不过载、不倒灌。\n\n右上角是积分：准点率、满意度、吞吐量、安全、效率。\n\n当右上角\"吞吐量\"达标，任务达成。",
	},
	{
		"title": "④ 阻碍：突发状况",
		"body": "运营中会随机出现：\n· 暴雨——需求上升、列车变慢\n· 信号故障——某线延误\n· 出口关闭——某站容量下降\n· 设备检修——某站进站效率降低\n\n遇到时用你的操作应对，别让站点爆发恐慌（变紫）。",
	},
	{
		"title": "现在就开始吧",
		"body": "关闭教程，开始运营！\n\n记住：规则 > 操作。把规则调对了，客流自然顺畅。",
	},
]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_show_step(0)


func setup(p_sim: Simulation) -> void:
	sim = p_sim


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	cc.add_child(panel)

	var layout := VBoxContainer.new()
	layout.custom_minimum_size = Vector2(520, 0)
	layout.add_theme_constant_override("separation", 14)
	panel.add_child(layout)

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.modulate = Color(0.55, 0.9, 1.0)
	layout.add_child(title_label)

	body_label = Label.new()
	body_label.add_theme_font_size_override("font_size", 15)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.custom_minimum_size = Vector2(0, 190)
	body_label.modulate = Color(0.9, 0.93, 1.0)
	layout.add_child(body_label)

	progress_label = Label.new()
	progress_label.add_theme_font_size_override("font_size", 12)
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_label.modulate = Color(0.6, 0.65, 0.75)
	layout.add_child(progress_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	layout.add_child(btn_row)

	next_button = Button.new()
	next_button.text = "下一步 →"
	next_button.custom_minimum_size = Vector2(140, 42)
	next_button.add_theme_font_size_override("font_size", 16)
	next_button.pressed.connect(_on_next)
	btn_row.add_child(next_button)

	close_button = Button.new()
	close_button.text = "关闭教程"
	close_button.custom_minimum_size = Vector2(140, 42)
	close_button.add_theme_font_size_override("font_size", 16)
	close_button.pressed.connect(_on_close)
	btn_row.add_child(close_button)


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.16, 0.96)
	sb.border_color = Color(0.35, 0.6, 0.95, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(24)
	return sb


func _show_step(i: int) -> void:
	step = clampi(i, 0, STEPS.size() - 1)
	var s: Dictionary = STEPS[step]
	title_label.text = s["title"]
	body_label.text = s["body"]
	progress_label.text = "第 %d / %d 步" % [step + 1, STEPS.size()]
	next_button.text = "下一步 →" if step < STEPS.size() - 1 else "完成"


func _on_next() -> void:
	if step < STEPS.size() - 1:
		_show_step(step + 1)
	else:
		_on_close()


func _on_close() -> void:
	queue_free()
