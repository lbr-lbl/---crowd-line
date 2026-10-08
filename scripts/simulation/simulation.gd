class_name Simulation
extends Node
## 模拟层核心：乘客 Agent、列车、站点、需求、延误、恐慌、积分、事件。

# ================= 寻路 / 拥挤代价参数 =================
const CONGESTION_WEIGHT := 2.2   # 拥挤代价权重（越高越愿意绕开拥堵站）
const TRANSFER_COST := 2.0       # 换乘一次的额外代价（等效"多坐两跳"）
const CLOSED_PENALTY := 8.0      # 封站惩罚：几乎绕开，但保留可达性
const SKIP_PENALTY := 1.5        # 跳站惩罚
const OVERFLOW_PENALTY := 4.0    # 超出容量后的额外惩罚（溢出到站外）
const CROWD_THRESHOLD := 0.6     # 超过这个密度才开始算拥挤代价
const REROUTE_INTERVAL := 18.0   # 同一乘客两次重算路径的最小间隔（秒）
const REROUTE_BUDGET := 6        # 每帧最多重算几条路径（性能护栏）

## 车队规模系数：车队数 = 往返时间 / (班次间隔 × 本系数)。
##   1.0 = 严格按班次间隔配车（运力贴合设计值，较紧）
##  < 1.0 = 多配车（更宽松、更好通关）。想回到旧的"每线 2+站数/3 辆"手感，
##          大约把它调到 0.55~0.65。
const FLEET_HEADWAY_MULT := 1.0

var network: Dictionary = {}
var stations: Array[Station] = []
var lines: Array[Line] = []
var trains: Array[Train] = []
var passengers: Array = []  # Array[Passenger] 当前活跃

var time: TimeSystem
var weather: WeatherSystem
var score: ScoreSystem
var events: EventSystem

var running: bool = false
var elapsed: float = 0.0
var duration: float = 300.0
var mode: String = "entry"
var tutorial_mode: bool = false

# --- 需求 ---
var base_spawn_rate: float = 3.0
var spawn_accum: float = 0.0
var demand_event_mult: float = 1.0
var spawn_weights: Array = []
var dest_weights: Array = []

# --- 玩家资源 ---
var resources: float = 100.0
var resource_regen: float = 0.6

# --- 操作参数 ---
var broadcast_cooldown: float = 0.0
var broadcast_cooldown_max: float = 30.0
var limit_power: float = 0.5
var close_penalty_mult: float = 1.0

# --- 肉鸽升级修饰符 ---
var entry_multiplier: float = 1.0
var add_train_cost: float = 30.0
var broadcast_power: float = 1.0
var satisfaction_bias: float = 0.0

# --- 定时效果 ---
var timed_effects: Array = []

# --- 邻接表（BFS 寻路）---
var adjacency: Dictionary = {}

# --- 线路内位置索引：line_pos[站点id][线路id] = 该站在此线的下标 ---
var line_pos: Dictionary = {}

# --- 发车时刻表："lineId:terminalIdx" -> 上次发车时刻（保证班次间隔）---
var last_departure: Dictionary = {}

# --- 本帧剩余的重算路径预算 ---
var reroute_budget: int = REROUTE_BUDGET

# --- 计数 ---
var next_passenger_id: int = 0
var next_train_id: int = 0

# --- 选择 ---
var selected_station_id: int = -1
var selected_line_id: int = -1

# --- 事件定时 ---
var concert_emitter: bool = false


func setup(network_id: String, p_mode: String) -> void:
    mode = p_mode
    tutorial_mode = (p_mode == "tutorial")
    var diff: Dictionary = Config.DIFFICULTY.get(p_mode, Config.DIFFICULTY["entry"])
    duration = diff["duration"]

    time = TimeSystem.new()
    time.name = "TimeSystem"
    add_child(time)
    time.set_time_speed(diff["time_speed"])
    time.set_hour(diff["start_hour"])

    weather = WeatherSystem.new()
    weather.name = "WeatherSystem"
    add_child(weather)

    score = ScoreSystem.new()
    score.reset(diff["target_served"])

    network = NetworkLoader.load_network(network_id)
    stations = NetworkLoader.build_stations(network)
    lines = NetworkLoader.build_lines(network, stations)

    # 需求权重
    _precompute_weights()

    _build_adjacency()
    _spawn_initial_trains()

    events = EventSystem.new(self)

    # 根据线路规模调整基准客流
    base_spawn_rate = clampf(stations.size() * 0.5, 2.0, 12.0) * (1.0 if p_mode != "hardcore" else 1.6)
    if tutorial_mode:
        # 教程局：客流温和，便于观察与学习
        base_spawn_rate = clampf(base_spawn_rate * 0.7, 1.5, 4.0)
        # 教程开局多给一些资源，方便体验"加车"
        resources = 150.0

    elapsed = 0.0
    if not tutorial_mode:
        resources = 100.0
    running = true


