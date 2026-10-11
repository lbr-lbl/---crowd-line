class_name HUD
extends CanvasLayer
## 游戏内 HUD：时间、天气、时段、资源、积分指标、操作按钮、提示。
##
## 界面本体在 scenes/hud.tscn 里搭好（可在编辑器里直接预览、拖拽布局），
## 本脚本只负责绑定节点、刷新文本、按状态置灰。字段用 @onready 绑定。

@onready var clock_label: Label = $TimePanel/TimeRow/ClockLabel
@onready var pause_button: Button = $TimePanel/TimeRow/PauseButton
@onready var speed_button: Button = $TimePanel/TimeRow/SpeedButton

## 竖直时间轴（需求 ⑧）：进度向下走、颜色随时段变、顶端是天气图标
@onready var time_axis: TimeAxis = $TimeAxis

# 左上角只剩评级：**只放徽章图**（徽章本身就带字母 art，再写一个字母是重复）
@onready var rating_badge: TextureRect = $RatingPanel/RatingRow/RatingBadge

@onready var resource_label: Label = $MetricsPanel/MetricsBox/ResourceLabel
@onready var period_label: Label = $MetricsPanel/MetricsBox/PeriodLabel
@onready var weather_label: Label = $MetricsPanel/MetricsBox/WeatherLabel
@onready var wave_label: Label = $MetricsPanel/MetricsBox/WaveLabel
## 视野提示挪到视野滑钮旁边（需求）；指标面板默认还是隐藏的，
## 放在里面等于永远看不见，所以它必须是**独立的**节点。
@onready var band_label: Label = $BandLabel

@onready var sel_label: Label = $OpPanel/OpBox/SelLabel
## 操作按钮那一排（需求 ⑥：没有可用操作时整排隐藏）
@onready var op_row: HBoxContainer = $OpPanel/OpBox/OpRow
@onready var toast_label: Label = $ToastLabel

# 右侧：运营日志
@onready var log_button: Button = $LogButton
@onready var log_panel: PanelContainer = $LogPanel
@onready var log_text: RichTextLabel = $LogPanel/LogBox/LogText

# 右侧：视野滑钮（轨道 + 三站点 + 列车指示当前视野）
@onready var view_slider: ViewSlider = $ViewSlider

## 指标加减分的飘字容器（需求 ⑨）
@onready var float_layer: Control = $FloatLayer

## 需要"平时半透明、交互或悬浮不透明"的卡片
@onready var cards: Array[Control] = [$RatingPanel, $MetricsPanel, $TimePanel, $OpPanel, $LogButton, $LogPanel]

## 这三张卡按需求**去掉底板**（评级 / 顶部时间 / 操作按钮条），详见 `_flatten_chrome()`
@onready var rating_panel: PanelContainer = $RatingPanel
@onready var time_panel: PanelContainer = $TimePanel
@onready var op_panel: PanelContainer = $OpPanel
@onready var metrics_panel: PanelContainer = $MetricsPanel
## 右下角资源徽章（在 _ready 里创建）
var resource_badge: ResourceBadge = null
## 悬浮评级时出现的评分文字（在 _setup_rating_click 里创建）
var score_label: Label = null

## 卡片背景平时的透明度（悬浮或**按住**时变 1.0）
const CARD_IDLE_ALPHA := 0.62
## card -> [{sb: StyleBoxFlat, base: float}]：被我们换成"可调 alpha"的副本，改它就能淡出背景
var _card_styles: Dictionary = {}


func _ready() -> void:
	_build_bindings()
	_setup_card_fade()
	_flatten_chrome()
	_setup_rating_click()
	_setup_resource_badge()
	# 操作面板初始不显示（选中站点/线路时才从下升起）
	_op_rest_y = op_panel.position.y
	op_panel.visible = false


## 评级徽章：**悬浮出评分**（需求），**点击**展开/收起运营指标。
##
## 评分标签挂在 RatingRow（HBoxContainer）里，让它自己排在徽章右边——
## 手工算坐标在锚定/容器布局下很容易算错（资源徽章那次就飞出过屏幕）。
func _setup_rating_click() -> void:
	rating_badge.mouse_filter = Control.MOUSE_FILTER_STOP
	rating_badge.tooltip_text = "悬浮看评分，点一下看运营指标"
	rating_badge.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			metrics_panel.visible = not metrics_panel.visible)

	score_label = Label.new()
	score_label.visible = false
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_label.add_theme_font_size_override("font_size", 22)
	score_label.add_theme_color_override("font_color", Config.COLOR_INK)
	rating_badge.get_parent().add_child(score_label)

	rating_badge.mouse_entered.connect(_show_score)
	rating_badge.mouse_exited.connect(func() -> void: score_label.visible = false)


