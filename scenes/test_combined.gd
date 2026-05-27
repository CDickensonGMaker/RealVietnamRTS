extends Node3D
## Test Combined - Full game loop testing (clearing, construction, combat)
##
## Default test scene for RealVietnamRTS. Features:
## - HQ prefab structures (gate, TOC, hootches, bunkers)
## - Local 256m terrain with async loading (prevents window freeze)
## - JobSystem/BattleHUD integration
## - Combat units for testing engagement and projectiles

const TerrainTypes = preload("res://terrain/terrain_types.gd")
const UnifiedJobClass = preload("res://firebase_system/job_system/unified_job.gd")
const GridCoordsClass = preload("res://terrain/core/grid_coords.gd")
const TerrainGridClass = preload("res://terrain/core/terrain_grid.gd")
const TreeNodeClass = preload("res://terrain/vegetation/tree_node.gd")
const Squad = preload("res://battle_system/nodes/squad.gd")
const FirebaseClass = preload("res://firebase_system/firebase.gd")

## Mock heightmap for flat terrain fallback
class MockHeightmap:
	var height: float = 0.0
	func sample_world(_x: float, _z: float) -> float:
		return height
	func get_normal_world(_x: float, _z: float) -> Vector3:
		return Vector3.UP

# Map configuration - optimized for fast loading
const MAP_SIZE := 256.0  # 256m map (minimal load time)
const CHUNK_SIZE := 64.0
const CLEARING_RADIUS := 30.0  # Pre-cleared HQ area

# Firebase structure models
const GATE_MODEL := "res://assets/models/structures/firebase/gate_entrance.glb"
const HOOTCH_MODEL := "res://assets/models/structures/firebase/hootch.glb"
const SANDBAG_BUNKER_MODEL := "res://assets/models/structures/firebase/sandbag_bunker.glb"
const TOC_MODEL := "res://assets/models/structures/firebase/toc.glb"
const MG_NEST_MODEL := "res://assets/models/structures/firebase/mg_nest.glb"
const AMMO_BUNKER_MODEL := "res://assets/models/structures/firebase/ammo_bunker.glb"

# Unit data
var us_rifle_data: Resource = preload("res://battle_system/data/units/us_rifle_platoon.tres")
var us_engineer_data: Resource = preload("res://battle_system/data/units/us_engineers.tres")
var us_bulldozer_data: Resource = preload("res://battle_system/data/units/us_bulldozer.tres")
var vc_infantry_data: Resource = preload("res://battle_system/data/units/vc_infantry.tres")

@onready var camera: Camera3D = $RTSCamera

# Terrain systems (local, not 3000m global)
var local_terrain: TerrainManager
var terrain_intg: Node
var mock_heightmap: MockHeightmap

# Vegetation systems
var vegetation_manager: VegetationManager
var billboard_vegetation: BillboardVegetation
var tree_container: Node3D
var tree_nodes: Array[Node3D] = []
var _trees_by_bundle: Dictionary = {}
var VEG_CHUNKS: Array[Vector2i] = []

# HQ structures
var _hq_structures: Array[Node3D] = []
var _hq_center: Vector3 = Vector3.ZERO

# Workers (engineers + bulldozers)
var workers: Array[Node3D] = []

# Debug overlays
var grid_overlay: MeshInstance3D
var grid_visible := false
var trees_visible := true
var hud: Label

# Build menu UI
var build_menu: Control = null
var battle_hud: Node = null

# Billboard settings (minimal for fast load)
const TEST_BILLBOARD_COUNT := 300
const TREE_DENSITY := 0.008

# Loading overlay
var _loading_overlay: ColorRect = null
var _loading_label: Label = null
var _is_loading: bool = false


