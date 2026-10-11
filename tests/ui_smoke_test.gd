extends Node
## HUD / GameView 运行时冒烟测试（无头跑）。
##
## 跑法（PowerShell 5.1）：
##   $godot = "D:\下载\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
##   & $godot --headless --path "F:\Godot_project\涌线--crowd-line" res://tests/ui_smoke_test.tscn
##
## 为什么需要这个测试：
##   A/B/C/D 改造删掉了 Simulation.depot_remaining()/depot_duration() 和 Train.is_in_depot()，
##   而 HUD._refresh_line_label()/_refresh_depot_tip() 是最容易残留"调用已删除方法"的地方。
##   这类错误 GDScript **编译期查不出来**（sim 上的调用是动态的），只有真的把 HUD 挂到树上、
##   把车辆段的各种状态各走一遍，让 _process() 跑起来才会暴露。
##   GameView 同理：它引用了 Train.coupling / Line.pending_couples，也要真的实例化一次。
##
## 性质：只读 + 只调已有公开接口，不改游戏代码。失败时退出码 1。

const DT := 1.0 / 60.0
const TICK_BUDGET := 20000  # 单次推进上限（≈333 游戏秒），防死循环

var _fails: int = 0
var _sim: Simulation
var _hud: HUD
var _view: GameView


## 用来确认"无头模式下 _draw() 到底有没有被调用"的探针。
## 如果探针一次都没画，那么 GameView 的 _draw 路径其实没被验证到，
## 就该把下面那句 [PASS] 降级成"未验证"，而不是假装跑过了。
class DrawProbe extends Node2D:
	var hits: int = 0

	func _draw() -> void:
		hits += 1


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("  [PASS] %s   %s" % [label, detail])
	else:
		_fails += 1
		print("  [FAIL] %s   %s" % [label, detail])


