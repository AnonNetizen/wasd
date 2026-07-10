shader_type canvas_item;
render_mode blend_mix;

// 边缘须状 runner：从 creep 结节向外伸出的"手指"。
// 根部暗茄紫、尖端亮品红，沿线有爬行流动脉冲，按 growth 渐显。

uniform float time = 0.0;
uniform float growth_amount = 1.0;
uniform float decay_amount = 0.0;
uniform float activation = 0.0;
uniform float line_phase = 0.0;
uniform float flow_speed = 0.16;
uniform float growth_start = 0.0;
uniform float growth_end = 1.0;
uniform float strand_width = 2.0;
uniform vec4 dormant_color : source_color = vec4(0.280, 0.070, 0.220, 0.70);
uniform vec4 active_color : source_color = vec4(0.620, 0.160, 0.460, 0.80);
uniform vec4 pulse_color : source_color = vec4(0.980, 0.550, 0.850, 0.70);

void fragment() {
	float reveal = smoothstep(growth_start, growth_end, growth_amount);
	float along = UV.x;                        // 0=根, 1=尖
	float across = abs(UV.y * 2.0 - 1.0);      // 0=中心, 1=边缘
	float taper = 1.0 - smoothstep(0.55, 1.0, along);          // 向尖端变细
	float core = 1.0 - smoothstep(0.0, 0.85, across);
	float feather = (1.0 - smoothstep(0.5, 1.0, across)) * 0.30;
	float crawl = fract(along * 1.6 - time * flow_speed + line_phase);
	float pulse = smoothstep(0.85, 1.0, crawl) * smoothstep(0.0, 0.18, crawl);
	float breathing = 0.85 + sin(time * 1.4 + line_phase + along * 3.5) * 0.10;
	float tip = smoothstep(0.35, 1.0, along);

	vec4 base = mix(dormant_color, active_color, activation);
	vec3 color = base.rgb;
	color = mix(color, pulse_color.rgb, tip * 0.6);                       // 尖端提亮
	color += pulse_color.rgb * pulse * (0.20 + activation * 0.50);        // 流动脉冲高光
	color = mix(color, dormant_color.rgb * 0.6, decay_amount * 0.40);

	float alpha = (core + feather) * base.a * taper * breathing;
	alpha += pulse * pulse_color.a * (0.30 + activation * 0.40);
	alpha *= 0.5 + min(strand_width, 3.0) * 0.12;
	alpha *= max(0.14, reveal);
	alpha *= 1.0 - decay_amount * 0.60;

	COLOR = vec4(color, alpha) * COLOR;
}
