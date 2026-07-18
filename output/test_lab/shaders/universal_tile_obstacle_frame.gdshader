shader_type canvas_item;
render_mode unshaded, blend_mix;

// Hand-painted card base for opaque 128 x 128 obstacle tiles.
// The quad expands in vertex(), while fragment() remaps the original art back to
// its authored size so the frame grows outside the image instead of covering it.

uniform vec2 tile_size_px = vec2(128.0);
uniform float frame_margin_px = 11.0;
uniform float content_corner_radius_px = 11.0;
uniform float base_width_px = 6.0;
uniform float mid_width_px = 2.5;
uniform float lip_width_px = 1.25;
uniform float shadow_softness_px = 3.0;
uniform vec2 shadow_offset_px = vec2(1.25, 1.75);
uniform float roughness_broad_px = 0.8;
uniform float roughness_detail_px = 0.35;
uniform float breath_width_px = 0.6;
uniform float breath_period_seconds = 5.2;
uniform float highlight_period_seconds = 9.0;
uniform float phase = 0.0;
uniform vec4 shadow_color : source_color = vec4(0.06, 0.05, 0.03, 0.28);
uniform vec4 base_color : source_color = vec4(0.20, 0.16, 0.08, 1.0);
uniform vec4 mid_color : source_color = vec4(0.28, 0.23, 0.12, 1.0);
uniform vec4 lip_color : source_color = vec4(0.36, 0.31, 0.18, 1.0);
uniform bool freeze_animation = false;
uniform float frozen_time = 0.0;

const float TAU_VALUE = 6.28318530718;


float hash21(vec2 point) {
	point = fract(point * vec2(123.34, 456.21));
	point += dot(point, point + 45.32 + phase * 0.17);
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


float inside_mask(float distance, float threshold, float antialias_width) {
	return 1.0 - smoothstep(
		threshold - antialias_width,
		threshold + antialias_width,
		distance
	);
}


void vertex() {
	VERTEX += (UV * 2.0 - 1.0) * frame_margin_px;
}


void fragment() {
	float animation_time = freeze_animation ? frozen_time : TIME;
	vec2 expanded_size_px = tile_size_px + vec2(frame_margin_px * 2.0);
	vec2 expanded_pixel = UV * expanded_size_px;
	vec2 content_pixel = expanded_pixel - vec2(frame_margin_px);
	vec2 local = content_pixel - tile_size_px * 0.5;
	vec2 half_extent = tile_size_px * 0.5 - vec2(0.35);

	float broad_noise = (value_noise(content_pixel / 38.0 + phase * 2.1) - 0.5) * 2.0;
	float detail_noise = (value_noise(content_pixel / 11.0 - phase * 3.7) - 0.5) * 2.0;
	float roughness = broad_noise * roughness_broad_px + detail_noise * roughness_detail_px;
	float content_distance = signed_rounded_box(local, half_extent, content_corner_radius_px);
	float frame_distance = content_distance + roughness;
	float antialias_width = max(fwidth(frame_distance), 0.75);

	float breath = sin(
		animation_time * TAU_VALUE / max(breath_period_seconds, 0.001) + phase
	);
	float width_breath = breath * breath_width_px;
	float lip_outer_width = lip_width_px + width_breath * 0.08;
	float mid_outer_width = lip_width_px + mid_width_px + width_breath * 0.20;
	float base_outer_width = lip_width_px + mid_width_px + base_width_px + width_breath;

	float content_mask = inside_mask(
		content_distance + roughness * 0.16,
		0.0,
		antialias_width
	);
	float lip_outer = inside_mask(frame_distance, lip_outer_width, antialias_width);
	float mid_outer = inside_mask(frame_distance, mid_outer_width, antialias_width);
	float base_outer = inside_mask(frame_distance, base_outer_width, antialias_width);
	float lip_mask = clamp(lip_outer - content_mask, 0.0, 1.0);
	float mid_mask = clamp(mid_outer - lip_outer, 0.0, 1.0);
	float base_mask = clamp(base_outer - mid_outer, 0.0, 1.0);

	vec2 shadow_local = local - shadow_offset_px;
	float shadow_distance = signed_rounded_box(
		shadow_local,
		half_extent,
		content_corner_radius_px
	) + roughness * 0.72 - base_outer_width;
	float shadow_shape = 1.0 - smoothstep(
		-antialias_width,
		shadow_softness_px,
		shadow_distance
	);
	float shadow_mask = shadow_shape * (1.0 - base_outer);

	vec2 approximate_normal = normalize(local + vec2(0.0001));
	float directional_light = clamp(
		dot(approximate_normal, normalize(vec2(-0.72, -0.69))) * 0.5 + 0.5,
		0.0,
		1.0
	);
	float perimeter = fract(atan(local.y, local.x) / TAU_VALUE + 1.0);
	float highlight_head = fract(
		animation_time / max(highlight_period_seconds, 0.001) + phase / TAU_VALUE
	);
	float arc_distance = abs(fract(perimeter - highlight_head + 0.5) - 0.5);
	float highlight_arc = 1.0 - smoothstep(0.045, 0.19, arc_distance);
	float highlight_breakup = smoothstep(
		0.46,
		0.72,
		value_noise(vec2(perimeter * 23.0 + phase * 4.0, phase * 11.0))
	);
	float moving_highlight = highlight_arc * highlight_breakup;

	vec3 mid_tone = mix(base_color.rgb, mid_color.rgb, 0.62 + directional_light * 0.30);
	vec3 lip_tone = mix(mid_color.rgb, lip_color.rgb, 0.52 + directional_light * 0.40);
	lip_tone = mix(lip_tone, lip_color.rgb, moving_highlight * 0.18);
	lip_tone *= 0.96 + (breath * 0.5 + 0.5) * 0.04;
	float shadow_alpha = shadow_color.a * (0.82 + (breath * 0.5 + 0.5) * 0.18);

	vec4 result = vec4(shadow_color.rgb, shadow_alpha * shadow_mask);
	result = mix(result, vec4(base_color.rgb, 1.0), base_mask);
	result = mix(result, vec4(mid_tone, 1.0), mid_mask);
	result = mix(result, vec4(lip_tone, 1.0), lip_mask);

	vec2 source_uv = content_pixel / tile_size_px;
	vec4 source = texture(TEXTURE, clamp(source_uv, vec2(0.0), vec2(1.0)));
	result = mix(result, source, content_mask * source.a);
	COLOR = result;
}
