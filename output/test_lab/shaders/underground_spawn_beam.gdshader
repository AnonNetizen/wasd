shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 danger_color : source_color = vec4(0.929, 0.184, 0.447, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0);
uniform float reveal_progress : hint_range(0.0, 1.0) = 0.0;
uniform float opacity : hint_range(0.0, 2.0) = 1.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float luma = max(source.r, max(source.g, source.b));
	float reveal_edge = 1.0 - reveal_progress;
	float bottom_up_mask = smoothstep(reveal_edge - 0.025, reveal_edge + 0.018, UV.y);
	float base_heat = smoothstep(0.12, 1.0, UV.y);
	float alpha = smoothstep(0.018, 1.0, luma) * bottom_up_mask * opacity;
	float white_heat = clamp(luma * 0.38 + base_heat * 0.18 + flash, 0.0, 1.0);
	vec3 tint = mix(danger_color.rgb, hot_color.rgb, white_heat);
	COLOR = vec4(tint * luma * (1.0 + flash * 0.9), alpha);
}
