extends Node
## 相机视野段行为：M 段吸附到最近站、L 段把相机夹在预选站附近。
##
## 为什么要单列一节：截图工具会 `set_process(false)` 关掉相机控制器，
## 所以这两条行为**在截图里永远验证不到**，只能直接把 `_process` 跑起来看状态。
func _check_camera_bands(game: Game) -> void:
	print("--- 相机视野段行为 ---")
	var cc: CameraController = game.camera_ctrl
	var sim: Simulation = game.sim
	if cc == null or sim == null or sim.stations.is_empty():
		print("  !! 缺相机或模拟，跳过")
		return
	var st: Station = sim.stations[2]
	# M 段：把相机放在该站附近偏一点，跑若干帧，看它是否收向站心、预选是否命中
	cc.dragging = false
	cc.target_zoom = cc.mid_zoom
	cc.target_pos = st.position + Vector2(30.0, 12.0)
	for _i in range(150):
		cc._process(0.016)
	var d0: float = (cc.target_pos - st.position).length()
	var hit: bool = cc.preselect_sid == st.id
	print("  M 段：预选站命中 = %s（应为 %s）　偏离 %.2f 世界单位　%s" % [
		str(hit), str(st.id), d0, "✓" if hit and d0 < 6.0 else "✗ 没吸附上"])
	# L 段：把目标挪到很远，看是否被夹回"**锁定站**"周围的框里。
	# ⚠ 两个要点，都是被现实打过脸才写下来的：
	#   1. 断言必须相对**锁定站**（preselect_sid），不能相对一开始挑的那个 st ——
	#      挪远之后最近的站会换成邻站，拿 st 去比就会误报"没夹住"；
	#   2. 断言必须**按分量**：x 允许 ±FORE_RANGE_X（沿站台可走）、
	#      y 只允许 ±FORE_RANGE_Y（垂直方向夹紧 = "始终在站点里"）。
	cc.target_zoom = cc.fore_zoom
	cc.target_pos = st.position + Vector2(200.0, 90.0)
	for _i in range(40):
		cc._process(0.016)
	var anchor_st: Station = sim.get_station(cc.preselect_sid)
	if anchor_st == null:
		print("  L 段：没有锁定站 ✗")
		return
	var dv1: Vector2 = cc.target_pos - anchor_st.position
	var ok1: bool = absf(dv1.x) <= cc.FORE_RANGE_X + 0.5 and absf(dv1.y) <= cc.FORE_RANGE_Y + 0.5
	print("  L 段：锁定站 %d　偏移 (%.1f, %.1f)　限值 (±%.0f, ±%.0f)　%s" % [
		cc.preselect_sid, dv1.x, dv1.y, cc.FORE_RANGE_X, cc.FORE_RANGE_Y,
		"✓ 夹住了" if ok1 else "✗ 没夹住"])

	# M -> L：**放大要落到聚焦的那个站**（用户要求）
	# 先回到 M 段并吸到该站，再连按几次"滚轮放大"，看最后是否停在该站附近
	cc.target_zoom = cc.mid_zoom
	cc.target_pos = st.position + Vector2(25.0, 10.0)
	for _i in range(150):
		cc._process(0.016)
	var focused: int = cc.preselect_sid
	for _i in range(6):
		cc._zoom_gesture(1.2)
	for _i in range(200):
		cc._process(0.016)
	var dst: Station = sim.get_station(focused)
	var d2: float = 9999.0
	if dst != null:
		d2 = (cc.target_pos - dst.position).length()
	print("  M→L 放大：聚焦站 %d　最终偏离 %.2f　%s" % [
		focused, d2, "✓ 落在聚焦站上" if d2 <= 6.0 else "✗ 跑偏了"])


## 操作面板可见性规则：**相机带出来的"预选"不算玩家选择**，
## 所以从 L 缩回 M 之后不会留着一个面板（用户反馈过两次，值得钉住）。
func _check_panel_visibility(game: Game) -> void:
	print("--- 操作面板可见性 ---")
	var hud: HUD = game.hud
	if hud == null or game.sim == null or game.sim.stations.is_empty():
		print("  !! 缺 HUD/模拟，跳过")
		return
	var sid: int = game.sim.stations[2].id
	EventBus.selection_changed.emit({"type": "preselect", "id": sid})
	print("  预选（相机带出来的）　_user_selected = %s（应 false）　%s" % [
		str(hud._user_selected), "✓" if not hud._user_selected else "✗ 会被误当成玩家点选"])
	EventBus.selection_changed.emit({"type": "station", "id": sid})
	print("  玩家点选　　　　　　　_user_selected = %s（应 true）　%s" % [
		str(hud._user_selected), "✓" if hud._user_selected else "✗"])
	EventBus.selection_changed.emit({"type": "none", "id": -1})
	print("  取消选择　　　　　　　_user_selected = %s（应 false）　%s" % [
		str(hud._user_selected), "✓" if not hud._user_selected else "✗"])


