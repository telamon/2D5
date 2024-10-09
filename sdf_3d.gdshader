shader_type spatial;
//render_mode unshaded;

group_uniforms Textures;
uniform sampler2D diffuse;
uniform sampler2D depth_map;
uniform sampler2D norm_map;

group_uniforms Depth;
uniform float depth_scale : hint_range(0., 5., 0.001) = 1.;
uniform float depth_add : hint_range(-3., 3., 0.01) = 0.;
uniform float depth_resolution : hint_range(0., 1., 0.001) = 0.3;
uniform int sample_mode : hint_range(0, 5, 1) = 0;
uniform float depth_smooth : hint_range(0., 128., 0.001) = 0.;

uniform float computed_normals : hint_range(0., 1., 0.01) = 1.;

group_uniforms Debug;
uniform bool dbg_depth = false;
uniform float dbg_lod : hint_range(0.,1.,0.001) = 0.;
uniform float dbg_lod_an : hint_range(0.,1.,0.001) = 0.;

varying vec3 vert;
// Raymarching constants
const float SURFACE_DST = .01;
uniform int MAX_STEPS : hint_range(8, 2048, 4) = 128;
const float MAX_DISTANCE = 10.;

void vertex() {
	vert = VERTEX;
	// VERTEX.y *= 1.2;
}

float smax(float a, float b, float k) {
	return log(exp(k * a) + exp(k * b)) / k;
}
float smin(float a, float b, float k) {
	return -log(max(exp(k * -a) + exp(k * -b), 0.0001)) / k;
	// return -smax(-a, -b, k);
}
float aspect(sampler2D t) {
	ivec2 ts = textureSize(t, 0);
	return float(ts.y) / float(ts.x);
}
vec4 gaussTexture(sampler2D texo, vec2 tex_offset, float blur_size) {
	if (blur_size == 0.) return textureLod(texo, tex_offset, 0);
    vec3 col = vec3(0.0);
    float denominator = 0.0;

    //float blur_size = 1.0 / 1024.0;  // Adjust size to your needs
    // Gaussian kernel definition (3x3 example)
    float kernel[9] = float[](0.0625, 0.125, 0.0625, 0.125, 0.25, 0.125, 0.0625, 0.125, 0.0625);
    int idx = 0;
	float ar = aspect(texo);
    for(int y = -1; y <= 1; y++) {
        for(int x = -1; x <= 1; x++) {
            vec3 sample = textureLod(texo, tex_offset + vec2(float(x) * ar, float(y)) * blur_size, 0).rgb;
            col += sample * kernel[idx];
            denominator += kernel[idx];
            idx++;
        }
    }
    return vec4(vec3(col / denominator), 1.);
}
vec2 vert_to_uv (vec3 p) {
	return vec2(p.x, -p.y) - -0.5;
	// return (p.xy / (p.z)) - 0.5; // casuses exponential z explosion
}
float get_depth (vec2 p) {
	float d = textureLod(depth_map, p, dbg_lod * 10.).r;
	return d * depth_scale;
}

float super_sample(vec3 p) {
	float d = get_depth(vert_to_uv(p)); // center
	if (sample_mode == 0) return d;
	if (sample_mode == 3) return gaussTexture(depth_map, vert_to_uv(p), 0.01 * depth_smooth).r;
	float ar = aspect(depth_map);
	float sd = 0.011;
	vec2 bd = vec2(
		get_depth(vert_to_uv(p - vec3(sd, 0., 0.))),
		get_depth(vert_to_uv(p - vec3(0., sd * ar, 0.)))
	);
	vec2 fd = vec2(
		get_depth(vert_to_uv(p + vec3(sd, 0., 0.))),
		get_depth(vert_to_uv(p + vec3(0., sd * ar, 0.)))
	);
	float mf = min(d, min(min(bd.x, bd.y), min(fd.x, fd.y)));
	float mc = max(d, max(max(bd.x, bd.y), max(fd.x, fd.y)));

	switch(sample_mode) {
		case 0: return d;
		case 1: return mix(d, (bd.x + bd.y + fd.x + fd.y) / 5., depth_smooth / 128.);
		case 2: return smax(d, (fd.x + fd.y) / 2., depth_smooth);
	}
	return d;
}

float sdf_box(vec3 p, vec3 s) {
	vec3 obj = vec3(s);
	vec3 d = (abs(p) - obj);
	return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, 0.0));
}

float sdf_hcylinder(vec3 p, float r, float h) {
	vec2 pp = abs(vec2(length(p.xz),p.y));
	vec2 d = pp.x > r ? pp : vec2(r - pp.x, pp.y - h);
	return length(max(d,0.0)); // no cap
	// return min(max(d.x,d.y),0.0) + length(max(d,0.0)); // cap
}
float sdf_hsphere(vec3 p, float r) {
	float l = length(p);
	return l > r ? l + 0. : r - l;
}
float sdf_plane(vec3 p, vec3 n, float d) {
	return dot(n, p) - d;
}

