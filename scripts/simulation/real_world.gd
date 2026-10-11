class_name RealWorld
extends RefCounted
## 现实依据集中表（`resources/real_world.json`）的读取口。
##
## 内容侧的东西——**哪种天气可能出现在哪张图、事件落在哪个真实场馆**——全部查这里；
## 地图 JSON 只描述拓扑（站点、线路、换乘），不掺内容。
## 想改"温州演唱会只在奥体中心"或"香港不下雪"，只改这个 JSON，不用碰任何地图。

const PATH := "res://resources/real_world.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_load()
	return _data


static func _load() -> void:
	var fallback := {"weather": {}, "networks": {}, "event_kinds": {}}
	if not FileAccess.file_exists(PATH):
		push_warning("RealWorld: 找不到 %s，内容侧退回空表" % PATH)
		_data = fallback
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("RealWorld: %s 解析失败，内容侧退回空表" % PATH)
		_data = fallback
		return
	_data = parsed


static func _net(network_id: String) -> Dictionary:
	return data().get("networks", {}).get(network_id, {})


static func city(network_id: String) -> String:
	return str(_net(network_id).get("city", ""))


static func venues(network_id: String) -> Array:
	return _net(network_id).get("venues", [])


## 该线网此刻允许出现的天气 id（按气候带 + 禁用表筛）。
## `climates` 里出现 "*"（任意气候）或该天气的 climates 含 "*" 都会放行。
static func allowed_weather(network_id: String) -> Array:
	var all: Dictionary = data().get("weather", {})
	var climates: Array = _net(network_id).get("climates", ["*"])
	var forbidden: Array = _net(network_id).get("forbidden_weather", [])
	var out: Array = []
	for wid in all.keys():
		if wid in forbidden:
			continue
		var need: Array = all[wid].get("climates", ["*"])
		if "*" in need or "*" in climates:
			out.append(wid)
			continue
		for c in need:
			if c in climates:
				out.append(wid)
				break
	return out


## 按权重抽一个允许的天气。
## `opening = true` 时只在标了 `"opening": true` 的**温和天气**里抽（晴/阴）——
## 否则开局可能直接抽到"酷热"（需求 ×1.22）撞上早高峰，硬核池会开局就崩
## （实测：不加这个限制，重庆 none 的失败时间从 ~348s 掉到 76.6s）。
static func roll_weather(network_id: String, opening: bool = false) -> String:
	var allowed := allowed_weather(network_id)
	if opening:
		var mild: Array = []
		for w in allowed:
			if bool(data()["weather"][w].get("opening", false)):
				mild.append(w)
		if not mild.is_empty():
			allowed = mild
	if allowed.is_empty():
		return "clear"
	var all: Dictionary = data().get("weather", {})
	var total := 0.0
	for wid in allowed:
		total += float(all[wid].get("weight", 10))
	var r := randf() * total
	for wid in allowed:
		r -= float(all[wid].get("weight", 10))
		if r <= 0.0:
			return wid
	return str(allowed[allowed.size() - 1])


## 找一处能办这类活动的真实场馆（{} = 这张图没有）
static func pick_venue(network_id: String, kind: String) -> Dictionary:
	var pool: Array = []
	for v in venues(network_id):
		var kinds: Array = v.get("kinds", [])
		if kind in kinds:
			pool.append(v)
	if pool.is_empty():
		return {}
	return pool.pick_random()


## 这张图有没有任何场馆（没有就不该往事件池里放"场馆类"事件）
static func has_any_venue(network_id: String) -> bool:
	return not venues(network_id).is_empty()


static func event_kinds() -> Dictionary:
	return data().get("event_kinds", {})


## 该线网能办的活动种类（去重）
static func available_event_kinds(network_id: String) -> Array:
	var out: Array = []
	for v in venues(network_id):
		for k in v.get("kinds", []):
			if not (k in out):
				out.append(k)
	return out
