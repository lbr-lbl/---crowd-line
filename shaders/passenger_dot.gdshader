shader_type canvas_item;
render_mode blend_mix, unshaded;
// 乘客图形：**圆头 + 正三角（男）/ 倒三角（女）**。
//
// 为什么不用贴图：贴图放大就糊，而这个游戏近景会放得很大。
// 这里全部**程序化**画出来（SDF），任何缩放下都是锐的，也不需要新素材。
//
// 接口不变（乘客层照旧 `draw_texture_rect` 画一个方块）：
//   UV     = 方块内归一化坐标 0..1 -> 图形定义在这个坐标系里
//   COLOR  = 乘客层给的调制色（按耐心值变色那一套）与透明度
//   VERTEX = 该点在世界里的位置 -> 当**相位种子**，同屏的人不会整齐划一
//
// 动作（都由 TIME + 相位驱动，不需要模拟层额外喂数据）：
//   · 呼吸：身体纵向极慢涨落；单个人看不出，一片人一起呼吸就有"活的"感觉
//   · 踱步：左右小幅摆动，各人相位不同
//   · 拥挤推挤：`press` 越大抖得越强 —— 这是"涌现感"的关键
//
// `press`（0..1）由乘客层每帧写入（取全图最挤的那个站）。

// 拥挤程度：0 = 宽松，1 = 挤爆
uniform float press : hint_range(0.0, 1.0) = 0.0;

// **展开度**：0 = M 视野下的一个圆点，1 = L 视野下的"圆头 + 三角身"。
// 用户澄清："乘客铺开指的是**单个乘客**由 M 视野下的圆点展开成 L 下的圆头和三角形身。"
uniform float figure : hint_range(0.0, 1.0) = 1.0;

// **摇摆幅度开关**：站台上的人在走动 -> 左右摇摆打开；站着的人只上下平动（用户要求）。
uniform float walk_amt : hint_range(0.0, 1.0) = 0.7;

// 图形度量（都归一化到方块内）。
// ⚠ 头与身体**必须相交**：之前头底 0.35、身体顶 0.43，中间留了 0.08 的缝，
// 于是"圆 + 三角"分裂成两块孤立形状 —— 看起来像**枫叶**、很割裂（用户反馈）。
// 现在让三角形的**尖伸进头里**（身体顶 0.33 < 头底 0.37），轮廓连成一个整体，
// 三角的尖被头挡住，露出来的就是"圆头 + 三角身"的经典人形。
const float HEAD_Y = 0.19;      // 头心高度
const float HEAD_R = 0.18;      // 头半径
const float BODY_TOP = 0.33;    // 身体上沿（= 三角尖，藏在头里）
const float BODY_BOT = 0.96;    // 身体下沿（= 三角底）
const float BODY_HW = 0.38;     // 三角底边半宽
const float TAU_F = 6.2831853;

// 相位由**顶点着色器**算好后传给片元。
// ⚠ 绝对不要在 fragment 里对 `VERTEX` 做 `floor()`/哈希：
//   fragment 的 `VERTEX` 是**逐像素插值**的，`floor` 会在一个方块**内部**跳变，
//   哈希一放大就变成逐像素的伪随机值 —— 形状每个像素都不一样，
//   表现就是"乘客全是离散的像素点"（用户看到的正是这个）。
varying float v_ph;

// 由世界位置给出的稳定相位（同屏不齐闪；同一个人不会每帧变）
float phase_of(vec2 world) {
	return fract(sin(dot(floor(world * 0.5), vec2(12.9898, 78.233))) * 43758.5453);
}

// **平滑并集**。头和身体的接合处**不能有凹口**：
// 硬 `min()` 会在圆与三角相交处留下两个凹角，加上三角底的两个角，
// 整个轮廓就有四个尖 —— 读起来就是"枫叶"（用户反馈，且一直都有，与脖子缝无关）。
// 用 smin 把两个形状融成一条连续轮廓，凹角被填成圆角。k 越大过渡越圆。
float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

void vertex() {
	// 相位在顶点阶段算一次 -> 整个方块共享一个常数
	v_ph = phase_of(VERTEX);
	// 拥挤推挤：**幅度要克制**（0.9 -> 0.25）。原来 0.9 世界单位 ≈ 近景 11 像素的随机抖动，
	// 叠加起来就是"一群细菌在爆开"（用户反馈）。
	VERTEX += vec2(sin(TIME * 3.1 + v_ph * 31.0), cos(TIME * 2.7 + v_ph * 27.0)) * (press * 0.25);
}

void fragment() {
	float ph = v_ph;
	// 性别：由相位派生一个稳定位（一个人不会中途变性）
	bool female = fract(ph * 7.130) > 0.5;

	// 动效原则（用户要求）：**让身体整体动起来**，不要"长出手脚"。
	// 所以只做两件**刚体变换**（形状完全不变）：
	//   · 站立：整体上下平动（bob）
	//   · 走动：以**脚跟为支点**整体轻微摆动。
	// ⚠ 幅度要**小**（约 3 度）。原来 8 度时头离支点最远、横向位移最大，
	// 看起来像"以脖子为支点"在晃（用户反馈）。
	float bob = 0.022 * sin(TIME * 1.7 + ph * TAU_F);
	float lean = 0.05 * walk_amt * sin(TIME * 1.05 + ph * TAU_F);

	vec2 u = UV - vec2(0.5, 1.0);     // 原点移到脚跟：y 从 -1（顶）到 0（脚）
	float cs = cos(lean);
	float sn = sin(lean);
	u = vec2(u.x * cs - u.y * sn, u.x * sn + u.y * cs);
	u.y += bob;
	vec2 q = u + vec2(0.5, 1.0);      // 回到方块坐标（y: 0 = 顶，1 = 底）
	vec2 uv = q - vec2(0.5, 0.5);
	float y = q.y;

	// 头：圆
	float head = length(vec2(uv.x, y - HEAD_Y)) - HEAD_R;

	// 身体：**无分支**的锥形（正三角 / 倒三角）。
	// 原来写的是 `if (t >= 0 && t <= 1) halfw = ...`，范围外 `halfw = -1`，
	// 于是 SDF 在边界处**跳变** -> `fwidth` 爆掉 -> 边会碎成锯齿（用户反馈的"破碎感"）。
	// 用 clamp + max 把"竖向范围"并进 SDF，就没有跳变了。
	float t = clamp((y - BODY_TOP) / (BODY_BOT - BODY_TOP), 0.0, 1.0);
	float halfw = female ? (1.0 - t) * BODY_HW : t * BODY_HW;
	float body = max(abs(uv.x) - halfw, max(BODY_TOP - y, y - BODY_BOT));

	// 点（M 视野）= 实心圆；图形（L 视野）= 头 + 三角身；按 figure 插值
	float dot_mask = length(UV - vec2(0.5)) - 0.40;
	float d = mix(dot_mask, smin(head, body, 0.075), figure);
	// 软边收窄（×0.9）：之前 ×1.2 在 48 像素的方块上偏糊，读起来像一团
	float aa = max(fwidth(d) * 0.9, 0.0012);
	float mask = 1.0 - smoothstep(-aa, aa, d);
	if (mask <= 0.002) {
		discard;
	}
	COLOR = vec4(COLOR.rgb, COLOR.a * mask);
}
