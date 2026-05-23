extends Node
## TerrainIntegration - Autoload singleton bridging the firebase system with TerrainEngine
## Note: No class_name since this is registered as an autoload
## Initializes and wires up TerrainManager, VegetationManager, and BillboardVegetation
## Connects to ClearingSystem and DamageSystem signals and forwards to BattleSignals
##
## Uses TerrainGrid as the SINGLE SOURCE OF TRUTH for all terrain queries

# Preload terrain system classes
const TerrainManagerClass := preload("res://terrain/core/terrain_manager.gd")
const VegetationManagerClass := preload("res://terrain/vegetation/vegetation_manager.gd")
const BillboardVegetationClass := preload("res://terrain/vegetation/billboard_vegetation.gd")
const ClearingSystemClass := preload("res://terrain/systems/clearing_system.gd")
const DamageSystemClass := preload("res://terrain/systems/damage_system.gd")
const TerrainGridClass := preload("res://terrain/core/terrain_grid.gd")
const TerrainTypesConst := preload("res://terrain/terrain_types.gd")
const GridCoordsClass := preload("res://terrain/core/grid_coords.gd")
const UnifiedTerrainEngineClass := preload("res://terrain/core/unified_terrain_engine.gd")

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
var terrain_grid: RefCounted  # TerrainGrid - SINGLE SOURCE OF TRUTH for terrain queries
var unified_terrain: Node  # UnifiedTerrainEngine (new system - provides proper Y values)

# State
var _is_initialized: bool = false
var _camera: Camera3D


func _ready() -> void:
	# Try to get UnifiedTerrainEngine autoload
	unified_terrain = get_node_or_null("/root/UnifiedTerrain")
	if unified_terrain:
		print("[TerrainIntegration] UnifiedTerrain autoload found - will use for height queries")

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

	# Create unified TerrainGrid - SINGLE SOURCE OF TRUTH
	terrain_grid = TerrainGridClass.new(terrain_manager.map_size)

	# Initialize GridCoords canonical coordinate system
	GridCoordsClass.init(terrain_manager.map_size)

	# Wire TerrainGrid to ClearingSystem for direct writes
	if clearing_system.has_method("set_terrain_grid"):
		clearing_system.set_terrain_grid(terrain_grid)

	# Wire TerrainGrid to VegetationManager for reads
	if vegetation_manager.has_method("set_terrain_grid"):
		vegetation_manager.set_terrain_grid(terrain_grid)

	# Wire TerrainGrid to BillboardVegetation for clearing stage checks
	if billboard_vegetation.has_method("set_terrain_grid"):
		billboard_vegetation.set_terrain_grid(terrain_grid)

	print("[TerrainIntegration] Terrain subsystems wired up with unified TerrainGrid")


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

	# TerrainGrid signals (unified terrain data updates)
	if terrain_grid:
		terrain_grid.cell_updated.connect(_on_terrain_grid_updated)

	# UnifiedTerrainEngine signals (new system)
	if unified_terrain:
		if unified_terrain.has_signal("terrain_modified"):
			unified_terrain.terrain_modified.connect(_on_unified_terrain_modified)
		if unified_terrain.has_signal("vegetation_changed"):
			unified_terrain.vegetation_changed.connect(_on_vegetation_updated)

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

	# Build TerrainGrid from heightmap data
	if terrain_grid and terrain_manager.heightmap:
		terrain_grid.build_from_heightmap(terrain_manager.heightmap)

	# Initialize UnifiedTerrainEngine with heightmap (for proper Y values)
	if unified_terrain and unified_terrain.has_method("init_from_heightmap"):
		unified_terrain.init_from_heightmap(terrain_manager.heightmap)
		print("[TerrainIntegration] UnifiedTerrain initialized with heightmap")

	_is_initialized = true
	print("[TerrainIntegration] Terrain initialized with camera: %s" % camera.name)


