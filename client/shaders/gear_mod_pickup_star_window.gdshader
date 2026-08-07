shader_type canvas_item;
render_mode unshaded;

uniform float animation_time = 0.0;
uniform float viewport_aspect = 1.68421;
uniform float star_scale : hint_range(0.5, 2.0) = 1.8;
uniform float outline_texels : hint_range(1.0, 64.0) = 22.0;
uniform vec2 texture_pixel_size = vec2(0.00125, 0.00125);
uniform vec4 outline_color : source_color = vec4(0.407843, 0.737255, 0.866667, 1.0);

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
	float amplitude = 0.56;
	for (int octave = 0; octave < 3; octave++) {
		result += value_noise(point) * amplitude;
		point = point * 2.03 + vec2(7.1, 3.7);
		amplitude *= 0.48;
	}
	return result;
}

vec3 star_color(float seed) {
	vec3 cold = vec3(0.38, 0.78, 1.0);
	vec3 neutral = vec3(0.92, 0.97, 1.0);
	vec3 warm = vec3(1.0, 0.63, 0.36);
	vec3 cold_to_neutral = mix(cold, neutral, smoothstep(0.20, 0.62, seed));
	return mix(cold_to_neutral, warm, smoothstep(0.78, 0.98, seed));
}

void fragment() {
	float body_alpha = texture(TEXTURE, UV).a;
	vec2 step_uv = texture_pixel_size * outline_texels;
	float expanded_body_alpha = body_alpha;
	for (int outline_index = 0; outline_index < 16; outline_index++) {
		float outline_angle = float(outline_index) * 0.3926990817;
		expanded_body_alpha = max(
			expanded_body_alpha,
			texture(
				TEXTURE,
				UV + vec2(cos(outline_angle), sin(outline_angle)) * step_uv
			).a
		);
	}
	float rim_alpha = max(expanded_body_alpha - body_alpha, 0.0);
	float safe_aspect = max(viewport_aspect, 0.01);
	float safe_scale = max(star_scale, 0.05);
	vec2 screen_point = (SCREEN_UV - 0.5) * vec2(safe_aspect, 1.0);
	float broad_cloud = fbm(screen_point * (2.8 / safe_scale) + vec2(4.0, 9.0));
	float fine_cloud = fbm(screen_point * (6.4 / safe_scale) + vec2(13.0, 2.0));
	float cloud_mask = smoothstep(0.42, 0.91, broad_cloud * 0.80 + fine_cloud * 0.28);
	vec3 cloud_color = mix(vec3(0.035, 0.16, 0.30), vec3(0.31, 0.055, 0.37), fine_cloud);
	vec3 color = vec3(0.004, 0.008, 0.026) + cloud_color * cloud_mask * 0.58;
	for (int layer_index = 0; layer_index < 4; layer_index++) {
		float layer = float(layer_index);
		float density = mix(42.0, 118.0, layer / 3.0) / safe_scale;
		vec2 grid_point = screen_point * density + vec2(layer * 31.7, layer * 17.3);
		vec2 cell = floor(grid_point);
		vec2 local = fract(grid_point) - 0.5;
		float seed = hash_21(cell + vec2(layer * 19.4, layer * 7.7));
		float color_seed = hash_21(cell + vec2(layer * 5.8 + 2.1, layer * 23.6 + 8.4));
		float exists = step(mix(0.72, 0.89, layer / 3.0), seed);
		float radius = mix(0.055, 0.145, seed) * mix(0.72, 0.42, layer / 3.0);
		float star = smoothstep(radius, radius * 0.16, length(local)) * exists;
		float twinkle = 0.78 + 0.22 * sin(animation_time * mix(0.8, 1.6, seed) + seed * 31.0);
		color += star_color(color_seed) * star * twinkle * mix(0.58, 1.18, seed);
	}
	float glass_noise = value_noise(screen_point * 95.0 + vec2(11.0, 4.0));
	color += vec3(0.015, 0.030, 0.050) * glass_noise;
	color = color / (vec3(1.0) + color * 0.34);
	vec3 final_color = mix(outline_color.rgb, color, body_alpha);
	float final_alpha = max(body_alpha, rim_alpha * outline_color.a);
	COLOR = vec4(final_color, final_alpha);
}
