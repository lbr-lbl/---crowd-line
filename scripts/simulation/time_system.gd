class_name TimeSystem
extends Node
## 昼夜循环：时间驱动需求、速度、恐慌阈值。
## time_speed 单位：游戏内小时 / 现实分钟。

var game_hour: float = 6.0
var time_speed: float = 2.0  # 游戏内小时/分钟
var elapsed: float = 0.0

var current_period: String = "dawn"

# 平滑后的背景色（渲染用，避免突变）
var display_bg: Color = Color("#1a1a3e")


func _ready() -> void:
	current_period = Config.period_for_hour(game_hour)
	display_bg = Config.bg_color(game_hour)


func set_time_speed(speed: float) -> void:
	time_speed = speed


func set_hour(h: float) -> void:
	game_hour = h
	_emit_period()


func tick(delta: float) -> void:
	elapsed += delta
	var prev_hour := game_hour
	game_hour += time_speed * delta / 60.0
	if game_hour >= 24.0:
		game_hour = fmod(game_hour, 24.0)
	_emit_period()
	if int(prev_hour) != int(game_hour):
		EventBus.hour_changed.emit(game_hour)
	# 平滑背景色
	display_bg = display_bg.lerp(Config.bg_color(game_hour), clampf(delta * 0.5, 0.0, 1.0))


func _emit_period() -> void:
	var p := Config.period_for_hour(game_hour)
	if p != current_period:
		current_period = p
		EventBus.period_changed.emit(p)


func get_hour() -> float:
	return game_hour


func get_period() -> String:
	return current_period


func get_demand_multiplier() -> float:
	return Config.demand_multiplier(game_hour)


func get_patience_decay() -> float:
	return Config.PERIOD_PATIENCE_DECAY.get(current_period, 0.015)


func get_conformity() -> float:
	return Config.PERIOD_CONFORMITY.get(current_period, 0.4)


func get_hour_label() -> String:
	var h := int(game_hour) % 24
	var m := int(fmod(game_hour, 1.0) * 60.0)
	return "%02d:%02d" % [h, m]
