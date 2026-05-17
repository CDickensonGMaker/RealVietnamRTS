extends Node
## TerrainIntegration - Autoload singleton bridging the firebase system with TerrainEngine
## Note: No class_name since this is registered as an autoload
## Initializes and wires up TerrainManager, VegetationManager, and BillboardVegetation
## Connects to ClearingSystem and DamageSystem signals and forwards to BattleSignals

# Preload terrain system classes
const TerrainManagerClass := preload("res://terrain/core/terrain_manager.gd")
const VegetationManagerClass := preload("res://terrain/vegetation/vegetation_manager.gd")
const BillboardVegetationClass := preload("res://terrain/vegetation/billboard_vegetation.gd")
const ClearingSystemClass := preload("res://terrain/systems/clearing_system.gd")
const DamageSystemClass := preload("res://terrain/systems/damage_system.gd")

# Re-export damage types for external use
enum DamageType {
	SMALL_EXPLOSION = 0,
	MEDIUM_EXPLOSION = 1,
	LARGE_EXPLOSION = 2,
	NAPALM = 3,
	BUNKER_COLLAPSE = 4,
}

# Internal signals (forwarded to BattleSignals)
signal terrain_ready
signal terrain_cleared(position: Vector3, radius: float)
signal terrain_damaged(position: Vector3, damage_type: int, radius: float)

# System instances
var terrain_manager: Node3D
var vegetation_manager: Node3D
var billboard_vegetation: Node3D
var clearing_system: Node
var damage_system: Node

# State
var _is_initialized: bool = false
var _camera: Camera3D


func _ready() -> void:
	# Create terrain system instances
	_create_terrain_systems()

	# Wire up signal connections
	_connect_signals()

	print("[TerrainIntegration] Ready - call init_terrain(camera) to initialize")


## Create terrain subsystem instances and wire up autoloads
func _create_terrain_systems() -> void:
	# Create TerrainManager (local instance)
	terrain_manager = TerrainManagerClass.new()
	terrain_manager.name = "TerrainManager"
	add_child(terrain_manager)

	# Create VegetationManager (local instance)
	vegetation_manager = VegetationManagerClass.new()
	vegetation_manager.name = "VegetationManager"
	add_child(vegetation_manager)

	# Create BillboardVegetation (local instance)
	billboard_vegetation = BillboardVegetationClass.new()
	billboard_vegetation.name = "BillboardVegetation"
	add_child(billboard_vegetation)

	# Use global autoloads for ClearingSystem and DamageSystem
	clearing_system = get_node_or_null("/root/ClearingSystem")
	if not clearing_system:
		push_warning("[TerrainIntegration] ClearingSystem autoload not found - creating local instance")
		clearing_system = ClearingSystemClass.new()
		clearing_system.name = "ClearingSystemLocal"
		add_child(clearing_system)

	damage_system = get_node_or_null("/root/DamageSystem")
	if not damage_system:
		push_warning("[TerrainIntegration] DamageSystem autoload not found - creating local instance")
		damage_system = DamageSystemClass.new()
		damage_system.name = "DamageSystemLocal"
		add_child(damage_system)

	# Wire up internal references
	terrain_manager.vegetation_manager = vegetation_manager
	if clearing_system.has_method("set_terrain_manager"):
		clearing_system.set_terrain_manager(terrain_manager)
	if clearing_system.has_method("set_vegetation_manager"):
		clearing_system.set_vegetation_manager(vegetation_manager)
	if damage_system.has_method("set_terrain_manager"):
		damage_system.set_terrain_manager(terrain_manager)
	if damage_system.has_method("set_vegetation_manager"):
		damage_system.set_vegetation_manager(vegetation_manager)
	if damage_system.has_method("set_billboard_vegetation"):
		damage_system.set_billboard_vegetation(billboard_vegetation)

	# Billboard vegetation references
	billboard_vegetation.set_terrain_manager(terrain_manager)
	billboard_vegetation.set_vegetation_manager(vegetation_manager)
	billboard_vegetation.set_chunk_size(terrain_manager.chunk_size)

	# Vegetation manager chunk size
	vegetation_manager.set_chunk_size(terrain_manager.chunk_size)

	print("[TerrainIntegration] Terrain subsystems wired up (using autoloads for ClearingSystem/DamageSystem)")