func _show_score() -> void:
	if score_label == null or sim == null or sim.score == null:
		return
	# ⚠ 直接问 ScoreSystem，**不要从 `_metrics` 里读**。
	# `_metrics` 来自 `EventBus.metrics_changed`，而模拟层发的是 `live_metrics()`
	# （每帧发的轻量版），里面**没有 total_score / rating**。
	# 从那里读的结果就是永远 "0 分 / D"，而结算面板调 `metrics()` 显示正常——两边不一致的根源。
	score_label.text = "评分 %d" % int(round(sim.score.total_score()))
	score_label.visible = true


## 右下角资源徽章（金色圆圈 + 圈内数值），需求：资源从指标面板移到这里
func _setup_resource_badge() -> void:
	resource_badge = ResourceBadge.new()
	resource_badge.name = "ResourceBadge"
	# ⚠ 顺序与方式都有讲究：
	#   ① 先定尺寸再设锚点预设，否则预设时尺寸还是 0，矩形退化成一点；
	#   ② 锚到右下角之后**必须改 offsets 来挪位置**——直接写 `position` 会按父节点原点
	#      反算 offsets，等于把控件扔到屏幕外（第一版就是这么错的，徽章根本没出现）。
	resource_badge.custom_minimum_size = Vector2(68.0, 68.0)
	resource_badge.anchor_left = 1.0
	resource_badge.anchor_top = 1.0
	resource_badge.anchor_right = 1.0
	resource_badge.anchor_bottom = 1.0
	resource_badge.offset_left = -88.0
	resource_badge.offset_top = -88.0
	resource_badge.offset_right = -20.0
	resource_badge.offset_bottom = -20.0
	add_child(resource_badge)


## 需求："评级 / 顶部时间 / 各按钮不要背景面板，但要让它们贴合主题"。
##
## 做法：把这些控件的 StyleBox 换成 `StyleBoxEmpty`（没有底板、没有边框、没有阴影），
## 让它们直接"贴"在纸面上。可读性交给 Theme 里的浅色字阴影（见 hud.tscn 的 Theme_hud），
## 所以压在彩色线路上也还读得清。
##
## 指标面板与日志面板**保留卡片**：它们是大段文字，没有底板会糊在地图上。
func _flatten_chrome() -> void:
	var empty := StyleBoxEmpty.new()
	for n in [rating_panel, time_panel, op_panel]:
		n.add_theme_stylebox_override("panel", empty)
	var btns: Array = [log_button, pause_button, speed_button]
	for key in op_buttons:
		btns.append(op_buttons[key])
	# 悬浮/按下的交互提示改成**改色**（用户要求："按钮悬浮提示还是改色吧"）：
	# 不再给 hover 加底板，而是把图标与文字的染色换掉——悬浮变蓝、按下变橙。
	const HOVER_COL := Color("#1d4ed8")
	const PRESS_COL := Color("#b45309")
	for b in btns:
		if b == null:
			continue
		for k in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(k, empty)
		b.add_theme_color_override("icon_normal_color", Config.COLOR_INK)
		b.add_theme_color_override("icon_hover_color", HOVER_COL)
		b.add_theme_color_override("icon_pressed_color", PRESS_COL)
		b.add_theme_color_override("font_normal_color", Config.COLOR_INK)
		b.add_theme_color_override("font_hover_color", HOVER_COL)
		b.add_theme_color_override("font_pressed_color", PRESS_COL)


## 卡片平时半透明。**只让背景变淡，不动 modulate** ——
## 之前是给整张卡片上 `modulate.a = 0.6`，结果深色字被一起冲淡成灰白，看不清（用户反馈）。
## 现在改成把面板/按钮的 StyleBoxFlat 复制一份、只降 `bg_color.a`，文字保持完全实心。
## 交互也从"点一下钉住"改成"**按住**才不透明"（用户要求）。
func _setup_card_fade() -> void:
	for c in cards:
		if c == null:
			continue
		var styles: Array = []
		_collect_styleboxes(c, styles)
		_card_styles[c] = styles
		_set_card_alpha(c, CARD_IDLE_ALPHA)
		c.mouse_filter = Control.MOUSE_FILTER_PASS
		c.mouse_entered.connect(_set_card_alpha.bind(c, 1.0))
		c.mouse_exited.connect(_set_card_alpha.bind(c, CARD_IDLE_ALPHA))
		c.gui_input.connect(_on_card_input.bind(c))


