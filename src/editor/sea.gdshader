// Meer und Seen in den groben Ausschnitten (Kontinent bis Region): Farbe nach echter Tiefe in
// Metern (türkis über flachem Grund, tiefblau draußen), ein heller Schein entlang der Küsten wie
// auf einer gemalten Karte, matter Glanz statt Sonnenblendung.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx, depth_draw_always;

#include "res://src/target/meadow.gdshaderinc"

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
// Höhen des Ausschnitts (für den Küstenschein): R = Höhe in m.
uniform sampler2D data_lin : filter_linear, repeat_disable;
uniform int res = 257;
uniform float plane_size = 1000.0;
// Darstellungseinheiten je Meter Höhe (mit Überhöhung).
uniform float height_scale = 1.0;
uniform bool is_lake = false;
// Breite des Küstenscheins als Anteil des Ausschnitts.
uniform float glow_width = 0.022;

uniform vec3 shallow_color : source_color = vec3(0.14, 0.50, 0.52);
uniform vec3 shelf_color : source_color = vec3(0.06, 0.32, 0.43);
uniform vec3 deep_color : source_color = vec3(0.025, 0.10, 0.21);
uniform vec3 abyss_color : source_color = vec3(0.015, 0.06, 0.15);
uniform vec3 foam_color : source_color = vec3(0.86, 0.90, 0.86);

varying vec3 world_pos;

float land_at(vec2 tuv) {
	if (tuv.x < 0.0 || tuv.y < 0.0 || tuv.x > 1.0 || tuv.y > 1.0) {
		return 0.0;
	}
	return smoothstep(-20.0, 5.0, texture(data_lin, tuv).r);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Senkrechte Wassertiefe aus dem Tiefenpuffer, in Meter umgerechnet.
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	vec3 floor_world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	float thickness = depth < 0.000001 ? 1e6 : max(0.0, world_pos.y - floor_world.y);
	// Außerhalb des Ausschnitts gibt es keinen Grund: dort wie offenes Meer (gleiche Farbe wie innen).
	float depth_m = min(thickness / max(height_scale, 1e-6), 1600.0);

	vec2 m = to_meters(world_pos.xz);
	float px_m = max(length(fwidth(m)), 0.001);

	vec3 c = mix(shallow_color, shelf_color, smoothstep(2.0, 60.0, depth_m));
	c = mix(c, deep_color, smoothstep(60.0, 700.0, depth_m));
	c = mix(c, abyss_color, smoothstep(1500.0, 4000.0, depth_m));

	if (!is_lake) {
		// Küstenschein: Nähe zu Land in drei Ringen (gemittelt, weich).
		vec2 uv = world_pos.xz / plane_size + 0.5;
		vec2 tuv = (uv * float(res - 1) + 0.5) / float(res);
		float near = 0.0;
		float total = 0.0;
		for (int r = 1; r <= 3; r++) {
			float radius = glow_width * float(r * r) / 9.0;
			float w = 1.0 / float(r);
			for (int k = 0; k < 8; k++) {
				float a = (float(k) + 0.5 * float(r)) * 0.785398;
				near += land_at(tuv + vec2(cos(a), sin(a)) * radius) * w;
				total += w;
			}
		}
		near /= total;
		float glow = smoothstep(0.0, 0.55, near);
		c = mix(c, mix(shelf_color, shallow_color, glow), glow * 0.75 * smoothstep(5.0, 40.0, depth_m));
	}

	// Ruhige, großflächige Wasserstruktur (etwa acht Bildpunkte), kein Glitzern.
	float lvl = log2(max(px_m * 8.0, 1.0));
	float l0 = floor(lvl);
	float t = lvl - l0;
	float w0 = m_noise(m / exp2(l0) + 3.1);
	float w1 = m_noise(m / exp2(l0 + 1.0) + 8.7);
	float ripple = mix(w0, w1, t);
	c *= 0.94 + 0.12 * ripple;

	// Schmaler heller Saum an der Uferlinie.
	float foam = 1.0 - smoothstep(0.0, 4.0, depth_m);
	c = mix(c, foam_color, foam * 0.45);

	ALBEDO = c;
	ALPHA = clamp(mix(0.5, 1.0, smoothstep(0.5, 30.0, depth_m)) + foam * 0.2, 0.0, 1.0);
	ROUGHNESS = 0.55;
	SPECULAR = 0.18;
	METALLIC = 0.0;
}
