shader_type canvas_item;

// Selection box shader with animated scan lines
// Creates a tactical RTS-style selection box effect

uniform vec4 fill_color : source_color = vec4(0.2, 0.6, 1.0, 0.15);
uniform vec4 border_color : source_color = vec4(0.3, 0.7, 1.0, 0.9);
uniform vec4 scanline_color : source_color = vec4(0.4, 0.8, 1.0, 0.3);
uniform float border_width : hint_range(1.0, 10.0) = 2.0;
uniform float scanline_spacing : hint_range(4.0, 32.0) = 12.0;
uniform float scanline_speed : hint_range(0.0, 100.0) = 30.0;
uniform float scanline_angle : hint_range(-1.57, 1.57) = 0.785; // ~45 degrees
uniform float corner_radius : hint_range(0.0, 20.0) = 3.0;

// Animated diagonal scan lines
float get_scanline(vec2 uv, vec2 size, float time) {
    // Rotate UV for diagonal lines
    float c = cos(scanline_angle);
    float s = sin(scanline_angle);
    vec2 rotated = vec2(
        uv.x * size.x * c - uv.y * size.y * s,
        uv.x * size.x * s + uv.y * size.y * c
    );

    // Animate and create stripe pattern
    float line = mod(rotated.x + rotated.y + time * scanline_speed, scanline_spacing);
    float stripe = smoothstep(0.0, 2.0, line) * smoothstep(scanline_spacing, scanline_spacing - 2.0, line);

    return stripe * 0.5;
}

// Rounded rectangle SDF
float rounded_rect_sdf(vec2 uv, vec2 size, float radius) {
    vec2 half_size = size * 0.5;
    vec2 q = abs(uv - half_size) - half_size + vec2(radius);
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void fragment() {
    vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
    vec2 pixel_uv = UV * size;

    // Calculate distance from rounded rect edge
    float dist = rounded_rect_sdf(pixel_uv, size, corner_radius);

    // Inside the box
    if (dist < 0.0) {
        // Base fill color
        vec4 color = fill_color;

        // Add animated scanlines
        float scanline = get_scanline(UV, size, TIME);
        color.rgb = mix(color.rgb, scanline_color.rgb, scanline * scanline_color.a);
        color.a = mix(color.a, fill_color.a + 0.1, scanline);

        // Border region (inner glow towards edge)
        float border_blend = smoothstep(-border_width, 0.0, dist);
        color = mix(color, border_color, border_blend * 0.6);

        COLOR = color;
    }
    // Border edge
    else if (dist < border_width) {
        float edge_alpha = 1.0 - smoothstep(0.0, border_width, dist);
        COLOR = vec4(border_color.rgb, border_color.a * edge_alpha);
    }
    // Outside
    else {
        COLOR = vec4(0.0);
    }
}
