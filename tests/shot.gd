extends Node
## 视觉核对用：开真窗口渲染并存成 PNG，并可选地再抓一帧算像素差来证明"动效真的在动"。
##
## 为什么需要它：`--headless` 用的是空渲染器，视口纹理里什么都没有，
## 所以"背景到底亮没亮、图标清不清楚、云和点长什么样、有没有动效"这类问题只能真渲染一次看图。
##
## 跑法（PowerShell 5.1）：
##   $godot = "D:\下载\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
##   & $godot --path "F:\Godot_project\涌线--crowd-line" res://tests/shot.tscn -- hongkong_tw_kt advance 2.2 25 res://tests/_shot.png
##
## 参数（都可省）：<线网> <难度> <缩放> <先跑多少游戏秒> <输出路径> [取景站号]
##   取景站号默认 -1 = 用站点质心取景。**不要用外接矩形中心**：香港图那种 U 形线网的
##   矩形中心是空的，高缩放时会出现"整屏空白"的假象。

const DEF_OUT := "res://tests/_shot.png"
const MOTION_WAIT := 0.8  # 抓第二帧前等多久（秒），用于测动效


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var net_id: String = args[0] if args.size() > 0 else "hongkong_tw_kt"

	# 模式一：直接渲染一个场景（主菜单 / 结算这类没有模拟层的界面）
	#   ... shot.tscn -- scene res://scenes/main.tscn res://tests/_menu.png
	#   ... shot.tscn -- scene res://scenes/pause_overlay.tscn res://tests/_pause.png sim
	#   末尾给 "sim" 时会先造一个跑过 60 秒的 Simulation，再交给节点的 open()/setup()，
	#   这样"需要数据才有内容"的界面（暂停概览）也能截到真实样子。
	if net_id == "scene":
		var scene_path: String = args[1] if args.size() > 1 else "res://scenes/main.tscn"
		var out_s: String = args[2] if args.size() > 2 else DEF_OUT
		var node: Node = (load(scene_path) as PackedScene).instantiate()
		add_child(node)
		if args.size() > 3 and args[3] == "sim":
			var s := Simulation.new()
			add_child(s)
			s.setup("hongkong_tw_kt", "advance")
			for _i in range(3600):
				s.tick(1.0 / 60.0)
				if not s.running:
					break
			if node.has_method("open"):
				node.open(s)
			elif node.has_method("setup"):
				node.setup(s)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img_s := get_viewport().get_texture().get_image()
		var e_s := img_s.save_png(out_s)
		print("已保存 %s（场景 %s）err=%d" % [out_s, scene_path, e_s])
		get_tree().quit(0 if e_s == OK else 1)
		return

	var mode: String = args[1] if args.size() > 1 else "advance"
	var zoom: float = float(args[2]) if args.size() > 2 else 1.0
	var secs: float = float(args[3]) if args.size() > 3 else 25.0
	var out_path: String = args[4] if args.size() > 4 else DEF_OUT
	var focus: int = int(args[5]) if args.size() > 5 else -1

	# 必须实例化场景：Game 现在用 @onready 绑定 $Simulation/$World/Camera2D/...，
	# 直接 Game.new() 的话这些引用全是 null。
	var game: Game = preload("res://scenes/game.tscn").instantiate()
	add_child(game)
	game.setup(net_id, mode)
	await get_tree().process_frame

	var sim: Simulation = game.sim
	# 先把模拟跑够时间（乘客涌出来），再冻住它，免得截图时画面还在变
	game.paused_flag = true
	var dt := 1.0 / 60.0
	var steps := int(secs / dt)
	for i in range(steps):
		sim.tick(dt)
		if not sim.running:
			break

	# 接管相机：关掉控制器，自己摆到取景点并套用指定缩放
	var ctrl: CameraController = game.camera_ctrl
	if ctrl != null:
		ctrl.set_process(false)
	var cam: Camera2D = game.camera
	if cam != null:
		cam.zoom = Vector2(zoom, zoom)
		cam.position = _focus_point(sim, focus)

	# 可选：末尾参数带 "log" 时，顺手做几次操作并展开右侧运营日志，
	# 这样截图里能同时看到"事件 / 天气 / 操作"三类记录
	if "log" in args:
		sim.apply_operation("broadcast", -1)
		sim.apply_operation("limit", sim.lines[0].station_ids[1])
		sim.tick(dt * 60.0)
		if game.hud != null and game.hud.has_method("open_log"):
			game.hud.open_log()

	# 可选：末尾带 "select" 时选中一个站点（操作按钮只会在选中后出现）
	if "select" in args:
		var sid0: int = sim.lines[0].station_ids[mini(2, sim.lines[0].station_ids.size() - 1)]
		sim.selected_station_id = sid0
		EventBus.selection_changed.emit({"type": "station", "id": sid0})

	# 可选：末尾带 "float" 时制造一次明显的指标变化，好在截图里抓到"加减分飘字"
	if "float" in args:
		var busy := sim.lines[0].station_ids[1]
		for st in sim.stations:
			if st.queue.size() > 5:
				busy = st.id
				break
		sim.apply_operation("close", busy)
		for _i in range(30):
			sim.tick(dt)
			if not sim.running:
				break

	# 可选：末尾带 "storm" 时强制雷暴并立刻打一记闪电，
	# 用来核对"雷雨天闪闪灭灭"是否真的出现在画面上（第 1 帧亮、0.8 秒后那帧已灭）
	if "storm" in args:
		sim.weather.set_weather("thunderstorm", true)
		if game.screen_fx != null:
			game.screen_fx.pulse_flash(1.0)

	# 可选：末尾带 "dwell" 时推进到"某一列车正好靠站"，并把相机锁到它身上，
	# 用来核对"进站后车身仍在 + 环状剩余时间条 + 倒计秒数"这三件事
	if "dwell" in args and cam != null:
		var guard := 0
		var target: Train = null
		while guard < 6000 and target == null:
			guard += 1
			sim.tick(dt)
			if not sim.running:
				break
			for t in sim.trains:
				if t.state == Train.TrainState.DWELL and t.dwell_timer > 0.5:
					target = t
					break
		if target != null:
			var ln2: Line = sim.lines[target.line_id]
			cam.position = sim.stations[ln2.station_ids[target.to_idx]].position
			print("锁定靠站列车 id=%d 剩余 %.2fs" % [target.id, target.dwell_timer])

	# 让渲染层把这一帧画出来（两次重绘 + 一次等待比较稳）
	game.game_view.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img_a := get_viewport().get_texture().get_image()
	var err := img_a.save_png(out_path)
	print("已保存 %s  （%s / %s / zoom %.2f / %.0f 游戏秒 / 站点 %d / 活跃乘客 %d / 取景 %s）" % [
		out_path, net_id, mode, zoom, sim.elapsed, sim.stations.size(), sim.passengers.size(),
		_focus_desc(sim, focus)])

	# ---- 动效客观检验：冻住模拟后再抓一帧，像素差 > 0 就说明有东西在"自己动" ----
	if err != OK:
		print("保存失败 err=%d" % err)
		get_tree().quit(1)
		return
	await get_tree().create_timer(MOTION_WAIT).timeout
	await RenderingServer.frame_post_draw
	var img_b := get_viewport().get_texture().get_image()
	var b_path := "%s_b.png" % out_path.get_basename()
	img_b.save_png(b_path)
	print("动效检验：%.2fs 后第二帧 %s，像素差 %s（模拟已冻住，差异只可能来自着色器/自绘动画）" % [
		MOTION_WAIT, b_path, _pixel_diff(img_a, img_b)])
	get_tree().quit(0)


