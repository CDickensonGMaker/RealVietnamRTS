extends Node3D
## Battle Scene - Main RTS gameplay scene
##
## Uses production systems:
## - BattleHUD for all UI/input handling
## - PlacementController for building placement
## - SelectionManager for unit selection
## - JobSystem for job creation/management
##
## Input is now handled by BattleHUD (build menu, placement, paint modes)
## This scene only handles setup and debug toggles (G=grid, T=trees, F8=reset)

const TerrainTypes = preload("res://terrain/terrain_types.gd")
const UnifiedJobClass = preload("res://firebase_system/job_system/unified_job.gd")
const GridCoordsClass = preload("res://terrain/core/grid_coords.gd")
const TerrainGridClass = preload("res://terrain/core/terrain_grid.gd")
const TreeNodeClass = preload("res://terrain/vegetation/tree_node.gd")
# BlueprintGhostClass removed - now using PlacementController via BattleHUD

## Mock heightmap for flat terrain
class MockHeightmap:
	var height: float = 0.0

	func sample_world(_x: float, _z: float) -> float:
		return height

	func get_normal_world(_x: float, _z: float) -> Vector3:
		return Vector3.UP

## Command modes are now handled by BattleHUD's CursorModeScript
## This scene only handles test/debug hotkeys (E, Shift+B, F8, etc.)

## State
var camera: Camera3D
var hud: Label
var workers: Array[Node3D] = []
# Ghost and mode state removed - now handled by BattleHUD/PlacementController

## Supply tracking
var current_supply: int = 2000  # Starting supply for full firebase construction

## Note: ground collision is provided by TerrainManager chunks via create_raycast_collision()

## Local terrain for test scene (faster than 3km full terrain)
var local_terrain: TerrainManager  # Local instance with small map
var terrain_intg: Node  # TerrainIntegration autoload (fallback)

## Vegetation systems
var vegetation_manager: VegetationManager
var billboard_vegetation: BillboardVegetation
var mock_heightmap: MockHeightmap
var chunk_size: float = 64.0  # Chunk size for vegetation bundles

## Grid overlay for visualizing clearing bundles
var grid_overlay: MeshInstance3D
var grid_visible := true

## 3D Trees (close-up jungle density models)
var tree_container: Node3D
var tree_nodes: Array[Node3D] = []
var trees_visible := true
const TREE_DENSITY := 0.02  # Trees per square meter in heavy jungle

## Vegetation chunks - cover the larger test area
## For 320m map with 64m chunks, need 5x5 chunk coverage
var VEG_CHUNKS: Array[Vector2i] = []

## Map size for camera bounds - 320m for full firebase complex
var MAP_SIZE := 320.0

## Override billboard count for test scene (scaled for larger map)
const TEST_BILLBOARD_COUNT := 1200  # More vegetation for larger map


func _reset_persistent_state() -> void:
	"""Reset all autoloads that survive scene reloads. This ensures each run
	starts fresh without inheriting jobs, construction sites, clearing zones,
	or tree nodes from the previous run."""

	# 1. JobSystem - clears all jobs and their visual nodes (construction sites, etc.)
	var job_sys := get_node_or_null("/root/JobSystem")
	if job_sys and job_sys.has_method("reset"):
		job_sys.reset()

	# 2. ClearingSystem - clears all clearing zones
	var clearing_sys := get_node_or_null("/root/ClearingSystem")
	if clearing_sys and clearing_sys.has_method("clear_all_zones"):
		clearing_sys.clear_all_zones()

	# 3. TreeNodeManager - clears all tree node tracking
	var tree_mgr := get_node_or_null("/root/TreeNodeManager")
	if tree_mgr and tree_mgr.has_method("clear_all_zones"):
		tree_mgr.clear_all_zones()

	# 4. BattleHUD's PlacementController - cancel any active placement
	var battle_hud: Node = get_node_or_null("/root/BattleHUD")
	if battle_hud:
		var placement: Variant = battle_hud.get("_placement_controller")
		if placement != null and placement is Node and placement.has_method("cancel_placement"):
			placement.cancel_placement()

	# 5. ConstructionManager - clear any tracked constructions
	var construction_mgr := get_node_or_null("/root/ConstructionManager")
	if construction_mgr and construction_mgr.has_method("reset"):
		construction_mgr.reset()

	# 6. TestDaemon - clear commands to prevent re-execution on scene reload
	var test_daemon := get_node_or_null("/root/TestDaemon")
	if test_daemon and test_daemon.has_method("reset"):
		test_daemon.reset()

	# 7. Clean up any orphaned construction sites in the scene tree
	for site in get_tree().get_nodes_in_group("construction_sites"):
		if is_instance_valid(site):
			site.queue_free()

	print("[ClearingTest] Reset all persistent autoload state")


func _ready() -> void:
	print("=== Battle Scene ===")
	print("320m map | All input via BattleHUD")
	print("")

	# Wipe persistent autoload state before generating this run's world.
	_reset_persistent_state()

	# Build VEG_CHUNKS array for 5x5 grid (320m / 64m = 5 chunks per side)
	var chunks_per_side: int = int(ceil(MAP_SIZE / chunk_size))
	for cx in range(chunks_per_side):
		for cz in range(chunks_per_side):
			VEG_CHUNKS.append(Vector2i(cx, cz))
	print("[ClearingTest] Generated %d vegetation chunks (%dx%d)" % [VEG_CHUNKS.size(), chunks_per_side, chunks_per_side])

	# Get TerrainIntegration autoload (we may use its systems if already initialized)
	terrain_intg = get_node_or_null("/root/TerrainIntegration")

	# Disable TerrainIntegration's vegetation to prevent duplicate billboard systems
	if terrain_intg and terrain_intg.has_method("get"):
		var ti_billboard = terrain_intg.get("billboard_vegetation")
		if ti_billboard and ti_billboard is Node3D:
			ti_billboard.visible = false
			ti_billboard.set_process(false)
			print("[ClearingTest] Disabled TerrainIntegration billboard vegetation")

	# Calculate center of map for spawning and camera
	var map_center := MAP_SIZE * 0.5

	# Use TestSceneBase for RTS camera and environment
	# Skip global terrain - we use local terrain for fast iteration
	var setup_result: Dictionary = TestSceneBase.setup_environment(self, {
		"name": "Firebase Construction Test",
		"size": MAP_SIZE,
		"seed": 42,
		"add_camera": true,
		"camera_position": Vector3(map_center, 120, map_center + 80),  # Higher camera for larger 320m map
		"skip_terrain": true,  # We'll create a small local terrain instead
	})
	camera = setup_result.get("camera") as Camera3D

	# Set camera bounds to allow free movement around the terrain
	# Generous bounds: -50 to MAP_SIZE+50 so camera can orbit freely
	if camera and camera.has_method("set_map_bounds"):
		var padding := 100.0  # Extra space outside map for orbiting
		camera.set_map_bounds(
			Vector3(-padding, 0, -padding),
			Vector3(MAP_SIZE + padding, 200, MAP_SIZE + padding)
		)
		print("[ClearingTest] Camera bounds set: -%.0f to %.0f" % [padding, MAP_SIZE + padding])

	# Create local TerrainManager for fast terrain (128m instead of 3km)
	# This generates quickly and gives us real heightmap for testing
	_setup_local_terrain()

	_setup_vegetation()
	_setup_3d_trees()
	# _setup_area_preview() removed - ghosts now handled by PlacementController
	_setup_grid_overlay()

	# Create simple HUD
	hud = TestSceneBase.make_hud(self)

	# SelectionManager is now enabled (used for unit selection in production)

	# Spawn initial workers at center of map (4 engineers + 4 bulldozers for firebase construction)
	# Arrange in two rows: engineers on one side, bulldozers on the other
	for i in range(4):
		var offset_x: float = (i - 1.5) * 4.0  # Spread 4m apart
		_spawn_engineer(Vector3(map_center + offset_x, 0, map_center - 6))
	for i in range(4):
		var offset_x: float = (i - 1.5) * 5.0  # Spread 5m apart (bulldozers are larger)
		_spawn_bulldozer(Vector3(map_center + offset_x, 0, map_center + 6))

	# Connect to JobSystem
	var job_system = get_node_or_null("/root/JobSystem")
	if job_system:
		job_system.job_created.connect(_on_job_created)
		job_system.job_completed.connect(_on_job_completed)
		print("[ClearingTest] Connected to JobSystem")

	# Connect to ClearingSystem for immediate billboard updates
	var clearing_system = get_node_or_null("/root/ClearingSystem")
	if clearing_system and clearing_system.has_signal("vegetation_updated"):
		clearing_system.vegetation_updated.connect(_on_clearing_vegetation_updated)
		print("[ClearingTest] Connected to ClearingSystem.vegetation_updated for billboard clearing")

	# Create initial CLEAR_TERRAIN job in the jungle for workers to test
	# This gives workers something to do immediately without manual input
	_create_initial_clearing_job()

	print("")
	print("=== Battle Scene Ready ===")
	print("Workers: 4 Engineers + 4 Bulldozers | Supply: %d" % current_supply)
	print("")
	print("=== BUILDING PLACEMENT ===")
	print("1. Place TOC first (B menu) - it can be placed anywhere")
	print("2. Other buildings (bunkers, MG nests, etc.) require TOC zone")
	print("3. An initial clearing job was created in the jungle for worker testing")
	print("")
	print("Controls: B=Build menu | G=Grid | T=Trees | F8=Reset")
	print("")


