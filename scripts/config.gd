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
# 画面基调：浅色"图纸"底 + 深墨前景（Mini Metro 那种简约亮色），
# 所以面板是半透明白、文字是墨色；世界里的线/站/点统一用 ink() 压深保证对比度。
const COLOR_BG_BASE := Color("#e6eef7")
const COLOR_PANEL := Color(1.0, 1.0, 1.0, 0.78)
const COLOR_PANEL_SOLID := Color(0.98, 0.99, 1.0, 0.94)
const COLOR_STROKE := Color(0.22, 0.28, 0.40, 0.85)

# 墨色：所有"压在浅底上"的前景都往这里压
const COLOR_INK := Color("#182236")
const COLOR_INK_SOFT := Color("#46536b")

# HUD 文字色
const COLOR_TEXT := Color("#1b2436")
const COLOR_TEXT_DIM := Color("#5a6a86")
const COLOR_TEXT_ACCENT := Color("#b4611f")

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

# 时段 -> 底色（亮色纸感：晨蓝 / 早高峰暖桃 / 平峰冷蓝 / 午近白 /
# 午后暖纸 / 晚高峰粉 / 夜浅板岩 / 深夜更沉的板岩）
const PERIOD_BG: Dictionary = {
	"dawn": Color("#dbe6f2"),
	"morning_peak": Color("#fbe6d2"),
	"flat": Color("#e6eef7"),
	"noon": Color("#eff4fa"),
	"afternoon": Color("#f1ece1"),
	"evening_peak": Color("#f9dcd2"),
	"night": Color("#c9d4e6"),
	"late_night": Color("#b9c6dd"),
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
	"clear":        {"demand": 1.00, "speed": 1.00, "label": "晴"},
	"overcast":     {"demand": 0.95, "speed": 1.00, "label": "阴"},
	"light_rain":   {"demand": 1.10, "speed": 0.95, "label": "小雨"},
	"heavy_rain":   {"demand": 1.20, "speed": 0.90, "label": "暴雨"},
	"thunderstorm": {"demand": 1.15, "speed": 0.88, "label": "雷暴"},
	"typhoon":      {"demand": 0.55, "speed": 0.65, "label": "台风"},
	"heatwave":     {"demand": 1.22, "speed": 0.95, "label": "酷热"},
	"fog":          {"demand": 1.00, "speed": 0.88, "label": "大雾"},
	# 雪只对"snowy"气候带的线网开放（见 resources/real_world.json），
	# 本项目现有的南方线网全部禁用它——不会出现"香港下雪"。
	"snow":         {"demand": 0.90, "speed": 0.85, "label": "雪"},
}

# ---- 车辆段 / 编组延长 ----
# 「加车」（凭空多一列车）被替换为「升级车辆」：先建车辆段，再下达加挂指令 ——
# 线路上下一列停靠车辆段站的列车，在该站就地多停几秒加挂一节车厢（增加定员）。
# 旧版是"把整列车抽下线路 24 秒去编组"，实测那是严格劣势策略：台北两条线各自
# 只有 2 列车，抽走 1 列等于该线运力腰斩，满意度直接从 0.74 掉到 0.58。
# 现在车不离开线路，代价只剩"那几秒站台占用" —— 而这几秒的贵贱由时刻决定，
# 这才是"分时规划"的真正取舍：平峰又快又便宜，高峰又慢又贵。
const DEPOT: Dictionary = {
	"build_cost": 55.0,        # 建车辆段（每条线一次）
	"base_cost": 40.0,         # 第一次加挂的基准费用（还要乘下面的分时系数）
	"cost_growth": 0.55,       # 该线每加挂一次，费用乘 (1 + 已加挂次数 × 本值)
	"car_capacity": 40,        # 每节车厢定员
	"min_cars": 2,             # 初始编组 2 节 = 80 人
	"max_cars": 6,             # 编组上限
	"cars_per_upgrade": 1,     # 每次加挂增加几节
	# —— 分时规划（C）：需求倍率 ≤ load_low 算平峰，≥ load_high 算高峰，中间线性插值 ——
	"couple_dwell_flat": 5.0,  # 平峰：列车在段站多停几秒
	"couple_dwell_peak": 12.0, # 高峰：同样一次加挂要占更久的站台
	"cost_flat": 0.75,         # 平峰折扣（费用 × 0.75）
	"cost_peak": 1.35,         # 高峰加价（费用 × 1.35）
	"load_low": 0.5,           # 需求倍率归一化下界
	"load_high": 2.0,          # 需求倍率归一化上界
}

