class_name PassengerLayer
extends Node2D
## 站台上的乘客小点。点走 shaders/passenger_dot.gdshader（呼吸 + 涟漪），
## 相位由点在世界里的位置推出，所以不会整齐划一地闪。
## 全貌段（云段）不画点：那一段由 GameView 画成分云。

const GOLDEN_ANGLE := 2.39996323
const DOT_TEXTURE := "res://assets/icons/passenger_dot.png"
const DOT_SHADER := "res://shaders/passenger_dot.gdshader"

var sim: Simulation = null
var camera: Camera2D = null
var game_view: GameView = null

## 贴图可以在场景里指定；为空时按 DOT_TEXTURE 兜底加载。
@export var dot_texture: Texture2D = null

var _cloud_zoom_lo := 0.6
var _cloud_zoom_hi := 0.95
## 层材质（用来每帧写 `press`）
var _mat: ShaderMaterial = null


func _ready() -> void:
	# 动效的关键：着色器必须挂在 CanvasItem 上。`_draw()` 里单次 `draw_*` 是没法
	# 各自带材质的，但**整个层的材质会作用于这一层的每一次绘制**——所以每个点的
	# UV（贴图内归一化坐标）、COLOR（modulate）、VERTEX（点在世界里的位置）依然各自独立，
	# 涟漪相位由 VERTEX 推出，同屏的点不会齐刷刷一起闪。
	if ResourceLoader.exists(DOT_SHADER):
		var mat := ShaderMaterial.new()
		mat.shader = load(DOT_SHADER)
		material = mat
		_mat = mat
	set_process(true)


## L 视野下乘客"在站台里走来走去"用的时间累积（秒）。
## 自己累加 delta，不依赖模拟时钟，也不依赖着色器的 TIME —— 位置得由这一层算。
var _t: float = 0.0

## 上一个被展开的站：换站时要把"上一帧队列"和上下车表现清掉，
## 否则会把上一站的人全判成"刚从本站上车"。
var _prev_station: int = -1

## 上一帧本站等车的人（用乘客对象本身当键，避免依赖 Passenger.id 这种字段）：对象 -> 位置
var _prev_q: Dictionary = {}
## 上一帧每人**被分配到的闸机**（上车路径要用它，保证前后一致）
var _prev_gate: Dictionary = {}
## 上一帧**未过滤**的等车集合。用来区分"刚下车的人"和"因为寻路重算才变合格的人"：
## 后者上一帧也在等车，只是没被这条线的过滤选中，不该播下车动画。
var _prev_all: Dictionary = {}
## 上下车的一次性表现：{from, to, t, dur, col}
var _fx: Array = []
## 一次上下车表现持续多久（秒）。
## **必须够长**（原来 0.45）：太短的话人瞬间就"上车"了，看不到挤的过程（用户反馈）。
const FX_DUR := 1.0
## 同批上车的人**错开出发**，形成一条人流而不是整批一起消失
const FX_STAGGER := 0.07


func _process(delta: float) -> void:
	_t += delta
	# 上下车表现的推进与回收（放在 _process 里，这样不画的时候也在走）
	if not _fx.is_empty():
		var alive: Array = []
		for fx in _fx:
			fx["t"] = float(fx["t"]) + delta
			if float(fx["t"]) < float(fx.get("delay", 0.0)) + FX_DUR:
				alive.append(fx)
		_fx = alive
	# 把"全图最挤的那个站"喂给着色器，用来驱动**拥挤推挤**的强度。
	# 一个材质作用于全层，所以做不到"每个乘客各自的拥挤度"，
	# 但"越挤大家越躁动"这个整体观感是成立的，也是涌现感最需要的那一层。
	if _mat != null and sim != null:
		var press := 0.0
		for st in sim.stations:
			press = maxf(press, clampf(st.overflow_ratio(), 0.0, 1.0))
		_mat.set_shader_parameter("press", press)
		# 展开度：M 视野是圆点，L 视野展开成"圆头 + 三角身"（单个乘客的外观插值）
		var zoom := camera.zoom.x if camera != null else 1.0
		_mat.set_shader_parameter("figure", _detail(zoom))
		# 摇摆幅度：站台上的人在走动，所以左右摇摆是开着的（用户要求"移动时左右摇摆"）
		_mat.set_shader_parameter("walk_amt", 0.7)
	queue_redraw()


