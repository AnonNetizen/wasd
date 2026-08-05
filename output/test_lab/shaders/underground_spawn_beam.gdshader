shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec4 deep_color : source_color = vec4(0.353, 0.043, 0.125, 1.0);
uniform vec4 danger_color : source_color = vec4(0.929, 0.184, 0.447, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0);
uniform float reveal_progress : hint_range(0.0, 1.0) = 0.0;
uniform float opacity : hint_range(0.0, 2.0) = 1.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float safe_reveal = max(reveal_progress, 0.001);
	float reveal_edge = 1.0 - reveal_progress;
	vec2 source_uv = vec2(
		UV.x,
		clamp((UV.y - reveal_edge) / safe_reveal, 0.0, 1.0)
	);
	vec4 source = texture(TEXTURE, source_uv);
	float luma = max(source.r, max(source.g, source.b));
	float bottom_up_mask = smoothstep(reveal_edge - 0.006, reveal_edge + 0.008, UV.y);
	float alpha = smoothstep(0.018, 0.18, luma) * bottom_up_mask * clamp(opacity, 0.0, 1.0);
	float body_band = smoothstep(0.12, 0.58, luma);
	float wet_band = smoothstep(0.78, 0.98, luma);
	vec3 tint = mix(deep_color.rgb, danger_color.rgb, body_band);
	float flash_heat = (
		flash
		* smoothstep(0.68, 0.98, luma)
		* smoothstep(0.45, 1.0, source_uv.y)
	);
	tint = mix(tint, hot_color.rgb, clamp(wet_band * 0.62 + flash_heat, 0.0, 1.0));
	float soft_volume = mix(0.72, 1.05, smoothstep(0.08, 0.72, luma));
	COLOR = vec4(tint * soft_volume, alpha);
}