## 递归收集面板与按钮的 StyleBoxFlat，换成可调透明的副本并记下原始 alpha
func _collect_styleboxes(node: Control, into: Array) -> void:
	if node is PanelContainer:
		var sb := node.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			var d: StyleBoxFlat = (sb as StyleBoxFlat).duplicate()
			into.append({"sb": d, "base": d.bg_color.a})
			node.add_theme_stylebox_override("panel", d)
	if node is Button:
		for k in ["normal", "hover", "pressed", "disabled"]:
			var sb2 := node.get_theme_stylebox(k)
			if sb2 is StyleBoxFlat:
				var d2: StyleBoxFlat = (sb2 as StyleBoxFlat).duplicate()
				into.append({"sb": d2, "base": d2.bg_color.a})
				node.add_theme_stylebox_override(k, d2)
	for ch in node.get_children():
		if ch is Control:
			_collect_styleboxes(ch, into)


func _set_card_alpha(c: Control, a: float) -> void:
	for e in _card_styles.get(c, []):
		var sb: StyleBoxFlat = e["sb"]
		sb.bg_color.a = float(e["base"]) * a
	if c != null:
		c.queue_redraw()


## 鼠标左键**按住**时卡片变实心，松开恢复半透明
func _on_card_input(event: InputEvent, c: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_set_card_alpha(c, 1.0 if event.pressed else CARD_IDLE_ALPHA)

## 请求 Game 打开"暂停概览"（评分 / 时长 / 退出 / 继续）
signal pause_overview_requested

var sim: Simulation
var game: Node = null

var metric_labels: Dictionary = {}
## 最近一次 metrics_changed 收到的指标快照（评级等要从这里读，避免每帧重新算一份字典）
var _metrics: Dictionary = {}
var op_buttons: Dictionary = {}
var eligible: Dictionary = {}   # op -> bool：当前选择下该操作是否可用（价格另算）

var toast_tween: Tween
var _scale: float = 1.0


func setup(p_sim: Simulation, p_game: Node) -> void:
	sim = p_sim
	game = p_game
	time_axis.sim = p_sim
	_connect()


## 把场景里的按钮/指标标签登记进字典，并接上点击回调
func _build_bindings() -> void:
	for key in ["punctuality", "satisfaction", "throughput", "safety", "efficiency"]:
		var n := "MetricsPanel/MetricsBox/%sLabel" % key.capitalize()
		metric_labels[key] = get_node_or_null(n)

	var paths := {
		"limit": "OpPanel/OpBox/OpRow/LimitButton",
		"upgrade_train": "OpPanel/OpBox/OpRow/UpgradeButton",
		"close": "OpPanel/OpBox/OpRow/CloseButton",
		"skip": "OpPanel/OpBox/OpRow/SkipButton",
		"broadcast": "OpPanel/OpBox/OpRow/BroadcastButton",
	}
	for op in paths:
		var b: Button = get_node_or_null(paths[op])
		if b == null:
			continue
		b.pressed.connect(_on_op.bind(op))
		op_buttons[op] = b

	pause_button.pressed.connect(_on_pause_pressed)
	speed_button.toggled.connect(_on_speed_toggled)
	log_button.pressed.connect(_toggle_log)
	log_text.meta_clicked.connect(_on_log_meta)
	view_slider.view_changed.connect(_on_view_slider)


## 点日志条目 -> 镜头飞到该站并高亮（需求："点日志条目平滑飞过去并短暂高亮"）
func _on_log_meta(meta: Variant) -> void:
	var s := str(meta)
	if not s.begins_with("st:"):
		return
	if game != null and game.has_method("focus_station"):
		game.focus_station(int(s.substr(3)))


## 视野滑钮拖动：换算成目标缩放交给 Game（与滚轮同一套回弹规则）
func _on_view_slider(t: float) -> void:
	if game != null and game.has_method("set_view_zoom"):
		game.set_view_zoom(view_slider.zoom_of_t(t))


## 每帧把相机当前缩放同步给滑钮（这样滚轮缩放时"列车"也会跟着走）
func _sync_view_slider() -> void:
	if game == null:
		return
	var cam = game.get("camera")
	if cam is Camera2D:
		view_slider.set_from_zoom((cam as Camera2D).zoom.x)


func _op_label(op: String) -> String:
	return _op_name(op)


## 操作的中文名（不含价格；价格由 _refresh_op_buttons 每帧拼上去）
func _op_name(op: String) -> String:
	match op:
		"limit": return "限流"
		"upgrade_train": return "升级车辆"
		"close": return "封站"
		"skip": return "跳站"
		"broadcast": return "广播"
	return op


## 该操作此刻的价格（D）。升级车辆随选中线路与当前时段浮动；没选中时返回 0。
func _op_cost(op: String) -> float:
	if sim == null:
		return 0.0
	if op == "upgrade_train":
		var lid: int = sim.selected_line_id
		if lid < 0:
			return 0.0
		var ln: Line = sim.get_line(lid)
		if ln == null:
			return 0.0
		if not ln.depot_built:
			return sim.depot_build_cost(lid)
		return sim.depot_upgrade_cost(lid)
	return Config.operation_cost(op)


## 操作栏悬停说明（默认文案；车辆段那条会在 _refresh_depot_tip 里按状态覆盖）
func _op_tip(op: String) -> String:
	match op:
		"limit":
			return "限流 %d 资源：降低该站进站速度 30s，代价是站内乘客耐心受损" % int(Config.operation_cost("limit"))
		"upgrade_train":
			return "升级车辆：先建车辆段，再下达加挂指令 —— 下一列停靠段站的列车就地加长编组，运营不中断"
		"close":
			return "封站 %d 资源：列车不停靠 20s，副作用是站内乘客耐心大跌" % int(Config.operation_cost("close"))
		"skip":
			return "跳站 %d 资源：列车通过不停 20s，适合快速散开某站积聚" % int(Config.operation_cost("skip"))
		"broadcast":
			return "广播 %d 资源：安抚全场恐慌，并让乘客获知路况、主动绕开爆站" % int(Config.operation_cost("broadcast"))
	return op


func _connect() -> void:
	EventBus.metrics_changed.connect(_on_metrics)
	EventBus.selection_changed.connect(_on_selection)
	EventBus.toast.connect(_on_toast)
	EventBus.log_updated.connect(_refresh_log)
	EventBus.hour_changed.connect(func(_h): _refresh_top())
	EventBus.period_changed.connect(func(_p): _refresh_top())
	EventBus.weather_changed.connect(func(_w): _refresh_top())


## 右侧日志：按钮开合面板；打开时按最新在前重建内容
func _toggle_log() -> void:
	if log_panel.visible:
		log_panel.visible = false
	else:
		open_log()


## 打开日志并刷新（截图/测试也走这个口）
func open_log() -> void:
	log_panel.visible = true
	_refresh_log()


## 把运营日志渲染成 BBCode（最新在前，按类别上色）
func _refresh_log() -> void:
	if log_text == null or not log_panel.visible:
		return
	if sim == null or sim.ops_log == null:
		log_text.text = "[color=#6b7280]（本局还没有记录）[/color]"
		return
	var rows: Array = []
	var entries: Array = sim.ops_log.entries
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		var col := _log_color(str(e["kind"]))
		var body := "[color=%s]%s[/color]  %s" % [
			col, OpsLog.kind_label(str(e["kind"])), sim.ops_log.line_for(e)]
		# 带站点指向的条目做成可点链接：点了镜头飞过去（RichTextLabel 的 meta_clicked）
		var ref: Dictionary = e.get("ref", {})
		if ref.has("station"):
			body = "[url=st:%d]%s[/url]" % [int(ref["station"]), body]
		rows.append(body)
	if rows.is_empty():
		log_text.text = "[color=#6b7280]（本局还没有记录）[/color]"
	else:
		log_text.text = "\n".join(PackedStringArray(rows))


func _log_color(kind: String) -> String:
	match kind:
		"event": return "#b45309"
		"weather": return "#0369a1"
		"operation": return "#15803d"
		"wave": return "#7c3aed"
	return "#334155"


# ================= 指标加减分飘字（需求 ⑨）=================

## key -> 上一次的值；用来算"这次变了多少"
var _prev_metrics: Dictionary = {}
## key -> 上次飘字的时间戳（毫秒），避免高频刷屏
var _float_cd: Dictionary = {}
## key -> **累计还没飘出去的增量**。
## 关键：`metrics_changed` 每帧都发，而满意度/准点率这种每帧只动零点几个百分点，
## 逐帧比较永远不会超过阈值 —— 实测结果就是"只有吞吐量会飘字，其它全都没有"（用户反馈）。
## 所以改成**累加**，攒够阈值再飘一次并把累计清零。
var _float_acc: Dictionary = {}
## key -> 上次的评级字母（评级变了也要飘）
var _prev_rating_letter: String = ""
var _float_font: Font = null

const FLOAT_MIN_GAP_MS := 280
## 各类指标的"攒够多少才飘"：百分比按百分点，吞吐按人，总分按分
const FLOAT_THRESHOLD: Dictionary = {
	"punctuality": 2.0, "satisfaction": 2.0, "safety": 2.0, "efficiency": 2.0,
	"served": 12.0, "score": 80.0,
}
const FLOAT_FONT_PATH := "res://assets/fonts/Anton-Regular.ttf"


## 比较这一次与上一次的指标，累计到阈值就在对应那一行旁边飘一个 +/− 数字。
##
## **指标面板隐藏时不再飘指标数字**（需求）：面板关着，数字飘在空白处没人看得懂。
## 此时只保留评级旁的**评分加减**——那是常驻可见的锚点。
func _emit_metric_floats(m: Dictionary) -> void:
	var metrics_visible := metrics_panel != null and metrics_panel.visible
	# 百分比类（以"百分点"计）
	for key in ["punctuality", "satisfaction", "safety", "efficiency"]:
		if not m.has(key):
			continue
		var cur := float(m[key])
		if _prev_metrics.has(key):
			if metrics_visible:
				_accumulate(key, (cur - float(_prev_metrics[key])) * 100.0, "%.0f%%")
			else:
				_float_acc[key] = 0.0
		_prev_metrics[key] = cur
	# 吞吐量（以"人"计）——锚在吞吐那一行
	if m.has("served"):
		var cur_n := float(m["served"])
		if _prev_metrics.has("served"):
			if metrics_visible:
				_accumulate_anchor("throughput", "served", cur_n - float(_prev_metrics["served"]), "%d 人", true)
			else:
				_float_acc["served"] = 0.0
		_prev_metrics["served"] = cur_n
	# 总分（以"分"计）——锚在**评级徽章**旁边
	# 总分（以"分"计）——锚在**评级徽章**旁边。
	# 同样直接问 ScoreSystem：`live_metrics()` 里没有 total_score，
	# 之前从 m 里读的结果是"评分飘字从来没出现过"。
	var cur_s := sim.score.total_score()
	if _prev_metrics.has("__score"):
		_accumulate_anchor("rating", "score", cur_s - float(_prev_metrics["__score"]), "%d 分", true)
	_prev_metrics["__score"] = cur_s
	# 评级：字母变了立刻飘（S 最好）
	var letter := str(m.get("rating", ""))
	if letter != "" and _prev_rating_letter != "" and letter != _prev_rating_letter:
		var better := _rating_rank(letter) > _rating_rank(_prev_rating_letter)
		_spawn_float(rating_badge, "评级 %s" % letter, better)
	if letter != "":
		_prev_rating_letter = letter


## 累计某个指标的增量；攒够阈值就飘一次并清零
func _accumulate(key: String, delta: float, fmt: String) -> void:
	_accumulate_anchor(key, key, delta, fmt, false)

## `anchor_key` 决定飘在哪个标签旁；`acc_key` 决定用哪个阈值；`as_int` = 取整显示（人数/分数）
func _accumulate_anchor(anchor_key: String, acc_key: String, delta: float, fmt: String, as_int: bool) -> void:
	var acc := float(_float_acc.get(acc_key, 0.0)) + delta
	var th := float(FLOAT_THRESHOLD.get(acc_key, 5.0))
	if absf(acc) < th:
		_float_acc[acc_key] = acc
		return
	_float_acc[acc_key] = 0.0
	var text: String = (fmt % int(round(acc))) if as_int else (fmt % acc)
	var anchor: Control = rating_badge if anchor_key == "rating" else metric_labels.get(anchor_key, null)
	_float_metric(anchor_key, anchor, text, acc > 0.0)


static func _rating_rank(letter: String) -> int:
	match letter:
		"S": return 5
		"A": return 4
		"B": return 3
		"C": return 2
		"D": return 1
	return 0


func _float_metric(key: String, anchor: Control, text: String, positive: bool) -> void:
	var now := Time.get_ticks_msec()
	var last := int(_float_cd.get(key, -99999))
	if now - last < FLOAT_MIN_GAP_MS:
		return
	_float_cd[key] = now
	_spawn_float(anchor, ("+" if positive else "") + text, positive)


## 飘字：在锚点右侧生成一个粗体数字，向上（加分）或向下（减分）漂移并消散。
## 字体用下载的展示字体（OFL，见 素材应用表.md），带白色描边保证浅色底上也看得清。
func _spawn_float(anchor: Control, text: String, positive: bool) -> void:
	if anchor == null or float_layer == null:
		return
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _get_float_font())
	l.add_theme_font_size_override("font_size", 19)
	# 颜色约定（用户要求）：**增加用红、下降用绿**（和常见直觉相反，照做）
	l.add_theme_color_override("font_color",
		Color(0.80, 0.15, 0.18) if positive else Color(0.10, 0.60, 0.28))
	l.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.95))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	float_layer.add_child(l)

	var gp := anchor.global_position
	l.global_position = Vector2(gp.x + anchor.size.x + 6.0, gp.y + 2.0)
	var dy := -34.0 if positive else 34.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + dy, 0.95) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.55).set_delay(0.40)
	tw.chain().tween_callback(l.queue_free)


