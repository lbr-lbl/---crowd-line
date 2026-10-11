class_name PauseOverlay
extends Control
## 暂停概览：评分、游戏时长、继续、退出到主菜单。
## 界面本体在 scenes/pause_overlay.tscn 里（编辑器里可直接预览/拖拽），本脚本只填数据。

signal resume_requested
signal quit_requested

@onready var rating_label: Label = $Center/Card/Box/RatingLabel
@onready var score_label: Label = $Center/Card/Box/ScoreLabel
@onready var duration_label: Label = $Center/Card/Box/DurationLabel
@onready var metrics_label: Label = $Center/Card/Box/MetricsLabel
@onready var extra_label: Label = $Center/Card/Box/ExtraLabel
@onready var resume_button: Button = $Center/Card/Box/Buttons/ResumeButton
@onready var quit_button: Button = $Center/Card/Box/Buttons/QuitButton


func _ready() -> void:
	resume_button.pressed.connect(func(): resume_requested.emit())
	quit_button.pressed.connect(func(): quit_requested.emit())
	hide()


func open(sim: Simulation) -> void:
	refresh(sim)
	show()


func refresh(sim: Simulation) -> void:
	if sim == null or sim.score == null:
		return
	var m: Dictionary = sim.score.metrics()
	rating_label.text = "评级 %s" % str(m.get("rating", "D"))
	score_label.text = "总分 %d" % int(m.get("total_score", 0))
	duration_label.text = _duration_text(sim)
	metrics_label.text = "准点率 %.0f%%　满意度 %.0f%%\n吞吐 %d/%d　安全 %.0f%%　效率 %.0f%%" % [
		float(m.get("punctuality", 0.0)) * 100.0,
		float(m.get("satisfaction", 0.0)) * 100.0,
		int(m.get("served", 0)), int(m.get("target_served", 0)),
		float(m.get("safety", 0.0)) * 100.0,
		float(m.get("efficiency", 0.0)) * 100.0,
	]
	# 无限模式追加"撑到第几波、线网多大"
	if sim.infinite_mode and sim.director != null:
		extra_label.visible = true
		extra_label.text = "第 %d 波　站点 %d　线路 %d" % [
			sim.director.wave, sim.stations.size(), sim.lines.size()]
	else:
		extra_label.visible = false


## 游戏时长：普通模式给「已进行 / 总时长（剩 …）」，无限模式只给已进行
func _duration_text(sim: Simulation) -> String:
	var done := _mmss(sim.elapsed)
	if sim.infinite_mode or sim.duration <= 0.0:
		return "已运营 %s" % done
	return "运营时长 %s / %s（剩 %s）" % [
		done, _mmss(sim.duration), _mmss(maxf(0.0, sim.duration - sim.elapsed))]


static func _mmss(sec: float) -> String:
	var s := int(maxf(0.0, sec))
	return "%d:%02d" % [s / 60, s % 60]