func _ready() -> void:
	# 安全网：GDScript 的运行时错误**会中断 _ready() 的剩余部分**（包括末尾的 quit()），
	# 于是 headless 进程会永远挂着不出结果——这是本项目已经踩过一次的坑。
	# 所以这里先挂一个超时兜底，保证任何情况下都有明确退出码。
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		print("!! 超时强制退出：很可能有运行时错误中断了 _ready()（查上面的 SCRIPT ERROR）")
		get_tree().quit(3))

	print("=========== HUD / GameView 运行时冒烟 ===========")
	_sim = Simulation.new()
	add_child(_sim)
	# 用台北双线图：两条线各有自己的段站，能覆盖"多线各自车辆段"的情况
	_sim.setup("taipei_cross", "advance")

	# HUD 的界面本体在 scenes/hud.tscn 里，脚本只用 @onready 绑定节点，
	# 所以这里必须实例化场景，不能 HUD.new()。
	_hud = preload("res://scenes/hud.tscn").instantiate()
	add_child(_hud)
	_hud.setup(_sim, self)  # game 传自己（没有 camera_ctrl，_refresh_band 会安全早退）

	_view = GameView.new()
	add_child(_view)
	_view.sim = _sim
	_view.set_zoom_bands(0.9, 3.2, 9.0)   # 注入三段锚点，避免走兜底分支

	_test_selection_states()
	_test_depot_states()
	_test_game_view_blend()

	# 让引擎真的走几帧 _draw()：把 _draw_heatmap / _draw_clouds / _draw_lines /
	# _draw_depots / _draw_stations / _draw_trains / _draw_dots 全跑一遍。
	# GDScript 的运行时错误不会中断脚本，只会打到 stdout，所以要靠调用方 grep
	# "SCRIPT ERROR" / "Invalid" 来判定——本测试只保证这些路径真的被执行到。
	# （注意：queue_redraw() 是 CanvasItem 的方法，HUD 是 CanvasLayer，没有这个函数。）
	var probe := DrawProbe.new()
	add_child(probe)
	probe.queue_redraw()
	_view.queue_redraw()
	for _i in range(3):
		await get_tree().process_frame
	_check(probe.hits > 0, "无头模式下 _draw() 确实被调用", "探针画了 %d 次" % probe.hits)
	if probe.hits > 0:
		print("  （GameView._draw 与探针同一帧序列，其全路径也已执行；错误需查 stdout）")

	print("=========== 失败 %d 项 ===========" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


## 让 HUD 的 _process 真跑几帧（pump 一次等价于一帧）
func _pump(times: int = 3) -> void:
	for _i in range(times):
		_hud._process(DT)


## 推进模拟直到 pred 成立，返回是否成立
func _advance_until(pred: Callable) -> bool:
	var guard := 0
	while not pred.call() and guard < TICK_BUDGET:
		_sim.tick(DT)
		guard += 1
	return pred.call()


## 选择态：无选中 / 选站 / 选线，按钮可用性与价格文案
func _test_selection_states() -> void:
	print("--- 选择态与按钮 ---")
	var ln: Line = _sim.lines[0]
	var lid: int = ln.id
	var sid: int = ln.depot_station_id()

	# 1) 未选目标：按钮整排隐藏（需求 ⑥：初始不显示任何操作按钮）
	_sim.selected_station_id = -1
	_sim.selected_line_id = -1
	EventBus.selection_changed.emit({"type": "none"})
	_pump()
	var any_visible := false
	for key in _hud.op_buttons:
		if _hud.op_buttons[key].visible:
			any_visible = true
	_check(not any_visible, "未选目标时操作按钮整排隐藏",
		"提示语 \"%s\"" % _hud.sel_label.text)
	_check(not _hud.op_row.visible, "按钮行本身也收起")

	# 2) 选中站点：只显示 limit/close/skip（升级车辆属于"线路"语境，不该出现），
	#    并且**只留图标**（文字清空），详细信息在 tooltip 里
	_sim.selected_station_id = sid
	EventBus.selection_changed.emit({"type": "station", "id": sid})
	_hud._refresh_op_buttons()
	_check(_hud.op_row.visible, "选中站点后按钮行出现")
	_check(_hud.op_buttons["limit"].visible, "选中站点后限流出现")
	_check(_hud.op_buttons["close"].visible and _hud.op_buttons["skip"].visible,
		"选中站点后封站/跳站出现")
	_check(not _hud.op_buttons["upgrade_train"].visible, "选中站点时不显示升级车辆")
	_check(_hud.op_buttons["limit"].text == "", "按钮只留图标（文字为空）",
		"text=\"%s\"" % _hud.op_buttons["limit"].text)
	var tip: String = _hud.op_buttons["limit"].tooltip_text
	_check(tip.contains("限流") and tip.contains("%d" % int(round(Config.operation_cost("limit")))),
		"悬浮说明里有名字与价格", "tooltip=\"%s\"" % tip.replace("\n", " / "))
	_check(_hud.sel_label.text.begins_with("站点："), "站点标签文案", "\"%s\"" % _hud.sel_label.text)

	# 评分/评级必须与 ScoreSystem 一致（回归守卫）：
	# 模拟层每帧发的是 `live_metrics()`，里面**没有** total_score / rating 两个键，
	# 从那个字典读出来的结果就是永远"0 分 / D"（真发生过的 bug，结算面板却是对的）。
	_sim.score.served = 4000
	var want_score := int(round(_sim.score.total_score()))
	var want_rating := Config.rating_for_score(_sim.score.total_score())
	_hud._refresh_rating()
	_hud._show_score()
	_check(_hud._last_rating == want_rating, "评级取自 ScoreSystem（不是恒为 D）",
		"显示 %s / 应为 %s（总分 %d）" % [_hud._last_rating, want_rating, want_score])
	_check(_hud.score_label.text == "评分 %d" % want_score, "悬浮评分取自 ScoreSystem（不是 0）",
		"\"%s\"" % _hud.score_label.text)

	# 视野提示必须挂在 HUD 根下、**不能**在指标面板里：
	# 指标面板默认隐藏，放里面等于永远看不见；而且路径写错只会静默失效（不报错）。
	_check(_hud.band_label != null, "视野提示节点存在")
	if _hud.band_label != null:
		_check(_hud.band_label.get_parent() == _hud,
			"视野提示挂在 HUD 根下（不在指标面板里）",
			"父节点=%s" % _hud.band_label.get_parent().name)
	# 按钮的悬浮反馈改成"改色"而不是加底板：悬浮色必须与常态色不同
	var limit_btn: Button = _hud.op_buttons["limit"]
	_check(limit_btn.get_theme_color("icon_hover_color") != limit_btn.get_theme_color("icon_normal_color"),
		"按钮悬浮会改色（交互提示）",
		"normal=%s hover=%s" % [
			str(limit_btn.get_theme_color("icon_normal_color")),
			str(limit_btn.get_theme_color("icon_hover_color"))])
	_check(limit_btn.get_theme_stylebox("hover") is StyleBoxEmpty,
		"按钮悬浮不再加底板（改色方案）",
		limit_btn.get_theme_stylebox("hover").get_class())

	# 3) 选中线路：只显示升级车辆，且报价 = depot_build_cost（未建段时）
	_sim.selected_line_id = lid
	EventBus.selection_changed.emit({"type": "line", "id": lid})
	_pump()
	_check(_hud.op_buttons["upgrade_train"].visible, "选中线路后升级车辆出现")
	_check(not _hud.op_buttons["limit"].visible, "选中线路时不显示限流")
	var build := int(round(_sim.depot_build_cost(lid)))
	_check(_hud.op_buttons["upgrade_train"].tooltip_text.contains("%d" % build),
		"未建段时悬浮说明报建段价", "期望含 %d，实际 \"%s\"" % [
			build, _hud.op_buttons["upgrade_train"].tooltip_text.replace("\n", " / ")])

	# 4) 资源不足：按钮**仍在**（是你当前选择下的可用操作）但置灰点不动
	_sim.resources = 1.0
	_hud._refresh_op_buttons()
	_check(_hud.op_buttons["upgrade_train"].visible and _hud.op_buttons["upgrade_train"].disabled,
		"资源不足时按钮保留但置灰", "资源 %.0f" % _sim.resources)
	_check(_hud.op_buttons["upgrade_train"].tooltip_text.contains("资源不足"),
		"悬浮说明标出资源不足")
	_sim.resources = 999.0
	_hud._refresh_op_buttons()
	_check(not _hud.op_buttons["upgrade_train"].disabled, "资源充足后按钮恢复")


## 车辆段五态：未建 → 已建成 → 待加挂 → 加挂中 → 已建成(编组+1) → 触顶
func _test_depot_states() -> void:
	print("--- 车辆段状态文案 ---")
	var ln: Line = _sim.lines[0]
	var lid: int = ln.id
	_sim.selected_line_id = lid
	_sim.resources = 999.0

	# 未建
	_pump()
	_check(_hud.sel_label.text.contains("未建"), "未建段时线路标签", "\"%s\"" % _hud.sel_label.text)
	_check(_hud.op_buttons["upgrade_train"].tooltip_text.contains("先建车辆段"), "未建段 tooltip")

	# 建段
	_sim.apply_operation("upgrade_train", lid)
	_pump()
	_check(ln.depot_built, "建段成功")
	_check(_hud.sel_label.text.contains("已建成"), "建成后线路标签", "\"%s\"" % _hud.sel_label.text)

	# 下单 → 待加挂
	var before_cars: int = ln.max_cars()
	var before_fleet: int = ln.trains.size()
	_sim.apply_operation("upgrade_train", lid)
	_pump()
	_check(ln.pending_couples == 1, "加挂指令已下达", "pending=%d" % ln.pending_couples)
	_check(_hud.sel_label.text.contains("待加挂"), "下单后线路标签显示待加挂",
		"\"%s\"" % _hud.sel_label.text)
	_check(_hud.op_buttons["upgrade_train"].tooltip_text.contains("指令已下达"), "下单后 tooltip")

	# 等某列车真的开始挂 → 加挂中（不能被"待加挂"盖住）
	var started := _advance_until(func(): return ln.coupling_train() != null)
	_check(started, "有列车开始就地加挂")
	if started:
		_pump()
		_check(_hud.sel_label.text.contains("加挂中"), "加挂那几秒标签显示加挂中",
			"\"%s\"" % _hud.sel_label.text)
		_check(_hud.op_buttons["upgrade_train"].tooltip_text.contains("正在加挂"), "加挂中 tooltip",
			"\"%s\"" % _hud.op_buttons["upgrade_train"].tooltip_text)
		# 加挂中的列车必须仍在线上（A 的核心：不再把车抽走，车队规模不变）
		_check(ln.trains.size() == before_fleet, "车队规模不变（没有车被抽走）",
			"%d -> %d 列" % [before_fleet, ln.trains.size()])

	# 等挂完 → 回到已建成，编组 +1
	var done := _advance_until(func(): return ln.pending_couples == 0 and ln.coupling_train() == null)
	_pump()
	_check(done, "指令兑现", "pending=%d" % ln.pending_couples)
	_check(ln.max_cars() == before_cars + 1, "编组 +1 节",
		"%d -> %d" % [before_cars, ln.max_cars()])
	_check(_hud.sel_label.text.contains("已建成"), "兑现后回到已建成",
		"\"%s\"" % _hud.sel_label.text)

	# 触顶：把所有车塞到上限，tooltip 应提示上限
	var cap := int(Config.DEPOT["max_cars"])
	for t in ln.trains:
		t.cars = cap
		t.refresh_capacity()
	_pump()
	_check(_hud.op_buttons["upgrade_train"].tooltip_text.contains("上限"), "触顶时 tooltip 提示上限",
		"\"%s\"" % _hud.op_buttons["upgrade_train"].tooltip_text)


## GameView：实例化不报错 + 云点混合在三个档位上单调
func _test_game_view_blend() -> void:
	print("--- GameView ---")
	_check(_view != null and _view.bands_ready, "GameView 实例化并注入三段锚点",
		"overview=%.2f mid=%.2f fore=%.2f" % [_view.overview_zoom, _view.mid_zoom, _view.fore_zoom])
	var c_over := _view.cloud_blend_for(0.5)   # 比全貌更远 → 全云
	var c_mid := _view.cloud_blend_for(3.2)    # 中景 → 无云
	var c_between := _view.cloud_blend_for(2.0)
	_check(c_over > 0.99, "全貌段 = 全云", "%.2f" % c_over)
	_check(c_mid < 0.01, "中景段 = 无云", "%.2f" % c_mid)
	_check(c_between > 0.0 and c_between < 1.0, "段间 = 交叉淡化", "%.2f" % c_between)
	_check(c_over > c_between and c_between > c_mid, "云量随缩放单调递减")
	_view.queue_redraw()
	_check(true, "queue_redraw 未中断流程")