func _ready() -> void:
	print("========================================")
	print("  TEST COMBINED - Full Game Loop")
	print("  Map: %.0fm x %.0fm (async loading)")
	print("========================================")
	print("")

	# Show loading overlay immediately
	_create_loading_overlay()
	_show_loading("Initializing...")

	# Reset persistent autoload state
	_reset_persistent_state()

	# Build vegetation chunk list
	var chunks_per_side: int = int(ceil(MAP_SIZE / CHUNK_SIZE))
	for cx in range(chunks_per_side):
		for cz in range(chunks_per_side):
			VEG_CHUNKS.append(Vector2i(cx, cz))
	print("[TestCombined] Generated %d vegetation chunks" % VEG_CHUNKS.size())

	# Get autoloads
	terrain_intg = get_node_or_null("/root/TerrainIntegration")
	mock_heightmap = MockHeightmap.new()

	# Disable global terrain vegetation
	if terrain_intg:
		var ti_billboard = terrain_intg.get("billboard_vegetation")
		if ti_billboard and ti_billboard is Node3D:
			ti_billboard.visible = false
			ti_billboard.set_process(false)

	# Calculate map center
	var map_center := MAP_SIZE * 0.5
	_hq_center = Vector3(map_center, 0, map_center)

	# Setup camera with correct bounds
	_setup_camera()

	# Create local terrain (async with frame yields)
	await _setup_local_terrain_async()

	# Get actual terrain height at HQ center
	_hq_center.y = _get_terrain_height(_hq_center.x, _hq_center.z)

	# Setup vegetation
	_setup_vegetation()
	_setup_3d_trees()
	_setup_grid_overlay()

	# Create HUD
	hud = TestSceneBase.make_hud(self) if has_node("/root/TestSceneBase") else _create_simple_hud()

	# Spawn HQ structures
	_create_cleared_hq_area(_hq_center)
	_spawn_hq_structures(_hq_center)

	# Spawn workers (engineers + bulldozers)
	_spawn_workers(_hq_center)

	# Spawn combat units (US + VC)
	_spawn_combat_units(_hq_center)

	# Connect to JobSystem
	var job_system = get_node_or_null("/root/JobSystem")
	if job_system:
		job_system.job_created.connect(_on_job_created)
		job_system.job_completed.connect(_on_job_completed)
		print("[TestCombined] Connected to JobSystem")

	# Connect to ClearingSystem
	var clearing_system = get_node_or_null("/root/ClearingSystem")
	if clearing_system and clearing_system.has_signal("vegetation_updated"):
		clearing_system.vegetation_updated.connect(_on_clearing_vegetation_updated)

	# Setup build menu (works without selecting engineers)
	_setup_build_menu()

	# NOTE: No initial clearing job - user creates jobs via build menu
	# _create_initial_clearing_job()

	# Hide loading overlay - we're ready!
	_hide_loading()

	print("")
	print("=== TEST COMBINED READY ===")
	print("Controls:")
	print("  WASD: Pan camera | Mouse Wheel: Zoom")
	print("  Left Click: Select | Right Click: Move")
	print("  B: Build menu | G: Grid | T: Trees | R: Reload")
	print("")


func _reset_persistent_state() -> void:
	var job_sys := get_node_or_null("/root/JobSystem")
	if job_sys and job_sys.has_method("reset"):
		job_sys.reset()

	var clearing_sys := get_node_or_null("/root/ClearingSystem")
	if clearing_sys and clearing_sys.has_method("clear_all_zones"):
		clearing_sys.clear_all_zones()

	var tree_mgr := get_node_or_null("/root/TreeNodeManager")
	if tree_mgr and tree_mgr.has_method("clear_all_zones"):
		tree_mgr.clear_all_zones()

	var construction_mgr := get_node_or_null("/root/ConstructionManager")
	if construction_mgr and construction_mgr.has_method("reset"):
		construction_mgr.reset()

	for site in get_tree().get_nodes_in_group("construction_sites"):
		if is_instance_valid(site):
			site.queue_free()

	print("[TestCombined] Reset persistent autoload state")


func _setup_camera() -> void:
	if not camera:
		push_warning("[TestCombined] No camera!")
		return

	var map_center := MAP_SIZE * 0.5
	var padding := 100.0

	if camera.has_method("set_map_bounds"):
		camera.set_map_bounds(
			Vector3(-padding, 0, -padding),
			Vector3(MAP_SIZE + padding, 200, MAP_SIZE + padding)
		)

	# Position camera above TOC (TOC is at hq_center + Z offset of 10)
	# Use center_on_position with instant=true to override RTSCamera's internal state
	var toc_pos := Vector3(map_center, 0, map_center + 10)
	if camera.has_method("center_on_position"):
		camera.center_on_position(toc_pos, true)
		print("[TestCombined] Camera centered on TOC at %v" % toc_pos)
	else:
		# Fallback for non-RTSCamera
		camera.position = Vector3(toc_pos.x, 60, toc_pos.z + 40)
		camera.look_at(toc_pos)
		print("[TestCombined] Camera positioned above TOC (fallback)")


