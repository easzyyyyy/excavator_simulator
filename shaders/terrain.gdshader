shader_type spatial;
// Heightfield ground. Meshes are flat grids aligned with the height grid; the
// vertex stage lifts each vertex to its grid point height and derives the normal
// from the neighbouring points. Untouched ground carries thin lines every metre and
// thick lines every five; ground cut below its built height and loose soil are
// shaded as dug earth without lines.
//
// Each chunk reads its own heights, loose thickness and loose shares from small textures
// that start one point before the chunk (chunk_origin); the material of the ground in
// place and the built heights come from whole-grid textures. The flat ring around the
// grid draws plain untouched ground of the first material.
//
// Materials: each point carries the material of its ground in place and the share of
// each material in its loose soil. Every material has its own untouched, dug and loose
// colours and a grain size: fine for sand, clods for earth, large patches for clay.

uniform sampler2D heightmap : filter_nearest, repeat_disable;
uniform sampler2D loose_map : filter_nearest, repeat_disable;
uniform sampler2D base_map : filter_nearest, repeat_disable;
uniform sampler2D material_map : filter_nearest, repeat_disable;
uniform sampler2D mix_map : filter_nearest, repeat_disable;
uniform vec2 grid_origin;
uniform float cell_size = 0.25;
uniform int grid_points = 2;
uniform ivec2 chunk_origin;
uniform bool outside_grid = false;

uniform vec3 ground_colors[4] : source_color;
uniform vec3 dug_colors[4] : source_color;
uniform vec3 loose_colors[4] : source_color;
uniform float grain_scales[4];
// Grid lines darken the untouched ground colour by these factors.
uniform float minor_line_shade = 0.79;
uniform float major_line_shade = 0.52;
uniform float fade_distance = 80.0;

varying vec3 world_pos;
varying float loose_depth;
varying float cut_depth;
varying vec3 ground_tint;
varying vec3 dug_tint;
varying vec3 loose_tint;
varying vec3 bank_grain;
varying vec3 loose_grain;

ivec2 clamped(ivec2 p) {
	return clamp(p, ivec2(0), ivec2(grid_points - 1));
}

ivec2 chunk_texel(ivec2 p) {
	return clamp(p - chunk_origin, ivec2(0), textureSize(heightmap, 0) - ivec2(1));
}

float point_height(ivec2 p) {
	return texelFetch(heightmap, chunk_texel(p), 0).r;
}

float grid_line(vec2 coord, float spacing, float width) {
	vec2 g = abs(fract(coord / spacing - 0.5) - 0.5) * spacing;
	vec2 aa = fwidth(coord) * 1.2;
	vec2 line = 1.0 - smoothstep(vec2(width), vec2(width) + aa, g);
	return max(line.x, line.y);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Weights of the three drawn grain sizes (3 cm, 11 cm, 35 cm) closest to a grain size.
vec3 grain_weights(float scale) {
	vec3 centres = vec3(-3.5, -2.2, -1.05);
	vec3 weights = max(vec3(1.0) - abs(vec3(log(max(scale, 0.01))) - centres) / 1.25, vec3(0.0));
	return weights / max(weights.x + weights.y + weights.z, 1e-4);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ivec2 p = ivec2(round((wp.xz - grid_origin) / cell_size));
	float h = 0.0;
	int m = 0;
	vec4 shares = vec4(0.0);
	if (outside_grid) {
		NORMAL = vec3(0.0, 1.0, 0.0);
		loose_depth = 0.0;
		cut_depth = 0.0;
	} else {
		h = point_height(p);
		VERTEX.y = h - MODEL_MATRIX[3].y;
		float dx = point_height(p + ivec2(1, 0)) - point_height(p - ivec2(1, 0));
		float dz = point_height(p + ivec2(0, 1)) - point_height(p - ivec2(0, 1));
		NORMAL = normalize(vec3(-dx, 2.0 * cell_size, -dz));
		loose_depth = texelFetch(loose_map, chunk_texel(p), 0).r;
		cut_depth = texelFetch(base_map, clamped(p), 0).r - (h - loose_depth);
		m = clamp(int(round(texelFetch(material_map, clamped(p), 0).r * 255.0)), 0, 3);
		shares = texelFetch(mix_map, chunk_texel(p), 0);
	}
	world_pos = vec3(wp.x, h, wp.z);
	ground_tint = ground_colors[m];
	dug_tint = dug_colors[m];
	bank_grain = grain_weights(grain_scales[m]);
	float share_sum = shares.r + shares.g + shares.b + shares.a;
	if (share_sum > 0.0) {
		loose_tint = (loose_colors[0] * shares.r + loose_colors[1] * shares.g + loose_colors[2] * shares.b
				+ loose_colors[3] * shares.a) / share_sum;
		loose_grain = (grain_weights(grain_scales[0]) * shares.r + grain_weights(grain_scales[1]) * shares.g
				+ grain_weights(grain_scales[2]) * shares.b + grain_weights(grain_scales[3]) * shares.a) / share_sum;
	} else {
		loose_tint = loose_colors[m];
		loose_grain = bank_grain;
	}
}

void fragment() {
	float speckle = mix(0.97, 1.02, hash(floor(world_pos.xz * 2.0)));
	vec3 patterns = vec3(hash(floor(world_pos.xz * 30.0)), hash(floor(world_pos.xz * 9.0)),
			hash(floor(world_pos.xz * 2.8)));
	float dug_variation = dot(bank_grain, mix(vec3(0.9), vec3(1.06), patterns));
	float loose_variation = dot(loose_grain, mix(vec3(0.86), vec3(1.1), patterns));
	float cut = smoothstep(0.02, 0.12, cut_depth);
	float loose_cover = smoothstep(0.004, 0.04, loose_depth);
	vec3 color = mix(ground_tint * speckle, dug_tint * mix(speckle, dug_variation, 0.5), cut);
	color = mix(color, loose_tint * loose_variation, loose_cover);
	float untouched = (1.0 - cut) * (1.0 - loose_cover);
	float fade = 1.0 - smoothstep(fade_distance * 0.5, fade_distance, length(world_pos.xz - CAMERA_POSITION_WORLD.xz));
	color = mix(color, ground_tint * minor_line_shade, grid_line(world_pos.xz, 1.0, 0.015) * 0.7 * fade * untouched);
	color = mix(color, ground_tint * major_line_shade, grid_line(world_pos.xz, 5.0, 0.04) * fade * untouched);
	ALBEDO = color;
	ROUGHNESS = mix(0.95, 1.0, loose_cover);
}
