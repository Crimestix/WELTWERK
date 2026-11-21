// Globus: Meer, Breitengrade und alle platzierten Kontinente (Anzahl nicht begrenzt).
// Lage wie GlobeMath: mittabstandstreue Abbildung um (lat0, lon0), gedreht um heading.
// Je Kontinent eine Kachel (8 × 8 je Ebene) im Texturfeld (Farbe, Höhe) und zwei Texel in params
// (Spalte k % 256, Zeilenpaar k / 256):
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

const int TILES = 8;
const int PER_LAYER = 64;
const int PARAM_WIDTH = 256;
const float TILE_RES = 129.0;

uniform vec3 deep_color : source_color = vec3(0.05, 0.19, 0.36);
uniform vec3 shallow_color : source_color = vec3(0.10, 0.42, 0.48);
uniform vec3 line_color : source_color = vec3(0.85, 0.80, 0.65);
uniform vec3 outline_color : source_color = vec3(0.95, 0.76, 0.40);
uniform vec3 air_color : source_color = vec3(0.45, 0.66, 0.95);

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

ivec2 param_texel(int k, int row) {
	return ivec2(k % PARAM_WIDTH, (k / PARAM_WIDTH) * 2 + row);
}

// Kachel-Koordinaten im Texturfeld (Texelmitten, kein Übergreifen auf Nachbarkacheln).
vec3 atlas_uv(vec2 uv, int k) {
	int t = k % PER_LAYER;
	vec2 tile = vec2(float(t % TILES), float(t / TILES));
	vec2 texel = tile * TILE_RES + 0.5 + clamp(uv, 0.0, 1.0) * (TILE_RES - 1.0);
	return vec3(texel / (float(TILES) * TILE_RES), float(k / PER_LAYER));
}

bool inside(vec2 uv) {
	return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

void vertex() {
	model_dir = VERTEX;
	vec3 n = normalize(VERTEX);
	float h = 0.0;
	for (int k = 0; k < count; k++) {
		vec4 reach = texelFetch(params, param_texel(k, 1), 0);
		if (dot(n, reach.xyz) < reach.w) continue;
		vec2 uv = continent_uv(n, texelFetch(params, param_texel(k, 0), 0));
		if (inside(uv)) {
			h = max(h, textureLod(continent_data, atlas_uv(uv, k), 0.0).r);
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
		vec4 reach = texelFetch(params, param_texel(k, 1), 0);
		if (dot(n, reach.xyz) < reach.w) continue;
		vec2 uv = continent_uv(n, texelFetch(params, param_texel(k, 0), 0));
		if (!inside(uv)) continue;
		vec3 auv = atlas_uv(uv, k);
		vec4 col = texture(continent_color, auv);
		float h = texture(continent_data, auv).r;
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
	SPECULAR = 0.35;
	// Atmosphäre: heller Saum zum Rand hin.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = air_color * rim * 0.55;
}