## 滑钮映射：三个锚点应分别落在滑轨的 0 / 0.5 / 1
## （用户要求："滑钮按钮 M 视野时在滑轨的中间"）。
func _check_slider_mapping(game: Game) -> void:
	print("--- 视野滑钮映射 ---")
	var vs: ViewSlider = game.hud.view_slider if game.hud != null else null
	if vs == null:
		print("  !! 缺滑钮，跳过")
		return
	var b: Vector3 = vs.bands
	var t0: float = vs.t_of_zoom(b.x)
	var t1: float = vs.t_of_zoom(b.y)
	var t2: float = vs.t_of_zoom(b.z)
	print("  H t=%.3f（应 0.0）　M t=%.3f（应 0.5）　L t=%.3f（应 1.0）　%s" % [
		t0, t1, t2,
		"✓" if absf(t0) < 0.02 and absf(t1 - 0.5) < 0.02 and absf(t2 - 1.0) < 0.02 else "✗ 锚点没对齐"])


## 运行时接线自检：把"引擎实际解析出来的东西"打出来，而不是看 .tscn/.gd 里写了什么。
##
## 为什么需要它：有两类 bug 在 Godot 里**完全静默**——
##   1. `theme` 只有 Control / Window 才有。挂在 CanvasLayer 上会被无声忽略，
##      整棵 UI 回落到默认深色主题（浅色面板变灰、深色字看不见）。
##   2. 渲染层之间的数据线（`layer.sim = sim`）如果没人接，节点就什么都不画，
##      或者只画了一半（比如着色器没挂上 → 动效全无）。
## 这两类都不会报错，所以必须主动问引擎。
##
## 跑法：
##   & $godot --headless --quit-after 300 --path <root> res://tests/wiring_probe.tscn

func _ready() -> void:
	var game: Game = preload("res://scenes/game.tscn").instantiate()
	add_child(game)
	game.setup("hongkong_tw_kt", "advance")
	await get_tree().process_frame
	# 让渲染层跑几帧，_process 里才会建子节点
	for _i in range(5):
		await get_tree().process_frame

	_check_hud_theme(game)
	_check_render_wiring(game)
	_check_train_positions(game)
	_check_camera_bands(game)
	_check_panel_visibility(game)
	_check_slider_mapping(game)
	_check_scene_completeness(game)
	get_tree().quit(0)


