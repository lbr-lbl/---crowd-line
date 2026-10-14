extends Node
## 无限模式验收（无头跑）。
##
## 跑法（PowerShell 5.1）：
##   $godot = "D:\下载\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
##   & $godot --headless --quit-after 300 --path "F:\Godot_project\涌线--crowd-line" res://tests/infinite_test.tscn
##
## 用 .tscn 而不是 -s：`-s script.gd` 模式不注册 autoload 命名全局，
## 引用 EventBus 的脚本（含 simulation.gd）根本编译不过。
##
## 验五件事：
##   1) 不看钟：无限模式没有"时间到"，普通模式仍然有
##   2) 每波扩张：加站、加线、新线有车、新站真的连进线网（BFS 可达，不是孤岛）
##   3) 数据表同步：station.id == 下标、spawn/dest 权重表长度 == 站点数、坐标不越界
##   4) 加压：基准客流、吞吐目标、事件密度随波次变化
##   5) 线路数不超过上限

const DT := 1.0 / 60.0

var _fails: int = 0
var _over_reason: String = ""


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("  [PASS] %s   %s" % [label, detail])
	else:
		_fails += 1
		print("  [FAIL] %s   %s" % [label, detail])


func _on_game_over(reason: String, _m: Dictionary) -> void:
	_over_reason = reason


