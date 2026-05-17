extends Node3D
## TerrainGenerator - Creates procedural terrain for the firebase map
## Generates height variation, jungle areas, clearings, and roads

signal terrain_ready

@export var map_width: float = 200.0
@export var map_depth: float = 200.0
@export var grid_resolution: int = 50  # Vertices per side

# Terrain features
@export var max_height: float = 8.0
@export var firebase_clearing_radius: float = 25.0
@export var road_width: float = 4.0

# References
var terrain_mesh: MeshInstance3D
var nav_region: NavigationRegion3D
var collision_body: StaticBody3D

# Materials
var terrain_material: StandardMaterial3D


func _ready() -> void:
	_create_terrain_material()
	_generate_terrain()
	_generate_navigation_mesh()
	terrain_ready.emit()


func _create_terrain_material() -> void:
	terrain_material = StandardMaterial3D.new()
	terrain_material.albedo_color = Color(0.25, 0.35, 0.2)  # Jungle green
	terrain_material.roughness = 1.0


func _generate_terrain() -> void:
	# Create mesh
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var cell_width := map_width / grid_resolution
	var cell_depth := map_depth / grid_resolution

	# Firebase center
	var center := Vector3(map_width / 2, 0, map_depth / 2)

	# Generate vertices
	var heights: Array[Array] = []
	for z in range(grid_resolution + 1):
		var row: Array[float] = []
		for x in range(grid_resolution + 1):
			var world_x := x * cell_width
			var world_z := z * cell_depth
			var pos := Vector3(world_x, 0, world_z)

			# Calculate height
			var height := _calculate_height(pos, center)
			row.append(height)
		heights.append(row)

	# Generate triangles
	for z in range(grid_resolution):
		for x in range(grid_resolution):
			var x0 := x * cell_width
			var x1 := (x + 1) * cell_width
			var z0 := z * cell_depth
			var z1 := (z + 1) * cell_depth

			var h00: float = heights[z][x]
			var h10: float = heights[z][x + 1]
			var h01: float = heights[z + 1][x]
			var h11: float = heights[z + 1][x + 1]

			# Get terrain color based on height and position
			var c00 := _get_terrain_color(Vector3(x0, h00, z0), center)
			var c10 := _get_terrain_color(Vector3(x1, h10, z0), center)
			var c01 := _get_terrain_color(Vector3(x0, h01, z1), center)
			var c11 := _get_terrain_color(Vector3(x1, h11, z1), center)

			# Triangle 1
			surface_tool.set_color(c00)
			surface_tool.set_uv(Vector2(x0 / map_width, z0 / map_depth))
			surface_tool.add_vertex(Vector3(x0, h00, z0))

			surface_tool.set_color(c10)
			surface_tool.set_uv(Vector2(x1 / map_width, z0 / map_depth))
			surface_tool.add_vertex(Vector3(x1, h10, z0))

			surface_tool.set_color(c01)
			surface_tool.set_uv(Vector2(x0 / map_width, z1 / map_depth))
			surface_tool.add_vertex(Vector3(x0, h01, z1))

			# Triangle 2
			surface_tool.set_color(c10)
			surface_tool.set_uv(Vector2(x1 / map_width, z0 / map_depth))
			surface_tool.add_vertex(Vector3(x1, h10, z0))

			surface_tool.set_color(c11)
			surface_tool.set_uv(Vector2(x1 / map_width, z1 / map_depth))
			surface_tool.add_vertex(Vector3(x1, h11, z1))

			surface_tool.set_color(c01)
			surface_tool.set_uv(Vector2(x0 / map_width, z1 / map_depth))
			surface_tool.add_vertex(Vector3(x0, h01, z1))

	surface_tool.generate_normals()

	# Create mesh instance
	terrain_mesh = MeshInstance3D.new()
	terrain_mesh.name = "TerrainMesh"
	terrain_mesh.mesh = surface_tool.commit()
	terrain_mesh.material_override = terrain_material
	add_child(terrain_mesh)

	# Create collision
	_create_terrain_collision(heights)


