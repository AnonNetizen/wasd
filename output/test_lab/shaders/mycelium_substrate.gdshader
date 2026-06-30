shader_type canvas_item;
render_mode blend_mix;

const int MAX_BLOBS = 8;

uniform float time = 0.0;
uniform float growth_amount = 1.0;
uniform float decay_amount = 0.0;
uniform vec2 focus_position = vec2(0.5, 0.5);
uniform float focus_radius = 0.18;
uniform int blob_count = 6;
uniform vec4 blob_data[MAX_BLOBS];
uniform vec4 blob_0 = vec4(0.5, 0.5, 0.0, 0.0);
uniform vec4 blob_1 = vec4(0.5, 0.5, 0.0, 0.0);
uniform vec4 blob_2 = vec4(0.5, 0.5, 0.0, 0.0);
uniform vec4 blob_3 = vec4(0.5, 0.5, 0.0, 0.0);
uniform vec4 blob_4 = vec4(0.5, 0.5, 0.0, 0.0);
uniform vec4 blob_5 = vec4(0.5, 0.5, 0.0, 0.0);
uniform vec4 blob_6 = vec4(0.5, 0.5, 0.0, 0.0);
uniform vec4 blob_7 = vec4(0.5, 0.5, 0.0, 0.0);
uniform vec4 dark_color : source_color = vec4(0.055, 0.025, 0.065, 0.92);
uniform vec4 mid_color : source_color = vec4(0.205, 0.065, 0.180, 0.90);
uniform vec4 edge_color : source_color = vec4(0.500, 0.145, 0.220, 0.82);
uniform vec4 gloss_color : source_color = vec4(0.780, 0.520, 0.820, 0.46);

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

float blob_contribution(vec2 uv, vec4 blob, float growth, float enabled) {
	float pulse = 1.0 + sin(time * 0.62 + blob.w) * 0.035;
	float radius = blob.z * mix(0.35, 1.0, growth) * pulse;
	float distance_to_blob = distance(uv, blob.xy);
	float contribution = 1.0 - smoothstep(radius * 0.34, radius, distance_to_blob);
	float soft_halo = 1.0 - smoothstep(radius * 0.78, radius * 1.28, distance_to_blob);
	return (contribution * 0.94 + soft_halo * 0.34) * enabled;
}

float blob_field(vec2 uv, float growth) {
	float field = 0.0;
	field += blob_contribution(uv, blob_0, growth, step(0.5, float(blob_count)));
	field += blob_contribution(uv, blob_1, growth, step(1.5, float(blob_count)));
	field += blob_contribution(uv, blob_2, growth, step(2.5, float(blob_count)));
	field += blob_contribution(uv, blob_3, growth, step(3.5, float(blob_count)));
	field += blob_contribution(uv, blob_4, growth, step(4.5, float(blob_count)));
	field += blob_contribution(uv, blob_5, growth, step(5.5, float(blob_count)));
	field += blob_contribution(uv, blob_6, growth, step(6.5, float(blob_count)));
	field += blob_contribution(uv, blob_7, growth, step(7.5, float(blob_count)));
	return field;
}

void fragment() {
	vec2 uv = UV;
	float low_noise = value_noise(uv * 4.1 + vec2(time * 0.015, -time * 0.012));
	float mid_noise = value_noise(uv * 12.0 + vec2(-time * 0.026, time * 0.018));
	float fine_noise = value_noise(uv * 34.0 + time * 0.035);
	vec2 warped_uv = uv + vec2(low_noise - 0.5, mid_noise - 0.5) * 0.038;

	float field = blob_field(warped_uv, growth_amount);
	float membrane = smoothstep(0.18, 0.52, field + (mid_noise - 0.5) * 0.18);
	float edge_band = smoothstep(0.14, 0.38, field) * (1.0 - smoothstep(0.56, 0.90, field));
	float outer_bleed = smoothstep(0.06, 0.24, field) * (1.0 - membrane);
	float focus_glow = 1.0 - smoothstep(0.0, focus_radius, distance(uv, focus_position));
	float vein = smoothstep(0.78, 1.0, sin((uv.x + uv.y) * 54.0 + low_noise * 7.0 + time * 1.3) * 0.5 + 0.5);
	float wet_sheen = smoothstep(0.72, 1.0, fine_noise) * membrane;
	float pulse_wave = sin(field * 5.2 - time * 1.6 + low_noise * 2.2) * 0.5 + 0.5;

	float polygon_fill = smoothstep(0.02, 0.28, growth_amount);
	vec3 color = mix(dark_color.rgb, mid_color.rgb, max(membrane, 0.72 * polygon_fill));
	color = mix(color, edge_color.rgb, edge_band * 0.56 + outer_bleed * 0.22);
	color += gloss_color.rgb * wet_sheen * 0.28;
	color += edge_color.rgb * vein * max(membrane, polygon_fill * 0.72) * 0.085;
	color += gloss_color.rgb * pulse_wave * focus_glow * membrane * 0.12;
	color = mix(color, dark_color.rgb * 0.62, decay_amount * 0.34);

	float alpha = max(membrane * dark_color.a, dark_color.a * 0.72 * polygon_fill);
	alpha += edge_band * 0.44 + outer_bleed * 0.26;
	alpha += wet_sheen * 0.10 + focus_glow * membrane * 0.08;
	alpha *= 1.0 - decay_amount * 0.45;
	COLOR = vec4(color, alpha);
}
