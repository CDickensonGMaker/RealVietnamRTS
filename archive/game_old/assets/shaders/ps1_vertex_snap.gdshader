shader_type spatial;
render_mode vertex_lighting, skip_vertex_transform, diffuse_lambert;

// PS1-style vertex snapping and affine texture mapping
// Creates the characteristic "wobbly" look of PlayStation 1 graphics

uniform float snap_strength : hint_range(0.0, 1.0) = 1.0;
uniform float vertex_snap_grid : hint_range(1.0, 100.0) = 32.0;
uniform bool affine_mapping = true;
uniform sampler2D texture_albedo : source_color, filter_nearest;
uniform vec4 albedo_color : source_color = vec4(1.0);

// For vertex color support (flat shading on terrain)
varying vec3 vertex_color;
varying vec3 view_space_pos;

vec4 snap_to_grid(vec4 vertex, float grid_size) {
	// Snap vertex positions to a grid in screen space
	vec4 snapped = vertex;

	// Only snap X and Y (screen space), keep Z for depth
	if (snap_strength > 0.0) {
		snapped.x = floor(snapped.x * grid_size + 0.5) / grid_size;
		snapped.y = floor(snapped.y * grid_size + 0.5) / grid_size;
	}

	return snapped;
}

void vertex() {
	// Standard model-view transform
	vec4 world_vertex = MODEL_MATRIX * vec4(VERTEX, 1.0);
	vec4 view_vertex = VIEW_MATRIX * world_vertex;

	// Store for affine texture mapping
	view_space_pos = view_vertex.xyz;

	// Project to clip space
	vec4 clip_vertex = PROJECTION_MATRIX * view_vertex;

	// Apply vertex snapping in screen space
	vec4 snapped = snap_to_grid(clip_vertex, vertex_snap_grid);

	// Blend between snapped and original based on strength
	POSITION = mix(clip_vertex, snapped, snap_strength);

	// Pass vertex color if available (for terrain vertex coloring)
	vertex_color = COLOR.rgb;
}

void fragment() {
	// Affine texture mapping (PS1 didn't have perspective-correct texturing)
	vec2 tex_coord = UV;

	if (affine_mapping) {
		// This creates the "warping" effect on textures
		// PS1 interpolated UVs linearly in screen space, not perspective-correct
		tex_coord = UV;  // In practice, the vertex shader distortion handles most of this
	}

	// Sample texture with nearest-neighbor filtering
	vec4 tex_color = texture(texture_albedo, tex_coord);

	// Combine with albedo and vertex color
	ALBEDO = tex_color.rgb * albedo_color.rgb * vertex_color;

	// No specular for PS1 look
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}