func _precompute_weights() -> void:
    spawn_weights.clear()
    dest_weights.clear()
    for st in stations:
        spawn_weights.append(1.0)
        var w := 1.0
        if st.is_interchange():
            w += 2.0
        dest_weights.append(w)


func _build_adjacency() -> void:
    adjacency.clear()
    line_pos.clear()
    for ln in lines:
        # 记录每个站"位于本条线的第几个位置"，供同线相邻站扩展使用
        for i in range(ln.station_ids.size()):
            var sid_i: int = ln.station_ids[i]
            if not line_pos.has(sid_i):
                line_pos[sid_i] = {}
            line_pos[sid_i][ln.id] = i
        for i in range(ln.station_ids.size() - 1):
            var a: int = ln.station_ids[i]
            var b: int = ln.station_ids[i + 1]
            if not adjacency.has(a):
                adjacency[a] = []
            if not adjacency.has(b):
                adjacency[b] = []
            if b not in adjacency[a]:
                adjacency[a].append(b)
            if a not in adjacency[b]:
                adjacency[b].append(a)


## 一条线的往返耗时（秒）：双向行驶 + 每站停靠。用于按班次间隔配车。
func _line_round_trip_time(ln: Line) -> float:
    var total := 0.0
    for i in range(ln.station_ids.size() - 1):
        var a: Vector2 = stations[ln.station_ids[i]].position
        var b: Vector2 = stations[ln.station_ids[i + 1]].position
        total += a.distance_to(b)
    var speed := maxf(ln.base_speed, 1.0)
    return (total * 2.0) / speed + float(ln.station_ids.size()) * 3.0


func _spawn_initial_trains() -> void:
    for ln in lines:
        var k := ln.station_ids.size()
        if k < 2:
            continue
        # 车队规模 = 往返时间 / (班次间隔 × 系数) —— 让 headway 真正决定发车密度，
        # 这样终点站的时刻表只需要"拉开扎堆"，不会白白压低运力。
        var hw := maxf(ln.effective_headway() * FLEET_HEADWAY_MULT, 0.5)
        var n := clampi(int(round(_line_round_trip_time(ln) / hw)), 2, 8)
        var cycle := (k - 1) * 2   # 往返一趟的段数（去程 + 回程）
        for i in range(n):
            var t := Train.new()
            t.id = next_train_id
            next_train_id += 1
            t.line_id = ln.id
            t.capacity = 80
            t.speed = ln.base_speed
            # 均匀铺满整趟往返（含回程反向），而不是全堆在起点单向排队
            _place_train_at_phase(t, ln, k, float(i) * float(cycle) / float(n))
            ln.trains.append(t)
            trains.append(t)


## 把列车放到往返循环的第 phase 个段位置（0 .. 2(k-1)）。
## phase 落在前半 -> 去程（direction = +1）；落在后半 -> 回程（direction = -1）。
func _place_train_at_phase(t: Train, ln: Line, k: int, phase: float) -> void:
    var legs := k - 1
    var ph := fposmod(phase, float(legs * 2))
    var seg := int(floor(ph))
    var prog := ph - float(seg)
    if seg < legs:
        # 去程：站索引递增
        t.direction = 1
        t.from_idx = seg
        t.to_idx = mini(seg + 1, k - 1)
    else:
        # 回程：站索引递减
        var back := seg - legs
        t.direction = -1
        t.from_idx = k - 1 - back
        t.to_idx = maxi(t.from_idx - 1, 0)
    t.progress = prog
    t.state = Train.TrainState.MOVING