## 列车是否画在"自己那条线"上。
## 背景：`Train.from_idx`/`to_idx` 是**本线 `station_ids` 的下标**，不是全局站点 id。
## 曾经写成 `sim.stations[t.from_idx]`，于是每条线的列车都被画到"全局第 N 号站"上，
## 而低编号站全属于第一条线 → 用户看到的是"所有列车莫名挤在一条线路上"。
## 这里**不复用被修的实现**，测试里自己再算一遍期望位置，所以能真正盯住这个回归。
func _check_train_positions(game: Game) -> void:
	print("=========== 4. 列车是否画在自己线上 ===========")
	var sim: Simulation = game.sim
	var train_layer: Node = game.get_node_or_null("World/TrainLayer")
	if sim == null or train_layer == null:
		print("  !! 找不到 sim / TrainLayer")
		return
	# 站点现在是多线共用的**长条胶囊体**，列车停在"自己那条线的泊位"上，
	# 会沿长轴偏离站点中心一点点。所以判据是"离本线这一段的距离"，不是"精确等于插值点"。
	# 上限按"最多每条线一格"给，仍然远小于"跑到别的线的站点上"（那会差几百）。
	var tol := Config.view_px(RouteGeometry.LANE_GAP_PX, 1.0) * float(maxi(1, sim.lines.size())) + 3.0
	var checked := 0
	var bad := 0
	var views := 0
	for c in train_layer.get_children():
		if not (c is LineTrainView):
			continue
		views += 1
		var v := c as LineTrainView
		var ln: Line = v.line
		if ln == null:
			continue
		for t in ln.trains:
			checked += 1
			if t.from_idx < 0 or t.from_idx >= ln.station_ids.size():
				continue
			if t.to_idx < 0 or t.to_idx >= ln.station_ids.size():
				continue
			# 独立复算：这里必须经过 line.station_ids 间接寻址（这正是当年画错的原因）
			var a: Vector2 = sim.stations[ln.station_ids[t.from_idx]].position
			var b: Vector2 = sim.stations[ln.station_ids[t.to_idx]].position
			var got: Vector2 = v.train_position(t)
			var d := _dist_to_seg(got, a, b)
			if d > tol:
				bad += 1
				if bad <= 3:
					print("    ✗ %s 的车 id=%d 画在 (%.0f,%.0f)，离本线该段 %.0f（上限 %.0f）" % [
						ln.name, t.id, got.x, got.y, d, tol])
	print("  LineTrainView=%d 个 · 检查 %d 列车 · 偏离本线 %d 列 %s" % [
		views, checked, bad, "✓" if bad == 0 else "← 索引映射又错了"])
	var wrong_line := 0
	for c in train_layer.get_children():
		if not (c is LineTrainView):
			continue
		var v2 := c as LineTrainView
		if v2.line == null:
			continue
		for t2 in v2.line.trains:
			var pos := v2.train_position(t2)
			var own := _dist_to_line(sim, v2.line, pos)
			var best_other := INF
			for other in sim.lines:
				if other.id == v2.line.id:
					continue
				best_other = minf(best_other, _dist_to_line(sim, other, pos))
			if best_other < own:
				wrong_line += 1
	print("  离别的线比离自己线更近的列车：%d 列 %s" % [
		wrong_line, "✓" if wrong_line == 0 else "← 这就是「所有车挤在一条线」的成因"])

	# 自证有效性：如果按**旧的错误写法**（直接 sim.stations[t.from_idx]，漏掉 station_ids 间接寻址）
	# 算，会有多少列车被画到别的地方？这个数是 0 就说明本断言是空转的、没有牙。
	var would_be_wrong := 0
	var total2 := 0
	for c in train_layer.get_children():
		if not (c is LineTrainView):
			continue
		var v3 := c as LineTrainView
		if v3.line == null:
			continue
		var ln3: Line = v3.line
		for t3 in ln3.trains:
			if t3.from_idx < 0 or t3.from_idx >= ln3.station_ids.size():
				continue
			total2 += 1
			var want3: Vector2 = v3.train_position(t3)
			var buggy: Vector2 = sim.stations[t3.from_idx].position  # ← 旧写法
			if buggy.distance_to(want3) > 0.5:
				would_be_wrong += 1
	print("  自证：按旧写法直取 sim.stations[t.from_idx] 会有 %d/%d 列车画错 %s" % [
		would_be_wrong, total2,
		"（断言有效 ✓，能抓住这个回归）" if would_be_wrong > 0 else "（⚠ 空转！本样本区分不出来，要换线网）"])


func _dist_to_line(sim: Simulation, ln: Line, p: Vector2) -> float:
	var best := INF
	for i in range(ln.station_ids.size() - 1):
		var a: Vector2 = sim.stations[ln.station_ids[i]].position
		var b: Vector2 = sim.stations[ln.station_ids[i + 1]].position
		best = minf(best, _dist_to_seg(p, a, b))
	return best


