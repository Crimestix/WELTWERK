// Landschaft eines Ausschnitts (Kontinent bis grobe Region) als hochwertige, gut lesbare Karte.
// Gitter wird auf der Grafikkarte aus der Datentextur gehoben. Datentextur: R = Höhe (m),
// G = Wald (0–1), B = Bearbeitungsmarke (+2 wo geschützt), A = Tiefe eines Binnengewässers (m).
// Gewässer im Land (Flüsse, Seen) zeichnet die Landschaftsansicht als eigene Flächen; hier nur
// Ufer und feuchter Grund. Licht und Schummerung aus glatt (bikubisch) gefilterten Höhen – so
// zeigen sich keine Rasterkanten. Kleinteilige Musterung (Kronen, Wiesenflecken) ist Darstellung
// in festen Metern: Sie wandert beim Zoomen nicht und gehört nicht zur Geografie.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Gemeinsame Wiesenpalette und Umrechnung in Meter (meadow_origin, meadow_scale).
#include "res://src/target/meadow.gdshaderinc"

uniform sampler2D data_tex : filter_nearest, repeat_disable;
uniform sampler2D data_lin : filter_linear, repeat_disable;
uniform int res = 257;
uniform float plane_size = 1000.0;
uniform float height_scale = 1.0;
uniform float snowline = 3000.0;
uniform float treeline = 2100.0;
uniform float dryness = 0.3;
uniform float canopy = 1.0;        // 1 = Wald als Kronendach färben (grobe Ansicht), 0 = Waldboden
uniform float hillshade = 0.55;    // Stärke der Kartenschummerung zusätzlich zum Sonnenlicht
uniform bool show_marks = true;
uniform bool show_protect = false; // Schutzflächen schraffiert (nur beim Werkzeug „Schützen“)
uniform vec3 brush = vec3(0.0, 0.0, -1.0);   // x, z, Radius in Darstellungseinheiten
uniform vec3 brush_color : source_color = vec3(0.88, 0.70, 0.38);
// Umgebung: gröberer Ausschnitt um den aktuellen herum; innerhalb von hole (x0, z0, x1, z1) ausgespart.
uniform bool is_context = false;
uniform vec4 hole = vec4(0.0);

uniform vec3 map_meadow_light : source_color = vec3(0.52, 0.57, 0.21);
uniform vec3 map_meadow_mid : source_color = vec3(0.38, 0.48, 0.15);
uniform vec3 lush_color : source_color = vec3(0.23, 0.39, 0.11);
uniform vec3 highland_color : source_color = vec3(0.52, 0.49, 0.31);
uniform vec3 steppe_color : source_color = vec3(0.71, 0.60, 0.33);
uniform vec3 forest_dark : source_color = vec3(0.06, 0.17, 0.055);
uniform vec3 forest_light : source_color = vec3(0.23, 0.37, 0.10);
uniform vec3 conifer_dark : source_color = vec3(0.04, 0.12, 0.07);
uniform vec3 conifer_light : source_color = vec3(0.11, 0.22, 0.12);
uniform vec3 forest_floor_color : source_color = vec3(0.20, 0.17, 0.10);
uniform vec3 rock_color : source_color = vec3(0.55, 0.52, 0.47);
uniform vec3 rock_dark_color : source_color = vec3(0.30, 0.28, 0.26);
uniform vec3 scree_color : source_color = vec3(0.64, 0.60, 0.53);
uniform vec3 sand_color : source_color = vec3(0.86, 0.78, 0.57);
uniform vec3 snow_color : source_color = vec3(0.95, 0.96, 0.98);
uniform vec3 seabed_color : source_color = vec3(0.55, 0.55, 0.42);
// Kronendach als Luftbild (in Metern gekachelt), für Ausschnitte, in denen Kronen erkennbar sind.
uniform sampler2D canopy_broadleaf : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D canopy_conifer : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float conifer_bias = 0.0;   // kälteres Klima: mehr Nadelwald

varying vec3 world_pos;
varying vec2 uv_v;
varying float mark;
varying float protect;

// --- Glatte Höhen ------------------------------------------------------------------------------

