// Laub der eigenen Blender-Bäume und -Büsche (Variante B): Eckpunktfarben aus Blender,
// dazu feines Blattmuster und Wölbung im Shader, Durchscheinen gegen die Sonne, leichter Wind.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float leaf_scale = 5.0;
uniform float bump_strength = 0.6;
uniform float wind_strength = 0.04;
uniform vec3 color_scale = vec3(1.0);

varying vec3 world_pos;
varying float height;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1, 0, 0));
	float n010 = hash13(i + vec3(0, 1, 0));
	float n110 = hash13(i + vec3(1, 1, 0));
	float n001 = hash13(i + vec3(0, 0, 1));
	float n101 = hash13(i + vec3(1, 0, 1));
	float n011 = hash13(i + vec3(0, 1, 1));
	float n111 = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

void vertex() {
	height = VERTEX.y;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 1.1 + world_pos.x * 0.21 + world_pos.z * 0.17);
	VERTEX.x += sway * wind_strength * max(VERTEX.y - 1.5, 0.0);
}

void fragment() {
	vec3 p = world_pos * leaf_scale;
	float leaves = value_noise3(p) * 0.65 + value_noise3(p * 2.3) * 0.35;
	vec3 base = COLOR.rgb * color_scale;
	ALBEDO = base * (0.62 + 0.75 * leaves);

	// Wölbung aus dem Blattmuster (Bump-Mapping über Bildschirmableitungen).
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float hx = dFdx(leaves);
	float hy = dFdy(leaves);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (hx * r1 + hy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * bump_strength);

	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
	BACKLIGHT = base * 0.5;
	AO = mix(0.55, 1.0, leaves);
}
