shader_type canvas_item;
render_mode blend_mix, unshaded;
// 全屏氛围层：暗角 + 夜间压暗 + 紧急泛红 + 雷雨闪电。
//
// 这一层盖在线路/站点之上、HUD 之下（CanvasLayer），所以它**只影响观感，不碰模拟**。
// 所有 uniform 都由 scripts/rendering/screen_fx.gd 每帧写入，前三个做了平滑过渡，
// 不会出现"到了整点画面突然变黑"这种跳变；flash 是故意做"突跳"的（闪电就该是突跳）。

uniform float night : hint_range(0.0, 1.0) = 0.0;      // 夜间程度（时段驱动，平滑趋近）
uniform float vignette : hint_range(0.0, 1.0) = 0.55;  // 暗角强度
uniform float alert : hint_range(0.0, 1.0) = 0.0;      // 紧急程度（踩踏/大范围恐慌）
uniform float flash : hint_range(0.0, 1.0) = 0.0;      // 雷雨闪电：整体泛白

uniform vec4 night_tint : source_color = vec4(0.04, 0.07, 0.20, 1.0);
uniform vec4 alert_tint : source_color = vec4(0.70, 0.06, 0.10, 1.0);
uniform vec4 vignette_tint : source_color = vec4(0.02, 0.03, 0.06, 1.0);
// 必须是 source_color（Godot 4 里 vec4 的颜色提示只认这个）。
// 用 hint_color 会让着色器**编译失败**，Godot 就退回用 ColorRect 自带的白色画一整屏纯白——
// 现象是"闪电永远不灭"。而用 source_color + 纯白 (1,1,1) 就没有色彩空间问题：
// 1.0 在线性/非线性空间都是 1.0，混合出来必定是 255。
uniform vec4 flash_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	// 椭圆暗角：横向压一点，更贴近屏幕比例
	vec2 p = UV - vec2(0.5);
	p.x *= 1.22;
	float d = clamp(length(p) * 1.68, 0.0, 1.0);
	float vig = smoothstep(0.42, 1.0, d) * vignette;

	vec3 col = mix(vignette_tint.rgb, night_tint.rgb, night);
	float a = vig * 0.55 + night * 0.30;
	// 紧急：主要在边缘泛红（中间尽量留清楚，方便救火）
	a = min(0.92, a + alert * 0.34 * smoothstep(0.18, 1.0, d));
	col = mix(col, alert_tint.rgb, alert);
	// 闪电：**颜色恒为纯白，只让不透明度跟着 flash 走**。
	//
	// 不能写成 `col = mix(col, flash_tint, flash)` —— col 在部分闪电时是
	// "暗夜色 v.s. 白"的中间灰，于是闪电一弱反而把亮部（纸面）压暗，
	// 观感是"蒙了一层灰雾"而不是"啪地亮一下"（实测纸面 241 → 192）。
	// 用 max() 保证闪电只会让画面更亮，永远不会更暗。
	if (flash > 0.001) {
		col = vec3(1.0);
		a = max(a, flash * 0.92);
	}
	COLOR = vec4(col, a);
}
