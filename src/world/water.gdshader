// Wasserfläche: Farbe nach Tiefe, leichte Wellen, heller Saum am Ufer.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx, depth_draw_always;

uniform vec3 shallow_color : source_color = vec3(0.10, 0.52, 0.52);
uniform vec3 deep_color : source_color = vec3(0.02, 0.12, 0.24);
uniform vec3 foam_color : source_color = vec3(0.82, 0.88, 0.85);
uniform float depth_fade = 9.0;
uniform float wave_strength = 0.35;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec3 world_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float waves(vec2 p, float t) {
	return value_noise(p * 0.22 + vec2(t * 0.05, t * 0.03)) * 0.6
		+ value_noise(p * 0.55 - vec2(t * 0.04, t * 0.07)) * 0.3
		+ value_noise(p * 1.4 + vec2(t * 0.09, -t * 0.05)) * 0.1;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Senkrechte Wassertiefe: Grund aus dem Tiefenpuffer zurück in Weltkoordinaten.
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	vec3 floor_world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	float thickness = depth < 0.000001 ? 1000.0 : max(0.0, world_pos.y - floor_world.y);
	float deep = smoothstep(0.0, 1.0, clamp(thickness / depth_fade, 0.0, 1.0));

	// Wellen als Normale aus dem Gefälle des Rauschens.
	float e = 0.15;
	float h = waves(world_pos.xz, TIME);
	float hx = waves(world_pos.xz + vec2(e, 0.0), TIME);
	float hz = waves(world_pos.xz + vec2(0.0, e), TIME);
	vec3 wn = normalize(vec3((h - hx) / e * wave_strength, 1.0, (h - hz) / e * wave_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// Schmaler Saum direkt an der Uferlinie.
	float foam = (1.0 - smoothstep(0.0, 0.18, thickness)) * smoothstep(0.35, 0.75, h);

	ALBEDO = mix(mix(shallow_color, deep_color, deep), foam_color, foam * 0.5);
	ALPHA = clamp(mix(0.65, 1.0, deep) + foam * 0.2, 0.0, 1.0);
	ROUGHNESS = 0.18;
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
