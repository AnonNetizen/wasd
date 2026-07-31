shader_type canvas_item;
render_mode unshaded;

uniform vec2 asset_half_size = vec2(128.0, 96.0);
uniform float animation_time = 0.0;
uniform vec2 movement_deformation = vec2(0.0);
uniform float generation_progress : hint_range(0.0, 1.0) = 1.0;
uniform float dissolve_progress : hint_range(0.0, 1.0) = 0.0;
uniform bool outline_mode = false;
uniform vec2 motion_axis = vec2(1.0, 0.0);
uniform float motion_origin = 0.0;
uniform float motion_span = 1.0;
uniform float motion_tangent_center = 0.0;
uniform float motion_tangent_span = 1.0;
uniform vec4 movement_tint : source_color = vec4(0.79, 0.60, 0.36, 1.0);
uniform vec4 generation_tint : source_color = vec4(0.79, 0.60, 0.36, 1.0);
uniform vec4 dissolve_tint : source_color = vec4(0.31, 0.24, 0.43, 1.0);

void vertex() {
	float deformation_amount = length(movement_deformation);
	if (deformation_amount > 0.0001) {
		vec2 direction = movement_deformation / deformation_amount;
		vec2 tangent = vec2(-direction.y, direction.x);
		float longitudinal_extent = max(
			dot(abs(direction), asset_half_size),
			1.0
		);
		float longitudinal = dot(VERTEX, direction);
		float lateral = dot(VERTEX, tangent);
		float normalized_longitudinal = clamp(
			longitudinal / longitudinal_extent,
			-1.0,
			1.0
		);
		float front_weight = smoothstep(
			-0.10,
			0.92,
			normalized_longitudinal
		);
		float center_weight = (
			1.0
			- normalized_longitudinal * normalized_longitudinal
		);
		longitudinal *= 1.0 + deformation_amount * 0.085;
		longitudinal += deformation_amount * front_weight * 4.5;
		longitudinal -= deformation_amount * center_weight * 2.2;
		lateral *= (
			1.0
			- deformation_amount
			* 0.048
			* (1.0 - abs(normalized_longitudinal) * 0.35)
		);
		VERTEX = direction * longitudinal + tangent * lateral;
	}
}

void fragment() {
	vec4 face_color = vec4(COLOR.rgb, 1.0);
	float primary_face = outline_mode ? 0.0 : step(0.75, COLOR.a);
	float interior_factor = outline_mode ? 0.0 : 1.0;
	face_color.rgb = mix(
		face_color.rgb,
		movement_tint.rgb,
		primary_face
		* min(length(movement_deformation), 1.0)
		* 0.14
	);

	float generation_visibility = smoothstep(
		0.0,
		0.08,
		generation_progress
	);
	float dissolve_visibility = 1.0 - smoothstep(
		0.94,
		1.0,
		dissolve_progress
	);
	if (!outline_mode) {
		if (generation_progress <= 0.0001) {
			generation_visibility = 0.0;
		} else if (generation_progress >= 0.9999) {
			generation_visibility = 1.0;
		} else {
			generation_visibility = 1.0 - smoothstep(
				generation_progress,
				generation_progress + 0.028,
				UV.x
			);
		}
		if (dissolve_progress <= 0.0001) {
			dissolve_visibility = 1.0;
		} else if (dissolve_progress >= 0.9999) {
			dissolve_visibility = 0.0;
		} else {
			dissolve_visibility = smoothstep(
				dissolve_progress,
				dissolve_progress + 0.028,
				UV.x
			);
		}
	}
	float generation_edge = 1.0 - smoothstep(
		0.02,
		0.10,
		abs(UV.x - generation_progress)
	);
	float dissolve_edge = 1.0 - smoothstep(
		0.02,
		0.10,
		abs(UV.x - dissolve_progress)
	);
	face_color.rgb = mix(
		face_color.rgb,
		generation_tint.rgb,
		generation_edge * interior_factor * 0.28
	);
	face_color.rgb = mix(
		face_color.rgb,
		dissolve_tint.rgb,
		dissolve_edge * interior_factor * 0.34
	);
	COLOR = vec4(
		face_color.rgb,
		face_color.a * generation_visibility * dissolve_visibility
	);
}
