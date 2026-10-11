shader_type canvas_item;
// 乘客小点：软芯呼吸 + 向外扩散的涟漪环。
// 相位由"节点在世界里的位置"推出，所以同一屏上的点不会齐刷刷一起闪。

uniform float breathe : hint_range(0.0, 1.0) = 0.55;   // 呼吸幅度
uniform float speed : hint_range(0.0, 8.0) = 2.2;      // 呼吸/涟漪速度
uniform float ring_alpha : hint_range(0.0, 1.0) = 0.32;
uniform float ring_width : hint_range(0.02, 0.4) = 0.11;
uniform float core_gain : hint_range(0.0, 2.0) = 1.0;

varying vec2 node_pos;
varying float v_alpha;

void vertex() {
	node_pos = VERTEX;
	v_alpha = COLOR.a;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// 贴图本身是一颗软白球，alpha 就是它的形状
	float shape = tex.a;
	if (shape <= 0.001) {
		discard;
	}

	vec2 c = UV - vec2(0.5);
	float d = length(c) * 2.0;               // 0 = 中心，1 = 贴图边

	float phase = (node_pos.x + node_pos.y) * 0.04;
	float t = TIME * speed * 0.25 + phase;

	// 软芯：整体亮度轻微起伏
	float breath = 1.0 + breathe * 0.16 * sin(t * 2.0);

	// 涟漪：一圈从中心往外走的亮环，走到边就淡掉
	float pulse = fract(t * 0.5);
	float rr = 0.30 + 0.75 * pulse;
	float ring = exp(-pow((d - rr) / ring_width, 2.0)) * (1.0 - pulse);

	float alpha = clamp(shape * v_alpha * breath + shape * ring * ring_alpha * v_alpha, 0.0, 1.0);

	// 芯里再亮一点，浅色底上也看得清
	vec3 rgb = mix(COLOR.rgb, vec3(1.0), smoothstep(1.0, 0.0, d) * 0.16);
	COLOR = vec4(rgb, alpha * core_gain);
}
