shader_type spatial;
render_mode cull_back;

uniform vec4 stone_color : source_color = vec4(0.25, 0.35, 0.34, 1.0);
uniform vec4 inner_color : source_color = vec4(0.13, 0.58, 0.48, 1.0);
uniform vec4 rim_color : source_color = vec4(0.58, 0.92, 0.76, 1.0);
uniform float pulse = 0.0;

varying vec3 local_vertex;


float segment_distance(vec2 point, vec2 segment_start, vec2 segment_end) {
	vec2 segment = segment_end - segment_start;
	float projection = clamp(
		dot(point - segment_start, segment) / max(dot(segment, segment), 0.0001),
		0.0,
		1.0
	);
	return length(point - (segment_start + segment * projection));
}


void vertex() {
	local_vertex = VERTEX;
}


void fragment() {
	vec2 face_point = vec2(local_vertex.x / 1.32, (local_vertex.y - 2.05) / 2.25);
	float front_face = smoothstep(0.55, 0.92, NORMAL.z);
	float center_glow = 1.0 - smoothstep(0.22, 0.88, length(face_point / vec2(0.82, 1.0)));
	float crack_a = 1.0 - smoothstep(
		0.018,
		0.038,
		segment_distance(face_point, vec2(-0.10, 0.48), vec2(0.02, 0.20))
	);
	float crack_b = 1.0 - smoothstep(
		0.016,
		0.034,
		segment_distance(face_point, vec2(0.02, 0.20), vec2(-0.12, -0.02))
	);
	float crack_c = 1.0 - smoothstep(
		0.014,
		0.032,
		segment_distance(face_point, vec2(0.00, 0.21), vec2(0.20, 0.06))
	);
	float crack = max(crack_a, max(crack_b, crack_c)) * front_face;
	float vertical_light = smoothstep(-0.85, 0.95, face_point.y);
	float fresnel = pow(
		1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0),
		2.4
	);
	float pulse_glow = center_glow * (0.12 + pulse * 0.24) * front_face;
	vec3 base = stone_color.rgb * mix(0.67, 1.08, vertical_light);
	base = mix(base, inner_color.rgb, center_glow * front_face * 0.30);
	base = mix(base, inner_color.rgb * 0.26, crack * 0.82);
	base = mix(base, rim_color.rgb, fresnel * 0.12);
	ALBEDO = base;
	ROUGHNESS = mix(0.48, 0.28, pulse_glow);
	SPECULAR = 0.34;
	EMISSION = inner_color.rgb * pulse_glow * 0.22 + rim_color.rgb * fresnel * 0.022;
}
