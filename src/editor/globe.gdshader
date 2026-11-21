// Globus: Meer, Breitengrade und alle platzierten Kontinente (Anzahl nicht begrenzt).
// Lage wie GlobeMath: mittabstandstreue Abbildung um (lat0, lon0), gedreht um heading.
// Je Kontinent eine Ebene im Texturfeld (Farbe, Höhe) und zwei Texel in params:
//   Zeile 0: Breite, Länge, Ausrichtung (Grad), Fenstergröße (m)
//   Zeile 1: Mittelpunkt als Einheitsvektor, Kosinus der Reichweite (schnelle Vorprüfung)
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray continent_color : source_color, filter_linear, repeat_disable;
uniform sampler2DArray continent_data : filter_linear, repeat_disable;  // R = Höhe (m)
uniform sampler2D params : filter_nearest, repeat_disable;
uniform int count = 0;
uniform int selected = -1;
uniform float planet_radius_m = 6371000.0;
uniform float relief_scale = 0.0;

uniform vec3 deep_color : source_color = vec3(0.03, 0.12, 0.25);
uniform vec3 shallow_color : source_color = vec3(0.10, 0.42, 0.48);
uniform vec3 line_color : source_color = vec3(0.85, 0.80, 0.65);
uniform vec3 outline_color : source_color = vec3(0.95, 0.76, 0.40);

varying vec3 model_dir;

vec2 continent_uv(vec3 n, vec4 p) {
	float phi = asin(clamp(n.y, -1.0, 1.0));
	float lam = atan(n.x, n.z);
	float phi0 = radians(p.x);
	float dlam = lam - radians(p.y);
	float cos_c = clamp(sin(phi0) * sin(phi) + cos(phi0) * cos(phi) * cos(dlam), -1.0, 1.0);
	float c = acos(cos_c);
	float kk = c < 1e-6 ? 1.0 : c / sin(c);
	float e = planet_radius_m * kk * cos(phi) * sin(dlam);
	float no = planet_radius_m * kk * (cos(phi0) * sin(phi) - sin(phi0) * cos(phi) * cos(dlam));
	float h = radians(p.z);
	float x = e * cos(h) - no * sin(h);
	float y = e * sin(h) + no * cos(h);
	return vec2(x / p.w + 0.5, 0.5 - y / p.w);
}

bool inside(vec2 uv) {
	return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

void vertex() {
	model_dir = VERTEX;
	vec3 n = normalize(VERTEX);
	float h = 0.0;
	for (int k = 0; k < count; k++) {
		vec4 reach = texelFetch(params, ivec2(k, 1), 0);
		if (dot(n, reach.xyz) < reach.w) continue;
		vec2 uv = continent_uv(n, texelFetch(params, ivec2(k, 0), 0));
		if (inside(uv)) {
			h = max(h, textureLod(continent_data, vec3(uv, float(k)), 0.0).r);
		}
	}
	VERTEX += n * max(h, 0.0) * relief_scale;
}

void fragment() {
	vec3 n = normalize(model_dir);
	float lat = degrees(asin(clamp(n.y, -1.0, 1.0)));
	vec3 c = deep_color;
	float rough = 0.55;
	float land_acc = 0.0;
	for (int k = 0; k < count; k++) {
		vec4 reach = texelFetch(params, ivec2(k, 1), 0);
		if (dot(n, reach.xyz) < reach.w) continue;
		vec2 uv = continent_uv(n, texelFetch(params, ivec2(k, 0), 0));
		if (!inside(uv)) continue;
		vec4 col = texture(continent_color, vec3(uv, float(k)));
		float h = texture(continent_data, vec3(uv, float(k))).r;
		// Flachwasser nur dort, wo noch kein Land eines anderen Kontinents liegt.
		vec3 sea = mix(shallow_color, c, smoothstep(-20.0, -600.0, h));
		c = mix(c, sea, 1.0 - land_acc);
		c = mix(c, col.rgb, col.a);
		land_acc = max(land_acc, col.a);
		rough = mix(rough, 0.9, col.a);
		if (k == selected) {
			// Gewählter Kontinent: Messingrahmen um sein Fenster und Saum an der Küste.
			vec2 edge = min(uv, 1.0 - uv);
			float frame = 1.0 - smoothstep(0.0, 0.006, min(edge.x, edge.y));
			float coast = 1.0 - smoothstep(0.0, 0.25, abs(col.a - 0.5));
			c = mix(c, outline_color, max(frame * 0.7, coast * 0.55));
		}
	}
	float px = fwidth(lat) * 1.2;
	float equator = 1.0 - smoothstep(0.0, px * 1.5, abs(lat));
	float grid = 0.0;
	for (int k = -2; k <= 2; k++) {
		if (k == 0) continue;
		grid = max(grid, 1.0 - smoothstep(0.0, px, abs(lat - float(k) * 30.0)));
	}
	c = mix(c, line_color, max(equator * 0.8, grid * 0.45));
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.2;
}