# ---- 玩家操作的资源价格（D）----
# 车辆段之外，限流/封站/跳站/广播也要花钱。实测数据：改造前「只建车辆段、从不送车」
# 与「完全不操作」两种打法**逐位同分**（温州 978 人 / 3748 分 / 满意 0.81 完全一致）——
# 因为全工程只有建段与编组两处扣资源，钱是白送的，建段等于零成本试错。
# 定价之后，资源第一次有了竞争用途：留着钱等下一班加挂，还是现在花掉压住这个爆站。
const OPERATION_COST: Dictionary = {
	"limit": 15.0,      # 每次限流（持续 30s，可反复使用）
	"close": 12.0,      # 每次封站（持续 20s）
	"skip": 12.0,       # 每次跳站（持续 20s）
	"broadcast": 20.0,  # 每次广播（冷却 30s）
}

# ---- 无限模式导演参数 ----
# 无限模式没有"时间到"：每过 wave_seconds 就往线网里加一个新站 + 一条新线，
# 同时把客流与事件密度往上推。玩家不是在"撑到终点"，而是在"能撑多少波"。
const INFINITE: Dictionary = {
	"wave_seconds": 75.0,          # 每波间隔（现实秒）
	"new_stations_per_wave": 1,    # 每波新增站点数
	"max_lines": 12,               # 线路数上限；到顶后只继续加压，不再加线
	"line_min_stops": 3,           # 新线站数下限
	"line_max_stops": 5,           # 新线站数上限
	"max_leg_dist": 170.0,         # 新线相邻两站的最大间距
	"station_jitter_min": 60.0,    # 新站离母站的距离下限
	"station_jitter_max": 130.0,   # 新站离母站的距离上限
	"spawn_growth": 0.09,          # 每波基准客流 ×(1 + 本值)
	"spawn_cap": 48.0,             # 基准客流上限
	"event_scale_per_wave": 0.93,  # 每波事件/升级间隔 ×本值（越来越密）
	"target_growth": 260.0,        # 每波吞吐目标增量，让"吞吐比"始终保持意义
	"resource_bonus": 40.0,        # 每波奖励资源
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
	"infinite": {
		"label": "无限模式",
		"duration": 0.0,          # 0 = 不限时：只靠"撑不住"结束，不看钟
		"time_speed": 2.4,
		"start_hour": 6.0,
		"target_served": 900,
		"score_goal": 99999,
	},
}


# ---- 静态工具函数 ----

## 某个玩家操作的资源价格（未定价的操作返回 0）
static func operation_cost(op: String) -> float:
	return float(OPERATION_COST.get(op, 0.0))


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


## 把任何前景色压向墨色，用在浅色底上保证辨识度。
static func ink(c: Color, amount: float) -> Color:
	return c.lerp(COLOR_INK, clampf(amount, 0.0, 1.0))


# ---- 视野尺寸补偿（"放大 = 把东西拉开"，不是"把东西画大"）----
#
# 用户要求：滚轮放大时**不应该把乘客、线路这些本身放大**，而应该把站点之间、
# 乘客之间的距离拉开，让人"看得见更多空隙"。
#
# 做法：世界坐标继续交给 Camera2D 缩放（于是间距自然被拉开），但渲染层里所有
# **看起来应该恒定大小**的东西——站点环、乘客点、线宽、进度环、车辆段方框、
# 热力光晕——都必须除以当前相机缩放，抵消掉相机的放大。
#
# VIEW_SIZE_POW 留成可调：1.0 = 完全恒定屏幕尺寸（严格按用户要求）；
# 调小（如 0.5）就变成"放大一点点"，可以权衡"放大了但近景别太空"。
const VIEW_SIZE_POW := 1.0


