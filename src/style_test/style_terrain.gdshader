// Gelände des Stiltests: Fototexturen (Poly Haven, CC0), gemischt nach Neigung, Höhe und Lage.
// Variante B nutzt dieselben Texturen mit Farbanpassung (tint, saturation, brightness).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D meadow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D meadow_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D meadow_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cliff_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float tile_size = 4.0;
uniform float meadow_tile_size = 9.0;
uniform float rock_tile_size = 7.0;
uniform float sea_level = 0.0;
uniform vec2 grove_center = vec2(-20.0, -12.0);
uniform float grove_radius = 17.0;
uniform vec2 bank_from = vec2(2.0, -4.0);
uniform vec2 bank_to = vec2(30.0, 4.0);

uniform vec3 tint = vec3(1.0);
uniform float saturation = 1.0;
uniform float brightness = 1.0;

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

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
	return length(p - (a + ab * t));
}

// Zwei Maßstäbe derselben Textur gegen sichtbare Wiederholung.
vec3 albedo_two_scales(sampler2D tex, vec2 uv, float mixer) {
	vec3 a = texture(tex, uv).rgb;
	vec3 b = texture(tex, uv * 0.27 + vec2(0.37, 0.71)).rgb;
	return mix(a, b, mixer * 0.5);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	float slope = 1.0 - n.y;
	vec2 xz = world_pos.xz;
	vec2 uv = xz / tile_size;
	float macro = value_noise(xz * 0.04) * 0.6 + value_noise(xz * 0.13) * 0.4;
	float mixer = value_noise(xz * 0.08);

	float bank = 1.0 - smoothstep(3.0, 9.0, segment_distance(xz, bank_from, bank_to) + (macro - 0.5) * 4.0);
	float rock_w = clamp(smoothstep(0.30, 0.50, slope + (macro - 0.5) * 0.15) + bank * 0.7, 0.0, 1.0);
	float cliff_w = smoothstep(0.55, 0.75, slope);
	float sand_w = (1.0 - smoothstep(0.25, 1.1, world_pos.y - sea_level + (mixer - 0.5) * 0.6)) * (1.0 - rock_w);
	float forest_w = (1.0 - smoothstep(grove_radius - 6.0, grove_radius + 4.0,
		length(xz - grove_center) + (macro - 0.5) * 8.0)) * (1.0 - rock_w) * (1.0 - sand_w);
	float meadow_w = 1.0 - rock_w - sand_w - forest_w;
	float sparse = smoothstep(0.55, 0.80, macro);

	vec3 albedo = vec3(0.0);
	vec3 nrm = vec3(0.0);
	vec3 arm = vec3(0.0);
	if (meadow_w > 0.001) {
		float wg = meadow_w * (1.0 - sparse);
		float wm = meadow_w * sparse;
		if (wg > 0.001) {
			albedo += albedo_two_scales(grass_albedo, uv, mixer) * wg;
			nrm += (texture(grass_normal, uv).rgb * 2.0 - 1.0) * wg;
			arm += texture(grass_arm, uv).rgb * wg;
		}
		if (wm > 0.001) {
			vec2 muv = xz / meadow_tile_size;
			albedo += albedo_two_scales(meadow_albedo, muv, mixer) * wm;
			nrm += (texture(meadow_normal, muv).rgb * 2.0 - 1.0) * wm;
			arm += texture(meadow_arm, muv).rgb * wm;
		}
	}
	if (forest_w > 0.001) {
		albedo += albedo_two_scales(forest_albedo, uv, mixer) * forest_w;
		nrm += (texture(forest_normal, uv).rgb * 2.0 - 1.0) * forest_w;
		arm += texture(forest_arm, uv).rgb * forest_w;
	}
	if (sand_w > 0.001) {
		albedo += albedo_two_scales(sand_albedo, uv, mixer) * sand_w;
		nrm += (texture(sand_normal, uv).rgb * 2.0 - 1.0) * sand_w;
		arm += texture(sand_arm, uv).rgb * sand_w;
	}
	if (rock_w > 0.001) {
		vec2 ruv = xz / rock_tile_size;
		vec3 rock = albedo_two_scales(rock_albedo, ruv, mixer);
		if (cliff_w > 0.001) {
			// Steile Wände: Textur von der Seite (zweiseitig projiziert) statt von oben.
			vec3 bw = abs(n) + 0.0001;
			bw /= (bw.x + bw.z);
			vec3 side = texture(cliff_albedo, world_pos.zy / 5.0).rgb * bw.x
				+ texture(cliff_albedo, world_pos.xy / 5.0).rgb * bw.z;
			rock = mix(rock, side, cliff_w);
		}
		albedo += rock * rock_w;
		nrm += (texture(rock_normal, ruv).rgb * 2.0 - 1.0) * rock_w * (1.0 - cliff_w);
		arm += texture(rock_arm, ruv).rgb * rock_w;
	}

	// Großflächige Helligkeitsschwankung gegen Gleichförmigkeit.
	albedo *= 0.88 + 0.24 * macro;

	float luma = dot(albedo, vec3(0.299, 0.587, 0.114));
	albedo = mix(vec3(luma), albedo, saturation) * tint * brightness;

	float wet = 1.0 - smoothstep(sea_level - 0.4, sea_level + 0.25, world_pos.y);
	float underwater = smoothstep(sea_level, sea_level - 3.0, world_pos.y);
	albedo *= mix(1.0, 0.65, wet);
	albedo = mix(albedo, vec3(0.05, 0.20, 0.20), underwater * 0.6);

	ALBEDO = albedo;
	NORMAL_MAP = normalize(nrm + vec3(0.0, 0.0, 0.001)) * 0.5 + 0.5;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.3;
	ROUGHNESS = mix(arm.g, 0.35, wet);
	SPECULAR = 0.4;
}