## 列车在往返循环上的相位（单位=段），用于判断同线列车是否扎堆。
func _train_phase(t: Train, k: int) -> float:
    if t.direction > 0:
        return float(t.from_idx) + t.progress
    return float((k - 1) * 2) - (float(t.from_idx) - t.progress)


# ================= 主循环 =================

func tick(delta: float) -> void:
    if not running:
        return
    elapsed += delta

    time.tick(delta)
    weather.tick(delta)

    _update_timed_effects(delta)

    if events:
        events.tick(delta)

    _spawn_passengers(delta)
    _update_trains(delta)
    # 每帧重置重算路径预算，防止大量乘客同时重算导致卡顿
    reroute_budget = REROUTE_BUDGET
    _update_passengers(delta)
    _update_panic(delta)
    _update_scoring(delta)

    broadcast_cooldown = maxf(0.0, broadcast_cooldown - delta)
    resources = minf(999.0, resources + resource_regen * delta)

    EventBus.metrics_changed.emit(score.live_metrics())

    _check_failure()


# ================= 需求生成 =================

func _spawn_passengers(delta: float) -> void:
    var rate := base_spawn_rate * time.get_demand_multiplier() * weather.get_demand_multiplier() * demand_event_mult
    spawn_accum += rate * delta
    while spawn_accum >= 1.0:
        spawn_accum -= 1.0
        _spawn_one()


func _spawn_one() -> void:
    var origin := _pick_origin()
    if origin < 0:
        return
    var dest := _pick_weighted(dest_weights)
    var guard := 0
    while dest == origin and guard < 10:
        dest = _pick_weighted(dest_weights)
        guard += 1
    _spawn_at(origin, dest)


## 按"限流系数"加权抽一个进站口。
## 限流（entry_limit）与封站在这里真正生效：限流站新乘客更少，封站不产生乘客。
func _pick_origin() -> int:
    var w: Array = []
    var total := 0.0
    for i in range(stations.size()):
        var st: Station = stations[i]
        var wi := 1.0
        if i < spawn_weights.size():
            wi = float(spawn_weights[i])
        if st.closed:
            wi = 0.0
        else:
            wi *= clampf(st.entry_limit, 0.0, 1.0)
        w.append(wi)
        total += wi
    if total <= 0.0:
        return -1
    var r := randf() * total
    var acc := 0.0
    for i in range(w.size()):
        acc += float(w[i])
        if r <= acc:
            return i
    return w.size() - 1


## 在指定站生成一名乘客：先掷 info / conformity，再按"拥挤感知"寻路。
func _spawn_at(origin: int, dest: int) -> void:
    var info := randf_range(0.3, 1.0)
    var conf := clampf(time.get_conformity() + randf_range(-0.2, 0.2), 0.0, 1.0)
    var path := path_find(origin, dest, info, conf)
    if path.is_empty():
        return
    var p := Passenger.new(next_passenger_id, origin, dest)
    next_passenger_id += 1
    p.path = path
    p.info_level = info
    p.conformity = conf
    p.spawn_hour = time.get_hour()
    p.spawn_time = elapsed
    stations[origin].queue.append(p)
    passengers.append(p)


func _spawn_burst(station_id: int, count: int) -> void:
    for i in range(count):
        var dest := _pick_weighted(dest_weights)
        var guard := 0
        while dest == station_id and guard < 10:
            dest = _pick_weighted(dest_weights)
            guard += 1
        _spawn_at(station_id, dest)


func _pick_weighted(weights: Array) -> int:
    var total := 0.0
    for w in weights:
        total += w
    var r := randf() * total
    var acc := 0.0
    for i in range(weights.size()):
        acc += weights[i]
        if r <= acc:
            return i
    return weights.size() - 1


