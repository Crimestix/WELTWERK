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

uniform vec3 map_meadow_light : source_color = vec3(0.42, 0.54, 0.18);
uniform vec3 map_meadow_mid : source_color = vec3(0.30, 0.44, 0.13);
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

// --- Kartenbestand (assets/map/) -----------------------------------------------------------------
// Gestaltungsvariante: 0 = gemalt (Farben aus Regeln, Kleinrelief aus Erosionskacheln),
// 1 = Luftbild (Fels, Wald, Wiese, Boden, Küste aus gekachelten Luftbild-Texturen, gleiches Relief).
uniform int map_style = 1;
// Erosionskacheln (eigene Erzeugung, Blender): Normale und Masken (R Rinne, G Grat, B Steilheit, A Höhe).
uniform sampler2D erosion_alpine_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D erosion_alpine_masks : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D erosion_hills_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D erosion_hills_masks : hint_default_black, filter_linear_mipmap, repeat_enable;
// Lage der Erosionskacheln in der Welt (wie ErosionField.placements): je Größe (Texel je Meter,
// cos, sin, Anteil) und Versatz in Texeln; dazu die Formel der Höhen (TerrainWindow).
uniform vec4 relief_alp[3];
uniform vec2 relief_alp_off[3];
uniform vec4 relief_hil[2];
uniform vec2 relief_hil_off[2];
uniform float relief_base_scale = 1.0;
uniform float grid_cell_m = 3000.0;
uniform float mountain_foot = 250.0;
uniform float carve = 1.05;
uniform float foothill_relief = 260.0;
uniform float detail_px = 260.0;
uniform float relief_strength = 1.0;
uniform float rock_px = 320.0;
uniform float meadow_px = 300.0;
uniform float forest_px = 160.0;
uniform sampler2D tex_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_snow : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_forest : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_conifer : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_meadow : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_dry : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_shallows : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

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

// Gradientenrauschen (rund statt kästchenförmig wie Wertrauschen) mit ganzzahliger Mischfunktion.
float g_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a0 = m_hash12(i) * 6.2831853;
	float a1 = m_hash12(i + vec2(1.0, 0.0)) * 6.2831853;
	float a2 = m_hash12(i + vec2(0.0, 1.0)) * 6.2831853;
	float a3 = m_hash12(i + vec2(1.0, 1.0)) * 6.2831853;
	float v0 = dot(vec2(cos(a0), sin(a0)), f);
	float v1 = dot(vec2(cos(a1), sin(a1)), f - vec2(1.0, 0.0));
	float v2 = dot(vec2(cos(a2), sin(a2)), f - vec2(0.0, 1.0));
	float v3 = dot(vec2(cos(a3), sin(a3)), f - vec2(1.0, 1.0));
	return clamp(0.5 + 0.75 * mix(mix(v0, v1, u.x), mix(v2, v3, u.x), u.y), 0.0, 1.0);
}

// Muster in festen Metern, dessen Wellenlänge etwa „px“ Bildpunkte beträgt: zwei Oktaven werden
// nach dem Zoom überblendet, das Muster bleibt an seinem Ort (kein Schwimmen beim Zoomen). Jede
// Oktave ist gedreht, damit sich keine Rasterrichtung abzeichnet.
float screen_pattern(vec2 m, float px_m, float px, float salt) {
	float lvl = log2(max(px_m * px, 1.0));
	float l0 = floor(lvl);
	float t = lvl - l0;
	mat2 rot = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	float a = g_noise(rot * (m / exp2(l0)) + salt);
	float b = g_noise(rot * rot * (m / exp2(l0 + 1.0)) + salt * 1.7 + 5.3);
	return mix(a, b, t);
}

mat2 rot2(float a) {
	return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
}

// Kleinrelief aus einer Erosionskachel: je Zoomstufe eine gedrehte, versetzte Abtastung, zwei
// Stufen überblendet. Gibt die Steigung (dh/dx, dh/dz) zurück, mask: Rinne, Grat, Steilheit, Höhe.
vec2 relief(sampler2D nmap, sampler2D masks, vec2 m, float px_m, float px, float salt, out vec4 mask) {
	float lvl = log2(max(px_m * px, 1.0));
	float l0 = floor(lvl);
	float t = lvl - l0;
	vec2 grad = vec2(0.0);
	mask = vec4(0.0);
	for (int k = 0; k < 2; k++) {
		float level = l0 + float(k);
		float w = k == 0 ? 1.0 - t : t;
		mat2 r = rot2(level * 1.7 + salt);
		vec2 uv = r * (m / exp2(level)) + vec2(0.37, 0.71) * (level + salt);
		vec2 nxy = texture(nmap, uv).xy * 2.0 - 1.0;
		float nz = sqrt(max(1.0 - dot(nxy, nxy), 0.04));
		vec2 g_tex = vec2(-nxy.x, nxy.y) / nz;
		grad += (transpose(r) * g_tex) * w;
		mask += texture(masks, uv) * w;
	}
	return grad;
}

