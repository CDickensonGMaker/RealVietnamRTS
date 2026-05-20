extends Node3D
## Clearing Test Scene - Tests worker auto-assignment to clear jobs
##
## Uses 2D billboard trees from BillboardVegetation system
## RTS camera controls via TestSceneBase
##
## Rise to Ruins style: Paint clear areas, workers auto-go do them
##
## Controls:
## - WASD: Pan camera
## - Mouse wheel: Zoom
## - Middle mouse drag: Rotate
## - Left-click + drag: Paint clear area (default mode)
## - B: Open build menu (RTS-style building selection)
## - Right-click or ESC: Cancel placement mode
## - E: Spawn engineer at cursor
## - Shift+B: Spawn bulldozer at cursor
## - X: Create crater at cursor (terrain deformation!)
## - Z: Raise terrain at cursor
## - R: Rotate building preview (in placement mode)
## - Space: Toggle auto-mode

const TerrainTypes = preload("res://terrain/terrain_types.gd")
const UnifiedJobClass = preload("res://firebase_system/job_system/unified_job.gd")
const BuildingDataClass = preload("res://firebase_system/building_data.gd")
const GridCoordsClass = preload("res://terrain/core/grid_coords.gd")
const TerrainGridClass = preload("res://terrain/core/terrain_grid.gd")
const TreeNodeClass = preload("res://terrain/vegetation/tree_node.gd")
const BlueprintGhostClass = preload("res://battle_system/ui/blueprint_ghost.gd")
const BuildMenuPopupClass = preload("res://battle_system/ui/build_menu_popup.gd")

## Mock heightmap for flat terrain
class MockHeightmap:
	var height: float = 0.0

	func sample_world(_x: float, _z: float) -> float:
		return height

	func get_normal_world(_x: float, _z: float) -> Vector3:
		return Vector3.UP

## Command mode enum
enum CommandMode {
	PAINT_CLEAR,    # Default: paint clearing areas
	PLACE_BUILDING, # Building placement mode (after selecting from menu)
	ROAD_MODE,      # Road painting mode
	FORT_MODE,      # Fortification line mode (trenches/wire)
}

## State
var camera: Camera3D
var is_painting := false
var paint_start: Vector3 = Vector3.INF
var paint_current: Vector3 = Vector3.INF
var blueprint_ghost: Node3D  # BlueprintGhost for clearing/building preview
var hud: Label
var workers: Array[Node3D] = []

## Command mode
var current_mode: CommandMode = CommandMode.PAINT_CLEAR

## Road painting mode
var road_points: PackedVector3Array = []
var road_ghost: Node3D  # Separate ghost for road preview

## Fortification line-painting mode (trenches, wire)
enum FortType { NONE, TRENCH, WIRE }
var fort_type: FortType = FortType.NONE
var fort_line_start: Vector3 = Vector3.INF
var fort_line_end: Vector3 = Vector3.INF
var fort_ghost: Node3D  # Line ghost for fortification preview

## Building placement system (RTS-style)
var build_menu: BuildMenuPopupClass
var selected_building_key: String = ""
var selected_building_type: int = -1
var placement_rotation: float = 0.0
var building_ghost: Node3D  # Ghost for building placement
var current_building_data: BuildingDataClass

## Supply tracking
var current_supply: int = 500  # Starting supply for test

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
## For 90m map with 64m chunks, need 2x2 chunk coverage
var VEG_CHUNKS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]

## Map size for camera bounds - 40% larger for more testing space
var MAP_SIZE := 90.0

## Override billboard count for test scene (scaled for larger map)
const TEST_BILLBOARD_COUNT := 600  # More vegetation for larger map


func _ready() -> void:
	print("=== Clearing Test (Billboard Trees) ===")
	print("Testing worker auto-assignment to clear jobs")
	print("")

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
		"name": "Clearing Test",
		"size": MAP_SIZE,
		"seed": 42,
		"add_camera": true,
		"camera_position": Vector3(map_center, 70, map_center + 40),  # Higher camera for hilly terrain
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
	_setup_area_preview()
	_setup_grid_overlay()
	_setup_build_menu()

	# Create simple HUD
	hud = TestSceneBase.make_hud(self)

	# Disable SelectionManager to prevent blue box interference
	var sel_mgr = get_node_or_null("/root/SelectionManager")
	if sel_mgr:
		sel_mgr.set_process_input(false)
		print("[ClearingTest] Disabled SelectionManager input")

	# Spawn initial workers at center of map
	_spawn_engineer(Vector3(map_center - 3, 0, map_center))
	_spawn_bulldozer(Vector3(map_center + 3, 0, map_center))

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

	print("")
	print("Controls:")
	print("  WASD: Pan camera | Mouse wheel: Zoom | Middle drag: Rotate")
	print("  Left-click + drag: Paint clear area")
	print("  B: Open build menu | R: Rotate building")
	print("  E: Spawn engineer | Shift+B: Spawn bulldozer")
	print("  G: Toggle grid | T: Toggle 3D trees")
	print("  ESC/Right-click: Cancel placement")
	print("")
	print("Terrain Deformation:")
	print("  X: Create crater | Z: Raise terrain (mound)")
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
		# Use STEEP_MOUNTAINS preset for dramatic hills and valleys
		terrain_engine.set_preset(terrain_engine.TerrainPreset.STEEP_MOUNTAINS)
		# Boost settings for small maps (more variation in less space)
		terrain_engine.set_param("ridge_blend", 0.5)
		terrain_engine.set_param("warp_strength", 60.0)
		terrain_engine.set_param("base_frequency", 0.006)  # Higher freq = more variation in small area
		print("[ClearingTest] TerrainEngine configured: STEEP_MOUNTAINS preset")

	# Create TerrainManager with small map settings
	local_terrain = TerrainManager.new()
	local_terrain.name = "LocalTerrain"
	local_terrain.map_size = MAP_SIZE
	local_terrain.chunk_size = chunk_size  # 64m chunks = 4 chunks for 128m map
	local_terrain.cell_size = 2.0
	local_terrain.height_scale = 60.0  # Taller hills for more dramatic terrain
	local_terrain.rivers_enabled = false  # No rivers for fast generation
	local_terrain.load_distance = 3
	local_terrain.unload_distance = 4
	add_child(local_terrain)

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


