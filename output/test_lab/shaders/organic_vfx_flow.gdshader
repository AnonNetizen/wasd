shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform vec4 primary_color : source_color = vec4(0.4078, 0.7373, 0.8667, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.9294, 0.1843, 0.4471, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0);
uniform float animation_time = 0.0;
uniform float phase_index : hint_range(0.0, 2.0, 1.0) = 0.0;
uniform float phase_progress : hint_range(0.0, 1.0) = 0.0;
uniform float opacity : hint_range(0.0, 1.5) = 1.0;
uniform float seed_offset = 0.0;
uniform sampler2D flow_texture : source_color, filter_linear;

float luma_at(vec2 uv) {
	vec3 source = texture(flow_texture, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
	return dot(source, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float angle = animation_time * 0.34 + seed_offset;
	mat2 rotation = mat2(vec2(cos(angle), -sin(angle)), vec2(sin(angle), cos(angle)));
	vec2 rotated = rotation * centered;
	float coarse = luma_at(UV * 0.58 + vec2(0.16, 0.21));
	vec2 warp = vec2(
		luma_at(UV * 0.83 + vec2(animation_time * 0.018, 0.07)),
		luma_at(UV * 0.77 + vec2(0.31, -animation_time * 0.015))
	) - vec2(0.5);
	vec2 sample_uv = rotated + vec2(0.5) + warp * (0.09 + coarse * 0.08);
	float detail = luma_at(sample_uv);
	float second = luma_at(sample_uv.yx * vec2(0.92, 1.08) + vec2(0.06, -0.03));
	float field = mix(detail, second, 0.34);
	float irregular_radius = length(centered * vec2(1.03, 0.91));
	float envelope = smoothstep(0.57 + (coarse - 0.5) * 0.18, 0.18, irregular_radius);
	float threshold = 0.24;
	float phase_alpha = 1.0;
	float heat_boost = 0.0;
	if (phase_index < 0.5) {
		threshold = mix(0.62, 0.28, phase_progress);
		phase_alpha = mix(0.36, 1.0, phase_progress);
	} else if (phase_index < 1.5) {
		threshold = mix(0.18, 0.34, phase_progress);
		phase_alpha = 1.0 - phase_progress * 0.18;
		heat_boost = 0.34 * (1.0 - phase_progress);
	} else {
		threshold = mix(0.31, 0.78, phase_progress);
		phase_alpha = 1.0 - phase_progress;
	}
	float alpha = smoothstep(threshold, threshold + 0.24, field) * envelope * phase_alpha * opacity;
	float accent = smoothstep(0.28, 0.82, second + coarse * 0.18);
	float heat = smoothstep(0.68, 0.98, field + heat_boost);
	vec3 mapped = mix(primary_color.rgb, secondary_color.rgb, accent * 0.72);
	mapped = mix(mapped, hot_color.rgb, heat);
	COLOR = vec4(mapped * alpha * (1.05 + heat * 0.5), alpha);
}
