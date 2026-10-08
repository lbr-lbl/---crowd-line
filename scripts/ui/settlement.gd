class_name Settlement
extends Control
## 结算界面：积分明细、评级、历史最佳。

signal restart_requested
signal menu_requested

var metrics: Dictionary = {}
var reason: String = ""
var network_id: String = ""

var rating_label: Label
var score_label: Label
var detail_label: Label
var best_label: Label
var new_record: bool = false


func setup(p_reason: String, p_metrics: Dictionary, p_network_id: String) -> void:
	reason = p_reason
	metrics = p_metrics
	network_id = p_network_id
	var score: float = p_metrics.get("total_score", 0.0)
	new_record = AppState.record_result(network_id, score)
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)

	var center := VBoxContainer.new()
	center.custom_minimum_size = Vector2(460, 0)
	center.add_theme_constant_override("separation", 10)
	cc.add_child(center)

	var title := Label.new()
	title.text = "运营结算"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)

	var reason_label := Label.new()
	reason_label.text = reason
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason_label.modulate = Color(0.8, 0.85, 1.0)
	center.add_child(reason_label)

	rating_label = Label.new()
	rating_label.text = "评级 %s" % metrics.get("rating", "D")
	rating_label.add_theme_font_size_override("font_size", 60)
	rating_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(rating_label)

	score_label = Label.new()
	score_label.text = "总分 %d" % int(metrics.get("total_score", 0))
	score_label.add_theme_font_size_override("font_size", 26)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(score_label)

	best_label = Label.new()
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	best_label.add_theme_font_size_override("font_size", 15)
	if new_record:
		best_label.text = "★ 新纪录！"
		best_label.modulate = Color(1.0, 0.9, 0.3)
	else:
		var best: float = AppState.high_scores.get(network_id, 0)
		best_label.text = "历史最佳 %d 分" % int(best)
		best_label.modulate = Color(0.7, 0.8, 1.0)
	center.add_child(best_label)

	detail_label = Label.new()
	detail_label.add_theme_font_size_override("font_size", 15)
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(detail_label)
	_detail_text()

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 16)
	center.add_child(btns)

	var restart := Button.new()
	restart.text = "再来一局"
	restart.custom_minimum_size = Vector2(140, 44)
	restart.pressed.connect(func(): restart_requested.emit())
	btns.add_child(restart)

	var menu := Button.new()
	menu.text = "返回菜单"
	menu.custom_minimum_size = Vector2(140, 44)
	menu.pressed.connect(func(): menu_requested.emit())
	btns.add_child(menu)


func _detail_text() -> void:
	var served: int = metrics.get("served", 0)
	var target: int = metrics.get("target_served", 0)
	detail_label.text = "准点率 %.0f%% · 满意度 %.0f%% · 吞吐 %d/%d\n安全 %.0f%% · 效率 %.0f%%" % [
		metrics.get("punctuality", 0.0) * 100,
		metrics.get("satisfaction", 0.0) * 100,
		served, target,
		metrics.get("safety", 0.0) * 100,
		metrics.get("efficiency", 0.0) * 100,
	]