func _setup_local_terrain_async() -> void:
	print("[TestCombined] Creating local terrain (%.0fm)..." % MAP_SIZE)
	_show_loading("Creating terrain...")

	var terrain_engine: Node = get_node_or_null("/root/TerrainEngine")
	if terrain_engine:
		terrain_engine.set_preset(terrain_engine.TerrainPreset.ROLLING_HILLS)
		terrain_engine.set_param("ridge_blend", 0.15)
		terrain_engine.set_param("warp_strength", 15.0)
		terrain_engine.set_param("base_frequency", 0.003)

	local_terrain = TerrainManager.new()
	local_terrain.name = "LocalTerrain"
	local_terrain.map_size = MAP_SIZE
	local_terrain.chunk_size = CHUNK_SIZE
	local_terrain.cell_size = 2.0
	local_terrain.height_scale = 30.0  # Gentle hills
	local_terrain.rivers_enabled = false
	local_terrain.load_distance = 3
	local_terrain.unload_distance = 4
	add_child(local_terrain)

	local_terrain.add_to_group("terrain_managers")
	local_terrain.set_camera(camera)

	# Connect to progress signal for loading overlay updates
	local_terrain.generation_progress.connect(_on_terrain_progress)

	# Await async terrain generation (keeps window responsive)
	await local_terrain.generate_terrain(42)

	print("[TestCombined] Local terrain ready: %d chunks" % local_terrain.chunks.size())

	_sync_terrain_with_globals()


func _sync_terrain_with_globals() -> void:
	if terrain_intg and terrain_intg.has_method("reinit_with_terrain"):
		terrain_intg.reinit_with_terrain(local_terrain, MAP_SIZE)
		if terrain_intg.terrain_grid:
			_initialize_terrain_grid(terrain_intg.terrain_grid)
	else:
		GridCoordsClass.init(MAP_SIZE)
		if terrain_intg:
			terrain_intg.terrain_manager = local_terrain
			var new_grid = TerrainGridClass.new(MAP_SIZE)
			terrain_intg.terrain_grid = new_grid
			_initialize_terrain_grid(new_grid)


func _initialize_terrain_grid(grid) -> void:
	if not grid or not grid.has_method("set_terrain_type"):
		return

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.015
	noise.seed = 42

	var cell_size: float = GridCoordsClass.GAMEPLAY_CELL_SIZE
	var cell_count: int = int(ceil(MAP_SIZE / cell_size))
	var map_center: float = MAP_SIZE * 0.5

	for x in range(cell_count):
		for z in range(cell_count):
			var world_x: float = (x + 0.5) * cell_size
			var world_z: float = (z + 0.5) * cell_size
			var world_pos := Vector3(world_x, 0.0, world_z)

			var dist_from_center: float = Vector2(world_x - map_center, world_z - map_center).length()
			var terrain_type: int

			if dist_from_center < CLEARING_RADIUS:
				terrain_type = TerrainTypes.Type.CLEAR
			else:
				var n: float = noise.get_noise_2d(world_x, world_z)
				if n < -0.3:
					terrain_type = TerrainTypes.Type.LIGHT_JUNGLE
				elif n < 0.3:
					terrain_type = TerrainTypes.Type.MEDIUM_JUNGLE
				else:
					terrain_type = TerrainTypes.Type.HEAVY_JUNGLE

			grid.set_terrain_type(world_pos, terrain_type)

	if grid.has_method("mark_area_cleared"):
		var center_pos := Vector3(map_center, 0.0, map_center)
		grid.mark_area_cleared(center_pos, CLEARING_RADIUS)

	print("[TestCombined] Terrain grid initialized with sporadic jungle")


