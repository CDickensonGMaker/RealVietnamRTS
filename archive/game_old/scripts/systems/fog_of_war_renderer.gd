extends Node3D
## FogOfWarRenderer - Renders fog of war as a texture overlay on terrain
## Updates based on unit positions and IntelDirector data

signal fog_updated

@export var map_size: Vector2 = Vector2(200, 200)
@export var texture_resolution: int = 256  # Higher res for smoother fog
@export var update_interval: float = 0.1

# Fog texture - uses RG channels: R = currently visible, G = explored
var fog_image: Image
var fog_texture: ImageTexture
var fog_mesh: MeshInstance3D

# Explored state tracking (separate from visibility)
var explored_data: PackedFloat32Array

# Update tracking
var update_timer: float = 0.0

# Reveal settings
const SIGHT_FALLOFF: float = 0.8  # Where edge falloff starts (80% of radius)


func _ready() -> void:
	_create_fog_texture()
	_create_fog_mesh()

	# Initialize explored data
	explored_data.resize(texture_resolution * texture_resolution)
	explored_data.fill(0.0)

	# Initial fill with unexplored
	fog_image.fill(Color(0, 0, 0, 1))  # R=0 (not visible), G=0 (not explored)
	_update_texture()


func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0
		_update_fog()


func _create_fog_texture() -> void:
	fog_image = Image.create(texture_resolution, texture_resolution, false, Image.FORMAT_RGBA8)
	fog_texture = ImageTexture.create_from_image(fog_image)


func _create_fog_mesh() -> void:
	fog_mesh = MeshInstance3D.new()
	fog_mesh.name = "FogMesh"

	# Create a plane mesh covering the map
	var plane := PlaneMesh.new()
	plane.size = map_size
	plane.orientation = PlaneMesh.FACE_Y
	fog_mesh.mesh = plane

	# Position at ground level, slightly above terrain
	fog_mesh.position = Vector3(map_size.x / 2, 1.0, map_size.y / 2)

	# Create shader material for fog
	var material := ShaderMaterial.new()
	material.shader = _create_fog_shader()
	material.set_shader_parameter("fog_texture", fog_texture)
	material.render_priority = 100  # Render on top
	fog_mesh.material_override = material
	fog_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(fog_mesh)


func _create_fog_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D fog_texture : filter_linear;
uniform vec3 fog_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float explored_alpha : hint_range(0.0, 1.0) = 0.6;

void vertex() {
	// Fog stays flat on ground plane
}

void fragment() {
	vec4 fog_data = texture(fog_texture, UV);

	float visible = fog_data.r;
	float explored = fog_data.g;

	// Calculate alpha based on visibility state
	float alpha;

	if (explored < 0.01) {
		// Unexplored - fully opaque black
		alpha = 1.0;
	} else if (visible < 0.01) {
		// Explored but not visible - semi-transparent
		alpha = explored_alpha;
	} else {
		// Currently visible - fade based on visibility value
		alpha = mix(explored_alpha, 0.0, visible);
	}

	ALBEDO = fog_color;
	ALPHA = alpha;
}
"""
	return shader


func _update_fog() -> void:
	# Reset visibility while keeping explored state
	for y in range(texture_resolution):
		for x in range(texture_resolution):
			var idx := y * texture_resolution + x
			var explored := explored_data[idx]
			# R = 0 (not visible), G = explored state
			fog_image.set_pixel(x, y, Color(0, explored, 0, 1))

	# Reveal areas around player units
	for squad in GameManager.player_squads:
		if is_instance_valid(squad):
			_reveal_around_unit(squad)

	# Reveal around structures
	for structure in GameManager.structures:
		if is_instance_valid(structure):
			var sight := 15.0
			# Some structures have better sight
			if structure.has_method("get") and structure.get("sight_range"):
				sight = structure.sight_range
			_reveal_around_position(structure.global_position, sight)

	_update_texture()
	fog_updated.emit()


func _reveal_around_unit(unit: Node3D) -> void:
	var sight_range := 30.0

	# Get unit's sight range if available
	if "sight_range" in unit:
		sight_range = unit.sight_range

	_reveal_around_position(unit.global_position, sight_range)


func _reveal_around_position(world_pos: Vector3, radius: float) -> void:
	var tex_x := int((world_pos.x / map_size.x) * texture_resolution)
	var tex_y := int((world_pos.z / map_size.y) * texture_resolution)
	var tex_radius := int((radius / map_size.x) * texture_resolution)

	for dy in range(-tex_radius, tex_radius + 1):
		for dx in range(-tex_radius, tex_radius + 1):
			var px := tex_x + dx
			var py := tex_y + dy

			if px < 0 or px >= texture_resolution:
				continue
			if py < 0 or py >= texture_resolution:
				continue

			var dist := sqrt(float(dx * dx + dy * dy))
			if dist <= tex_radius:
				# Calculate visibility with soft falloff at edges
				var visibility := 1.0
				var falloff_start := tex_radius * SIGHT_FALLOFF
				if dist > falloff_start:
					visibility = 1.0 - ((dist - falloff_start) / (tex_radius - falloff_start))
				visibility = clamp(visibility, 0.0, 1.0)

				var idx := py * texture_resolution + px

				# Mark as explored (permanent)
				explored_data[idx] = 1.0

				# Set visibility (R channel) and explored (G channel)
				var current := fog_image.get_pixel(px, py)
				var new_visibility := maxf(current.r, visibility)
				fog_image.set_pixel(px, py, Color(new_visibility, 1.0, 0, 1))

				# Update IntelDirector
				var world_x := (float(px) / texture_resolution) * map_size.x
				var world_z := (float(py) / texture_resolution) * map_size.y
				IntelDirector.reveal_area(Vector3(world_x, 0, world_z), radius * 0.25)


func _update_texture() -> void:
	fog_texture.update(fog_image)


func is_position_visible(world_pos: Vector3) -> bool:
	var tex_x := int((world_pos.x / map_size.x) * texture_resolution)
	var tex_y := int((world_pos.z / map_size.y) * texture_resolution)

	if tex_x < 0 or tex_x >= texture_resolution:
		return false
	if tex_y < 0 or tex_y >= texture_resolution:
		return false

	var pixel := fog_image.get_pixel(tex_x, tex_y)
	return pixel.r > 0.5


func is_position_explored(world_pos: Vector3) -> bool:
	var tex_x := int((world_pos.x / map_size.x) * texture_resolution)
	var tex_y := int((world_pos.z / map_size.y) * texture_resolution)

	if tex_x < 0 or tex_x >= texture_resolution:
		return false
	if tex_y < 0 or tex_y >= texture_resolution:
		return false

	var idx := tex_y * texture_resolution + tex_x
	return explored_data[idx] > 0.5


func get_fog_texture() -> ImageTexture:
	return fog_texture
