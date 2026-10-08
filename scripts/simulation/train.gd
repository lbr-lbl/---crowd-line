class_name Train
extends RefCounted
## 地铁列车：容量、班次、速度、延误传播。

var id: int = 0
var line_id: int = 0
var capacity: int = 80

# 沿线路位置：station_ids[from_idx] -> station_ids[to_idx]，progress 0..1
var from_idx: int = 0
var to_idx: int = 1
var progress: float = 0.0
var direction: int = 1

var speed: float = 120.0  # 世界单位/秒（沿线路径）
var dwell_timer: float = 0.0
var dwell_time: float = 3.0

# 延误（秒），>0 表示晚点
var delay: float = 0.0
var delay_source_line: int = -1

var passengers: Array = []  # Array[Passenger]

enum TrainState { MOVING, DWELL }
var state: int = TrainState.MOVING


func is_full() -> bool:
	return passengers.size() >= capacity


func load_passenger(p: Passenger) -> void:
	passengers.append(p)


func unload_passenger(p: Passenger) -> void:
	passengers.erase(p)