vec4 bspline_weights(float v) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	float w = 6.0 - x - y - z;
	return vec4(x, y, z, w) * (1.0 / 6.0);
}

// Bikubische B-Spline-Filterung mit vier linearen Zugriffen: stetige Steigung, keine Rasterkanten.
vec4 smooth_data(vec2 uv) {
	float size = float(res);
	vec2 st = uv * size - 0.5;
	vec2 f = fract(st);
	st -= f;
	vec4 xc = bspline_weights(f.x);
	vec4 yc = bspline_weights(f.y);
	vec4 c = st.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
	vec4 o = (c + vec4(xc.yw, yc.yw) / s) / size;
	vec4 s0 = texture(data_lin, o.xz);
	vec4 s1 = texture(data_lin, o.yz);
	vec4 s2 = texture(data_lin, o.xw);
	vec4 s3 = texture(data_lin, o.yw);
	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);
	return mix(mix(s3, s2, sx), mix(s1, s0, sx), sy);
}

float h_smooth(vec2 uv) {
	return smooth_data(uv).r;
}

// Muster in festen Metern, dessen Wellenlänge etwa „px“ Bildpunkte beträgt: zwei Oktaven werden
// nach dem Zoom überblendet, das Muster bleibt an seinem Ort (kein Schwimmen beim Zoomen).
float screen_pattern(vec2 m, float px_m, float px, float salt) {
	float lvl = log2(max(px_m * px, 1.0));
	float l0 = floor(lvl);
	float t = lvl - l0;
	float a = m_noise(m / exp2(l0) + salt);
	float b = m_noise(m / exp2(l0 + 1.0) + salt * 1.7 + 5.3);
	return mix(a, b, t);
}

