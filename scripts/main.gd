extends Node
## 应用入口：状态机 菜单 -> 游戏 -> 结算。

var menu: MainMenu
var game: Game
var settlement: Settlement

var current_network: String = ""
var current_mode: String = "entry"


func _ready() -> void:
	_show_menu()


func _show_menu() -> void:
	if settlement:
		settlement.queue_free()
		settlement = null
	menu = MainMenu.new()
	add_child(menu)
	menu.start_requested.connect(_start_game)


func _start_game(network_id: String, mode: String) -> void:
	current_network = network_id
	current_mode = mode
	if menu:
		menu.queue_free()
		menu = null
	if settlement:
		settlement.queue_free()
		settlement = null
	if game:
		game.queue_free()
	game = Game.new()
	add_child(game)
	game.setup(network_id, mode)
	game.finished.connect(_on_finished)


func _on_finished(reason: String, metrics: Dictionary) -> void:
	if game:
		game.queue_free()
		game = null
	_show_settlement(reason, metrics)


func _show_settlement(reason: String, metrics: Dictionary) -> void:
	settlement = Settlement.new()
	add_child(settlement)
	settlement.setup(reason, metrics, current_network)
	settlement.restart_requested.connect(func(): _start_game(current_network, current_mode))
	settlement.menu_requested.connect(_show_menu)
