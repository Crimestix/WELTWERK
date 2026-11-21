// Blattkarten (Variante C): Laubatlas mit Alpha (Higgsfield), Eckpunktfarbe als vorgebackene
// Verschattung, Normalen aus Blender (vom Kronenmittelpunkt nach außen), leichter Wind.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D leaf_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_cut = 0.42;
uniform float wind_strength = 0.035;
uniform vec3 tint = vec3(1.0);
uniform float backlight = 0.55;

// Streuung je Baum (MultiMesh-Zusatzdaten): rgb × 2 als Farbfaktor, nur wenn a > 0,5 gesetzt ist.
varying vec3 instance_tint;

void vertex() {
	instance_tint = INSTANCE_CUSTOM.a > 0.5 ? INSTANCE_CUSTOM.rgb * 2.0 : vec3(1.0);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 1.2 + wp.x * 0.23 + wp.z * 0.19) + 0.4 * sin(TIME * 2.7 + wp.y * 0.9);
	VERTEX.xz += vec2(sway, sway * 0.6) * wind_strength * max(VERTEX.y - 1.5, 0.0) * 0.3;
}

void fragment() {
	vec4 t = texture(leaf_atlas, UV);
	// Godot dreht auf Rückseiten die Normale um; hier sollen alle Karten nach außen zeigen.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALBEDO = t.rgb * COLOR.rgb * tint * instance_tint;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.72;
	SPECULAR = 0.35;
	BACKLIGHT = ALBEDO * backlight;
}
