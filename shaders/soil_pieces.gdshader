shader_type particles;
// Stones and crumbs falling in the soil poured from the bucket. Each piece starts at a
// random point of the emission box across the rim, falls freely while tumbling about its
// own random axis, and disappears where the soil lands: under the rim, the landing height
// is read at five points across the stream (land_heights, from across_axis and width
// around rim_point). Every piece has its own random stretch, so one irregular mesh gives
// pieces of many shapes.

const float GRAVITY = 9.8;

uniform vec3 emission_extents = vec3(0.5, 0.03, 0.1);
uniform vec3 rim_point;
uniform vec3 across_axis = vec3(1.0, 0.0, 0.0);
uniform float width = 1.0;
uniform float land_heights[5];
uniform float size_min = 0.5;
uniform float size_max = 1.5;
uniform float exit_speed = 2.0;
// Colours passed on as they are, read as sRGB vertex colours by the draw material.
uniform vec3 dark_color = vec3(0.2, 0.15, 0.1);
uniform vec3 light_color = vec3(0.38, 0.29, 0.2);

float random(inout uint seed) {
	seed = seed * 747796405u + 2891336453u;
	uint word = ((seed >> ((seed >> 28u) + 4u)) ^ seed) * 277803737u;
	word = (word >> 22u) ^ word;
	return float(word) / 4294967295.0;
}

float landing(vec3 position) {
	float share = dot(position - rim_point, across_axis) / max(width, 0.01) + 0.5;
	float x = clamp(share, 0.0, 1.0) * 4.0;
	int k = min(int(floor(x)), 3);
	return mix(land_heights[k], land_heights[k + 1], x - float(k));
}

mat3 axis_rotation(vec3 axis, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	float t = 1.0 - c;
	return mat3(
			vec3(t * axis.x * axis.x + c, t * axis.x * axis.y + s * axis.z, t * axis.x * axis.z - s * axis.y),
			vec3(t * axis.x * axis.y - s * axis.z, t * axis.y * axis.y + c, t * axis.y * axis.z + s * axis.x),
			vec3(t * axis.x * axis.z + s * axis.y, t * axis.y * axis.z - s * axis.x, t * axis.z * axis.z + c));
}

// Orientation and shape of a piece at an age, the same from its number every step.
mat3 piece_basis(uint number, float age) {
	uint seed = number * 9781u + 6271u;
	vec3 axis = normalize(vec3(random(seed), random(seed), random(seed)) - 0.5 + vec3(0.0, 0.0, 1e-3));
	float start = random(seed) * TAU;
	float spin = mix(-9.0, 9.0, random(seed));
	float size = mix(size_min, size_max, random(seed));
	vec3 stretch = vec3(mix(0.7, 1.3, random(seed)), mix(0.6, 1.1, random(seed)), mix(0.8, 1.4, random(seed)));
	mat3 turn = axis_rotation(axis, start + spin * age);
	return turn * mat3(vec3(stretch.x * size, 0.0, 0.0), vec3(0.0, stretch.y * size, 0.0), vec3(0.0, 0.0, stretch.z * size));
}

void start() {
	uint seed = NUMBER * 7919u + RANDOM_SEED;
	if (RESTART_POSITION) {
		vec3 local = (vec3(random(seed), random(seed), random(seed)) * 2.0 - 1.0) * emission_extents;
		TRANSFORM = mat4(1.0);
		TRANSFORM[3].xyz = (EMISSION_TRANSFORM * vec4(local, 1.0)).xyz;
	}
	if (RESTART_VELOCITY) {
		vec3 drift = vec3(random(seed) - 0.5, 0.0, random(seed) - 0.5) * 0.3;
		VELOCITY = drift - vec3(0.0, exit_speed * mix(0.6, 1.2, random(seed)), 0.0);
	}
	if (RESTART_COLOR) {
		COLOR = vec4(mix(dark_color, light_color, random(seed)), 1.0);
	}
	if (RESTART_CUSTOM) {
		CUSTOM = vec4(0.0);
	}
	vec3 origin = TRANSFORM[3].xyz;
	TRANSFORM = mat4(piece_basis(NUMBER, 0.0));
	TRANSFORM[3] = vec4(origin, 1.0);
}

void process() {
	CUSTOM.y += DELTA;
	VELOCITY.y -= GRAVITY * DELTA;
	vec3 origin = TRANSFORM[3].xyz;
	if (origin.y + VELOCITY.y * DELTA <= landing(origin)) {
		ACTIVE = false;
	}
	TRANSFORM = mat4(piece_basis(NUMBER, CUSTOM.y));
	TRANSFORM[3] = vec4(origin, 1.0);
}