func _get_float_font() -> Font:
	if _float_font == null:
		_float_font = load(FLOAT_FONT_PATH) if ResourceLoader.exists(FLOAT_FONT_PATH) else ThemeDB.fallback_font
	return _float_font


func _process(_delta: float) -> void:
	if sim == null:
		return
	_refresh_top()
	_refresh_band()
	_refresh_op_buttons()
	_sync_view_slider()
	# 选中线路时每帧刷新编组/车辆段状态（加挂中的倒计时要动起来）
	# 注意与下面互斥：线路优先，否则两者都选中时站点标签会把线路标签盖掉
	if sim.selected_line_id >= 0:
		_refresh_line_label()
		_refresh_depot_tip()
	# 选中**站点**时也要每帧刷新：等车人数是实时变化的（用户反馈原来只在点选那一刻更新一次）
	elif sim.selected_station_id >= 0:
		_refresh_station_label()


## 站点标签：等车人数 / 容量都是实时值，所以放在 _process 里每帧刷
func _refresh_station_label() -> void:
	var st: Station = sim.get_station(sim.selected_station_id)
	if st == null:
		return
	sel_label.text = "站点：%s（等车 %d / 容量 %d）" % [
		st.name, st.queue_size(), st.effective_capacity()]


## 暂停键不再自己切暂停，而是让 Game 弹出"概览"面板（里面才有继续/退出）
func _on_pause_pressed() -> void:
	pause_overview_requested.emit()