## 加权最短路（Dijkstra），在 (站点, 线路) 状态图上搜索。
## 代价 = 乘坐跳数 + 目标站拥挤度 + 换乘代价 + 封站/超容惩罚。
##   p_info        信息水平：越高越会主动避开拥挤站
##   p_conformity  从众性：越高越盲从人群，削弱避挤（拥堵因此更容易涌现）
## 返回值是"站点 id 序列"（换乘处会合并重复站），与乘客 path/path_index 约定一致。
func path_find(origin: int, dest: int, p_info: float = 1.0, p_conformity: float = 0.0) -> Array[int]:
    var same: Array[int] = []
    if origin == dest:
        same.append(origin)
        return same
    var empty: Array[int] = []
    if not adjacency.has(origin) or not adjacency.has(dest):
        return empty

    # 避挤强度：信息水平越高越避挤，从众性越高越不避挤
    var avoid := CONGESTION_WEIGHT * clampf(p_info, 0.0, 1.0)
    avoid *= 1.0 - 0.7 * clampf(p_conformity, 0.0, 1.0)

    # 状态编码：key = 站点id * stride + (线路id + 1)，线路 id 为 -1 表示尚未上车
    var stride := maxi(lines.size() + 2, 2)

    var dist: Dictionary = {}
    var prev: Dictionary = {}
    var start_key := origin * stride
    dist[start_key] = 0.0
    var open: Array = [start_key]

    while not open.is_empty():
        # 线性取最小（站点规模很小，够快且无需堆）
        var best_i := 0
        var best_d: float = float(dist[open[0]])
        for i in range(1, open.size()):
            var d: float = float(dist[open[i]])
            if d < best_d:
                best_d = d
                best_i = i
        var cur_key: int = int(open[best_i])
        open.remove_at(best_i)

        var cur_sid := int(cur_key / stride)
        var cur_lid := (cur_key % stride) - 1

        if cur_sid == dest:
            return _reconstruct_path(prev, cur_key, stride)

        # 1) 沿当前线路走到相邻站
        if cur_lid >= 0 and cur_lid < lines.size():
            var ln: Line = lines[cur_lid]
            var idx := -1
            if line_pos.has(cur_sid) and line_pos[cur_sid].has(cur_lid):
                idx = int(line_pos[cur_sid][cur_lid])
            if idx >= 0:
                for step in [-1, 1]:
                    var nidx: int = idx + int(step)
                    if nidx < 0 or nidx >= ln.station_ids.size():
                        continue
                    var nsid: int = ln.station_ids[nidx]
                    var cost := 1.0 + _structural_penalty(nsid) + avoid * _crowd_penalty(nsid)
                    _relax(dist, prev, open, cur_key, nsid * stride + (cur_lid + 1), cost)

        # 2) 在本站换乘（或首次上车）
        for other in stations[cur_sid].lines:
            var other_lid := int(other)
            if other_lid == cur_lid:
                continue
            var tcost := 0.0
            if cur_lid >= 0:
                # 换乘代价 + 换乘通道拥堵代价
                tcost = TRANSFER_COST + avoid * _crowd_penalty(cur_sid) * 0.5
            _relax(dist, prev, open, cur_key,
                cur_sid * stride + (other_lid + 1), tcost)

    return empty


## Dijkstra 松弛操作。
func _relax(dist: Dictionary, prev: Dictionary, open: Array,
        from_key: int, to_key: int, cost: float) -> void:
    var nd: float = float(dist[from_key]) + cost
    if not dist.has(to_key):
        dist[to_key] = nd
        prev[to_key] = from_key
        open.append(to_key)
    elif nd < float(dist[to_key]) - 0.0001:
        dist[to_key] = nd
        prev[to_key] = from_key
        if to_key not in open:
            open.append(to_key)


## 由前驱表回溯出站点序列（合并换乘产生的连续重复站）。
func _reconstruct_path(prev: Dictionary, goal_key: int, stride: int) -> Array[int]:
    var keys: Array = [goal_key]
    var node := goal_key
    while prev.has(node):
        node = int(prev[node])
        keys.append(node)
    keys.reverse()
    var path: Array[int] = []
    for k in keys:
        var sid := int(int(k) / stride)
        if path.is_empty() or path[path.size() - 1] != sid:
            path.append(sid)
    return path


## 拥挤代价：密度超过阈值后开始惩罚（越挤越贵）。
func _crowd_penalty(sid: int) -> float:
    if sid < 0 or sid >= stations.size():
        return 0.0
    var d := stations[sid].density()
    if d <= CROWD_THRESHOLD:
        return 0.0
    return (d - CROWD_THRESHOLD) * 3.0


