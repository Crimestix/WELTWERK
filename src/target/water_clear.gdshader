// Klares Seewasser: Durchsicht auf den Grund mit Lichtbrechung, Farbe nach Wassertiefe
// (Türkis im Flachen, Tiefblau in der Tiefe), Himmelsspiegelung über den Fresnel-Anteil.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx, depth_draw_always;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 shallow_color : source_color = vec3(0.1, 0.78, 0.72);
uniform vec3 deep_color : source_color = vec3(0.02, 0.16, 0.33);
uniform vec3 absorption = vec3(0.42, 0.11, 0.07);
uniform float deep_depth = 7.0;
uniform float wave_strength = 0.22;
uniform float refraction = 0.025;

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

// fine = Anteil der kleinsten Wellen (in der Ferne ausgeblendet, sonst flimmert es).
float waves(vec2 p, float t, float fine) {
	return value_noise(p * 0.35 + vec2(t * 0.06, t * 0.04)) * 0.5
		+ value_noise(p * 0.9 - vec2(t * 0.05, t * 0.09)) * 0.3
		+ value_noise(p * 2.3 + vec2(t * 0.12, -t * 0.07)) * 0.2 * fine;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = length(VERTEX);
	float fine = 1.0 - smoothstep(40.0, 120.0, dist);
	float e = 0.08 + dist * 0.004;
	float hc = waves(world_pos.xz, TIME, fine);
	float hx = waves(world_pos.xz + vec2(e, 0.0), TIME, fine);
	float hz = waves(world_pos.xz + vec2(0.0, e), TIME, fine);
	float strength = wave_strength * mix(0.45, 1.0, fine);
	vec3 wn = normalize(vec3((hc - hx) / e * strength, 1.0, (hc - hz) / e * strength));
	vec3 view_normal = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// Wassertiefe senkrecht unter diesem Punkt.
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	v.xyz /= v.w;
	vec3 floor_world = (INV_VIEW_MATRIX * vec4(v.xyz, 1.0)).xyz;
	float depth = raw < 1e-6 ? 50.0 : max(world_pos.y - floor_world.y, 0.0);

	// Lichtbrechung: Grund leicht verschoben gelesen (nicht über Objekte vor dem Wasser).
	vec2 offset = wn.xz * refraction * clamp(depth, 0.0, 1.0);
	float raw2 = texture(depth_tex, SCREEN_UV + offset).r;
	vec4 v2 = INV_PROJECTION_MATRIX * vec4((SCREEN_UV + offset) * 2.0 - 1.0, raw2, 1.0);
	if (v2.z / v2.w > VERTEX.z) {
		offset = vec2(0.0);
	}
	vec3 behind = textureLod(screen_tex, SCREEN_UV + offset, 0.0).rgb;

	// Licht wird mit dem Weg durchs Wasser geschluckt (Rot zuerst): klar im Flachen, blau in der Tiefe.
	float path = depth * 1.4;
	vec3 through = behind * exp(-absorption * path);
	float deep = smoothstep(0.0, deep_depth, depth);
	vec3 body = mix(shallow_color, deep_color, deep);
	// Flach: Grund klar sichtbar, türkis eingefärbt; tief: Wasserfarbe.
	vec3 tinted = through * mix(vec3(1.0), shallow_color * 1.6, clamp(depth * 0.6, 0.0, 0.7));
	vec3 water = mix(tinted, body, smoothstep(0.15, 1.0, deep));

	float fresnel = pow(1.0 - clamp(dot(normalize(VIEW), view_normal), 0.0, 1.0), 5.0);
	NORMAL = view_normal;
	ALBEDO = vec3(0.0);
	EMISSION = water * (1.0 - fresnel * 0.6);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.55;
	float shore = 1.0 - smoothstep(0.0, 0.12, depth);
	ALPHA = 1.0 - shore * 0.85;
}