func _setup_vegetation() -> void:
	var heightmap_to_use = _get_heightmap_or_mock()

	vegetation_manager = VegetationManager.new()
	vegetation_manager.name = "VegetationManager"
	vegetation_manager.set_chunk_size(CHUNK_SIZE)
	vegetation_manager.set_camera(camera)
	add_child(vegetation_manager)

	billboard_vegetation = BillboardVegetation.new()
	billboard_vegetation.name = "BillboardVegetation"
	billboard_vegetation.set_chunk_size(CHUNK_SIZE)
	billboard_vegetation.set_camera(camera)
	billboard_vegetation.set_vegetation_manager(vegetation_manager)

	if terrain_intg and terrain_intg.terrain_grid:
		billboard_vegetation.set_terrain_grid(terrain_intg.terrain_grid)

	billboard_vegetation.billboards_per_chunk = TEST_BILLBOARD_COUNT
	billboard_vegetation.billboard_range_min = 80.0
	billboard_vegetation.billboard_range_max = 500.0
	add_child(billboard_vegetation)

	# Generate vegetation for all chunks
	var veg_noise := FastNoiseLite.new()
	veg_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	veg_noise.frequency = 0.015
	veg_noise.seed = 42
	var map_center: float = MAP_SIZE * 0.5

	for chunk_coord in VEG_CHUNKS:
		var bundles_per_side: int = int(CHUNK_SIZE / vegetation_manager.bundle_meters)
		var terrain_data := PackedByteArray()
		terrain_data.resize(bundles_per_side * bundles_per_side)

		var chunk_offset_x: float = chunk_coord.x * CHUNK_SIZE
		var chunk_offset_z: float = chunk_coord.y * CHUNK_SIZE

		for bz in bundles_per_side:
			for bx in bundles_per_side:
				var bundle_idx: int = bz * bundles_per_side + bx
				var world_x: float = chunk_offset_x + (bx + 0.5) * vegetation_manager.bundle_meters
				var world_z: float = chunk_offset_z + (bz + 0.5) * vegetation_manager.bundle_meters
				var dist_from_center: float = Vector2(world_x - map_center, world_z - map_center).length()

				var terrain_type: int
				if dist_from_center < CLEARING_RADIUS:
					terrain_type = VegetationManager.TerrainType.CLEAR
				else:
					var n: float = veg_noise.get_noise_2d(world_x, world_z)
					if n < -0.3:
						terrain_type = VegetationManager.TerrainType.LIGHT_JUNGLE
					elif n < 0.3:
						terrain_type = VegetationManager.TerrainType.MEDIUM_JUNGLE
					else:
						terrain_type = VegetationManager.TerrainType.HEAVY_JUNGLE

				terrain_data[bundle_idx] = terrain_type

		vegetation_manager._chunk_terrain[chunk_coord] = terrain_data
		billboard_vegetation.generate_for_chunk(chunk_coord, heightmap_to_use, terrain_data)

	# Force billboards visible
	for chunk_coord in VEG_CHUNKS:
		if billboard_vegetation._chunk_billboards.has(chunk_coord):
			var container: Node3D = billboard_vegetation._chunk_billboards[chunk_coord]
			if container:
				container.visible = true

	print("[TestCombined] Vegetation setup complete: %d chunks" % VEG_CHUNKS.size())


func _setup_3d_trees() -> void:
	tree_container = Node3D.new()
	tree_container.name = "TreeNodes3D"
	add_child(tree_container)

	var lod_manager := get_node_or_null("/root/VegetationLODManager")
	if lod_manager:
		lod_manager.set_camera(camera)

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	var veg_noise := FastNoiseLite.new()
	veg_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	veg_noise.frequency = 0.015
	veg_noise.seed = 42

	var map_center: float = MAP_SIZE * 0.5
	var tree_count := 0
	var max_attempts := 1500  # Reduced for fast loading

	for _i in range(max_attempts):
		var pos := Vector3(
			rng.randf_range(5.0, MAP_SIZE - 5.0),
			0.0,
			rng.randf_range(5.0, MAP_SIZE - 5.0)
		)
		pos.y = _get_terrain_height(pos.x, pos.z)

		var dist_from_center: float = Vector2(pos.x - map_center, pos.z - map_center).length()
		if dist_from_center < CLEARING_RADIUS:
			continue

		var n: float = veg_noise.get_noise_2d(pos.x, pos.z)
		var density_multiplier: float
		if n < -0.3:
			density_multiplier = 0.25
		elif n < 0.3:
			density_multiplier = 0.55
		else:
			density_multiplier = 0.85

		if rng.randf() > density_multiplier:
			continue

		var base_height := rng.randf_range(5.0, 9.0)
		var tree: Node3D = TreeNodeClass.create(TreeNodeClass.TreeType.JUNGLE_LIGHT, pos, base_height)
		if tree:
			tree.rotation.y = rng.randf() * TAU
			tree_container.add_child(tree)
			tree_nodes.append(tree)
			tree_count += 1

			var bundle_meters: float = vegetation_manager.bundle_meters if vegetation_manager else 8.0
			var bundle_coord := Vector2i(int(pos.x / bundle_meters), int(pos.z / bundle_meters))
			if not _trees_by_bundle.has(bundle_coord):
				_trees_by_bundle[bundle_coord] = []
			_trees_by_bundle[bundle_coord].append(tree)
			tree.set_meta("bundle_coord", bundle_coord)

	tree_container.visible = trees_visible
	print("[TestCombined] Spawned %d trees in %d bundles" % [tree_count, _trees_by_bundle.size()])

	if lod_manager:
		lod_manager.register_trees(tree_nodes)


func _setup_grid_overlay() -> void:
	grid_overlay = MeshInstance3D.new()
	grid_overlay.name = "GridOverlay"
	grid_overlay.visible = grid_visible
	add_child(grid_overlay)
	call_deferred("_rebuild_grid_overlay")


func _create_cleared_hq_area(hq_pos: Vector3) -> void:
	print("[TestCombined] Creating cleared HQ area (radius: %.0fm)" % CLEARING_RADIUS)

	var clearing_sys := get_node_or_null("/root/ClearingSystem")
	if clearing_sys and clearing_sys.has_method("mark_area_cleared"):
		clearing_sys.mark_area_cleared(hq_pos, CLEARING_RADIUS)