func _draw() -> void:
	if sim == null or sim.time == null:
		return
	var zoom := camera.zoom.x if camera != null else 1.0
	var cloud := _cloud_blend(zoom)
	var alpha := 1.0 - cloud
	if alpha <= 0.01:
		return
	var tex := _texture()
	if tex == null:
		return

	var detail := _detail(zoom)
	# **L 视野（站台视图）走独立分支**：
	#   · 只画本站 -> 沿站台滑动不会看到邻站的人（需求）
	#   · 只画当前线 -> 切换线色圆点时看到的人不一样（需求）
	#   · 分上下站台站人 -> 人**站在站台上**，不再飘在点簇位置（需求）
	if game_view != null and game_view.interior_active():
		_draw_interior(alpha)
		return

	# 尺寸补偿的两条不同规则（对应"放大 = 把东西拉开，而不是画大"）：
	#   · 符号本身（点的大小）和"贴住站环"的基准偏移 → `view_px`，屏幕上恒定大小
	#   · 人群的散布半径 → `view_spread`（√zoom），屏幕上缓慢拉开：
	#     放大能看清一个个乘客，但人还围着本站，不会撒得满屏都是、看不出谁在哪等车
	var z := maxf(zoom, 0.001)
	# 站的尺寸要与 GameView._draw_stations 一致，点才落在站里
	for st in sim.stations:
		if st.queue.is_empty():
			continue
		var base_half := clampf(6.0 + st.effective_capacity() / 40.0, 7.0, 16.0)
		var base_r := Config.view_px(base_half, z)
		if game_view != null:
			# 站点可能是**长条胶囊体**（多线共用的站），点簇要躲开它，
			# 半径必须用同一份轨道几何算，否则点会糊在胶囊上
			base_r = game_view.route_geo.cluster_radius(sim, st.id, base_half, z)
		var spread := Config.view_spread(lerpf(3.0, 4.2, detail), z)
		var max_r := Config.view_spread(
			lerpf(34.0, 46.0, detail) + clampf(st.overflow_ratio(), 0.0, 2.0) * 14.0, z)
		var dot_r := Config.view_px(lerpf(3.0, 3.6, detail), z)
		var i := 0
		for p in st.queue:
			if p.state != Passenger.State.WAITING:
				i += 1
				continue
			var ang := float(i) * GOLDEN_ANGLE
			var off := Vector2(cos(ang), sin(ang)) * minf(
				base_r + Config.view_px(8.0, z) + sqrt(float(i)) * spread, max_r)
			# 新加入的人**由外向内浮现**（需求）：
			# 拿"耐心还剩多少"当年龄用（刚生成时耐心接近满）—— 这样**不用给 Passenger 加字段、
			# 也不动模拟层**。在最初的一小段生命周期里，从站外一圈往站台里收，
			# 同时由小变大、由透明变实。
			var age := clampf(1.0 - p.patience, 0.0, 1.0)
			var appear := clampf(age / 0.16, 0.0, 1.0)
			if appear <= 0.02:
				i += 1
				continue
			off *= lerpf(1.9, 1.0, appear)
			# 用户澄清："乘客铺开"指的是**单个乘客**由 M 视野下的圆点
			# 展开成 L 视野下的"圆头 + 三角身" —— 是**外观**在插值，位置不变。
			# 外观由着色器的 `figure` 决定；这里同时把方块放大一点，
			# 因为"一个人"本来就该比一个点大（不然头身比例会挤成一小团）。
			var col := _dot_color(p, st)
			col.a = alpha * appear
			var side := dot_r * 2.3 * lerpf(0.45, 1.0, appear) * lerpf(1.0, 2.6, detail)
			draw_texture_rect(tex, Rect2(st.position + off - Vector2(side, side) * 0.5, Vector2(side, side)), false, col)
			i += 1


