shader_type canvas_item;

// Fog of War shader for minimap and viewport overlay
// Three states: unexplored (black), explored (darkened), visible (clear)

uniform sampler2D fog_texture : filter_nearest;  // R = visible, G = explored
uniform vec4 unexplored_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 explored_color : source_color = vec4(0.1, 0.1, 0.15, 0.7);
uniform float edge_softness : hint_range(0.0, 0.5) = 0.1;

void fragment() {
	vec4 fog_data = texture(fog_texture, UV);

	float visible = fog_data.r;
	float explored = fog_data.g;

	// Smooth edges
	visible = smoothstep(0.0, edge_softness, visible);
	explored = smoothstep(0.0, edge_softness, explored);

	// Calculate final fog color
	// unexplored = fully black
	// explored but not visible = darkened
	// visible = transparent

	vec4 final_color;

	if (explored < 0.1) {
		// Unexplored - full black
		final_color = unexplored_color;
	} else if (visible < 0.1) {
		// Explored but not currently visible - dark overlay
		final_color = explored_color;
	} else {
		// Currently visible - transparent
		final_color = vec4(0.0);
	}

	COLOR = final_color;
}
