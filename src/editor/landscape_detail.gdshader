// Feine Ausschnitte im Editor (bis ca. 3,5 km): Aussehen wie die Zielszene.
// Gitter wie landscape.gdshader aus der Datentextur gehoben (R Höhe m, G Wald, B Marke);
// Farbe aus der gemeinsamen Wiesenpalette und Fototexturen (Poly Haven), gerechnet in Metern.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://src/target/meadow.gdshaderinc"

uniform sampler2D data_tex : filter_nearest, repeat_disable;
uniform int res = 257;
uniform float plane_size = 1000.0;
uniform float height_scale = 1.0;
uniform float snowline = 3000.0;
uniform bool show_marks = true;
uniform vec3 brush = vec3(0.0, 0.0, -1.0);
uniform vec3 brush_color : source_color = vec3(0.88, 0.70, 0.38);
uniform bool is_context = false;
uniform vec4 hole = vec4(0.0);

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D meadow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bottom_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 forest_floor : source_color = vec3(0.20, 0.26, 0.10);
// Ohne einzelne Bäume (Ausschnitte über 1,7 km): Wald als Kronendach-Luftbild wie im groben Shader.
uniform float canopy = 0.0;
uniform sampler2D canopy_broadleaf : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D canopy_conifer : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float conifer_bias = 0.0;
uniform vec3 snow_color : source_color = vec3(0.93, 0.94, 0.96);

varying vec3 world_pos;
varying vec3 n_world;
varying float height_m;
varying float forest;
varying float mark;
varying float protect;
varying float water;

float h_at(ivec2 p) {
	return texelFetch(data_tex, clamp(p, ivec2(0), ivec2(res - 1)), 0).r * height_scale;
}

float caustics(vec2 p, float t) {
	float c = 0.0;
	for (int k = 0; k < 2; k++) {
		vec2 q = p * (1.3 + float(k) * 0.7) + vec2(t * 0.35, -t * 0.27) * (1.0 + float(k));
		vec2 i = floor(q);
		vec2 f = fract(q);
		float m = 8.0;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 o = vec2(float(x), float(y));
				vec2 r = o + vec2(m_hash12(i + o), m_hash12(i + o + 7.3)) * 0.85 - f;
				m = min(m, dot(r, r));
			}
		}
		c += pow(clamp(m * 1.6, 0.0, 1.0), 3.0);
	}
	return c * 0.5;
}