func _spawn_hq_structures(hq_pos: Vector3) -> void:
	print("[TestCombined] Spawning HQ structures...")

	# Gate at front
	_spawn_structure(GATE_MODEL, hq_pos + Vector3(0, 0, -25), 0, "HQ_Gate")

	# TOC at center-back - also creates Firebase influence zone
	var toc_position := hq_pos + Vector3(0, 0, 10)
	_spawn_structure(TOC_MODEL, toc_position, 0, "HQ_TOC")
	_create_firebase_at(toc_position, "MainFirebase")

	# Hootches on sides
	_spawn_structure(HOOTCH_MODEL, hq_pos + Vector3(-18, 0, -5), 0, "HQ_Hootch_1")
	_spawn_structure(HOOTCH_MODEL, hq_pos + Vector3(18, 0, -5), 0, "HQ_Hootch_2")

	# Bunkers for defense
	_spawn_structure(SANDBAG_BUNKER_MODEL, hq_pos + Vector3(-15, 0, -18), -45, "HQ_Bunker_1")
	_spawn_structure(SANDBAG_BUNKER_MODEL, hq_pos + Vector3(15, 0, -18), 45, "HQ_Bunker_2")

	# Fix 8: MG nest moved 10m behind gate (was only 3m apart at -28, gate at -25)
	var mg_pos := hq_pos + Vector3(0, 0, -35)
	_spawn_structure(MG_NEST_MODEL, mg_pos, 0, "HQ_MG_Nest")

	# Ammo bunker
	_spawn_structure(AMMO_BUNKER_MODEL, hq_pos + Vector3(-22, 0, 8), 0, "HQ_Ammo")

	print("[TestCombined] Spawned 8 HQ structures (includes TOC)")


func _spawn_structure(model_path: String, pos: Vector3, rotation_deg: float, struct_name: String) -> Node3D:
	pos.y = _get_terrain_height(pos.x, pos.z)

	var structure := Node3D.new()
	structure.name = struct_name
	structure.position = pos
	structure.rotation_degrees.y = rotation_deg

	var model_scene := load(model_path) as PackedScene
	if model_scene:
		var model := model_scene.instantiate()
		structure.add_child(model)
	else:
		# Fallback box
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(4, 2, 4)
		mesh.mesh = box
		mesh.position.y = 1
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.4, 0.3)
		mesh.material_override = mat
		structure.add_child(mesh)
		print("[TestCombined] WARNING: Model not found: %s" % model_path)

	add_child(structure)
	_hq_structures.append(structure)
	return structure


func _create_firebase_at(pos: Vector3, fb_name: String) -> void:
	"""Create a Firebase node at position to provide influence zone for building placement"""
	var firebase := FirebaseClass.new()
	firebase.name = fb_name
	firebase.firebase_name = fb_name
	firebase.position = pos
	firebase.position.y = _get_terrain_height(pos.x, pos.z)
	firebase.influence_radius = 168.0  # Match TOC building data (168m = 20% less than original 210m)
	firebase._is_active = true  # Pre-activate for testing (normally set by HQ completion)
	add_child(firebase)
	print("[TestCombined] Created Firebase '%s' at %v with %.0fm influence radius (active=%s)" % [
		fb_name, pos, firebase.influence_radius, firebase._is_active
	])


func _spawn_workers(hq_pos: Vector3) -> void:
	print("[TestCombined] Spawning workers...")

	# Engineers near HQ
	for i in range(2):
		var offset_x: float = (i - 0.5) * 4.0
		_spawn_squad(us_engineer_data, hq_pos + Vector3(offset_x, 0, -35), "US_Engineer_%d" % (i + 1))

	# Bulldozers
	for i in range(2):
		var offset_x: float = (i - 0.5) * 6.0
		_spawn_squad(us_bulldozer_data, hq_pos + Vector3(offset_x + 20, 0, -5), "US_Bulldozer_%d" % (i + 1))

	print("[TestCombined] Spawned 2 Engineers + 2 Bulldozers")


