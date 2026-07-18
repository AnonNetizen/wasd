shader_type canvas_item;
render_mode unshaded, blend_mix;

// Low-contrast floor edge treatment. World-space phase keeps neighboring tiles
// in one continuous material wave instead of making every cell pulse alone.

uniform vec2 tile_size_px = vec2(128.0);
uniform vec2 cell_origin_px = vec2(0.0);
uniform float corner_radius_px = 8.0;
uniform float edge_width_px = 2.5;
uniform float lip_width_px = 1.0;
uniform float source_crop_px = 3.5;
uniform float breath_width_px = 0.35;
uniform float breath_period_seconds = 5.6;
uniform float wave_spatial_frequency = 0.012;
uniform vec4 edge_color : source_color = vec4(0.72, 0.73, 0.63, 1.0);
uniform vec4 lip_color : source_color = vec4(0.82, 0.83, 0.72, 1.0);
uniform bool freeze_animation = false;
uniform float frozen_time = 0.0;

const float TAU_VALUE = 6.28318530718;


float hash21(vec2 point) {
	point = fract(point * vec2(123.34, 456.21));
	point += dot(point, point + 45.32);
	return fract(point.x * point.y);
}


float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	vec2 curve = local * local * (3.0 - 2.0 * local);
	float bottom_left = hash21(cell);
	float bottom_right = hash21(cell + vec2(1.0, 0.0));
	float top_left = hash21(cell + vec2(0.0, 1.0));
	float top_right = hash21(cell + vec2(1.0, 1.0));
	return mix(
		mix(bottom_left, bottom_right, curve.x),
		mix(top_left, top_right, curve.x),
		curve.y
	);
}


float signed_rounded_box(vec2 point, vec2 half_extent, float radius) {
	vec2 distance = abs(point) - half_extent + vec2(radius);
	return min(max(distance.x, distance.y), 0.0) + length(max(distance, vec2(0.0))) - radius;
}


void fragment() {
	float animation_time = freeze_animation ? frozen_time : TIME;
	vec2 crop_uv = vec2(source_crop_px) / tile_size_px;
	vec2 source_uv = mix(crop_uv, vec2(1.0) - crop_uv, UV);
	vec4 source = texture(TEXTURE, source_uv);
	vec2 local = (UV - vec2(0.5)) * tile_size_px;
	vec2 world_pixel = cell_origin_px + UV * tile_size_px;

	float static_roughness = (
		value_noise(world_pixel / 29.0) - 0.5
	) * 0.50;
	float distance_to_edge = signed_rounded_box(
		local,
		tile_size_px * 0.5 - vec2(0.25),
		corner_radius_px
	) + static_roughness;
	float antialias_width = max(fwidth(distance_to_edge), 0.75);
	float inward_distance = max(-distance_to_edge, 0.0);

	float wave_coordinate = dot(world_pixel, normalize(vec2(1.0, 0.72)));
	float wave = 0.5 + 0.5 * sin(
		wave_coordinate * wave_spatial_frequency
		- animation_time * TAU_VALUE / max(breath_period_seconds, 0.001)
	);
	float animated_edge_width = edge_width_px + (wave * 2.0 - 1.0) * breath_width_px;
	float edge_mask = 1.0 - smoothstep(
		animated_edge_width - antialias_width,
		animated_edge_width + antialias_width,
		inward_distance
	);
	float lip_start = max(animated_edge_width - lip_width_px, 0.0);
	float lip_enter = smoothstep(
		lip_start - antialias_width,
		lip_start + antialias_width,
		inward_distance
	);
	float lip_exit = 1.0 - smoothstep(
		animated_edge_width + antialias_width,
		animated_edge_width + lip_width_px + antialias_width,
		inward_distance
	);
	float lip_mask = lip_enter * lip_exit;

	float edge_mix = edge_mask * (0.24 + wave * 0.08);
	float lip_mix = lip_mask * (0.08 + wave * 0.10);
	vec3 color = mix(source.rgb, edge_color.rgb, edge_mix);
	color = mix(color, lip_color.rgb, lip_mix);
	COLOR = vec4(color, 1.0);
}
