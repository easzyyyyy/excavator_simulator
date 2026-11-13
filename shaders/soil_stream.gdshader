shader_type spatial;
render_mode cull_disabled;
// Soil pouring over the bucket rim, drawn as a falling curtain of clumps. The mesh is a
// tube whose UV.x runs around its section and UV.y from the rim down to where the soil
// lands; the vertex stage lays it out in world space (the node stays at the origin) from
// the rim point, the across and outward directions, the width, the thickness at the rim,
// and the landing height at five points across. The curtain thins as the soil speeds up
// and spreads a little across.
//
// The fragment stage cuts the tube into lumps with a noise running down at flow_speed, the
// mean speed of the fall, with finer grain over it. The stream is whole at the rim, ragged
// along its outline and sides, and breaks into lumps after a long fall; coverage thins it
// out for a small flow.

const float GRAVITY = 9.8;

uniform vec3 rim_point;
uniform vec3 across_axis = vec3(1.0, 0.0, 0.0);
uniform vec3 outward_axis = vec3(0.0, 0.0, 1.0);
uniform float width = 1.0;
uniform float thickness = 0.2;
uniform float land_heights[5];
uniform float flow_speed = 4.0;
uniform float flow_time = 0.0;
uniform float coverage = 1.0;
uniform float clump_size = 0.12;
uniform vec3 dark_color : source_color = vec3(0.24, 0.18, 0.12);
uniform vec3 light_color : source_color = vec3(0.36, 0.28, 0.19);

varying float fall;
varying float side;

float landing(float across_share) {
	float x = clamp(across_share, 0.0, 1.0) * 4.0;
	int k = min(int(floor(x)), 3);
	return mix(land_heights[k], land_heights[k + 1], x - float(k));
}

// Integer hash of a noise cell, exact however far the flow coordinate runs.
float hash(vec2 cell) {
	uvec2 q = uvec2(ivec2(cell));
	uint h = (q.x * 1597334677u) ^ (q.y * 3812015801u);
	h = (h ^ (h >> 16u)) * 2246822519u;
	h ^= h >> 13u;
	return float(h) / 4294967295.0;
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float lumps(vec2 p) {
	return value_noise(p) * 0.7 + value_noise(p * 2.3 + vec2(17.1, 3.7)) * 0.3;
}

void vertex() {
	float angle = UV.x * TAU;
	side = cos(angle);
	float depth = sin(angle);
	float land = landing(side * 0.5 + 0.5);
	fall = UV.y * max(rim_point.y - land, 0.0);
	float half_width = 0.5 * width * (1.0 + 0.1 * UV.y);
	float half_thickness = 0.5 * thickness * mix(1.0, 0.45, smoothstep(0.0, 2.5, fall));
	vec3 world = rim_point + across_axis * side * half_width + outward_axis * depth * half_thickness;
	world.y = rim_point.y - fall;
	VERTEX = world;
	NORMAL = normalize(across_axis * side / half_width + outward_axis * depth / half_thickness);
	TANGENT = across_axis;
	BINORMAL = vec3(0.0, -1.0, 0.0);
}

void fragment() {
	// Metres across the curtain and along the flow, in lumps three grains long.
	vec2 metres = vec2((side * 0.5 + 0.5) * width, fall - flow_time * flow_speed);
	float lump = lumps(metres / (clump_size * 3.0));
	float grain = value_noise(metres / clump_size + vec2(5.3, 11.9));
	float n = lump * 0.75 + grain * 0.25;
	float outline = 1.0 - smoothstep(0.05, 0.7, abs(dot(NORMAL, VIEW)));
	float opening = 0.06 + 0.4 * smoothstep(0.5, 5.0, fall) + (1.0 - coverage) * 0.5
			+ smoothstep(0.6, 1.0, abs(side)) * 0.3 + outline * 0.5;
	ALPHA = smoothstep(opening - 0.03, opening + 0.03, n);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = mix(dark_color, light_color, grain) * (0.8 + 0.25 * lump);
	ROUGHNESS = 1.0;
	float e = 0.3;
	float dx = value_noise((metres + vec2(e * clump_size, 0.0)) / clump_size + vec2(5.3, 11.9)) - grain;
	float dy = value_noise((metres + vec2(0.0, e * clump_size)) / clump_size + vec2(5.3, 11.9)) - grain;
	NORMAL = normalize(NORMAL - (TANGENT * dx + BINORMAL * dy) * 1.5);
}