## 只留一个加速键：按下 = 2×，再按一次 = 原速（用户要求）
func _on_speed_toggled(on: bool) -> void:
	_apply_scale(2.0 if on else 1.0)


func _apply_scale(v: float) -> void:
	_scale = v
	if game != null and game.has_method("set_time_scale"):
		game.set_time_scale(v)
	speed_button.set_pressed_no_signal(v >= 1.5)


## 刷新"当前视野段"提示：从 Game 上挂着的相机控制器读取。
## 需求："去掉视野提示字样，只在调整视野时浮现"。
## 做法：不调整时 alpha 趋近 0（而不是删除节点），调整中或刚停下 1.2 秒内趋近 1。
func _refresh_band() -> void:
	if band_label == null or game == null:
		return
	var cc = game.get("camera_ctrl")
	if cc == null or not cc.has_method("band_name"):
		return
	band_label.text = str(cc.band_name())


func _update_band_visibility() -> void:
	if band_label == null or game == null:
		return
	var cc = game.get("camera_ctrl")
	if cc == null:
		return
	var settled: bool = cc.has_method("is_settled") and bool(cc.call("is_settled"))
	if not settled:
		_band_show_t = 1.2
	else:
		_band_show_t = maxf(0.0, _band_show_t - get_process_delta_time())
	var a := 1.0 if _band_show_t > 0.0 else 0.0
	band_label.modulate.a = lerpf(band_label.modulate.a, a, 0.25)


