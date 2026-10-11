class_name Game
extends Node2D
## 单局编排：组装模拟、渲染、相机、天气、HUD 与升级覆盖层。
##
## 节点树在 scenes/game.tscn 里搭好（编辑器里能直接看到相机、世界层、HUD 与各个覆盖层），
## 本脚本只负责把模拟对象接上各层、转发事件。字段用 @onready 绑定。

signal finished(reason: String, metrics: Dictionary)
## 玩家在暂停概览里点了"退出到主菜单"
signal quit_requested

@onready var sim: Simulation = $Simulation
@onready var background: BackgroundLayer = $BackgroundLayer/Paper
@onready var camera: Camera2D = $World/Camera2D
@onready var game_view: GameView = $World/GameView
@onready var passenger_layer: PassengerLayer = $World/PassengerLayer
@onready var train_layer: TrainLayer = $World/TrainLayer
@onready var weather_particles: WeatherParticles = $WeatherLayer/WeatherParticles
@onready var hud: HUD = $HUD
@onready var upgrade_ui: UpgradeUI = $OverlayLayer/UpgradeUI
@onready var pause_overlay: PauseOverlay = $OverlayLayer/PauseOverlay
@onready var tutorial_layer: CanvasLayer = $TutorialLayer
@onready var tutorial_ui: TutorialOverlay = $TutorialLayer/TutorialOverlay
@onready var camera_ctrl: CameraController = $CameraController

var network_id: String = ""
var mode: String = "entry"
var paused_flag: bool = false

## 全屏氛围层（暗角 / 夜间压暗 / 紧急泛红），在 setup 里创建
var screen_fx: ScreenFx = null
## 玩家选的推进倍率：0 = 暂停，1 = 正常，2 = 快进（由 HUD 的暂停/播放/快进按钮驱动）
var time_scale: float = 1.0


func setup(p_network_id: String, p_mode: String) -> void:
	network_id = p_network_id
	mode = p_mode

	# 模拟
	sim.setup(network_id, mode)

	# 相机
	camera.make_current()

	# 渲染层：背景着色器、线路/车站/热力、乘客点、列车
	background.sim = sim
	background.camera = camera

	game_view.sim = sim
	game_view.camera = camera

	passenger_layer.sim = sim
	passenger_layer.camera = camera
	passenger_layer.game_view = game_view

	train_layer.sim = sim
	# 轨道几何：GameView 持有并负责重建，列车层与乘客层共用同一份，
	# 这样"折线怎么拐 / 车停在哪 / 乘客点簇躲多远"三件事不会各算一遍而错位
	train_layer.route_geo = game_view.route_geo

	camera_ctrl.setup(camera, sim)
	# 跟车需要列车世界坐标（由 TrainLayer 维护）；镜头点击命中列车也用它
	camera_ctrl.train_source = train_layer

	# 全屏氛围层：暗角 / 夜间压暗 / 紧急泛红。盖在世界之上、HUD 之下，纯观感。
	screen_fx = ScreenFx.new()
	screen_fx.name = "ScreenFx"
	add_child(screen_fx)
	screen_fx.sim = sim
	# 突发事件 -> 震屏 + 边缘泛红（踩踏最重，单站恐慌只轻轻一下）
	EventBus.stampede.connect(_on_stampede)
	EventBus.station_panic.connect(_on_panic)

	# 把三段视野锚点同步给渲染层：全貌段 H 画成分云，中景 M / 近景 L 画乘客点；
	# 列车层用它判断"是不是远景"（远景车身拉长一点）
	game_view.set_zoom_bands(camera_ctrl.overview_zoom, camera_ctrl.mid_zoom, camera_ctrl.fore_zoom)
	train_layer.zoom_bands = Vector3(camera_ctrl.overview_zoom, camera_ctrl.mid_zoom, camera_ctrl.fore_zoom)
	# 右侧视野滑钮：把可缩放的完整区间与三个锚点交给它，三个站点才会落在正确位置
	hud.view_slider.configure(camera_ctrl.min_allowed_zoom, camera_ctrl.max_allowed_zoom,
		camera_ctrl.overview_zoom, camera_ctrl.mid_zoom, camera_ctrl.fore_zoom)

	# 天气粒子（屏幕空间）
	weather_particles.sim = sim

	# HUD
	hud.setup(sim, self)

	# 教程覆盖层（仅教程线路池出现，讲解操作/目标/阻碍）
	# ⚠ 必须同时打开**子节点**：`TutorialOverlay` 在 game.tscn 里是 `visible = false`，
	# 只设父层可见的话教程永远显示不出来（这里曾经漏过，用户报"教程没了"）。
	tutorial_layer.visible = (mode == "tutorial")
	tutorial_ui.visible = (mode == "tutorial")
	if mode == "tutorial":
		tutorial_ui.setup(sim)

	# 升级覆盖层
	upgrade_ui.chosen.connect(_on_upgrade_chosen)
	upgrade_ui.hide()

	# 暂停概览：HUD 的暂停键请求打开，里面的"继续/退出"回到这里
	hud.pause_overview_requested.connect(open_pause_overview)
	pause_overlay.resume_requested.connect(close_pause_overview)
	pause_overlay.quit_requested.connect(func(): quit_requested.emit())

	# 事件
	EventBus.upgrade_offer.connect(_on_upgrade_offer)
	EventBus.game_over.connect(_on_game_over)