func _exit_tree() -> void:
	# Re-enable TerrainIntegration's vegetation when test scene closes
	if terrain_intg and terrain_intg.has_method("get"):
		var ti_billboard = terrain_intg.get("billboard_vegetation")
		if ti_billboard and ti_billboard is Node3D:
			ti_billboard.visible = true
			ti_billboard.set_process(true)
			print("[ClearingTest] Re-enabled TerrainIntegration billboard vegetation")


## Setup local terrain with small map for fast generation
func _setup_local_terrain() -> void:
	print("[ClearingTest] Creating local terrain (%.0fm map)..." % MAP_SIZE)

	# Configure TerrainEngine for more dynamic terrain BEFORE generating
	var terrain_engine: Node = get_node_or_null("/root/TerrainEngine")
	if terrain_engine:
		print("[DIAG] TerrainEngine BEFORE setup: height_scale=%.1f" % terrain_engine.height_scale)
		# Use ROLLING_HILLS preset - gentler terrain that won't spike on small maps
		terrain_engine.set_preset(terrain_engine.TerrainPreset.ROLLING_HILLS)
		# Conservative settings for 320m map to prevent extreme height spikes
		terrain_engine.set_param("ridge_blend", 0.15)      # Low ridge influence
		terrain_engine.set_param("warp_strength", 15.0)    # Moderate warping
		terrain_engine.set_param("base_frequency", 0.003)  # Lower freq = smoother hills
		print("[DIAG] TerrainEngine AFTER preset: height_scale=%.1f, ridge_blend=%.2f, warp=%.1f" % [
			terrain_engine.height_scale,
			terrain_engine.params.get("ridge_blend", -1),
			terrain_engine.params.get("warp_strength", -1)
		])
		print("[ClearingTest] TerrainEngine configured: ROLLING_HILLS preset (spike-safe)")

	# Create TerrainManager with small map settings
	local_terrain = TerrainManager.new()
	local_terrain.name = "LocalTerrain"
	local_terrain.map_size = MAP_SIZE
	local_terrain.chunk_size = chunk_size  # 64m chunks = 4 chunks for 128m map
	local_terrain.cell_size = 2.0
	local_terrain.height_scale = 30.0  # Moderate hills - prevents spikes on small maps
	local_terrain.rivers_enabled = false  # No rivers for fast generation
	local_terrain.load_distance = 3
	local_terrain.unload_distance = 4
	add_child(local_terrain)
	print("[DIAG] TerrainManager created: height_scale=%.1f, map_size=%.0f, chunk_size=%.0f" % [
		local_terrain.height_scale, local_terrain.map_size, local_terrain.chunk_size
	])

	# Register as terrain manager so TreeNodeManager can find it
	local_terrain.add_to_group("terrain_managers")

	# Set camera for chunk streaming
	local_terrain.set_camera(camera)

	# Generate terrain synchronously (small map = fast)
	local_terrain.generate_terrain(42)

	print("[ClearingTest] Local terrain ready (%.0fm, %d chunks, height 0-%.0fm)" % [
		MAP_SIZE,
		local_terrain.chunks.size(),
		local_terrain.height_scale
	])

	# CRITICAL: Sync local terrain with global systems so JobSystem uses correct heights
	_sync_terrain_with_globals()


## Sync local terrain with global autoloads so jobs/workers use correct coordinates
func _sync_terrain_with_globals() -> void:
	print("[ClearingTest] Syncing local terrain with global systems...")

	if terrain_intg and terrain_intg.has_method("reinit_with_terrain"):
		# Use the clean reinitialization API
		terrain_intg.reinit_with_terrain(local_terrain, MAP_SIZE)

		# Initialize terrain types for testing clearing behavior
		if terrain_intg.terrain_grid:
			_initialize_terrain_grid(terrain_intg.terrain_grid)
	else:
		# Fallback for older versions (manual sync)
		push_warning("[ClearingTest] TerrainIntegration missing reinit_with_terrain - using fallback")
		GridCoordsClass.init(MAP_SIZE)
		if terrain_intg:
			# Hide old terrain
			var ti_terrain = terrain_intg.get("terrain_manager")
			if ti_terrain and ti_terrain is Node3D:
				ti_terrain.visible = false
				ti_terrain.set_process(false)
			terrain_intg.terrain_manager = local_terrain

			# Recreate TerrainGrid
			var new_grid = TerrainGridClass.new(MAP_SIZE)
			terrain_intg.terrain_grid = new_grid
			if local_terrain.heightmap:
				_initialize_terrain_grid(new_grid)


