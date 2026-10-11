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

# 车辆段：每条线一个。建好后下达加挂指令，线路上下一列停靠段站的列车就地加长编组。
var depot_built: bool = false
var depot_station_idx: int = 1   # 车辆段所在站（本线 station_ids 的下标）
var depot_station_override: int = -1  # 线网 JSON 的 depot_station（站点 id）；-1 = 自动选址
var depot_upgrades: int = 0      # 该线已完成的加挂次数（决定下次费用）
var pending_couples: int = 0     # 已下达、还在等列车停靠段站的加挂指令数


## 车辆段所在站的站点 id（未建成时也给出规划位置，便于渲染"待建"标记）
func depot_station_id() -> int:
	if station_ids.is_empty():
		return -1
	var i := clampi(depot_station_idx, 0, station_ids.size() - 1)
	return station_ids[i]


## 正在段站就地加挂的那列车；没有则返回 null。
## 与"只是下了单还没兑现"（pending_couples > 0）是两回事，UI 文案要分开。
func coupling_train() -> Train:
	for t in trains:
		if t.coupling:
			return t
	return null


## 该线车辆段是否忙：有指令在等车，或正有列车在段站加挂
func depot_busy() -> bool:
	return pending_couples > 0 or coupling_train() != null


## 该线编组最长的列车节数（用于显示"最大编组"）
func max_cars() -> int:
	var m := 0
	for t in trains:
		m = maxi(m, t.cars)
	return m


func effective_headway() -> float:
	return maxf(2.0, headway * frequency_mod)


func has_station(sid: int) -> bool:
	return sid in station_ids


func index_of_station(sid: int) -> int:
	return station_ids.find(sid)
