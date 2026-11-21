// Gelände der Zielszene: Wiese (zwei Fototexturen), trockene Stellen, Uferfels, Seegrund mit
// Lichtmustern unter Wasser. Fototexturen von Poly Haven (CC0), Farbe warm angepasst.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://src/target/meadow.gdshaderinc"

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D meadow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dry_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dry_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bottom_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bottom_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 grass_tint = vec3(0.95, 1.25, 0.5);
// Außerhalb des gestalteten Kerns liegt Wald: dunkler Waldboden statt Wiese und Ufersaum.
uniform vec4 core_rect = vec4(-150.0, -170.0, 130.0, 90.0);
uniform vec3 forest_floor : source_color = vec3(0.16, 0.24, 0.08);
uniform vec3 dry_tint = vec3(1.3, 1.05, 0.6);
uniform float saturation = 1.6;
uniform float brightness = 1.25;

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

// Lichtmuster am Seegrund (zwei verschobene Zellmuster).
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
				vec2 r = o + vec2(hash12(i + o), hash12(i + o + 7.3)) * 0.85 - f;
				m = min(m, dot(r, r));
			}
		}
		c += pow(clamp(m * 1.6, 0.0, 1.0), 3.0);
	}
	return c * 0.5;
}

vec3 grade(vec3 c, vec3 tint) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	return mix(vec3(l), c, saturation) * tint * brightness;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 xz = world_pos.xz;
	float h = world_pos.y;
	float slope = 1.0 - normalize(world_normal).y;
	float macro = fbm(xz * 0.03);
	float mixer = value_noise(xz * 0.11);

	vec2 uv_g = xz / 3.0;
	vec2 uv_m = xz / 9.0;
	// Farbe aus der gemeinsamen Wiesenpalette, Feindetail aus der Helligkeit der Fototexturen.
	float detail_l = dot(mix(texture(grass_albedo, uv_g).rgb, texture(meadow_albedo, uv_m).rgb, 0.35), vec3(0.299, 0.587, 0.114));
	vec3 grass = meadow_color(xz) * clamp(detail_l / 0.22, 0.6, 1.35);
	vec3 n_grass = texture(grass_normal, uv_g).rgb * 2.0 - 1.0;

	float dry_w = meadow_dryness(xz);
	vec3 dry = grass;
	vec3 n_dry = texture(dry_normal, xz / 4.0).rgb * 2.0 - 1.0;

	float shore_w = (1.0 - smoothstep(0.9, 1.9 + macro * 0.6, h)) * step(-0.35, h);
	float rock_w = clamp(smoothstep(0.35, 0.55, slope) + shore_w * smoothstep(0.35, 0.65, mixer + 0.2), 0.0, 1.0);
	vec3 rock = grade(texture(rock_albedo, xz / 5.0).rgb, vec3(0.95, 0.97, 0.94)) * 0.85;
	vec3 n_rock = texture(rock_normal, xz / 5.0).rgb * 2.0 - 1.0;

	float under = smoothstep(-0.05, -0.45, h);
	vec2 uv_b = xz / 3.5;
	vec3 bottom = texture(bottom_albedo, uv_b).rgb * vec3(0.95, 1.0, 0.95);
	vec3 n_bottom = texture(bottom_normal, uv_b).rgb * 2.0 - 1.0;

	vec3 c = mix(grass, dry, dry_w);
	vec3 nn = mix(n_grass, n_dry, dry_w);
	c = mix(c, rock, rock_w);
	nn = mix(nn, n_rock, rock_w);
	c = mix(c, bottom, under);
	nn = mix(nn, n_bottom, under);

	vec2 outside = max(core_rect.xy - xz, xz - core_rect.zw);
	float forest = smoothstep(-5.0, 15.0, max(outside.x, outside.y)) * (1.0 - under);
	c = mix(c, forest_floor * (0.8 + 0.4 * macro), forest * 0.9);

	// Nasser Ufersaum dunkler.
	float wet = (1.0 - smoothstep(-0.1, 0.35, h)) * (1.0 - under);
	c *= mix(1.0, 0.62, wet);

	// Lichtmuster unter Wasser, mit der Tiefe schwächer.
	float depth = max(-h, 0.0);
	float caus = caustics(xz * 0.9, TIME) * exp(-depth * 0.35) * under;
	c += vec3(0.75, 0.9, 0.85) * caus * 0.55;

	ALBEDO = c;
	NORMAL_MAP = normalize(nn + vec3(0.0, 0.0, 0.001)) * 0.5 + 0.5;
	ROUGHNESS = mix(0.92, 0.45, max(wet, under));
	SPECULAR = 0.35;
}