## 结构性代价（与乘客信息水平无关）：封站、跳站、严重超容。
func _structural_penalty(sid: int) -> float:
    if sid < 0 or sid >= stations.size():
        return 0.0
    var st: Station = stations[sid]
    var pen := 0.0
    if st.closed:
        pen += CLOSED_PENALTY
    if st.skip_trains:
        pen += SKIP_PENALTY
    pen += st.overflow_ratio() * OVERFLOW_PENALTY
    return pen


# ================= 列车 =================

func _update_trains(delta: float) -> void:
    for t in trains:
        var ln: Line = lines[t.line_id]
        var k := ln.station_ids.size()
        if t.state == Train.TrainState.MOVING:
            var a: Vector2 = stations[ln.station_ids[t.from_idx]].position
            var b: Vector2 = stations[ln.station_ids[t.to_idx]].position
            var seg_len := a.distance_to(b)
            if seg_len < 0.001:
                t.progress = 1.0
            else:
                var speed_mult := weather.get_speed_multiplier()
                if t.delay > 20.0:
                    speed_mult *= 0.85
                t.progress += (t.speed * speed_mult * delta) / seg_len
            if t.progress >= 1.0:
                t.progress = 0.0
                t.from_idx = t.to_idx
                _arrive_train(t, ln, k)
        else:
            t.dwell_timer -= delta
            if t.dwell_timer <= 0.0:
                _depart_train(t, ln, k)
        # 延误自然恢复
        t.delay = maxf(0.0, t.delay - delta * 0.6)


func _arrive_train(t: Train, ln: Line, k: int) -> void:
    var sid: int = ln.station_ids[t.to_idx]
    var st: Station = stations[sid]
    t.state = Train.TrainState.DWELL

    # 准点记录
    score.record_arrival(t.delay < 15.0)

    # 延误传播：晚点列车在换乘站影响其他线路
    if t.delay > 15.0 and st.is_interchange():
        for other in trains:
            if other.line_id != t.line_id and other.delay < t.delay:
                other.delay = maxf(other.delay, t.delay * 0.4)
                EventBus.train_delayed.emit(other.line_id, other.delay)

    # 跳站 / 封站：不停靠
    if st.skip_trains or st.closed:
        t.dwell_timer = 0.05
        return

    t.dwell_timer = t.dwell_time

    # 上车方向：端点站会掉头，必须按"发车后要去的下一站"判定。
    # 原来的写法在端点站会算回本站自己，导致始发/终点站没有任何乘客能上车、人越积越多。
    var next_idx := _departure_next_index(t.to_idx, t.direction, k)
    var next_sid: int = ln.station_ids[next_idx]

    # 按班次间隔发车：同线、同站、同发车方向的后车，必须等前车离开 headway 秒后才能走。
    # 正常运行时全员按 headway 均匀间隔；一旦扎堆，后车扣车（最多 hw 秒）自动拉开。
    var key := "%d:%d:%d" % [ln.id, t.to_idx, next_idx]
    var since: float = elapsed - float(last_departure.get(key, -9999.0))
    var hw := ln.effective_headway()
    var wait := clampf(hw - since, t.dwell_time, hw)
    t.dwell_timer = maxf(t.dwell_timer, wait)

    # 下车
    var alighting: Array = []
    for p in t.passengers:
        if p.next_station() == sid:
            alighting.append(p)
    for p in alighting:
        t.unload_passenger(p)
        p.advance_path()
        if p.path_index >= p.path.size() - 1:
            # 到达终点
            p.state = Passenger.State.ARRIVED
            score.record_served(p.wait_time)
            st.total_served += 1
            EventBus.passenger_arrived.emit(sid)
            passengers.erase(p)
        else:
            # 换乘，回到站台
            p.state = Passenger.State.WAITING
            p.station_id = sid
            st.queue.append(p)

    # 上车（复用上面按"发车方向"解析好的 next_sid）
    var boarders: Array = []
    for p in st.queue:
        if t.is_full():
            break
        if p.state == Passenger.State.WAITING and p.next_station() == next_sid:
            boarders.append(p)
    for p in boarders:
        if t.is_full():
            break
        st.queue.erase(p)
        p.state = Passenger.State.RIDING
        p.train_ref = t
        p.board_count += 1
        p.boarded_line = t.line_id
        t.load_passenger(p)
        st.total_boarded += 1


