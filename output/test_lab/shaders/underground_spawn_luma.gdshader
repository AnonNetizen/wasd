shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 primary_color : source_color = vec4(0.929, 0.184, 0.447, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0);
uniform float opacity : hint_range(0.0, 2.0) = 1.0;
uniform float hot_mix : hint_range(0.0, 1.0) = 0.0;
uniform float alpha_floor : hint_range(0.0, 0.25) = 0.018;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float luma = max(source.r, max(source.g, source.b));
	float alpha = smoothstep(alpha_floor, 1.0, luma) * opacity * COLOR.a;
	vec3 tint = mix(primary_color.rgb, hot_color.rgb, clamp(hot_mix + luma * 0.25, 0.0, 1.0));
	COLOR = vec4(tint * luma * COLOR.rgb, alpha);
}
