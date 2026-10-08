class_name ScoreSystem
extends RefCounted
## 积分系统：准点率、满意度、吞吐量、安全分、效率分。

var served: int = 0
var target_served: float = 600.0

var arrivals_total: int = 0
var arrivals_on_time: int = 0

var satisfaction_sum: float = 0.0
var satisfaction_samples: int = 0

var wait_time_total: float = 0.0
var wait_count: int = 0

var safety: float = 1.0


func reset(p_target: float) -> void:
	served = 0
	target_served = p_target
	arrivals_total = 0
	arrivals_on_time = 0
	satisfaction_sum = 0.0
	satisfaction_samples = 0
	wait_time_total = 0.0
	wait_count = 0
	safety = 1.0


func record_arrival(on_time: bool) -> void:
	arrivals_total += 1
	if on_time:
		arrivals_on_time += 1


func record_served(wait_time: float) -> void:
	served += 1
	wait_time_total += wait_time
	wait_count += 1


func sample_satisfaction(avg_patience: float) -> void:
	satisfaction_sum += avg_patience
	satisfaction_samples += 1


func add_safety_penalty(amount: float) -> void:
	safety = maxf(0.0, safety - amount)


func punctuality() -> float:
	if arrivals_total == 0:
		return 1.0
	return float(arrivals_on_time) / float(arrivals_total)


func satisfaction() -> float:
	if satisfaction_samples == 0:
		return 1.0
	return clampf(satisfaction_sum / satisfaction_samples, 0.0, 1.0)


func throughput_ratio() -> float:
	return clampf(float(served) / target_served, 0.0, 1.0)


func efficiency() -> float:
	if wait_count == 0:
		return 1.0
	var avg_wait := wait_time_total / wait_count
	# 平均等待越短效率越高，60 秒映射到 0
	return clampf(1.0 - avg_wait / 60.0, 0.0, 1.0)


func total_score() -> float:
	var s := punctuality() * 1000.0
	s += satisfaction() * 1000.0
	s += throughput_ratio() * 800.0
	s += safety * 800.0
	s += efficiency() * 400.0
	return s


func metrics() -> Dictionary:
	return {
		"punctuality": punctuality(),
		"satisfaction": satisfaction(),
		"throughput": throughput_ratio(),
		"safety": safety,
		"efficiency": efficiency(),
		"served": served,
		"target_served": int(target_served),
		"total_score": total_score(),
		"rating": Config.rating_for_score(total_score()),
	}


func live_metrics() -> Dictionary:
	return {
		"punctuality": punctuality(),
		"satisfaction": satisfaction(),
		"throughput": throughput_ratio(),
		"safety": safety,
		"efficiency": efficiency(),
		"served": served,
		"target_served": int(target_served),
	}
