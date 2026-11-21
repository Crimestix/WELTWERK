// Landschaft eines Ausschnitts: Gitter wird auf der Grafikkarte aus der Datentextur gehoben.
// Datentextur: R = Höhe (m), G = Wald (0–1), B = Bearbeitungsmarke (0–1).
// Farben vorläufig nach den Kartenbildern; die endgültige Bildsprache folgt dem Stiltest.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D data_tex : filter_nearest, repeat_disable;
uniform int res = 257;
uniform float plane_size = 1000.0;
uniform float height_scale = 1.0;
uniform float snowline = 3000.0;
uniform float treeline = 2100.0;
uniform float dryness = 0.3;
uniform float canopy = 1.0;        // 1 = Wald als Kronendach färben (grobe Ansicht), 0 = Waldboden
uniform bool show_marks = true;
uniform vec3 brush = vec3(0.0, 0.0, -1.0);   // x, z, Radius in Darstellungseinheiten
uniform vec3 brush_color : source_color = vec3(0.88, 0.70, 0.38);
// Umgebung: gröberer Ausschnitt um den aktuellen herum; innerhalb von hole (x0, z0, x1, z1) ausgespart.
uniform bool is_context = false;
uniform vec4 hole = vec4(0.0);

uniform vec3 meadow_color : source_color = vec3(0.36, 0.47, 0.13);
uniform vec3 meadow_dark_color : source_color = vec3(0.15, 0.29, 0.07);
uniform vec3 dry_color : source_color = vec3(0.64, 0.56, 0.26);
uniform vec3 forest_color : source_color = vec3(0.07, 0.17, 0.05);
uniform vec3 forest_floor_color : source_color = vec3(0.20, 0.17, 0.10);
uniform vec3 rock_color : source_color = vec3(0.52, 0.49, 0.45);
uniform vec3 rock_dark_color : source_color = vec3(0.27, 0.25, 0.23);
uniform vec3 sand_color : source_color = vec3(0.80, 0.72, 0.52);
uniform vec3 snow_color : source_color = vec3(0.93, 0.94, 0.96);

varying vec3 world_pos;
varying vec3 n_world;
varying float height_m;
varying float forest;
varying float mark;

float h_at(ivec2 p) {
	return texelFetch(data_tex, clamp(p, ivec2(0), ivec2(res - 1)), 0).r * height_scale;
}

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

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * value_noise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	ivec2 p = ivec2(round(UV * float(res - 1)));
	vec4 d = texelFetch(data_tex, p, 0);
	height_m = d.r;
	forest = d.g;
	mark = d.b;
	VERTEX.y = d.r * height_scale;
	float step = plane_size / float(res - 1);
	vec3 n = normalize(vec3(h_at(p + ivec2(-1, 0)) - h_at(p + ivec2(1, 0)), 2.0 * step,
		h_at(p + ivec2(0, -1)) - h_at(p + ivec2(0, 1))));
	NORMAL = n;
	n_world = normalize(MODEL_NORMAL_MATRIX * n);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 xz = world_pos.xz;
	if (is_context && xz.x > hole.x && xz.x < hole.z && xz.y > hole.y && xz.y < hole.w) {
		discard;
	}
	vec3 n = normalize(n_world);
	float slope = 1.0 - n.y;
	float macro = fbm(xz * 0.012);
	float detail = fbm(xz * 0.25);
	float micro = value_noise(xz * 2.0);

	vec3 grass = mix(meadow_dark_color, meadow_color, smoothstep(0.3, 0.7, macro));
	grass = mix(grass, dry_color, clamp(smoothstep(0.5, 0.8, fbm(xz * 0.004 + 31.0)) * 0.5 + dryness - 0.45, 0.0, 0.7));
	grass *= 0.85 + 0.28 * detail;

	float f = smoothstep(0.15, 0.55, forest + (detail - 0.5) * 0.25);
	vec3 trees = forest_color * (0.7 + 0.9 * value_noise(xz * 1.3) * detail);
	vec3 ground = mix(grass, mix(forest_floor_color, trees, canopy), f);

	vec3 rock = mix(rock_dark_color, rock_color, smoothstep(0.25, 0.75, detail)) * (0.9 + 0.2 * micro);
	float rock_w = smoothstep(0.32, 0.5, slope + (detail - 0.5) * 0.14);
	float sand_w = (1.0 - smoothstep(1.0, 3.5 + detail * 3.0, height_m)) * (1.0 - rock_w);
	float snow_w = smoothstep(snowline - 150.0, snowline + 150.0, height_m + (macro - 0.5) * 400.0)
		* (1.0 - smoothstep(0.4, 0.6, slope));

	vec3 c = mix(ground, rock, rock_w);
	c = mix(c, sand_color * (0.92 + 0.16 * micro), sand_w);
	c = mix(c, snow_color, snow_w);

	float underwater = smoothstep(0.0, -40.0, height_m);
	c = mix(c, vec3(0.05, 0.2, 0.22), underwater * 0.7);

	if (show_marks) {
		float ring = smoothstep(0.30, 0.45, mark) - smoothstep(0.55, 0.70, mark);
		c = mix(c, brush_color, ring * 0.85);
	}
	if (brush.z > 0.0) {
		float d = length(xz - brush.xy);
		float edge = 1.0 - smoothstep(0.0, brush.z * 0.025 + 0.4, abs(d - brush.z));
		c = mix(c, brush_color, edge * 0.9);
		c = mix(c, c + brush_color * 0.12, (1.0 - step(brush.z, d)) * 0.6);
	}

	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.6, snow_w * 0.4);
	SPECULAR = 0.3;
}
