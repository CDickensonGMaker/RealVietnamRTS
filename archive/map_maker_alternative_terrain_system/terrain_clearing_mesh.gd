## terrain_clearing_mesh.gd - Dynamic mesh updates when jungle is cleared
## Handles real-time terrain modification for firebase construction
class_name TerrainClearingMesh
extends RefCounted


## =============================================================================
## CLEARING EFFECTS
## =============================================================================
const CLEARING_STAGES: Dictionary = {
	0: {  # JUNGLE
		"name": "Dense Jungle",
		"vegetation_multiplier": 1.0,
		"height_flattening": 0.0,
		"ground_color": Color(0.15, 0.35, 0.1),
	},
	1: {  # PARTIALLY_CLEARED
		"name": "Partially Cleared",
		"vegetation_multiplier": 0.3,
		"height_flattening": 0.3,
		"ground_color": Color(0.35, 0.3, 0.2),
	},
	2: {  # CLEARED
		"name": "Cleared",
		"vegetation_multiplier": 0.0,
		"height_flattening": 0.8,
		"ground_color": Color(0.5, 0.4, 0.3),
	},
	3: {  # FORTIFIED
		"name": "Fortified",
		"vegetation_multiplier": 0.0,
		"height_flattening": 1.0,
		"ground_color": Color(0.55, 0.45, 0.35),
	},
}


## =============================================================================
## CLEARING ZONE CLASS
## =============================================================================
class ClearingZone:
	var id: String = ""
	var rect: Rect2 = Rect2()
	var center: Vector3 = Vector3.ZERO
	var radius: float = 0.0
	var clearing_stage: int = 0
	var progress: float = 0.0
	var assigned_engineers: Array = []

	func get_area() -> float:
		if radius > 0.0:
			return PI * radius * radius
		return rect.size.x * rect.size.y

	func is_complete() -> bool:
		return progress >= 100.0


## =============================================================================
## STATE
## =============================================================================
static var _clearing_zones: Dictionary = {}  # zone_id -> ClearingZone
static var _affected_cells: Dictionary = {}  # Vector2i -> Array of zone_ids


## =============================================================================
## ZONE MANAGEMENT
## =============================================================================

## Create a circular clearing zone
static func create_circular_zone(center: Vector3, radius: float) -> ClearingZone:
	var zone := ClearingZone.new()
	zone.id = "zone_%d" % randi()
	zone.center = center
	zone.radius = radius
	zone.rect = Rect2(
		center.x - radius,
		center.z - radius,
		radius * 2,
		radius * 2
	)

	_register_zone(zone)
	return zone


## Create a rectangular clearing zone
static func create_rect_zone(rect: Rect2) -> ClearingZone:
	var zone := ClearingZone.new()
	zone.id = "zone_%d" % randi()
	zone.rect = rect
	zone.center = Vector3(
		rect.position.x + rect.size.x * 0.5,
		0.0,
		rect.position.y + rect.size.y * 0.5
	)
	zone.radius = 0.0

	_register_zone(zone)
	return zone


static func _register_zone(zone: ClearingZone) -> void:
	_clearing_zones[zone.id] = zone

	# Find affected cells
	var cells: Array[Vector2i] = _get_cells_in_zone(zone)
	for cell_coords in cells:
		if not _affected_cells.has(cell_coords):
			_affected_cells[cell_coords] = []
		_affected_cells[cell_coords].append(zone.id)


static func _get_cells_in_zone(zone: ClearingZone) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []

	var start_x: int = int(floor(zone.rect.position.x / VietnamTerrain.CELL_SIZE))
	var start_y: int = int(floor(zone.rect.position.y / VietnamTerrain.CELL_SIZE))
	var end_x: int = int(ceil((zone.rect.position.x + zone.rect.size.x) / VietnamTerrain.CELL_SIZE))
	var end_y: int = int(ceil((zone.rect.position.y + zone.rect.size.y) / VietnamTerrain.CELL_SIZE))

	for x in range(start_x, end_x + 1):
		for y in range(start_y, end_y + 1):
			cells.append(Vector2i(x, y))

	return cells


## =============================================================================
## CLEARING PROGRESS
## =============================================================================

## Update clearing progress for a zone
static func update_clearing_progress(zone_id: String, delta_progress: float) -> Dictionary:
	if not _clearing_zones.has(zone_id):
		return {"success": false, "error": "Zone not found"}

	var zone: ClearingZone = _clearing_zones[zone_id]
	zone.progress = clampf(zone.progress + delta_progress, 0.0, 100.0)

	# Check for stage advancement
	var old_stage: int = zone.clearing_stage
	var new_stage: int = _calculate_stage(zone.progress)

	if new_stage > old_stage:
		zone.clearing_stage = new_stage
		_apply_stage_change(zone, old_stage, new_stage)

		return {
			"success": true,
			"stage_changed": true,
			"old_stage": old_stage,
			"new_stage": new_stage,
			"progress": zone.progress,
		}

	return {
		"success": true,
		"stage_changed": false,
		"progress": zone.progress,
	}


