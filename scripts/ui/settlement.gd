class_name Settlement
extends Control
## 结算界面：积分明细、评级徽章、历史最佳。
## 界面本体在 scenes/settlement.tscn 里搭好，本脚本只填文本与徽章图。

signal restart_requested
signal menu_requested

const BADGE_PATH := "res://assets/icons/badge_%s.png"

@onready var reason_label: Label = $Center/Box/ReasonLabel
@onready var rating_badge: TextureRect = $Center/Box/RatingRow/RatingBadge
@onready var rating_label: Label = $Center/Box/RatingRow/RatingLabel
@onready var score_label: Label = $Center/Box/ScoreLabel
@onready var best_label: Label = $Center/Box/BestLabel
@onready var detail_label: Label = $Center/Box/DetailLabel
@onready var restart_button: Button = $Center/Box/Buttons/RestartButton
@onready var menu_button: Button = $Center/Box/Buttons/MenuButton

var metrics: Dictionary = {}
var reason: String = ""
var network_id: String = ""
var new_record: bool = false


func _ready() -> void:
	restart_button.pressed.connect(func(): restart_requested.emit())
	menu_button.pressed.connect(func(): menu_requested.emit())
	hide()


func setup(p_reason: String, p_metrics: Dictionary, p_network_id: String) -> void:
	reason = p_reason
	metrics = p_metrics
	network_id = p_network_id
	var score: float = p_metrics.get("total_score", 0.0)
	new_record = AppState.record_result(network_id, score)
	_refresh()


func _refresh() -> void:
	var rating := str(metrics.get("rating", "D"))
	reason_label.text = reason
	rating_label.text = "评级 %s" % rating
	# 评级徽章：assets/icons/badge_S..D.png
	var path := BADGE_PATH % rating
	if ResourceLoader.exists(path):
		rating_badge.texture = load(path)
		rating_badge.visible = true
	else:
		rating_badge.visible = false
	score_label.text = "总分 %d" % int(metrics.get("total_score", 0))
	if new_record:
		best_label.text = "★ 新纪录！"
	else:
		var best: float = AppState.high_scores.get(network_id, 0)
		best_label.text = "历史最佳 %d 分" % int(best)
	_detail_text()


func _detail_text() -> void:
	var served: int = metrics.get("served", 0)
	var target: int = metrics.get("target_served", 0)
	detail_label.text = "准点率 %.0f%% · 满意度 %.0f%% · 吞吐 %d/%d\n安全 %.0f%% · 效率 %.0f%%" % [
		metrics.get("punctuality", 0.0) * 100,
		metrics.get("satisfaction", 0.0) * 100,
		served, target,
		metrics.get("safety", 0.0) * 100,
		metrics.get("efficiency", 0.0) * 100,
	]
	# 无限模式：成绩主要是"撑到第几波、线网长到多大"
	if bool(metrics.get("infinite", false)):
		detail_label.text += "\n撑到第 %d 波 · 站点 %d · 线路 %d" % [
			int(metrics.get("wave", 0)),
			int(metrics.get("stations", 0)),
			int(metrics.get("lines", 0)),
		]