## Initialize terrain grid with natural sporadic jungle for realistic firebase building
## Creates varying density: dense clusters, sparse areas, and natural clearings
func _initialize_terrain_grid(grid) -> void:
	if not grid or not grid.has_method("set_terrain_type"):
		return

	# Use noise for natural vegetation distribution
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.015  # Controls cluster size (lower = larger clusters)
	noise.seed = 42

	# Secondary noise for additional variation
	var detail_noise := FastNoiseLite.new()
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.05  # Higher frequency for fine detail
	detail_noise.seed = 1337

	var cell_size: float = GridCoordsClass.GAMEPLAY_CELL_SIZE
	var cell_count: int = int(ceil(MAP_SIZE / cell_size))

	var terrain_counts: Dictionary = {
		TerrainTypes.Type.CLEAR: 0,
		TerrainTypes.Type.GRASSLAND: 0,
		TerrainTypes.Type.LIGHT_JUNGLE: 0,
		TerrainTypes.Type.MEDIUM_JUNGLE: 0,
		TerrainTypes.Type.HEAVY_JUNGLE: 0,
	}

	# Create a natural clearing in the center for the firebase LZ
	var map_center: float = MAP_SIZE * 0.5
	var central_clearing_radius: float = 25.0  # 25m natural clearing for initial LZ

	for x in range(cell_count):
		for z in range(cell_count):
			var world_x: float = (x + 0.5) * cell_size
			var world_z: float = (z + 0.5) * cell_size
			var world_pos := Vector3(world_x, 0.0, world_z)

			# Distance from map center for natural clearing
			var dist_from_center: float = Vector2(world_x - map_center, world_z - map_center).length()

			var terrain_type: int

			# Natural clearing in center (simulates existing LZ or firebase site)
			if dist_from_center < central_clearing_radius:
				# Gradient from clear center to light jungle at edges
				var clearing_factor: float = dist_from_center / central_clearing_radius
				if clearing_factor < 0.5:
					terrain_type = TerrainTypes.Type.CLEAR
				elif clearing_factor < 0.75:
					terrain_type = TerrainTypes.Type.GRASSLAND
				else:
					terrain_type = TerrainTypes.Type.LIGHT_JUNGLE
			else:
				# Natural jungle with varying density using noise
				var primary_noise: float = noise.get_noise_2d(world_x, world_z)  # -1 to 1
				var detail: float = detail_noise.get_noise_2d(world_x, world_z) * 0.3  # Small variation
				var combined: float = primary_noise + detail  # -1.3 to 1.3

				# Map noise to terrain types (weighted toward medium/heavy for challenging clearing)
				if combined < -0.7:
					# Natural clearings / grassland (rare, ~10%)
					terrain_type = TerrainTypes.Type.GRASSLAND
				elif combined < -0.3:
					# Light jungle (sparse trees, ~15%)
					terrain_type = TerrainTypes.Type.LIGHT_JUNGLE
				elif combined < 0.3:
					# Medium jungle (moderate density, ~35%)
					terrain_type = TerrainTypes.Type.MEDIUM_JUNGLE
				else:
					# Heavy jungle (dense canopy, ~40%)
					terrain_type = TerrainTypes.Type.HEAVY_JUNGLE

			grid.set_terrain_type(world_pos, terrain_type)
			terrain_counts[terrain_type] += 1

	print("[ClearingTest] Initialized %dx%d terrain grid with natural sporadic jungle:" % [cell_count, cell_count])
	print("  CLEAR: %d, GRASSLAND: %d, LIGHT: %d, MEDIUM: %d, HEAVY: %d" % [
		terrain_counts[TerrainTypes.Type.CLEAR],
		terrain_counts[TerrainTypes.Type.GRASSLAND],
		terrain_counts[TerrainTypes.Type.LIGHT_JUNGLE],
		terrain_counts[TerrainTypes.Type.MEDIUM_JUNGLE],
		terrain_counts[TerrainTypes.Type.HEAVY_JUNGLE],
	])
	print("  Central clearing: %.0fm radius for LZ/firebase site" % central_clearing_radius)

	# CRITICAL: Also mark central clearing as CLEARED for building (not just vegetation TYPE)
	# This allows buildings to be placed without auto-creating clearing prerequisite jobs
	if grid.has_method("mark_area_cleared"):
		var center_pos := Vector3(map_center, 0.0, map_center)
		grid.mark_area_cleared(center_pos, central_clearing_radius)
		print("[ClearingTest] Marked central clearing as CLEARED stage for building")
	else:
		# Fallback: use ClearingSystem directly
		var clearing_sys := get_node_or_null("/root/ClearingSystem")
		if clearing_sys and clearing_sys.has_method("mark_area_cleared"):
			var center_pos := Vector3(map_center, 0.0, map_center)
			clearing_sys.mark_area_cleared(center_pos, central_clearing_radius)
			print("[ClearingTest] Marked central clearing as CLEARED via ClearingSystem")


func _setup_vegetation() -> void:
	# Create mock heightmap as fallback (should rarely be used now)
	mock_heightmap = MockHeightmap.new()

	# Get heightmap - should be local_terrain's heightmap
	var heightmap_to_use = _get_heightmap_or_mock()
	var using_real_terrain: bool = heightmap_to_use != mock_heightmap

	# Create VegetationManager for terrain type data
	vegetation_manager = VegetationManager.new()
	vegetation_manager.name = "VegetationManager"
	vegetation_manager.set_chunk_size(chunk_size)
	vegetation_manager.set_camera(camera)
	add_child(vegetation_manager)

	# Create BillboardVegetation for 2D billboard trees
	billboard_vegetation = BillboardVegetation.new()
	billboard_vegetation.name = "BillboardVegetation"
	billboard_vegetation.set_chunk_size(chunk_size)
	billboard_vegetation.set_camera(camera)
	billboard_vegetation.set_vegetation_manager(vegetation_manager)

	# Wire terrain_grid for clearing stage checks (billboard removal in cleared areas)
	# NOTE: terrain_intg.terrain_grid is NOW the local 320m grid after _sync_terrain_with_globals()
	# ran in _setup_local_terrain(). This ensures billboards respect cleared areas.
	if terrain_intg and terrain_intg.terrain_grid:
		billboard_vegetation.set_terrain_grid(terrain_intg.terrain_grid)
		print("[ClearingTest] Wired local terrain_grid to billboard_vegetation for clearing tracking")

	# CRITICAL: Set billboard parameters BEFORE adding to tree (before _ready)
	billboard_vegetation.billboards_per_chunk = TEST_BILLBOARD_COUNT
	# For 320m test map: show billboards beyond 80m (where 3D trees thin out)
	# This creates visible "jungle edge" effect during testing
	billboard_vegetation.billboard_range_min = 80.0
	billboard_vegetation.billboard_range_max = 500.0
	print("[ClearingTest] Billboard config: count=%d, range=80-500m" % TEST_BILLBOARD_COUNT)

	add_child(billboard_vegetation)

	# LOD is now handled by VegetationLODManager (hysteresis prevents flashing)
	# Billboard processing enabled - it will coordinate with 3D tree LOD

	# Generate terrain types for all chunks covering the play area with natural sporadic jungle
	var veg_noise := FastNoiseLite.new()
	veg_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	veg_noise.frequency = 0.015
	veg_noise.seed = 42

	var veg_detail_noise := FastNoiseLite.new()
	veg_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	veg_detail_noise.frequency = 0.05
	veg_detail_noise.seed = 1337

	var map_center: float = MAP_SIZE * 0.5
	var central_clearing_radius: float = 25.0

	for chunk_coord in VEG_CHUNKS:
		var bundles_per_side: int = int(chunk_size / vegetation_manager.bundle_meters)
		var terrain_data := PackedByteArray()
		terrain_data.resize(bundles_per_side * bundles_per_side)

		var chunk_offset_x: float = chunk_coord.x * chunk_size
		var chunk_offset_z: float = chunk_coord.y * chunk_size

		# Generate natural sporadic vegetation for each bundle
		for bz in bundles_per_side:
			for bx in bundles_per_side:
				var bundle_idx: int = bz * bundles_per_side + bx
				var world_x: float = chunk_offset_x + (bx + 0.5) * vegetation_manager.bundle_meters
				var world_z: float = chunk_offset_z + (bz + 0.5) * vegetation_manager.bundle_meters

				# Distance from map center for natural clearing
				var dist_from_center: float = Vector2(world_x - map_center, world_z - map_center).length()

				var terrain_type: int

				# Central clearing
				if dist_from_center < central_clearing_radius:
					var clearing_factor: float = dist_from_center / central_clearing_radius
					if clearing_factor < 0.5:
						terrain_type = VegetationManager.TerrainType.CLEAR
					elif clearing_factor < 0.75:
						terrain_type = VegetationManager.TerrainType.GRASSLAND
					else:
						terrain_type = VegetationManager.TerrainType.LIGHT_JUNGLE
				else:
					# Natural jungle variation using noise
					var primary: float = veg_noise.get_noise_2d(world_x, world_z)
					var detail: float = veg_detail_noise.get_noise_2d(world_x, world_z) * 0.3
					var combined: float = primary + detail

					if combined < -0.7:
						terrain_type = VegetationManager.TerrainType.GRASSLAND
					elif combined < -0.3:
						terrain_type = VegetationManager.TerrainType.LIGHT_JUNGLE
					elif combined < 0.3:
						terrain_type = VegetationManager.TerrainType.MEDIUM_JUNGLE
					else:
						terrain_type = VegetationManager.TerrainType.HEAVY_JUNGLE

				terrain_data[bundle_idx] = terrain_type

		vegetation_manager._chunk_terrain[chunk_coord] = terrain_data

		# Generate billboards using terrain data
		billboard_vegetation.generate_for_chunk(chunk_coord, heightmap_to_use, terrain_data)

	print("[ClearingTest] Generated %d chunks with natural sporadic vegetation" % VEG_CHUNKS.size())

	# Force all billboards visible and count them
	var total_billboard_instances := 0
	var chunks_with_billboards := 0
	for chunk_coord in VEG_CHUNKS:
		if billboard_vegetation._chunk_billboards.has(chunk_coord):
			var container: Node3D = billboard_vegetation._chunk_billboards[chunk_coord]
			if container:
				container.visible = true
				chunks_with_billboards += 1
				# Count MultiMesh instances in the container
				for child in container.get_children():
					if child is MultiMeshInstance3D and child.multimesh:
						total_billboard_instances += child.multimesh.instance_count

	var terrain_source: String = "local TerrainManager" if local_terrain else ("TerrainIntegration" if using_real_terrain else "mock flat")
	print("[ClearingTest] Billboard vegetation: %d chunks generated, %d have containers, %d total billboard instances" % [
		VEG_CHUNKS.size(), chunks_with_billboards, total_billboard_instances
	])
	print("[ClearingTest] Billboard camera set: %s" % (billboard_vegetation._camera != null))