func _calculate_height(pos: Vector3, center: Vector3) -> float:
	var dist_to_center := Vector2(pos.x, pos.z).distance_to(Vector2(center.x, center.z))

	# Flatten the firebase area
	if dist_to_center < firebase_clearing_radius:
		return 0.0

	# Road from south edge to firebase
	var road_dist: float = absf(pos.x - center.x)
	if pos.z < center.z and road_dist < road_width:
		return 0.0

	# Perlin-like noise for terrain variation
	var noise_scale := 0.02
	var height := 0.0

	# Simple layered noise approximation
	height += sin(pos.x * noise_scale * 1.0) * cos(pos.z * noise_scale * 1.0) * 3.0
	height += sin(pos.x * noise_scale * 2.3 + 1.5) * cos(pos.z * noise_scale * 2.1) * 1.5
	height += sin(pos.x * noise_scale * 4.7 + 3.2) * cos(pos.z * noise_scale * 5.3) * 0.7

	# Clamp and smooth transition at clearing edge
	if dist_to_center < firebase_clearing_radius * 1.5:
		var blend := (dist_to_center - firebase_clearing_radius) / (firebase_clearing_radius * 0.5)
		blend = clamp(blend, 0, 1)
		height *= blend

	return clamp(height, 0, max_height)


func _get_terrain_color(pos: Vector3, center: Vector3) -> Color:
	var dist_to_center := Vector2(pos.x, pos.z).distance_to(Vector2(center.x, center.z))

	# Firebase clearing - dirt/sand
	if dist_to_center < firebase_clearing_radius:
		return Color(0.45, 0.38, 0.28)  # Sandy brown

	# Road
	var road_dist: float = absf(pos.x - center.x)
	if pos.z < center.z and road_dist < road_width:
		return Color(0.4, 0.35, 0.3)  # Road brown

	# Higher areas - rocky
	if pos.y > max_height * 0.7:
		return Color(0.35, 0.35, 0.32)  # Rocky grey-green

	# Jungle - various greens
	var green_variation := sin(pos.x * 0.3) * cos(pos.z * 0.3) * 0.1
	return Color(0.2 + green_variation, 0.35 + green_variation, 0.15)


func _create_terrain_collision(heights: Array[Array]) -> void:
	collision_body = StaticBody3D.new()
	collision_body.name = "TerrainCollision"
	collision_body.collision_layer = 1  # Terrain layer
	collision_body.collision_mask = 0

	var shape := HeightMapShape3D.new()
	shape.map_width = grid_resolution + 1
	shape.map_depth = grid_resolution + 1

	# Flatten heights array
	var height_data := PackedFloat32Array()
	for row_idx: int in range(heights.size()):
		var row: Array = heights[row_idx]
		for h_idx: int in range(row.size()):
			var h: float = row[h_idx]
			height_data.append(h)

	shape.map_data = height_data

	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape

	# Scale and position to match mesh
	var scale_x := map_width / grid_resolution
	var scale_z := map_depth / grid_resolution
	collision_shape.scale = Vector3(scale_x, 1, scale_z)
	collision_shape.position = Vector3(map_width / 2, 0, map_depth / 2)

	collision_body.add_child(collision_shape)
	add_child(collision_body)


func _generate_navigation_mesh() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavigationRegion"

	var nav_mesh := NavigationMesh.new()

	# Configure navigation mesh
	nav_mesh.cell_size = 0.5
	nav_mesh.cell_height = 0.25
	nav_mesh.agent_height = 2.0
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_max_climb = 0.5
	nav_mesh.agent_max_slope = 45.0

	# Source geometry
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN

	nav_region.navigation_mesh = nav_mesh
	add_child(nav_region)

	# Bake navigation mesh after terrain is added
	await get_tree().process_frame
	nav_region.bake_navigation_mesh()


func get_height_at(pos: Vector3) -> float:
	## Get terrain height at a world position
	var cell_width := map_width / grid_resolution
	var cell_depth := map_depth / grid_resolution

	var center := Vector3(map_width / 2, 0, map_depth / 2)
	return _calculate_height(pos, center)
