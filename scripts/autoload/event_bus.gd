extends Node
## 全局信号总线。
## 模拟层、渲染层、UI 层之间通过 EventBus 解耦，避免直接引用。

# --- 时间与天气 ---
signal hour_changed(hour: float)
signal period_changed(period: String)
signal weather_changed(weather: String)

# --- 模拟 ---
signal passenger_arrived(station_id: int)
signal station_density_changed(station_id: int, density: float, queue_size: int)
signal station_panic(station_id: int, level: float)
signal train_delayed(line_id: int, delay: float)
signal stampede(station_id: int)

# --- 事件与肉鸽 ---
signal event_triggered(event: Dictionary)
signal upgrade_offer(choices: Array)
signal upgrade_chosen(upgrade: Dictionary)

# --- 积分 ---
signal metrics_changed(metrics: Dictionary)
signal game_over(reason: String, metrics: Dictionary)

# --- 交互 ---
signal selection_changed(target: Dictionary)
signal operation_applied(op: String, target_id: int)
signal toast(message: String)
signal pause_requested(paused: bool)
