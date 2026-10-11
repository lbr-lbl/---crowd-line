extends Node
## 应用入口：状态机 菜单 -> 游戏 -> 结算。
##
## scenes/main.tscn 里已经把三层搭好：菜单层（常驻）、GameHost（每局实例化 scenes/game.tscn）、
## 结算层（常驻，平时隐藏）。本脚本只负责切换。

const GAME_SCENE := preload("res://scenes/game.tscn")

@onready var menu: MainMenu = $MenuLayer/MainMenu
@onready var game_host: Node = $GameHost
@onready var settlement: Settlement = $SettlementLayer/Settlement

var game: Game = null

var current_network: String = ""
var current_mode: String = "entry"


func _ready() -> void:
	menu.start_requested.connect(_start_game)
	settlement.restart_requested.connect(func(): _start_game(current_network, current_mode))
	settlement.menu_requested.connect(_show_menu)
	_show_menu()


func _show_menu() -> void:
	_clear_game()
	settlement.hide()
	menu.show()
	menu.refresh_pool_info()


func _start_game(network_id: String, mode: String) -> void:
	current_network = network_id
	current_mode = mode
	_clear_game()
	menu.hide()
	settlement.hide()
	game = GAME_SCENE.instantiate()
	game_host.add_child(game)
	game.setup(network_id, mode)
	game.finished.connect(_on_finished)
	# 暂停概览里的"退出到主菜单"：直接回菜单，不走结算
	game.quit_requested.connect(_show_menu)


func _clear_game() -> void:
	if game != null:
		game.queue_free()
		game = null


func _on_finished(reason: String, metrics: Dictionary) -> void:
	_clear_game()
	settlement.setup(reason, metrics, current_network)
	settlement.show()