// Kachelkoordinate (0–1 je Kachel) eines Kontinentpunkts für eine Kachelgröße.
vec2 geo_uv(vec4 r, vec2 off, vec2 p) {
	return (vec2(p.x * r.y - p.y * r.z, p.x * r.z + p.y * r.y) * r.x + off) / 1024.0;
}

// Steigung des Kachelanteils feiner als das Raster (Meter Kachelhöhe je Meter, mal 0–1-Skala):
// Abtastung in Pixelfeinheit minus Abtastung in Rasterfeinheit. scale: Umrechnung der in der
// Normalenkarte gespeicherten Neigung auf die 0–1-Kachelhöhe je Meter Kachelgröße.
vec2 geo_gradient(sampler2D nmap, vec4 r, vec2 off, vec2 p, float px, float cell, float scale) {
	vec2 uv = geo_uv(r, off, p);
	float lod_px = max(log2(max(px * r.x, 1e-6)), 0.0);
	float lod_grid = max(log2(max(2.0 * cell * r.x, 1e-6)), 0.0);
	if (lod_px >= lod_grid) {
		return vec2(0.0);
	}
	vec2 a = textureLod(nmap, uv, lod_px).xy * 2.0 - 1.0;
	vec2 b = textureLod(nmap, uv, lod_grid).xy * 2.0 - 1.0;
	// Normale → Neigung in Kachelrichtung (u nach rechts, v nach unten im Bild).
	vec2 sa = vec2(-a.x, a.y) / sqrt(max(1.0 - dot(a, a), 0.04));
	vec2 sb = vec2(-b.x, b.y) / sqrt(max(1.0 - dot(b, b), 0.04));
	vec2 d = (sa - sb) * scale * r.x / 1024.0;
	// Zurück in Weltachsen (Kachel = Drehung der Welt).
	return vec2(d.x * r.y + d.y * r.z, -d.x * r.z + d.y * r.y);
}

vec4 geo_masks(sampler2D masks, vec4 r, vec2 off, vec2 p, float px) {
	vec2 uv = geo_uv(r, off, p);
	return textureLod(masks, uv, max(log2(max(px * r.x, 1e-6)), 0.0));
}