func _depart_train(t: Train, ln: Line, k: int) -> void:
    var next_idx := _next_station_index(t.to_idx, t.direction, k)
    if next_idx == t.to_idx:
        t.direction *= -1
        next_idx = _next_station_index(t.to_idx, t.direction, k)
    # 记下这班车"从哪个站、往哪个方向"发出的时刻（键与到站时算的一致）
    last_departure["%d:%d:%d" % [ln.id, t.to_idx, next_idx]] = elapsed
    t.from_idx = t.to_idx
    t.to_idx = next_idx
    t.progress = 0.0
    t.state = Train.TrainState.MOVING


func _next_station_index(cur: int, dir: int, k: int) -> int:
    var n := cur + dir
    if n < 0 or n >= k:
        return cur  # 需要掉头，由调用方处理
    return n


## 列车从 cur 站发车后将要前往的站索引：到端点会掉头（纯计算，不改列车方向）。
func _departure_next_index(cur: int, dir: int, k: int) -> int:
    var nxt := _next_station_index(cur, dir, k)
    if nxt == cur:
        nxt = _next_station_index(cur, -dir, k)
    return nxt


# ================= 乘客耐心 =================

func _update_passengers(delta: float) -> void:
    var decay := time.get_patience_decay()
    var sum := 0.0
    var count := 0
    for p in passengers:
        p.reroute_cd = maxf(0.0, p.reroute_cd - delta)
        if p.state == Passenger.State.WAITING:
            var mult := 1.0
            if p.station_id >= 0 and p.station_id < stations.size():
                var st: Station = stations[p.station_id]
                # 站台超容：人群溢出到站外，耐心掉得更快
                mult += st.overflow_ratio() * 1.5
                if st.panic > 0.5:
                    mult += 0.5
            p.wait_time += delta
            p.patience = maxf(0.0, p.patience - decay * mult * delta)
            # 等到不耐烦就重找一条不那么挤的路（带每帧预算）
            _try_reroute(p)
        else:
            p.patience = maxf(0.0, p.patience - decay * 0.2 * delta)
        sum += p.patience
        count += 1
    if count > 0:
        score.sample_satisfaction(sum / count + satisfaction_bias)


## 等太久且当前路线上有爆站时，重算一次路径 —— 这正是"人自己绕开拥堵"的涌现来源。
## 带冷却与每帧预算，避免大量乘客同一帧重算导致卡顿。
func _try_reroute(p: Passenger) -> void:
    if reroute_budget <= 0 or p.reroute_cd > 0.0:
        return
    if p.patience > 0.6:
        return
    if p.station_id < 0 or p.station_id >= stations.size():
        return
    p.reroute_cd = REROUTE_INTERVAL
    reroute_budget -= 1
    var np := path_find(p.station_id, p.dest_id, p.info_level, p.conformity)
    if np.is_empty():
        return
    # 新路和剩下的旧路完全一样就不动，避免来回抖动
    var remain := p.path.size() - p.path_index
    if np.size() == remain:
        var same := true
        for i in range(np.size()):
            if np[i] != p.path[p.path_index + i]:
                same = false
                break
        if same:
            return
    p.path = np
    p.path_index = 0


# ================= 恐慌与踩踏 =================

func _update_panic(delta: float) -> void:
    var conformity := time.get_conformity()
    for st in stations:
        var d := st.density()
        st.display_density = lerpf(st.display_density, d, clampf(delta * 3.0, 0.0, 1.0))
        if d > 0.85:
            st.panic += (d - 0.85) * (0.6 + conformity) * delta * 1.6
        else:
            st.panic = maxf(0.0, st.panic - delta * 0.5)
        if st.panic >= 1.0:
            _trigger_stampede(st)
        EventBus.station_density_changed.emit(st.id, st.display_density, st.queue_size())
        if st.panic > 0.7:
            EventBus.station_panic.emit(st.id, st.panic)


func _trigger_stampede(st: Station) -> void:
    st.panic = 0.35
    score.add_safety_penalty(0.5)
    EventBus.stampede.emit(st.id)
    EventBus.toast.emit("⚠ 踩踏风险！%s 站人群失控" % st.name)


# ================= 积分采样 =================

