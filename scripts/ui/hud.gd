class_name HUD
extends CanvasLayer
## 游戏内 HUD：时间、天气、时段、资源、积分指标、操作按钮、提示。

var sim: Simulation
var game: Node = null

var time_label: Label
var period_label: Label
var weather_label: Label
var resource_label: Label
var time_bar: ProgressBar

var metric_labels: Dictionary = {}
var band_label: Label = null

var sel_panel: PanelContainer
var sel_label: Label
var op_panel: HBoxContainer
var op_buttons: Dictionary = {}

var toast_label: Label
var toast_tween: Tween


func setup(p_sim: Simulation, p_game: Node) -> void:
	sim = p_sim
	game = p_game
	_build_ui()
	_connect()


func _build_ui() -> void:
	layer = 10
	const VW := 1280.0
	const VH := 720.0

	# 顶部时间面板（左上）
	var top := PanelContainer.new()
	top.position = Vector2(12, 12)
	top.size = Vector2(252, 140)
	top.name = "TopPanel"
	add_child(top)
	var tb := VBoxContainer.new()
	tb.add_theme_constant_override("separation", 2)
	top.add_child(tb)

	time_label = _make_label("", 30)
	tb.add_child(time_label)
	period_label = _make_label("", 15)
	period_label.modulate = Color(0.8, 0.85, 1.0)
	tb.add_child(period_label)
	weather_label = _make_label("", 15)
	weather_label.modulate = Color(0.8, 0.9, 1.0)
	tb.add_child(weather_label)
	resource_label = _make_label("", 15)
	resource_label.modulate = Color(1.0, 0.9, 0.5)
	tb.add_child(resource_label)

	time_bar = ProgressBar.new()
	time_bar.custom_minimum_size = Vector2(0, 8)
	time_bar.max_value = 1.0
	time_bar.show_percentage = false
	tb.add_child(time_bar)

	# 当前视野段指示（H 全貌 / M 中景 / L 近景），对应效果图右侧那一栏
	band_label = _make_label("", 14)
	band_label.position = Vector2(16, 160)
	band_label.size = Vector2(260, 22)
	band_label.modulate = Color(0.62, 0.78, 1.0, 0.9)
	add_child(band_label)

	# 积分面板（右上）
	var right := PanelContainer.new()
	right.position = Vector2(VW - 250, 12)
	right.size = Vector2(238, 170)
	add_child(right)
	var rb := VBoxContainer.new()
	rb.add_theme_constant_override("separation", 1)
	right.add_child(rb)
	var title := _make_label("运营指标", 16)
	title.modulate = Color(0.7, 0.8, 1.0)
	rb.add_child(title)
	for key in ["punctuality", "satisfaction", "throughput", "safety", "efficiency"]:
		var l := _make_label("", 13)
		rb.add_child(l)
		metric_labels[key] = l

	# 底部操作面板
	var bottom := PanelContainer.new()
	bottom.position = Vector2((VW - 760.0) / 2.0, VH - 84)
	bottom.size = Vector2(760, 72)
	add_child(bottom)
	var bb := VBoxContainer.new()
	bottom.add_child(bb)
	sel_label = _make_label("未选择", 14)
	sel_label.modulate = Color(0.7, 0.8, 1.0)
	bb.add_child(sel_label)
	op_panel = HBoxContainer.new()
	op_panel.add_theme_constant_override("separation", 8)
	bb.add_child(op_panel)
	for op in ["limit", "add_train", "close", "skip", "broadcast"]:
		var b := Button.new()
		b.text = _op_label(op)
		b.custom_minimum_size = Vector2(110, 34)
		b.disabled = true
		b.pressed.connect(_on_op.bind(op))
		op_panel.add_child(b)
		op_buttons[op] = b

	# Toast 提示
	toast_label = _make_label("", 20)
	toast_label.position = Vector2((VW - 600.0) / 2.0, 90)
	toast_label.size = Vector2(600, 40)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.modulate = Color(1, 1, 1, 0)
	add_child(toast_label)


func _make_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _op_label(op: String) -> String:
	match op:
		"limit": return "限流"
		"add_train": return "加车"
		"close": return "封站"
		"skip": return "跳站"
		"broadcast": return "广播"
	return op


