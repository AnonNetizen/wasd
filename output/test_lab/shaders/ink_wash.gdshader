shader_type canvas_item;
render_mode blend_mix;

// 中国水墨画风：把一组抽象墨团（玩家 + 敌人角色）渲成黑墨笔形，合成到米白宣纸底。
// 各角色圆盘用 smin 软并集成连续墨场，fbm 域扭曲做毛笔不规则轮廓与渗墨；
// 叠浓淡斑驳、积墨边、飞白枯笔、宣纸纤维纹。纯过程化，无反馈缓冲。

const int MAX_CHARS = 12;

uniform float time = 0.0;
uniform float aspect = 1.684; // 屏幕宽/高
uniform int char_count = 0;
// xy = UV 位置，z = 半径（以高度归一化），w = 相位
uniform vec4 ink_chars[MAX_CHARS];

uniform vec4 paper_color : source_color = vec4(0.918, 0.890, 0.820, 1.0);
uniform vec4 ink_color : source_color = vec4(0.070, 0.060, 0.072, 1.0);
uniform float bleed_amount = 0.30;
uniform float feibai_amount = 0.42;

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

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

void fragment() {
	vec2 uv = UV;
	vec2 p = vec2(uv.x * aspect, uv.y);

	// 全局域扭曲：墨边随宣纸纤维渗化、不规则
	float warp = fbm(p * 3.0 + vec2(time * 0.03, -time * 0.02));
	vec2 pw = p + vec2(warp - 0.5, fbm(p * 3.0 + 7.7) - 0.5) * 0.03;

	// 墨场：各角色圆盘软并集，边界用角向波瓣做毛笔不规则（振幅按半径比例缩放，避免掐裂成花瓣）
	float field = 4.0;
	for (int i = 0; i < MAX_CHARS; i++) {
		if (i >= char_count) {
			break;
		}
		vec4 ch = ink_chars[i];
		if (ch.z <= 0.0001) {
			continue;
		}
		vec2 center = vec2(ch.x * aspect, ch.y);
		vec2 rel = pw - center;
		float ang = atan(rel.y, rel.x);
		float rr = length(rel);
		// 整数角频避免 atan 接缝突变；振幅 = 半径的一小比例
		float wob = ch.z * (sin(ang * 2.0 + ch.w) * 0.18 + sin(ang * 3.0 - ch.w * 1.3 + time * 0.25) * 0.10);
		// 小半径（敌人）边缘略不规则
		wob += step(ch.z, 0.12) * ch.z * sin(ang * 5.0 + ch.w) * 0.05;
		float di = rr - (ch.z + wob);
		field = smin(field, di, 0.04);
	}

	// 浓淡斑驳（大 washes + 中细节）
	float tone = fbm(pw * 4.0 + vec2(time * 0.02, time * 0.015));
	float tone2 = fbm(pw * 8.5 + 5.0);
	float mottle = mix(tone, tone2, 0.5);

	float core = smoothstep(0.010, -0.05, field);   // 浓墨内部
	float bleed = smoothstep(0.05, -0.025, field);  // 渗墨外晕
	float edge_pool = smoothstep(0.016, 0.0, abs(field + 0.004)); // 积墨边

	// 覆盖度（墨 vs 纸）
	float density = core;
	density += bleed * bleed_amount * (0.40 + 0.50 * tone2);
	density += edge_pool * 0.25 * bleed;
	density = clamp(density, 0.0, 1.0);

	// 飞白：双向拉伸枯笔白丝，集中在非核心 / 薄墨处
	float dry1 = value_noise(pw * vec2(20.0, 6.0) + vec2(time * 0.04, 0.0));
	float dry2 = value_noise(pw * vec2(7.0, 24.0) + 9.0);
	float feibai = (smoothstep(0.55, 0.82, dry1) + smoothstep(0.60, 0.86, dry2) * 0.6) * (1.0 - core * 0.45);

	// 宣纸底：米白 + 各向异性纤维纹 + 四角压暗
	float fiber = fbm(uv * vec2(160.0, 52.0));
	float fiber2 = value_noise(uv * vec2(400.0, 120.0));
	vec3 paper = paper_color.rgb;
	paper *= 0.96 + fiber * 0.06;
	paper *= 0.99 + (fiber2 - 0.5) * 0.04;
	float vignette = 1.0 - smoothstep(0.55, 1.15, distance(uv, vec2(0.5)));
	paper *= 0.90 + vignette * 0.10;

	// 墨色明度：焦墨(深)→淡墨(浅)，按 mottle 变化；积墨湿边更深；飞白处露纸提亮
	float ink_value = mix(0.045, 0.34, mottle);
	ink_value -= edge_pool * bleed * 0.10;
	ink_value += feibai * feibai_amount;
	ink_value = clamp(ink_value, 0.02, 0.92);
	// 焦墨(ink_color 深色端) → 淡墨(冷灰) 的统一墨色 ramp
	float ink_level = clamp(ink_value / 0.42, 0.0, 1.0);
	vec3 ink_rgb = mix(ink_color.rgb, vec3(0.46, 0.45, 0.50), ink_level);
	ink_rgb *= 0.97 + fiber * 0.06;

	vec3 final_color = mix(paper, ink_rgb, density);
	COLOR = vec4(final_color, 1.0);
}
