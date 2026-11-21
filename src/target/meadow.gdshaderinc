// Gemeinsame Wiesenfarbe für Gelände und Grasbüschel (Palette nach dem Zielbild).
// Beide Shader rechnen dieselbe Funktion an derselben Weltstelle – Gras und Boden passen zusammen.

uniform vec3 meadow_light : source_color = vec3(0.72, 0.77, 0.26);
uniform vec3 meadow_mid : source_color = vec3(0.50, 0.63, 0.17);
uniform vec3 meadow_deep : source_color = vec3(0.30, 0.46, 0.12);
uniform vec3 meadow_dry : source_color = vec3(0.74, 0.62, 0.34);

float m_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float m_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(m_hash12(i), m_hash12(i + vec2(1.0, 0.0)), u.x),
		mix(m_hash12(i + vec2(0.0, 1.0)), m_hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float m_fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * m_noise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return s;
}

// Anteil trockener Stellen (0–1).
float meadow_dryness(vec2 xz) {
	return smoothstep(0.56, 0.72, m_fbm(xz / 22.0 + 11.0) + (m_noise(xz * 0.6) - 0.5) * 0.1) * 0.6;
}

vec3 meadow_color(vec2 xz) {
	float macro = m_fbm(xz * 0.03);
	float patches = m_fbm(xz * 0.11 + 4.0);
	vec3 c = mix(meadow_mid, meadow_light, smoothstep(0.35, 0.72, macro));
	c = mix(meadow_deep, c, smoothstep(0.25, 0.55, patches));
	return mix(c, meadow_dry, meadow_dryness(xz));
}
