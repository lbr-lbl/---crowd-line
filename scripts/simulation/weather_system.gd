class_name WeatherSystem
extends Node
## 天气系统：天气直接改参数，与昼夜叠加。
##
## **天气由现实依据决定**：这张图可能出现哪些天气，查 `RealWorld.allowed_weather()`；
## 抽签用 `RealWorld.roll_weather()`（权重写在 `resources/real_world.json`）。
## 所以"香港不下雪"这种事是**数据驱动**的，代码里没有任何城市名。
##
## 两层来源：
##   · 自然轮替：每隔 `ROLL_MIN..ROLL_MAX` 秒按权重抽一次允许的天气；
##   · 事件驱动（`trigger_timed`）：如"暴雨"持续若干秒，到点自动恢复成自然天气。

const ROLL_MIN := 70.0
const ROLL_MAX := 150.0

var sim: Simulation = null

var weather: String = "clear"
var intensity: float = 0.0       # 0..1 平滑过渡
var target_intensity: float = 0.0

# 事件驱动的临时天气（如暴雨），到期自动恢复
var timed_weather: String = ""
var timed_remaining: float = 0.0

# 下一次自然轮替的倒计时
var roll_timer: float = 0.0


func _ready() -> void:
	EventBus.weather_changed.emit(weather)


## 由 Simulation 在 setup 末尾调用（此时 sim/ops_log 都已就绪）
func setup_cycle() -> void:
	roll_timer = randf_range(ROLL_MIN, ROLL_MAX)
	# 教程局固定晴朗，便于学习；其他模式从**温和天气**里抽开局（不让特殊天气撞上开局早高峰）
	var start := "clear" if (sim != null and sim.tutorial_mode) else RealWorld.roll_weather(_net(), true)
	_apply(start, true)
	_note_weather()


func _net() -> String:
	return sim.network_id if sim != null else ""


func set_weather(w: String, immediate: bool = false) -> void:
	_apply(w, immediate)


func _apply(w: String, immediate: bool) -> void:
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
	_apply(w, false)
	_note_weather()


func tick(delta: float) -> void:
	# 平滑过渡
	intensity = lerpf(intensity, target_intensity, clampf(delta * 2.0, 0.0, 1.0))

	# 事件驱动的临时天气优先：它自己管恢复，恢复后立刻回到自然轮替
	if timed_weather != "":
		timed_remaining -= delta
		if timed_remaining <= 0.0:
			timed_weather = ""
			roll_timer = randf_range(ROLL_MIN, ROLL_MAX)
			_apply(RealWorld.roll_weather(_net()), false)
			_note_weather()
		return

	# 自然轮替
	roll_timer -= delta
	if roll_timer <= 0.0:
		roll_timer = randf_range(ROLL_MIN, ROLL_MAX)
		var nw := RealWorld.roll_weather(_net())
		if nw != weather:
			_apply(nw, false)
			_note_weather()


## 记一条天气日志（`OpsLog.note` 会把上一条"进行中"的天气自动收尾，正好表达"持续时段"）
func _note_weather() -> void:
	if sim == null or sim.ops_log == null:
		return
	sim.ops_log.note("weather", "天气：%s" % get_label(), sim.elapsed, _clock())


func _clock() -> String:
	return sim.time.get_hour_label() if (sim != null and sim.time != null) else "--:--"


func get_weather() -> String:
	return weather


func get_label() -> String:
	return Config.WEATHER_PARAMS.get(weather, {}).get("label", "晴")


func get_demand_multiplier() -> float:
	return Config.WEATHER_PARAMS.get(weather, {}).get("demand", 1.0)


func get_speed_multiplier() -> float:
	return Config.WEATHER_PARAMS.get(weather, {}).get("speed", 1.0)


func is_raining() -> bool:
	return weather in ["light_rain", "heavy_rain", "thunderstorm"]


func is_snowing() -> bool:
	return weather == "snow"


## 天气粒子要不要下雪/下雨（渲染层用）
func particle_kind() -> String:
	if is_snowing():
		return "snow"
	if is_raining():
		return "rain"
	return ""