## 取景点：默认站点质心（一定落在路网内部），也可指定某一站
func _focus_point(sim: Simulation, focus: int) -> Vector2:
	if focus >= 0 and focus < sim.stations.size():
		return sim.stations[focus].position
	if sim.stations.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for st in sim.stations:
		sum += st.position
	return sum / float(sim.stations.size())


func _focus_desc(sim: Simulation, focus: int) -> String:
	if focus >= 0 and focus < sim.stations.size():
		return "站%d %s" % [focus, sim.stations[focus].name]
	return "站点质心"


## 逐通道比较两张图。**必须多档灵敏度**：背景点阵是"缓慢漂移"，单帧差只有 1~2/255，
## 用单一阈值（比如 >8）会得出"没有动效"的错误结论。
func _pixel_diff(a: Image, b: Image) -> String:
	if a.get_size() != b.get_size():
		return "尺寸不同，无法比较"
	var da := a.get_data()
	var db := b.get_data()
	if da.size() != db.size():
		return "数据长度不同，无法比较"
	var any_diff := 0
	var over8 := 0
	var mx := 0
	for i in range(da.size()):
		var d := absi(int(da[i]) - int(db[i]))
		if d > 0:
			any_diff += 1
		if d > mx:
			mx = d
		if d > 8:
			over8 += 1
	var total := float(da.size())
	return "任意变化 %d 字节（%.3f%%）｜>8 的 %d 字节（%.3f%%）｜最大通道差 %d/255" % [
		any_diff, 100.0 * float(any_diff) / total,
		over8, 100.0 * float(over8) / total, mx]