func _dist_to_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _check_hud_theme(game: Game) -> void:
	print("=========== 1. HUD 主题是否真的生效 ===========")
	var hud: CanvasLayer = game.get_node_or_null("HUD")
	if hud == null:
		print("  !! 找不到 HUD")
		return
	print("  HUD 是 %s，有 theme 属性 = %s（CanvasLayer 必然为 false，"
		% [hud.get_class(), hud.has_method("get_theme_stylebox")] + "所以主题必须挂在 Control 上）")
	# 需求："评级 / 顶部时间不要背景面板" -> 这两张卡应挂 StyleBoxEmpty（无底板）；
	# 指标 / 日志是大段文字，仍必须是浅色卡片（有底板、且亮度高）。
	# 注：本工具是**打印式巡检**（没有断言、永远 quit(0)），所以判断结果直接写在行末。
	var want_empty := {"RatingPanel": true, "TimePanel": true, "OpPanel": true, "MetricsPanel": false}
	for path in want_empty.keys():
		var n: Control = hud.get_node_or_null(path)
		if n == null:
			print("  %-14s 找不到" % path)
			continue
		var sb := n.get_theme_stylebox("panel")
		var lum := -1.0
		if sb is StyleBoxFlat:
			lum = (sb as StyleBoxFlat).bg_color.get_luminance()
		var empty_wanted: bool = want_empty[path]
		var verdict := ""
		if empty_wanted:
			verdict = "（去底板 ✓）" if sb is StyleBoxEmpty else "（本该去底板 ✗）"
		else:
			verdict = "（浅色卡片 亮度=%.2f ✓）" % lum if lum > 0.7 else "（深色！主题没生效 ✗）"
		print("  %-14s stylebox=%-14s %s" % [path, sb.get_class(), verdict])

	var btn: Button = hud.get_node_or_null("OpPanel/OpBox/OpRow/LimitButton")
	if btn != null:
		# 按钮也去掉了底板，可读性靠深色字 + 浅色字阴影
		print("  LimitButton  stylebox=%s  字色=%s  阴影=%s" % [
			btn.get_theme_stylebox("normal").get_class(),
			str(btn.get_theme_color("font_color")),
			str(btn.get_theme_color("font_shadow_color"))])
		print("  LimitButton  图标色 normal=%s disabled=%s（图标是白底透明图，浅色底上必须染色）" % [
			str(btn.get_theme_color("icon_normal_color")), str(btn.get_theme_color("icon_disabled_color"))])


func _check_render_wiring(game: Game) -> void:
	print("=========== 2. 渲染层数据线与材质 ===========")
	var pairs := [
		["World/GameView", "game_view"],
		["World/PassengerLayer", "passenger_layer"],
		["World/TrainLayer", "train_layer"],
	]
	for p in pairs:
		var n: Node = game.get_node_or_null(p[0])
		if n == null:
			print("  %-22s 找不到" % p[0])
			continue
		var has_sim := n.get("sim") != null
		var mat: Material = n.get("material") if n is CanvasItem else null
		var mdesc := "无材质"
		if mat is ShaderMaterial:
			var sh := (mat as ShaderMaterial).shader
			mdesc = "ShaderMaterial(%s)" % (sh.resource_path if sh != null else "无 shader")
		print("  %-22s sim接线=%-5s %s" % [p[0], str(has_sim), mdesc])

	var train_layer: Node = game.get_node_or_null("World/TrainLayer")
	if train_layer != null:
		var views := 0
		for c in train_layer.get_children():
			if c is LineTrainView:
				views += 1
		print("  TrainLayer 子节点 LineTrainView = %d 个（每条线一个；为 0 说明 _sync_views 没跑或 sim 没接）" % views)
		for c in train_layer.get_children():
			if c is LineTrainView:
				var m: Material = c.material
				var spd := {}
				print("    %s  材质=%s  线色=%s" % [
					c.name, "有" if m is ShaderMaterial else "无", str(c.body_color)])

	var paper: Node = game.get_node_or_null("BackgroundLayer/Paper")
	if paper != null:
		var m: Material = paper.get("material")
		print("  BackgroundLayer/Paper  材质=%s" % ("有 ShaderMaterial" if m is ShaderMaterial else "无/不是 ShaderMaterial"))
		if m is ShaderMaterial:
			var sm := m as ShaderMaterial
			for pname in ["top_color", "bottom_color", "grid_alpha", "mood", "drift", "cam_offset"]:
				print("    uniform %-14s = %s" % [pname, str(sm.get_shader_parameter(pname))])

	var bg_layer: Node = game.get_node_or_null("BackgroundLayer")
	if bg_layer != null:
		print("  BackgroundLayer 脚本 = %s" % ("有" if bg_layer.get_script() != null else "无"))


func _check_scene_completeness(game: Game) -> void:
	print("=========== 3. 场景完整性（需求 4：编辑器里看得见）===========")
	print("  Game 子节点：")
	for c in game.get_children():
		var kind := c.get_class()
		print("    %-18s %s" % [c.name, kind])
	print("  World 子节点：")
	var world: Node = game.get_node_or_null("World")
	if world != null:
		for c in world.get_children():
			print("    %-18s %s" % [c.name, c.get_class()])
	print("  Camera2D = %s  enabled=%s  zoom=%s" % [
		str(game.camera != null),
		str((game.camera as Camera2D).enabled) if game.camera != null else "?",
		str((game.camera as Camera2D).zoom) if game.camera != null else "?"])
