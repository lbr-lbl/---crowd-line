class_name OpsLog
extends RefCounted
## 运营日志：记录**特殊事件 / 特殊天气 / 玩家操作**，每条带开始与结束时间。
##
## 时间同时记两份：游戏内时钟标签（08:15，和画面上方一致，给玩家看）与 `elapsed`
## （模拟秒，便于排序/调试）。这样日志里显示的时间跟玩家在 HUD 上看到的是同一套。
##
## 一条"还在进行"的条目 `end_t` 为 -1、`end_clock` 为空，界面显示"进行中"。

const MAX_ENTRIES := 80

var entries: Array[Dictionary] = []


## 追加一条。同 kind 上一条还"进行中"的会先被收尾（天气切换、连续同类操作）。
func note(kind: String, text: String, elapsed: float, clock: String, ref: Dictionary = {}) -> int:
	close_open(kind, elapsed, clock)
	entries.append({
		"kind": kind,
		"text": text,
		"start_t": elapsed,
		"start_clock": clock,
		"end_t": -1.0,
		"end_clock": "",
		"ref": ref,
	})
	if entries.size() > MAX_ENTRIES:
		entries = entries.slice(entries.size() - MAX_ENTRIES)
	EventBus.log_updated.emit()
	return entries.size() - 1


## 追加一条**瞬时**记录（开始=结束）：玩家操作、突发事件这类没有"持续时段"的东西。
func note_point(kind: String, text: String, elapsed: float, clock: String, ref: Dictionary = {}) -> int:
	entries.append({
		"kind": kind,
		"text": text,
		"start_t": elapsed,
		"start_clock": clock,
		"end_t": elapsed,
		"end_clock": clock,
		"ref": ref,
	})
	if entries.size() > MAX_ENTRIES:
		entries = entries.slice(entries.size() - MAX_ENTRIES)
	EventBus.log_updated.emit()
	return entries.size() - 1


## 把某 kind 最近一条"进行中"的条目收尾（例如天气从"暴雨"切回"晴"）
func close_open(kind: String, elapsed: float, clock: String) -> void:
	for i in range(entries.size() - 1, -1, -1):
		if str(entries[i]["kind"]) == kind and float(entries[i]["end_t"]) < 0.0:
			entries[i]["end_t"] = elapsed
			entries[i]["end_clock"] = clock
			EventBus.log_updated.emit()
			return


func close_index(i: int, elapsed: float, clock: String) -> void:
	if i < 0 or i >= entries.size():
		return
	if float(entries[i]["end_t"]) < 0.0:
		entries[i]["end_t"] = elapsed
		entries[i]["end_clock"] = clock
		EventBus.log_updated.emit()


## 一行展示文本："08:15 → 08:47　演唱会散场：温州奥体中心"
func line_for(e: Dictionary) -> String:
	var s := str(e["start_clock"])
	var en := str(e["end_clock"]) if float(e["end_t"]) >= 0.0 else "进行中"
	return "%s → %s　%s" % [s, en, str(e["text"])]


static func kind_label(kind: String) -> String:
	match kind:
		"event": return "事件"
		"weather": return "天气"
		"operation": return "操作"
		"wave": return "波次"
	return kind
