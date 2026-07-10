shader_type canvas_item;
render_mode blend_mix;

// 星际争霸2 虫族 creep 风格的多源扩散菌毯基质。
// 每个 creep 源(菌瘤)是一个圆盘距离场，用 smooth-union 软并集融合成连续菌毯；
// 表面用 FBM 噪声做肉质凹凸 / 暗色凹坑 / 血管，叠湿润高光，边界用噪声扰动成碎裂须状推进边缘。

const int MAX_SOURCES = 16;

uniform float time = 0.0;
uniform float growth_amount = 1.0;
uniform float decay_amount = 0.0;
uniform float aspect = 1.74; // 房间宽 / 高，用于把 UV 校正成等比，保证源是正圆
uniform vec2 focus_position = vec2(0.5, 0.5);
uniform float focus_radius = 0.18;
uniform int source_count = 6;
// xy = 源中心 UV，z = 当前半径(以房间高度归一化)，w = 相位
uniform vec4 creep_sources[MAX_SOURCES];

uniform vec4 pit_color : source_color = vec4(0.035, 0.010, 0.055, 1.0);
uniform vec4 deep_color : source_color = vec4(0.150, 0.035, 0.180, 1.0);
uniform vec4 mid_color : source_color = vec4(0.470, 0.090, 0.360, 1.0);
uniform vec4 rim_color : source_color = vec4(0.880, 0.380, 0.700, 1.0);
uniform vec4 sheen_color : source_color = vec4(0.950, 0.800, 1.000, 1.0);
uniform float base_alpha = 0.97;
uniform vec2 field_extent = vec2(1020.0, 560.0); // substrate 矩形局部尺寸(局部坐标跨 -half..half)

// 从局部顶点坐标自算 UV，避免无纹理 Polygon2D 的 uv 数组不被 shader 采纳
varying vec2 field_uv;

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

// 软并集：把两个距离场平滑融合，k 越大融合越圆润
float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

void vertex() {
	field_uv = (VERTEX + field_extent * 0.5) / field_extent;
}

void fragment() {
	vec2 uv = field_uv;
	vec2 p = vec2(uv.x * aspect, uv.y); // 等比校正空间

	// --- creep 距离场（各源圆盘软并集）---
	float field_distance = 4.0;
	for (int i = 0; i < MAX_SOURCES; i++) {
		if (i >= source_count) {
			break;
		}
		vec4 source = creep_sources[i];
		if (source.z <= 0.0001) {
			continue;
		}
		vec2 center = vec2(source.x * aspect, source.y);
		float pulse = 1.0 + sin(time * 0.6 + source.w) * 0.02;
		float source_distance = distance(p, center) - source.z * pulse;
		field_distance = smin(field_distance, source_distance, 0.06);
	}

	// --- 噪声层 ---
	float warp = fbm(p * 5.5 + vec2(time * 0.02, -time * 0.018));
	vec2 warped = p + vec2(warp - 0.5, fbm(p * 5.5 + 11.3) - 0.5) * 0.06;
	float bump = fbm(warped * 9.0 + time * 0.015);
	float pit = fbm(warped * 4.0 + 5.0);
	float fine = value_noise(warped * 24.0 + time * 0.04);

	// 碎裂须状边缘：多频噪声扰动边界距离，形成手指状凸起
	float edge_noise = fbm(p * 9.0 + time * 0.03) - 0.5;
	float finger_noise = value_noise(p * 20.0 + time * 0.02) - 0.5;
	float perturbed = field_distance + edge_noise * 0.07 + finger_noise * 0.035;

	float inside = smoothstep(0.004, -0.014, perturbed);              // 更脆的边
	float depth = smoothstep(0.0, -0.18, perturbed);                 // 越往核心越大
	float rim = 1.0 - smoothstep(0.0, 0.022, abs(perturbed + 0.010)); // 紧贴边界的细亮环

	// --- 血管（脊状噪声）---
	float ridge = abs(fbm(warped * 6.5 + bump * 0.6) - 0.5);
	float vein = smoothstep(0.05, 0.0, ridge) * inside;

	// --- 颜色：深核暗、浅处品红，拉大明度对比 ---
	vec3 color = mix(deep_color.rgb, mid_color.rgb, smoothstep(0.30, 0.80, bump));
	color = mix(color, pit_color.rgb, depth * 0.50);                       // 核心压暗
	color = mix(color, pit_color.rgb, smoothstep(0.55, 0.90, pit) * 0.65); // 深色凹坑
	color = mix(color, pit_color.rgb * 0.9, vein * 0.50);                  // 暗血管
	color *= 0.62 + bump * 0.82;                                           // 凹凸明暗（更立体）

	// 湿润高光（高光聚在凸起肉面峰值上，柔和而非静态雪花噪点）
	float spec = smoothstep(0.50, 0.80, fine) * smoothstep(0.40, 0.80, bump) * inside;
	float glint = 0.5 + 0.5 * sin(time * 0.7 + bump * 7.0);
	color += sheen_color.rgb * spec * glint * 0.55;

	// 明亮须状推进边缘（细环，紧贴边界）
	color = mix(color, rim_color.rgb, clamp(rim, 0.0, 1.0) * inside);

	// 鼠标焦点活化辉光
	float focus = 1.0 - smoothstep(0.0, focus_radius, distance(uv, focus_position));
	color += rim_color.rgb * focus * inside * 0.18 * (0.6 + 0.4 * sin(time * 3.0));

	// 整体呼吸脉动
	color *= 0.93 + 0.07 * sin(time * 0.6 + depth * 3.0);

	// 枯萎暗化
	color = mix(color, pit_color.rgb * 0.7, decay_amount * 0.4);

	// --- alpha：内部不透明，边缘只加细环，去掉宽糊光晕 ---
	float alpha = inside * base_alpha;
	alpha += rim * inside * 0.15;
	alpha = clamp(alpha, 0.0, 1.0);
	alpha *= 1.0 - decay_amount * 0.5;

	COLOR = vec4(color, alpha);
}