## 把"屏幕像素"换算成当前缩放下的世界单位（渲染层**符号尺寸**统一走这里）
static func view_px(v: float, zoom: float) -> float:
	return v / pow(maxf(zoom, 0.001), VIEW_SIZE_POW)


## 布局间距的补偿指数，与 VIEW_SIZE_POW 分开：
##   1.0 = 间距也恒定（放大后人和站分不开，只剩"空"）
##   0.0 = 间距完全随缩放（放大后人群被撒得满屏都是，看不出谁在哪个站等）
##   0.5 = 屏幕上按 √zoom 缓慢拉开 —— 既"看得见空隙"，人群又还围着本站
const VIEW_SPREAD_POW := 0.5


## 布局间距（乘客围绕站点的散布半径等）走这里
static func view_spread(v: float, zoom: float) -> float:
	return v / pow(maxf(zoom, 0.001), VIEW_SPREAD_POW)


# ---- 列车运动手感 ----
# 远景（全貌段）把车身拉长、加粗：**视野缩得越远，车身越长**（用户要求），所以倍率给得明显。
const TRAIN_FAR_LEN := 2.3
const TRAIN_FAR_H := 1.5

# 出站加速 / 进站减速：把段内进度映射成速度倍率。
# TRAIN_ACCEL_PART = 段的前百分之多少在加速；TRAIN_DECEL_PART = 后百分之多少在减速；
# TRAIN_MIN_FACTOR = 端点处最低速度倍率（不设 0，否则班次会被拉爆）。
#
# ⚠ **这不是纯视觉参数**：它改变列车在段内的**速度分布**，进而改变排队与扎堆的动力学。
# ⚠ 参数给小的坑：一段路本身只有 1 秒出头，如果加速段只占 24%（约 0.25 秒），
#   肉眼**根本抓不到**——用户连续两轮反馈"加减速看不出来"就是这个原因。
#   现在取消匀速中段（0.45 + 0.45 ≈ 整段都在变），整段都是"起步慢 - 中间快 - 进站慢"，看得清。
# 时间精确归一化保证**全程耗时不变**，所以观感变了但平衡不变（仍需重跑基线核对）。
# `TRAIN_MIN_FACTOR = 1.0` 时该曲线退化为恒等（等于完全关掉这个效果）。
const TRAIN_ACCEL_PART := 0.45
const TRAIN_DECEL_PART := 0.45
const TRAIN_MIN_FACTOR := 0.30


## 符号（站点 / 列车）随缩放一起放大缩小的倍率。
##
## **全貌段（H）最小，越放大越大** —— 需求原文："H 视野列车应该最小才对" +
## "希望站点也跟列车一并放大缩小"。（之前我按"远景拉长"做成了反的，已改正。）
##
## 以近景锚点为 1.0，用 **√** 而不是线性：从全貌到近景大约放大 3 倍，
## 既看得出"放大就变大"，又不至于在全貌段小到认不出来。
const VIEW_GROW_POW := 0.5
const VIEW_GROW_MIN := 0.38
const VIEW_GROW_MAX := 2.6


static func view_grow(zoom: float, fore_zoom: float) -> float:
	if fore_zoom <= 0.001:
		return 1.0
	return clampf(pow(maxf(zoom, 0.001) / fore_zoom, VIEW_GROW_POW), VIEW_GROW_MIN, VIEW_GROW_MAX)

## 硬核池的客流基准倍率。用户反馈"硬核放着不动也随便通关"，所以从 1.6 调到 1.8。
## 只影响 hardcore 一档，入门/进阶的手感不动。
const HARDCORE_SPAWN_MULT := 1.8

## 硬核池的**绝对客流下限**（人/秒）。
## 为什么需要它：基准客流是按地图站数算的（`clampf(站数*0.5, 2, 12)`），
## 于是"小地图 + 硬核"的绝对客流太低 —— 实测温州（7 站）硬核**放着不动也能跑满 720 秒**拿 B，
## 而重庆（12 站）硬核同样不动 150 秒就崩。光调倍率只会把小图和大图一起推爆。
## 加了下限之后：小图的硬核被抬到和大图同一量级，两张图都真的难。
const HARDCORE_MIN_SPAWN := 9.5


