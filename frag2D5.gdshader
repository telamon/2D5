/**
  2.5D Fragment shader that combines
  an image with a depth map and
  allows manipulation of the view angle through transform.
  Lights/normals also supported.
  - @telamon (Tony)
*/

shader_type canvas_item;
global uniform bool dbg_depth = false;
group_uniforms Maps;
uniform sampler2D depth_map;
uniform sampler2D norm_map;
uniform sampler2D fx_map;

group_uniforms Depth;
uniform float alpha_mask : hint_range(0.0, 1.0, 0.001) = 0;
uniform float mask_falloff : hint_range(-1., 1., 0.001) = 0;
uniform bool inst_dbg_depth = false;

uniform bool damp_boost = false; // Depth separation boost
uniform float focal_length : hint_range(0., 1., 0.001) = 0; // Depth separation
uniform float xy_separation : hint_range(0., 5., 0.001) = 0.127; // Depth separation boost
uniform float z_separation : hint_range(0., 1., 0.01) = 0.;
uniform float falloff_treshold : hint_range(0, 1., 0.001)= 1.;
uniform float norm_scale = -1.0;



group_uniforms Motion;
uniform mat3 transform = mat3(1.);
uniform int automotion : hint_range(0, 3) = 0; // 0 AUTOPAN, 1 USE_TRANSFORM
uniform float pan_speed : hint_range(-10., 10., 0.5) = 4; // Auto-pan feature

group_uniforms Effect;


uniform int fx_mode : hint_range(0, 4) = 0; // 0 DISABLED, 1 FOG, 2 ???
uniform float fx_strength : hint_range(0.0, 1.0, 0.001) = 1;
uniform float fx_depth : hint_range(0.0, 1.0, 0.001) = 0;

varying vec3 UVD;

// uniform mat3 transform;
mat3 translate_matrix(vec3 translate) {
	mat3 t = mat3(1.);
	t[0][2] = translate.x; // move camera x
	t[1][2] = translate.y; // move camera y
	t[2][2] = translate.z; // zoom
	//t[0][0] /= translate.z;	t[1][1] /= translate.z;
	return t;
}
float _samp_depth(vec2 uv) {
	vec4 depth_pix = textureLod(depth_map, uv, 0);
	float depth = depth_pix.r;
	if (fx_mode == 4) { // TODO; move to depth_displace buffer/viewport
		float f = textureLod(fx_map, uv, 0).a;
		if (f == 0.) f = 0.5;
		vec3 tuv =  vec3(uv - 0.5, 1.) * transform;
		// float f = sin(tuv.x * 6. + TIME) * cos(tuv.y * 6. + TIME);
		float displacement = (1. - f); //  (f - 0.5) * 2. * depth;
		depth = clamp(depth + displacement * fx_strength, 0., 1.);
	}
	return depth;
}
vec2 pshift(vec3 v) { return v.xy / v.z; } /* planar shift z into xy */

// Applies 2.5D transformation to uv
// returns transformed UV + depth
vec3 transform_uv(vec2 uv, mat3 tmat) { // tmat is probably synonymous with view/cam-matrix
	vec3 vuv = vec3(uv - 0.5, 1.); // View-space UV
	vec3 t = vuv * tmat; // Transformed vector
	vec2 L = 0.5 + pshift(t); // Linear transform in UV-space, planar shifted z into zoom
	float depth = _samp_depth(L); // original depth
	float d = focal_length - _samp_depth(L); // It's not focal length, it's Z-origin.
	// vec3 uv3 = vec3((uv - 0.5), 1. - f) * tmat; // Pixel view-position in 3D-space (origin 0,0,0)
	float f =  d * xy_separation; // displacement factor
	float fz = d * z_separation;
	// vec2 duv = 0.5 + pshift(vuv + (t -vuv) * -f); // displaced UV using delta scaling (looks ok sometimes but not correct)
	mat3 dmat = mat3(vec3(tmat[0]), vec3(tmat[1]), vec3(tmat[2]));
	if (damp_boost) {  dmat[0][2] *= -f; dmat[1][2] *= -f; } // dampen translation by depth factor
	else { dmat[0][2] *= 1. + f; dmat[1][2] *= 1. + f; } // boost translation by depth factor
	dmat[0][0] /= 1. - fz; dmat[1][1] /= 1. - fz; // tweak scale by perspective zoom
	dmat[0][1] /= 1. - f; // tweak shearing/rotation by depth factor as well
	dmat[1][0] /= 1. - f;
	//dmat[2][0] /= 1. - fz;
	//dmat[2][1] /= 1. - fz;
	//dmat = mat3(1.);
	//dmat *= translate_matrix(vec3(0., 0., 1. - fz));
	//dmat *= tmat;
	//dmat = mat3(
		//vec3(1., dmat[0][1] / (1. - fz), tmat[0][2] * -fz),
		//vec3(dmat[0][1] / (1. - fz), 1., tmat[1][2] * -fz),
		//vec3(dmat[2][0] / (1. - fz), dmat[2][1] / (1. - fz), 1.)
	//);

	vec2 duv = 0.5 + pshift(vuv * dmat);
	float depth2 = _samp_depth(duv); // Resample depth at displaced position.
	// depth2 = (dmat[0][1]); // use virtual rescaled depth?
	float d2 = (focal_length - depth2);
	float slope = d2 / d; // slope between depth at position and displaced position
	if (abs(d - d2) > falloff_treshold) return vec3(L, depth);
	return vec3(duv.xy, depth2);

	//float d3 = _samp_depth(mix(tuv+0.5, duv, 2.));
	//if (-(depth - d2) > falloff_treshold) duv = 0.5 + tuv; // fill bg
	//if (depth - d3 > falloff_treshold) duv = 0.5 + tuv * (scale); // stretch fg-inner
	//if ((depth - d2) > falloff_treshold) duv = 0.5 + tuv * (scale); // fill fg-outer
	//if (abs(depth - d2) > falloff_treshold) duv = L; // fill all gaps
}