var _band_show_t: float = 0.0


func _refresh_top() -> void:
	if sim == null or sim.time == null:
		return
	# 具体时刻放在屏幕顶端居中（像手机状态栏），暂停/加速两个图标分列两侧
	clock_label.text = sim.time.get_hour_label()
	period_label.text = _period_label(sim.time.get_period())
	weather_label.text = "天气：%s" % sim.weather.get_label()
	# 资源移到右下角的金色圆圈徽章里，指标面板不再显示资源
	resource_label.visible = false
	if resource_badge != null:
		resource_badge.set_value(sim.resources, RealWorld.city(sim.network_id))
	if band_label != null:
		_update_band_visibility()
	# 无限模式：显示"第几波 + 下一波倒计时"（进度由竖直时间轴负责画）
	if wave_label != null:
		wave_label.visible = sim.infinite_mode and sim.director != null
		if wave_label.visible:
			wave_label.text = "第 %d 波 · 下一波 %.0fs" % [sim.director.wave, sim.director.seconds_left()]
	_refresh_rating()


const BADGE_PATH := "res://assets/icons/badge_%s.png"
## 评级 -> 徽章染色（用户要求：只用图标，且不同评级不同颜色）
const RATING_COLOR: Dictionary = {
	"S": Color("#f59e0b"),
	"A": Color("#16a34a"),
	"B": Color("#2563eb"),
	"C": Color("#ea580c"),
	"D": Color("#dc2626"),
}
var _badge_cache: Dictionary = {}
var _last_rating: String = ""


