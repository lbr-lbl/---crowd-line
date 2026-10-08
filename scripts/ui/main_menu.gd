class_name MainMenu
extends Control
## 主菜单：选择"线路池"（→随机抽线网）与难度，开始游戏。

signal start_requested(network_id: String, mode: String)

var pool_option: OptionButton
var difficulty_option: OptionButton
var pool_desc_label: Label
var highscore_label: Label


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# 背景
	var bg := ColorRect.new()
	bg.color = Color("#0e0e1e")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)

	var center := VBoxContainer.new()
	center.custom_minimum_size = Vector2(460, 0)
	center.add_theme_constant_override("separation", 12)
	center.anchor_left = 0.5
	center.anchor_right = 0.5
	cc.add_child(center)

	var title := Label.new()
	title.text = "涌线 -- crowd line"
	title.add_theme_font_size_override("font_size", 42)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "涌现式地铁调度沙盒 · 你只调规则，不控制乘客"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.7, 0.8, 1.0)
	center.add_child(subtitle)

	center.add_child(_spacer(6))

	# 线路池选择
	var nl := Label.new()
	nl.text = "线路池"
	nl.add_theme_font_size_override("font_size", 14)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(nl)
	pool_option = OptionButton.new()
	pool_option.add_theme_font_size_override("font_size", 16)
	for pid in NetworkPool.list_pool_ids():
		pool_option.add_item(NetworkPool.pool_label(pid))
	center.add_child(pool_option)

	# 池描述
	pool_desc_label = Label.new()
	pool_desc_label.add_theme_font_size_override("font_size", 13)
	pool_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pool_desc_label.modulate = Color(0.7, 0.8, 1.0)
	center.add_child(pool_desc_label)

	# 难度选择
	var dl := Label.new()
	dl.text = "难度池"
	dl.add_theme_font_size_override("font_size", 14)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(dl)
	difficulty_option = OptionButton.new()
	difficulty_option.add_item("入门池 ★（5 分钟）")
	difficulty_option.add_item("进阶池 ★★（8 分钟）")
	difficulty_option.add_item("硬核池 ★★★（12 分钟）")
	difficulty_option.add_theme_font_size_override("font_size", 16)
	center.add_child(difficulty_option)
	difficulty_option.visible = false  # 池已决定难度，隐藏手动难度，避免双重选择

	center.add_child(_spacer(4))

	highscore_label = Label.new()
	highscore_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	highscore_label.add_theme_font_size_override("font_size", 14)
	highscore_label.modulate = Color(1.0, 0.9, 0.5)
	center.add_child(highscore_label)

	var start := Button.new()
	start.text = "开始运营"
	start.custom_minimum_size = Vector2(0, 48)
	start.add_theme_font_size_override("font_size", 20)
	start.pressed.connect(_on_start)
	center.add_child(start)

	var hint := Label.new()
	hint.text = "滚轮缩放 · 拖拽平移 · 点击站点/线路选择 · 点空白取消"
	hint.add_theme_font_size_override("font_size", 12)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.55, 0.6, 0.7)
	center.add_child(hint)

	pool_option.item_selected.connect(func(_i): _refresh_pool_info())
	_refresh_pool_info()


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _current_pool_id() -> String:
	var pids := NetworkPool.list_pool_ids()
	if pool_option.selected < 0 or pool_option.selected >= pids.size():
		return "entry"
	return pids[pool_option.selected]


func _refresh_pool_info() -> void:
	var pid := _current_pool_id()
	pool_desc_label.text = NetworkPool.pool_desc(pid)
	# 随机抽一条展示这个名字，让玩家知道会进哪条线
	var rand_net := NetworkPool.random_network(pid)
	highscore_label.text = "本次将从「%s」中随机进入一条线网" % NetworkPool.pool_label(pid)
	if rand_net != "":
		highscore_label.text += "\n示例线网：%s" % NetworkLoader.get_network_name(rand_net)


func _on_start() -> void:
	var pid := _current_pool_id()
	# 从池中随机抽一条真实线网
	var network_id := NetworkPool.random_network(pid)
	# 难度由池决定（等级/教学），并向下兼容手动翻倍键
	var mode := NetworkPool.pool_mode(pid)
	AppState.selected_network_id = network_id
	AppState.selected_mode = mode
	start_requested.emit(network_id, mode)