// Luftbild-Textur in festen Metern, Kachel etwa px Bildpunkte, zwei Zoomstufen überblendet; je
// Stufe zwei gedrehte Abtastungen, von großem Rauschen gemischt (bricht Wiederholungsmuster).
vec3 tex_world(sampler2D tex, vec2 m, float px_m, float px, float salt) {
	float lvl = log2(max(px_m * px, 1.0));
	float l0 = floor(lvl);
	float t = lvl - l0;
	vec3 c = vec3(0.0);
	for (int k = 0; k < 2; k++) {
		float level = l0 + float(k);
		float w = k == 0 ? 1.0 - t : t;
		float tile = exp2(level);
		vec2 uv1 = rot2(level * 2.3 + salt) * (m / tile) + vec2(0.13, 0.57) * salt;
		vec2 uv2 = rot2(level * 2.3 + salt + 2.1) * (m / (tile * 0.77)) + vec2(0.61, 0.29) * salt;
		float b = smoothstep(0.3, 0.7, g_noise(m / (tile * 1.9) + salt + level));
		c += mix(texture(tex, uv1).rgb, texture(tex, uv2).rgb, b) * w;
	}
	return c;
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
	float land = step(0.0, height_f);

	// --- Geografisches Erosionsrelief ---------------------------------------------------------------
	// Grate und Täler sind Teil der Höhen (TerrainWindow/ErosionField) und damit in jedem Maßstab am
	// selben Ort. Hier kommt nur der Anteil hinzu, der feiner als das Raster ist: dieselbe Kachel in
	// derselben Weltlage, als Normale, und zwar Pixelauflösung minus Rasterauflösung – so verdoppelt
	// sich nichts, und beim Vertiefen wird genau dieses Kleinrelief zu Geometrie.
	float mountain = clamp(smoothstep(450.0, 1700.0, height_f) * 0.75 + smoothstep(0.05, 0.3, slope) * 0.5, 0.0, 1.0) * land;
	float above = max(height_f - mountain_foot, 0.0);
	float foothill_w = smoothstep(40.0, 350.0, height_f) * (1.0 - smoothstep(900.0, 1800.0, height_f)) * land;
	vec2 geo = vec2(m.x, -m.y) * relief_base_scale;   // Kontinentmeter (x Osten, y Norden) der Grundform
	vec2 g_world = vec2(0.0);                           // dh/dx, dh/dy in Metern je Meter
	vec4 alp = vec4(0.0);
	vec4 hil = vec4(0.0);
	float px_geo = px_m * relief_base_scale;
	float cell_geo = grid_cell_m * relief_base_scale;
	if (above > 1.0) {
		for (int k = 0; k < 3; k++) {
			vec2 gk = geo_gradient(erosion_alpine_normal, relief_alp[k], relief_alp_off[k], geo, px_geo, cell_geo, 9.6);
			g_world += gk * above * carve * 2.0 * relief_alp[k].w;
			alp += geo_masks(erosion_alpine_masks, relief_alp[k], relief_alp_off[k], geo, px_geo) * relief_alp[k].w;
		}
	}
	if (foothill_w > 0.001) {
		for (int k = 0; k < 2; k++) {
			vec2 gk = geo_gradient(erosion_hills_normal, relief_hil[k], relief_hil_off[k], geo, px_geo, cell_geo, 24.0);
			g_world += gk * foothill_relief * foothill_w * relief_hil[k].w;
			hil += geo_masks(erosion_hills_masks, relief_hil[k], relief_hil_off[k], geo, px_geo) * relief_hil[k].w;
		}
	}
	// In Darstellungseinheiten (Überhöhung) und auf die glatte Geländenormale aufsetzen.
	vec2 g_disp = g_world * height_scale / meadow_scale * relief_strength;
	vec3 n_raw = n / max(n.y, 0.05);
	vec3 nd = normalize(vec3(n_raw.x - g_disp.x, 1.0, n_raw.z + g_disp.y));
	float d_slope = 1.0 - nd.y;
	float upland = foothill_w * (1.0 - mountain);
	// Rinnen (Abfluss) und Grate derselben Kachel in derselben Lage – geografisch, nicht Muster.
	float gully = alp.r * mountain + hil.r * upland * 0.7;
	float crest = alp.g * mountain + hil.g * upland * 0.6;
	float steep = alp.b * mountain;

	// --- Wiesen und Grasland: Klima, Höhe, Feuchte, große Flecken --------------------------------
	float vary = 0.0;
	float lam = 40.0;
	for (int o = 0; o < 8; o++) {
		float fade = 1.0 - smoothstep(0.15, 0.6, px_m / lam);
		vary += (m_noise(m / lam + float(o) * 13.7) - 0.5) * fade * (0.5 + 0.12 * float(o));
		lam *= 4.0;
	}
	float moist = clamp(0.62 - dryness * 0.8 + valley * 0.35 + vary * 0.35 + gully * 0.5 - crest * 0.25, 0.0, 1.0);
	float speck = screen_pattern(m, px_m, 3.0, 2.0);
	float mottle = screen_pattern(m, px_m, 12.0, 6.0);
	// Gemalte Wiesenfarbe nach Regeln (Variante B; in A als grüne Grundtönung beigemischt).
	vec3 painted = mix(map_meadow_mid, map_meadow_light, clamp(0.5 + vary * 1.2, 0.0, 1.0));
	painted = mix(painted, lush_color, smoothstep(0.5, 0.95, moist) * 0.6);
	float dry_patch = smoothstep(0.5, 0.8, m_noise(m / 60000.0 + 31.0) * 0.6 + m_noise(m / 14000.0 + 5.0) * 0.4);
	painted = mix(painted, steppe_color, clamp(smoothstep(0.3, 0.0, moist) * 0.6 + dry_patch * 0.2 * smoothstep(0.25, 0.6, dryness), 0.0, 0.6));
	vec3 grass;
	if (map_style == 1) {
		// Luftbild: Wiesenmosaik und trockener Boden nach Feuchte; die gemalte Tönung hält das
		// Tiefland grün wie in der Referenz, die Textur liefert Mosaik und Gebüsch.
		vec3 meadow = tex_world(tex_meadow, m, px_m, meadow_px, 5.0);
		vec3 dry = tex_world(tex_dry, m, px_m, meadow_px, 11.0);
		grass = mix(dry, meadow, smoothstep(-0.15, 0.2, moist + (mottle - 0.5) * 0.25));
		float lum = dot(grass, vec3(0.3, 0.55, 0.15));
		// Grüner als das Luftbild allein (das Mosaik behält seine Helligkeit).
		grass = mix(grass, painted * (lum / max(dot(painted, vec3(0.3, 0.55, 0.15)), 0.01)), 0.6);
	} else {
		grass = painted * (0.84 + 0.2 * speck + 0.14 * mottle);
	}
	// Höhenstufen: Hochland olivbraun, damit Ebenen und Bergland auseinanderzuhalten sind.
	grass = mix(grass, highland_color, smoothstep(1000.0, 2400.0, height_f) * 0.45);

	// --- Wald: Dichte als Anteil, im Gebirge in den Rinnen, nicht auf den Graten -----------------------
	float clumps = screen_pattern(m, px_m, 4.0, 9.0) * 0.45 + screen_pattern(m, px_m, 14.0, 13.0) * 0.35
		+ screen_pattern(m, px_m, 45.0, 17.0) * 0.2;
	float density = forest_f * 1.15 + (1.0 - smoothstep(0.2, 0.6, dryness)) * 0.12 * smoothstep(0.0, 0.25, forest_f + moist * 0.2);
	// Im Gebirge: Rinnen und Unterhänge bewaldet (unter der Baumgrenze), Grate kahl.
	float below_treeline = 1.0 - smoothstep(treeline - 150.0, treeline + 350.0, height_f);
	density += (gully * 1.1 - crest * 0.9 + 0.15) * 0.7 * mountain * below_treeline;
	float cover = smoothstep(clumps - 0.06, clumps + 0.06, density);
	float conifer = clamp(0.1 + smoothstep(400.0, 1500.0, height_f) * 0.85 + conifer_bias * 0.5 + vary * 0.3, 0.0, 1.0);
	vec3 trees = forest_dark;
	if (cover < 0.001) {
	} else if (map_style == 1) {
		vec3 b = tex_world(tex_forest, m, px_m, forest_px, 7.0);
		vec3 c = tex_world(tex_conifer, m, px_m, forest_px, 13.0);
		// Etwas dunkler als das Luftbild: Waldmassen sollen sich wie in der Referenz abheben.
		trees = mix(b, c, smoothstep(0.45, 0.7, conifer)) * 0.82;
	} else {
		float crowns = screen_pattern(m, px_m, 3.2, 21.0);
		float crowns2 = screen_pattern(m, px_m, 9.0, 33.0);
		float lit = smoothstep(0.3, 0.85, crowns * 0.65 + crowns2 * 0.35);
		vec3 broad = mix(forest_dark, forest_light, lit) * (0.92 + vary * 0.4);
		vec3 needles = mix(conifer_dark, conifer_light, lit);
		trees = mix(broad, needles, smoothstep(0.45, 0.7, conifer));
	}
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
	float alpine = smoothstep(treeline - 200.0, treeline + 500.0, height_f + vary * 300.0);
	// Fels auf Graten und steilen Flanken (auch im Kleinrelief der Kachel), Täler bleiben grün;
	// der Übergang folgt der Kachelstruktur statt einer weichen Höhenlinie.
	float ridge = clamp(-curv / 150.0, 0.0, 1.0);
	float rock_score = d_slope * 1.3 + ridge * 0.15 + crest * 0.45 + steep * 0.3 - gully * 0.5 + (rocky - 0.5) * 0.12;
	float rock_w = max(smoothstep(0.32, 0.55, rock_score) * smoothstep(700.0, 1500.0, height_f), alpine * 0.85);
	rock_w = max(rock_w, smoothstep(0.6, 0.85, d_slope + crest * 0.2) * smoothstep(80.0, 300.0, height_f) * 0.7);
	// Massive: Fels folgt dem Kleinrelief – Grate und Steilflanken felsig, Rinnen grün.
	float massif = mountain * smoothstep(500.0, 1200.0, height_f)
		* smoothstep(0.3, 0.58, crest * 0.75 + d_slope * 1.1 - gully * 0.9 + (rocky - 0.5) * 0.2 + 0.05);
	rock_w = max(rock_w, massif);
	float snow_score = height_f + vary * 400.0 + clamp(-curv, -100.0, 300.0) + (crest - gully) * 500.0 * mountain;
	float snow_w = smoothstep(snowline - 150.0, snowline + 150.0, snow_score) * (1.0 - smoothstep(0.62, 0.85, d_slope));
	vec3 snow = snow_color;
	if (map_style == 1) {
		snow = mix(snow_color, tex_world(tex_snow, m, px_m, rock_px, 23.0), 0.6);
	}

	vec3 rock = rock_color;
	if (rock_w < 0.001 && height_f > 150.0) {
	} else if (map_style == 1) {
		rock = tex_world(tex_rock, m, px_m, rock_px, 17.0);
		// Heller Kalk/Granit wie in der Referenz; Grate hell, Rinnen schattig.
		rock = rock * 1.18 * (0.88 + 0.32 * crest - 0.22 * gully);
	} else {
		rock = mix(rock_dark_color, rock_color, smoothstep(0.2, 0.8, rocky * 0.5 + crest * 0.6 - gully * 0.4 + 0.2));
		rock = mix(rock, scree_color, smoothstep(0.55, 0.9, alp.a * (1.0 - gully)) * 0.45);
	}
	vec3 c = mix(ground, rock, rock_w);
	c = mix(c, snow, snow_w);

	// --- Küste: Strand in flachen Buchten, Fels an steilen Küsten; Meeresgrund unter Wasser --------
	float sea_near = 0.0;
	for (int k = 0; k < 8; k++) {
		float a = float(k) * 0.785398;
		vec2 o = vec2(cos(a), sin(a)) * du * 1.6;
		sea_near = max(sea_near, 1.0 - smoothstep(-6.0, 0.0, texture(data_lin, tuv + o).r));
	}
	float coast_band = sea_near * (1.0 - smoothstep(4.0, 80.0, height_f)) * land;
	float cliff = smoothstep(0.25, 0.5, d_slope + crest * 0.3);
	vec3 beach_c = sand_color * (0.92 + 0.12 * speck);
	vec3 coast_rock = rock;
	// (Die Strand-Textur aus dem Bestand zeigt Kiesel aus Bodennähe – im Kartenmaßstab falsch,
	// daher heller Sand nach Regeln; Steilküsten zeigen den Fels.)
	c = mix(c, mix(beach_c, coast_rock, cliff), coast_band * 0.85);
	float under = 1.0 - smoothstep(-2.0, 0.5, height_f);
	vec3 seabed = mix(sand_color, seabed_color, smoothstep(0.0, 60.0, -height_f));
	if (map_style == 1) {
		seabed = mix(tex_world(tex_shallows, m, px_m, meadow_px, 31.0), seabed_color, smoothstep(10.0, 120.0, -height_f));
	}
	c = mix(c, seabed, under);

	// Ufer von Binnengewässern: dunklerer, feuchter Saum.
	float wet = smoothstep(0.0, 1.5, water_f);
	c = mix(c, c * vec3(0.72, 0.8, 0.72), wet * 0.6);

	// --- Kartenschummerung (Licht von Nordwesten) mit Kleinrelief ----------------------------------
	vec3 ns = normalize(vec3(nd.x * 2.6, nd.y, nd.z * 2.6));
	vec3 light = normalize(vec3(-0.65, 0.9, -0.75));
	float shade = clamp(dot(ns, light) / light.y, 0.25, 1.25);
	c *= mix(1.0, shade, hillshade * land);
	// Täler etwas dunkler, Grate heller; Rinnen der Kachel als Schattenlinien.
	c *= 1.0 + clamp(-curv / 400.0, -0.18, 0.12) * land * smoothstep(100.0, 600.0, height_f);
	c *= 1.0 - gully * 0.22 * (1.0 - snow_w * 0.5);

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
	// Normale mit Kleinrelief für das Sonnenlicht (Schatten der Grate).
	NORMAL = normalize((VIEW_MATRIX * vec4(nd, 0.0)).xyz);
	ROUGHNESS = rough;
	SPECULAR = 0.25;
}
