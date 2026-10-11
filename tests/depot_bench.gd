extends Node
## 车辆段手感基准工具（无头跑局）。
##
## 跑法（PowerShell 5.1）：
##   $godot = "D:\下载\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
##   & $godot --headless --path "F:\Godot_project\涌线--crowd-line" res://tests/depot_bench.tscn
## 只跑指定组合：
##   & $godot --headless --path "..." res://tests/depot_bench.tscn -- wenzhou_s1/entry/none
##
## 为什么用 .tscn 而不是 -s：`-s script.gd` 模式不注册 autoload 命名全局，
## 引用 EventBus 的脚本（含 simulation.gd）根本编译不过。跑场景才是正常启动路径。
##
## 性质：纯读取。只用模拟层公开字段与已有 apply_operation 接口，
## 不修改任何游戏代码，不写存档。

const DT := 1.0 / 60.0  # 与 game.gd 的 tick(delta) 一致

# [线网 id, 难度池, 策略]；策略 none = 从不建段，greedy = 有钱就点，late = 后半程才点
const CASES := [
	["wenzhou_s1", "entry", "none"],
	["wenzhou_s1", "entry", "greedy"],
	["wenzhou_s1", "entry", "late"],
	["lisbon_blue", "entry", "none"],
	["lisbon_blue", "entry", "greedy"],
	["taipei_cross", "advance", "none"],
	["taipei_cross", "advance", "greedy"],
	["chongqing_net", "hardcore", "none"],
	["chongqing_net", "hardcore", "greedy"],
	["chongqing_net", "hardcore", "late"],
]

var _stampedes: int = 0
var _reason: String = ""
var _phase_hist: Dictionary = {}  # 加挂指令下达时处于哪个时段（验证"分时规划"是否真的被用上）


func _ready() -> void:
	EventBus.stampede.connect(_on_stampede)
	EventBus.game_over.connect(_on_game_over)

	var cases: Array = []
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0:
		for s in user_args:
			var parts: PackedStringArray = String(s).split("/")
			if parts.size() == 3:
				cases.append([parts[0], parts[1], parts[2]])
			elif parts.size() == 4:
				cases.append([parts[0], parts[1], parts[2], int(parts[3])])
	else:
		cases = CASES

	print("=========== 车辆段基准开始（%d 个组合）===========" % cases.size())
	for c in cases:
		_run(c[0], c[1], c[2], int(c[3]) if c.size() > 3 else 0)
	print("=========== 车辆段基准结束 ===========")
	get_tree().quit()


func _on_stampede(_sid: int) -> void:
	_stampedes += 1


func _on_game_over(reason: String, _m: Dictionary) -> void:
	if _reason == "":
		_reason = reason