vec2 scene(vec3 p) {
	float l = sdf_box(p, vec3(.5));
	if (l >= SURFACE_DST) return vec2(l, SURFACE_DST); 	// March to bounding box first
														// TODO: also unintenionally culls backface
	vec2 uv = vert_to_uv(p);
	float pxr = 1. / 1024.; // new surface-dist/min step
	float d = super_sample(p); //get_depth(uv);
	l = sdf_plane(p, vec3(0,0,1), 0.5 - (1. - d) + (1. - depth_scale));

	float is = max(pxr, pxr * 200. * depth_resolution);
	l = min(is, l);
	return vec2(l, pxr);
}

vec3 sample_normal3D(vec3 p) {
	const float EPS = 0.01;
	vec3 v1 = vec3(
		scene(p + vec3(EPS, 0., 0.)).s,
		scene(p + vec3(0., EPS, 0.)).s,
		scene(p + vec3(0., 0., EPS)).s
	);
	vec3 v2 = vec3(
		scene(p - vec3(EPS, 0., 0.)).s,
		scene(p - vec3(0., EPS, 0.)).s,
		scene(p - vec3(0., 0., EPS)).s
	);
	return normalize(v1 - v2);
}

// The actual raymarching function
float ray_march(vec3 ro, vec3 rd) {
	float d = 0.;
	//rd *= max((1. + sin(TIME) ) / 2., 0.001);
	for (int i = 0; i < MAX_STEPS; i++) {
		vec3 pos = ro + rd * d;
		vec2 dm = scene(pos); // (distance, min_distance);
		float sceneDst = dm.x;
		d += sceneDst;
		// Only stop if distance is higher than MAX_DISTANCE or sampled distance
		// is less that surface threshold
		if (d > MAX_DISTANCE || abs(sceneDst) <= dm.y) break;
	}
	return d;
}

vec3 floatToViridis(float value) {
    const int n = 6; // Number of key colors; increase this for smoother gradients
    vec3 colormap[n] = vec3[](
        vec3(0.167004, 0.004874, 0.329415),
        vec3(0.229739, 0.322361, 0.545706),
        vec3(0.127568, 0.566949, 0.550556),
        vec3(0.369214, 0.788888, 0.382914),
        vec3(0.993248, 0.906157, 0.143936),
        vec3(0.267004, 0.004874, 0.329415)
    );

    float index = clamp(value, 0.0, 0.999) * float(n - 1);
    int i = int(index);
    float f = fract(index);
    return mix(colormap[i], colormap[i + 1], f);
}

vec3 floatToMagma(float value) {
    const int n = 4;
    vec3 colormap[n] = vec3[](
        vec3(0.001462, 0.000466, 0.013866),
        vec3(0.258234, 0.038571, 0.406485),
        vec3(0.375713, 0.071361, 0.391917),
        vec3(0.988362, 0.998364, 0.644924)
    );

    float index = clamp(value, 0.0, 0.999) * float(n - 1);
    int i = int(index);
    float f = fract(index);
    return mix(colormap[i], colormap[i + 1], f);
}

void fragment() {
	vec3 ray_origin = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.)).xyz; // RAY ORIGIN
	vec3 ray_dir = normalize(vert - ray_origin);

	float d = ray_march(ray_origin, ray_dir);
	// Set the world position from the raymarching output
	vec3 world = ray_origin + ray_dir * d;
	vec2 uv = vert_to_uv(world);
	vec3 cnorm = sample_normal3D(world);
	float a = acos(cnorm.z);

	if (d >= MAX_DISTANCE) {
		if (dbg_depth) {
			ALBEDO = vec3(0.9, 0., 9.);
			DEPTH = 1.;
		} else discard;
	} else if (uv.y < 0. || uv.y > 1. || uv.x < 0. || uv.x > 1.) {
		discard;
		// ALBEDO=vec3(1.,0,0);
	} else {
		// gaussTexture(diffuse, uv, 0.005 * sin(TIME) * (1. - get_depth(uv))).rgb // depth blur
		ALBEDO = degrees(a) < 80.
			?  textureLod(diffuse, uv, dbg_lod_an).rgb
			: gaussTexture(diffuse, uv, 0.3).rgb;
		//if (degrees(a) >= 80.) ALBEDO=vec3(0,1,0);
		vec3 displacement = (ray_origin - world);
		NORMAL = textureLod(norm_map, uv, dbg_lod_an).rgb;
		if (computed_normals > 0.) NORMAL = mix(NORMAL, cnorm, computed_normals);
		// Depth calculation, this makes possible for other meshes intersect
		// properly with the geometry
		vec4 ndc = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.);
		float depth = (ndc.z / ndc.w) * .5f + .5f;
		if (dbg_depth) ALBEDO = floatToMagma(world.z * 2.); // Correct for depth map vis
		if (dbg_depth) ALBEDO = floatToMagma((1. - d) * 2.); // correct for SDF vis
		DEPTH = depth;
	}
}

//void light() {
	// Called for every pixel for every light affecting the material.
	// Uncomment to replace the default light processing function with this one.
//}