# ================= 镜头效果 =================

## 踩踏：最重的反馈（震屏 + 画面边缘泛红）
func _on_stampede(_sid: int) -> void:
	if camera_ctrl != null:
		camera_ctrl.shake(1.0)
	if screen_fx != null:
		screen_fx.pulse_alert(0.85)


## 单站恐慌：只在很严重时轻轻震一下（不然满屏都在抖，反而看不清线）
func _on_panic(_sid: int, level: float) -> void:
	if level < 0.85:
		return
	if camera_ctrl != null:
		camera_ctrl.shake(0.18)
	if screen_fx != null:
		screen_fx.pulse_alert(0.30)


## 供 HUD 日志点击 / 外部调用：镜头飞到某站并短暂高亮
func focus_station(sid: int) -> void:
	if sim == null or camera_ctrl == null:
		return
	var st: Station = sim.get_station(sid)
	if st == null:
		return
	camera_ctrl.set_follow(-1)
	sim.select_station(sid)
	EventBus.selection_changed.emit({"type": "station", "id": sid})
	camera_ctrl.fly_to(st.position, camera_ctrl.mid_zoom)
	EventBus.camera_focus.emit(st.position, sid)


## HUD 的暂停/加速按钮通过它改推进倍率。
## 不用 Engine.time_scale：那会连 Tween、UI 动画、粒子一起变速。
func set_time_scale(v: float) -> void:
	time_scale = clampf(v, 0.0, 4.0)


## 右侧视野滑钮拖出来的目标缩放（走相机控制器，保持与滚轮同一套回弹规则）
func set_view_zoom(z: float) -> void:
	if camera_ctrl != null:
		camera_ctrl.set_zoom_target(z)


## 暂停并弹出概览（评分 / 时长 / 继续 / 退出）。模拟冻结，但相机与 UI 照常刷新。
func open_pause_overview() -> void:
	if sim == null or not sim.running:
		return
	paused_flag = true
	# 告诉氛围层"暂停了"：否则刚好在闪电那一瞬间按暂停，画面会一直白着
	if screen_fx != null:
		screen_fx.paused = true
	pause_overlay.open(sim)


func close_pause_overview() -> void:
	pause_overlay.hide()
	paused_flag = false
	if screen_fx != null:
		screen_fx.paused = false


func _process(delta: float) -> void:
	# 相机是否已稳定停在某个视野段 -> 渲染层据此把站点画成实心 ●
	if camera_ctrl != null and game_view != null:
		game_view.camera_settled = camera_ctrl.is_settled()
	if sim == null or not sim.running or paused_flag:
		return
	# 玩家按了暂停：模拟时间不再推进，但上面的相机/UI 照常刷新
	if time_scale <= 0.0:
		return
	sim.tick(delta * time_scale)


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
