extends Node
## 现实依据集中表（`resources/real_world.json`）的验收。
##
## 跑法：
##   & $godot --headless --quit-after 300 --path <root> res://tests/real_world_test.tscn
##
## 为什么需要它：内容表是**数据**，写错不会报错、只会静默失效——
## 比如场馆里把站名写成"奥体城"而地图里其实是"奥体中心"，
## 结果就是"演唱会事件永远不在这张图发生"，而且没有任何提示。
## 所以这里把"表里的站名必须真的存在于对应地图"当成硬断言。

var _fails: int = 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("  [PASS] %s   %s" % [label, detail])
	else:
		_fails += 1
		print("  [FAIL] %s   %s" % [label, detail])


func _ready() -> void:
	print("=========== 现实依据表验收 ===========")
	_test_weather_climate()
	_test_venues_exist()
	_test_event_kinds()
	print("=========== 失败 %d 项 ===========" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _net_ids() -> Array:
	var ids: Array = NetworkPool.all_network_ids()
	if ids.is_empty():
		ids = RealWorld.data().get("networks", {}).keys()
	return ids


## 气候带 / 禁用天气：南方线网绝不下雪；内陆不刮台风
func _test_weather_climate() -> void:
	print("--- 天气可用性 ---")
	for nid in _net_ids():
		var allowed := RealWorld.allowed_weather(nid)
		_check(not allowed.is_empty(), "%s 至少有一种天气可用" % nid, "共 %d 种" % allowed.size())
		if nid != "tutorial_basics":
			_check(not ("snow" in allowed), "%s 不会下雪" % nid,
				"可用=%s" % str(allowed))
	for nid in ["wenzhou_s1", "taipei_cross", "hongkong_tw_kt"]:
		_check("typhoon" in RealWorld.allowed_weather(nid), "%s 可能有台风" % nid)
	for nid in ["chongqing_net", "chengdu_net", "lisbon_blue"]:
		_check(not ("typhoon" in RealWorld.allowed_weather(nid)), "%s 不会有台风" % nid)
	_check("fog" in RealWorld.allowed_weather("chongqing_net"), "重庆多雾（雾都）")
	_check("heatwave" in RealWorld.allowed_weather("taipei_cross"), "台北可能酷热")


## 场馆站名必须真的存在于对应地图（写错就会静默失效）
func _test_venues_exist() -> void:
	print("--- 场馆站名与地图一致性 ---")
	for nid in _net_ids():
		var venues := RealWorld.venues(nid)
		if venues.is_empty():
			print("  （%s 没有配置场馆，事件池里不会有场馆类事件）" % nid)
			continue
		var names := _station_names(nid)
		_check(not names.is_empty(), "%s 能读到站点表" % nid, "%d 站" % names.size())
		var bad := 0
		for v in venues:
			var sname := str(v.get("station", ""))
			if not (sname in names):
				bad += 1
				print("    ✗ %s 的场馆「%s」写了站名「%s」，地图里没有这个站" % [
					nid, str(v.get("name", "?")), sname])
			_check(not (v.get("kinds", []) as Array).is_empty(),
				"%s / %s 有活动类型" % [nid, str(v.get("name", "?"))])
		_check(bad == 0, "%s 全部场馆站名有效" % nid, "%d 处场馆" % venues.size())


## 事件种类：每种都必须能至少在一张图上落地
func _test_event_kinds() -> void:
	print("--- 事件种类可落地性 ---")
	var kinds: Dictionary = RealWorld.event_kinds()
	_check(not kinds.is_empty(), "事件种类表非空", "%d 种" % kinds.size())
	for kind in kinds.keys():
		var hit := ""
		for nid in _net_ids():
			for v in RealWorld.venues(nid):
				if kind in (v.get("kinds", []) as Array):
					hit = nid
					break
			if hit != "":
				break
		_check(hit != "", "事件「%s」在至少一张图上能触发" % kind, "例：%s" % hit)
	# 用户点名的例子：温州演唱会只在奥体中心
	var v := RealWorld.pick_venue("wenzhou_s1", "concert")
	_check(str(v.get("station", "")) == "奥体中心",
		"温州演唱会只落在奥体中心", "实际=%s" % str(v.get("station", "无")))


## 直接读线网 JSON 的站名（不经过 Simulation，保证与配置表比对的是"数据源"）
func _station_names(net_id: String) -> Array:
	var out: Array = []
	var path := "res://resources/networks/%s.json" % net_id
	if not FileAccess.file_exists(path):
		return out
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	for s in parsed.get("stations", []):
		out.append(str(s.get("name", "")))
	return out
