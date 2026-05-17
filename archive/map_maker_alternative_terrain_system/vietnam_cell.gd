## vietnam_cell.gd - Cell generation with terrain type, vegetation, and trails
## Handles individual cell generation for the Vietnam map system
class_name VietnamCell
extends Node3D


## =============================================================================
## SIGNALS
## =============================================================================
signal cell_loaded(coords: Vector2i)
signal cell_unloaded(coords: Vector2i)
signal terrain_cleared(coords: Vector2i, zone_rect: Rect2)
signal vegetation_spawned(count: int)


## =============================================================================
## PROPERTIES
## =============================================================================
var coords: Vector2i = Vector2i.ZERO
var campaign_preset: String = "default"
var cell_data: VietnamWorldGrid.CellInfo = null
var heights: PackedFloat32Array = PackedFloat32Array()
var is_generated: bool = false

## Child nodes
var _terrain_node: Node3D = null
var _vegetation_container: Node3D = null
var _features_container: Node3D = null
var _markers_container: Node3D = null


## =============================================================================
## VEGETATION SETTINGS
## =============================================================================
const TREE_DENSITY_MULTIPLIER: float = 0.02  # Trees per square unit
const GRASS_DENSITY_MULTIPLIER: float = 0.05
const MAX_TREES_PER_CELL: int = 200
const MAX_GRASS_PATCHES_PER_CELL: int = 500


## =============================================================================
## LIFECYCLE
## =============================================================================

func _ready() -> void:
	_setup_containers()


func _setup_containers() -> void:
	_vegetation_container = Node3D.new()
	_vegetation_container.name = "Vegetation"
	add_child(_vegetation_container)

	_features_container = Node3D.new()
	_features_container.name = "Features"
	add_child(_features_container)

	_markers_container = Node3D.new()
	_markers_container.name = "Markers"
	add_child(_markers_container)


## =============================================================================
## GENERATION
## =============================================================================

## Generate the cell terrain and content
func generate(p_coords: Vector2i, p_campaign_preset: String) -> void:
	coords = p_coords
	campaign_preset = p_campaign_preset

	# Get cell data from world grid
	cell_data = VietnamWorldGrid.get_cell(coords)

	# 1. Generate base terrain heightmap
	var blend_edges: Dictionary = _calculate_blend_edges()
	var result: Dictionary = VietnamTerrain.generate(
		coords.x,
		coords.y,
		cell_data.preset_name,
		cell_data.terrain_type,
		null,  # Use default material
		blend_edges
	)

	_terrain_node = result["node"]
	heights = result["heights"]
	add_child(_terrain_node)

	# 2. Apply terrain type modifiers
	_apply_terrain_modifiers()

	# 3. Spawn vegetation based on terrain type
	_spawn_vegetation()

	# 4. Add terrain features (craters, trails, clearings)
	_spawn_features()

	# 5. Place strategic markers if defined
	_place_strategic_markers()

	is_generated = true
	cell_loaded.emit(coords)


## Regenerate terrain mesh after clearing
func regenerate_terrain_mesh(cleared_rect: Rect2) -> void:
	if not is_generated:
		return

	# Update heights in cleared area to be flat
	var flat_height: float = _get_average_height_in_rect(cleared_rect)

	var step: float = VietnamTerrain.CELL_SIZE / (VietnamTerrain.GRID_SIZE - 1)
	var half_size: float = VietnamTerrain.CELL_SIZE * 0.5

	for z in range(VietnamTerrain.GRID_SIZE):
		for x in range(VietnamTerrain.GRID_SIZE):
			var local_x: float = x * step - half_size
			var local_z: float = z * step - half_size
			var world_pos := Vector2(
				position.x + local_x,
				position.z + local_z
			)

			if cleared_rect.has_point(world_pos):
				heights[z * VietnamTerrain.GRID_SIZE + x] = flat_height

	# Rebuild mesh with new heights
	if _terrain_node:
		_terrain_node.queue_free()

	var result: Dictionary = VietnamTerrain.generate(
		coords.x,
		coords.y,
		cell_data.preset_name,
		VietnamTerrain.TerrainType.CLEARED,
		null,
		{}
	)

	# Override heights with our modified version
	_terrain_node = result["node"]
	_terrain_node.set_meta("heights", heights)
	add_child(_terrain_node)

	# Remove vegetation in cleared area
	_remove_vegetation_in_rect(cleared_rect)

	terrain_cleared.emit(coords, cleared_rect)


## =============================================================================
## INTERNAL METHODS
## =============================================================================

