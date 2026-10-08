class_name Game
extends Node2D
## 单局编排：组装模拟、渲染、相机、天气、HUD 与升级覆盖层。

signal finished(reason: String, metrics: Dictionary)

var sim: Simulation
var world: Node2D
var camera: Camera2D
var game_view: GameView
var camera_ctrl: CameraController
var weather_layer: CanvasLayer
var weather_particles: WeatherParticles
var hud: HUD
var overlay_layer: CanvasLayer
var upgrade_ui: UpgradeUI
var tutorial_layer: CanvasLayer
var tutorial_ui: TutorialOverlay

var network_id: String = ""
var mode: String = "entry"
var paused_flag: bool = false


func setup(p_network_id: String, p_mode: String) -> void:
	network_id = p_network_id
	mode = p_mode

	# 模拟
	sim = Simulation.new()
	sim.name = "Simulation"
	add_child(sim)
	sim.setup(network_id, mode)

	# 世界与相机
	world = Node2D.new()
	world.name = "World"
	add_child(world)

	camera = Camera2D.new()
	camera.name = "Camera2D"
	world.add_child(camera)
	camera.make_current()

	game_view = GameView.new()
	game_view.name = "GameView"
	world.add_child(game_view)
	game_view.sim = sim
	game_view.camera = camera

	camera_ctrl = CameraController.new()
	camera_ctrl.name = "CameraController"
	add_child(camera_ctrl)
	camera_ctrl.setup(camera, sim)

	# 把三段视野锚点同步给渲染层：全貌段 H 画成分云，中景 M / 近景 L 画乘客点
	game_view.set_zoom_bands(camera_ctrl.overview_zoom, camera_ctrl.mid_zoom, camera_ctrl.fore_zoom)

	# 天气粒子（屏幕空间）
	weather_layer = CanvasLayer.new()
	weather_layer.layer = 5
	add_child(weather_layer)
	weather_particles = WeatherParticles.new()
	weather_layer.add_child(weather_particles)
	weather_particles.sim = sim

	# HUD
	hud = HUD.new()
	hud.layer = 10
	add_child(hud)
	hud.setup(sim, self)

	# 教程覆盖层（仅教程线路池出现，讲解操作/目标/阻碍）
	if mode == "tutorial":
		tutorial_layer = CanvasLayer.new()
		tutorial_layer.layer = 30
		add_child(tutorial_layer)
		tutorial_ui = TutorialOverlay.new()
		tutorial_layer.add_child(tutorial_ui)
		tutorial_ui.setup(sim)

	# 升级覆盖层
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 20
	add_child(overlay_layer)
	upgrade_ui = UpgradeUI.new()
	overlay_layer.add_child(upgrade_ui)
	upgrade_ui.chosen.connect(_on_upgrade_chosen)
	upgrade_ui.hide()

	# 事件
	EventBus.upgrade_offer.connect(_on_upgrade_offer)
	EventBus.game_over.connect(_on_game_over)


func _process(delta: float) -> void:
	# 相机是否已稳定停在某个视野段 -> 渲染层据此把站点画成实心 ●
	if camera_ctrl != null and game_view != null:
		game_view.camera_settled = camera_ctrl.is_settled()
	if sim == null or not sim.running or paused_flag:
		return
	sim.tick(delta)


func _on_upgrade_offer(choices: Array) -> void:
	paused_flag = true
	upgrade_ui.show_choices(choices)
	upgrade_ui.show()


func _on_upgrade_chosen(id: String) -> void:
	sim.apply_upgrade(id)
	upgrade_ui.hide()
	paused_flag = false


func _on_game_over(reason: String, metrics: Dictionary) -> void:
	finished.emit(reason, metrics)
