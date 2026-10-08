class_name Passenger
extends RefCounted
## 乘客 Agent：只有简单规则——去目的地、选最短路径、耐心有限、从众/恐慌。

enum State { WAITING, RIDING, ARRIVED }

var id: int = 0
var origin_id: int = 0
var dest_id: int = 0

# 最短路径（含起终点，station id 序列）
var path: Array[int] = []
var path_index: int = 0

var state: int = State.WAITING

# 当前所在站点（等车时）或所在列车（乘车时）
var station_id: int = -1
var train_ref = null

# 耐心 1.0 -> 0.0；越低越不满
var patience: float = 1.0
var wait_time: float = 0.0

# 从众性 / 信息获取（用于恐慌传播）
var conformity: float = 0.5
var info_level: float = 0.5

# 重算路径冷却（秒）：等到不耐烦时会重新找一条不那么挤的路
var reroute_cd: float = 0.0

# 当前所乘线路 id（-1 表示还没上车），用于统计换乘次数
var boarded_line: int = -1

# 记账
var spawn_hour: float = 0.0
var spawn_time: float = 0.0
var board_count: int = 0


func _init(p_id: int, p_origin: int, p_dest: int) -> void:
	id = p_id
	origin_id = p_origin
	dest_id = p_dest
	station_id = p_origin


func next_station() -> int:
	if path_index + 1 < path.size():
		return path[path_index + 1]
	return -1


func is_arriving_here(st: int) -> bool:
	return next_station() == st


func advance_path() -> void:
	path_index += 1
