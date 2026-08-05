shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec4 deep_color : source_color = vec4(0.353, 0.043, 0.125, 1.0);
uniform vec4 primary_color : source_color = vec4(0.929, 0.184, 0.447, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0);
uniform float opacity : hint_range(0.0, 2.0) = 1.0;
uniform float hot_mix : hint_range(0.0, 1.0) = 0.0;
uniform float alpha_floor : hint_range(0.0, 0.25) = 0.018;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float luma = max(source.r, max(source.g, source.b));
	float alpha = smoothstep(alpha_floor, 0.18, luma) * clamp(opacity, 0.0, 1.0) * COLOR.a;
	float body_band = smoothstep(0.12, 0.58, luma);
	float wet_band = smoothstep(0.76, 0.98, luma);
	vec3 tint = mix(deep_color.rgb, primary_color.rgb, body_band);
	tint = mix(tint, hot_color.rgb, clamp(wet_band * 0.78 + hot_mix, 0.0, 1.0));
	float soft_volume = mix(0.72, 1.06, smoothstep(0.08, 0.72, luma));
	COLOR = vec4(tint * soft_volume * COLOR.rgb, alpha);
}
