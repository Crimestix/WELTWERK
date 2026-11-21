// Gras und Blumen aus Atlas-Karten (Higgsfield). Je Instanz: INSTANCE_CUSTOM.r = Atlaszelle / 8,
// .g = Trockenheit, .b = Helligkeit. Normale zeigt nach oben – Karten werden wie der Boden
// beleuchtet. In der Ferne schrumpfen die Büschel in den Boden (kein harter Rand).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://src/target/meadow.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 grid = vec2(4.0, 2.0);
uniform float alpha_cut = 0.5;
uniform float fade_start = 110.0;
uniform float fade_end = 170.0;
uniform float wind_strength = 0.08;
uniform vec3 tint = vec3(0.86, 1.1, 0.62);
uniform vec3 dry_tint = vec3(1.15, 1.0, 0.75);
uniform float saturation = 1.25;
// Farbe vom Boden am Fuß des Büschels (gleiche Textur und Farbanpassung wie das Gelände);
// der Atlas liefert nur Form und Helligkeitsverlauf. So passen Gras und Boden zusammen.
uniform sampler2D ground_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ground_dry_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 ground_tint = vec3(0.95, 1.25, 0.5);
uniform float ground_saturation = 1.6;
uniform float ground_brightness = 1.25;
uniform bool from_ground = true;
uniform float calm_start = 25.0;
uniform float calm_end = 90.0;

varying float cell;
varying float dry;
varying float bright;
varying float calm;
varying vec3 root_color;

vec3 grade_ground(vec3 c, vec3 t) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	return mix(vec3(l), c, ground_saturation) * t * ground_brightness;
}

void vertex() {
	cell = floor(INSTANCE_CUSTOM.r * 8.0 + 0.5);
	dry = INSTANCE_CUSTOM.g;
	bright = INSTANCE_CUSTOM.b;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = length(wp - CAMERA_POSITION_WORLD);
	float keep = smoothstep(fade_end, fade_start, dist);
	calm = smoothstep(calm_start, calm_end, dist);
	root_color = meadow_color(to_meters(MODEL_MATRIX[3].xz));
	float top = 1.0 - UV.y;
	VERTEX.y *= keep;
	float sway = sin(TIME * 1.6 + wp.x * 0.45 + wp.z * 0.3) + 0.5 * sin(TIME * 3.1 + wp.x * 1.3);
	VERTEX.x += sway * wind_strength * top * top;
	NORMAL = (inverse(MODEL_NORMAL_MATRIX) * vec3(0.0, 1.0, 0.0));
}

void fragment() {
	vec2 cr = vec2(mod(cell, grid.x), floor(cell / grid.x));
	vec4 t = texture(atlas, (UV + cr) / grid);
	vec3 c = t.rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	if (from_ground) {
		// Helligkeit des Halms relativ zum Mittelwert des Atlas (ca. 0,3) auf die Bodenfarbe legen.
		float rel = clamp(l / 0.3, 0.75, 1.35);
		c = root_color * mix(rel, 1.0, calm * 0.6);
	} else {
		c = mix(vec3(l), c, saturation) * tint;
		c = mix(c, c * dry_tint, dry);
	}
	c *= mix(0.82, 1.08, 1.0 - UV.y) * (0.92 + 0.16 * bright);
	ALBEDO = c;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = c * 0.5;
}