func _ready() -> void:
	print("=========== 无限模式验收 ===========")
	EventBus.game_over.connect(_on_game_over)
	_test_timer()
	_test_expansion()
	_test_line_cap()
	_test_no_duplicate_corridor()
	_test_no_time_limit()
	_test_normal_mode_still_ends()
	print("=========== 失败 %d 项 ===========" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


## 把导演的每波间隔压到 0.5s，只验"计时器真的会推进波次"（含大 delta 不漏波）
func _test_timer() -> void:
	print("--- 计时器推进波次 ---")
	_over_reason = ""
	var sim := _new_sim("wenzhou_s1", "infinite")
	_check(sim.infinite_mode and sim.director != null, "无限模式装上导演")
	_check(is_equal_approx(sim.duration, 0.0), "duration == 0（不限时）", "%.0f" % sim.duration)

	sim.director.duration = 0.5
	sim.director.timer = 0.5
	var t := 0.0
	while t < 3.0:
		sim.tick(DT)
		t += DT
	_check(sim.director.wave >= 5, "3 秒内推进 >=5 波", "wave=%d" % sim.director.wave)

	# 一次超大 delta 也不能漏波（tick 里是 while 而不是 if）
	var before: int = sim.director.wave
	sim.director.timer = 0.01
	sim.tick(2.0)
	_check(sim.director.wave >= before + 3, "大 delta 不漏波", "%d -> %d" % [before, sim.director.wave])

	var p: float = sim.director.progress()
	_check(p >= 0.0 and p <= 1.0, "progress() 在 0..1", "%.3f" % p)
	_drop(sim)


## 每波扩张的硬不变量
func _test_expansion() -> void:
	print("--- 每波扩张 ---")
	_over_reason = ""
	var sim := _new_sim("wenzhou_s1", "infinite")
	var s0: int = sim.stations.size()
	var l0: int = sim.lines.size()
	var rate0: float = sim.base_spawn_rate
	var target0: float = sim.score.target_served
	var rect: Rect2 = sim._map_rect

	for i in range(5):
		sim.director.advance_wave()

	_check(sim.director.wave == 5, "波次计数", "wave=%d" % sim.director.wave)
	_check(sim.stations.size() > s0, "站点增加", "%d -> %d" % [s0, sim.stations.size()])
	_check(sim.lines.size() > l0, "线路增加", "%d -> %d" % [l0, sim.lines.size()])
	_check(sim.stations.size() == s0 + sim.director.stations_added, "加站数记账一致",
		"%d + %d" % [s0, sim.director.stations_added])
	_check(sim.lines.size() == l0 + sim.director.lines_added, "加线数记账一致",
		"%d + %d" % [l0, sim.director.lines_added])
	_check(sim.base_spawn_rate > rate0, "基准客流上升", "%.2f -> %.2f" % [rate0, sim.base_spawn_rate])
	_check(sim.score.target_served > target0, "吞吐目标上升", "%.0f -> %.0f" % [target0, sim.score.target_served])
	_check(sim.events.interval_scale < 1.0, "事件间隔被压紧", "scale=%.3f" % sim.events.interval_scale)

	# 新线不能是"有轨道没车"的空线
	var empty_lines: Array = []
	for ln in sim.lines:
		if ln.trains.is_empty():
			empty_lines.append(ln.id)
	_check(empty_lines.is_empty(), "每条线都有车", "空线 %s" % str(empty_lines))

	# 关键不变量：新站必须被同波新建的线接进线网，否则是永远没人能到的孤岛
	var reached := _reachable_count(sim)
	_check(reached == sim.stations.size(), "全站可达（新站不是孤岛）",
		"%d / %d" % [reached, sim.stations.size()])

	# 数据表同步
	_check(_ids_are_indices(sim), "station.id == 数组下标")
	_check(sim.spawn_weights.size() == sim.stations.size(), "spawn_weights 与站点数对齐",
		"%d / %d" % [sim.spawn_weights.size(), sim.stations.size()])
	_check(sim.dest_weights.size() == sim.stations.size(), "dest_weights 与站点数对齐",
		"%d / %d" % [sim.dest_weights.size(), sim.stations.size()])

	# 相机三段锚点是按初始地图算的，新站跑出外接矩形就会飘到视野外
	var outside := 0
	for st in sim.stations:
		if not rect.grow(1.0).has_point(st.position):
			outside += 1
	_check(outside == 0, "所有站点都在初始外接矩形内", "越界 %d 个" % outside)

	# 能真的跑起来（不检查胜负，只看不崩 + 乘客能找到路）
	var t := 0.0
	while t < 30.0 and sim.running:
		sim.tick(DT)
		t += DT
	var no_path := 0
	for p in sim.passengers:
		if p.path.is_empty():
			no_path += 1
	_check(no_path == 0, "扩张后仍有乘客能算出路径",
		"%.0fs 时活跃 %d 人，无路径 %d 人" % [sim.elapsed, sim.passengers.size(), no_path])
	_drop(sim)


## 线路数到上限后：不再加线加站，只继续加压
func _test_line_cap() -> void:
	print("--- 线路数上限 ---")
	var sim := _new_sim("taipei_cross", "infinite")
	var cap: int = int(Config.INFINITE["max_lines"])
	for i in range(cap * 4):
		sim.director.advance_wave()
	_check(sim.lines.size() <= cap, "线路数不超过上限", "%d <= %d" % [sim.lines.size(), cap])
	var reached := _reachable_count(sim)
	_check(reached == sim.stations.size(), "到上限后仍全站可达",
		"%d / %d" % [reached, sim.stations.size()])
	_check(sim.lines.size() == cap, "一直加压直到顶满线路上限", "lines=%d" % sim.lines.size())
	_drop(sim)


## 回归：**新加入的线不应和旧线整段重叠**（用户反馈"无限模式新加入的线会和之前的线重叠"）。
##
## 根因：`_walk_route` 原本是"走到最近的未访问站"，而一个站的**最近邻往往正是旧线连过的站**，
## 于是新线几乎是旧线的复制品。修法是重走旧走廊要乘 `REUSE_PENALTY`。
##
## 指标 = **重复走廊占比**：所有线的相邻站对里，被两条以上线共用的比例。
## 这条断言就是"把用户的观感反馈变成数字"——没有它，改完选路只能靠感觉说"应该好了"。
func _test_no_duplicate_corridor() -> void:
	print("--- 新线不重走旧走廊 ---")
	var sim := _new_sim("taipei_cross", "infinite")
	for _i in range(10):
		sim.director.advance_wave()
	var seen := {}
	var dup := 0
	var total := 0
	for ln in sim.lines:
		for i in range(ln.station_ids.size() - 1):
			var a: int = mini(int(ln.station_ids[i]), int(ln.station_ids[i + 1]))
			var b: int = maxi(int(ln.station_ids[i]), int(ln.station_ids[i + 1]))
			var key := "%d_%d" % [a, b]
			total += 1
			if seen.has(key):
				dup += 1
			seen[key] = true
	var frac := 0.0 if total == 0 else float(dup) / float(total)
	_check(frac < 0.40, "重复走廊占比 < 40%", "%d/%d = %.0f%%　线数=%d" % [
		dup, total, frac * 100.0, sim.lines.size()])
	_drop(sim)


## 无限模式跑过普通模式的总时长，也不会"时间到"
func _test_no_time_limit() -> void:
	print("--- 不看钟 ---")
	_over_reason = ""
	var sim := _new_sim("wenzhou_s1", "infinite")
	var limit: float = float(Config.DIFFICULTY["entry"]["duration"]) + 100.0
	var t := 0.0
	while t < limit and sim.running:
		sim.tick(DT)
		t += DT
	_check(_over_reason != "时间到", "跑过 %.0fs 没有触发\"时间到\"" % limit,
		"elapsed=%.0fs running=%s 结束原因=%s" % [sim.elapsed, str(sim.running), _over_reason])
	_drop(sim)


## 回归：普通模式仍然照旧按时结束（别把 duration 判定一起改坏）
func _test_normal_mode_still_ends() -> void:
	print("--- 普通模式回归 ---")
	_over_reason = ""
	var sim := _new_sim("wenzhou_s1", "entry")
	var t := 0.0
	while t < 400.0 and sim.running:
		sim.tick(DT)
		t += DT
	_check(_over_reason == "时间到", "入门局到点结束", "原因=%s elapsed=%.1fs" % [_over_reason, sim.elapsed])
	_check(absf(sim.elapsed - float(Config.DIFFICULTY["entry"]["duration"])) < 0.5,
		"结束时刻 == 配置时长", "%.1fs / %.0fs" % [sim.elapsed, float(Config.DIFFICULTY["entry"]["duration"])])
	_drop(sim)


func _new_sim(net_id: String, mode: String) -> Simulation:
	var sim := Simulation.new()
	add_child(sim)
	sim.setup(net_id, mode)
	return sim


func _drop(sim: Simulation) -> void:
	remove_child(sim)
	sim.free()


func _reachable_count(sim: Simulation) -> int:
	if sim.stations.is_empty():
		return 0
	var seen := {0: true}
	var q: Array[int] = [0]
	while not q.is_empty():
		var cur: int = q.pop_front()
		for nb in sim.adjacency.get(cur, []):
			if not seen.has(nb):
				seen[nb] = true
				q.append(nb)
	return seen.size()


func _ids_are_indices(sim: Simulation) -> bool:
	for i in range(sim.stations.size()):
		if sim.stations[i].id != i:
			return false
	return true
