shader_type canvas_item;
// 镂空胶囊车身。逐车数据走顶点 COLOR —— 一个 CanvasItem 里的多列车就能各自动各自的，
// 不必每辆车一个材质：
//   COLOR.r = 车速 0..1    COLOR.g = 正在减速 0..1
//   COLOR.b = 停站剩余 1..0  COLOR.a = 载客率 0..1
//
// **载客率的表现 = 车身内部的不透明度**（用户选定：不要"液体"那套）。
// 空车几乎是透的（只剩外壳），越挤内部越实。
//
// 形状用"超椭圆" `pow(|x|,n)+pow(|y|,n)` 表达圆角端：它与宽高比无关，
// 所以同一条线上编组长度不同的车、以及远景拉长后的车，都不需要每辆车改 uniform。

uniform vec4 body_color : source_color = vec4(0.10, 0.70, 0.95, 1.0);
uniform vec4 ink_color : source_color = vec4(0.09, 0.13, 0.22, 1.0);
uniform float roundness : hint_range(1.5, 8.0) = 3.4;
// 内壁位置：越小壳越厚。**0.80 是回调过的值** —— 之前用 0.60 在 H/M 上显得轮廓过粗。
uniform float shell : hint_range(0.3, 0.98) = 0.80;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;   // -1..1
	float speed = clamp(COLOR.r, 0.0, 1.0);
	float load  = clamp(COLOR.a, 0.0, 1.0);

	// 超椭圆距离场：rr < 1 在车身内
	float rr = pow(pow(abs(p.x), roundness) + pow(abs(p.y), roundness), 1.0 / roundness);
	float aa = max(fwidth(rr) * 1.5, 0.004);

	float body = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, rr);
	if (body <= 0.003) {
		discard;
	}

	// 壳 = 描边带；内部 = 车身色（不透明度由载客率给）
	float outer = smoothstep(shell - aa, shell + aa, rr);   // 1 = 在描边带里
	// 描边**只比线路深一点**（原来是 ×0.42，H/M 上看着太深）
	vec3 outline = mix(body_color.rgb, ink_color.rgb, 0.25);
	vec3 col = mix(body_color.rgb, outline, outer);

	// **载客率 = 内部不透明度**：空车几乎透（0.14），满车实心（1.0）
	float interior_a = mix(0.14, 1.0, load);
	float a = mix(interior_a, 1.0, outer);

	// 液面式的流动反光已随"液体"方案一起去掉，只留一点随车速的明暗呼吸，
	// 让车在跑动时不至于完全静止。
	a *= 1.0 - 0.10 * speed * (1.0 - load);

	COLOR = vec4(col, a * body);
}
