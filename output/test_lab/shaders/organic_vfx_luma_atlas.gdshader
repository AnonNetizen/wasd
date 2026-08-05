shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform vec4 primary_color : source_color = vec4(0.4078, 0.7373, 0.8667, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.9294, 0.1843, 0.4471, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0);
uniform float opacity : hint_range(0.0, 1.5) = 1.0;
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float frame_index : hint_range(0.0, 15.0, 1.0) = 0.0;
uniform float atlas_columns : hint_range(1.0, 8.0, 1.0) = 4.0;
uniform float atlas_rows : hint_range(1.0, 8.0, 1.0) = 4.0;

void fragment() {
	float column = mod(floor(frame_index + 0.5), atlas_columns);
	float row = floor(floor(frame_index + 0.5) / atlas_columns);
	vec2 atlas_uv = (UV + vec2(column, row)) / vec2(atlas_columns, atlas_rows);
	vec3 source = texture(TEXTURE, atlas_uv).rgb;
	float luma = dot(source, vec3(0.299, 0.587, 0.114));
	float body = smoothstep(0.018, 0.72, luma);
	float accent = smoothstep(0.18, 0.76, luma);
	float heat = smoothstep(0.58, 0.98, luma);
	vec3 mapped = mix(primary_color.rgb, secondary_color.rgb, accent * 0.58);
	mapped = mix(mapped, hot_color.rgb, heat);
	float alpha = pow(body, 0.82) * opacity;
	COLOR = vec4(mapped * alpha * intensity, alpha);
}
