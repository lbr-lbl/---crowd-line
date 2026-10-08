class_name Line
extends RefCounted
## 线路：一条线的站点序列、颜色、班次与列车。

var id: int = 0
var name: String = ""
var color: Color = Color.WHITE
var station_ids: Array[int] = []

var headway: float = 12.0      # 班次间隔（秒）
var base_speed: float = 120.0  # 基准速度

var trains: Array = []  # Array[Train]

# 玩家操作状态
var frequency_mod: float = 1.0  # 调班次：班次间隔倍率（<1 更密）

# 延误传播记录
var delay_level: float = 0.0


func effective_headway() -> float:
	return maxf(2.0, headway * frequency_mod)


func has_station(sid: int) -> bool:
	return sid in station_ids


func index_of_station(sid: int) -> int:
	return station_ids.find(sid)