## Setup 3D jungle trees using ONLY light tree model
## Density is controlled by tree COUNT (more trees in denser areas)
## This makes clearing feel like "chipping away" at the jungle
func _setup_3d_trees() -> void:
	tree_container = Node3D.new()
	tree_container.name = "TreeNodes3D"
	add_child(tree_container)

	# Register tree container with VegetationLODManager for distance culling
	var lod_manager := get_node_or_null("/root/VegetationLODManager")
	if lod_manager:
		lod_manager.set_camera(camera)
		# Container will be registered after trees are added
		print("[ClearingTest] VegetationLODManager connected")

	# Spawn 3D trees across the map - use only JUNGLE_LIGHT model
	# Density controlled by spawn multiplier based on terrain type
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345  # Consistent placement

	var tree_count := 0
	var area := MAP_SIZE * MAP_SIZE
	# Reduce density for larger map to maintain performance
	var adjusted_density: float = TREE_DENSITY * 0.6  # 60% density for 320m map
	var base_target_trees := int(area * adjusted_density)

	print("[ClearingTest] Spawning jungle trees (light model only, natural sporadic density)...")

	# Generate more positions than needed, then filter based on density multiplier
	var max_attempts := mini(base_target_trees * 4, 20000)  # Cap at 20k attempts for performance

	# Use same noise as terrain for consistent vegetation distribution
	var veg_noise := FastNoiseLite.new()
	veg_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	veg_noise.frequency = 0.015
	veg_noise.seed = 42

	var veg_detail_noise := FastNoiseLite.new()
	veg_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	veg_detail_noise.frequency = 0.05
	veg_detail_noise.seed = 1337

	var map_center: float = MAP_SIZE * 0.5
	var central_clearing_radius: float = 25.0

	for _i in range(max_attempts):
		var pos := Vector3(
			rng.randf_range(5.0, MAP_SIZE - 5.0),
			0.0,
			rng.randf_range(5.0, MAP_SIZE - 5.0)
		)

		# Get terrain height
		pos.y = _get_terrain_height(pos.x, pos.z)

		# Check central clearing - no trees in LZ area
		var dist_from_center: float = Vector2(pos.x - map_center, pos.z - map_center).length()
		if dist_from_center < central_clearing_radius:
			continue

		# Get terrain type at position (use noise directly for consistency)
		var primary: float = veg_noise.get_noise_2d(pos.x, pos.z)
		var detail: float = veg_detail_noise.get_noise_2d(pos.x, pos.z) * 0.3
		var combined: float = primary + detail

		var terrain_type: int
		if combined < -0.7:
			terrain_type = TerrainTypes.Type.GRASSLAND
		elif combined < -0.3:
			terrain_type = TerrainTypes.Type.LIGHT_JUNGLE
		elif combined < 0.3:
			terrain_type = TerrainTypes.Type.MEDIUM_JUNGLE
		else:
			terrain_type = TerrainTypes.Type.HEAVY_JUNGLE

		# Skip cleared/grassland areas
		if terrain_type <= TerrainTypes.Type.GRASSLAND:
			continue

		# Density multiplier - determines spawn chance
		# More trees in denser jungle areas (controlled by probability)
		var density_multiplier: float
		match terrain_type:
			TerrainTypes.Type.LIGHT_JUNGLE:
				density_multiplier = 0.25   # 25% spawn chance - sparse
			TerrainTypes.Type.MEDIUM_JUNGLE:
				density_multiplier = 0.55   # 55% spawn chance - moderate
			TerrainTypes.Type.HEAVY_JUNGLE:
				density_multiplier = 0.85   # 85% spawn chance - dense (not 100% for natural gaps)
			_:
				density_multiplier = 0.0    # No trees in cleared areas

		# Probability-based spawning for density control
		if rng.randf() > density_multiplier:
			continue

		# Random tree height - consistent for all light trees
		var base_height := rng.randf_range(5.0, 9.0)

		# ALWAYS use JUNGLE_LIGHT model - density is controlled by COUNT, not model type
		var tree: Node3D = TreeNodeClass.create(TreeNodeClass.TreeType.JUNGLE_LIGHT, pos, base_height)
		if tree:
			# Random rotation
			tree.rotation.y = rng.randf() * TAU
			tree_container.add_child(tree)
			tree_nodes.append(tree)
			tree_count += 1

	tree_container.visible = trees_visible
	print("[ClearingTest] Spawned %d light trees (natural sporadic pattern, T to toggle)" % tree_count)

	# Register all trees with LOD manager for distance culling
	# Note: lod_manager already retrieved at start of function
	if lod_manager:
		lod_manager.register_trees(tree_nodes)
		print("[ClearingTest] Registered %d trees with VegetationLODManager" % tree_nodes.size())


func _set_chunk_heavy_jungle(chunk_coord: Vector2i) -> void:
	if vegetation_manager._chunk_terrain.has(chunk_coord):
		var terrain: PackedByteArray = vegetation_manager._chunk_terrain[chunk_coord]
		for i in range(terrain.size()):
			terrain[i] = VegetationManager.TerrainType.HEAVY_JUNGLE
		vegetation_manager._chunk_terrain[chunk_coord] = terrain
		print("[ClearingTest] Set all bundles to HEAVY_JUNGLE")


# _setup_area_preview removed - ghosts now handled by PlacementController via BattleHUD