func _spawn_combat_units(hq_pos: Vector3) -> void:
	print("[TestCombined] Spawning combat units...")

	# US rifle platoons near HQ (defensive positions)
	_spawn_squad(us_rifle_data, hq_pos + Vector3(-15, 0, -35), "US_Rifle_1")
	_spawn_squad(us_rifle_data, hq_pos + Vector3(15, 0, -35), "US_Rifle_2")

	# VC forces - 70m away for 256m map
	var enemy_offset := 70.0
	var enemy_pos := hq_pos + Vector3(0, 0, enemy_offset)
	enemy_pos.y = _get_terrain_height(enemy_pos.x, enemy_pos.z)

	_spawn_squad(vc_infantry_data, enemy_pos + Vector3(-10, 0, 0), "VC_Squad_1")
	_spawn_squad(vc_infantry_data, enemy_pos + Vector3(10, 0, 0), "VC_Squad_2")

	print("[TestCombined] Spawned 2 US Rifle + 2 VC Infantry (70m apart)")


func _spawn_squad(squad_data: Resource, spawn_pos: Vector3, unit_name: String) -> Squad:
	spawn_pos.y = _get_terrain_height(spawn_pos.x, spawn_pos.z)

	var squad := Squad.new()
	squad.name = unit_name
	squad.data = squad_data
	squad.position = spawn_pos

	add_child(squad)

	# Track workers
	if squad_data == us_engineer_data or squad_data == us_bulldozer_data:
		workers.append(squad)

	var faction: int = squad_data.faction if squad_data else GameEnums.Faction.US_ARMY
	BattleSignals.unit_spawned.emit(squad, faction)

	return squad


func _setup_build_menu() -> void:
	## Setup build menu UI - accessible via B key without selecting engineers
	# Try to use BattleHUD autoload first
	battle_hud = get_node_or_null("/root/BattleHUD")
	if battle_hud:
		print("[TestCombined] Using BattleHUD autoload for build menu")
		return

	# Create local build menu popup if no BattleHUD
	var BuildMenuPopupScript = preload("res://battle_system/ui/build_menu_popup.gd")
	build_menu = BuildMenuPopupScript.new()
	build_menu.name = "BuildMenuPopup"
	build_menu.visible = false

	# Add to a canvas layer for proper UI rendering
	var canvas := CanvasLayer.new()
	canvas.name = "BuildMenuLayer"
	canvas.layer = 100  # Above other UI
	add_child(canvas)
	canvas.add_child(build_menu)

	# Connect building selection signal
	if build_menu.has_signal("building_selected"):
		build_menu.building_selected.connect(_on_building_selected)

	print("[TestCombined] Created local build menu (B to open)")


func _on_building_selected(building_key: String, placement_mode: int) -> void:
	## Handle building selection from build menu
	var job_system = get_node_or_null("/root/JobSystem")
	if not job_system:
		print("[TestCombined] JobSystem not found")
		return

	# Get building entry for metadata
	var entry = build_menu.get_building(building_key) if build_menu else null
	if not entry:
		print("[TestCombined] Building entry not found: %s" % building_key)
		return

	# For now, create a build job at a default position near HQ
	# In a full implementation, this would enter placement mode
	var build_pos := _hq_center + Vector3(30.0, 0.0, 30.0)
	build_pos.y = _get_terrain_height(build_pos.x, build_pos.z)

	if entry.building_type >= 0:
		var job = job_system.create_build_job(
			build_pos,
			entry.building_type,
			0.0,
			Vector2(6.0, 6.0),
			true  # skip_validation for testing
		)
		if job:
			print("[TestCombined] Created build job for %s at %v" % [building_key, build_pos])
		else:
			print("[TestCombined] Failed to create build job for %s" % building_key)


func _open_build_menu() -> void:
	## Open the build menu - works without selecting engineers
	if battle_hud and battle_hud.has_method("open_build_menu"):
		battle_hud.open_build_menu()
		return

	if build_menu:
		var supply_mgr = get_node_or_null("/root/SupplyManager")
		var supply: int = 1000
		if supply_mgr and supply_mgr.has_method("get_global_supply"):
			supply = int(supply_mgr.get_global_supply())
		build_menu.open_menu(supply)
		print("[TestCombined] Build menu opened with %d supply" % supply)


func _create_initial_clearing_job() -> void:
	var job_system = get_node_or_null("/root/JobSystem")
	if not job_system:
		return

	var map_center := MAP_SIZE * 0.5
	# Place clearing job in jungle (outside HQ clearing radius)
	var job_center := Vector3(map_center + 40.0, 0.0, map_center - 40.0)
	job_center.y = _get_terrain_height(job_center.x, job_center.z)

	var job = job_system.create_job(
		UnifiedJobClass.Type.CLEAR_TERRAIN,
		job_center,
		Vector2(15.0, 15.0)  # 15x15m clearing area
	)

	if job:
		print("[TestCombined] Initial clearing job #%d at %v (15x15m)" % [job.job_id, job_center])


func _on_job_created(job) -> void:
	print("[TestCombined] Job created: #%d %s" % [job.job_id, UnifiedJobClass.get_type_name(job.job_type)])


