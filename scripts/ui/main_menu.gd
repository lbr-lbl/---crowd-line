class_name MainMenu
extends Control
## 主菜单：选择"线路池"（→随机抽线网），开始游戏。
## 界面本体在 scenes/main_menu.tscn 里搭好，本脚本只绑定节点与刷新文案。

signal start_requested(network_id: String, mode: String)

@onready var pool_option: OptionButton = $Center/Box/PoolOption
@onready var pool_desc_label: Label = $Center/Box/PoolDesc
@onready var highscore_label: Label = $Center/Box/HighScore
@onready var start_button: Button = $Center/Box/StartButton


func _ready() -> void:
	pool_option.clear()
	for pid in NetworkPool.list_pool_ids():
		pool_option.add_item(NetworkPool.pool_label(pid))
	pool_option.item_selected.connect(func(_i): refresh_pool_info())
	start_button.pressed.connect(_on_start)
	refresh_pool_info()


func _current_pool_id() -> String:
	var pids := NetworkPool.list_pool_ids()
	if pool_option.selected < 0 or pool_option.selected >= pids.size():
		return "entry"
	return pids[pool_option.selected]


func refresh_pool_info() -> void:
	var pid := _current_pool_id()
	pool_desc_label.text = NetworkPool.pool_desc(pid)
	# 随机抽一条展示这个名字，让玩家知道会进哪条线
	var rand_net := NetworkPool.random_network(pid)
	highscore_label.text = "本次将从「%s」中随机进入一条线网" % NetworkPool.pool_label(pid)
	if rand_net != "":
		highscore_label.text += "\n示例线网：%s" % NetworkLoader.get_network_name(rand_net)


func _on_start() -> void:
	var pid := _current_pool_id()
	# 从池中随机抽一条真实线网
	var network_id := NetworkPool.random_network(pid)
	# 难度由池决定（等级/教学），并向下兼容手动翻倍键
	var mode := NetworkPool.pool_mode(pid)
	AppState.selected_network_id = network_id
	AppState.selected_mode = mode
	start_requested.emit(network_id, mode)