## Initialize terrain grid with jungle type for testing clearing
func _initialize_terrain_grid(grid) -> void:
	if not grid or not grid.has_method("set_terrain_type"):
		return

	# Set all cells to HEAVY_JUNGLE initially (requires clearing)
	# set_terrain_type takes world_pos: Vector3, not grid coords
	var cell_size: float = GridCoordsClass.GAMEPLAY_CELL_SIZE
	var cell_count: int = int(ceil(MAP_SIZE / cell_size))
	for x in range(cell_count):
		for z in range(cell_count):
			var world_pos := Vector3((x + 0.5) * cell_size, 0.0, (z + 0.5) * cell_size)
			grid.set_terrain_type(world_pos, TerrainTypes.Type.HEAVY_JUNGLE)

	print("[ClearingTest] Initialized %dx%d terrain grid with HEAVY_JUNGLE" % [cell_count, cell_count])


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

	# CRITICAL: Wire terrain_grid for clearing stage checks (billboard removal)
	if terrain_intg and terrain_intg.terrain_grid:
		billboard_vegetation.set_terrain_grid(terrain_intg.terrain_grid)
		print("[ClearingTest] Wired terrain_grid to billboard_vegetation for clearing")

	# CRITICAL: Set low billboard count BEFORE adding to tree (before _ready)
	billboard_vegetation.billboards_per_chunk = TEST_BILLBOARD_COUNT
	print("[ClearingTest] Billboard count set to %d (was 4500)" % TEST_BILLBOARD_COUNT)

	add_child(billboard_vegetation)

	# Disable LOD updates - we'll manually control visibility in this test
	# This prevents flashing when camera is at the LOD threshold distance
	billboard_vegetation.set_process(false)

	# Generate terrain types for all chunks covering the play area
	for chunk_coord in VEG_CHUNKS:
		# Skip 3D tree generation - just create terrain type data directly
		var bundles_per_side: int = int(chunk_size / vegetation_manager.bundle_meters)
		var terrain_data := PackedByteArray()
		terrain_data.resize(bundles_per_side * bundles_per_side)
		terrain_data.fill(VegetationManager.TerrainType.HEAVY_JUNGLE)
		vegetation_manager._chunk_terrain[chunk_coord] = terrain_data
		print("[ClearingTest] Created %d bundles for chunk %s (no 3D trees)" % [terrain_data.size(), chunk_coord])

		# Generate billboards using terrain data
		billboard_vegetation.generate_for_chunk(chunk_coord, heightmap_to_use, terrain_data)

	# Force all billboards visible (since LOD is disabled)
	for chunk_coord in VEG_CHUNKS:
		if billboard_vegetation._chunk_billboards.has(chunk_coord):
			var container: Node3D = billboard_vegetation._chunk_billboards[chunk_coord]
			if container:
				container.visible = true

	var terrain_source: String = "local TerrainManager" if local_terrain else ("TerrainIntegration" if using_real_terrain else "mock flat")
	print("[ClearingTest] Billboard vegetation generated for %d chunks (terrain: %s)" % [
		VEG_CHUNKS.size(), terrain_source
	])


