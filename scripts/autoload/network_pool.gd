extends Node
## 线路池注册表：按策划案线路池设计，把线网分组成池。
## 主菜单选择的是"池"，进入后用 pool.random_network() 从池中随机抽一条真实线网。
## 池的难度键映射到 Config.DIFFICULTY（tutorial/entry/advance/hardcore）。

# 池结构。members 为资源里的网络文件 id（resources/networks/<id>.json）。
const POOLS: Dictionary = {
	"tutorial": {
		"label": "教程线路",
		"mode": "tutorial",
		"desc": "手把手教你操作、目标与阻碍",
		"members": ["tutorial_basics"],
	},
	"entry": {
		"label": "基础池 ★",
		"mode": "entry",
		"desc": "1-2 条线 · 5-8 个站 · 熟悉操作",
		"members": ["wenzhou_s1", "lisbon_blue"],
	},
	"advance": {
		"label": "进阶池 ★★",
		"mode": "advance",
		"desc": "3-5 条线 · 15-25 个站 · 换乘与高峰压力",
		"members": ["hongkong_tw_kt", "taipei_cross"],
	},
	"hardcore": {
		"label": "硬核池 ★★★",
		"mode": "hardcore",
		"desc": "8 条线以上 · 50+ 站 · 密集换乘与涌现",
		"members": ["chongqing_net", "chengdu_net"],
	},
	"infinite": {
		"label": "无限模式 ∞",
		"mode": "hardcore",
		"desc": "随机组合· 每局不同 · 肉鸽升级",
		"members": [],
	},
}

# 所有池的抽屉顺序（菜单下拉展示用）
const POOL_ORDER: Array[String] = ["tutorial", "entry", "advance", "hardcore", "infinite"]


static func list_pool_ids() -> Array[String]:
	return POOL_ORDER


static func pool_exists(pool_id: String) -> bool:
	return POOLS.has(pool_id)


static func pool_label(pool_id: String) -> String:
	if POOLS.has(pool_id):
		return str(POOLS[pool_id]["label"])
	return pool_id


static func pool_desc(pool_id: String) -> String:
	if POOLS.has(pool_id):
		return str(POOLS[pool_id]["desc"])
	return ""


static func pool_mode(pool_id: String) -> String:
	if POOLS.has(pool_id):
		return str(POOLS[pool_id]["mode"])
	return "entry"


## 池内可选的网络 id 数组
static func members_of(pool_id: String) -> Array[String]:
	if POOLS.has(pool_id):
		var ids: Array[String] = []
		for m in POOLS[pool_id]["members"]:
			ids.append(str(m))
		return ids
	return []


## 池内网络是否全部计入"任意池"（无限模式抽全部真实线）
static func all_network_ids() -> Array[String]:
	var seen: Dictionary = {}
	var out: Array[String] = []
	for pid in POOL_ORDER:
		if pid == "infinite":
			continue
		for m in members_of(pid):
			if not seen.has(m):
				seen[m] = true
				out.append(m)
	return out


## 从池中随机抽一条真实线网 id（无限模式从全部池中抽）。
static func random_network(pool_id: String) -> String:
	var ids: Array[String] = []
	if pool_id == "infinite":
		ids = all_network_ids()
	else:
		ids = members_of(pool_id)
	if ids.is_empty():
		# 兜底：任意池
		ids = all_network_ids()
	if ids.is_empty():
		return "wenzhou_s1"
	return ids.pick_random()


## 该池是否为教程
static func is_tutorial(pool_id: String) -> bool:
	return pool_id == "tutorial"
