// Grashalme der Blender-Grasbüschel (Variante B): Eckpunktfarben, beidseitig, leichter Wind.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float wind_strength = 0.12;
uniform vec3 color_scale = vec3(1.0);

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 1.7 + wp.x * 0.5 + wp.z * 0.35);
	VERTEX.x += sway * wind_strength * VERTEX.y * VERTEX.y;
}

void fragment() {
	ALBEDO = COLOR.rgb * color_scale;
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
	BACKLIGHT = COLOR.rgb * 0.6;
}
