// Gelände ohne Texturen: Farbe nach Neigung, Höhe und festem Rauschen in Weltkoordinaten.
// Platzhalter, bis die Frage nach Modellen und Texturen geklärt ist.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float sea_level = 0.0;

uniform vec3 meadow_color : source_color = vec3(0.36, 0.47, 0.13);
uniform vec3 meadow_dark_color : source_color = vec3(0.15, 0.29, 0.07);
uniform vec3 dry_grass_color : source_color = vec3(0.62, 0.55, 0.25);
uniform vec3 soil_color : source_color = vec3(0.40, 0.31, 0.19);
uniform vec3 rock_color : source_color = vec3(0.55, 0.52, 0.47);
uniform vec3 rock_dark_color : source_color = vec3(0.27, 0.25, 0.23);
uniform vec3 sand_color : source_color = vec3(0.80, 0.72, 0.52);
uniform vec3 snow_color : source_color = vec3(0.92, 0.93, 0.95);
uniform float snow_height = 52.0;

varying vec3 world_pos;
varying vec3 world_normal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += amp * value_noise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		amp *= 0.5;
	}
	return sum;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	float slope = 1.0 - n.y;
	vec2 xz = world_pos.xz;

	float macro = fbm(xz * 0.010);
	float dryness = fbm(xz * 0.004 + 31.0);
	float detail = fbm(xz * 0.30);
	float micro = value_noise(xz * 2.7) * 0.6 + value_noise(xz * 9.0) * 0.4;

	// Wiese: dunklere und hellere Flecken, stellenweise trocken.
	vec3 grass = mix(meadow_dark_color, meadow_color, smoothstep(0.30, 0.70, macro));
	grass = mix(grass, dry_grass_color, smoothstep(0.52, 0.80, dryness) * 0.75);
	grass *= 0.82 + 0.30 * detail + 0.08 * micro;

	vec3 rock = mix(rock_dark_color, rock_color, smoothstep(0.25, 0.75, detail));
	rock *= 0.90 + 0.20 * micro;
	vec3 soil = soil_color * (0.85 + 0.30 * micro);
	vec3 sand = sand_color * (0.92 + 0.16 * micro);

	float wobble = (detail - 0.5) * 0.14;
	float rock_w = smoothstep(0.30, 0.46, slope + wobble);
	float soil_w = smoothstep(0.20, 0.32, slope + wobble) * (1.0 - rock_w)
		* smoothstep(0.35, 0.65, fbm(xz * 0.05 + 5.0)) * 0.8;
	float sand_w = (1.0 - smoothstep(sea_level + 0.4, sea_level + 2.0 + detail * 1.5, world_pos.y)) * (1.0 - rock_w);
	float snow_w = smoothstep(snow_height - 4.0, snow_height + 4.0, world_pos.y + (macro - 0.5) * 10.0)
		* (1.0 - smoothstep(0.35, 0.55, slope));

	vec3 c = grass;
	c = mix(c, soil, soil_w);
	c = mix(c, rock, rock_w);
	c = mix(c, sand, sand_w);
	c = mix(c, snow_color, snow_w);

	// Unter Wasser dunkler, mit der Tiefe ins Blaugrüne.
	float wet = 1.0 - smoothstep(sea_level - 0.5, sea_level + 0.3, world_pos.y);
	float underwater = smoothstep(sea_level, sea_level - 4.0, world_pos.y);
	c *= mix(1.0, 0.7, wet);
	c = mix(c, vec3(0.05, 0.22, 0.24), underwater * 0.7);

	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.55, max(wet, snow_w * 0.4));
	SPECULAR = 0.35;
}