## Reinitialize terrain system with a different terrain manager
## Used by test scenes that create local terrain instances instead of using global terrain
## @param new_terrain_manager: The terrain manager to use (must have heightmap generated)
## @param new_map_size: Map size in meters (-1 to use terrain_manager.map_size)
func reinit_with_terrain(new_terrain_manager: Node3D, new_map_size: float = -1) -> void:
	# Disable old terrain manager if different
	if terrain_manager and terrain_manager != new_terrain_manager and is_instance_valid(terrain_manager):
		terrain_manager.visible = false
		terrain_manager.set_process(false)

	# Set new terrain manager
	terrain_manager = new_terrain_manager

	# Determine effective map size
	var effective_size: float = new_map_size if new_map_size > 0 else terrain_manager.map_size

	# Reinitialize GridCoords canonical coordinate system
	GridCoordsClass.init(effective_size)

	# Create new TerrainGrid (single source of truth for RTS queries)
	terrain_grid = TerrainGridClass.new(effective_size)

	# Build terrain grid from heightmap
	if terrain_grid and terrain_manager.heightmap:
		terrain_grid.build_from_heightmap(terrain_manager.heightmap)

	# Wire terrain_grid to subsystems
	if clearing_system and clearing_system.has_method("set_terrain_grid"):
		clearing_system.set_terrain_grid(terrain_grid)
	if vegetation_manager and vegetation_manager.has_method("set_terrain_grid"):
		vegetation_manager.set_terrain_grid(terrain_grid)
	if billboard_vegetation and billboard_vegetation.has_method("set_terrain_grid"):
		billboard_vegetation.set_terrain_grid(terrain_grid)

	# Initialize UnifiedTerrainEngine with heightmap (for proper Y values)
	if unified_terrain and unified_terrain.has_method("init_from_heightmap") and terrain_manager.heightmap:
		unified_terrain.init_from_heightmap(terrain_manager.heightmap)
		print("[TerrainIntegration] UnifiedTerrain reinitialized with heightmap")

	# Mark as fully initialized
	_is_initialized = true

	print("[TerrainIntegration] Reinitialized with %s (%.0fm map)" % [
		terrain_manager.name, effective_size
	])


## Get terrain height at world position (O(1) bilinear interpolation)
## Primary API for unit movement - does NOT use physics
## Prioritizes UnifiedTerrain, falls back to terrain_manager
## Note: Works even before init_terrain() if terrain_manager has a heightmap
func get_height_at(world_pos: Vector3) -> float:
	# Prioritize UnifiedTerrain for proper Y values
	if unified_terrain and unified_terrain.has_method("get_height_at"):
		return unified_terrain.get_height_at(world_pos)
	# Fallback to terrain_manager
	if terrain_manager and terrain_manager.has_method("get_height_at"):
		return terrain_manager.get_height_at(world_pos)
	return 0.0


## Get terrain normal at world position
## Prioritizes UnifiedTerrain, falls back to terrain_manager
## Note: Works even before init_terrain() if terrain_manager has a heightmap
func get_normal_at(world_pos: Vector3) -> Vector3:
	# Prioritize UnifiedTerrain for proper normals
	if unified_terrain and unified_terrain.has_method("get_normal_at"):
		return unified_terrain.get_normal_at(world_pos)
	# Fallback to terrain_manager
	if terrain_manager and terrain_manager.has_method("get_normal_at"):
		return terrain_manager.get_normal_at(world_pos)
	return Vector3.UP


## Get movement cost multiplier at world position (based on terrain type)
## Returns: 1.0 = full speed, 0.3 = heavy jungle (30% speed), etc.
## Uses TerrainGrid as the single source of truth for RTS queries
func get_movement_cost(world_pos: Vector3) -> float:
	if not _is_initialized:
		return 1.0

	# Use TerrainGrid for movement cost (includes slope penalty)
	if terrain_grid:
		return terrain_grid.get_movement_cost(world_pos)

	return 1.0


## Get movement speed multiplier at world position
## Returns: 1.0 = full speed, lower = slower
func get_movement_speed(world_pos: Vector3) -> float:
	if not _is_initialized:
		return 1.0

	if terrain_grid:
		return terrain_grid.get_movement_speed(world_pos)

	return 1.0


## Get cover value at world position (0.0-1.0)
## Returns damage reduction factor (0 = no cover, 1 = full cover)
func get_cover_at(world_pos: Vector3) -> float:
	if not _is_initialized or not terrain_grid:
		return 0.0
	return terrain_grid.get_cover(world_pos)


## Get slope at world position (0=flat, 1=cliff)
func get_slope_at(world_pos: Vector3) -> float:
	if not _is_initialized or not terrain_grid:
		return 0.0
	return terrain_grid.get_slope(world_pos)


