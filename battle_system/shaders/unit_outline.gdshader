shader_type spatial;
render_mode unshaded, cull_front;

// Blue outline shader for player units
// Renders an extruded silhouette behind the mesh

uniform vec4 outline_color : source_color = vec4(0.2, 0.5, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 0.1) = 0.03;

void vertex() {
	// Extrude vertices along normals
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