func _update_scoring(_delta: float) -> void:
    pass  # 满意度在 _update_passengers 里采样


# ================= 失败判定 =================

func _check_failure() -> void:
    if not running:
        return
    if score.safety <= 0.0:
        _game_over("踩踏风险失控，安全分归零")
        return
    if score.satisfaction() < 0.15 and score.satisfaction_samples > 20:
        _game_over("乘客满意度归零")
        return
    var overcrowded := 0
    for st in stations:
        if st.density() > 1.2:
            overcrowded += 1
    if stations.size() > 0 and overcrowded > stations.size() * 0.4:
        _game_over("全网瘫痪：过多站点超载")
        return
    if elapsed >= duration:
        _game_over("时间到")


func _game_over(reason: String) -> void:
    if not running:
        return
    running = false
    var m := score.metrics()
    EventBus.game_over.emit(reason, m)


# ================= 定时效果 =================

func _add_timed(kind: String, sid: int, remaining: float, factor: float = 1.0) -> void:
    timed_effects.append({"kind": kind, "sid": sid, "remaining": remaining, "factor": factor})


func _update_timed_effects(delta: float) -> void:
    var done: Array = []
    for e in timed_effects:
        e["remaining"] -= delta
        if e["remaining"] <= 0.0:
            _revert_effect(e)
            done.append(e)
    for e in done:
        timed_effects.erase(e)


func _revert_effect(e: Dictionary) -> void:
    var kind: String = e["kind"]
    var sid: int = e["sid"]
    match kind:
        "limit", "maintenance":
            stations[sid].entry_limit = 1.0
        "close":
            stations[sid].closed = false
        "skip":
            stations[sid].skip_trains = false
        "capacity":
            stations[sid].capacity_mod /= e["factor"]
        "demand":
            demand_event_mult /= e["factor"]


# ================= 玩家操作 =================

func apply_operation(op: String, target_id: int) -> void:
    if not running:
        return
    match op:
        "limit":
            var st: Station = stations[target_id]
            st.entry_limit = limit_power
            _add_timed("limit", target_id, 30.0)
            _damage_station_patience(st, 0.05)
            EventBus.operation_applied.emit("limit", target_id)
            EventBus.toast.emit("限流 %s" % st.name)
        "add_train":
            if resources < add_train_cost:
                EventBus.toast.emit("资源不足，无法加车")
                return
            resources -= add_train_cost
            _add_train_to_line(target_id)
            EventBus.operation_applied.emit("add_train", target_id)
            EventBus.toast.emit("已加车：%s" % lines[target_id].name)
        "close":
            var st2: Station = stations[target_id]
            st2.closed = true
            _add_timed("close", target_id, 20.0)
            _damage_station_patience(st2, 0.3 * close_penalty_mult)
            EventBus.operation_applied.emit("close", target_id)
            EventBus.toast.emit("封站 %s" % st2.name)
        "skip":
            var st3: Station = stations[target_id]
            st3.skip_trains = true
            _add_timed("skip", target_id, 20.0)
            EventBus.operation_applied.emit("skip", target_id)
            EventBus.toast.emit("跳站 %s" % st3.name)
        "broadcast":
            if broadcast_cooldown > 0.0:
                EventBus.toast.emit("广播冷却中 %.0fs" % broadcast_cooldown)
                return
            broadcast_cooldown = broadcast_cooldown_max
            for st in stations:
                st.panic = maxf(0.0, st.panic * (0.5 / broadcast_power))
            # 广播让乘客"知道路况"，主动绕开爆站 —— 这才是真正意义上的引导改道
            var informed := 0
            for p in passengers:
                if p.state == Passenger.State.WAITING:
                    p.info_level = clampf(p.info_level + 0.35 * broadcast_power, 0.0, 1.0)
                    p.reroute_cd = 0.0
                    informed += 1
            demand_event_mult *= 0.9
            _add_timed("demand", -1, 30.0, 0.9)
            EventBus.operation_applied.emit("broadcast", -1)
            EventBus.toast.emit("广播引导：%d 名乘客开始改道" % informed)


func _damage_station_patience(st: Station, amount: float) -> void:
    for p in st.queue:
        p.patience = maxf(0.0, p.patience - amount)