## Check if position is passable by ground units
func is_passable(world_pos: Vector3) -> bool:
	if not _is_initialized or not terrain_grid:
		return true
	return terrain_grid.is_passable(world_pos)


## Check if position is buildable
func is_buildable(world_pos: Vector3) -> bool:
	if not _is_initialized or not terrain_grid:
		return false
	return terrain_grid.is_buildable(world_pos)


## Check line of sight between two positions
func has_line_of_sight(from_pos: Vector3, to_pos: Vector3) -> bool:
	if not _is_initialized or not terrain_grid:
		return true
	return terrain_grid.has_line_of_sight(from_pos, to_pos)


## Get elevation advantage (height difference for combat)
func get_elevation_advantage(attacker_pos: Vector3, target_pos: Vector3) -> float:
	if not _is_initialized or not terrain_grid:
		return 0.0
	return terrain_grid.get_elevation_advantage(attacker_pos, target_pos)


## Check if position blocks line of sight (dense vegetation or cliffs)
## Uses TerrainGrid for consistent terrain data
func blocks_los(world_pos: Vector3) -> bool:
	if not _is_initialized:
		return false

	if terrain_grid:
		return terrain_grid.blocks_los(world_pos)

	return false


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
	if not _is_initialized or not terrain_grid:
		return false
	return terrain_grid.is_position_cleared(world_pos)


## Get vegetation density at world position (0.0-1.0, 0=cleared, 1=full jungle)
func get_vegetation_density(world_pos: Vector3) -> float:
	if not _is_initialized or not terrain_grid:
		return 1.0
	return terrain_grid.get_vegetation_density(world_pos)


## Get terrain type at world position
## Returns: TerrainTypes.Type enum value
func get_terrain_type_at(world_pos: Vector3) -> int:
	if not _is_initialized or not terrain_grid:
		return 0  # CLEAR
	return terrain_grid.get_terrain_type(world_pos)


## Get clearing stage at world position
## Returns: ClearingState.Stage enum value
func get_clearing_stage_at(world_pos: Vector3) -> int:
	if not _is_initialized or not terrain_grid:
		return 0  # JUNGLE
	return terrain_grid.get_clearing_stage(world_pos)


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

	# Convert region to world coordinates
	# The region is in TerrainGrid cell coordinates
	var cell_size: float = TerrainGridClass.CELL_SIZE

	var world_min := Vector2(
		region.position.x * cell_size,
		region.position.y * cell_size
	)
	var world_max := Vector2(
		(region.position.x + region.size.x) * cell_size,
		(region.position.y + region.size.y) * cell_size
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
			# Regenerate vegetation for this chunk
			if vegetation_manager:
				vegetation_manager.regenerate_chunk(coord, terrain_manager.heightmap)
			if billboard_vegetation and vegetation_manager._chunk_terrain.has(coord):
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


func _on_terrain_grid_updated(region: Rect2i) -> void:
	# TerrainGrid data updated - trigger vegetation update
	_on_vegetation_updated(region)


func _on_unified_terrain_modified(region: Rect2i) -> void:
	# UnifiedTerrainEngine terrain was modified - sync with legacy TerrainGrid
	if terrain_grid and terrain_grid.has_method("update_region_from_heightmap"):
		terrain_grid.update_region_from_heightmap(region)

	# Rebuild visual mesh chunks in TerrainManager
	# Convert gameplay region to heightmap cell region for chunk rebuilding
	if terrain_manager and terrain_manager.has_method("_rebuild_chunks_in_region"):
		# Region is in gameplay coords (4m cells), convert to heightmap coords (2m cells)
		var heightmap_region := Rect2i(
			region.position * 2,
			region.size * 2
		)
		terrain_manager._rebuild_chunks_in_region(heightmap_region)

	# Also trigger vegetation update
	_on_vegetation_updated(region)


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
		if not is_buildable(point):
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
	if not _is_initialized:
		return 0

	# Use TerrainGrid to mark area as cleared
	if terrain_grid:
		terrain_grid.mark_area_cleared(center, radius)

	# VegetationManager will automatically re-materialize based on TerrainGrid
	if vegetation_manager:
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

	return 0