## L 视野（站台视图）里画乘客：**只画当前线、当前站**，并让他们**站在站台上**。
##
## 站位与站台几何必须**同源**（都用 `GameView` 的常量），否则人会站到站台外面去。
## 上下站台按"下一站索引比本站大还是小"分派，和列车所在的那条轨道是一致的。
func _draw_interior(alpha: float) -> void:
	var st: Station = game_view._interior_station()
	# 诊断计数：到底哪一道门把人全挡掉了（站空？线不对？appear 太小？）
	var n_q := 0
	var n_line := 0
	var n_appear := 0
	var n_drawn := 0
	if st == null:
		print("[乘客·站台] 没有展开的站 -> 不画")
		return
	if _prev_station != st.id:
		_prev_station = st.id
		_prev_q.clear()
		_prev_gate.clear()
		_prev_all.clear()
		_fx.clear()
	n_q = st.queue.size()
	if st.queue.is_empty():
		print("[乘客·站台] 站 %s 队列为空 -> 不画（注意：此时连别的站也不画，这是设计缺陷）" % st.name)
		return
	var lines_at: Array = game_view.interior_lines()
	if lines_at.is_empty():
		print("[乘客·站台] 站 %s 没有可显示线路 -> 不画" % st.name)
		return
	var ln: Line = lines_at[0]
	for l in lines_at:
		if l.id == game_view.interior_line:
			ln = l
			break
	var si: int = ln.station_ids.find(st.id)
	if si < 0:
		return
	var tex := _texture()
	if tex == null:
		return

	# 上下两条站台的"站位中线"（世界单位），与 game_view._draw_station_interior 同源
	var cy_up: float = st.position.y - GameView.TRACK_DY
	var cy_dn: float = st.position.y + GameView.TRACK_DY
	var band_up: float = cy_up - GameView.TRENCH_H * 0.5 - GameView.PLAT_EDGE_GAP - GameView.PLAT_W * 0.5
	var band_dn: float = cy_dn + GameView.TRENCH_H * 0.5 + GameView.PLAT_EDGE_GAP + GameView.PLAT_W * 0.5

	var zoom: float = camera.zoom.x if camera != null else 1.0
	# **像素给足**：原来 M 视野一套尺寸，近景下一个人只有十来像素，看着"破碎"。
	# 这里直接按屏幕 30 像素给（再除以缩放换算成世界单位）。
	# 乘客大小：站台加宽后可以**稍微小一点**，一屏能站更多人（用户要求）
	var side: float = Config.view_px(48.0, zoom)
	# **散开站**，不要整齐站成一排（用户要求）。
	# 位置由"序号哈希"给出：同一个人在同一侧始终是同一个位置（不会每帧乱跳），
	# 但整体看不出排列规律。随后由碰撞松弛把人推开到互不重叠。
	# 上限是为了控制松弛的 O(n²) 成本。
	var gate_hist: Dictionary = {}
	var max_per_side := 40
	var spread_x := 62.0                       # 世界单位：沿站台铺开的半宽
	var spread_y: float = GameView.PLAT_W * 0.30
	var slot := {0: 0, 1: 0}
	# 本站此刻有没有车停着（停站中）。有车 -> 等车的人会**往闸机挤**，
	# 这就是"拥挤着上车"的观感来源（用户要的涌现感）。
	var dwell_here := false
	for tr in sim.trains:
		if tr.line_id == ln.id and tr.from_idx == tr.to_idx and tr.from_idx == si:
			dwell_here = true
			break

	# **开着的闸机**（按站台分两侧）：站台沿是一道墙，只有开着的闸机过人。
	# 两侧分开是关键 —— 上面的车到站，只开上站台的闸机（用户反馈过"开错侧"）。
	var open_gates: Array = [[], []]
	if dwell_here and game_view.has_method("gate_passable"):
		for side_i in [0, 1]:
			for gx in GameView.GATE_X:
				if game_view.gate_passable(ln, st, float(gx), side_i):
					open_gates[side_i].append(float(gx))

	# 第一遍：算出每人"想站"的位置与颜色
	var want: Array = []
	for p in st.queue:
		if p.state != Passenger.State.WAITING:
			continue
		var nxt: int = p.next_station()
		var ni: int = ln.station_ids.find(nxt)
		if ni < 0:
			continue        # 这条线不去他要去的下一站 -> 他不是这条线的人
		n_line += 1
		var k: int = 1 if ni > si else 0
		var idx: int = int(slot[k])
		slot[k] = idx + 1
		if idx >= max_per_side:
			continue        # 站台站不下就干脆不画，避免糊成一团
		# **由站台外走进来**（用户要求：不要只是"由淡变深"）。
		# 年龄仍用耐心值推（耐心接近满 = 刚生成），但"入场段"只占很小一段 ——
		# patience 的寿命本身有几十秒，用 0.16 会走上十几秒。
		var age := clampf(1.0 - p.patience, 0.0, 1.0)
		var enter := clampf(age / 0.05, 0.0, 1.0)
		n_appear += 1
		# 稳定的伪随机散点（不站成一排）。
		# ⚠ 每行都要**显式标 float**：`floor()` 是 GDScript 的重载全局函数、返回 Variant，
		# 于是 `var x := 表达式里含 floor(...)` 会报"无法推断类型"。
		var h1: float = sin(float(idx) * 12.9898 + float(k) * 78.233) * 43758.5453
		var h2: float = sin(float(idx) * 39.3468 + float(k) * 11.135) * 24634.6345
		var f1: float = h1 - floor(h1)
		var f2: float = h2 - floor(h2)
		var bx: float = (f1 - 0.5) * 2.0 * spread_x
		var by: float = (f2 - 0.5) * 2.0 * spread_y
		var wander := sin(_t * 0.35 + float(idx) * 1.7) * 5.0
		var side_gates: Array = open_gates[k]
		# ⚠ `gate_x` 必须在 if **外面**声明：GDScript 的 var 是块作用域，
		# 在 if 里声明、else 里赋值会直接报"未声明标识符"。
		var gate_x: float = 0.0
		if dwell_here and not side_gates.is_empty():
			# **按人轮流分配闸机**，而不是"各人找自己最近的"（用户要求）。
			# 原因："就近"在人少时必然退化成"都挤最近那两道"，看起来就是只往中间走；
			# 轮流分配则把人平均铺到各道开着的闸机上。
			# 分配是**确定的**：同一个人的序号不变，就一直走同一道闸机，不会每帧乱跳。
			gate_x = float(side_gates[idx % side_gates.size()])
			gate_hist[int(gate_x)] = int(gate_hist.get(int(gate_x), 0)) + 1
			bx = lerpf(bx, gate_x, 0.60)
			by = lerpf(by, 0.0, 0.5)              # 并向站台中线靠
			wander *= 0.30
		var off := Vector2(bx + wander, by)
		# 从站台外（沿站台方向很远）走进自己的位置；**不做淡入**，是"走进去"而不是"渐渐显形"。
		var enter_e: float = enter * enter * (3.0 - 2.0 * enter)      # smoothstep
		off.x = lerpf(off.x - 110.0, off.x, enter_e)
		var y := (band_up if k == 0 else band_dn) - st.position.y
		var col := _dot_color(p, st)
		col.a = alpha
		want.append({"p": p, "pos": Vector2(st.position.x + off.x, st.position.y + y + off.y),
			"col": col, "k": k, "appear": enter, "gate": gate_x})

	# 第二遍：**互斥松弛** —— 乘客之间要有碰撞，会互相挤开。
	# 这是"拥挤着上车"的基础：有碰撞才推得动，否则人只会叠在一起。
	# 只做几轮、每轮只推开部分穿透量，避免抖动与"爆开"。
	# 碰撞距离 = 人身体宽度的量级（屏幕约 34 像素，比如方块略小）。
	# 这样**静止时就略微重叠**，松弛会把他们推到刚好挨着；
	# 车停站时大家朝闸机收拢 -> 互相挤 -> 就被推开了。
	var min_d: float = Config.view_px(34.0, zoom)
	for _it in range(6):
		for i in range(want.size()):
			for j in range(i + 1, want.size()):
				if int(want[i]["k"]) != int(want[j]["k"]):
					continue            # 上下行站台互不干涉
				var a: Vector2 = want[i]["pos"]
				var b: Vector2 = want[j]["pos"]
				var dv: Vector2 = b - a
				var dist := dv.length()
				if dist < min_d and dist > 0.0001:
					var push: Vector2 = dv / dist * (min_d - dist) * 0.45
					want[i]["pos"] = a - push
					want[j]["pos"] = b + push

	# ---- 上下车表现（纯渲染层，不改模拟）----
	# 上一帧在等、这一帧不在了 -> **上车了**：从站台上原位跑向车门（站台靠轨道那条边）。
	# 上一帧不在、这一帧在了 -> **下车了**（或新到站）：从车门走向站台。
	# 这样就能看到"人从车里出来、又涌进车里"的连续过程，而不是瞬间消失/出现。
	# 车门所在的 y = 站台**靠轨道那条边**（绝对世界坐标）
	var edge_up: float = band_up + GameView.PLAT_W * 0.5
	var edge_dn: float = band_dn - GameView.PLAT_W * 0.5
	var now_q: Dictionary = {}
	var now_gate: Dictionary = {}
	for w in want:
		now_q[w["p"]] = w["pos"]
		now_gate[w["p"]] = w["gate"]
	for p in _prev_q.keys():
		if now_q.has(p):
			continue
		# **只有真的离开"在本站等车"才算上车**（上了车 / 换了站）。
		# 如果他还在这儿 `WAITING`，那他只是**被线路过滤掉了**（改线、寻路重算）——
		# 这时不播任何动画。否则一次重算就会让一群人同时"凭空消失又出现"（用户反馈）。
		if p.state == Passenger.State.WAITING and p.station_id == st.id:
			continue
		var prev_pos: Vector2 = _prev_q[p]
		var k2: int = 0 if prev_pos.y < st.position.y else 1
		var door_y: float = edge_up if k2 == 0 else edge_dn
		# **从他上一帧被分配到的那道闸机钻过去**：先横向走到那道闸机，再穿过它到车门。
		# ⚠ 没有分配记录时**必须用他自己的 x**，不能落到站心：
		# `_prev_gate` 缺省是 0，而 `st.position.x + 0` 正好是站台正中 ——
		# 那正是"所有上车的人都往中间跑"的来源（用户反馈）。
		var gx3: float = float(_prev_gate.get(p, 0.0))
		var has_gate: bool = absf(gx3) > 0.01
		if not has_gate:
			# **没有分配记录时也必须走某道闸机**，绝不能顺着自己的 x 直直穿过黑线 ——
			# 那正是"乘客直接跨过黑线上车"的来源（用户反馈）。
			# 优先取**本侧开着的**闸机里最近的一道；一道都没开（罕见）才退到最近的门位。
			var pool: Array = open_gates[k2]
			if pool.is_empty():
				pool = GameView.GATE_X
			gx3 = float(pool[0])
			for gx5 in pool:
				if absf(float(gx5) - (prev_pos.x - st.position.x)) \
						< absf(gx3 - (prev_pos.x - st.position.x)):
					gx3 = float(gx5)
			has_gate = true
		# 车门永远在**闸机的那个 x** 上：黑线是墙，只有开口能过。
		var go_x: float = st.position.x + gx3
		var mid := Vector2(go_x, prev_pos.y)
		var to := Vector2(go_x, door_y)
		_fx.append({"from": prev_pos, "mid": mid, "to": to, "t": 0.0, "gate": has_gate,
			"delay": minf(float(_fx.size()) * FX_STAGGER, 0.8),
			"col": Color(Config.COLOR_NORMAL.r, Config.COLOR_NORMAL.g, Config.COLOR_NORMAL.b, alpha)})
	for w in want:
		if _prev_q.has(w["p"]):
			continue
		# **上一帧也在本站等车的人不算"刚下车"**：他可能只是因为寻路重算才变合格，
		# 给他播一段"从车门走出来"就是凭空出现一堆人（用户反馈）。
		if _prev_all.has(w["p"]):
			continue
		# 新出现的：若本站正停着车，多半是刚下车的 -> 从车门往里走
		if not dwell_here:
			continue
		var k3: int = int(w["k"])
		var door_y2: float = edge_up if k3 == 0 else edge_dn
		# **下车也要走闸机口**（用户反馈）：原来是顺着他自己的 x 直上来的，
		# 等于从黑线上任意一点穿出来。现在取本侧**开着的**闸机里离他站位最近的一道，
		# 路径与上车相反：先从闸机口钻出来，再沿站台横向走到自己的站位。
		var pool2: Array = open_gates[k3]
		var gx6: float = 0.0
		if not pool2.is_empty():
			var wx: float = (w["pos"] as Vector2).x - st.position.x
			gx6 = float(pool2[0])
			for gx7 in pool2:
				if absf(float(gx7) - wx) < absf(gx6 - wx):
					gx6 = float(gx7)
		var out_x: float = st.position.x + gx6 if not pool2.is_empty() else (w["pos"] as Vector2).x
		_fx.append({"from": Vector2(out_x, door_y2), "mid": Vector2(out_x, (w["pos"] as Vector2).y),
			"to": w["pos"], "t": 0.0,
			"col": Color(Config.COLOR_WAITING.r, Config.COLOR_WAITING.g, Config.COLOR_WAITING.b, alpha)})
	_prev_q = now_q
	_prev_gate = now_gate
	# 未过滤的等车集合（下一帧用它区分"刚下车"和"因重算才变合格"）
	var now_all: Dictionary = {}
	for p2 in st.queue:
		if p2.state == Passenger.State.WAITING:
			now_all[p2] = true
	_prev_all = now_all

	# 画"正在上下车的人"：沿路径插值，末端淡出。
	# 上车的路径是两段（先走到闸机、再穿过去），所以前 55% 走第一段。
	for fx in _fx:
		# 错开出发：同批上车的人依次动身，形成一条人流（而不是整批一起消失）
		var t_local: float = float(fx["t"]) - float(fx.get("delay", 0.0))
		if t_local < 0.0:
			continue
		var ft: float = clampf(t_local / FX_DUR, 0.0, 1.0)
		if ft >= 1.0:
			continue
		var pos2: Vector2
		if fx.has("mid") and ft < 0.55:
			pos2 = (fx["from"] as Vector2).lerp(fx["mid"] as Vector2, ft / 0.55)
		elif fx.has("mid"):
			pos2 = (fx["mid"] as Vector2).lerp(fx["to"] as Vector2, (ft - 0.55) / 0.45)
		else:
			pos2 = (fx["from"] as Vector2).lerp(fx["to"] as Vector2, ft)
		var c2: Color = fx["col"]
		c2.a = alpha * (1.0 - ft * 0.75)
		draw_texture_rect(tex, Rect2(pos2 - Vector2(side, side) * 0.5, Vector2(side, side)), false, c2)

	# 第三遍：画站台上的人
	for w in want:
		draw_texture_rect(tex, Rect2(w["pos"] - Vector2(side, side) * 0.5, Vector2(side, side)), false, w["col"])
		n_drawn += 1

	# 诊断：松弛之后的**最小间距**。它应该贴着碰撞距离 —— 那是"人在互相挤"的直接证据；
	# 如果远大于碰撞距离，就说明松弛没生效（曾经真的发生过：间距用量纲错了）。
	var dmin := 9999.0
	for i in range(want.size()):
		for j in range(i + 1, want.size()):
			if int(want[i]["k"]) != int(want[j]["k"]):
				continue
			dmin = minf(dmin, (want[i]["pos"] as Vector2).distance_to(want[j]["pos"]))
	if dmin < 9000.0:
		print("　最小间距 %.2f / 碰撞距离 %.2f 世界单位　%s" % [
			dmin, min_d, "✓ 挤在一起" if dmin <= min_d + 0.15 else "✗ 没挤（碰撞没生效）"])
	var avg_ax := 0.0
	for w in want:
		avg_ax += absf((w["pos"] as Vector2).x - st.position.x)
	if want.size() > 0:
		avg_ax /= float(want.size())
	var hist_s := ""
	var hk: Array = gate_hist.keys()
	hk.sort()
	for g in hk:
		hist_s += "%+d:%d " % [int(g), int(gate_hist[g])]
	print("[乘客·站台] 站=%s 队列=%d 线=%s si=%d 画出=%d 开度=%.2f 可过=%d(上%d/下%d) 平均|x|=%.1f 各闸机=%s" % [
		st.name, n_q, ln.name, si, n_drawn,
		game_view._gate_open(ln, st.id),
		open_gates[0].size() + open_gates[1].size(), open_gates[0].size(), open_gates[1].size(),
		avg_ax, hist_s if hist_s != "" else "（无停站车）"])