## Setup 3D jungle trees using ONLY light tree model
## Density is controlled by tree COUNT (more trees in denser areas)
## This makes clearing feel like "chipping away" at the jungle
func _setup_3d_trees() -> void:
	tree_container = Node3D.new()
	tree_container.name = "TreeNodes3D"
	add_child(tree_container)

	# Spawn 3D trees across the map - use only JUNGLE_LIGHT model
	# Density controlled by spawn multiplier based on terrain type
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345  # Consistent placement

	var tree_count := 0
	var area := MAP_SIZE * MAP_SIZE
	var base_target_trees := int(area * TREE_DENSITY)

	print("[ClearingTest] Spawning jungle trees (light model only, density by count)...")

	# Generate more positions than needed, then filter based on density multiplier
	var max_attempts := base_target_trees * 4  # Try more positions for denser areas

	for _i in range(max_attempts):
		var pos := Vector3(
			rng.randf_range(5.0, MAP_SIZE - 5.0),
			0.0,
			rng.randf_range(5.0, MAP_SIZE - 5.0)
		)

		# Get terrain height
		pos.y = _get_terrain_height(pos.x, pos.z)

		# Get terrain type at position
		var terrain_type: int = TerrainTypes.Type.HEAVY_JUNGLE  # Default
		if terrain_intg and terrain_intg.terrain_grid:
			terrain_type = terrain_intg.terrain_grid.get_terrain_type(pos)

		# Skip cleared areas
		if terrain_type <= TerrainTypes.Type.GRASSLAND:
			continue

		# Density multiplier - determines spawn chance
		# More trees in denser jungle areas (controlled by probability)
		var density_multiplier: float
		match terrain_type:
			TerrainTypes.Type.LIGHT_JUNGLE:
				density_multiplier = 0.3   # 30% spawn chance - sparse
			TerrainTypes.Type.MEDIUM_JUNGLE:
				density_multiplier = 0.6   # 60% spawn chance - moderate
			TerrainTypes.Type.HEAVY_JUNGLE:
				density_multiplier = 1.0   # 100% spawn chance - dense
			_:
				density_multiplier = 0.0   # No trees in cleared areas

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
	print("[ClearingTest] Spawned %d light trees (density by count, T to toggle)" % tree_count)


func _set_chunk_heavy_jungle(chunk_coord: Vector2i) -> void:
	if vegetation_manager._chunk_terrain.has(chunk_coord):
		var terrain: PackedByteArray = vegetation_manager._chunk_terrain[chunk_coord]
		for i in range(terrain.size()):
			terrain[i] = VegetationManager.TerrainType.HEAVY_JUNGLE
		vegetation_manager._chunk_terrain[chunk_coord] = terrain
		print("[ClearingTest] Set all bundles to HEAVY_JUNGLE")


func _setup_area_preview() -> void:
	# Main blueprint ghost for clearing/building preview
	blueprint_ghost = BlueprintGhostClass.create_rectangle(Vector3(8, 2, 8))
	blueprint_ghost.name = "BlueprintGhost"
	add_child(blueprint_ghost)

	# Road ghost for line-based construction
	road_ghost = BlueprintGhostClass.create_line(4.0)
	road_ghost.name = "RoadGhost"
	add_child(road_ghost)

	# Fortification ghost for trench/wire line painting
	fort_ghost = BlueprintGhostClass.create_line(2.0)
	fort_ghost.name = "FortGhost"
	add_child(fort_ghost)

	# Wire local terrain to all ghosts for terrain-conforming visuals (alpha polish)
	if local_terrain:
		blueprint_ghost.set_terrain(local_terrain)
		road_ghost.set_terrain(local_terrain)
		fort_ghost.set_terrain(local_terrain)
		print("[ClearingTest] Blueprint ghosts wired to local terrain for conforming")

	print("[ClearingTest] Blueprint ghosts created (rectangle + 2 lines)")


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


