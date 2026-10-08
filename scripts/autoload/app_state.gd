extends Node
## 跨场景持久状态：菜单 -> 游戏 -> 结算 之间共享选择与成绩。

const SAVE_PATH := "user://crowd_line_highscores.json"

var selected_network_id: String = "wenzhou_s1"
var selected_mode: String = "entry"

var last_metrics: Dictionary = {}
var last_score: float = 0.0
var last_rating: String = "D"
var last_network_name: String = ""

var high_scores: Dictionary = {}  # network_id -> best score


func _ready() -> void:
	load_highscores()


func record_result(network_id: String, score: float) -> bool:
	var best: float = high_scores.get(network_id, -1.0)
	if score > best:
		high_scores[network_id] = score
		save_highscores()
		return true
	return false


func save_highscores() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(high_scores))


func load_highscores() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		high_scores = data