static func _calculate_stage(progress: float) -> int:
	if progress >= 100.0:
		return 3  # FORTIFIED
	elif progress >= 66.0:
		return 2  # CLEARED
	elif progress >= 33.0:
		return 1  # PARTIALLY_CLEARED
	else:
		return 0  # JUNGLE


static func _apply_stage_change(zone: ClearingZone, old_stage: int, new_stage: int) -> void:
	# Update all affected cells
	var cells: Array[Vector2i] = _get_cells_in_zone(zone)

	for cell_coords in cells:
		# Update world grid data
		VietnamWorldGrid.set_clearing_state(cell_coords, new_stage)

		# Emit signal for terrain regeneration
		if BattleSignals:
			BattleSignals.clearing_complete.emit(null, new_stage)


## =============================================================================
## MESH MODIFICATION
## =============================================================================

## Modify heightmap within a clearing zone
static func modify_heights_for_clearing(
	heights: PackedFloat32Array,
	zone: ClearingZone,
	cell_position: Vector3
) -> PackedFloat32Array:
	var modified: PackedFloat32Array = heights.duplicate()
	var stage_data: Dictionary = CLEARING_STAGES.get(zone.clearing_stage, CLEARING_STAGES[0])
	var flattening: float = stage_data.get("height_flattening", 0.0)

	if flattening <= 0.0:
		return modified

	var step: float = VietnamTerrain.CELL_SIZE / (VietnamTerrain.GRID_SIZE - 1)
	var half_size: float = VietnamTerrain.CELL_SIZE * 0.5

	# Calculate target height (average of affected area)
	var target_height: float = _calculate_target_height(heights, zone, cell_position)

	for z in range(VietnamTerrain.GRID_SIZE):
		for x in range(VietnamTerrain.GRID_SIZE):
			var local_x: float = x * step - half_size
			var local_z: float = z * step - half_size
			var world_pos := Vector3(
				cell_position.x + local_x,
				0.0,
				cell_position.z + local_z
			)

			# Check if point is in zone
			var in_zone: bool = false
			var zone_factor: float = 0.0

			if zone.radius > 0.0:
				# Circular zone
				var distance: float = Vector2(world_pos.x, world_pos.z).distance_to(
					Vector2(zone.center.x, zone.center.z)
				)
				if distance < zone.radius:
					in_zone = true
					# Smooth falloff at edges
					zone_factor = 1.0 - smoothstep(zone.radius * 0.7, zone.radius, distance)
			else:
				# Rectangular zone
				var rect_pos := Vector2(world_pos.x, world_pos.z)
				if zone.rect.has_point(rect_pos):
					in_zone = true
					# Calculate edge distance for falloff
					var edge_dist: float = _distance_to_rect_edge(rect_pos, zone.rect)
					zone_factor = clampf(edge_dist / 10.0, 0.0, 1.0)

			if in_zone:
				var idx: int = z * VietnamTerrain.GRID_SIZE + x
				var original_height: float = heights[idx]
				var blend_factor: float = flattening * zone_factor
				modified[idx] = lerpf(original_height, target_height, blend_factor)

	return modified


static func _calculate_target_height(
	heights: PackedFloat32Array,
	zone: ClearingZone,
	cell_position: Vector3
) -> float:
	var total: float = 0.0
	var count: int = 0
	var step: float = VietnamTerrain.CELL_SIZE / (VietnamTerrain.GRID_SIZE - 1)
	var half_size: float = VietnamTerrain.CELL_SIZE * 0.5

	for z in range(VietnamTerrain.GRID_SIZE):
		for x in range(VietnamTerrain.GRID_SIZE):
			var local_x: float = x * step - half_size
			var local_z: float = z * step - half_size
			var world_pos := Vector2(
				cell_position.x + local_x,
				cell_position.z + local_z
			)

			var in_zone: bool = false
			if zone.radius > 0.0:
				var distance: float = world_pos.distance_to(Vector2(zone.center.x, zone.center.z))
				in_zone = distance < zone.radius
			else:
				in_zone = zone.rect.has_point(world_pos)

			if in_zone:
				total += heights[z * VietnamTerrain.GRID_SIZE + x]
				count += 1

	return total / maxf(float(count), 1.0)


static func _distance_to_rect_edge(point: Vector2, rect: Rect2) -> float:
	var dx: float = minf(point.x - rect.position.x, rect.position.x + rect.size.x - point.x)
	var dy: float = minf(point.y - rect.position.y, rect.position.y + rect.size.y - point.y)
	return minf(dx, dy)


