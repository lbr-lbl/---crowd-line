class_name EventSystem
extends RefCounted
## 随机事件与肉鸽升级：只改参数，不改规则。

const UPGRADE_INTERVAL := 120.0
const EVENT_INTERVAL := 45.0

var sim: Simulation = null

var upgrade_timer: float = UPGRADE_INTERVAL
var event_timer: float = EVENT_INTERVAL * 0.6

var pending_upgrade: bool = false


func _init(p_sim: Simulation) -> void:
	sim = p_sim


func tick(delta: float) -> void:
	upgrade_timer -= delta
	if upgrade_timer <= 0.0:
		upgrade_timer = UPGRADE_INTERVAL
		_offer_upgrades()

	event_timer -= delta
	if event_timer <= 0.0:
		event_timer = EVENT_INTERVAL + randf_range(-10.0, 15.0)
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
	var ev: Dictionary = event_pool().pick_random()
	sim.apply_event(ev["id"])
	EventBus.event_triggered.emit(ev)


# ---------------- 定义 ----------------

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
			"id": "spare_train", "name": "备用列车",
			"desc": "加车成本 -30%",
			"icon": "🚇",
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


static func event_pool() -> Array:
	return [
		{"id": "concert", "name": "演唱会散场", "desc": "某站短时大客流涌入", "icon": "🎤"},
		{"id": "heavy_rain", "name": "暴雨", "desc": "需求 +20%，列车减速", "icon": "🌧"},
		{"id": "signal_fault", "name": "信号故障", "desc": "某线列车延误传播", "icon": "🚦"},
		{"id": "exit_closed", "name": "出口关闭", "desc": "某站容量 -30%", "icon": "🚧"},
		{"id": "fare_off", "name": "票价优惠", "desc": "需求 +15%，持续 1 分钟", "icon": "🎫"},
		{"id": "maintenance", "name": "设备检修", "desc": "某站闸机效率 -50%", "icon": "🔧"},
	]


static func upgrade_by_id(id: String) -> Dictionary:
	for u in upgrade_pool():
		if u["id"] == id:
			return u
	return {}
