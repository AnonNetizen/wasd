shader_type canvas_item;
render_mode unshaded;

// 旋转星云穿行背景。五层星点使用固定循环制造纵深、旋转与向镜头推进，
// gameplay_mix 同时压低中心活动、亮星和星云对比，避免遮住居中角色。

uniform float animation_time = 0.0;
uniform float motion_speed : hint_range(0.0, 2.0) = 1.0;
uniform float effect_intensity : hint_range(0.0, 1.5) = 1.0;
uniform float pattern_scale : hint_range(0.5, 2.0) = 1.0;
uniform float gameplay_mix : hint_range(0.0, 1.0) = 0.0;
uniform float viewport_aspect = 1.68421;

mat2 rotate_2d(float angle) {
	float sine = sin(angle);
	float cosine = cos(angle);
	return mat2(vec2(cosine, -sine), vec2(sine, cosine));
}

float hash_21(vec2 point) {
	point = fract(point * vec2(123.34, 456.21));
	point += dot(point, point + 45.32);
	return fract(point.x * point.y);
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	vec2 curve = local * local * (3.0 - 2.0 * local);
	float a = hash_21(cell);
	float b = hash_21(cell + vec2(1.0, 0.0));
	float c = hash_21(cell + vec2(0.0, 1.0));
	float d = hash_21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, curve.x), mix(c, d, curve.x), curve.y);
}

float fbm(vec2 point) {
	float result = 0.0;
	float amplitude = 0.55;
	for (int octave = 0; octave < 3; octave++) {
		result += value_noise(point) * amplitude;
		point = rotate_2d(0.61) * point * 2.03 + vec2(4.7, 2.1);
		amplitude *= 0.48;
	}
	return result;
}

vec3 star_tint(float seed) {
	vec3 cold = vec3(0.46, 0.76, 1.0);
	vec3 warm = vec3(1.0, 0.75, 0.48);
	return mix(cold, warm, smoothstep(0.52, 0.94, seed));
}

void fragment() {
	float safe_aspect = max(viewport_aspect, 0.01);
	vec2 point = (UV - 0.5) * vec2(safe_aspect, 1.0);
	float radial_distance = length(point);
	float time = animation_time * motion_speed;
	float game = clamp(gameplay_mix, 0.0, 1.0);
	float scale = max(pattern_scale, 0.05);

	vec2 nebula_point = rotate_2d(time * 0.025) * point;
	nebula_point = nebula_point * (1.55 / scale) + vec2(time * 0.018, -time * 0.012);
	float broad_nebula = fbm(nebula_point);
	float fine_nebula = fbm(nebula_point * 2.15 + vec2(7.3, 1.8));
	float nebula_mask = smoothstep(0.34, 0.88, broad_nebula * 0.82 + fine_nebula * 0.30);
	float nebula_ridge = smoothstep(0.04, 0.48, 1.0 - abs(broad_nebula - 0.57) * 3.4);

	vec3 deep_space = mix(vec3(0.005, 0.008, 0.030), vec3(0.012, 0.018, 0.055), 1.0 - game);
	vec3 nebula_color = mix(vec3(0.035, 0.090, 0.170), vec3(0.215, 0.080, 0.330), fine_nebula);
	nebula_color = mix(nebula_color, vec3(0.055, 0.075, 0.115), game * 0.76);
	vec3 color = deep_space + nebula_color * nebula_mask * nebula_ridge * mix(0.72, 0.22, game);

	float center_activity = mix(1.0, smoothstep(0.10, 0.47, radial_distance), game * 0.82);
	vec3 stars = vec3(0.0);
	for (int layer_index = 0; layer_index < 5; layer_index++) {
		float layer = float(layer_index);
		float depth = fract(layer / 5.0 + time * 0.072);
		float depth_fade = smoothstep(0.02, 0.20, depth) * (1.0 - smoothstep(0.84, 1.0, depth));
		float rotation = time * (0.105 + layer * 0.009) + layer * 1.371;
		float zoom = mix(0.58, 3.35, depth * depth);
		vec2 star_point = rotate_2d(rotation) * point * zoom * (5.0 / scale);
		vec2 cell = floor(star_point);
		vec2 local = fract(star_point) - 0.5;
		float seed = hash_21(cell + vec2(layer * 37.17, layer * 11.93));
		float color_seed = hash_21(cell + vec2(layer * 19.41 + 8.7, layer * 29.13 + 4.2));
		float density = step(mix(0.76, 0.88, game), seed);

		vec2 radial_direction = normalize(star_point + vec2(0.0001));
		float along = dot(local, radial_direction);
		float across = dot(local, vec2(-radial_direction.y, radial_direction.x));
		float stretch = mix(0.62, 0.88, game);
		float star_distance = length(vec2(across, along * stretch));
		float radius = mix(0.028, 0.105, depth) * mix(0.72, 1.18, seed);
		float star = smoothstep(radius, radius * 0.18, star_distance) * density * depth_fade;
		float core = smoothstep(radius * 0.42, 0.0, star_distance) * density * depth_fade;
		float brightness = mix(0.38, 1.25, depth) * mix(0.72, 1.16, seed);
		brightness *= center_activity * mix(1.0, 0.64, game);
		stars += star_tint(color_seed) * (star * brightness + core * 0.78);
	}

	color += stars * effect_intensity;

	float vignette = 1.0 - smoothstep(0.48, 1.08, radial_distance);
	float center_lift = 1.0 - smoothstep(0.0, 0.64, radial_distance);
	color *= mix(0.46, 1.0, vignette);
	color += vec3(0.008, 0.012, 0.026) * center_lift * mix(0.45, 0.12, game);
	color = color / (vec3(1.0) + color * 0.42);

	COLOR = vec4(color, 1.0);
}