## Connect ClearingSystem and DamageSystem signals to forward to BattleSignals
func _connect_signals() -> void:
	# ClearingSystem signals
	clearing_system.clearing_started.connect(_on_clearing_started)
	clearing_system.clearing_completed.connect(_on_clearing_completed)
	clearing_system.vegetation_updated.connect(_on_vegetation_updated)

	# DamageSystem signals
	damage_system.damage_applied.connect(_on_damage_applied)
	damage_system.terrain_scarred.connect(_on_terrain_scarred)

	# TerrainManager signals
	terrain_manager.terrain_ready.connect(_on_terrain_ready)
	terrain_manager.chunk_loaded.connect(_on_chunk_loaded)

	print("[TerrainIntegration] Signal connections established")


# =============================================================================
# PUBLIC API - RTS Game Interface
# =============================================================================

## Initialize terrain system with camera reference
## Call this after scene setup, before gameplay begins
func init_terrain(camera: Camera3D, seed_value: int = -1) -> void:
	if _is_initialized:
		push_warning("[TerrainIntegration] Already initialized")
		return

	if not camera:
		push_error("[TerrainIntegration] Camera required for initialization")
		return

	_camera = camera

	# Set camera references
	terrain_manager.set_camera(camera)
	vegetation_manager.set_camera(camera)
	billboard_vegetation.set_camera(camera)

	# Generate terrain
	terrain_manager.generate_terrain(seed_value)

	_is_initialized = true
	print("[TerrainIntegration] Terrain initialized with camera: %s" % camera.name)


## Get terrain height at world position (O(1) bilinear interpolation)
## Primary API for unit movement - does NOT use physics
func get_height_at(world_pos: Vector3) -> float:
	if not _is_initialized or not terrain_manager:
		return 0.0
	return terrain_manager.get_height_at(world_pos)


## Get terrain normal at world position
func get_normal_at(world_pos: Vector3) -> Vector3:
	if not _is_initialized or not terrain_manager:
		return Vector3.UP
	return terrain_manager.get_normal_at(world_pos)


## Get movement cost multiplier at world position (based on vegetation density)
## Returns: 1.0 = full speed, 0.3 = heavy jungle (30% speed), etc.
func get_movement_cost(world_pos: Vector3) -> float:
	if not _is_initialized or not vegetation_manager:
		return 1.0

	# VegetationManager.get_movement_multiplier_at returns speed multiplier
	# We return this directly as movement cost is inverted in the RTS context
	var multiplier: float = vegetation_manager.get_movement_multiplier_at(
		world_pos,
		terrain_manager.chunk_size
	)
	return multiplier


## Check if position blocks line of sight (dense vegetation)
func blocks_los(world_pos: Vector3) -> bool:
	if not _is_initialized or not vegetation_manager:
		return false
	return vegetation_manager.blocks_los(world_pos, terrain_manager.chunk_size)


## Apply damage at world position - wrapper for DamageSystem
## damage_type: DamageType enum (SMALL_EXPLOSION, MEDIUM_EXPLOSION, etc.)
## intensity: 0.0-1.0 scale factor for damage
func apply_damage_at(world_pos: Vector3, damage_type: int, intensity: float = 1.0) -> void:
	if not _is_initialized or not damage_system:
		push_warning("[TerrainIntegration] Cannot apply damage - not initialized")
		return

	# Convert our enum to DamageSystem's enum
	var ds_type: int = clampi(damage_type, 0, 4)
	damage_system.apply_damage(world_pos, ds_type, intensity)


## Apply area bombardment (multiple craters)
func apply_bombardment(center: Vector3, radius: float, count: int, damage_type: int) -> void:
	if not _is_initialized or not damage_system:
		return

	var ds_type: int = clampi(damage_type, 0, 4)
	damage_system.apply_bombardment(center, radius, count, ds_type)


## Start clearing a zone for construction - wrapper for ClearingSystem
## Returns: zone_id for tracking progress
func start_clearing_zone(center: Vector3, radius: float, shape: String = "circle", rect_size: Vector2 = Vector2.ZERO) -> int:
	if not _is_initialized or not clearing_system:
		push_warning("[TerrainIntegration] Cannot start clearing - not initialized")
		return -1

	return clearing_system.create_zone(center, radius, shape, rect_size)


## Advance clearing progress for a zone
## amount: 0.0-1.0 progress per stage
func advance_clearing(zone_id: int, amount: float) -> void:
	if not _is_initialized or not clearing_system:
		return
	clearing_system.advance_clearing(zone_id, amount)


## Set clearing zone directly to a stage (for testing/scripting)
## stage: 0=JUNGLE, 1=PARTIALLY_CLEARED, 2=CLEARED, 3=FORTIFIED
func set_clearing_stage(zone_id: int, stage: int) -> void:
	if not _is_initialized or not clearing_system:
		return
	clearing_system.set_zone_stage(zone_id, stage)