void vertex() {
	ivec2 p = ivec2(round(UV * float(res - 1)));
	vec4 d = texelFetch(data_tex, p, 0);
	height_m = d.r;
	forest = d.g;
	protect = step(1.5, d.b);
	mark = d.b - 2.0 * protect;
	water = d.a;
	VERTEX.y = (d.r + water) * height_scale;
	float cell_r = plane_size / float(res - 1);
	vec3 n = normalize(vec3(h_at(p + ivec2(-1, 0)) - h_at(p + ivec2(1, 0)), 2.0 * cell_r,
		h_at(p + ivec2(0, -1)) - h_at(p + ivec2(0, 1))));
	if (water > 0.05) {
		n = vec3(0.0, 1.0, 0.0);
	}
	NORMAL = n;
	n_world = normalize(MODEL_NORMAL_MATRIX * n);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 rxz = world_pos.xz;
	if (is_context && rxz.x > hole.x && rxz.x < hole.z && rxz.y > hole.y && rxz.y < hole.w) {
		discard;
	}
	vec2 xz = to_meters(rxz);
	vec3 n = normalize(n_world);
	float slope = 1.0 - n.y;
	float h = height_m;
	float macro = m_fbm(xz * 0.03);
	float mixer = m_noise(xz * 0.11);

	vec2 uv_g = xz / 3.0;
	float detail_l = dot(mix(texture(grass_albedo, uv_g).rgb, texture(meadow_albedo, xz / 9.0).rgb, 0.35), vec3(0.299, 0.587, 0.114));
	vec3 c = meadow_color(xz) * clamp(detail_l / 0.22, 0.6, 1.35);
	vec3 nn = texture(grass_normal, uv_g).rgb * 2.0 - 1.0;

	// Waldboden unter gemaltem Wald.
	float f = smoothstep(0.2, 0.6, forest + (mixer - 0.5) * 0.2);
	vec3 floor_c = forest_floor * (0.75 + 0.5 * texture(forest_albedo, xz / 4.0).g);
	float conifer = clamp(0.12 + smoothstep(300.0, 1400.0, h) * 0.8 + conifer_bias * 0.5, 0.0, 0.95);
	vec3 broad = mix(texture(canopy_broadleaf, xz / 230.0).rgb, texture(canopy_broadleaf, xz.yx / 610.0 + 0.37).rgb, 0.35);
	vec3 needles = mix(texture(canopy_conifer, xz / 190.0).rgb, texture(canopy_conifer, xz.yx / 530.0 + 0.61).rgb, 0.35) * vec3(1.02, 1.1, 0.78);
	vec3 crowns = mix(broad, needles, smoothstep(0.35, 0.65, conifer + (macro - 0.5) * 0.4));
	c = mix(c, mix(floor_c, crowns, canopy), f * mix(0.85, 1.0, canopy));

	float shore_w = (1.0 - smoothstep(0.9, 1.9 + macro * 0.6, h)) * step(-0.35, h);
	float rock_w = clamp(smoothstep(0.35, 0.55, slope) + shore_w * smoothstep(0.35, 0.65, mixer + 0.2), 0.0, 1.0);
	vec3 rock = texture(rock_albedo, xz / 5.0).rgb * 0.9;
	c = mix(c, rock, rock_w);
	nn = mix(nn, texture(rock_normal, xz / 5.0).rgb * 2.0 - 1.0, rock_w);

	float under = smoothstep(-0.05, -0.45, h);
	c = mix(c, texture(bottom_albedo, xz / 3.5).rgb, under);
	float wet = (1.0 - smoothstep(-0.1, 0.35, h)) * (1.0 - under);
	c *= mix(1.0, 0.62, wet);
	c += vec3(0.75, 0.9, 0.85) * caustics(xz * 0.9, TIME) * exp(-max(-h, 0.0) * 0.35) * under * 0.55;

	float snow_w = smoothstep(snowline - 150.0, snowline + 150.0, h + (macro - 0.5) * 400.0) * (1.0 - smoothstep(0.4, 0.6, slope));
	c = mix(c, snow_color, snow_w);

	// Binnengewässer (Fluss, See): klares Wasser über dem Grund, zur Tiefe hin blaugrün.
	float rough_w = 0.0;
	if (water > 0.03) {
		float wd = water;
		vec3 bottom = texture(bottom_albedo, xz / 3.5).rgb * exp(-vec3(0.42, 0.11, 0.07) * wd);
		vec3 tint = mix(vec3(0.20, 0.52, 0.52), vec3(0.04, 0.17, 0.26), smoothstep(0.5, 8.0, wd));
		vec3 wc = mix(bottom, tint, smoothstep(0.2, 6.0, wd) * 0.85);
		wc += vec3(0.75, 0.9, 0.85) * caustics(xz * 0.9, TIME) * exp(-wd * 0.5) * 0.4;
		float a = smoothstep(0.03, 0.4, wd);
		c = mix(c, wc, a);
		nn = mix(nn, vec3(0.0, 0.0, 1.0), a);
		rough_w = a;
	}
	if (protect > 0.5) {
		float stripes = step(0.82, fract((rxz.x + rxz.y) / (plane_size * 0.006)));
		c = mix(c, brush_color, stripes * 0.25);
	}
	if (show_marks) {
		float ring = smoothstep(0.30, 0.45, mark) - smoothstep(0.55, 0.70, mark);
		c = mix(c, brush_color, ring * 0.85);
	}
	if (brush.z > 0.0) {
		float d = length(rxz - brush.xy);
		float edge = 1.0 - smoothstep(0.0, brush.z * 0.025 + 0.4, abs(d - brush.z));
		c = mix(c, brush_color, edge * 0.9);
		c = mix(c, c + brush_color * 0.12, (1.0 - step(brush.z, d)) * 0.6);
	}

	ALBEDO = c;
	NORMAL_MAP = normalize(nn + vec3(0.0, 0.0, 0.001)) * 0.5 + 0.5;
	ROUGHNESS = mix(mix(0.92, 0.45, max(wet, under)), 0.06, rough_w);
	SPECULAR = 0.35;
}
