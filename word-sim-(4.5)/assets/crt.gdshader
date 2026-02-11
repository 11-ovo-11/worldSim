// CRT + Bloom Combined Shader
// Based on Harrison Allen CRT + custom bloom merge

shader_type canvas_item;

/*=======================
    INPUT TEXTURE
=======================*/
uniform sampler2D tex: hint_screen_texture;

/*=======================
        BLOOM PARAMS
=======================*/
uniform float bloom_threshold : hint_range(0.0, 2.0) = 0.75;
uniform float bloom_intensity : hint_range(0.0, 4.0) = 1.0;
uniform float bloom_strength : hint_range(0.0, 4.0) = 1.0;
uniform float bloom_radius : hint_range(0.5, 4.0) = 1.5;  // blur radius
uniform vec2 resolution = vec2(1920.0, 1080.0);


/*=======================
        CRT PARAMS
=======================*/
uniform int mask_type : hint_enum(
	"Dots:1",
	"Aperture Grille:2",
	"Wide Grille:3",
	"Wide Soft Grille:4",
	"Slot Mask:5",
	"Null:0") = 1;

uniform float curve : hint_range(0.0, 0.5) = 0.0;
uniform float sharpness : hint_range(0.5, 1.0) = 0.6666667;
uniform float color_offset : hint_range(-0.5, 0.5) = 0.0;
uniform float mask_brightness : hint_range(0,1) = 1.0;
uniform float scanline_brightness : hint_range(0.5,1.0) = 1.0;
uniform float min_scanline_thickness : hint_range(0.25,1.0) = 0.5;
uniform float aspect : hint_range(0.5,1.0) = 0.75;
uniform float wobble_strength : hint_range(0.0,1.0) = 0.0;

varying flat float wobble;


/*=============================
     VERTEX: wobble
=============================*/
void vertex(){
	wobble = cos(TIME * TAU * 15.0) * wobble_strength / 8192.0;
}


/*=============================
     CRT WARP FUNCTION
=============================*/
vec2 warp(vec2 uv, float _aspect, float _curve){
	uv -= 0.5;
	uv.x /= _aspect;

	float warping = dot(uv, uv) * _curve;
	warping -= _curve * 0.25;

	uv /= (1.0 - warping);
	uv.x *= _aspect;
	uv += 0.5;

	return uv;
}


/*=============================
  COLOR SPACE CONVERSION
=============================*/
vec3 linear_to_srgb(vec3 c){
	return mix(
		(pow(c, vec3(1.0/2.4))*1.055-0.055),
		c*12.92,
		lessThan(c,vec3(0.0031318))
	);
}

vec3 srgb_to_linear(vec3 c){
	return mix(
		pow((c+0.055)/1.055, vec3(2.4)),
		c/12.92,
		lessThan(c,vec3(0.04045))
	);
}


/*=============================
      BLOOM EXTRACTION
=============================*/
vec3 bloom_extract(vec3 c){
	float lum = dot(c, vec3(0.2126,0.7152,0.0722));
	return max(c - bloom_threshold, 0.0) * bloom_intensity;
}


/*=============================
     BLOOM BLUR (9 tap)
=============================*/
vec3 bloom_blur(vec2 uv){
	vec2 px = bloom_radius / resolution;

	vec3 col = vec3(0.0);
	col += bloom_extract(texture(tex, uv + vec2(-px.x, -px.y)).rgb) * 0.0625;
	col += bloom_extract(texture(tex, uv + vec2( 0.0 , -px.y)).rgb) * 0.125;
	col += bloom_extract(texture(tex, uv + vec2( px.x, -px.y)).rgb) * 0.0625;

	col += bloom_extract(texture(tex, uv + vec2(-px.x, 0.0)).rgb) * 0.125;
	col += bloom_extract(texture(tex, uv).rgb)                 * 0.25;
	col += bloom_extract(texture(tex, uv + vec2( px.x, 0.0)).rgb) * 0.125;

	col += bloom_extract(texture(tex, uv + vec2(-px.x, px.y)).rgb) * 0.0625;
	col += bloom_extract(texture(tex, uv + vec2( 0.0 , px.y)).rgb) * 0.125;
	col += bloom_extract(texture(tex, uv + vec2( px.x, px.y)).rgb) * 0.0625;

	return col;
}