## Check if a position has been cleared (CLEARED or FORTIFIED stage)
func is_position_cleared(world_pos: Vector3) -> bool:
	if not _is_initialized or not clearing_system:
		return false

	# Check vegetation density - cleared areas have density < 0.1
	var density: float = clearing_system.get_vegetation_density(world_pos)
	return density < 0.1


## Get vegetation density at world position (0.0-1.0, 0=cleared, 1=full jungle)
func get_vegetation_density(world_pos: Vector3) -> float:
	if not _is_initialized or not clearing_system:
		return 1.0
	return clearing_system.get_vegetation_density(world_pos)


## Get terrain type at world position
## Returns: VegetationManager.TerrainType enum value
func get_terrain_type_at(world_pos: Vector3) -> int:
	if not _is_initialized or not vegetation_manager:
		return 0  # CLEAR
	return vegetation_manager.get_terrain_type_at(world_pos, terrain_manager.chunk_size)


## Check if position is near water (rivers)
func is_near_water(world_pos: Vector3) -> bool:
	if not _is_initialized or not terrain_manager:
		return false
	return terrain_manager.is_near_water(world_pos.x, world_pos.z)


## Get playable world bounds
func get_playable_bounds() -> Rect2:
	if not _is_initialized or not terrain_manager:
		return Rect2(Vector2.ZERO, Vector2(3000, 3000))
	return terrain_manager.get_playable_bounds()


## Get map size in meters
func get_map_size() -> float:
	if not terrain_manager:
		return 3000.0
	return terrain_manager.map_size


## Get chunk size in meters
func get_chunk_size() -> float:
	if not terrain_manager:
		return 256.0
	return terrain_manager.chunk_size


## Check if terrain system is ready
func is_ready() -> bool:
	return _is_initialized and terrain_manager and terrain_manager.is_ready


## Force load all terrain chunks (for small maps or loading screens)
func load_all_chunks() -> void:
	if terrain_manager:
		terrain_manager.load_all_chunks()


## Get total damage zone count
func get_damage_count() -> int:
	if not damage_system:
		return 0
	return damage_system.get_damage_count()


## Clear all damage (reset terrain)
func clear_all_damage() -> void:
	if damage_system:
		damage_system.clear_all_damage()


## Clear all clearing zones (reset construction areas)
func clear_all_zones() -> void:
	if clearing_system:
		clearing_system.clear_all_zones()


# =============================================================================
# SIGNAL HANDLERS - Forward to BattleSignals
# =============================================================================

func _on_clearing_started(zone_id: int, position: Vector3) -> void:
	print("[TerrainIntegration] Clearing started: zone %d at %s" % [zone_id, position])


func _on_clearing_completed(zone_id: int) -> void:
	if not clearing_system.zones.has(zone_id):
		return

	var zone = clearing_system.zones[zone_id]
	var position: Vector3 = zone.center
	var radius: float = zone.radius

	# Emit local signal
	terrain_cleared.emit(position, radius)

	# Forward to BattleSignals if available
	var battle_signals := get_node_or_null("/root/BattleSignals")
	if battle_signals and battle_signals.has_signal("terrain_cleared"):
		battle_signals.terrain_cleared.emit(position, radius)

	print("[TerrainIntegration] Clearing completed: zone %d at %s (r=%.1f)" % [zone_id, position, radius])


func _on_vegetation_updated(region: Rect2i) -> void:
	# Regenerate billboards for affected chunks
	if not terrain_manager or not billboard_vegetation:
		return

	var chunk_size: float = terrain_manager.chunk_size
	var _cell_size: float = terrain_manager.cell_size  # Reserved for precise positioning
	var veg_scale: float = float(clearing_system.vegetation_size) / terrain_manager.map_size

	# Convert vegetation texture region to chunk coordinates
	var world_min := Vector2(
		region.position.x / veg_scale,
		region.position.y / veg_scale
	)
	var world_max := Vector2(
		(region.position.x + region.size.x) / veg_scale,
		(region.position.y + region.size.y) / veg_scale
	)

	var chunk_min := Vector2i(
		int(floor(world_min.x / chunk_size)),
		int(floor(world_min.y / chunk_size))
	)
	var chunk_max := Vector2i(
		int(ceil(world_max.x / chunk_size)),
		int(ceil(world_max.y / chunk_size))
	)

	# Regenerate billboards for affected chunks
	for cz in range(chunk_min.y, chunk_max.y + 1):
		for cx in range(chunk_min.x, chunk_max.x + 1):
			var coord := Vector2i(cx, cz)
			if vegetation_manager._chunk_terrain.has(coord):
				billboard_vegetation.generate_for_chunk(
					coord,
					terrain_manager.heightmap,
					vegetation_manager._chunk_terrain[coord]
				)


