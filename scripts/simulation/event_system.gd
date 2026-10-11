class_name EventSystem
extends RefCounted
## 随机事件与肉鸽升级：只改参数，不改规则。

const UPGRADE_INTERVAL := 120.0
const EVENT_INTERVAL := 45.0

var sim: Simulation = null

var upgrade_timer: float = UPGRADE_INTERVAL
var event_timer: float = EVENT_INTERVAL * 0.6

var pending_upgrade: bool = false

## 间隔倍率（无限模式每过一波就调小一点，事件越来越密）
var interval_scale: float = 1.0


func _init(p_sim: Simulation) -> void:
	sim = p_sim


## 无限模式用：整体压缩/放大事件与升级的间隔
func set_interval_scale(s: float) -> void:
	interval_scale = clampf(s, 0.25, 4.0)


func tick(delta: float) -> void:
	upgrade_timer -= delta
	if upgrade_timer <= 0.0:
		upgrade_timer = UPGRADE_INTERVAL * interval_scale
		_offer_upgrades()

	event_timer -= delta
	if event_timer <= 0.0:
		event_timer = (EVENT_INTERVAL + randf_range(-10.0, 15.0)) * interval_scale
		# 教程局：不随机触发阻碍事件，便于学习
		if sim != null and sim.tutorial_mode:
			return
		_trigger_random_event()


func _offer_upgrades() -> void:
	var pool := upgrade_pool()
	pool.shuffle()
	var choices: Array = pool.slice(0, 3)
	EventBus.upgrade_offer.emit(choices)


func _trigger_random_event() -> void:
	var pool := event_pool_for(sim.network_id if sim != null else "")
	if pool.is_empty():
		return
	var ev: Dictionary = pool.pick_random()
	sim.apply_event(ev["id"])
	EventBus.event_triggered.emit(ev)


# ---------------- 定义 ----------------

## 通用事件池（设施类 + 天气类）。**场馆类事件不放这里**，见 `venue_events_for()`：
## 它们必须落在真实场馆所在的站，哪个站能办哪类活动查 `resources/real_world.json`。
static func base_event_pool() -> Array:
	return [
		{"id": "heavy_rain", "name": "暴雨", "desc": "需求 +20%，列车减速", "icon": "🌧"},
		{"id": "thunderstorm", "name": "雷暴", "desc": "短时强降雨，列车减速", "icon": "⛈"},
		{"id": "typhoon", "name": "台风", "desc": "全线大幅减速、客流骤降", "icon": "🌀"},
		{"id": "signal_fault", "name": "信号故障", "desc": "某线列车延误传播", "icon": "🚦"},
		{"id": "exit_closed", "name": "出口关闭", "desc": "某站容量 -30%", "icon": "🚧"},
		{"id": "fare_off", "name": "票价优惠", "desc": "需求 +15%，持续 1 分钟", "icon": "🎫"},
		{"id": "maintenance", "name": "设备检修", "desc": "某站闸机效率 -50%", "icon": "🔧"},
	]


## 该线网实际可触发的事件池 = 通用池（按天气可行性筛掉不可能天气）
## + 该线网真实场馆能办的场馆类活动
static func event_pool_for(network_id: String) -> Array:
	var allowed_weather := RealWorld.allowed_weather(network_id)
	var out: Array = []
	for e in base_event_pool():
		var eid: String = e["id"]
		# 天气类事件要求该天气在这张图是可能出现的（"香港不下雪"同理适用于台风等）
		if Config.WEATHER_PARAMS.has(eid) and not (eid in allowed_weather):
			continue
		out.append(e)
	for kind in RealWorld.available_event_kinds(network_id):
		var meta: Dictionary = RealWorld.event_kinds().get(kind, {})
		if meta.is_empty():
			continue
		out.append({
			"id": kind,
			"name": str(meta.get("label", kind)),
			"desc": "真实场馆散场客流",
			"icon": "🎪",
		})
	return out


static func venue_events_for(network_id: String) -> Array:
	return RealWorld.available_event_kinds(network_id)


## 兼容旧调用（无 network_id 时用通用池）
static func event_pool() -> Array:
	return base_event_pool()

static func upgrade_pool() -> Array:
	return [
		{
			"id": "quick_gate", "name": "快速闸机",
			"desc": "进站速度 +20%，但满意度 -5%",
			"icon": "⚡",
		},
		{
			"id": "smart_broadcast", "name": "智能广播",
			"desc": "广播改道效果 +15%，冷却 +30s",
			"icon": "📢",
		},
		{
			"id": "depot_shop", "name": "检修车间",
			"desc": "加挂费用 -30%，占站台时长 -20%",
			"icon": "🏭",
		},
		{
			"id": "wide_platform", "name": "宽敞站台",
			"desc": "全站站台容量 +25%",
			"icon": "🏗",
		},
		{
			"id": "emergency_exit", "name": "应急通道",
			"desc": "封站副作用 -50%，但限流效果 -10%",
			"icon": "🚪",
		},
	]


static func upgrade_by_id(id: String) -> Dictionary:
	for u in upgrade_pool():
		if u["id"] == id:
			return u
	return {}