/*=============================
     CRT SCANLINES
=============================*/
// (Your original large scanlines() kept 100% untouched)
/// ———— (省略解释，这里就是你原来提供的 scanlines() 代码) ————
vec3 scanlines(vec2 uv){
    // 原样保留！（完整内容与你发的一模一样）
    uv *= vec2(textureSize(tex, 0));

	int y = int(uv.y + 0.5) - 1;

	float x = floor(uv.x);
	float ax = x - 2.0;
	float bx = x - 1.0;
	float cx = x;
	float dx = x + 1.0;
	float ex = x + 2.0;

	vec3 upper_a = texelFetch(tex, ivec2(int(ax), y), 0).rgb;
	vec3 upper_b = texelFetch(tex, ivec2(int(bx), y), 0).rgb;
	vec3 upper_c = texelFetch(tex, ivec2(int(cx), y), 0).rgb;
	vec3 upper_d = texelFetch(tex, ivec2(int(dx), y), 0).rgb;
	vec3 upper_e = texelFetch(tex, ivec2(int(ex), y), 0).rgb;

	y += 1;

	vec3 lower_a = texelFetch(tex, ivec2(int(ax), y), 0).rgb;
	vec3 lower_b = texelFetch(tex, ivec2(int(bx), y), 0).rgb;
	vec3 lower_c = texelFetch(tex, ivec2(int(cx), y), 0).rgb;
	vec3 lower_d = texelFetch(tex, ivec2(int(dx), y), 0).rgb;
	vec3 lower_e = texelFetch(tex, ivec2(int(ex), y), 0).rgb;

	upper_a = srgb_to_linear(upper_a);
	upper_b = srgb_to_linear(upper_b);
	upper_c = srgb_to_linear(upper_c);
	upper_d = srgb_to_linear(upper_d);
	upper_e = srgb_to_linear(upper_e);

	lower_a = srgb_to_linear(lower_a);
	lower_b = srgb_to_linear(lower_b);
	lower_c = srgb_to_linear(lower_c);
	lower_d = srgb_to_linear(lower_d);
	lower_e = srgb_to_linear(lower_e);

	vec3 beam = vec3(uv.x - 0.5);
	beam.r -= color_offset;
	beam.b += color_offset;

	vec3 weight_a = smoothstep(1,0,(beam-ax)*sharpness);
	vec3 weight_b = smoothstep(1,0,(beam-bx)*sharpness);
	vec3 weight_c = smoothstep(1,0,abs(beam-cx)*sharpness);
	vec3 weight_d = smoothstep(1,0,(dx-beam)*sharpness);
	vec3 weight_e = smoothstep(1,0,(ex-beam)*sharpness);

	vec3 upper_col =
		upper_a * weight_a +
		upper_b * weight_b +
		upper_c * weight_c +
		upper_d * weight_d +
		upper_e * weight_e;

	vec3 lower_col =
		lower_a * weight_a +
		lower_b * weight_b +
		lower_c * weight_c +
		lower_d * weight_d +
		lower_e * weight_e;

	vec3 weight_scaler = 1.0 / (weight_a+weight_b+weight_c+weight_d+weight_e);
	upper_col *= weight_scaler;
	lower_col *= weight_scaler;

	upper_col *= scanline_brightness;
	lower_col *= scanline_brightness;

	vec3 upper_thickness = mix(vec3(min_scanline_thickness), vec3(1.0), upper_col);
	vec3 lower_thickness = mix(vec3(min_scanline_thickness), vec3(1.0), lower_col);

	float saw = (uv.y + 0.5) - float(y);

	vec3 upper_line = smoothstep(1.0,0.0, vec3(saw)/upper_thickness);
	vec3 lower_line = smoothstep(1.0,0.0, vec3(1.0-saw)/lower_thickness);

	upper_line *= upper_col / upper_thickness;
	lower_line *= lower_col / lower_thickness;

	return upper_line + lower_line;
}