func _on_damage_applied(position: Vector3, type: int, radius: float) -> void:
	# Emit local signal
	terrain_damaged.emit(position, type, radius)

	# Forward to BattleSignals if available
	var battle_signals := get_node_or_null("/root/BattleSignals")
	if battle_signals and battle_signals.has_signal("projectile_impact"):
		battle_signals.projectile_impact.emit(position, type)

	print("[TerrainIntegration] Damage applied: type %d at %s (r=%.1f)" % [type, position, radius])


func _on_terrain_scarred(_region: Rect2i) -> void:
	# Could trigger visual updates or notify other systems
	pass


func _on_terrain_ready() -> void:
	terrain_ready.emit()
	print("[TerrainIntegration] Terrain generation complete")


func _on_chunk_loaded(coord: Vector2i, _is_playable: bool) -> void:
	# Generate billboards for newly loaded chunks
	if not vegetation_manager._chunk_terrain.has(coord):
		return

	billboard_vegetation.generate_for_chunk(
		coord,
		terrain_manager.heightmap,
		vegetation_manager._chunk_terrain[coord]
	)


# =============================================================================
# CONVENIENCE METHODS FOR FIREBASE SYSTEM
# =============================================================================

## Check if a rectangular area can be built on (sufficiently cleared)
func can_build_at(center: Vector3, size: Vector2) -> bool:
	# Check corners and center
	var half_size := size * 0.5
	var check_points: Array[Vector3] = [
		center,
		center + Vector3(-half_size.x, 0, -half_size.y),
		center + Vector3(half_size.x, 0, -half_size.y),
		center + Vector3(-half_size.x, 0, half_size.y),
		center + Vector3(half_size.x, 0, half_size.y),
	]

	for point in check_points:
		if not is_position_cleared(point):
			return false

	return true


## Get average terrain height for a building footprint
func get_average_height(center: Vector3, size: Vector2) -> float:
	var half_size := size * 0.5
	var sample_points: Array[Vector3] = [
		center,
		center + Vector3(-half_size.x, 0, -half_size.y),
		center + Vector3(half_size.x, 0, -half_size.y),
		center + Vector3(-half_size.x, 0, half_size.y),
		center + Vector3(half_size.x, 0, half_size.y),
	]

	var total: float = 0.0
	for point in sample_points:
		total += get_height_at(point)

	return total / float(sample_points.size())


## Flatten terrain for building placement (creates a FORTIFIED clearing zone)
func prepare_building_site(center: Vector3, size: Vector2) -> int:
	var radius: float = maxf(size.x, size.y) * 0.6
	var zone_id: int = start_clearing_zone(center, radius, "rectangle", size)

	# Immediately advance to FORTIFIED for building placement
	if zone_id >= 0:
		set_clearing_stage(zone_id, 3)  # FORTIFIED

	return zone_id


## Clear vegetation around a building position
## Used automatically when buildings are placed to ensure visibility
## radius: clearing radius in meters (default 5m per game design - no trees within 5m of buildings)
func clear_vegetation_around_building(center: Vector3, radius: float = 5.0) -> int:
	if not _is_initialized or not vegetation_manager:
		return 0

	# Clear vegetation using VegetationManager
	var cleared: int = vegetation_manager.clear_area(
		center,
		radius,
		terrain_manager.chunk_size,
		terrain_manager.heightmap
	)

	if cleared > 0:
		# Regenerate billboards for affected chunks
		var chunk_min := Vector2i(
			int(floor((center.x - radius) / terrain_manager.chunk_size)),
			int(floor((center.z - radius) / terrain_manager.chunk_size))
		)
		var chunk_max := Vector2i(
			int(ceil((center.x + radius) / terrain_manager.chunk_size)),
			int(ceil((center.z + radius) / terrain_manager.chunk_size))
		)

		for cz in range(chunk_min.y, chunk_max.y + 1):
			for cx in range(chunk_min.x, chunk_max.x + 1):
				var coord := Vector2i(cx, cz)
				if vegetation_manager._chunk_terrain.has(coord):
					billboard_vegetation.generate_for_chunk(
						coord,
						terrain_manager.heightmap,
						vegetation_manager._chunk_terrain[coord]
					)

		print("[TerrainIntegration] Cleared %d vegetation bundles around building at %s (r=%.1f)" % [cleared, center, radius])

	return cleared