func _connect() -> void:
	EventBus.metrics_changed.connect(_on_metrics)
	EventBus.selection_changed.connect(_on_selection)
	EventBus.toast.connect(_on_toast)
	EventBus.hour_changed.connect(func(_h): _refresh_top())
	EventBus.period_changed.connect(func(_p): _refresh_top())
	EventBus.weather_changed.connect(func(_w): _refresh_top())


func _process(_delta: float) -> void:
	if sim == null:
		return
	_refresh_top()
	_refresh_band()


## 刷新"当前视野段"提示：从 Game 上挂着的相机控制器读取。
func _refresh_band() -> void:
	if band_label == null or game == null:
		return
	var cc = game.get("camera_ctrl")
	if cc == null or not cc.has_method("band_name"):
		return
	band_label.text = str(cc.band_name())


func _refresh_top() -> void:
	if sim == null or sim.time == null:
		return
	time_label.text = sim.time.get_hour_label()
	period_label.text = _period_label(sim.time.get_period())
	weather_label.text = "天气：%s" % sim.weather.get_label()
	resource_label.text = "资源 %d" % int(sim.resources)
	time_bar.max_value = sim.duration
	time_bar.value = sim.elapsed


func _period_label(p: String) -> String:
	match p:
		"dawn": return "清晨"
		"morning_peak": return "早高峰"
		"flat": return "平峰"
		"noon": return "午间"
		"afternoon": return "午后"
		"evening_peak": return "晚高峰"
		"night": return "夜间"
		"late_night": return "深夜"
	return p


func _on_metrics(m: Dictionary) -> void:
	if m.is_empty():
		return
	metric_labels["punctuality"].text = "准点率 %.0f%%" % (m["punctuality"] * 100)
	metric_labels["satisfaction"].text = "满意度 %.0f%%" % (m["satisfaction"] * 100)
	metric_labels["throughput"].text = "吞吐量 %d/%d" % [m["served"], m["target_served"]]
	metric_labels["safety"].text = "安全分 %.0f%%" % (m["safety"] * 100)
	metric_labels["efficiency"].text = "效率分 %.0f%%" % (m["efficiency"] * 100)
	# 安全分低时标红
	var s: float = m["safety"]
	metric_labels["safety"].modulate = Color(1, 1, 1) if s > 0.4 else Color(1, 0.4, 0.4)


func _on_selection(target: Dictionary) -> void:
	var t: String = target.get("type", "none")
	if t == "station":
		var st: Station = sim.get_station(target["id"])
		if st:
			sel_label.text = "站点：%s（等车 %d / 容量 %d）" % [st.name, st.queue_size(), st.effective_capacity()]
			_set_buttons(true)
	elif t == "line":
		var ln: Line = sim.get_line(target["id"])
		if ln:
			sel_label.text = "线路：%s（列车 %d 列）" % [ln.name, ln.trains.size()]
			_set_buttons(false)
	else:
		sel_label.text = "未选择（点击站点或线路）"
		_disable_buttons()


func _set_buttons(station_mode: bool) -> void:
	for key in op_buttons:
		op_buttons[key].disabled = true
	if station_mode:
		op_buttons["limit"].disabled = false
		op_buttons["close"].disabled = false
		op_buttons["skip"].disabled = false
	else:
		op_buttons["add_train"].disabled = false
	op_buttons["broadcast"].disabled = false


func _disable_buttons() -> void:
	for key in op_buttons:
		op_buttons[key].disabled = true


func _on_op(op: String) -> void:
	if sim == null:
		return
	var target: int = -1
	match op:
		"limit", "close", "skip":
			target = sim.selected_station_id
		"add_train":
			target = sim.selected_line_id
		"broadcast":
			target = -1
	if target < 0 and op != "broadcast":
		EventBus.toast.emit("请先选择目标")
		return
	sim.apply_operation(op, target)


func _on_toast(msg: String) -> void:
	toast_label.text = msg
	toast_label.modulate = Color(1, 1, 1, 1)
	if toast_tween and toast_tween.is_valid():
		toast_tween.kill()
	toast_tween = create_tween()
	toast_tween.tween_interval(2.0)
	toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.8)
