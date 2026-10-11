shader_type canvas_item;
// 亮色"图纸"底：上下渐变 + 极淡点阵网格 + 缓慢漂移的光泽 + 收边暗角。
// 由 RenderLayer/Game 每帧传入当前时段的 top/bottom 色。

uniform vec4 top_color : source_color = vec4(0.93, 0.96, 0.99, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.85, 0.89, 0.95, 1.0);
uniform vec4 grid_color : source_color = vec4(0.42, 0.54, 0.74, 1.0);
uniform float grid_alpha : hint_range(0.0, 0.6) = 0.13;
uniform float grid_step : hint_range(8.0, 200.0) = 58.0;
uniform vec2 cam_offset = vec2(0.0);
uniform float mood : hint_range(0.0, 1.0) = 0.5;   // 0 夜间沉 / 1 白天亮
uniform float drift : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = mix(top_color.rgb, bottom_color.rgb, uv.y);

	// 点阵网格：随相机轻微反向平移，制造视差
	vec2 g = (FRAGCOORD.xy + cam_offset * 0.14 + vec2(TIME * 1.5, TIME * 0.6)) / grid_step;
	vec2 cell = abs(fract(g) - vec2(0.5));
	float grid_dot = 1.0 - smoothstep(0.03, 0.095, length(cell));
	col = mix(col, grid_color.rgb, grid_dot * grid_alpha * (0.4 + 0.6 * mood));

	// 大尺度斜向光泽，避免纯色发闷
	float glow = sin((uv.x * 0.9 + uv.y * 1.3) * 3.14159 + drift * 6.28318) * 0.5 + 0.5;
	col *= mix(0.985, 1.02, glow);

	// 收边：四周轻微压暗，画面有边界感
	float vig = smoothstep(0.0, 0.20, uv.y) * smoothstep(1.0, 0.80, uv.y)
		* smoothstep(0.0, 0.09, uv.x) * smoothstep(1.0, 0.91, uv.x);
	col *= mix(0.90, 1.0, vig);

	COLOR = vec4(col, 1.0);
}
