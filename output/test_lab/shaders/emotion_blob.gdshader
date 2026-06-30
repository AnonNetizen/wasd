shader_type canvas_item;
render_mode blend_mix;

// 情绪团：发光气态软体团。
// 用角向正弦波瓣 + fbm 气态扰动算出会呼吸变形的软体轮廓，分层渲染外围辉光晕 / 团身气态 / 明亮核心。
// 所有情绪特征（配色 / 形变 / 律动）由 uniform 参数化，脚本在情绪间 lerp 实现平滑过渡。

uniform float time = 0.0;

uniform vec4 core_color : source_color = vec4(1.000, 0.950, 0.650, 1.0);
uniform vec4 mid_color : source_color = vec4(1.000, 0.760, 0.250, 1.0);
uniform vec4 edge_color : source_color = vec4(0.950, 0.420, 0.120, 1.0);
uniform vec4 glow_color : source_color = vec4(1.000, 0.640, 0.220, 1.0);

uniform float base_radius = 0.46;
uniform vec2 shape_scale = vec2(1.0, 1.0); // 横纵拉伸（悲伤纵向拉成泪滴，喜悦略扁圆）
uniform float bob = 0.0;                    // 垂直上浮（喜悦 > 0）
uniform float droop = 0.0;                  // 下垂下坠（悲伤 0..1）
uniform float wobble_amp = 0.05;
uniform float wobble_freq = 5.0;
uniform float wobble_speed = 2.0;
uniform float spike = 0.0;                  // 尖刺锐度（愤怒 0..1）
uniform float jitter = 0.0;                 // 高频颤抖（愤怒 0..1）
uniform float gas_scale = 3.0;
uniform float gas_speed = 0.3;
uniform float glow_strength = 1.0;
uniform float pulse_speed = 3.0;
uniform float pulse_amount = 0.04;
uniform float energy = 1.0;                 // 整体亮度 / 活力
uniform vec2 focus_position = vec2(8.0, 8.0); // 默认移出屏外，无鼠标时不打亮核心
uniform float focus_strength = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 4; octave++) {
		value += amplitude * value_noise(p);
		p *= 2.02;
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0; // 居中到 [-1, 1]

	// 团中心：喜悦上浮、悲伤下坠
	vec2 center = vec2(0.0, droop * 0.16 - bob);
	vec2 c = p - center;

	// 高频颤抖（愤怒）
	c += jitter * 0.025 * vec2(sin(time * 41.0 + p.y * 11.0), cos(time * 37.0 + p.x * 13.0));

	// 横纵拉伸
	c /= shape_scale;

	float rad = length(c);
	float angle = atan(c.y, c.x);

	// 呼吸脉动
	float breath = 1.0 + sin(time * pulse_speed) * pulse_amount;
	float radius = base_radius * breath;

	// 角向正弦波瓣（软体形变）；频率取整避免 atan 在 -x 轴接缝处突变
	float lobe_a = max(2.0, floor(wobble_freq));
	float lobe_b = floor(wobble_freq * 1.7 + 1.0);
	radius += sin(angle * lobe_a + time * wobble_speed) * wobble_amp;
	radius += sin(angle * lobe_b - time * wobble_speed * 0.8 + 1.3) * wobble_amp * 0.55;

	// 尖刺（愤怒）：相位 / 幅度用方向噪声扰动，做成不规则锯齿而非规则星
	float spike_dir = value_noise(normalize(c) * 4.0 + vec2(time * 0.6, 1.7));
	float spike_wave = pow(abs(sin(angle * 6.0 + time * 4.0 + spike_dir * 3.2)), 3.5);
	radius += spike * spike_wave * (0.45 + spike_dir * 0.7) * 0.14;

	// 下垂泪滴（悲伤）：底部更鼓、顶部收尖
	float vertical = c.y / max(rad, 0.0001);
	radius += droop * 0.18 * smoothstep(-1.0, 1.0, vertical);
	radius -= droop * 0.14 * smoothstep(0.1, -1.0, vertical);

	// 气态边界扰动
	vec2 q = c * gas_scale + vec2(time * gas_speed, -time * gas_speed * 0.7);
	float gas = fbm(q);
	radius += (gas - 0.5) * 0.05 * (0.5 + energy * 0.5);

	// 软体场：内部 1、外部 0
	float edge_soft = 0.10 - spike * 0.05;
	float body = 1.0 - smoothstep(radius - edge_soft, radius, rad);
	float t = clamp(1.0 - rad / max(radius, 0.0001), 0.0, 1.0); // 0=边缘, 1=核心

	// 内部气态星云
	float nebula = fbm(c * gas_scale * 1.7 + vec2(-time * gas_speed * 0.5, time * gas_speed * 0.45));

	// 分层配色：边缘 → 团身 → 核心
	vec3 color = mix(edge_color.rgb, mid_color.rgb, smoothstep(0.0, 0.45, t));
	color = mix(color, core_color.rgb, smoothstep(0.5, 1.0, t));
	color *= 0.82 + nebula * 0.34;                                  // 气态明暗
	float core = smoothstep(0.55, 1.0, t);
	color += core_color.rgb * core * 0.32 * energy;                // 明亮核心

	// 鼠标焦点加亮
	float focus = 1.0 - smoothstep(0.0, 0.4, distance(p, focus_position));
	color += core_color.rgb * focus * focus_strength * body;

	// 外围辉光晕
	float glow_ring = 1.0 - smoothstep(radius, radius + 0.42, rad);
	float halo = clamp(glow_ring - body, 0.0, 1.0);
	vec3 final_color = color * body + glow_color.rgb * halo * glow_strength;

	float alpha = clamp(body + halo * glow_strength * 0.55, 0.0, 1.0);
	COLOR = vec4(final_color, alpha);
}