func _on_job_completed(job) -> void:
	print("[TestCombined] Job completed: #%d %s" % [job.job_id, UnifiedJobClass.get_type_name(job.job_type)])


func _on_clearing_vegetation_updated(region: Rect2i) -> void:
	if not billboard_vegetation or not vegetation_manager:
		return

	var heightmap_to_use = _get_heightmap_or_mock()
	var cell_size: float = 4.0
	var region_min_x: float = region.position.x * cell_size
	var region_min_z: float = region.position.y * cell_size
	var region_max_x: float = (region.position.x + region.size.x) * cell_size
	var region_max_z: float = (region.position.y + region.size.y) * cell_size

	var bundle_size: float = vegetation_manager.bundle_meters
	var bundles_per_side: int = int(CHUNK_SIZE / bundle_size)

	for chunk_coord in VEG_CHUNKS:
		if not vegetation_manager._chunk_terrain.has(chunk_coord):
			continue

		var chunk_world_min_x: float = chunk_coord.x * CHUNK_SIZE
		var chunk_world_min_z: float = chunk_coord.y * CHUNK_SIZE
		var chunk_world_max_x: float = chunk_world_min_x + CHUNK_SIZE
		var chunk_world_max_z: float = chunk_world_min_z + CHUNK_SIZE

		if chunk_world_max_x < region_min_x or chunk_world_min_x > region_max_x:
			continue
		if chunk_world_max_z < region_min_z or chunk_world_min_z > region_max_z:
			continue

		var terrain_data: PackedByteArray = vegetation_manager._chunk_terrain[chunk_coord]
		var modified := false

		for bz in bundles_per_side:
			for bx in bundles_per_side:
				var bundle_center_x: float = chunk_world_min_x + (bx + 0.5) * bundle_size
				var bundle_center_z: float = chunk_world_min_z + (bz + 0.5) * bundle_size

				if bundle_center_x >= region_min_x and bundle_center_x <= region_max_x:
					if bundle_center_z >= region_min_z and bundle_center_z <= region_max_z:
						var idx: int = bz * bundles_per_side + bx
						if idx < terrain_data.size() and terrain_data[idx] != VegetationManager.TerrainType.CLEAR:
							terrain_data[idx] = VegetationManager.TerrainType.CLEAR
							modified = true

							var global_bundle_x: int = int(bundle_center_x / bundle_size)
							var global_bundle_z: int = int(bundle_center_z / bundle_size)
							_remove_trees_in_bundle(Vector2i(global_bundle_x, global_bundle_z))

		if modified:
			vegetation_manager._chunk_terrain[chunk_coord] = terrain_data
			billboard_vegetation.generate_for_chunk(chunk_coord, heightmap_to_use, terrain_data)

	_rebuild_grid_overlay()


func _remove_trees_in_bundle(bundle_coord: Vector2i) -> int:
	if not _trees_by_bundle.has(bundle_coord):
		return 0

	var trees_in_bundle: Array = _trees_by_bundle[bundle_coord]
	var removed_count: int = trees_in_bundle.size()

	for tree in trees_in_bundle:
		if is_instance_valid(tree):
			var idx: int = tree_nodes.find(tree)
			if idx >= 0:
				tree_nodes.remove_at(idx)
			tree.queue_free()

	_trees_by_bundle.erase(bundle_coord)
	return removed_count


func _rebuild_grid_overlay() -> void:
	if not grid_overlay or not vegetation_manager:
		return

	var bundle_size: float = vegetation_manager.bundle_meters
	var bundles_per_side: int = int(CHUNK_SIZE / bundle_size)
	var im := ImmediateMesh.new()

	# Lines
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var line_color := Color(1.0, 1.0, 0.0, 1.0)
	var height_offset := 1.5

	for chunk_coord in VEG_CHUNKS:
		if not vegetation_manager._chunk_terrain.has(chunk_coord):
			continue

		var chunk_offset_x: float = chunk_coord.x * CHUNK_SIZE
		var chunk_offset_z: float = chunk_coord.y * CHUNK_SIZE

		for x in range(bundles_per_side + 1):
			var world_x: float = chunk_offset_x + x * bundle_size
			for z in range(bundles_per_side):
				var z0: float = chunk_offset_z + z * bundle_size
				var z1: float = chunk_offset_z + (z + 1) * bundle_size
				var center_y: float = _get_terrain_height(world_x, (z0 + z1) * 0.5) + height_offset
				im.surface_set_color(line_color)
				im.surface_add_vertex(Vector3(world_x, center_y, z0))
				im.surface_add_vertex(Vector3(world_x, center_y, z1))

		for z in range(bundles_per_side + 1):
			var world_z: float = chunk_offset_z + z * bundle_size
			for x in range(bundles_per_side):
				var x0: float = chunk_offset_x + x * bundle_size
				var x1: float = chunk_offset_x + (x + 1) * bundle_size
				var center_y: float = _get_terrain_height((x0 + x1) * 0.5, world_z) + height_offset
				im.surface_set_color(line_color)
				im.surface_add_vertex(Vector3(x0, center_y, world_z))
				im.surface_add_vertex(Vector3(x1, center_y, world_z))

	im.surface_end()

	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.vertex_color_use_as_albedo = true
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.render_priority = 10
	line_mat.no_depth_test = true
	im.surface_set_material(0, line_mat)

	grid_overlay.mesh = im
	grid_overlay.visible = grid_visible


