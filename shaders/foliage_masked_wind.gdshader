shader_type spatial;
render_mode cull_disabled;

uniform sampler2D base_color_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float alpha_clip = 0.3333;
uniform float wind_directional_strength = 4.0;
uniform float wind_influence = 0.5;
uniform float wind_speed = 0.7;
uniform float wind_weight = 0.3;

void vertex() {
	// A low-amplitude local sway uses the source MI's measured wind settings.
	// UV.y provides a stable tip weight because these GLBs have no painted wind
	// weight in COLOR_0; geometry, UVs, and imported material slots stay intact.
	float tip_weight = clamp(UV.y, 0.0, 1.0);
	float phase = TIME * wind_speed + dot(VERTEX.xz, vec2(0.71, 0.71)) * wind_directional_strength;
	float sway = sin(phase) * wind_influence * wind_weight * 0.15 * tip_weight;
	VERTEX.xz += vec2(0.71, 0.71) * sway;
}

void fragment() {
	vec4 texel = texture(base_color_texture, UV);
	ALBEDO = texel.rgb;
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_clip;
	// The UE source parent routes Custom Roughness (default 1.0) to Roughness.
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