func _calculate_blend_edges() -> Dictionary:
	var blend: Dictionary = {}

	# Check neighboring cells for different terrain types
	var neighbors: Array[Vector2i] = VietnamWorldGrid.get_neighbors(coords)

	# North neighbor
	var north_cell: VietnamWorldGrid.CellInfo = VietnamWorldGrid.get_cell(neighbors[0])
	if north_cell.terrain_type != cell_data.terrain_type:
		blend["north"] = true

	# East neighbor
	var east_cell: VietnamWorldGrid.CellInfo = VietnamWorldGrid.get_cell(neighbors[1])
	if east_cell.terrain_type != cell_data.terrain_type:
		blend["east"] = true

	# South neighbor
	var south_cell: VietnamWorldGrid.CellInfo = VietnamWorldGrid.get_cell(neighbors[2])
	if south_cell.terrain_type != cell_data.terrain_type:
		blend["south"] = true

	# West neighbor
	var west_cell: VietnamWorldGrid.CellInfo = VietnamWorldGrid.get_cell(neighbors[3])
	if west_cell.terrain_type != cell_data.terrain_type:
		blend["west"] = true

	return blend


func _apply_terrain_modifiers() -> void:
	# Apply specific modifiers based on terrain type
	match cell_data.terrain_type:
		VietnamTerrain.TerrainType.RICE_PADDY:
			_add_water_layer()
		VietnamTerrain.TerrainType.SWAMP:
			_add_water_layer()
		VietnamTerrain.TerrainType.RIVER:
			_add_deep_water()


func _add_water_layer() -> void:
	# Add shallow water plane for rice paddies and swamps
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2(VietnamTerrain.CELL_SIZE, VietnamTerrain.CELL_SIZE)

	var water_instance := MeshInstance3D.new()
	water_instance.name = "WaterLayer"
	water_instance.mesh = water_mesh
	water_instance.position.y = 0.1  # Slightly above ground

	# Create water material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.35, 0.3, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.3
	mat.roughness = 0.2
	water_instance.material_override = mat

	_features_container.add_child(water_instance)


func _add_deep_water() -> void:
	# Add impassable water for rivers
	_add_water_layer()

	# Add collision to block movement
	var water_body := StaticBody3D.new()
	water_body.name = "WaterCollision"
	water_body.collision_layer = 1
	water_body.collision_mask = 0

	var shape := BoxShape3D.new()
	shape.size = Vector3(VietnamTerrain.CELL_SIZE, 5.0, VietnamTerrain.CELL_SIZE)

	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 2.5

	water_body.add_child(collision)
	_features_container.add_child(water_body)


func _spawn_vegetation() -> void:
	var density: float = VietnamTerrain.get_vegetation_density(cell_data.terrain_type)
	if density <= 0.0:
		return

	# Already cleared
	if cell_data.clearing_state >= 2:
		return

	var tree_count: int = int(VietnamTerrain.CELL_SIZE * VietnamTerrain.CELL_SIZE * TREE_DENSITY_MULTIPLIER * density)
	tree_count = mini(tree_count, MAX_TREES_PER_CELL)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(coords)

	var spawned: int = 0
	var half_size: float = VietnamTerrain.CELL_SIZE * 0.5

	for i in range(tree_count):
		var local_x: float = rng.randf_range(-half_size + 5.0, half_size - 5.0)
		var local_z: float = rng.randf_range(-half_size + 5.0, half_size - 5.0)
		var height: float = VietnamTerrain.get_height_at(heights, local_x, local_z)

		var tree: Node3D = _create_tree(cell_data.terrain_type, rng)
		tree.position = Vector3(local_x, height, local_z)
		_vegetation_container.add_child(tree)
		spawned += 1

	vegetation_spawned.emit(spawned)


func _create_tree(terrain_type: VietnamTerrain.TerrainType, rng: RandomNumberGenerator) -> Node3D:
	var tree := Node3D.new()
	tree.name = "Tree"

	# Create simple tree representation (CSG for now, replace with models later)
	var trunk := CSGCylinder3D.new()
	trunk.name = "Trunk"
	trunk.radius = 0.2 + rng.randf() * 0.2
	trunk.height = 3.0 + rng.randf() * 5.0

	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.35, 0.25, 0.15)
	trunk.material = trunk_mat

	trunk.position.y = trunk.height * 0.5
	tree.add_child(trunk)

	# Add foliage based on terrain
	var foliage: CSGSphere3D
	match terrain_type:
		VietnamTerrain.TerrainType.TRIPLE_CANOPY:
			foliage = CSGSphere3D.new()
			foliage.radius = 2.0 + rng.randf() * 2.0
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.1, 0.3, 0.08)
			foliage.material = mat
		VietnamTerrain.TerrainType.BAMBOO:
			foliage = CSGSphere3D.new()
			foliage.radius = 0.5 + rng.randf() * 0.5
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.2, 0.4, 0.15)
			foliage.material = mat
		_:
			foliage = CSGSphere3D.new()
			foliage.radius = 1.5 + rng.randf() * 1.5
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.15, 0.35, 0.1)
			foliage.material = mat

	foliage.name = "Foliage"
	foliage.position.y = trunk.height + foliage.radius * 0.5
	tree.add_child(foliage)

	# Random rotation
	tree.rotation.y = rng.randf() * TAU

	return tree


func _spawn_features() -> void:
	# Add features based on terrain type and cell data
	if cell_data.has_trail:
		_spawn_trail()

	# Check for special features
	if cell_data.feature_id != "":
		_spawn_special_feature(cell_data.feature_id)