## =============================================================================
## VEGETATION REMOVAL
## =============================================================================

## Get vegetation multiplier for a position
static func get_vegetation_multiplier(world_pos: Vector3) -> float:
	var min_multiplier: float = 1.0

	for zone in _clearing_zones.values():
		if _is_in_zone(world_pos, zone):
			var stage_data: Dictionary = CLEARING_STAGES.get(zone.clearing_stage, CLEARING_STAGES[0])
			var mult: float = stage_data.get("vegetation_multiplier", 1.0)
			min_multiplier = minf(min_multiplier, mult)

	return min_multiplier


static func _is_in_zone(world_pos: Vector3, zone: ClearingZone) -> bool:
	if zone.radius > 0.0:
		var distance: float = Vector2(world_pos.x, world_pos.z).distance_to(
			Vector2(zone.center.x, zone.center.z)
		)
		return distance < zone.radius
	else:
		return zone.rect.has_point(Vector2(world_pos.x, world_pos.z))


## Get ground color for a position (for material blending)
static func get_ground_color(world_pos: Vector3) -> Color:
	var base_color: Color = CLEARING_STAGES[0]["ground_color"]

	for zone in _clearing_zones.values():
		if _is_in_zone(world_pos, zone):
			var stage_data: Dictionary = CLEARING_STAGES.get(zone.clearing_stage, CLEARING_STAGES[0])
			return stage_data.get("ground_color", base_color)

	return base_color


## =============================================================================
## VISUAL EFFECTS
## =============================================================================

## Create falling tree effect at position
static func create_tree_fall_effect(position: Vector3, direction: Vector3) -> Node3D:
	# This would create a visual effect of a tree falling
	# For now, return empty node - implement with actual model/animation
	var effect := Node3D.new()
	effect.name = "TreeFallEffect"
	effect.position = position

	# Add timer to auto-remove
	var timer := Timer.new()
	timer.wait_time = 3.0
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(effect.queue_free)
	effect.add_child(timer)

	return effect


## Create dust cloud effect for bulldozer work
static func create_dust_effect(position: Vector3, radius: float) -> Node3D:
	var effect := Node3D.new()
	effect.name = "DustEffect"
	effect.position = position

	# Simple particle representation
	var particles := GPUParticles3D.new()
	particles.name = "DustParticles"

	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0, 1, 0)
	material.spread = 45.0
	material.initial_velocity_min = 1.0
	material.initial_velocity_max = 3.0
	material.gravity = Vector3(0, -2, 0)
	material.scale_min = 0.5
	material.scale_max = 1.5
	material.color = Color(0.6, 0.5, 0.4, 0.5)

	particles.process_material = material
	particles.amount = 50
	particles.lifetime = 2.0
	particles.explosiveness = 0.3
	particles.emitting = true

	# Simple quad mesh for particles
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	particles.draw_pass_1 = quad

	effect.add_child(particles)

	# Auto-remove
	var timer := Timer.new()
	timer.wait_time = 3.0
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(effect.queue_free)
	effect.add_child(timer)

	return effect


## =============================================================================
## QUERY API
## =============================================================================

## Get clearing zone by ID
static func get_zone(zone_id: String) -> ClearingZone:
	return _clearing_zones.get(zone_id, null)


## Get all zones affecting a cell
static func get_zones_at_cell(coords: Vector2i) -> Array[ClearingZone]:
	var result: Array[ClearingZone] = []
	var zone_ids: Array = _affected_cells.get(coords, [])

	for zone_id in zone_ids:
		if _clearing_zones.has(zone_id):
			result.append(_clearing_zones[zone_id])

	return result


## Get clearing stage at world position
static func get_clearing_stage_at(world_pos: Vector3) -> int:
	var highest_stage: int = 0

	for zone in _clearing_zones.values():
		if _is_in_zone(world_pos, zone):
			highest_stage = maxi(highest_stage, zone.clearing_stage)

	return highest_stage


## Check if position is cleared enough for building
static func is_buildable(world_pos: Vector3) -> bool:
	return get_clearing_stage_at(world_pos) >= 2  # CLEARED or higher


## Get all active clearing zones
static func get_all_zones() -> Array[ClearingZone]:
	var result: Array[ClearingZone] = []
	for zone in _clearing_zones.values():
		result.append(zone)
	return result


## Remove a zone
static func remove_zone(zone_id: String) -> void:
	if _clearing_zones.has(zone_id):
		var zone: ClearingZone = _clearing_zones[zone_id]

		# Remove from affected cells
		for cell_coords in _affected_cells.keys():
			_affected_cells[cell_coords].erase(zone_id)

		_clearing_zones.erase(zone_id)


## Clear all zones
static func clear() -> void:
	_clearing_zones.clear()
	_affected_cells.clear()
