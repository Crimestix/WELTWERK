// Granitfelsen: Flechtengranit-Textur (Higgsfield) dreiseitig in Weltkoordinaten projiziert,
// Feinrelief aus der Poly-Haven-Felsnormale, Moos auf Oberseiten, nass und dunkler unter Wasser.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D granite : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float scale = 0.33;
uniform vec3 moss_color : source_color = vec3(0.42, 0.5, 0.16);
uniform float brightness = 1.05;

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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = world_pos * scale;
	vec3 c = texture(granite, p.zy).rgb * w.x + texture(granite, p.xz).rgb * w.y + texture(granite, p.xy).rgb * w.z;
	// Granit kühler und kontrastreicher; Flechten bleiben gelbgrün, Fels grau.
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	float lichen = smoothstep(0.05, 0.2, c.g - c.b);
	c = mix(vec3(l) * vec3(0.92, 0.95, 1.0), c, mix(0.35, 1.0, lichen));
	c = (c - 0.5) * 1.25 + 0.48;
	// Großflächige Helligkeitsflecken, damit Felsen nicht gleichförmig wirken.
	c *= 0.78 + 0.35 * value_noise(world_pos.xz * 0.35 + world_pos.y * 0.2);
	vec3 tn = (texture(rock_normal, p.zy * 1.7).rgb * w.x + texture(rock_normal, p.xz * 1.7).rgb * w.y
		+ texture(rock_normal, p.xy * 1.7).rgb * w.z) * 2.0 - 1.0;
	// Moos auf flachen Oberseiten, fleckig.
	float moss = smoothstep(0.65, 0.92, n.y) * smoothstep(0.45, 0.7, value_noise(world_pos.xz * 0.9));
	c = mix(c, moss_color * (0.8 + 0.4 * value_noise(world_pos.xz * 6.0)), moss * 0.75);
	// Nass und dunkler unter dem Wasserspiegel, Saum knapp darüber.
	float wet = 1.0 - smoothstep(-0.05, 0.3, world_pos.y);
	c *= mix(1.0, 0.55, wet);
	ALBEDO = c * brightness;
	// Weltnormale leicht durch das Feinrelief kippen.
	vec3 bent = normalize(n + vec3(tn.x, 0.0, tn.y) * 0.35);
	NORMAL = normalize((VIEW_MATRIX * vec4(bent, 0.0)).xyz);
	ROUGHNESS = mix(0.85, 0.3, wet);
	SPECULAR = 0.35;
}
