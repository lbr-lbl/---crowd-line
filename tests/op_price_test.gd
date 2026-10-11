extends Node
## A/B/C/D 四项改造的定点验收（无头跑）。
##
## 跑法（PowerShell 5.1）：
##   $godot = "D:\下载\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
##   & $godot --headless --path "F:\Godot_project\涌线--crowd-line" res://tests/op_price_test.tscn
##
## 为什么用 .tscn 而不是 -s：`-s script.gd` 模式不注册 autoload 命名全局，
## 引用 EventBus 的脚本（含 simulation.gd）根本编译不过。
##
## 性质：纯读取 + 只调已有公开接口（apply_operation / depot_* 报价），不改游戏代码。

const DT := 1.0 / 60.0

var _fails: int = 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("  [PASS] %s   %s" % [label, detail])
	else:
		_fails += 1
		print("  [FAIL] %s   %s" % [label, detail])


func _ready() -> void:
	print("=========== A/B/C/D 定点验收 ===========")
	_test_op_prices()
	_test_depot_siting()
	_test_phase_pricing()
	_test_coupling()
	print("=========== 失败 %d 项 ===========" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


## D：四个操作各自扣费、资源不足时拒绝、广播冷却内不扣费
func _test_op_prices() -> void:
	print("--- D：操作定价 ---")
	var sim := Simulation.new()
	add_child(sim)
	sim.setup("wenzhou_s1", "entry")
	var sid: int = sim.lines[0].station_ids[0]

	for op in ["limit", "close", "skip"]:
		var before: float = sim.resources
		sim.apply_operation(op, sid)
		_check(is_equal_approx(sim.resources, before - Config.operation_cost(op)),
			"%s 扣 %d" % [op, int(Config.operation_cost(op))],
			"%.0f -> %.0f" % [before, sim.resources])

	var b0: float = sim.resources
	sim.apply_operation("broadcast", -1)
	_check(is_equal_approx(sim.resources, b0 - Config.operation_cost("broadcast")),
		"broadcast 扣 %d" % int(Config.operation_cost("broadcast")),
		"%.0f -> %.0f" % [b0, sim.resources])

	var b1: float = sim.resources
	sim.apply_operation("broadcast", -1)
	_check(is_equal_approx(sim.resources, b1), "广播冷却中不扣费", "仍为 %.0f" % sim.resources)

	sim.resources = 5.0
	var st: Station = sim.stations[sid]
	var limit_before: float = st.entry_limit
	sim.apply_operation("limit", sid)
	_check(is_equal_approx(sim.resources, 5.0) and is_equal_approx(st.entry_limit, limit_before),
		"资源不足时拒绝且不改状态", "资源 %.0f / entry_limit %.2f" % [sim.resources, st.entry_limit])
	sim.free()


## B：段站优先取 JSON 的 depot_station，否则取离线路中点最近的非换乘站
func _test_depot_siting() -> void:
	print("--- B：车辆段选址 ---")
	for net in ["wenzhou_s1", "lisbon_blue", "taipei_cross", "chongqing_net", "chengdu_net"]:
		var sim := Simulation.new()
		add_child(sim)
		sim.setup(net, "advance")
		for ln in sim.lines:
			var sid: int = ln.depot_station_id()
			if sid < 0:
				continue
			var st: Station = sim.stations[sid]
			var has_non_hub := false
			for s in ln.station_ids:
				if not sim.stations[s].is_interchange():
					has_non_hub = true
					break
			var ok: bool = (not st.is_interchange()) or (not has_non_hub)
			var tag := "换乘站" if st.is_interchange() else "非换乘"
			_check(ok, "%s / %s 段站" % [net, ln.name], "-> %s（%s，第 %d 站）" % [st.name, tag, ln.depot_station_idx])
		sim.free()


## C：同一笔加挂，平峰比高峰更便宜、占站台更短
func _test_phase_pricing() -> void:
	print("--- C：分时定价 ---")
	var sim := Simulation.new()
	add_child(sim)
	sim.setup("wenzhou_s1", "entry")
	sim.resources = 900.0
	var ln: Line = sim.lines[0]
	sim.apply_operation("upgrade_train", ln.id)  # 先建段，报价才进入"加挂"档
	var flat_cost := INF
	var peak_cost := -INF
	var flat_dwell := INF
	var peak_dwell := -INF
	var seen: Dictionary = {}
	while sim.elapsed < sim.duration:
		sim.tick(DT)
		var ph: String = sim.depot_phase()
		if seen.has(ph):
			continue
		seen[ph] = true
		var c: float = sim.depot_upgrade_cost(ln.id)
		var d: float = sim.depot_couple_dwell()
		print("    %s @ %.0fs：加挂 %.0f 资源 / 占站台 %.1fs" % [ph, sim.elapsed, c, d])
		if ph == "平峰":
			flat_cost = minf(flat_cost, c)
			flat_dwell = minf(flat_dwell, d)
		elif ph == "高峰":
			peak_cost = maxf(peak_cost, c)
			peak_dwell = maxf(peak_dwell, d)
	_check(flat_cost < peak_cost, "平峰加挂更便宜", "%.0f < %.0f" % [flat_cost, peak_cost])
	_check(flat_dwell < peak_dwell, "平峰占站台更短", "%.1fs < %.1fs" % [flat_dwell, peak_dwell])
	sim.free()


## A：下单不整列下线、不整批卸客、段站就地多停几秒后 +1 节
func _test_coupling() -> void:
	print("--- A：就地加挂 ---")
	var sim := Simulation.new()
	add_child(sim)
	sim.setup("wenzhou_s1", "entry")
	sim.resources = 900.0
	var ln: Line = sim.lines[0]
	var dsid: int = ln.depot_station_id()
	var dst: Station = sim.stations[dsid]

	# 先跑一会儿，让车上有乘客 —— 旧版"整列下线编组"会在这一刻把车上的人整批卸到段站台
	var warm: float = 0.0
	while warm < 45.0:
		sim.tick(DT)
		warm += DT

	var trains_before: int = ln.trains.size()
	var cars_before: int = ln.max_cars()

	var before_build: float = sim.resources
	sim.apply_operation("upgrade_train", ln.id)
	_check(ln.depot_built, "建段成功", "花费 %.0f（报价 %.0f）" % [before_build - sim.resources, sim.depot_build_cost(ln.id)])

	var onboard: int = 0
	for tr in ln.trains:
		onboard += tr.passengers.size()
	var q0: int = dst.queue.size()
	var before_order: float = sim.resources
	sim.apply_operation("upgrade_train", ln.id)
	_check(ln.pending_couples == 1, "加挂指令已下达",
		"花费 %.0f / pending=%d" % [before_order - sim.resources, ln.pending_couples])
	sim.tick(DT)
	_check(dst.queue.size() < q0 + maxi(onboard, 1),
		"下单不会把车上乘客卸到段站台",
		"车上 %d 人 / 段站队列 %d -> %d" % [onboard, q0, dst.queue.size()])

	# 跑到有车停靠段站并开工
	var guard: float = 0.0
	var started := false
	var q_prev: int = dst.queue.size()
	while guard < 900.0:
		q_prev = dst.queue.size()
		sim.tick(DT)
		guard += DT
		if _coupling_train(ln) != null:
			started = true
			_check(dst.queue.size() <= q_prev + 1, "开工瞬间没有整批卸客",
				"段站队列 %d -> %d" % [q_prev, dst.queue.size()])
			break
	_check(started, "有列车在段站就地加挂", "t=%.1fs" % guard)
	_check(ln.trains.size() == trains_before, "车队规模不变（没有车被抽走）",
		"%d -> %d" % [trains_before, ln.trains.size()])
	var ct: Train = _coupling_train(ln)
	if ct != null:
		_check(ct.couple_total > 0.0, "加挂有明确工时", "%.1fs（%s）" % [ct.couple_total, sim.depot_phase()])

	var guard2: float = 0.0
	while guard2 < 300.0 and ln.pending_couples > 0:
		sim.tick(DT)
		guard2 += DT
	var new_cars: int = ln.max_cars()
	_check(ln.pending_couples == 0, "指令已兑现", "%.1fs 后" % guard2)
	_check(new_cars == cars_before + 1, "编组 +1 节", "%d -> %d" % [cars_before, new_cars])
	var capped: bool = false
	for tr in ln.trains:
		if tr.cars == new_cars:
			capped = (tr.capacity == tr.cars * int(Config.DEPOT["car_capacity"]))
	_check(capped, "定员 = 节数 × 每节定员", "最大编组 %d 节" % new_cars)
	sim.free()


func _coupling_train(ln: Line) -> Train:
	for t in ln.trains:
		if t.coupling:
			return t
	return null
