shader_type canvas_item;
render_mode unshaded;

uniform vec2 asset_half_size = vec2(128.0, 96.0);
uniform float animation_time = 0.0;
uniform float deformation_progress : hint_range(0.0, 1.0) = 0.0;
uniform float clear_progress : hint_range(0.0, 1.0) = 0.0;
uniform bool outline_mode = false;
uniform vec2 deformation_axis = vec2(1.0, 0.0);
uniform float deformation_origin = 0.0;
uniform float deformation_span = 1.0;
uniform float deformation_tangent_center = 0.0;
uniform float deformation_tangent_span = 1.0;
uniform vec4 deformation_light : source_color = vec4(0.95, 0.80, 0.52, 1.0);
uniform vec4 deformation_shadow : source_color = vec4(0.55, 0.44, 0.36, 1.0);

void vertex() {
	vec2 axis = normalize(deformation_axis);
	vec2 tangent = vec2(-axis.y, axis.x);
	float primary_position = clamp(
		(dot(VERTEX, axis) - deformation_origin)
		/ max(deformation_span, 1.0),
		0.0,
		1.0
	);
	float tangent_position = clamp(
		(dot(VERTEX, tangent) - deformation_tangent_center)
		/ max(deformation_tangent_span * 0.5, 1.0),
		-1.0,
		1.0
	);
	float tangent_weight = abs(tangent_position);
	float vertex_deformation_weight = outline_mode ? 0.0 : UV.y;
	float deformation_envelope = sin(deformation_progress * 3.14159265);
	float crease_center = mix(0.18, 0.82, deformation_progress);
	float crease_offset = primary_position - crease_center;
	float crease_band = exp(-crease_offset * crease_offset * 34.0);
	float boundary_guard = (
		smoothstep(0.04, 0.20, primary_position)
		* (1.0 - smoothstep(0.76, 0.98, primary_position))
		* (1.0 - smoothstep(0.72, 0.97, tangent_weight))
	);
	float crease = (
		vertex_deformation_weight
		* deformation_envelope
		* crease_band
		* boundary_guard
	);
	VERTEX -= axis * crease * (10.0 + 7.0 * (1.0 - primary_position));
	VERTEX += tangent * crease * 9.0 * sin(tangent_position * 1.57079633);
}

void fragment() {
	vec4 face_color = vec4(COLOR.rgb, 1.0);
	float primary_face = outline_mode ? 0.0 : step(0.75, COLOR.a);
	float deformation_envelope = sin(deformation_progress * 3.14159265);
	float block_phase = fract(UV.x * 17.0);
	float color_wave = 0.5 + 0.5 * sin(
		deformation_progress * 6.28318531
		+ block_phase * 6.28318531
	);
	vec3 deformation_color = mix(
		deformation_shadow.rgb,
		deformation_light.rgb,
		color_wave
	);
	face_color.rgb = mix(
		face_color.rgb,
		deformation_color,
		primary_face * deformation_envelope * (0.18 + color_wave * 0.30)
	);
	float visibility = 1.0;
	if (outline_mode) {
		visibility = 1.0 - smoothstep(0.94, 1.0, clear_progress);
	} else if (clear_progress > 0.0001) {
		visibility = smoothstep(clear_progress, clear_progress + 0.028, UV.x);
	}
	COLOR = vec4(face_color.rgb, face_color.a * visibility);
}
