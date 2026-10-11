class_name ScreenFx
extends CanvasLayer
## 全屏氛围层：暗角 + 夜间压暗 + 紧急泛红（着色器 `shaders/screen_fx.gdshader`）。
##
## 放在世界之上、HUD 之下，**纯观感**，不参与任何模拟计算。
## 三个量都做了平滑趋近，避免整点跳变。

const SHADER_PATH := "res://shaders/screen_fx.gdshader"

## 各时段的夜间程度（与 Config.vibrancy_for_period 的时段名一致）
const NIGHT_BY_PERIOD: Dictionary = {
	"dawn": 0.28,
	"morning_peak": 0.0,
	"flat": 0.0,
	"afternoon": 0.0,
	"evening_peak": 0.22,
	"night": 0.72,
	"late_night": 1.0,
}

const SMOOTH := 1.6          # 每秒趋近速度（越小越柔和）
const ALERT_DECAY := 0.55    # 紧急泛红的自然衰减速度

var sim: Simulation = null
## 由 Game 在暂停/继续时设置：暂停期间不再闪电，并立刻清掉当前那一下
var paused: bool = false
var _rect: ColorRect = null
var _mat: ShaderMaterial = null
var _night: float = 0.0
var _alert: float = 0.0

# ---- 雷雨闪电 ----
const FLASH_DECAY := 3.6          # 闪电衰减速度（够快才有"啪"的感觉）
var _flash: float = 0.0           # 当前亮度 0..1
var _flickers: int = 0            # 还剩几次补闪（做出"闪闪灭灭"）
var _next_flash: float = 0.0      # 下一次闪电的倒计时


func _ready() -> void:
	layer = 5                     # 世界(0/1)之上、HUD(10)之下
	# **暂停时也继续处理**：否则树一被暂停，这一层的所有 uniform 就冻住，
	# 玩家刚好在闪电那一瞬间按暂停，画面会一直白着（截图工具冻结模拟时也是同一现象）。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH)
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


func _process(delta: float) -> void:
	if sim == null or sim.time == null:
		return
	# 夜间：按当前时段趋近（平滑，避免跳变）
	var want_night := float(NIGHT_BY_PERIOD.get(sim.time.get_period(), 0.0))
	_night = lerpf(_night, want_night, 1.0 - exp(-SMOOTH * delta))
	# 紧急：取"最严重的那个"——踩踏过的站或恐慌中的站
	_alert = maxf(0.0, _alert - delta * ALERT_DECAY)
	_tick_lightning(delta)
	_mat.set_shader_parameter("night", _night)
	_mat.set_shader_parameter("vignette", 0.55)
	_mat.set_shader_parameter("alert", _alert)
	_mat.set_shader_parameter("flash", _flash)


## 雷雨闪电（需求："雷雨天可以有镜头效果，闪闪灭灭"）。
##
## 做法是**两次抖**而不是一次亮：先猛亮一下，衰减到一半再补一记，
## 这样读起来才像"闪、灭一下、再闪"，而不是一盏灯被打开。
## 只有雷暴会闪电；台风偶尔漏一记（现实里台风外围也常有雷电）。
func _tick_lightning(delta: float) -> void:
	var w := sim.weather.get_weather()
	# 暂停 / 结算时必须清掉闪电。
	# 否则玩家刚好在闪电那一瞬间按暂停，画面就会一直白着（截图工具冻结模拟时也是这个现象）。
	if paused or not sim.running:
		_flash = 0.0
		_flickers = 0
		_next_flash = 0.0
		return
	var allow := (w == "thunderstorm") or (w == "typhoon" and randf() < 0.25)
	if not allow:
		_flash = maxf(0.0, _flash - delta * FLASH_DECAY)
		_next_flash = 0.0
		return

	_flash = maxf(0.0, _flash - delta * FLASH_DECAY)
	# 衰减到一半时补第二记（这就是"闪闪灭灭"的来源）
	if _flash > 0.0 and _flash < 0.42 and _flickers > 0:
		_flickers -= 1
		_flash = 0.72
		return
	_next_flash -= delta
	if _next_flash <= 0.0:
		_next_flash = randf_range(1.1, 3.4)
		_flickers = 1 + (1 if randf() < 0.6 else 0)
		_flash = 1.0


## 突发事件时让画面边缘泛红（由 Game 接 EventBus 调用）
func pulse_alert(amount: float) -> void:
	_alert = clampf(maxf(_alert, amount), 0.0, 1.0)


## 手动打一记闪电（截图/调试用）
func pulse_flash(amount: float = 1.0) -> void:
	_flash = clampf(amount, 0.0, 1.0)
	_flickers = 1