func _setup_grid_overlay() -> void:
	grid_overlay = MeshInstance3D.new()
	grid_overlay.name = "GridOverlay"
	# Ensure grid overlay has no transform offset
	grid_overlay.transform = Transform3D.IDENTITY
	add_child(grid_overlay)

	# Debug: check terrain height sampling and compare with actual mesh
	if local_terrain and local_terrain.heightmap:
		var test_h: float = local_terrain.heightmap.sample_world(32.0, 32.0)
		var raw_h: float = local_terrain.heightmap.sample_bilinear(32.0 / local_terrain.heightmap.cell_size, 32.0 / local_terrain.heightmap.cell_size)
		print("[ClearingTest] Terrain height at (32,32): %.2f (raw: %.4f, scale: %.1f)" % [
			test_h, raw_h, local_terrain.heightmap.height_scale
		])

		# Add a debug sphere at the sampled height position
		var debug_sphere := MeshInstance3D.new()
		debug_sphere.name = "DebugHeightMarker"
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		debug_sphere.mesh = sphere
		var debug_mat := StandardMaterial3D.new()
		debug_mat.albedo_color = Color.RED
		debug_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		debug_sphere.material_override = debug_mat
		debug_sphere.position = Vector3(32.0, test_h, 32.0)
		add_child(debug_sphere)
		print("[ClearingTest] Debug sphere placed at (32, %.2f, 32)" % test_h)

		# Also check local_terrain's global transform
		print("[ClearingTest] LocalTerrain transform: %s" % local_terrain.transform)

		# Check if chunk exists at (0,0) and its position
		if local_terrain.chunks.has(Vector2i(0, 0)):
			var chunk: Node3D = local_terrain.chunks[Vector2i(0, 0)]
			print("[ClearingTest] Chunk(0,0) position: %s, global: %s" % [chunk.position, chunk.global_position])

	# Defer grid rebuild to ensure terrain is fully ready
	call_deferred("_rebuild_grid_overlay")
	print("[ClearingTest] Grid overlay created (G to toggle)")


## Rebuild the grid overlay mesh based on current vegetation terrain types
## Grid conforms to actual terrain height from TerrainManager
func _rebuild_grid_overlay() -> void:
	if not grid_overlay or not vegetation_manager:
		return

	var bundle_size: float = vegetation_manager.bundle_meters
	var bundles_per_side: int = int(chunk_size / bundle_size)

	# Debug: sample a few heights to verify terrain is working
	var sample_h := _get_terrain_height(32.0, 32.0)
	print("[ClearingTest] Grid rebuild - height at (32,32): %.2f" % sample_h)

	# Build immediate geometry mesh with grid lines and cell fills
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	# Draw grid lines - sample terrain height at each vertex
	var line_color := Color(1.0, 1.0, 0.0, 1.0)  # Bright yellow for visibility
	var height_offset := 1.5  # Higher offset to ensure visibility above terrain

	# Draw grid for all chunks
	for chunk_coord in VEG_CHUNKS:
		if not vegetation_manager._chunk_terrain.has(chunk_coord):
			continue

		var chunk_offset_x: float = chunk_coord.x * chunk_size
		var chunk_offset_z: float = chunk_coord.y * chunk_size

		# Vertical lines (along Z) - use center height to avoid spikes on slopes
		for x in range(bundles_per_side + 1):
			var world_x: float = chunk_offset_x + x * bundle_size
			for z in range(bundles_per_side):
				var z0: float = chunk_offset_z + z * bundle_size
				var z1: float = chunk_offset_z + (z + 1) * bundle_size
				# Sample center point only - both endpoints at same height = flat line
				var center_z: float = (z0 + z1) * 0.5
				var center_y: float = _get_terrain_height(world_x, center_z) + height_offset
				im.surface_set_color(line_color)
				im.surface_add_vertex(Vector3(world_x, center_y, z0))
				im.surface_add_vertex(Vector3(world_x, center_y, z1))

		# Horizontal lines (along X) - use center height to avoid spikes on slopes
		for z in range(bundles_per_side + 1):
			var world_z: float = chunk_offset_z + z * bundle_size
			for x in range(bundles_per_side):
				var x0: float = chunk_offset_x + x * bundle_size
				var x1: float = chunk_offset_x + (x + 1) * bundle_size
				# Sample center point only - both endpoints at same height = flat line
				var center_x: float = (x0 + x1) * 0.5
				var center_y: float = _get_terrain_height(center_x, world_z) + height_offset
				im.surface_set_color(line_color)
				im.surface_add_vertex(Vector3(x0, center_y, world_z))
				im.surface_add_vertex(Vector3(x1, center_y, world_z))

	im.surface_end()

	# Create material for lines - render on top of terrain
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.vertex_color_use_as_albedo = true
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.render_priority = 10  # Render on top
	line_mat.no_depth_test = true  # Always visible
	im.surface_set_material(0, line_mat)

	# Build cell fill quads for terrain type visualization
	# Each quad conforms to terrain height at its 4 corners
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var fill_offset := 1.3  # Higher offset to stay visible above terrain

	for chunk_coord in VEG_CHUNKS:
		if not vegetation_manager._chunk_terrain.has(chunk_coord):
			continue

		var terrain: PackedByteArray = vegetation_manager._chunk_terrain[chunk_coord]
		var chunk_offset_x: float = chunk_coord.x * chunk_size
		var chunk_offset_z: float = chunk_coord.y * chunk_size

		for bz in bundles_per_side:
			for bx in bundles_per_side:
				var idx: int = bz * bundles_per_side + bx
				if idx >= terrain.size():
					continue

				var terrain_type: int = terrain[idx]
				var cell_color: Color

				# Color based on terrain type
				match terrain_type:
					VegetationManager.TerrainType.CLEAR:
						cell_color = Color(0.6, 0.5, 0.3, 0.25)  # Light brown (cleared)
					VegetationManager.TerrainType.RICE_PADDY:
						cell_color = Color(0.4, 0.6, 0.3, 0.25)  # Yellow-green (paddies)
					VegetationManager.TerrainType.GRASSLAND:
						cell_color = Color(0.5, 0.7, 0.3, 0.25)  # Light green (grass)
					VegetationManager.TerrainType.LIGHT_JUNGLE:
						cell_color = Color(0.2, 0.5, 0.2, 0.25)  # Medium green
					VegetationManager.TerrainType.MEDIUM_JUNGLE:
						cell_color = Color(0.1, 0.4, 0.15, 0.3)  # Darker green
					VegetationManager.TerrainType.HEAVY_JUNGLE:
						cell_color = Color(0.05, 0.3, 0.1, 0.35)  # Dark green
					_:
						cell_color = Color(0.5, 0.5, 0.5, 0.2)  # Gray (unknown)

				# Quad corners - use single center height (prevents vertical spikes on slopes)
				var x0: float = chunk_offset_x + bx * bundle_size
				var x1: float = chunk_offset_x + (bx + 1) * bundle_size
				var z0: float = chunk_offset_z + bz * bundle_size
				var z1: float = chunk_offset_z + (bz + 1) * bundle_size

				# Sample center point only - all 4 corners at same height = flat horizontal quad
				var center_x: float = (x0 + x1) * 0.5
				var center_z: float = (z0 + z1) * 0.5
				var center_y: float = _get_terrain_height(center_x, center_z) + fill_offset

				# Two triangles for quad (flat, not terrain-conforming to avoid vertical spikes)
				im.surface_set_color(cell_color)
				im.surface_add_vertex(Vector3(x0, center_y, z0))
				im.surface_add_vertex(Vector3(x1, center_y, z0))
				im.surface_add_vertex(Vector3(x1, center_y, z1))

				im.surface_add_vertex(Vector3(x0, center_y, z0))
				im.surface_add_vertex(Vector3(x1, center_y, z1))
				im.surface_add_vertex(Vector3(x0, center_y, z1))

	im.surface_end()

	# Create material for fill - render on top of terrain
	var fill_mat := StandardMaterial3D.new()
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.vertex_color_use_as_albedo = true
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fill_mat.render_priority = 9  # Below grid lines, above terrain
	fill_mat.no_depth_test = true  # Always visible
	im.surface_set_material(1, fill_mat)

	grid_overlay.mesh = im
	grid_overlay.visible = grid_visible