func _texture() -> Texture2D:
	if dot_texture != null:
		return dot_texture
	if ResourceLoader.exists(DOT_TEXTURE):
		dot_texture = load(DOT_TEXTURE)
	return dot_texture


func _cloud_blend(zoom: float) -> float:
	if game_view != null:
		return game_view.cloud_blend_for(zoom)
	if zoom <= _cloud_zoom_lo:
		return 1.0
	if zoom >= _cloud_zoom_hi:
		return 0.0
	return clampf(1.0 - (zoom - _cloud_zoom_lo) / maxf(_cloud_zoom_hi - _cloud_zoom_lo, 0.0001), 0.0, 1.0)


func _detail(zoom: float) -> float:
	if game_view == null:
		return 0.0
	return clampf((zoom - game_view.mid_zoom) / maxf(game_view.fore_zoom - game_view.mid_zoom, 0.0001), 0.0, 1.0)


## 乘客点是画面主体，要"饱和可辨"。
## 注意 `Config.ink(c, amount)` 的 amount 是**往墨色 #182236 里兑多少**（不是透明度）：
## 云用 0.18~0.30 是想要淡雅，但点用同样档位会把黄兑成橄榄、绿兑成灰绿，看着发脏。
## 这里只兑一点点去刺眼，层次交给 shader 的软芯/涟漪和下面的 alpha。
func _dot_color(p: Passenger, st: Station) -> Color:
	if st.panic > 0.5:
		return Config.ink(Config.COLOR_PANIC, 0.08)
	if p.patience < 0.3:
		return Config.ink(Config.COLOR_CROWDED, 0.08)
	if p.patience < 0.6:
		return Config.ink(Config.COLOR_WAITING, 0.08)
	return Config.ink(Config.COLOR_NORMAL, 0.08)