## 速度曲线的**时间精确归一化**系数：让 ∫dp/v(p) = 1，即"全程耗时严格不变"。
## 注意不能用算术平均（= 曲线下面积）来归一：算术平均保住的是"平均速度"，
## 而实际耗时是 ∫dp/v，两者差一个 AM–HM 不等式（按面积归一会让耗时变长约 2%）。
##   加速段 ∫dp/raw = a·ln(1/m)/(1−m)，减速段同，中段 1−a−d
##   所以 K = 1 / ( 2a·ln(1/m)/(1−m) + (1−a−d) )
static var _profile_k: float = 0.0


static func _compute_profile_k() -> float:
	var a := TRAIN_ACCEL_PART
	var d := TRAIN_DECEL_PART
	var m := TRAIN_MIN_FACTOR
	# 端点速度 = 1.0 时曲线是恒等，分母会 0/0，必须短路
	if m >= 0.999:
		return 1.0
	var time_area := 2.0 * a * log(1.0 / m) / (1.0 - m) + (1.0 - a - d)
	return 1.0 / maxf(time_area, 0.0001)


## 段内进度(0..1) -> 速度倍率：出站加速、途中匀速、进站减速。
## 已按"耗时不变"归一化，所以只改变速度的分布（观感），不改变通勤时间（平衡）。
static func train_speed_factor(progress: float) -> float:
	if _profile_k <= 0.0:
		_profile_k = _compute_profile_k()
	var p := clampf(progress, 0.0, 1.0)
	var f := 1.0
	if p < TRAIN_ACCEL_PART:
		f = lerpf(TRAIN_MIN_FACTOR, 1.0, p / TRAIN_ACCEL_PART)
	if p > 1.0 - TRAIN_DECEL_PART:
		f = minf(f, lerpf(TRAIN_MIN_FACTOR, 1.0, (1.0 - p) / TRAIN_DECEL_PART))
	return f * _profile_k


## 底色 -> 屏幕顶部的渐变端（更亮）
static func paper_top(c: Color) -> Color:
	return c.lerp(Color.WHITE, 0.42)


## 底色 -> 屏幕底部的渐变端（更沉）
static func paper_bottom(c: Color) -> Color:
	return c.lerp(Color("#8fa2bf"), 0.16)


## 根据站点密度(0..1+)映射热力色：绿->黄->红->深红
static func heat_color(density: float) -> Color:
	var d := clampf(density, 0.0, 1.3)
	if d < 0.5:
		return COLOR_NORMAL.lerp(COLOR_WAITING, d / 0.5)
	elif d < 1.0:
		return COLOR_WAITING.lerp(COLOR_CROWDED, (d - 0.5) / 0.5)
	else:
		return COLOR_CROWDED.lerp(Color("#6d1024"), clampf((d - 1.0) / 0.3, 0.0, 1.0))


## 乘客状态 -> 颜色
static func passenger_color(state: int) -> Color:
	match state:
		0: return COLOR_NORMAL
		1: return COLOR_WAITING
		2: return COLOR_CROWDED
		_: return COLOR_PANIC


static func line_color(index: int) -> Color:
	return LINE_PALETTE[index % LINE_PALETTE.size()]


## 时段 -> 画面"鲜艳度"：高峰最艳，深夜最沉。
## 浅色底上这个值决定颜色往墨色里压多深。
static func vibrancy_for_period(period: String) -> float:
	match period:
		"morning_peak", "evening_peak":
			return 1.0
		"night", "late_night":
			return 0.55
		_:
			return 0.8


## 线路在地图上**实际画出来的颜色**：JSON 里的线色按当前活力压向墨色。
## 线路本体（GameView）与列车（LineTrainView）都必须走这一个函数，
## 否则会出现"绿线上的车是青色的"这种色不对板——
## 之前列车用的是 `Config.line_color(ln.id)`（调色板按序号取），和 JSON 线色是两套源。
static func line_draw_color(base: Color, vibrancy: float) -> Color:
	return ink(base, lerpf(0.46, 0.28, clampf(vibrancy, 0.0, 1.0)))


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