func _spawn_engineer(pos: Vector3) -> void:
	var data: Resource = load("res://battle_system/data/units/us_engineers.tres")
	if not data:
		data = SquadData.new()
		data.display_name = "Combat Engineer"
		data.squad_size = 4
		data.faction = GameEnums.Faction.US_ARMY
		data.can_build = true
		data.is_vehicle = false

	var engineer := Squad.new()
	engineer.name = "Engineer_%d" % workers.size()
	engineer.data = data
	# Set Y position from terrain height
	var terrain_y: float = _get_terrain_height(pos.x, pos.z)
	engineer.position = Vector3(pos.x, terrain_y, pos.z)

	add_child(engineer)
	workers.append(engineer)
	print("[ClearingTest] Engineer spawned at Y=%.1f" % terrain_y)


func _spawn_bulldozer(pos: Vector3) -> void:
	var data: Resource = load("res://battle_system/data/units/us_bulldozer.tres")
	if not data:
		data = SquadData.new()
		data.display_name = "D7 Bulldozer"
		data.squad_size = 1
		data.faction = GameEnums.Faction.US_ARMY
		data.can_build = true
		data.is_vehicle = true
		data.move_speed = 3.0

	var bulldozer := Squad.new()
	bulldozer.name = "Bulldozer_%d" % workers.size()
	bulldozer.data = data
	# Set Y position from terrain height
	var terrain_y: float = _get_terrain_height(pos.x, pos.z)
	bulldozer.position = Vector3(pos.x, terrain_y, pos.z)

	add_child(bulldozer)
	workers.append(bulldozer)
	print("[ClearingTest] Bulldozer spawned at Y=%.1f" % terrain_y)


func _input(event: InputEvent) -> void:
	# All standard RTS input (selection, placement, paint modes) is now handled by BattleHUD.
	# This scene only handles TEST/DEBUG hotkeys.
	#
	# If BattleHUD is in a special mode (placing, paint), let it handle everything.
	var battle_hud := get_node_or_null("/root/BattleHUD")
	if battle_hud:
		# Check if BattleHUD is handling something
		if battle_hud.has_method("is_placing") and battle_hud.is_placing():
			return  # BattleHUD handles placement input
		if battle_hud.has_method("get_cursor_mode"):
			var mode: int = battle_hud.get_cursor_mode()
			if mode != 0:  # 0 = NORMAL mode
				return  # BattleHUD handles special mode input

	# Only handle keyboard events for test hotkeys
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			_handle_test_hotkey(key)


## Handle debug-only hotkeys - all gameplay input is handled by BattleHUD
## These are development aids, not gameplay features
func _handle_test_hotkey(event: InputEventKey) -> void:
	match event.keycode:
		KEY_G:  # Toggle grid overlay (debug visualization)
			grid_visible = not grid_visible
			if grid_overlay:
				grid_overlay.visible = grid_visible
			print("[DEBUG] Grid overlay: %s" % ("ON" if grid_visible else "OFF"))

		KEY_T:  # Toggle 3D trees (debug visualization)
			trees_visible = not trees_visible
			if tree_container:
				tree_container.visible = trees_visible
			print("[DEBUG] 3D Trees: %s" % ("ON" if trees_visible else "OFF"))

		KEY_F8:  # Reset scene (debug)
			print("[DEBUG] Resetting scene...")
			get_tree().reload_current_scene()


## NOTE: Construction cancellation via right-click is now handled by BattleHUD


## NOTE: Paint area preview now handled by BattleHUD's paint mode

func _create_clear_job(start: Vector3, end: Vector3) -> void:
	# Get terrain heights at corners to fix 3D arrival check (Y=0 caused workers to never arrive)
	var min_y := _get_terrain_height(minf(start.x, end.x), minf(start.z, end.z))
	var max_y := _get_terrain_height(maxf(start.x, end.x), maxf(start.z, end.z))
	var min_corner := Vector3(minf(start.x, end.x), min_y, minf(start.z, end.z))
	var max_corner := Vector3(maxf(start.x, end.x), max_y, maxf(start.z, end.z))

	var size: Vector3 = max_corner - min_corner
	if size.x < 2.0 or size.z < 2.0:
		print("[ClearingTest] Area too small (min 2x2)")
		return

	print("[ClearingTest] Creating CLEAR job: %.1f x %.1f at %s" % [size.x, size.z, min_corner])

	# Use JobSystem for job creation
	var job_system = get_node_or_null("/root/JobSystem")
	if job_system:
		var center := (min_corner + max_corner) * 0.5
		var job_size := Vector2(size.x, size.z)
		var job = job_system.create_job(
			UnifiedJobClass.Type.CLEAR_TERRAIN,
			center,
			job_size
		)
		if job:
			job.metadata["clear_center"] = center
			job.metadata["clear_radius"] = maxf(size.x, size.z) * 0.5
			job.metadata["clear_min"] = min_corner
			job.metadata["clear_max"] = max_corner
			print("[ClearingTest] Job #%d created via JobSystem" % job.job_id)
	else:
		push_warning("[ClearingTest] JobSystem not found - cannot create job")


func _create_initial_clearing_job() -> void:
	"""Create an initial CLEAR_TERRAIN job in the jungle area for immediate worker testing.
	   The job is placed in the jungle zone (offset from center clearing) so workers have trees to fell."""
	var job_system = get_node_or_null("/root/JobSystem")
	if not job_system:
		push_warning("[ClearingTest] JobSystem not found - cannot create initial clearing job")
		return

	# Place clearing job in the jungle area (northeast of center, outside the natural clearing)
	# Natural clearing is 25m radius at center, so place at 40m offset
	var map_center := MAP_SIZE * 0.5
	var job_center := Vector3(map_center + 45.0, 0.0, map_center - 45.0)
	var job_size := Vector2(20.0, 20.0)  # 20x20m clearing job

	# Get terrain height at job center
	job_center.y = _get_terrain_height(job_center.x, job_center.z)

	var job = job_system.create_job(
		UnifiedJobClass.Type.CLEAR_TERRAIN,
		job_center,
		job_size
	)

	if job:
		print("[ClearingTest] Initial CLEAR_TERRAIN job #%d created at %v (20x20m in jungle)" % [
			job.job_id, job_center
		])
		print("[ClearingTest] Trees in group: %d" % get_tree().get_nodes_in_group("trees").size())

		# Count trees in job bounds for debugging
		var trees_in_job := 0
		var bounds: AABB = job.world_bounds
		for tree in get_tree().get_nodes_in_group("trees"):
			if not is_instance_valid(tree):
				continue
			var pos: Vector3 = tree.global_position
			if pos.x >= bounds.position.x and pos.x <= bounds.end.x:
				if pos.z >= bounds.position.z and pos.z <= bounds.end.z:
					trees_in_job += 1
		print("[ClearingTest] Trees in job bounds: %d" % trees_in_job)
	else:
		push_warning("[ClearingTest] Failed to create initial clearing job")


func _on_job_created(job) -> void:
	print("[ClearingTest] JOB CREATED: #%d %s" % [job.job_id, UnifiedJobClass.get_type_name(job.job_type)])


func _on_job_completed(job) -> void:
	print("[ClearingTest] JOB COMPLETED: #%d %s" % [job.job_id, UnifiedJobClass.get_type_name(job.job_type)])
	# Progressive clearing: Billboards are removed as the ClearingZoneNode expands
	# via ClearingZoneNode._update_visuals() calling mark_area_cleared(). This happens
	# gradually during work, not all at once at completion.