func _create_simple_hud() -> Label:
	var label := Label.new()
	label.position = Vector2(10, 10)
	var canvas := CanvasLayer.new()
	canvas.add_child(label)
	add_child(canvas)
	return label


func _process(_delta: float) -> void:
	_update_hud()


func _update_hud() -> void:
	if not hud:
		return

	var supply_mgr := get_node_or_null("/root/SupplyManager")
	var supply_str: String = "%.0f" % supply_mgr.get_global_supply() if supply_mgr else "N/A"

	var text := "=== Test Arena (Combat + Construction) ===\n"
	text += "Supply: %s | Map: %.0fm\n" % [supply_str, MAP_SIZE]
	text += "Workers: %d | Grid: %s | Trees: %s\n" % [
		workers.size(),
		"ON" if grid_visible else "OFF",
		"ON" if trees_visible else "OFF"
	]

	var job_system = get_node_or_null("/root/JobSystem")
	if job_system:
		var counts: Dictionary = job_system.get_job_counts()
		text += "\nJobs: %d pending, %d ready, %d in-progress\n" % [counts.pending, counts.ready, counts.in_progress]

	text += "\nControls: B=Build | G=Grid | T=Trees | R=Reload"
	hud.text = text


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_B:
				# Open build menu - works without selecting engineers
				_open_build_menu()
			KEY_G:
				grid_visible = not grid_visible
				if grid_overlay:
					grid_overlay.visible = grid_visible
				print("[TestCombined] Grid: %s" % ("ON" if grid_visible else "OFF"))
			KEY_T:
				trees_visible = not trees_visible
				if tree_container:
					tree_container.visible = trees_visible
				print("[TestCombined] Trees: %s" % ("ON" if trees_visible else "OFF"))
			KEY_R:
				get_tree().reload_current_scene()
			KEY_ESCAPE:
				get_tree().quit()


func _get_terrain_height(world_x: float, world_z: float) -> float:
	if local_terrain and local_terrain.heightmap:
		return local_terrain.heightmap.sample_world(world_x, world_z)
	if terrain_intg and terrain_intg.terrain_manager and terrain_intg.terrain_manager.heightmap:
		return terrain_intg.terrain_manager.heightmap.sample_world(world_x, world_z)
	return 0.0


func _get_heightmap_or_mock():
	if local_terrain and local_terrain.heightmap:
		return local_terrain.heightmap
	if terrain_intg and terrain_intg.terrain_manager and terrain_intg.terrain_manager.heightmap:
		return terrain_intg.terrain_manager.heightmap
	return mock_heightmap


# ============================================================================
# LOADING OVERLAY - Shows progress during terrain generation
# ============================================================================

func _create_loading_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "LoadingLayer"
	canvas.layer = 200  # Above everything
	add_child(canvas)

	_loading_overlay = ColorRect.new()
	_loading_overlay.name = "LoadingOverlay"
	_loading_overlay.color = Color(0.1, 0.12, 0.15, 0.95)
	_loading_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(_loading_overlay)

	_loading_label = Label.new()
	_loading_label.name = "LoadingLabel"
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_label.set_anchors_preset(Control.PRESET_CENTER)
	_loading_label.add_theme_font_size_override("font_size", 28)
	_loading_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	_loading_label.text = "Loading..."
	_loading_overlay.add_child(_loading_label)


func _show_loading(message: String) -> void:
	_is_loading = true
	if _loading_label:
		_loading_label.text = message
	if _loading_overlay:
		_loading_overlay.visible = true


func _hide_loading() -> void:
	_is_loading = false
	if _loading_overlay:
		_loading_overlay.visible = false


func _on_terrain_progress(stage: String, percent: float) -> void:
	if _loading_label:
		_loading_label.text = "%s (%.0f%%)" % [stage, percent * 100.0]
