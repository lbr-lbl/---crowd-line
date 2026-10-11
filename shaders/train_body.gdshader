shader_type canvas_item;
// 镂空胶囊车身。逐车数据走顶点 COLOR —— 一个 CanvasItem 里的多列车就能各自动各自的，
// 不必每辆车一个材质：
//   COLOR.r = 车速 0..1    COLOR.g = 正在减速 0..1
//   COLOR.b = 停站剩余 1..0  COLOR.a = 载客率 0..1（镂空部分的填充量）
//
// 形状用"超椭圆" `pow(|x|,n)+pow(|y|,n)` 表达圆角端：它与宽高比无关，
// 所以同一条线上编组长度不同的车、以及远景拉长后的车，都不需要每辆车改 uniform。

uniform vec4 body_color : source_color = vec4(0.10, 0.70, 0.95, 1.0);
uniform vec4 ink_color : source_color = vec4(0.09, 0.13, 0.22, 1.0);
uniform float roundness : hint_range(1.5, 8.0) = 3.4;
uniform float shell : hint_range(0.5, 0.98) = 0.80;  // 内壁位置：越小壳越厚

void fragment() {
	vec2 p = UV * 2.0 - 1.0;   // -1..1
	float speed = clamp(COLOR.r, 0.0, 1.0);
	float brake = clamp(COLOR.g, 0.0, 1.0);
	float dwell = clamp(COLOR.b, 0.0, 1.0);
	float load  = clamp(COLOR.a, 0.0, 1.0);

	// 超椭圆距离场：rr < 1 在车身内
	float rr = pow(pow(abs(p.x), roundness) + pow(abs(p.y), roundness), 1.0 / roundness);
	float aa = max(fwidth(rr) * 1.5, 0.004);

	float body = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, rr);
	if (body <= 0.003) {
		discard;
	}
	float inner = 1.0 - smoothstep(shell - aa, shell + aa, rr);

	// 载客率：从左端向右填充内腔
	float edge = -1.0 + 2.0 * load;
	float fillmask = 1.0 - smoothstep(edge - aa * 2.0, edge + aa * 2.0, p.x);
	float fill = inner * fillmask;

	vec3 outline = mix(ink_color.rgb, body_color.rgb, 0.88);
	vec3 liquid = mix(body_color.rgb, vec3(1.0), 0.10);

	// 灯带：车越快跑得越快（只在内腔里，像液体表面的一道反光）
	float sweep = fract((p.x * 0.5 + 0.5) - TIME * (0.12 + speed * 0.75));
	float band = exp(-pow((sweep - 0.5) / 0.22, 2.0)) * (0.18 + 0.42 * speed);
	liquid = mix(liquid, vec3(1.0), band);

	// 刹车灯：减速时尾端（-x）泛红
	float tail = smoothstep(-0.35, -1.0, p.x) * brake;
	liquid = mix(liquid, vec3(1.0, 0.28, 0.22), tail * 0.85);
	outline = mix(outline, vec3(1.0, 0.38, 0.30), tail * 0.55);

	// 车头灯：低速（正要进站）时前端更亮
	float head = smoothstep(0.35, 1.0, p.x) * (1.0 - speed);
	outline = mix(outline, vec3(1.0, 1.0, 0.88), head * 0.35);

	// 停站：整体压暗半档，像灭了半灯
	outline *= mix(1.0, 0.86, dwell * (1.0 - speed));

	COLOR = vec4(mix(outline, liquid, fill), body);
}
