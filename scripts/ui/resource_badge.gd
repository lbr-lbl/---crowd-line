class_name ResourceBadge
extends Control
## 右下角的资源徽章：**金色圆圈 + 圈内数值**（需求：资源从指标面板移出来放这里）。
##
## · 数值是平滑滚动的（`_shown` 追 `value`），所以加钱时能看见数字在涨；
## · 加钱时金色环脉冲一下 + 浮出一个 `+n`；
## · 单位按地区给（`UNIT_BY_CITY`），没有对应地区就不带单位。

const RADIUS := 34.0

## 各地区货币单位。表里没有的地区就不显示单位。
const UNIT_BY_CITY: Dictionary = {
	"温州": "元", "重庆": "元", "成都": "元",
	"台北": "元", "香港": "元", "里斯本": "€",
}

const GOLD := Color("#d4a017")
const GOLD_DARK := Color("#8a6a08")

var value: float = 0.0
var unit: String = ""

var _shown: float = 0.0
var _pulse: float = 0.0
var _gain: float = 0.0          # 待浮出的增量（正数才浮）
var _gain_t: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func set_value(v: float, city: String = "") -> void:
	var d := v - value
	value = v
	unit = str(UNIT_BY_CITY.get(city, ""))
	if d > 0.5:
		# 只有"增加"才做动效（扣费是日常操作，每次都闪会烦）
		_pulse = 1.0
		_gain = d
		_gain_t = 1.0


func _process(delta: float) -> void:
	_shown = lerpf(_shown, value, 1.0 - exp(-7.0 * delta))
	if absf(_shown - value) < 0.4:
		_shown = value
	_pulse = maxf(0.0, _pulse - delta * 1.8)
	_gain_t = maxf(0.0, _gain_t - delta * 0.9)
	queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.5)
	var r := RADIUS + _pulse * 6.0
	# 金色圆：外深内亮，做出一点金属感
	draw_circle(c, r, GOLD_DARK)
	draw_circle(c, r - 3.0, GOLD)
	draw_circle(c, r - 3.0, Color(1.0, 0.97, 0.86, 0.55), false, 2.0, true)
	# 数值：圈内居中。数字长了就把字号压小，保证不出圈
	var txt := "%d" % int(round(_shown))
	var fs := 22 if txt.length() <= 3 else (18 if txt.length() <= 4 else 14)
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var ty := c.y + (fs * 0.36) + (2.0 if unit != "" else 0.0)
	draw_string(font, c - Vector2(w * 0.5, 0) + Vector2(0, ty - c.y), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.18, 0.12, 0.02))
	if unit != "":
		var uw := font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, Vector2(c.x - uw * 0.5, c.y + 20.0), unit,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.25, 0.18, 0.05))
	# 加钱时浮出的 +n
	if _gain_t > 0.0:
		var a := clampf(_gain_t, 0.0, 1.0)
		draw_string(font, Vector2(c.x - 12.0, c.y - r - 6.0 - (1.0 - a) * 22.0),
			"+%d" % int(round(_gain)), HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			Color(0.80, 0.15, 0.18, a))