## Setup build menu popup (RTS-style building selection)
func _setup_build_menu() -> void:
	build_menu = BuildMenuPopupClass.new()
	build_menu.name = "BuildMenuPopup"

	# Add to CanvasLayer so it's always on top
	var canvas := CanvasLayer.new()
	canvas.name = "BuildMenuCanvas"
	canvas.layer = 10
	add_child(canvas)
	canvas.add_child(build_menu)

	# Connect signals
	build_menu.building_selected.connect(_on_build_menu_building_selected)
	build_menu.menu_closed.connect(_on_build_menu_closed)

	print("[ClearingTest] Build menu created (B to open)")


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

		# Vertical lines (along Z) - sample height at each segment
		for x in range(bundles_per_side + 1):
			var world_x: float = chunk_offset_x + x * bundle_size
			for z in range(bundles_per_side):
				var z0: float = chunk_offset_z + z * bundle_size
				var z1: float = chunk_offset_z + (z + 1) * bundle_size
				var y0: float = _get_terrain_height(world_x, z0) + height_offset
				var y1: float = _get_terrain_height(world_x, z1) + height_offset
				im.surface_set_color(line_color)
				im.surface_add_vertex(Vector3(world_x, y0, z0))
				im.surface_add_vertex(Vector3(world_x, y1, z1))

		# Horizontal lines (along X) - sample height at each segment
		for z in range(bundles_per_side + 1):
			var world_z: float = chunk_offset_z + z * bundle_size
			for x in range(bundles_per_side):
				var x0: float = chunk_offset_x + x * bundle_size
				var x1: float = chunk_offset_x + (x + 1) * bundle_size
				var y0: float = _get_terrain_height(x0, world_z) + height_offset
				var y1: float = _get_terrain_height(x1, world_z) + height_offset
				im.surface_set_color(line_color)
				im.surface_add_vertex(Vector3(x0, y0, world_z))
				im.surface_add_vertex(Vector3(x1, y1, world_z))

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

				# Quad corners with terrain-conforming heights
				var x0: float = chunk_offset_x + bx * bundle_size
				var x1: float = chunk_offset_x + (bx + 1) * bundle_size
				var z0: float = chunk_offset_z + bz * bundle_size
				var z1: float = chunk_offset_z + (bz + 1) * bundle_size

				var y00: float = _get_terrain_height(x0, z0) + fill_offset
				var y10: float = _get_terrain_height(x1, z0) + fill_offset
				var y01: float = _get_terrain_height(x0, z1) + fill_offset
				var y11: float = _get_terrain_height(x1, z1) + fill_offset

				# Two triangles for quad (terrain-conforming)
				im.surface_set_color(cell_color)
				im.surface_add_vertex(Vector3(x0, y00, z0))
				im.surface_add_vertex(Vector3(x1, y10, z0))
				im.surface_add_vertex(Vector3(x1, y11, z1))

				im.surface_add_vertex(Vector3(x0, y00, z0))
				im.surface_add_vertex(Vector3(x1, y11, z1))
				im.surface_add_vertex(Vector3(x0, y01, z1))

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
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_handle_mouse_button(mb)

	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)

	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed:
			_handle_key(key)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var cursor_pos := _raycast_ground(event.position)

	# Update building ghost position in PLACE_BUILDING mode
	if current_mode == CommandMode.PLACE_BUILDING and building_ghost:
		if cursor_pos != Vector3.INF:
			building_ghost.update_position(cursor_pos)
			building_ghost.rotation.y = placement_rotation
			# Update validity color
			var is_valid := _check_placement_validity(cursor_pos)
			if is_valid:
				building_ghost.set_placement_state(BlueprintGhostClass.PlacementState.VALID)
			else:
				building_ghost.set_placement_state(BlueprintGhostClass.PlacementState.INVALID)

	# Update clearing preview during painting
	elif is_painting and current_mode == CommandMode.PAINT_CLEAR:
		paint_current = cursor_pos
		_update_area_preview()

	# Update road preview in road mode
	elif current_mode == CommandMode.ROAD_MODE:
		if cursor_pos != Vector3.INF and road_ghost:
			var preview_points := road_points.duplicate()
			preview_points.append(cursor_pos)
			if preview_points.size() >= 2:
				road_ghost.set_line_points(preview_points)

	# Update fortification preview during drag
	elif current_mode == CommandMode.FORT_MODE and fort_line_start != Vector3.INF:
		fort_line_end = cursor_pos
		if fort_line_end != Vector3.INF and fort_ghost:
			var preview_points := PackedVector3Array()
			preview_points.append(fort_line_start)
			preview_points.append(fort_line_end)
			fort_ghost.set_line_points(preview_points)
			# Color based on length
			var line_length := Vector2(fort_line_end.x - fort_line_start.x, fort_line_end.z - fort_line_start.z).length()
			if line_length >= 2.0:
				fort_ghost.set_placement_state(BlueprintGhostClass.PlacementState.VALID)
			else:
				fort_ghost.set_placement_state(BlueprintGhostClass.PlacementState.WARNING)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	var cursor_pos := _raycast_ground(event.position)

	# Handle building placement mode
	if current_mode == CommandMode.PLACE_BUILDING:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if cursor_pos != Vector3.INF:
				_try_place_building(cursor_pos)
			return
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_placement()
			return

	# Handle road mode clicks
	if current_mode == CommandMode.ROAD_MODE:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if cursor_pos != Vector3.INF:
				_handle_road_click(cursor_pos, false)
			return
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_road_click(Vector3.ZERO, true)  # Finish road
			return

	# Handle fortification line-painting mode (trenches, wire)
	if current_mode == CommandMode.FORT_MODE:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Start line painting
				if cursor_pos != Vector3.INF:
					fort_line_start = cursor_pos
					fort_line_end = cursor_pos
					if fort_ghost:
						fort_ghost.show_ghost()
			else:
				# Release - create the job with rotation
				if fort_line_start != Vector3.INF and fort_line_end != Vector3.INF:
					var line_vec := fort_line_end - fort_line_start
					var line_length := Vector2(line_vec.x, line_vec.z).length()
					if line_length >= 2.0:  # Minimum length
						var center := (fort_line_start + fort_line_end) * 0.5
						var rotation_y := atan2(line_vec.x, line_vec.z)
						_create_fortification_job(center, line_length, rotation_y)
				fort_line_start = Vector3.INF
				fort_line_end = Vector3.INF
				if fort_ghost:
					fort_ghost.hide_ghost()
			return
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Cancel fortification mode
			_exit_fort_mode()
			return

	# Default: clearing paint mode
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			paint_start = cursor_pos
			paint_current = paint_start
			is_painting = true
			if blueprint_ghost:
				blueprint_ghost.show_ghost()
		else:
			if is_painting and paint_start != Vector3.INF:
				_create_clear_job(paint_start, paint_current)
			is_painting = false
			if blueprint_ghost:
				blueprint_ghost.hide_ghost()

	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		is_painting = false
		if blueprint_ghost:
			blueprint_ghost.hide_ghost()

		# Try to cancel construction at click position
		_try_cancel_construction(event.position)


