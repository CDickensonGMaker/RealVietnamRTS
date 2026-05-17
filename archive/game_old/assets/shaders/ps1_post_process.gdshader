shader_type canvas_item;

// Post-processing for PS1 aesthetic
// Color depth reduction, dithering, and scanlines

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest;

uniform float color_depth : hint_range(2.0, 256.0) = 32.0;
uniform bool enable_dithering = true;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.5;
uniform bool enable_scanlines = false;
uniform float scanline_opacity : hint_range(0.0, 1.0) = 0.1;

// Bayer dither matrix (4x4)
const mat4 DITHER_MATRIX = mat4(
	vec4(0.0, 8.0, 2.0, 10.0),
	vec4(12.0, 4.0, 14.0, 6.0),
	vec4(3.0, 11.0, 1.0, 9.0),
	vec4(15.0, 7.0, 13.0, 5.0)
) / 16.0;

float get_dither_value(vec2 pixel_coord) {
	int x = int(mod(pixel_coord.x, 4.0));
	int y = int(mod(pixel_coord.y, 4.0));
	return DITHER_MATRIX[y][x] - 0.5;
}

vec3 quantize_color(vec3 color, float depth) {
	return floor(color * depth + 0.5) / depth;
}

void fragment() {
	vec2 screen_uv = SCREEN_UV;
	vec2 pixel_coord = FRAGCOORD.xy;

	// Sample screen
	vec3 color = texture(SCREEN_TEXTURE, screen_uv).rgb;

	// Apply dithering before quantization
	if (enable_dithering) {
		float dither = get_dither_value(pixel_coord) * dither_strength;
		color += vec3(dither) / color_depth;
	}

	// Reduce color depth (posterization)
	color = quantize_color(color, color_depth);

	// Optional scanlines
	if (enable_scanlines) {
		float scanline = mod(pixel_coord.y, 2.0) < 1.0 ? 1.0 : (1.0 - scanline_opacity);
		color *= scanline;
	}

	COLOR = vec4(color, 1.0);
}
