class_name WeatherParticles
extends Node2D
## 天气粒子：雨、雪，在屏幕空间绘制。

var sim: Simulation

const RAIN_COUNT := 180
const SNOW_COUNT := 120

var drops: Array = []  # 每个 drop: {pos: Vector2, vel: Vector2, len: float}


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_update_drops(delta)
	queue_redraw()


func _update_drops(delta: float) -> void:
	if sim == null:
		return
	var rain := sim.weather.is_raining() and sim.weather.intensity > 0.05
	var snow := sim.weather.is_snowing() and sim.weather.intensity > 0.05
	if not rain and not snow:
		drops.clear()
		return

	var target_count: int = RAIN_COUNT if rain else SNOW_COUNT
	while drops.size() < target_count:
		var vp := get_viewport_rect().size
		if snow:
			drops.append({"pos": Vector2(randf() * vp.x, randf() * vp.y), "vel": Vector2(randf_range(-12, 12), randf_range(30, 60)), "len": 0.0})
		else:
			drops.append({"pos": Vector2(randf() * vp.x, randf() * vp.y), "vel": Vector2(randf_range(-60, -30), randf_range(380, 560)), "len": randf_range(10, 18)})
	while drops.size() > target_count:
		drops.pop_back()

	var vp := get_viewport_rect().size
	for d in drops:
		d["pos"] += d["vel"] * delta
		if d["pos"].y > vp.y + 20:
			d["pos"] = Vector2(randf() * vp.x, -20.0)
		if d["pos"].x < -40:
			d["pos"].x = vp.x + 20
		if d["pos"].x > vp.x + 40:
			d["pos"].x = -20


func _draw() -> void:
	if sim == null:
		return
	var rain := sim.weather.is_raining() and sim.weather.intensity > 0.05
	var snow := sim.weather.is_snowing() and sim.weather.intensity > 0.05
	if not rain and not snow:
		return
	var alpha := sim.weather.intensity
	if snow:
		for d in drops:
			draw_circle(d["pos"], 2.0, Color(1, 1, 1, 0.5 * alpha))
	else:
		for d in drops:
			var p: Vector2 = d["pos"]
			var len: float = d["len"]
			var vel: Vector2 = d["vel"]
			var end: Vector2 = p + vel.normalized() * len
			draw_line(p, end, Color(0.6, 0.75, 0.9, 0.35 * alpha), 1.5)