func _handle_key(event: InputEventKey) -> void:
	var cursor_pos := _raycast_ground(get_viewport().get_mouse_position())

	match event.keycode:
		KEY_ESCAPE:
			# Cancel any active mode
			if build_menu and build_menu.visible:
				build_menu.close_menu()
			elif current_mode != CommandMode.PAINT_CLEAR:
				_cancel_placement()

		KEY_B:
			if event.shift_pressed:
				# Shift+B: Spawn bulldozer
				if cursor_pos != Vector3.INF:
					_spawn_bulldozer(cursor_pos)
			else:
				# B: Open build menu
				if build_menu:
					if build_menu.visible:
						build_menu.close_menu()
					else:
						build_menu.open_menu(current_supply)

		KEY_E:
			if cursor_pos != Vector3.INF:
				if event.shift_pressed:
					# Spawn 5 engineers in a spread
					for i in 5:
						var offset := Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
						_spawn_engineer(cursor_pos + offset)
					print("[ClearingTest] Spawned 5 engineers")
				else:
					_spawn_engineer(cursor_pos)

		KEY_R:
			# Rotate building preview
			if current_mode == CommandMode.PLACE_BUILDING:
				placement_rotation += PI / 2.0
				if placement_rotation >= TAU:
					placement_rotation = 0.0
				print("[ClearingTest] Rotation: %.0f deg" % rad_to_deg(placement_rotation))

		KEY_G:
			grid_visible = not grid_visible
			if grid_overlay:
				grid_overlay.visible = grid_visible
			print("[ClearingTest] Grid overlay: %s" % ("ON" if grid_visible else "OFF"))

		KEY_T:
			trees_visible = not trees_visible
			if tree_container:
				tree_container.visible = trees_visible
			print("[ClearingTest] 3D Trees: %s" % ("ON" if trees_visible else "OFF"))

		KEY_F:  # Flatten area at cursor
			if cursor_pos != Vector3.INF:
				_create_flatten_job(cursor_pos)

		KEY_Y:  # Toggle trench line-painting mode
			_toggle_fort_mode(FortType.TRENCH)

		KEY_W:  # Toggle wire line-painting mode
			_toggle_fort_mode(FortType.WIRE)

		KEY_X:  # Create crater at cursor (terrain deformation!)
			if cursor_pos != Vector3.INF:
				_create_crater(cursor_pos)

		KEY_Z:  # Raise terrain at cursor
			if cursor_pos != Vector3.INF:
				_raise_terrain(cursor_pos)


func _raycast_ground(screen_pos: Vector2) -> Vector3:
	if not camera:
		return Vector3.INF

	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)

	var space: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		ray_origin, ray_origin + ray_dir * 500.0
	)
	query.collision_mask = 1

	var result: Dictionary = space.intersect_ray(query)
	if not result.is_empty() and result.has("position"):
		return result["position"] as Vector3

	if ray_dir.y != 0:
		var t: float = -ray_origin.y / ray_dir.y
		if t > 0:
			return ray_origin + ray_dir * t

	return Vector3.INF


