shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.24, 0.8, 0.76, 0.45);
uniform vec4 deep_color : source_color = vec4(0.02, 0.17, 0.33, 0.94);
uniform float depth_distance : hint_range(0.1, 10.0) = 2.0;
uniform vec4 foam_color : source_color = vec4(0.96, 0.98, 1.0, 1.0);
uniform float foam_width : hint_range(0.0, 1.0) = 0.2;
uniform float wave_height : hint_range(0.0, 1.0) = 0.1;
uniform float wave_length : hint_range(0.5, 20.0) = 4.0;
uniform float wave_speed : hint_range(0.0, 2.0, 0.01) = 0.5;

uniform sampler2D normal_map_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale : hint_range(0.0, 2.0) = 0.25;
uniform float normal_tile_size : hint_range(0.5, 50.0) = 8.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.06;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

// Reduzido de 4 para 2 ondas para aliviar a GPU no Celeron N3350
const vec2 WAVE_DIR[2] = vec2[2](
	vec2(0.958, 0.287), vec2(-0.447, 0.894)
);
const float WAVE_LENGTH[2] = float[2](1.0, 0.71);
const float WAVE_SHARE[2] = float[2](0.4, 0.27);
const float WAVE_HALF_TURNS[2] = float[2](1.0, 2.0);

varying vec2 world_xz;

vec3 waves(vec2 xz, float t) {
	float height = 0.0;
	vec2 slope = vec2(0.0);
	for (int i = 0; i < 2; i++) {
		float k = TAU / (wave_length * WAVE_LENGTH[i]);
		float phase = k * dot(WAVE_DIR[i], xz) - PI * WAVE_HALF_TURNS[i] * t;
		float amplitude = wave_height * WAVE_SHARE[i];
		height += amplitude * sin(phase);
		slope += amplitude * cos(phase) * k * WAVE_DIR[i];
	}
	return vec3(height, slope);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_xz = world.xz;
	vec3 wave = waves(world.xz, TIME * wave_speed);
	VERTEX.y += wave.x;
	vec2 slope = wave.yz;
	NORMAL = normalize(vec3(-slope.x, 1.0, -slope.y));
	TANGENT = normalize(vec3(TANGENT.x, dot(TANGENT.xz, slope), TANGENT.z));
	BINORMAL = normalize(vec3(BINORMAL.x, dot(BINORMAL.xz, slope), BINORMAL.z));
}

void fragment() {
	float t = TIME * wave_speed;

	vec2 uv = world_xz / normal_tile_size;
	vec2 uv_a = uv + vec2(0.5, 0.0) * t;
	vec2 uv_b = uv * 2.0 + vec2(-0.5, 0.5) * t;
	vec2 ripple_a = texture(normal_map_a, uv_a).rg * 2.0 - 1.0;
	vec2 ripple_b = texture(normal_map_b, uv_b).rg * 2.0 - 1.0;
	vec2 ripple = ripple_a + ripple_b;
	ripple /= max(1.0, length(ripple) / 0.95);

	float raw_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, raw_depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
#endif
	vec4 behind_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	behind_view.xyz /= behind_view.w;
	vec3 behind_world = (INV_VIEW_MATRIX * vec4(behind_view.xyz, 1.0)).xyz;
	vec3 surface_world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float water_depth = max(surface_world.y - behind_world.y, 0.0);

	vec4 water = mix(shallow_color, deep_color, clamp(water_depth / depth_distance, 0.0, 1.0));

	float edge = foam_width > 0.0 ? 1.0 - clamp(water_depth / foam_width, 0.0, 1.0) : 0.0;
	float threshold = clamp(0.5 + 0.35 * (ripple_a.x + ripple_b.y), 0.05, 0.95);
	float foam = smoothstep(threshold - 0.06, threshold + 0.06, edge);

	ALBEDO = mix(water.rgb, foam_color.rgb, foam);
	ALPHA = mix(water.a, foam_color.a, foam);
	ROUGHNESS = mix(roughness, 0.9, foam);
	SPECULAR = 0.5;
	NORMAL_MAP = vec3(ripple * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = normal_scale * (1.0 - foam);
}