func _run(net_id: String, mode: String, policy: String, run_seed: int = 0) -> void:
	_stampedes = 0
	_reason = ""
	seed(run_seed if run_seed != 0 else 20261021)  # 同种子下三种策略看到同一串客流

	var sim := Simulation.new()
	add_child(sim)
	sim.setup(net_id, mode)

	var init_res: float = sim.resources
	var spent: float = 0.0
	var buys: int = 0
	var max_unload: int = 0
	var total_unload: int = 0
	var couple_seconds: float = 0.0
	_phase_hist.clear()
	var max_cars: int = int(Config.DEPOT["min_cars"])
	var peak_dens: float = 0.0
	var peak_dens_st: int = -1
	var peak_dens_t: float = 0.0
	var peak_backlog: int = 0
	var peak_backlog_t: float = 0.0
	var depot_q_peak: int = 0

	var t: float = 0.0
	var next_sample: float = 0.0
	var stop_at: float = sim.duration + 2.0
	var wall0 := Time.get_ticks_msec()

	while sim.running and t < stop_at:
		sim.tick(DT)
		t += DT

		if policy == "build":
			# 只建段、从不下达加挂指令：隔离"花钱建段"本身的收益（段本身不改变运力）
			var rb: Array = _policy(sim, true)
			spent += float(rb[0])
			buys += int(rb[1])
		elif policy == "greedy" or (policy == "late" and t > sim.duration * 0.6):
			var r: Array = _policy(sim)
			spent += float(r[0])
			buys += int(r[1])
			if int(r[2]) > max_unload:
				max_unload = int(r[2])
			total_unload += int(r[2])
		elif policy == "offpeak" and sim.depot_phase() != "高峰":
			# C 的验证策略：只在非高峰出手 —— 同样一笔钱，买到的站台占用时间更短、价格更低
			var ro: Array = _policy(sim)
			spent += float(ro[0])
			buys += int(ro[1])

		if t >= next_sample:
			next_sample = t + 0.5
			var backlog: int = 0
			for st in sim.stations:
				backlog += st.queue.size()
				var d: float = st.density()
				if d > peak_dens:
					peak_dens = d
					peak_dens_st = st.id
					peak_dens_t = t
			if backlog > peak_backlog:
				peak_backlog = backlog
				peak_backlog_t = t
			for tr in sim.trains:
				if tr.coupling:
					couple_seconds += 0.5

		for ln in sim.lines:
			if ln.max_cars() > max_cars:
				max_cars = ln.max_cars()
			if ln.depot_built:
				var q: int = sim.stations[ln.depot_station_id()].queue.size()
				if q > depot_q_peak:
					depot_q_peak = q

	var sc: ScoreSystem = sim.score
	var wall_ms := Time.get_ticks_msec() - wall0
	print("--- %s / %s / %s" % [net_id, mode, policy])
	print("    结局 %s @ %.1fs（时长 %.0fs）  资源 %.1f（初始 %.0f，实投 %.0f）" % [
		_reason, t, sim.duration, sim.resources, init_res, spent])
	print("    服务 %d 人  吞吐比 %.2f  准点 %.2f  满意 %.2f  安全 %.2f  效率 %.2f  总分 %.0f  评级 %s" % [
		sc.served, sc.throughput_ratio(), sc.punctuality(), sc.satisfaction(),
		sc.safety, sc.efficiency(), sc.total_score(),
		Config.rating_for_score(sc.total_score())])
	print("    峰值密度 %.3f（站 %d）@ %.1fs   峰值积压 %d 人 @ %.1fs   段站最长队列 %d" % [
		peak_dens, peak_dens_st, peak_dens_t, peak_backlog, peak_backlog_t, depot_q_peak])
	print("    踩踏 %d 次   最大编组 %d 节   建段/加挂指令 %d 次   加挂占站台合计 %.1f s" % [
		_stampedes, max_cars, buys, couple_seconds])
	print("    指令时段分布 %s   单次最大卸客 %d 人   累计卸客 %d 人" % [
		_hist_text(), max_unload, total_unload])
	print("    单局耗时 %.1f s" % (float(wall_ms) / 1000.0))

	sim.free()


## 返回 [本次花费, 是否成交(0/1), 本次卸客数]
func _policy(sim: Simulation, build_only: bool = false) -> Array:
	# 1) 铺开优先：还有没建段的线，够钱就建
	for ln in sim.lines:
		if ln.depot_built:
			continue
		if sim.resources >= sim.depot_build_cost(ln.id):
			var before := sim.resources
			sim.apply_operation("upgrade_train", ln.id)
			if sim.resources < before:
				return [before - sim.resources, 1, 0]
			return [0.0, 0, 0]

	if build_only:
		return [0.0, 0, 0]

	# 2) 加挂：挑已加挂次数最少的线（无未兑现指令、未到上限）
	var best = null
	for ln in sim.lines:
		if not ln.depot_built:
			continue
		if sim.depot_busy(ln.id):
			continue
		if ln.max_cars() >= int(Config.DEPOT["max_cars"]):
			continue
		if best == null or ln.depot_upgrades < best.depot_upgrades:
			best = ln
	if best == null:
		return [0.0, 0, 0]
	if sim.resources < sim.depot_upgrade_cost(best.id):
		return [0.0, 0, 0]

	var sid: int = best.depot_station_id()
	var q0: int = sim.stations[sid].queue.size()
	var before2 := sim.resources
	sim.apply_operation("upgrade_train", best.id)
	if sim.resources < before2:
		var ph: String = sim.depot_phase()
		_phase_hist[ph] = int(_phase_hist.get(ph, 0)) + 1
		var q1: int = sim.stations[sid].queue.size()
		return [before2 - sim.resources, 1, maxi(0, q1 - q0)]
	return [0.0, 0, 0]


func _hist_text() -> String:
	var parts: Array = []
	for k in ["平峰", "常态", "高峰"]:
		if _phase_hist.has(k):
			parts.append("%s %d" % [k, int(_phase_hist[k])])
	return ", ".join(PackedStringArray(parts)) if not parts.is_empty() else "无"