func _add_train_to_line(line_id: int) -> void:
    var ln: Line = lines[line_id]
    var k := ln.station_ids.size()
    if k < 2:
        return
    var t := Train.new()
    t.id = next_train_id
    next_train_id += 1
    t.line_id = line_id
    t.capacity = 80
    t.speed = ln.base_speed
    # 插到整趟往返里最空的一段，避免新车叠在既有列车头上（同站同方向多车）
    _place_train_at_phase(t, ln, k, _largest_gap_phase(ln, k))
    ln.trains.append(t)
    trains.append(t)


## 找到该线往返循环上两车之间最大的空隙，返回其中点相位；线上无车时从头开始。
func _largest_gap_phase(ln: Line, k: int) -> float:
    var cycle := float((k - 1) * 2)
    var phases: Array = []
    for t in trains:
        if t.line_id == ln.id:
            phases.append(_train_phase(t, k))
    if phases.is_empty():
        return 0.0
    phases.sort()
    var best_len := -1.0
    var best_mid := 0.0
    for i in range(phases.size()):
        var a := float(phases[i])
        var b := float(phases[(i + 1) % phases.size()])
        var gap := fposmod(b - a, cycle)
        if gap > best_len:
            best_len = gap
            best_mid = fposmod(a + gap * 0.5, cycle)
    return best_mid


# ================= 肉鸽升级 / 事件 =================

func apply_upgrade(id: String) -> void:
    match id:
        "quick_gate":
            entry_multiplier *= 1.2
            satisfaction_bias -= 0.05
        "smart_broadcast":
            broadcast_power += 0.15
            broadcast_cooldown_max += 30.0
        "spare_train":
            add_train_cost *= 0.7
        "wide_platform":
            for st in stations:
                st.capacity = int(st.capacity * 1.25)
        "emergency_exit":
            close_penalty_mult *= 0.5
            limit_power = maxf(0.3, limit_power - 0.1)
    EventBus.upgrade_chosen.emit(EventSystem.upgrade_by_id(id))


func apply_event(id: String) -> void:
    match id:
        "concert":
            var sid := randi_range(0, stations.size() - 1)
            _spawn_burst(sid, 18)
            EventBus.toast.emit("演唱会散场：%s 站涌入大客流" % stations[sid].name)
        "heavy_rain":
            weather.trigger_timed("heavy_rain", 40.0)
            EventBus.toast.emit("暴雨来袭，列车减速")
        "signal_fault":
            var lid := randi_range(0, lines.size() - 1)
            for t in trains:
                if t.line_id == lid:
                    t.delay += randf_range(15.0, 30.0)
            EventBus.toast.emit("信号故障：%s 延误传播" % lines[lid].name)
        "exit_closed":
            var sid2 := randi_range(0, stations.size() - 1)
            stations[sid2].capacity_mod *= 0.7
            _add_timed("capacity", sid2, 30.0, 0.7)
            EventBus.toast.emit("出口关闭：%s 容量 -30%%" % stations[sid2].name)
        "fare_off":
            demand_event_mult *= 1.15
            _add_timed("demand", -1, 60.0, 1.15)
            EventBus.toast.emit("票价优惠：需求 +15%")
        "maintenance":
            var sid3 := randi_range(0, stations.size() - 1)
            stations[sid3].entry_limit = 0.5
            _add_timed("maintenance", sid3, 30.0)
            EventBus.toast.emit("设备检修：%s 闸机效率 -50%%" % stations[sid3].name)


# ================= 查询 =================

func get_station(sid: int) -> Station:
    if sid >= 0 and sid < stations.size():
        return stations[sid]
    return null


func get_line(lid: int) -> Line:
    if lid >= 0 and lid < lines.size():
        return lines[lid]
    return null


func train_world_position(t: Train) -> Vector2:
    var ln: Line = lines[t.line_id]
    var a: Vector2 = stations[ln.station_ids[t.from_idx]].position
    var b: Vector2 = stations[ln.station_ids[t.to_idx]].position
    return a.lerp(b, t.progress)


func select_station(sid: int) -> void:
    selected_station_id = sid
    selected_line_id = -1


func select_line(lid: int) -> void:
    selected_line_id = lid
    selected_station_id = -1


func clear_selection() -> void:
    selected_station_id = -1
    selected_line_id = -1
