class_name WeatherSystem
extends Node
## 天气系统：天气直接改参数，与昼夜叠加。

var weather: String = "clear"
var intensity: float = 0.0       # 0..1 平滑过渡
var target_intensity: float = 0.0

# 事件驱动的临时天气（如暴雨），到期自动恢复
var timed_weather: String = ""
var timed_remaining: float = 0.0


func _ready() -> void:
	EventBus.weather_changed.emit(weather)


func set_weather(w: String, immediate: bool = false) -> void:
	if w == weather and timed_weather == "":
		return
	weather = w
	target_intensity = 1.0
	if immediate:
		intensity = 1.0
	EventBus.weather_changed.emit(weather)


func trigger_timed(w: String, duration: float) -> void:
	timed_weather = w
	timed_remaining = duration
	set_weather(w)


func tick(delta: float) -> void:
	# 平滑过渡
	intensity = lerpf(intensity, target_intensity, clampf(delta * 2.0, 0.0, 1.0))

	# 定时天气恢复
	if timed_weather != "":
		timed_remaining -= delta
		if timed_remaining <= 0.0:
			timed_weather = ""
			set_weather("clear")


func get_weather() -> String:
	return weather


func get_label() -> String:
	return Config.WEATHER_PARAMS.get(weather, {}).get("label", "晴")


func get_demand_multiplier() -> float:
	return Config.WEATHER_PARAMS.get(weather, {}).get("demand", 1.0)


func get_speed_multiplier() -> float:
	return Config.WEATHER_PARAMS.get(weather, {}).get("speed", 1.0)


func is_raining() -> bool:
	return weather == "light_rain" or weather == "heavy_rain"


func is_snowing() -> bool:
	return weather == "snow"
