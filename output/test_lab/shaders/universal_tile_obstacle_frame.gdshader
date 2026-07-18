shader_type canvas_item;
render_mode unshaded, blend_mix;

// Hand-painted card base for opaque 128 x 128 obstacle tiles. Neighbor-aware
// ownership keeps adjacent frames from covering each other, while both tiles
// contribute matching halves of one shared seam.

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
uniform vec2 cell_origin_px = vec2(0.0);
// left, right, top, bottom
uniform vec4 neighbor_mask = vec4(0.0);
uniform vec4 fusion_pair_phase = vec4(0.0);
uniform float fusion_half_width_px = 2.0;
uniform float fusion_lip_width_px = 0.65;
uniform float fusion_roughness_px = 0.35;
uniform float fusion_breath_width_px = 0.2;
uniform float fusion_cap_blend_px = 11.0;
uniform vec4 shadow_color : source_color = vec4(0.06, 0.05, 0.03, 0.28);
uniform vec4 base_color : source_color = vec4(0.20, 0.16, 0.08, 1.0);
uniform vec4 mid_color : source_color = vec4(0.28, 0.23, 0.12, 1.0);
uniform vec4 lip_color : source_color = vec4(0.36, 0.31, 0.18, 1.0);
uniform vec4 fusion_shadow_left : source_color = vec4(0.06, 0.05, 0.03, 0.28);
uniform vec4 fusion_shadow_right : source_color = vec4(0.06, 0.05, 0.03, 0.28);
uniform vec4 fusion_shadow_top : source_color = vec4(0.06, 0.05, 0.03, 0.28);
uniform vec4 fusion_shadow_bottom : source_color = vec4(0.06, 0.05, 0.03, 0.28);
uniform vec4 fusion_base_left : source_color = vec4(0.20, 0.16, 0.08, 1.0);
uniform vec4 fusion_base_right : source_color = vec4(0.20, 0.16, 0.08, 1.0);
uniform vec4 fusion_base_top : source_color = vec4(0.20, 0.16, 0.08, 1.0);
uniform vec4 fusion_base_bottom : source_color = vec4(0.20, 0.16, 0.08, 1.0);
uniform vec4 fusion_mid_left : source_color = vec4(0.28, 0.23, 0.12, 1.0);
uniform vec4 fusion_mid_right : source_color = vec4(0.28, 0.23, 0.12, 1.0);
uniform vec4 fusion_mid_top : source_color = vec4(0.28, 0.23, 0.12, 1.0);
uniform vec4 fusion_mid_bottom : source_color = vec4(0.28, 0.23, 0.12, 1.0);
uniform vec4 fusion_lip_left : source_color = vec4(0.36, 0.31, 0.18, 1.0);
uniform vec4 fusion_lip_right : source_color = vec4(0.36, 0.31, 0.18, 1.0);
uniform vec4 fusion_lip_top : source_color = vec4(0.36, 0.31, 0.18, 1.0);
uniform vec4 fusion_lip_bottom : source_color = vec4(0.36, 0.31, 0.18, 1.0);
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


float inside_mask(float distance, float threshold, float antialias_width) {
	return 1.0 - smoothstep(
		threshold - antialias_width,
		threshold + antialias_width,
		distance
	);
}


float maximum_component(vec4 value) {
	return max(max(value.x, value.y), max(value.z, value.w));
}


vec4 blended_side_color(
	vec4 local_color,
	vec4 weights,
	vec4 left_color,
	vec4 right_color,
	vec4 top_color,
	vec4 bottom_color
) {
	float weight_sum = dot(weights, vec4(1.0));
	if (weight_sum <= 0.0001) {
		return local_color;
	}
	vec4 shared_color = (
		left_color * weights.x
		+ right_color * weights.y
		+ top_color * weights.z
		+ bottom_color * weights.w
	) / weight_sum;
	return mix(local_color, shared_color, clamp(maximum_component(weights), 0.0, 1.0));
}


float shared_seam_width(float tangent, float pair_phase, float animation_time) {
	float static_noise = (
		value_noise(vec2(tangent / 19.0, pair_phase * 7.13 + 3.17)) - 0.5
	) * 2.0 * fusion_roughness_px;
	float breath = sin(
		animation_time * TAU_VALUE / max(breath_period_seconds, 0.001)
		+ pair_phase
	) * fusion_breath_width_px;
	return max(fusion_half_width_px + static_noise + breath, 0.75);
}


float shared_seam_mask(float distance_to_side, float width, float antialias_width) {
	return 1.0 - smoothstep(
		width - antialias_width,
		width + antialias_width,
		distance_to_side
	);
}