func _try_cancel_construction(screen_pos: Vector2) -> void:
	"""Try to cancel a construction job at the clicked position"""
	var cursor_pos := _raycast_ground(screen_pos)
	if cursor_pos == Vector3.INF:
		return

	# Find construction sites near the click
	var closest_site: Node3D = null
	var closest_dist: float = 5.0  # Max click distance in meters

	for site in get_tree().get_nodes_in_group("construction_sites"):
		if not is_instance_valid(site):
			continue
		var dist: float = site.global_position.distance_to(cursor_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest_site = site

	if closest_site:
		# Find and cancel the associated job
		var job_system = get_node_or_null("/root/JobSystem")
		if job_system:
			# Search for the job that owns this construction site
			var cancelled := false
			for job in job_system.jobs.values():
				if not is_instance_valid(job):
					continue
				var job_node: Node = job.metadata.get("job_node")
				if job_node == closest_site:
					job_system.cancel_job(job)
					print("[ClearingTest] Cancelled construction job #%d via right-click" % job.job_id)
					cancelled = true
					break

			if not cancelled:
				# Fallback: directly cancel the site
				if closest_site.has_method("cancel"):
					closest_site.cancel()
					print("[ClearingTest] Cancelled construction site directly (no job found)")


func _update_area_preview() -> void:
	if paint_start == Vector3.INF or paint_current == Vector3.INF:
		return

	var min_x: float = minf(paint_start.x, paint_current.x)
	var max_x: float = maxf(paint_start.x, paint_current.x)
	var min_z: float = minf(paint_start.z, paint_current.z)
	var max_z: float = maxf(paint_start.z, paint_current.z)

	var size_x: float = maxf(max_x - min_x, 1.0)
	var size_z: float = maxf(max_z - min_z, 1.0)

	# Update blueprint ghost size and position
	if blueprint_ghost:
		var center := Vector3((min_x + max_x) * 0.5, 0.0, (min_z + max_z) * 0.5)
		blueprint_ghost.set_size(Vector3(size_x, 2.0, size_z))
		blueprint_ghost.update_position(center)

		# Check if placement is valid (size check)
		if size_x >= 2.0 and size_z >= 2.0:
			blueprint_ghost.set_placement_state(BlueprintGhostClass.PlacementState.VALID)
		else:
			blueprint_ghost.set_placement_state(BlueprintGhostClass.PlacementState.WARNING)


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

	print("[ClearingTest] Clearing detected in region %s - regenerating billboards and removing 3D trees" % region)

	var heightmap_to_use = _get_heightmap_or_mock()

	# Convert region to world coordinates (TerrainGrid uses 4m cells)
	var cell_size: float = 4.0
	var region_min_x: float = region.position.x * cell_size
	var region_min_z: float = region.position.y * cell_size
	var region_max_x: float = (region.position.x + region.size.x) * cell_size
	var region_max_z: float = (region.position.y + region.size.y) * cell_size

	# Remove 3D trees in the cleared region
	var trees_removed := 0
	var trees_to_remove: Array[Node3D] = []
	for tree in tree_nodes:
		if not is_instance_valid(tree):
			continue
		var pos: Vector3 = tree.global_position
		if pos.x >= region_min_x and pos.x <= region_max_x:
			if pos.z >= region_min_z and pos.z <= region_max_z:
				trees_to_remove.append(tree)

	for tree in trees_to_remove:
		tree_nodes.erase(tree)
		# Animate tree falling before removing
		if tree.has_method("_start_clear"):
			tree._start_clear()
		else:
			tree.queue_free()
		trees_removed += 1

	if trees_removed > 0:
		print("[ClearingTest] Removed %d 3D trees in cleared area" % trees_removed)

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

	# Force visibility
	_force_billboard_visibility()

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
		# Force visibility
		_force_billboard_visibility()

		# Rebuild grid overlay to show cleared areas
		_rebuild_grid_overlay()

		print("[ClearingTest] Cleared %d vegetation bundles" % total_cleared)


func _force_billboard_visibility() -> void:
	# Force billboards visible regardless of LOD distance
	if not billboard_vegetation:
		return
	for chunk_coord in VEG_CHUNKS:
		if billboard_vegetation._chunk_billboards.has(chunk_coord):
			var container: Node3D = billboard_vegetation._chunk_billboards[chunk_coord]
			if is_instance_valid(container):
				container.visible = true


func _process(_delta: float) -> void:
	# Force billboards visible (override LOD)
	_force_billboard_visibility()

	_update_hud()


func _update_hud() -> void:
	if not hud:
		return

	var job_system = get_node_or_null("/root/JobSystem")

	var text := "=== Clearing Test (RTS Building) ===\n"
	text += "Workers: %d | Supply: %d\n" % [workers.size(), current_supply]

	var engineers := 0
	var bulldozers := 0
	for w in workers:
		if w.data and w.data.is_vehicle:
			bulldozers += 1
		else:
			engineers += 1
	text += "  Engineers: %d, Bulldozers: %d\n" % [engineers, bulldozers]

	# Show current mode
	var mode_str: String
	match current_mode:
		CommandMode.PAINT_CLEAR:
			mode_str = "PAINT CLEAR"
		CommandMode.PLACE_BUILDING:
			mode_str = "PLACE: %s" % selected_building_key
		CommandMode.ROAD_MODE:
			mode_str = "ROAD (%d pts)" % road_points.size()
		CommandMode.FORT_MODE:
			var fort_str := "TRENCH" if fort_type == FortType.TRENCH else "WIRE"
			mode_str = "%s LINE" % fort_str
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
	text += "3D Trees: %d (%s) | Grid: %s\n" % [
		tree_nodes.size(),
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

	if is_painting:
		var size_x: float = absf(paint_current.x - paint_start.x)
		var size_z: float = absf(paint_current.z - paint_start.z)
		text += "\nPainting: %.1f x %.1f m" % [size_x, size_z]

	# Controls reminder
	text += "\n\nControls:"
	text += "\n  B=Build menu | R=Rotate | ESC=Cancel"
	text += "\n  E=Engineer | Shift+B=Bulldozer"
	text += "\n  X=Crater | Z=Mound | G=Grid | T=Trees"

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
## BUILD MENU INTEGRATION (RTS-STYLE)
## =============================================================================

func _on_build_menu_building_selected(building_key: String, placement_mode: int) -> void:
	"""Handle building selection from build menu"""
	print("[ClearingTest] Build menu selected: %s (mode %d)" % [building_key, placement_mode])

	# Get building entry from menu
	var entry = build_menu.get_building(building_key)
	if not entry:
		print("[ClearingTest] Unknown building: %s" % building_key)
		return

	# Check if we can afford it
	if entry.supply_cost > current_supply:
		print("[ClearingTest] Cannot afford %s (need %d, have %d)" % [
			entry.display_name, entry.supply_cost, current_supply])
		return

	# Store selection
	selected_building_key = building_key
	selected_building_type = entry.building_type
	placement_rotation = 0.0

	# Get building data for footprint size
	if entry.building_type >= 0:
		current_building_data = BuildingDataClass.get_building_data(entry.building_type)
	else:
		current_building_data = null

	# Create ghost preview
	_create_building_ghost(entry)

	# Enter placement mode
	current_mode = CommandMode.PLACE_BUILDING
	print("[ClearingTest] Placement mode: %s (cost: %d)" % [entry.display_name, entry.supply_cost])


func _on_build_menu_closed() -> void:
	"""Handle build menu being closed without selection"""
	print("[ClearingTest] Build menu closed")


func _create_building_ghost(entry) -> void:
	"""Create ghost preview for building placement"""
	# Clear any existing ghost
	if building_ghost:
		building_ghost.queue_free()
		building_ghost = null

	# Get footprint size
	var footprint_size := Vector2(4.0, 4.0)
	var building_height := 2.0

	if current_building_data:
		footprint_size = current_building_data.footprint_size
		building_height = current_building_data.height

	# Create ghost based on placement mode
	match entry.placement_mode:
		BuildMenuPopupClass.PlacementMode.SINGLE:
			building_ghost = BlueprintGhostClass.create_rectangle(
				Vector3(footprint_size.x, building_height, footprint_size.y))

		BuildMenuPopupClass.PlacementMode.PAINTABLE:
			# Line-based (sandbags, trenches)
			building_ghost = BlueprintGhostClass.create_line(2.0)

		BuildMenuPopupClass.PlacementMode.PAINTABLE_SPACED:
			# Spaced placement (wire, tank traps)
			building_ghost = BlueprintGhostClass.create_line(entry.spacing if entry.spacing > 0 else 2.0)

	if building_ghost:
		building_ghost.name = "BuildingGhost"
		add_child(building_ghost)
		# Wire local terrain for terrain-conforming ghost (alpha polish)
		if local_terrain:
			building_ghost.set_terrain(local_terrain)
		# Set initial position to current mouse location to avoid interpolation lag
		var initial_pos := _raycast_ground(get_viewport().get_mouse_position())
		if initial_pos != Vector3.INF:
			building_ghost.global_position = initial_pos
			building_ghost.update_position(initial_pos)
		building_ghost.show_ghost()


func _check_placement_validity(position: Vector3) -> bool:
	"""Check if building can be placed at position"""
	if not current_building_data:
		return true  # No data = no restrictions

	var job_system = get_node_or_null("/root/JobSystem")
	if not job_system:
		return true

	# Use JobSystem's placement validation
	var footprint_size := current_building_data.footprint_size
	var validation: Dictionary = job_system.validate_placement(position, footprint_size, selected_building_type)

	return validation.valid


func _try_place_building(position: Vector3) -> void:
	"""Attempt to place building at position"""
	if selected_building_key.is_empty():
		return

	var entry = build_menu.get_building(selected_building_key)
	if not entry:
		return

	# Check affordability again (in case supply changed)
	if entry.supply_cost > current_supply:
		print("[ClearingTest] Cannot afford %s (need %d, have %d)" % [
			entry.display_name, entry.supply_cost, current_supply])
		return

	# Check placement validity
	if not _check_placement_validity(position):
		print("[ClearingTest] Invalid placement location")
		return

	# Create build job via JobSystem (handles prerequisites and supply)
	var job_system = get_node_or_null("/root/JobSystem")
	if not job_system:
		push_warning("[ClearingTest] JobSystem not found")
		return

	var footprint_size := Vector2(4.0, 4.0)
	if current_building_data:
		footprint_size = current_building_data.footprint_size

	# Use create_build_job which handles supply deduction and prerequisites
	var job = job_system.create_build_job(
		position,
		selected_building_type,
		placement_rotation,
		footprint_size,
		true  # skip_validation since we already checked
	)

	if job:
		# Deduct supply locally (JobSystem also deducts from firebase if present)
		# For test scene without firebase, we track supply manually
		current_supply -= entry.supply_cost
		print("[ClearingTest] Placed %s (job #%d), supply: %d remaining" % [
			entry.display_name, job.job_id, current_supply])

		# Update build menu supply display
		if build_menu:
			build_menu.set_supply(current_supply)
	else:
		print("[ClearingTest] Failed to create build job for %s" % entry.display_name)

	# Stay in placement mode for quick successive placements
	# (User can press ESC or right-click to exit)


func _cancel_placement() -> void:
	"""Cancel building placement mode"""
	if building_ghost:
		building_ghost.queue_free()
		building_ghost = null

	selected_building_key = ""
	selected_building_type = -1
	current_building_data = null
	current_mode = CommandMode.PAINT_CLEAR

	# Also cancel fortification mode if active
	_exit_fort_mode()

	# Cancel road mode if active
	if current_mode == CommandMode.ROAD_MODE:
		road_points.clear()
		if road_ghost:
			road_ghost.hide_ghost()

	print("[ClearingTest] Placement cancelled, back to clear mode")


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
		print("[ClearingTest] Flatten job created: #%d at %v" % [job.job_id, center])


## Toggle road painting mode
func _toggle_road_mode() -> void:
	if current_mode == CommandMode.ROAD_MODE:
		# Exit road mode
		road_points.clear()
		current_mode = CommandMode.PAINT_CLEAR
		if road_ghost:
			road_ghost.hide_ghost()
		print("[ClearingTest] Road mode: OFF")
	else:
		# Enter road mode
		_cancel_placement()
		current_mode = CommandMode.ROAD_MODE
		road_points.clear()
		if road_ghost:
			road_ghost.show_ghost()
		print("[ClearingTest] Road mode: ON (click points, right-click to finish)")


## Handle road mode clicks
func _handle_road_click(pos: Vector3, finish: bool) -> void:
	if current_mode != CommandMode.ROAD_MODE:
		return

	if finish:
		# Finish road - create job
		if road_points.size() >= 2:
			_create_road_job(road_points)
		road_points.clear()
		current_mode = CommandMode.PAINT_CLEAR
		if road_ghost:
			road_ghost.hide_ghost()
		print("[ClearingTest] Road mode: OFF")
	else:
		# Add point
		road_points.append(pos)
		print("[ClearingTest] Road point %d: %v" % [road_points.size(), pos])

		# Update road ghost with current points
		if road_ghost and road_ghost.has_method("set_line_points"):
			road_ghost.set_line_points(road_points)
			road_ghost.set_placement_state(BlueprintGhostClass.PlacementState.VALID if road_points.size() >= 2 else BlueprintGhostClass.PlacementState.WARNING)


## Create a road job from the collected points
func _create_road_job(points: PackedVector3Array) -> void:
	var job_system = get_node_or_null("/root/JobSystem")
	if not job_system:
		push_warning("[ClearingTest] JobSystem not found")
		return

	if not job_system.has_method("create_road_job"):
		push_warning("[ClearingTest] JobSystem missing create_road_job method")
		return

	var job = job_system.create_road_job(points, 4.0)  # 4m wide road
	if job:
		print("[ClearingTest] Road job created: #%d with %d points" % [job.job_id, points.size()])


## Toggle fortification line-painting mode
func _toggle_fort_mode(type: FortType) -> void:
	# If already in this mode, exit it
	if current_mode == CommandMode.FORT_MODE and fort_type == type:
		_exit_fort_mode()
		return

	# Exit other modes
	_cancel_placement()

	# Enter new mode
	current_mode = CommandMode.FORT_MODE
	fort_type = type
	fort_line_start = Vector3.INF
	fort_line_end = Vector3.INF

	var mode_name: String = "TRENCH" if type == FortType.TRENCH else "WIRE"
	print("[ClearingTest] %s mode: ON (click+drag to paint line, right-click to cancel)" % mode_name)


## Exit fortification mode
func _exit_fort_mode() -> void:
	if current_mode != CommandMode.FORT_MODE:
		return

	var mode_name: String = "TRENCH" if fort_type == FortType.TRENCH else "WIRE"
	current_mode = CommandMode.PAINT_CLEAR
	fort_type = FortType.NONE
	fort_line_start = Vector3.INF
	fort_line_end = Vector3.INF
	if fort_ghost:
		fort_ghost.hide_ghost()
	print("[ClearingTest] %s mode: OFF" % mode_name)


## Create a fortification job from line-painted coordinates
func _create_fortification_job(center: Vector3, length: float, rotation_y: float) -> void:
	var job_system = get_node_or_null("/root/JobSystem")
	if not job_system:
		push_warning("[ClearingTest] JobSystem not found")
		return

	match fort_type:
		FortType.TRENCH:
			if not job_system.has_method("create_trench_job"):
				push_warning("[ClearingTest] JobSystem missing create_trench_job method")
				return
			# Pass rotation_y to create_trench_job for proper oriented prerequisites
			var job = job_system.create_trench_job(center, length, 2.0, rotation_y)
			if job:
				print("[ClearingTest] Trench job created: #%d, %.1fm long at angle %.1f deg" % [
					job.job_id, length, rad_to_deg(rotation_y)
				])

		FortType.WIRE:
			if not job_system.has_method("create_wire_job"):
				push_warning("[ClearingTest] JobSystem missing create_wire_job method")
				return
			# Pass rotation_y to create_wire_job for proper oriented prerequisites
			var job = job_system.create_wire_job(center, length, 0, 0, rotation_y)
			if job:
				print("[ClearingTest] Wire job created: #%d, %.1fm long at angle %.1f deg" % [
					job.job_id, length, rad_to_deg(rotation_y)
				])


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

	print("[ClearingTest] Creating crater at %v (radius=%.1f, depth=%.1f)" % [center, radius, depth])

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

	print("[ClearingTest] Raising terrain at %v (radius=%.1f, height=%.1f)" % [center, radius, height])

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