## 左上角只放评级徽章（徽章图自带字母 art），并按评级染色。评级变了才换，避免每帧 load。
func _refresh_rating() -> void:
	if sim == null or sim.score == null:
		return
	# ⚠ 评级同样**不能**从 `_metrics` 读（见 `_show_score()` 的说明：live_metrics 没有这个键）。
	var rating: String = Config.rating_for_score(sim.score.total_score())
	if rating == _last_rating:
		return
	_last_rating = rating
	# 评级变了要**看得出来**：徽章弹一下（用户反馈"评级好像都不会变"，
	# 其实是在变（D<1000 / C<3000 / B<5000），只是没有任何反馈，前期又长时间停在 D）
	if rating_badge != null:
		rating_badge.pivot_offset = rating_badge.size * 0.5
		var tw := create_tween()
		tw.tween_property(rating_badge, "scale", Vector2(1.35, 1.35), 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(rating_badge, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var tex: Texture2D = _badge_cache.get(rating, null)
	if tex == null and not _badge_cache.has(rating):
		var p := BADGE_PATH % rating
		tex = load(p) if ResourceLoader.exists(p) else null
		_badge_cache[rating] = tex
	if tex != null:
		rating_badge.texture = tex
	# 不同评级不同颜色（徽章是白底透明图，染色即可）
	var col: Color = RATING_COLOR.get(rating, Color("#334155"))
	rating_badge.modulate = col
	rating_badge.tooltip_text = "当前评级 %s" % rating


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
	_metrics = m
	_emit_metric_floats(m)
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
			_refresh_station_label()
			_set_buttons(true)
	elif t == "line":
		_set_buttons(false)
		_refresh_line_label(int(target.get("id", sim.selected_line_id)))
	elif t == "train":
		# 点了列车 = 开始跟车（镜头一直跟着它）
		_set_buttons(false)
		sel_label.text = "跟随列车中（点空白处解除）"
	else:
		sel_label.text = "未选择（点击站点或线路）"
		_disable_buttons()


## 线路选中时的实时文本：车辆段建没建、有没有加挂指令在等车、加挂中、最大编组多少节
func _refresh_line_label(lid: int = -1) -> void:
	if sim == null:
		return
	if lid < 0:
		lid = sim.selected_line_id
	var ln: Line = sim.get_line(lid)
	if ln == null:
		return
	var depot_text := "未建"
	if ln.depot_built:
		# 顺序要紧：正在挂的那几秒要显示"加挂中"，不能被"待加挂"盖住
		if ln.coupling_train() != null:
			depot_text = "加挂中"
		elif ln.pending_couples > 0:
			depot_text = "待加挂（等车停靠）"
		else:
			depot_text = "已建成"
	sel_label.text = "线路：%s（列车 %d 列 / 最大编组 %d 节 / 车辆段 %s）" % [
		ln.name, ln.trains.size(), ln.max_cars(), depot_text]


## 「升级车辆」按钮的悬停说明按当前状态实时改写，让价格、时段和进度一眼可见
func _refresh_depot_tip(lid: int = -1) -> void:
	if sim == null or not op_buttons.has("upgrade_train"):
		return
	if lid < 0:
		lid = sim.selected_line_id
	var b: Button = op_buttons["upgrade_train"]
	var ln: Line = sim.get_line(lid)
	if ln == null:
		return
	var cap := int(Config.DEPOT["max_cars"])
	var hanging := ln.coupling_train()
	if not ln.depot_built:
		b.tooltip_text = "升级车辆：先建车辆段（%d 资源），建好后才能下达加挂指令" % int(round(sim.depot_build_cost(lid)))
	elif hanging != null:
		b.tooltip_text = "正在加挂：该车在段站多停 %.0fs，之后编组 +1 节（照常开门上下客）" % maxf(0.0, hanging.couple_timer)
	elif ln.pending_couples > 0:
		b.tooltip_text = "加挂指令已下达：等下一列列车停靠段站。平峰加挂又快又便宜，高峰又慢又贵"
	elif ln.max_cars() >= cap:
		b.tooltip_text = "该线列车编组已达上限 %d 节" % cap
	else:
		b.tooltip_text = "下达加挂指令：%d 资源（当前%s），下一列停靠段站的列车多停 %.0fs 加 1 节，期间照常运营" % [
			int(round(sim.depot_upgrade_cost(lid))), sim.depot_phase(), sim.depot_couple_dwell()]


## 只记录"当前选择下哪些操作可用"；资源是否够、按钮置灰留给 _refresh_op_buttons 每帧算
func _set_buttons(station_mode: bool) -> void:
	eligible["limit"] = station_mode
	eligible["close"] = station_mode
	eligible["skip"] = station_mode
	eligible["upgrade_train"] = not station_mode
	eligible["broadcast"] = true


func _disable_buttons() -> void:
	eligible.clear()


## 每帧刷新操作按钮。
## 需求 ⑥：按钮**只显示图标**（信息放 tooltip，鼠标悬浮才出），而且
## **选中站点/线路之前整排隐藏**——只留下当前选择下真正可用的那几个。
func _refresh_op_buttons() -> void:
	if sim == null:
		return
	var any_visible := false
	for key in op_buttons:
		var b: Button = op_buttons[key]
		var can_use: bool = bool(eligible.get(key, false))
		b.visible = can_use
		if can_use:
			any_visible = true
		# 只留图标：文字清空，按钮收窄成方形
		b.text = ""
		b.custom_minimum_size = Vector2(58, 44)
		var cost := _op_cost(key) if can_use else 0.0
		b.tooltip_text = _op_tooltip(key, cost)
		b.disabled = can_use and cost > 0.0 and sim.resources < cost
	# 没有可用操作时整条面板降下去（需求："不点击线路和站点时什么都不要显现"）
	op_row.visible = any_visible
	_animate_op_panel(any_visible)


## 操作面板"从下升起 / 取消后下降"（需求）。
## 起始位置在 `_ready` 里记下（面板靠 offsets 定位，直接读 position 即可）。
func _animate_op_panel(show_it: bool) -> void:
	if op_panel == null or _op_shown == show_it:
		return
	_op_shown = show_it
	var down_y := _op_rest_y + op_panel.size.y + 30.0
	if show_it:
		op_panel.visible = true
		op_panel.position.y = down_y
	var tw := create_tween()
	tw.tween_property(op_panel, "position:y", _op_rest_y if show_it else down_y, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not show_it:
		tw.tween_callback(func() -> void: op_panel.visible = false)


var _op_shown: bool = false
var _op_rest_y: float = 0.0


## 悬浮说明：名字 / 价格 / 效果 / 当前资源是否够（唯一的"详细信息"出口）
func _op_tooltip(op: String, cost: float) -> String:
	var head := _op_name(op)
	if cost > 0.0:
		head += "（%d 资源%s）" % [int(round(cost)),
			"　✔ 当前可负担" if sim != null and sim.resources >= cost else "　✘ 资源不足"]
	return "%s\n%s" % [head, _op_tip(op)]


func _on_op(op: String) -> void:
	if sim == null:
		return
	var target: int = -1
	match op:
		"limit", "close", "skip":
			target = sim.selected_station_id
		"upgrade_train":
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
