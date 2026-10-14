class_name Station
extends RefCounted
## 站点：闸机、站台、换乘通道的抽象。有容量上限与密度阈值。

var id: int = 0
var name: String = ""
var position: Vector2 = Vector2.ZERO
var capacity: int = 120

# 所属线路 id 列表（换乘站有多个）
var lines: Array[int] = []

var queue: Array = []  # Array[Passenger] 等车的乘客

# 玩家操作状态
var entry_limit: float = 1.0   # 限流：进站速率倍率 0..1
var closed: bool = false       # 封站
var skip_trains: bool = false  # 跳站：列车不停靠

# 临时事件状态
var capacity_mod: float = 1.0  # 出口关闭等导致的容量系数

# 恐慌度量 0..1
var panic: float = 0.0

# 统计
var total_served: int = 0
var total_boarded: int = 0

# ---- 纯表现用的上下车标记（渲染层消费，**不参与任何判定**）----
# 每项 = {"kind": 0 下车 / 1 上车, "side": 0 上站台 / 1 下站台}
# 为什么放在模拟层：站位、上下车都是模拟层的事件，渲染层靠差分去猜必然出错
# （互穿、凭空出现、做不出可靠的先下后上）。这里只给**顺序与侧别**，位置由渲染层安排。
var pax_fx: Array = []
## 标记数组的上限：只保留最近这些条，避免长局无限增长
const PAX_FX_MAX := 160


## 记一条上下车标记（超过上限就丢掉最旧的）
func note_pax_fx(kind: int, side: int) -> void:
	pax_fx.append({"kind": kind, "side": side})
	if pax_fx.size() > PAX_FX_MAX:
		pax_fx = pax_fx.slice(pax_fx.size() - PAX_FX_MAX)

# 平滑后的密度（供渲染）
var display_density: float = 0.0


func effective_capacity() -> int:
	return maxi(1, int(capacity * capacity_mod))


func density() -> float:
	return float(queue.size()) / float(effective_capacity())


## 超出容量的比例：>0 表示人群已溢出到站外（渲染层用它表现"门口堵死"）。
func overflow_ratio() -> float:
	return maxf(0.0, density() - 1.0)


func is_interchange() -> bool:
	return lines.size() > 1


func queue_size() -> int:
	return queue.size()