mat3 rotation_matrix_z(float angle) {
	  return mat3(
        vec3(cos(angle), -sin(angle), 0.0),
        vec3(sin(angle),  cos(angle), 0.0),
        vec3(0.0,         0.0,        1.0)
    );
}
mat3 rotation_matrix_x(float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return mat3(
        vec3(1.0, 0.0, 0.0),
        vec3(0.0, c, -s),
        vec3(0.0, s, c)
    );
}
mat3 rotation_matrix_y(float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return mat3(
        vec3(c,   0.0, s),   // Rotate in the XZ plane
        vec3(0.0, 1.0, 0.0), // Y column remains unchanged
        vec3(-s,  0.0, c)    // Rotate in the XZ plane
    );
}


vec3 parallax_uv(vec2 uv) {
	float t = TIME * pan_speed;
	mat3 cam = mat3(1.);
	vec3 translate = vec3(0., 0., 1.0);
	float angle = 0.;
	vec4 displace_range = vec4(transform[0][2], transform[1][2], transform[2][2] - 1., transform[0][0]);

	switch(automotion) {
		case 0: cam = transform;
			break;
		case 1:
			cam *= translate_matrix(vec3(
				cos(t) * displace_range.x,
				abs(cos(t)) * displace_range.y,
				displace_range.w + sin(t) * displace_range.z
			));
			break;
		case 2:
			// cam *= translate_matrix(vec3(sin(t) * -displace_range.x, 0., 1.));
			float r = displace_range.z;
			mat3 o1 = translate_matrix(vec3(0., 0., r));
			mat3 o2 = rotation_matrix_y(radians(sin(t) * displace_range.x * -1.));
			mat3 o3 = translate_matrix(vec3(0., 0., (1. / r) + displace_range.w));
			cam *= o2; //o1 * o2 * o3;
			break;
	}
	return transform_uv(uv, cam);
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
	UVD = parallax_uv(UV);
	vec2 uv = UVD.xy;

	COLOR = textureLod(TEXTURE, uv, 0.);
	// COLOR.b = UVD.z;
	NORMAL = textureLod(norm_map, uv, 0).rgb;

	if (fx_mode == 1 || fx_mode == 3) { // FOG
		float d =  UVD.z;
		vec4 fx = textureLod(fx_map, 0.5 + (uv - 0.5) / d, 0);
		if (fx.a + fx_depth > d) COLOR = mix(COLOR, vec4(fx.rgb, 1.), clamp(d * fx_strength, 0., 1.));
		// NORMAL *= fx.rgb * fx.a;
	}
	if (dbg_depth || inst_dbg_depth) COLOR = vec4(floatToMagma(UVD.z), 1.);
	// COLOR = vec4(NORMAL, 1.0);
	float od = textureLod(depth_map, UVD.xy, 0).r; // apply alphamask using original/unscaled depth
	COLOR.a = od < alpha_mask ? 1. - min((alpha_mask - od) * 50. * mask_falloff, 1.) : 1.; // step(alpha_mask, od);
}

void light() {
	vec2 uv = UVD.xy;
	float depth = UVD.z;
	vec3 norm = NORMAL;

	norm *= norm_scale < 0.0 ? -norm_scale * depth : norm_scale;
	vec4 color = COLOR;
	vec3 lcol = LIGHT_COLOR.rgb;
	float energy = LIGHT_ENERGY;
	vec4 fx = fx_mode != 0 ? textureLod(fx_map, 0.5 + (uv - 0.5) / depth, 0) : vec4(0);

	switch (fx_mode) {
		case 1: // Fog
			if (fx.a + fx_depth < depth) break;
			// norm = vec3(0.0,0.0,0.9) * (1. - fx.a); // dark fog of normal corruption / opaque
			color = mix(color, fx, fx.a * (1.- depth) * fx_strength); // Close becomes transparent
			// lcol += fx.rgb * fx.a;
			// lcol = mix(lcol, fx.rgb, (1.- depth) * fx_strength);
			break;
		case 2: // Light
			if (fx.a + fx_depth < depth) break;
			lcol += fx.rgb * fx.a;
			//color = vec4(lcol, fx.a);
			// This actually only scales current energy
			// We don't have LIGHT_DIRECTION of each fx.a != 0 particle/pixel
			//norm += vec3(0.,0.,0.5);
			energy += length(lcol) * fx_strength * 5.;
			break;
		case 3: // Shadow
			if (fx.a + fx_depth < depth) break;
			lcol = mix(lcol, fx.rgb * fx.a, 0.8);
			norm *= fx.a * depth;
			//energy = energy * fx.a * (depth * fx_strength);
			break;

	}

	float cNdotL = max(0.0, dot(norm, LIGHT_DIRECTION));
	LIGHT = vec4(lcol * color.rgb * energy * cNdotL, LIGHT_COLOR.a);
}