## Handle ClearingSystem vegetation_updated signal - regenerate LOCAL billboards and clear 3D trees
func _on_clearing_vegetation_updated(region: Rect2i) -> void:
	if not billboard_vegetation or not vegetation_manager:
		return

	print("[ClearingTest] Clearing detected in region %s - regenerating billboards" % region)

	var heightmap_to_use = _get_heightmap_or_mock()

	# Convert region to world coordinates (TerrainGrid uses 4m cells)
	var cell_size: float = 4.0
	var region_min_x: float = region.position.x * cell_size
	var region_min_z: float = region.position.y * cell_size
	var region_max_x: float = (region.position.x + region.size.x) * cell_size
	var region_max_z: float = (region.position.y + region.size.y) * cell_size

	# NOTE: 3D trees are felled individually by workers (WorkerController._process_chopping),
	# so they are not batch-removed here. This only regenerates distant billboards.

	# Update terrain data and regenerate billboards for affected chunks
	var bundle_size: float = vegetation_manager.bundle_meters
	var bundles_per_side: int = int(chunk_size / bundle_size)
	var billboards_cleared := 0

	for chunk_coord in VEG_CHUNKS:
		if not vegetation_manager._chunk_terrain.has(chunk_coord):
			continue

		# Check if this chunk overlaps the cleared region
		var chunk_world_min_x: float = chunk_coord.x * chunk_size
		var chunk_world_min_z: float = chunk_coord.y * chunk_size
		var chunk_world_max_x: float = chunk_world_min_x + chunk_size
		var chunk_world_max_z: float = chunk_world_min_z + chunk_size

		# Check overlap
		if chunk_world_max_x < region_min_x or chunk_world_min_x > region_max_x:
			continue
		if chunk_world_max_z < region_min_z or chunk_world_min_z > region_max_z:
			continue

		# FIX: Update terrain_data to mark cleared bundles BEFORE regenerating
		# This ensures billboards are actually removed, not just regenerated with old data
		var terrain_data: PackedByteArray = vegetation_manager._chunk_terrain[chunk_coord]
		var modified := false

		for bz in bundles_per_side:
			for bx in bundles_per_side:
				var bundle_center_x: float = chunk_world_min_x + (bx + 0.5) * bundle_size
				var bundle_center_z: float = chunk_world_min_z + (bz + 0.5) * bundle_size

				# Check if bundle is in the cleared region
				if bundle_center_x >= region_min_x and bundle_center_x <= region_max_x:
					if bundle_center_z >= region_min_z and bundle_center_z <= region_max_z:
						var idx: int = bz * bundles_per_side + bx
						if idx < terrain_data.size() and terrain_data[idx] != VegetationManager.TerrainType.CLEAR:
							terrain_data[idx] = VegetationManager.TerrainType.CLEAR
							modified = true
							billboards_cleared += 1

		if modified:
			vegetation_manager._chunk_terrain[chunk_coord] = terrain_data

		# Regenerate this chunk's billboards with updated terrain data
		billboard_vegetation.generate_for_chunk(chunk_coord, heightmap_to_use, terrain_data)
		print("[ClearingTest] Regenerated billboards for chunk %s" % chunk_coord)

	if billboards_cleared > 0:
		print("[ClearingTest] Cleared %d billboard bundles" % billboards_cleared)

	# Rebuild grid overlay
	_rebuild_grid_overlay()


func _clear_vegetation_in_rect(min_corner: Vector3, max_corner: Vector3) -> void:
	if not vegetation_manager or not billboard_vegetation:
		return

	var bundle_size: float = vegetation_manager.bundle_meters
	var bundles_per_side: int = int(chunk_size / bundle_size)
	var heightmap_to_use = _get_heightmap_or_mock()

	var total_cleared := 0

	# Check each chunk for affected bundles
	for chunk_coord in VEG_CHUNKS:
		if not vegetation_manager._chunk_terrain.has(chunk_coord):
			continue

		var terrain: PackedByteArray = vegetation_manager._chunk_terrain[chunk_coord]
		var chunk_offset_x: float = chunk_coord.x * chunk_size
		var chunk_offset_z: float = chunk_coord.y * chunk_size
		var cleared := 0

		# Clear bundles in the rectangle
		for bz in bundles_per_side:
			for bx in bundles_per_side:
				var bundle_center_x: float = chunk_offset_x + (bx + 0.5) * bundle_size
				var bundle_center_z: float = chunk_offset_z + (bz + 0.5) * bundle_size

				if bundle_center_x >= min_corner.x and bundle_center_x <= max_corner.x:
					if bundle_center_z >= min_corner.z and bundle_center_z <= max_corner.z:
						var idx: int = bz * bundles_per_side + bx
						if idx < terrain.size() and terrain[idx] != VegetationManager.TerrainType.CLEAR:
							terrain[idx] = VegetationManager.TerrainType.CLEAR
							cleared += 1

		if cleared > 0:
			vegetation_manager._chunk_terrain[chunk_coord] = terrain
			billboard_vegetation.generate_for_chunk(chunk_coord, heightmap_to_use, terrain)
			total_cleared += cleared

	if total_cleared > 0:
		# Rebuild grid overlay to show cleared areas
		_rebuild_grid_overlay()

		print("[ClearingTest] Cleared %d vegetation bundles" % total_cleared)


func _process(_delta: float) -> void:
	# LOD is now handled automatically by VegetationLODManager
	_update_hud()


func _update_hud() -> void:
	if not hud:
		return

	var job_system = get_node_or_null("/root/JobSystem")

	var text := "=== Firebase Construction (320m) ===\n"
	text += "Supply: %d | Map: %.0fm x %.0fm\n" % [current_supply, MAP_SIZE, MAP_SIZE]

	var engineers := 0
	var bulldozers := 0
	var idle_workers := 0
	for w in workers:
		if w.data and w.data.is_vehicle:
			bulldozers += 1
		else:
			engineers += 1
		# Check if worker is idle
		if w.has_method("get_worker_controller"):
			var wc: Node = w.get_worker_controller()
			if wc and wc.has_method("is_idle") and wc.is_idle():
				idle_workers += 1
	text += "Workers: %d Eng + %d Dozer (%d idle)\n" % [engineers, bulldozers, idle_workers]

	# Show current mode from BattleHUD
	var battle_hud := get_node_or_null("/root/BattleHUD")
	var mode_str: String = "NORMAL"
	if battle_hud and battle_hud.has_method("get_cursor_mode"):
		var mode: int = battle_hud.get_cursor_mode()
		match mode:
			0: mode_str = "NORMAL"
			1: mode_str = "PLACING"
			2: mode_str = "PAINT CLEAR"
			3: mode_str = "PAINT ROAD"
			_: mode_str = "MODE %d" % mode
	text += "\nMode: %s\n" % mode_str

	# Show job counts and queue
	if job_system:
		var counts: Dictionary = job_system.get_job_counts()
		text += "\nJobs: %d pending, %d ready, %d in-progress\n" % [counts.pending, counts.ready, counts.in_progress]

		# Show job queue details (up to 5 jobs)
		var all_jobs: Array = []
		for job in job_system._ready_jobs + job_system._in_progress_jobs:
			if is_instance_valid(job):
				all_jobs.append(job)

		if all_jobs.size() > 0:
			text += "Active Jobs:\n"
			var shown := 0
			for job in all_jobs:
				if shown >= 5:
					text += "  ... +%d more\n" % (all_jobs.size() - 5)
					break
				var type_name: String = UnifiedJobClass.get_type_name(job.job_type)
				var progress: float = job.work_done / job.work_required if job.work_required > 0 else 0.0
				var workers_count: int = job.assigned_workers.size()
				var state: String = "RDY" if job.state == UnifiedJobClass.State.READY else "WRK"
				text += "  [%s] %s: %.0f%% (%d workers)\n" % [state, type_name, progress * 100, workers_count]
				shown += 1

		# Show pending jobs (prerequisites not met)
		if job_system._pending_jobs.size() > 0:
			text += "Pending: %d (waiting for prerequisites)\n" % job_system._pending_jobs.size()

	# Vegetation stats
	var cleared := _count_clear_bundles()
	var total := _count_total_bundles()
	text += "\nVegetation: %d/%d bundles cleared\n" % [cleared, total]
	var standing_trees := 0
	for t in tree_nodes:
		if is_instance_valid(t):
			standing_trees += 1
	text += "3D Trees: %d (%s) | Grid: %s\n" % [
		standing_trees,
		"visible" if trees_visible else "hidden",
		"ON" if grid_visible else "OFF"
	]

	# Worker states
	text += "\nWorker Status:\n"
	for worker in workers:
		var status: String = "IDLE"

		# Check WorkerController for status
		if worker.has_method("get_worker_controller"):
			var wc: Node = worker.get_worker_controller()
			if wc and wc.has_method("get_status_string"):
				status = wc.get_status_string()

		text += "  %s: %s\n" % [worker.name, status]

	# Controls reminder
	text += "\n\nControls:"
	text += "\n  B=Build menu | R=Rotate | ESC=Cancel"
	text += "\n  G=Grid | T=Trees | F8=Reset"

	hud.text = text