func _spawn_trail() -> void:
	# Simple trail representation
	var trail := MeshInstance3D.new()
	trail.name = "Trail"

	var trail_mesh := PlaneMesh.new()
	trail_mesh.size = Vector2(4.0, VietnamTerrain.CELL_SIZE)
	trail.mesh = trail_mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.35, 0.25)
	trail.material_override = mat

	trail.position.y = 0.05
	_features_container.add_child(trail)


func _spawn_special_feature(feature_id: String) -> void:
	# Spawn markers or visual indicators for special locations
	if feature_id.begins_with("lz_"):
		_spawn_lz_marker(feature_id)
	elif feature_id.begins_with("hill_"):
		# Hills are handled by terrain, but add marker
		_spawn_hill_marker(feature_id)
	elif feature_id.begins_with("firebase_"):
		_spawn_firebase_marker(feature_id)


func _spawn_lz_marker(feature_id: String) -> void:
	# Create landing zone marker
	var marker := Node3D.new()
	marker.name = "LZ_" + feature_id

	# Circle marker on ground
	var circle := CSGTorus3D.new()
	circle.inner_radius = 8.0
	circle.outer_radius = 10.0
	circle.ring_sides = 32

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.6, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.6, 0.1)
	mat.emission_energy_multiplier = 0.5
	circle.material = mat

	circle.rotation.x = -PI / 2  # Lay flat
	marker.add_child(circle)

	_markers_container.add_child(marker)


func _spawn_hill_marker(feature_id: String) -> void:
	# Hill name marker
	var marker := Node3D.new()
	marker.name = "Hill_" + feature_id

	# Simple pole marker
	var pole := CSGCylinder3D.new()
	pole.radius = 0.1
	pole.height = 5.0
	pole.position.y = 2.5

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.1, 0.1)
	pole.material = mat

	marker.add_child(pole)
	_markers_container.add_child(marker)


func _spawn_firebase_marker(feature_id: String) -> void:
	# Firebase perimeter marker
	var marker := Node3D.new()
	marker.name = "Firebase_" + feature_id

	# Square perimeter
	var perimeter_size: float = 40.0
	var corners: Array[Vector3] = [
		Vector3(-perimeter_size/2, 0, -perimeter_size/2),
		Vector3(perimeter_size/2, 0, -perimeter_size/2),
		Vector3(perimeter_size/2, 0, perimeter_size/2),
		Vector3(-perimeter_size/2, 0, perimeter_size/2),
	]

	for i in range(4):
		var post := CSGCylinder3D.new()
		post.radius = 0.3
		post.height = 3.0
		post.position = corners[i]
		post.position.y = 1.5

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 0.35, 0.25)
		post.material = mat

		marker.add_child(post)

	_markers_container.add_child(marker)


func _place_strategic_markers() -> void:
	# Add any additional strategic markers from cell data
	pass


func _remove_vegetation_in_rect(rect: Rect2) -> void:
	for child in _vegetation_container.get_children():
		var child_pos := Vector2(
			position.x + child.position.x,
			position.z + child.position.z
		)
		if rect.has_point(child_pos):
			child.queue_free()


func _get_average_height_in_rect(rect: Rect2) -> float:
	var total: float = 0.0
	var count: int = 0
	var step: float = VietnamTerrain.CELL_SIZE / (VietnamTerrain.GRID_SIZE - 1)
	var half_size: float = VietnamTerrain.CELL_SIZE * 0.5

	for z in range(VietnamTerrain.GRID_SIZE):
		for x in range(VietnamTerrain.GRID_SIZE):
			var local_x: float = x * step - half_size
			var local_z: float = z * step - half_size
			var world_pos := Vector2(
				position.x + local_x,
				position.z + local_z
			)

			if rect.has_point(world_pos):
				total += heights[z * VietnamTerrain.GRID_SIZE + x]
				count += 1

	return total / maxf(float(count), 1.0)


## =============================================================================
## PUBLIC API
## =============================================================================

## Get height at world position within this cell
func get_height_at_world(world_pos: Vector3) -> float:
	var local_x: float = world_pos.x - position.x
	var local_z: float = world_pos.z - position.z
	return VietnamTerrain.get_height_at(heights, local_x, local_z)


## Get terrain type
func get_terrain_type() -> VietnamTerrain.TerrainType:
	if cell_data:
		return cell_data.terrain_type
	return VietnamTerrain.TerrainType.SINGLE_CANOPY


## Get speed modifier for movement
func get_speed_modifier() -> float:
	return VietnamTerrain.get_terrain_speed_modifier(get_terrain_type())


## Get concealment value
func get_concealment() -> float:
	return VietnamTerrain.get_terrain_concealment(get_terrain_type())


## Can build here
func can_build() -> bool:
	return cell_data != null and cell_data.clearing_state >= 2


## Unload cell
func unload() -> void:
	cell_unloaded.emit(coords)
	queue_free()
