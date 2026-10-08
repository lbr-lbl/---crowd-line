class_name Config
extends RefCounted
## 全局常量与调色板、时间曲线、难度预设。

# ---- 线路霓虹调色板 ----
const LINE_PALETTE: Array[Color] = [
	Color("#00e5ff"),  # 青
	Color("#ff2d78"),  # 品红
	Color("#ffe100"),  # 黄
	Color("#00ff88"),  # 绿
	Color("#ff8c00"),  # 橙
	Color("#b455ff"),  # 紫
]

# ---- 乘客状态颜色（绿=正常 黄=等待 红=拥堵 紫=恐慌）----
const COLOR_NORMAL := Color("#4ade80")
const COLOR_WAITING := Color("#ffd23f")
const COLOR_CROWDED := Color("#ff5c5c")
const COLOR_PANIC := Color("#c084fc")

# ---- 基础 UI 色 ----
const COLOR_BG_BASE := Color("#0e0e1e")
const COLOR_PANEL := Color(0.06, 0.07, 0.12, 0.82)
const COLOR_STROKE := Color(0.35, 0.45, 0.6, 0.9)

# ---- 昼夜时段（小时区间 -> 时段名）----
const PERIODS := [
	[5.0, "dawn"],
	[7.0, "morning_peak"],
	[9.0, "flat"],
	[11.0, "noon"],
	[13.0, "afternoon"],
	[17.0, "evening_peak"],
	[19.0, "night"],
	[23.0, "late_night"],
]

# 需求曲线关键点 (hour, multiplier)，中间线性插值
const DEMAND_CURVE: Array = [
	[0.0, 0.25],
	[5.0, 0.5],
	[7.0, 2.0],
	[9.0, 0.9],
	[11.0, 1.1],
	[13.0, 0.8],
	[17.0, 2.2],
	[19.0, 0.5],
	[23.0, 0.25],
	[24.0, 0.25],
]

# 时段 -> 背景色（夜黑 / 晨蓝紫 / 平峰灰蓝 / 午蓝 / 晚红 / 深夜）
const PERIOD_BG: Dictionary = {
	"dawn": Color("#1a1a3e"),
	"morning_peak": Color("#2e1a1a"),
	"flat": Color("#1e2a3e"),
	"noon": Color("#1a2a3e"),
	"afternoon": Color("#1c2836"),
	"evening_peak": Color("#3e1a1a"),
	"night": Color("#0e0e1e"),
	"late_night": Color("#0a0a16"),
}

# 时段 -> 乘客耐心衰减速率（每秒耐心损失，值越大越不耐烦）
const PERIOD_PATIENCE_DECAY: Dictionary = {
	"dawn": 0.010,
	"morning_peak": 0.035,
	"flat": 0.012,
	"noon": 0.015,
	"afternoon": 0.014,
	"evening_peak": 0.030,
	"night": 0.022,
	"late_night": 0.026,
}

# 时段 -> 从众性（影响恐慌传播）
const PERIOD_CONFORMITY: Dictionary = {
	"dawn": 0.3,
	"morning_peak": 0.7,
	"flat": 0.3,
	"noon": 0.4,
	"afternoon": 0.4,
	"evening_peak": 0.75,
	"night": 0.4,
	"late_night": 0.35,
}

# ---- 天气参数 ----
const WEATHER_PARAMS: Dictionary = {
	"clear":      {"demand": 1.00, "speed": 1.00, "label": "晴"},
	"overcast":   {"demand": 0.95, "speed": 1.00, "label": "阴"},
	"light_rain": {"demand": 1.10, "speed": 0.95, "label": "小雨"},
	"heavy_rain": {"demand": 1.20, "speed": 0.90, "label": "暴雨"},
	"snow":       {"demand": 0.90, "speed": 0.85, "label": "雪"},
	"fog":        {"demand": 1.00, "speed": 0.90, "label": "雾"},
}

# ---- 难度预设 ----
const DIFFICULTY: Dictionary = {
	"tutorial": {
		"label": "教程池",
		"duration": 240.0,        # 秒
		"time_speed": 4.0,        # 游戏内小时 / 现实分钟
		"start_hour": 6.0,
		"target_served": 120,
		"score_goal": 500,
	},
	"entry": {
		"label": "入门池",
		"duration": 300.0,        # 秒
		"time_speed": 4.8,        # 游戏内小时 / 现实分钟
		"start_hour": 6.0,
		"target_served": 600,
		"score_goal": 1000,
	},
	"advance": {
		"label": "进阶池",
		"duration": 480.0,
		"time_speed": 3.0,
		"start_hour": 6.0,
		"target_served": 1200,
		"score_goal": 3000,
	},
	"hardcore": {
		"label": "硬核池",
		"duration": 720.0,
		"time_speed": 2.0,
		"start_hour": 6.0,
		"target_served": 2400,
		"score_goal": 6000,
	},
}


# ---- 静态工具函数 ----

static func hex_to_color(hex: String) -> Color:
	if hex.begins_with("#"):
		hex = hex.substr(1)
	return Color(hex)


static func period_for_hour(hour: float) -> String:
	var h := fmod(hour, 24.0)
	var result := "late_night"
	for entry in PERIODS:
		if h >= entry[0]:
			result = entry[1]
		else:
			break
	return result


static func demand_multiplier(hour: float) -> float:
	var h := fmod(hour, 24.0)
	if h <= float(DEMAND_CURVE[0][0]):
		return float(DEMAND_CURVE[0][1])
	for i in range(DEMAND_CURVE.size() - 1):
		var a: Array = DEMAND_CURVE[i]
		var b: Array = DEMAND_CURVE[i + 1]
		var a0 := float(a[0])
		var a1 := float(a[1])
		var b0 := float(b[0])
		var b1 := float(b[1])
		if h >= a0 and h <= b0:
			var t: float = 0.0 if b0 == a0 else (h - a0) / (b0 - a0)
			return lerpf(a1, b1, t)
	return float(DEMAND_CURVE[DEMAND_CURVE.size() - 1][1])


static func bg_color(hour: float) -> Color:
	return PERIOD_BG.get(period_for_hour(hour), COLOR_BG_BASE)


## 根据站点密度(0..1+)映射热力色：绿->黄->红->白
static func heat_color(density: float) -> Color:
	var d := clampf(density, 0.0, 1.3)
	if d < 0.5:
		return COLOR_NORMAL.lerp(COLOR_WAITING, d / 0.5)
	elif d < 1.0:
		return COLOR_WAITING.lerp(COLOR_CROWDED, (d - 0.5) / 0.5)
	else:
		return COLOR_CROWDED.lerp(Color.WHITE, clampf((d - 1.0) / 0.3, 0.0, 1.0))


## 乘客状态 -> 颜色
static func passenger_color(state: int) -> Color:
	match state:
		0: return COLOR_NORMAL
		1: return COLOR_WAITING
		2: return COLOR_CROWDED
		_: return COLOR_PANIC


static func line_color(index: int) -> Color:
	return LINE_PALETTE[index % LINE_PALETTE.size()]


## 积分评级
static func rating_for_score(score: float) -> String:
	if score < 1000.0:
		return "D"
	elif score < 3000.0:
		return "C"
	elif score < 5000.0:
		return "B"
	elif score < 7000.0:
		return "A"
	return "S"