func _count_clear_bundles() -> int:
	if not vegetation_manager:
		return 0
	var count := 0
	for chunk_coord in VEG_CHUNKS:
		if vegetation_manager._chunk_terrain.has(chunk_coord):
			var terrain: PackedByteArray = vegetation_manager._chunk_terrain[chunk_coord]
			for t in terrain:
				if t == VegetationManager.TerrainType.CLEAR:
					count += 1
	return count


func _count_total_bundles() -> int:
	if not vegetation_manager:
		return 0
	var count := 0
	for chunk_coord in VEG_CHUNKS:
		if vegetation_manager._chunk_terrain.has(chunk_coord):
			count += vegetation_manager._chunk_terrain[chunk_coord].size()
	return count


## Get terrain height at world position using local terrain (primary) or TerrainIntegration (fallback)
func _get_terrain_height(world_x: float, world_z: float) -> float:
	# Primary: use local terrain (fast, small map)
	if local_terrain and local_terrain.heightmap:
		return local_terrain.heightmap.sample_world(world_x, world_z)
	# Fallback: TerrainIntegration (if loaded from main scene)
	if terrain_intg and terrain_intg.terrain_manager and terrain_intg.terrain_manager.heightmap:
		return terrain_intg.terrain_manager.heightmap.sample_world(world_x, world_z)
	return 0.0


## Get heightmap from local terrain or TerrainIntegration, fallback to mock
func _get_heightmap_or_mock():
	# Primary: local terrain heightmap
	if local_terrain and local_terrain.heightmap:
		return local_terrain.heightmap
	# Fallback: TerrainIntegration
	if terrain_intg and terrain_intg.terrain_manager and terrain_intg.terrain_manager.heightmap:
		return terrain_intg.terrain_manager.heightmap
	return mock_heightmap


## =============================================================================
## ADDITIONAL JOB TYPES
## =============================================================================

## Create a flatten job at the cursor position
func _create_flatten_job(center: Vector3) -> void:
	var job_system = get_node_or_null("/root/JobSystem")
	if not job_system:
		push_warning("[ClearingTest] JobSystem not found")
		return

	var job = job_system.create_job(
		UnifiedJobClass.Type.FLATTEN_AREA,
		center,
		Vector2(12.0, 12.0)
	)
	if job:
		print("[ClearingTest] Flatten job created: #%d at %s" % [job.job_id, center])


## NOTE: Road and fortification modes now handled by BattleHUD/PlacementController


## =============================================================================
## TERRAIN DEFORMATION (Real-time mesh modification!)
## =============================================================================

## Create a crater at the cursor position - ACTUALLY DEFORMS THE TERRAIN MESH
func _create_crater(center: Vector3) -> void:
	if not local_terrain or not local_terrain.heightmap:
		push_warning("[ClearingTest] No terrain to deform")
		return

	var radius := 6.0  # 6m crater radius
	var depth := 3.0   # 3m deep
	var rim_height := 1.0  # 1m rim

	print("[ClearingTest] Creating crater at %s (radius=%.1f, depth=%.1f)" % [center, radius, depth])

	# Modify the heightmap directly with crater shape
	var cell_center: Vector2i = local_terrain.heightmap.world_to_cell(center.x, center.z)
	var cell_radius: int = int(ceil(radius / local_terrain.cell_size))
	var normalized_depth: float = depth / local_terrain.height_scale
	var normalized_rim: float = rim_height / local_terrain.height_scale

	var modifier := func(h: float, falloff: float) -> float:
		if falloff > 0.7:
			# Inner crater - dig down
			return h - normalized_depth * falloff
		elif falloff > 0.3:
			# Rim - pile up dirt
			return h + normalized_rim * (1.0 - falloff)
		else:
			return h

	var affected: Rect2i = local_terrain.heightmap.modify_region(cell_center, cell_radius, modifier)

	# Rebuild affected chunks to show the deformation
	_rebuild_chunks_in_region(affected)

	print("[ClearingTest] Crater created! Affected region: %s" % affected)


## Raise terrain at the cursor position - mound/hill creation
func _raise_terrain(center: Vector3) -> void:
	if not local_terrain or not local_terrain.heightmap:
		push_warning("[ClearingTest] No terrain to deform")
		return

	var radius := 8.0  # 8m radius
	var height := 4.0  # 4m tall mound

	print("[ClearingTest] Raising terrain at %s (radius=%.1f, height=%.1f)" % [center, radius, height])

	var cell_center: Vector2i = local_terrain.heightmap.world_to_cell(center.x, center.z)
	var cell_radius: int = int(ceil(radius / local_terrain.cell_size))
	var normalized_height: float = height / local_terrain.height_scale

	var modifier := func(h: float, falloff: float) -> float:
		# Smooth gaussian mound
		return h + normalized_height * falloff * falloff

	var affected: Rect2i = local_terrain.heightmap.modify_region(cell_center, cell_radius, modifier)

	# Rebuild affected chunks
	_rebuild_chunks_in_region(affected)

	print("[ClearingTest] Terrain raised! Affected region: %s" % affected)


## Rebuild terrain chunks that overlap with a heightmap region
func _rebuild_chunks_in_region(region: Rect2i) -> void:
	if not local_terrain:
		return

	var cells_per_chunk: int = int(local_terrain.chunk_size / local_terrain.cell_size)

	# Convert heightmap cells to chunk coordinates
	var chunk_min := Vector2i(region.position.x / cells_per_chunk, region.position.y / cells_per_chunk)
	var chunk_max := Vector2i(region.end.x / cells_per_chunk, region.end.y / cells_per_chunk)

	# Rebuild all affected chunks
	for cx in range(chunk_min.x, chunk_max.x + 1):
		for cy in range(chunk_min.y, chunk_max.y + 1):
			var coord := Vector2i(cx, cy)
			if local_terrain.chunks.has(coord):
				local_terrain.queue_chunk_rebuild(coord)
				print("[ClearingTest] Queued chunk rebuild: %s" % coord)