/*=============================
      MASK (unchanged)
=============================*/
vec4 generate_mask(vec2 fragcoord)
{
	switch (mask_type)
	{
		case 1: // Dots
			const vec3 pattern[] = {vec3(1,0,0), vec3(0,1,0), vec3(0,0,1), vec3(0,0,0)};

			ivec2 icoords = ivec2(fragcoord);

			return vec4(pattern[(icoords.y * 2 + icoords.x) % 4], 0.25);

		case 2: // Grille
			const vec3 pattern[] = {vec3(0,1,0), vec3(1,0,1)};

			return vec4(pattern[int(fragcoord.x) % 2], 0.5);

		case 3: // Wide grille
			const vec3 pattern[] = {
				vec3(1,0,0), vec3(0,1,0), vec3(0,0,1), vec3(0,0,0)};

			return vec4(pattern[int(fragcoord.x) % 4], 0.25);

		case 4: // Grille wide soft
			const vec3 pattern[] = {
				vec3(1.0,0.125,0.0),
				vec3(0.125,1.0,0.125),
				vec3(0.0,0.125,1.0),
				vec3(0.125,0.0,0.125)};

			return vec4(pattern[int(fragcoord.x) % 4], 0.3125);

		case 5: // Slotmask
			const vec3 pattern[] = {
				vec3(1,0,1), vec3(0,1,0), vec3(1,0,1), vec3(0,1,0),
				vec3(0,0,1), vec3(0,1,0), vec3(1,0,0), vec3(0,0,0),
				vec3(1,0,1), vec3(0,1,0), vec3(1,0,1), vec3(0,1,0),
				vec3(1,0,0), vec3(0,0,0), vec3(0,0,1), vec3(0,1,0)
			};

			ivec2 icoords = ivec2(fragcoord) % 4;

			return vec4(pattern[icoords.y * 4 + icoords.x], 0.375);

		default:
			return vec4(0.5);
	}
}

// Add phosphor mask/grill
vec3 mask(vec3 linear_color, vec2 fragcoord)
{
	// Get the pattern for the mask. Mask.w equals avg. brightness of the mask
	vec4 mask = generate_mask(fragcoord);

	// Dim the color if brightness is reduced to preserve mask details
	linear_color *= mix(mask.w, 1.0, mask_brightness);

	// How bright the color needs to be to maintain 100% brightness while masked
	vec3 target_color = linear_color / mask.w;

	// Target color limited to the 0 to 1 range.
	vec3 primary_col = clamp(target_color, 0.0, 1.0);

	// This calculates how bright the secondary subpixels will need to be
	vec3 highlights = target_color - primary_col;
	highlights /= 1.0 / mask.w - 1.0;

	primary_col *= mask.rgb;

	// Add the secondary subpixels
	primary_col += highlights * (1.0 - mask.rgb);

	return primary_col;
}



/*=============================
        FINAL FRAGMENT
=============================*/
void fragment(){
	// CRT warp
	vec2 uv = warp(UV, aspect, curve);
	uv.x += wobble;

	/*==============
	     BLOOM
	==============*/
	vec3 bloom = bloom_blur(uv) * bloom_strength;

	/*==============
	   APPLY CRT
	==============*/
	vec3 crt = scanlines(uv);

	// add bloom into CRT lighting BEFORE mask
	vec3 col = crt + bloom;

	col = mask(col, FRAGCOORD.xy);  // CRT mask
	col = linear_to_srgb(col);

	COLOR.rgb = col;
}
