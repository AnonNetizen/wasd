shader_type canvas_item;
render_mode unshaded;

// 水火双流体涡旋背景。两组反向域扭曲场在中部互相吞吐，窄交界带形成蒸汽。
// gameplay_mix 降低饱和度、中心扰动和亮边强度，保留战斗功能色可读性。

uniform float animation_time = 0.0;
uniform float motion_speed : hint_range(0.0, 2.0) = 0.85;
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
	point = fract(point * vec2(127.1, 311.7));
	point += dot(point, point + 74.7);
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
	float amplitude = 0.52;
	for (int octave = 0; octave < 4; octave++) {
		result += value_noise(point) * amplitude;
		point = rotate_2d(0.73) * point * 2.01 + vec2(3.1, 5.7);
		amplitude *= 0.48;
	}
	return result;
}

void fragment() {
	float safe_aspect = max(viewport_aspect, 0.01);
	vec2 point = (UV - 0.5) * vec2(safe_aspect, 1.0);
	float radial_distance = length(point);
	float game = clamp(gameplay_mix, 0.0, 1.0);
	float time = animation_time * motion_speed;
	float scale = max(pattern_scale, 0.05);

	float vortex_angle = sin(radial_distance * 4.6 - time * 0.42) * mix(0.24, 0.12, game);
	vec2 base_point = rotate_2d(vortex_angle) * point * (2.35 / scale);
	float warp_x = fbm(base_point * 0.82 + vec2(time * 0.075, -time * 0.052));
	float warp_y = fbm(base_point * 0.88 + vec2(-time * 0.061, time * 0.081) + vec2(7.4, 2.6));
	vec2 warp = vec2(warp_x - 0.5, warp_y - 0.5);
	float center_activity = mix(1.0, smoothstep(0.09, 0.49, radial_distance), game * 0.78);
	warp *= mix(0.96, 0.58, game) * (0.34 + center_activity * 0.66);

	vec2 water_point = base_point + warp * 1.05 + vec2(time * 0.095, -time * 0.115);
	vec2 fire_point = base_point - vec2(warp.y, warp.x) * 1.12 + vec2(-time * 0.112, time * 0.082);
	float water_field = fbm(water_point * 1.25 + vec2(1.8, 6.1));
	float fire_field = fbm(fire_point * 1.32 + vec2(8.3, 3.4));
	float water_detail = value_noise(water_point * 4.2 - vec2(time * 0.08, time * 0.14));
	float fire_detail = value_noise(fire_point * 4.5 + vec2(time * 0.13, -time * 0.07));

	float tide = sin(base_point.y * 1.25 + time * 0.31) * 0.075;
	float signed_boundary = point.x + (water_field - fire_field) * 0.56 * center_activity + tide;
	float fire_mask = smoothstep(-0.16, 0.16, signed_boundary);
	float boundary_distance = abs(signed_boundary);
	float steam_band = 1.0 - smoothstep(0.018, mix(0.18, 0.12, game), boundary_distance);
	float turbulent_steam = smoothstep(0.30, 0.82, fbm(base_point * 2.1 + warp * 1.8 - vec2(0.0, time * 0.16)));

	vec3 water_deep_show = vec3(0.006, 0.035, 0.105);
	vec3 water_light_show = vec3(0.055, 0.690, 0.910);
	vec3 water_deep_game = vec3(0.015, 0.060, 0.090);
	vec3 water_light_game = vec3(0.160, 0.480, 0.580);
	vec3 fire_deep_show = vec3(0.105, 0.010, 0.008);
	vec3 fire_light_show = vec3(1.000, 0.405, 0.045);
	vec3 fire_deep_game = vec3(0.100, 0.035, 0.015);
	vec3 fire_light_game = vec3(0.600, 0.260, 0.070);

	vec3 water_deep = mix(water_deep_show, water_deep_game, game);
	vec3 water_light = mix(water_light_show, water_light_game, game);
	vec3 fire_deep = mix(fire_deep_show, fire_deep_game, game);
	vec3 fire_light = mix(fire_light_show, fire_light_game, game);
	float water_highlight = smoothstep(
		mix(0.34, 0.24, game),
		mix(0.91, 0.76, game),
		water_field + warp_x * 0.22 + (water_detail - 0.5) * 0.15
	);
	float fire_highlight = smoothstep(
		mix(0.32, 0.23, game),
		mix(0.92, 0.77, game),
		fire_field + warp_y * 0.30 + (fire_detail - 0.5) * 0.17
	);
	vec3 water_color = mix(water_deep, water_light, water_highlight * mix(0.92, 0.58, game));
	vec3 fire_color = mix(fire_deep, fire_light, fire_highlight * mix(1.0, 0.56, game));
	water_color *= clamp(0.56 + water_field * 0.92 + (water_detail - 0.5) * 0.16, 0.54, 1.32);
	fire_color *= clamp(0.54 + fire_field * 0.96 + (fire_detail - 0.5) * 0.18, 0.52, 1.34);
	float water_ridge = 1.0 - smoothstep(0.035, 0.15, abs(water_field - 0.58));
	float fire_ridge = 1.0 - smoothstep(0.035, 0.15, abs(fire_field - 0.60));
	water_color += water_light * water_ridge * mix(0.13, 0.09, game);
	fire_color += fire_light * fire_ridge * mix(0.15, 0.10, game);
	vec3 color = mix(water_color, fire_color, fire_mask);

	vec3 steam_show = vec3(0.78, 0.88, 0.91);
	vec3 steam_game = vec3(0.55, 0.51, 0.43);
	vec3 steam_color = mix(steam_show, steam_game, game);
	float steam_strength = steam_band * (0.30 + turbulent_steam * 0.70) * mix(0.70, 0.38, game);
	color = mix(color, steam_color, steam_strength);

	float foam = smoothstep(0.76, 0.96, water_field) * (1.0 - fire_mask);
	float ember = smoothstep(0.77, 0.97, fire_field) * fire_mask;
	color += water_light * foam * mix(0.22, 0.08, game);
	color += fire_light * ember * mix(0.32, 0.09, game);

	float gameplay_calm = mix(1.0, smoothstep(0.06, 0.42, radial_distance), game * 0.42);
	vec3 calm_color = mix(water_deep_game, fire_deep_game, smoothstep(-0.24, 0.24, point.x));
	color = mix(calm_color, color, gameplay_calm);
	color *= mix(0.72, 1.0, 1.0 - smoothstep(0.52, 1.06, radial_distance));
	color *= effect_intensity;
	color = color / (vec3(1.0) + color * 0.34);

	COLOR = vec4(color, 1.0);
}