void vertex() {
	ivec2 p = ivec2(round(UV * float(res - 1)));
	vec4 d = texelFetch(data_tex, p, 0);
	protect = step(1.5, d.b);
	mark = d.b - 2.0 * protect;
	uv_v = UV;
	// Gewässer werden nicht angehoben (eigene Flächen in der Ansicht) – keine Stufen am Ufer.
	VERTEX.y = d.r * height_scale;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 xz = world_pos.xz;
	if (is_context && xz.x > hole.x && xz.x < hole.z && xz.y > hole.y && xz.y < hole.w) {
		discard;
	}
	// Gitterpunkt i liegt bei uv = i/(res-1); die Textur hat Texelmitten bei (i+0,5)/res.
	vec2 tuv = (uv_v * float(res - 1) + 0.5) / float(res);
	float du = 1.0 / float(res);
	vec4 dl = smooth_data(tuv);
	float height_f = dl.r;
	float forest_f = dl.g;
	float water_f = dl.a;

	// Normale und Krümmung aus glatten Höhen (in Darstellungseinheiten, mit Überhöhung).
	float hl = h_smooth(tuv + vec2(-du, 0.0));
	float hr = h_smooth(tuv + vec2(du, 0.0));
	float hn = h_smooth(tuv + vec2(0.0, -du));
	float hs = h_smooth(tuv + vec2(0.0, du));
	float cell_r = plane_size / float(res - 1);
	vec3 n = normalize(MODEL_NORMAL_MATRIX * normalize(vec3((max(hl, 0.0) - max(hr, 0.0)) * height_scale, 2.0 * cell_r,
		(max(hn, 0.0) - max(hs, 0.0)) * height_scale)));
	float slope = 1.0 - n.y;
	// Krümmung in Metern: negativ auf Kämmen, positiv in Tälern (für Feuchte und Kammlicht).
	float curv = (hl + hr + hn + hs - 4.0 * height_f);
	// Weitere Umgebung (vier Zellen): Täler und Mulden sind feuchter und grüner.
	float r4 = 4.0 * du;
	float wide = (texture(data_lin, tuv + vec2(r4, 0.0)).r + texture(data_lin, tuv - vec2(r4, 0.0)).r
		+ texture(data_lin, tuv + vec2(0.0, r4)).r + texture(data_lin, tuv - vec2(0.0, r4)).r) * 0.25;
	float valley = clamp((wide - height_f) / 500.0, -1.0, 1.0);

	vec2 m = to_meters(xz);
	float px_m = max(length(fwidth(m)), 0.001);

	// --- Wiesen und Grasland: Klima, Höhe, Feuchte, große Flecken --------------------------------
	float vary = 0.0;
	float lam = 40.0;
	for (int o = 0; o < 8; o++) {
		float fade = 1.0 - smoothstep(0.15, 0.6, px_m / lam);
		vary += (m_noise(m / lam + float(o) * 13.7) - 0.5) * fade * (0.5 + 0.12 * float(o));
		lam *= 4.0;
	}
	float moist = clamp(0.62 - dryness * 0.8 + valley * 0.3 + vary * 0.35, 0.0, 1.0);
	vec3 grass = mix(map_meadow_mid, map_meadow_light, clamp(0.5 + vary * 1.2, 0.0, 1.0));
	grass = mix(grass, lush_color, smoothstep(0.5, 0.95, moist) * 0.6);
	float dry_patch = smoothstep(0.5, 0.8, m_noise(m / 60000.0 + 31.0) * 0.6 + m_noise(m / 14000.0 + 5.0) * 0.4);
	grass = mix(grass, steppe_color, clamp(smoothstep(0.3, 0.0, moist) * 0.7 + dry_patch * 0.25 * (0.4 + dryness), 0.0, 0.7));
	// Höhenstufen: Hochland olivbraun, damit Ebenen und Bergland auseinanderzuhalten sind.
	grass = mix(grass, highland_color, smoothstep(1000.0, 2400.0, height_f) * 0.5);
	// Feine Flecken etwa drei Bildpunkte groß – Lebendigkeit wie auf einer gemalten Karte.
	float speck = screen_pattern(m, px_m, 3.0, 2.0);
	float mottle = screen_pattern(m, px_m, 12.0, 6.0);
	grass *= 0.84 + 0.2 * speck + 0.14 * mottle;

	// --- Wald: dunkle, gekörnte Massen mit lockerem Rand ------------------------------------------
	// Walddichte als Anteil: Ein Punkt ist Wald, wo ein kleinteiliges Gehölzmuster unter der Dichte
	// liegt – dichter Wald ist geschlossen, lichter zerfällt in Haine und Gehölze, der Rand franst aus.
	float clumps = screen_pattern(m, px_m, 4.0, 9.0) * 0.45 + screen_pattern(m, px_m, 14.0, 13.0) * 0.35
		+ screen_pattern(m, px_m, 45.0, 17.0) * 0.2;
	float density = forest_f * 1.15 + (1.0 - smoothstep(0.2, 0.6, dryness)) * 0.12 * smoothstep(0.0, 0.25, forest_f + moist * 0.2);
	float cover = smoothstep(clumps - 0.06, clumps + 0.06, density);
	float conifer = clamp(0.1 + smoothstep(400.0, 1500.0, height_f) * 0.85 + conifer_bias * 0.5 + vary * 0.3, 0.0, 1.0);
	float crowns = screen_pattern(m, px_m, 2.6, 21.0);
	float crowns2 = screen_pattern(m, px_m, 1.4, 33.0);
	float lit = smoothstep(0.35, 0.8, crowns * 0.7 + crowns2 * 0.3);
	vec3 broad = mix(forest_dark, forest_light, lit) * (0.92 + vary * 0.4);
	vec3 needles = mix(conifer_dark, conifer_light, lit);
	vec3 trees = mix(broad, needles, smoothstep(0.45, 0.7, conifer));
	// Nah genug für einzelne Kronen: Luftbild in Metern.
	float photo = 1.0 - smoothstep(1.2, 3.0, px_m);
	if (photo > 0.0) {
		vec3 b = mix(texture(canopy_broadleaf, m / 230.0).rgb, texture(canopy_broadleaf, m.yx / 610.0 + 0.37).rgb, 0.35);
		vec3 c = mix(texture(canopy_conifer, m / 190.0).rgb, texture(canopy_conifer, m.yx / 530.0 + 0.61).rgb, 0.35) * vec3(1.02, 1.1, 0.78);
		trees = mix(trees, mix(b, c, smoothstep(0.45, 0.7, conifer)), photo);
	}
	vec3 ground = mix(grass, mix(forest_floor_color, trees, canopy), cover);

	// --- Fels, Geröll, Schnee ---------------------------------------------------------------------
	float rocky = screen_pattern(m, px_m, 4.0, 41.0);
	vec3 rock = mix(rock_dark_color, rock_color, smoothstep(0.25, 0.8, rocky + clamp(-curv / 60.0, -0.3, 0.3)));
	rock = mix(rock, scree_color, smoothstep(0.6, 0.95, rocky) * 0.5);
	float alpine = smoothstep(treeline - 200.0, treeline + 500.0, height_f + vary * 300.0);
	// Fels erst im Bergland: niedrige Hügel bleiben grün, auch wenn sie überhöht steil wirken.
	float rock_w = max(smoothstep(0.5, 0.72, slope + (rocky - 0.5) * 0.12) * smoothstep(800.0, 1500.0, height_f), alpine * 0.85);
	float snow_w = smoothstep(snowline - 120.0, snowline + 200.0, height_f + (vary - 0.0) * 500.0 + clamp(-curv, -100.0, 300.0))
		* (1.0 - smoothstep(0.62, 0.8, slope));

	vec3 c = mix(ground, rock, rock_w);
	c = mix(c, snow_color, snow_w);

	// --- Küste: schmaler heller Strand, wo Land an Meer grenzt; Meeresgrund unter Wasser ---------
	float sea_near = 0.0;
	for (int k = 0; k < 8; k++) {
		float a = float(k) * 0.785398;
		vec2 o = vec2(cos(a), sin(a)) * du * 1.6;
		sea_near = max(sea_near, 1.0 - smoothstep(-6.0, 0.0, texture(data_lin, tuv + o).r));
	}
	float beach = sea_near * (1.0 - smoothstep(4.0, 60.0, height_f)) * (1.0 - smoothstep(0.35, 0.6, slope)) * step(0.0, height_f);
	c = mix(c, sand_color * (0.92 + 0.12 * speck), beach * 0.85);
	float under = 1.0 - smoothstep(-2.0, 0.5, height_f);
	vec3 seabed = mix(sand_color, seabed_color, smoothstep(0.0, 60.0, -height_f));
	c = mix(c, seabed, under);

	// Ufer von Binnengewässern: dunklerer, feuchter Saum.
	float wet = smoothstep(0.0, 1.5, water_f);
	c = mix(c, c * vec3(0.72, 0.8, 0.72), wet * 0.6);

	// --- Kartenschummerung (Licht von Nordwesten) und Kammlicht -----------------------------------
	vec3 light = normalize(vec3(-0.65, 0.9, -0.75));
	float shade = clamp(dot(n, light) / light.y, 0.35, 1.15);
	float land = step(0.0, height_f);
	c *= mix(1.0, shade, hillshade * land);
	// Täler etwas dunkler, Grate heller: Gebirge wirken plastisch auch bei flachem Licht.
	c *= 1.0 + clamp(-curv / 400.0, -0.18, 0.12) * land * smoothstep(100.0, 600.0, height_f);

	float rough = mix(0.95, 0.7, snow_w);

	if (show_protect && protect > 0.5) {
		float stripes = step(0.86, fract((xz.x + xz.y) / (plane_size * 0.008)));
		c = mix(c, brush_color, stripes * 0.35);
	}
	if (show_marks) {
		float ring = smoothstep(0.30, 0.45, mark) - smoothstep(0.55, 0.70, mark);
		c = mix(c, brush_color, ring * 0.7);
	}
	if (brush.z > 0.0) {
		float d = length(xz - brush.xy);
		float px = length(fwidth(xz));
		float edge = 1.0 - smoothstep(0.0, px * 1.5, abs(d - brush.z));
		c = mix(c, brush_color, edge * 0.9);
		c = mix(c, c + brush_color * 0.1, (1.0 - step(brush.z, d)) * 0.5);
	}

	ALBEDO = c;
	// Glatte Normale für das Sonnenlicht (Schatten der Gebirge, keine Facetten).
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = rough;
	SPECULAR = 0.25;
}