float shared_seam_lip_mask(float distance_to_side, float width, float antialias_width) {
	float lip_start = max(width - fusion_lip_width_px, 0.0);
	float lip_enter = smoothstep(
		lip_start - antialias_width,
		lip_start + antialias_width,
		distance_to_side
	);
	float lip_exit = 1.0 - smoothstep(
		width - antialias_width,
		width + antialias_width,
		distance_to_side
	);
	return lip_enter * lip_exit;
}


void vertex() {
	VERTEX += (UV * 2.0 - 1.0) * frame_margin_px;
}


void fragment() {
	float animation_time = freeze_animation ? frozen_time : TIME;
	vec2 expanded_size_px = tile_size_px + vec2(frame_margin_px * 2.0);
	vec2 expanded_pixel = UV * expanded_size_px;
	vec2 content_pixel = expanded_pixel - vec2(frame_margin_px);
	vec2 world_pixel = cell_origin_px + content_pixel;
	vec2 local = content_pixel - tile_size_px * 0.5;
	vec2 half_extent = tile_size_px * 0.5 - vec2(0.35);

	float broad_noise = (value_noise(world_pixel / 38.0) - 0.5) * 2.0;
	float detail_noise = (value_noise(world_pixel / 11.0 + vec2(13.7, -8.9)) - 0.5) * 2.0;
	float roughness = broad_noise * roughness_broad_px + detail_noise * roughness_detail_px;
	float content_distance = signed_rounded_box(local, half_extent, content_corner_radius_px);
	float frame_distance = content_distance + roughness;
	float antialias_width = max(fwidth(frame_distance), 0.75);
	vec4 side_distance = vec4(
		abs(content_pixel.x),
		abs(tile_size_px.x - content_pixel.x),
		abs(content_pixel.y),
		abs(tile_size_px.y - content_pixel.y)
	);
	vec4 cap_weights = neighbor_mask * (
		vec4(1.0) - smoothstep(
			vec4(0.0),
			vec4(max(fusion_cap_blend_px, 0.001)),
			side_distance
		)
	);
	float cap_blend = clamp(maximum_component(cap_weights), 0.0, 1.0);

	float local_breath = sin(
		animation_time * TAU_VALUE / max(breath_period_seconds, 0.001) + phase
	);
	vec4 pair_breaths = sin(
		vec4(animation_time * TAU_VALUE / max(breath_period_seconds, 0.001))
		+ fusion_pair_phase
	);
	float cap_weight_sum = dot(cap_weights, vec4(1.0));
	float shared_breath = local_breath;
	if (cap_weight_sum > 0.0001) {
		shared_breath = dot(pair_breaths, cap_weights) / cap_weight_sum;
	}
	float breath = mix(local_breath, shared_breath, cap_blend);
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
	float ownership = 1.0;
	ownership *= mix(
		1.0,
		smoothstep(-antialias_width, antialias_width, content_pixel.x),
		neighbor_mask.x
	);
	ownership *= mix(
		1.0,
		1.0 - smoothstep(
			tile_size_px.x - antialias_width,
			tile_size_px.x + antialias_width,
			content_pixel.x
		),
		neighbor_mask.y
	);
	ownership *= mix(
		1.0,
		smoothstep(-antialias_width, antialias_width, content_pixel.y),
		neighbor_mask.z
	);
	ownership *= mix(
		1.0,
		1.0 - smoothstep(
			tile_size_px.y - antialias_width,
			tile_size_px.y + antialias_width,
			content_pixel.y
		),
		neighbor_mask.w
	);
	lip_mask *= ownership;
	mid_mask *= ownership;
	base_mask *= ownership;

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
	float shadow_mask = shadow_shape * (1.0 - base_outer) * ownership;

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
	float moving_highlight = highlight_arc * highlight_breakup * (1.0 - cap_blend);

	vec4 active_shadow = blended_side_color(
		shadow_color,
		cap_weights,
		fusion_shadow_left,
		fusion_shadow_right,
		fusion_shadow_top,
		fusion_shadow_bottom
	);
	vec4 active_base = blended_side_color(
		base_color,
		cap_weights,
		fusion_base_left,
		fusion_base_right,
		fusion_base_top,
		fusion_base_bottom
	);
	vec4 active_mid = blended_side_color(
		mid_color,
		cap_weights,
		fusion_mid_left,
		fusion_mid_right,
		fusion_mid_top,
		fusion_mid_bottom
	);
	vec4 active_lip = blended_side_color(
		lip_color,
		cap_weights,
		fusion_lip_left,
		fusion_lip_right,
		fusion_lip_top,
		fusion_lip_bottom
	);
	vec3 mid_tone = mix(active_base.rgb, active_mid.rgb, 0.62 + directional_light * 0.30);
	vec3 lip_tone = mix(active_mid.rgb, active_lip.rgb, 0.52 + directional_light * 0.40);
	lip_tone = mix(lip_tone, active_lip.rgb, moving_highlight * 0.18);
	lip_tone *= 0.96 + (breath * 0.5 + 0.5) * 0.04;
	float shadow_alpha = active_shadow.a * (0.82 + (breath * 0.5 + 0.5) * 0.18);

	vec4 result = vec4(active_shadow.rgb, shadow_alpha * shadow_mask);
	result = mix(result, vec4(active_base.rgb, 1.0), base_mask);
	result = mix(result, vec4(mid_tone, 1.0), mid_mask);
	result = mix(result, vec4(lip_tone, 1.0), lip_mask);

	vec2 source_uv = content_pixel / tile_size_px;
	vec4 source = texture(TEXTURE, clamp(source_uv, vec2(0.0), vec2(1.0)));
	result = mix(result, source, content_mask * source.a);

	float left_width = shared_seam_width(world_pixel.y, fusion_pair_phase.x, animation_time);
	float right_width = shared_seam_width(world_pixel.y, fusion_pair_phase.y, animation_time);
	float top_width = shared_seam_width(world_pixel.x, fusion_pair_phase.z, animation_time);
	float bottom_width = shared_seam_width(world_pixel.x, fusion_pair_phase.w, animation_time);
	vec4 seam_weights = neighbor_mask * content_mask * vec4(
		shared_seam_mask(max(content_pixel.x, 0.0), left_width, antialias_width),
		shared_seam_mask(max(tile_size_px.x - content_pixel.x, 0.0), right_width, antialias_width),
		shared_seam_mask(max(content_pixel.y, 0.0), top_width, antialias_width),
		shared_seam_mask(max(tile_size_px.y - content_pixel.y, 0.0), bottom_width, antialias_width)
	);
	vec4 seam_lip_weights = neighbor_mask * content_mask * vec4(
		shared_seam_lip_mask(max(content_pixel.x, 0.0), left_width, antialias_width),
		shared_seam_lip_mask(max(tile_size_px.x - content_pixel.x, 0.0), right_width, antialias_width),
		shared_seam_lip_mask(max(content_pixel.y, 0.0), top_width, antialias_width),
		shared_seam_lip_mask(max(tile_size_px.y - content_pixel.y, 0.0), bottom_width, antialias_width)
	);
	vec4 seam_base = blended_side_color(
		base_color,
		seam_weights,
		fusion_base_left,
		fusion_base_right,
		fusion_base_top,
		fusion_base_bottom
	);
	vec4 seam_mid = blended_side_color(
		mid_color,
		seam_weights,
		fusion_mid_left,
		fusion_mid_right,
		fusion_mid_top,
		fusion_mid_bottom
	);
	vec4 seam_lip = blended_side_color(
		lip_color,
		seam_lip_weights,
		fusion_lip_left,
		fusion_lip_right,
		fusion_lip_top,
		fusion_lip_bottom
	);
	float seam_alpha = clamp(maximum_component(seam_weights), 0.0, 1.0);
	float seam_lip_alpha = clamp(maximum_component(seam_lip_weights), 0.0, 1.0);
	vec3 seam_tone = mix(seam_base.rgb, seam_mid.rgb, 0.22);
	result.rgb = mix(result.rgb, seam_tone, seam_alpha * 0.96);
	result.rgb = mix(result.rgb, seam_lip.rgb, seam_lip_alpha * 0.62);
	result.a = max(result.a, seam_alpha);
	// Smooth masks shape the material, while this final half-open ownership rule
	// prevents neighboring antialias fringes from becoming draw-order dependent.
	float pixel_ownership = 1.0;
	pixel_ownership *= mix(1.0, step(0.0, content_pixel.x), neighbor_mask.x);
	pixel_ownership *= mix(
		1.0,
		1.0 - step(tile_size_px.x, content_pixel.x),
		neighbor_mask.y
	);
	pixel_ownership *= mix(1.0, step(0.0, content_pixel.y), neighbor_mask.z);
	pixel_ownership *= mix(
		1.0,
		1.0 - step(tile_size_px.y, content_pixel.y),
		neighbor_mask.w
	);
	COLOR = result * pixel_ownership;
}
