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
const ClearingState = preload("res://terrain/clearing_state.gd")
const TreeNodeClass = preload("res://terrain/vegetation/tree_node.gd")
const Squad = preload("res://battle_system/nodes/squad.gd")
const FirebaseClass = preload("res://firebase_system/firebase.gd")
const SupplyDepotScene = preload("res://game/scenes/buildings/supply_depot.tscn")

# Supply chain model paths
const M35_TRUCK_MODEL := "res://assets/models/vehicles/m35_deuce_truck.glb"
const CH47_CHINOOK_MODEL := "res://assets/models/helicopters/ch47_chinook.glb"

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

# Combat squads that consume supply
var _combat_squads: Array[Node3D] = []

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

# Supply chain settings
const REAR_DEPOT_CAPACITY := 999999.0
const FIREBASE_DEPOT_CAPACITY := 2000.0
const INITIAL_FIREBASE_SUPPLY := 400.0
const TRUCK_SUPPLY_AMOUNT := 500.0
const HELI_SUPPLY_AMOUNT := 800.0
const CHINOOK_CRUISE_ALTITUDE := 40.0
const CHINOOK_SPEED := 35.0
const CHINOOK_ROTOR_MAX_SPEED := 15.0

# Loading overlay
var _loading_overlay: ColorRect = null
var _loading_label: Label = null
var _is_loading: bool = false

# Supply chain - depots
var _rear_depot: Node3D = null
var _firebase_depot: Node3D = null

# Supply chain - convoy
var _supply_trucks: Array[Node3D] = []
var _convoy_state: String = "IDLE"
var _road_spline: RefCounted = null
var _return_spline: RefCounted = null
var _road_waypoints: Array[Vector3] = []

# Supply chain - Chinook
var _chinook: Node3D = null
var _chinook_state: String = "WAITING"
var _chinook_cargo: float = 0.0
var _chinook_rotor_speed: float = 0.0
var _chinook_waiting_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	print("========================================")
	print("  TEST COMBINED - Full Game Loop")
	print("  Map: %.0fm x %.0fm (async loading)")
	print("========================================")
	print("")

	# Disable test daemon to prevent freeze-causing synchronous file I/O
	var test_daemon = get_node_or_null("/root/TestDaemon")
	if test_daemon:
		test_daemon._enabled = false
		print("[TestCombined] Disabled TestDaemon for performance")

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

	# Setup supply chain (Pillar 3)
	_setup_supply_chain(_hq_center)

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
	print("  B: Build menu | G: Grid | V: Trees | R: Reload")
	print("  T: Dispatch truck convoy | H: Request Chinook supply")
	print("")
	print("SUPPLY CHAIN FLOW:")
	print("  1. Build a Supply Depot at firebase (B menu)")
	print("  2. Bulldozer auto-builds road to rear depot")
	print("  3. Truck starts supply runs when road completes")
	print("  4. Combat squads near depot receive supply")
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
	# Initialize UnifiedTerrain with our heightmap - this is THE single source of truth
	var unified_terrain: Node = get_node_or_null("/root/UnifiedTerrain")
	if unified_terrain and local_terrain and local_terrain.heightmap:
		if unified_terrain.has_method("init_from_heightmap"):
			unified_terrain.init_from_heightmap(local_terrain.heightmap)
			print("[TestCombined] UnifiedTerrain initialized with heightmap")

		# Initialize terrain types (jungle patterns, clear center)
		_initialize_terrain_types(unified_terrain)
	else:
		push_warning("[TestCombined] UnifiedTerrain not found or heightmap missing")

	# Also sync with TerrainIntegration for legacy compatibility
	GridCoordsClass.init(MAP_SIZE)
	if terrain_intg:
		terrain_intg.terrain_manager = local_terrain
		if unified_terrain:
			terrain_intg.unified_terrain = unified_terrain


func _initialize_terrain_types(terrain: Node) -> void:
	"""Initialize terrain types on UnifiedTerrain - clear HQ center, jungle elsewhere"""
	if not terrain:
		return

	var map_center: float = MAP_SIZE * 0.5
	var center_pos := Vector3(map_center, 0.0, map_center)

	# Mark the HQ center as cleared - this sets terrain type to CLEAR automatically
	if terrain.has_method("set_clearing_stage_area"):
		terrain.set_clearing_stage_area(center_pos, CLEARING_RADIUS, ClearingState.Stage.CLEARED)
		print("[TestCombined] HQ area marked as cleared (%.0fm radius)" % CLEARING_RADIUS)

	# The rest of the terrain types are derived from heightmap by UnifiedTerrain's
	# _build_gameplay_grid_from_heightmap() - jungle types based on elevation/slope

	print("[TestCombined] Terrain types initialized on UnifiedTerrain")


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

	# Connect vegetation to terrain for clearing signal chain
	# Note: VegetationManager expects RefCounted (TerrainGrid), not Node (UnifiedTerrain)
	# For now, connect to UnifiedTerrain's vegetation_changed signal for clearing updates
	var unified_terrain: Node = get_node_or_null("/root/UnifiedTerrain")
	if unified_terrain and unified_terrain.has_signal("vegetation_changed"):
		unified_terrain.vegetation_changed.connect(_on_vegetation_changed)
		print("[TestCombined] Connected to UnifiedTerrain.vegetation_changed for clearing updates")

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


func _on_vegetation_changed(region: Rect2i) -> void:
	"""Handle vegetation clearing from UnifiedTerrain"""
	# Forward clearing updates to vegetation managers
	if vegetation_manager and vegetation_manager.has_method("clear_vegetation_in_region"):
		vegetation_manager.clear_vegetation_in_region(region)
	if billboard_vegetation and billboard_vegetation.has_method("clear_vegetation_in_region"):
		billboard_vegetation.clear_vegetation_in_region(region)


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

	# Diagnostic: Verify workers have WorkerController
	call_deferred("_verify_worker_controllers")


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

	# Track US combat squads for supply consumption
	var faction: int = squad_data.faction if squad_data else GameEnums.Faction.US_ARMY
	if squad_data == us_rifle_data:
		_combat_squads.append(squad)
		# Add supply tracking metadata (start at 50% supply)
		squad.set_meta("supply_current", 50.0)
		squad.set_meta("supply_max", 100.0)

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


func _verify_worker_controllers() -> void:
	"""Diagnostic: Verify all workers have WorkerController attached"""
	print("\n=== WORKER DIAGNOSTIC ===")
	for worker in workers:
		if not is_instance_valid(worker):
			print("  [INVALID] Worker reference invalid")
			continue
		var has_wc: bool = worker.has_method("get_worker_controller") and worker.get_worker_controller() != null
		var can_build: bool = worker.data.can_build if worker.data else false
		var worker_class: String = "unknown"
		if has_wc:
			var wc = worker.get_worker_controller()
			worker_class = wc.worker_class if wc else "none"
		print("  %s: can_build=%s, has_controller=%s, class=%s" % [
			worker.name, can_build, has_wc, worker_class
		])
	print("=========================\n")


func _on_job_created(job) -> void:
	print("[TestCombined] Job created: #%d %s at %v" % [job.job_id, UnifiedJobClass.get_type_name(job.job_type), job.get_centroid()])


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


func _process(delta: float) -> void:
	_update_convoy_loop(delta)
	_update_chinook_loop(delta)
	_update_squad_supply(delta)
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

	# Add supply chain status
	var fb_supply: float = _firebase_depot.get_meta("supply_current", 0.0) if _firebase_depot else 0.0
	var fb_max: float = _firebase_depot.get_meta("supply_max", FIREBASE_DEPOT_CAPACITY) if _firebase_depot else FIREBASE_DEPOT_CAPACITY
	text += "\nFirebase Depot: %.0f/%.0f" % [fb_supply, fb_max]
	text += " | Convoy=%s | Chinook=%s\n" % [_convoy_state, _chinook_state]

	# Squad supply status
	if not _combat_squads.is_empty():
		text += "\nSquad Supply:\n" + _get_squad_supply_status()

	text += "Controls: B=Build | G=Grid | V=Trees | T=Convoy | H=Chinook | R=Reload"
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
			KEY_V:
				trees_visible = not trees_visible
				if tree_container:
					tree_container.visible = trees_visible
				print("[TestCombined] Trees: %s" % ("ON" if trees_visible else "OFF"))
			KEY_T:
				# Dispatch truck convoy
				_dispatch_convoy()
			KEY_H:
				# Request Chinook supply run
				_request_chinook_supply()
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


# ============================================================================
# SUPPLY CHAIN SYSTEM (Pillar 3: Physical Supply Chains)
# ============================================================================

func _setup_supply_chain(hq_pos: Vector3) -> void:
	"""Setup supply chain: rear depot only, firebase depot placed by player triggers road building"""
	print("[TestCombined] Setting up supply chain (Pillar 3)...")

	# Calculate positions relative to HQ
	var rear_depot_pos := hq_pos + Vector3(-100, 0, 0)  # 100m west of HQ
	rear_depot_pos.y = _get_terrain_height(rear_depot_pos.x, rear_depot_pos.z)

	# Chinook waiting position (behind rear depot, at altitude)
	_chinook_waiting_pos = rear_depot_pos + Vector3(-30, CHINOOK_CRUISE_ALTITUDE, -30)

	# Create ONLY the rear depot (main base) - firebase depot is player-placed
	_create_rear_depot(rear_depot_pos)

	# Create supply truck (1 truck, waiting for road)
	_create_supply_convoy(rear_depot_pos)

	# Create Chinook helicopter
	_create_chinook_helicopter()

	# Register rear depot as main base
	_register_depots_for_auto_roads()

	# Connect to SupplyChainManager for road completion
	var supply_chain_manager: Node = get_node_or_null("/root/SupplyChainManager")
	if supply_chain_manager and supply_chain_manager.has_signal("road_construction_completed"):
		supply_chain_manager.road_construction_completed.connect(_on_road_construction_completed)
		print("[TestCombined] Connected to SupplyChainManager.road_construction_completed")

	print("[TestCombined] Supply chain ready: 1 rear depot, %d truck (waiting), 1 Chinook" % _supply_trucks.size())
	print("[TestCombined] Build a Supply Depot at firebase to trigger auto-road construction")


func _create_rear_depot(pos: Vector3) -> void:
	"""Create rear supply depot using the real supply_depot.tscn model"""
	# Instantiate the real supply depot scene
	_rear_depot = SupplyDepotScene.instantiate()
	_rear_depot.name = "RearSupplyDepot"
	_rear_depot.position = pos
	add_child(_rear_depot)

	# Supply storage metadata (high capacity for main base)
	_rear_depot.set_meta("supply_current", REAR_DEPOT_CAPACITY)
	_rear_depot.set_meta("supply_max", REAR_DEPOT_CAPACITY)
	_rear_depot.set_meta("name", "Rear Depot")

	# Helipad for Chinook (placed beside depot)
	var helipad := _create_helipad_visual()
	helipad.position = Vector3(15, 0, 0)
	_rear_depot.add_child(helipad)

	print("[TestCombined] Rear depot created at %v (using real model)" % pos)


func _create_helipad_visual() -> Node3D:
	"""Create helipad visual"""
	var helipad := Node3D.new()
	helipad.name = "Helipad"

	# Pad surface
	var pad := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(15, 15)
	pad.mesh = plane
	pad.position.y = 0.05

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.3)
	pad.material_override = mat
	helipad.add_child(pad)

	# H marking
	var h_mark := MeshInstance3D.new()
	var h_box := BoxMesh.new()
	h_box.size = Vector3(6, 0.1, 1)
	h_mark.mesh = h_box
	h_mark.position.y = 0.1

	var h_mat := StandardMaterial3D.new()
	h_mat.albedo_color = Color(0.9, 0.9, 0.9)
	h_mark.material_override = h_mat
	helipad.add_child(h_mark)

	return helipad


func _setup_road_waypoints(rear_pos: Vector3, firebase_pos: Vector3) -> void:
	"""Setup road waypoints between depots for convoy movement"""
	# Simple waypoint path from rear depot to firebase
	_road_waypoints = [
		rear_pos + Vector3(20, 0, 0),
		Vector3((rear_pos.x + firebase_pos.x) * 0.5, 0, rear_pos.z + 15),
		firebase_pos + Vector3(-30, 0, 0),
	]

	# Adjust heights
	for i in _road_waypoints.size():
		_road_waypoints[i].y = _get_terrain_height(_road_waypoints[i].x, _road_waypoints[i].z)

	# Create TerrainSpline for smooth curves
	if ClassDB.class_exists("TerrainSpline") or ResourceLoader.exists("res://terrain/splines/terrain_spline.gd"):
		var TerrainSplineClass = load("res://terrain/splines/terrain_spline.gd")
		if TerrainSplineClass:
			var terrain: Node = get_node_or_null("/root/TerrainIntegration")

			_road_spline = TerrainSplineClass.new()
			if terrain and _road_spline.has_method("set_terrain"):
				_road_spline.set_terrain(terrain)
			if _road_spline.has_method("set_waypoints"):
				_road_spline.set_waypoints(_road_waypoints)

			# Create return spline (reverse waypoints)
			var reverse_waypoints: Array[Vector3] = []
			for i in range(_road_waypoints.size() - 1, -1, -1):
				reverse_waypoints.append(_road_waypoints[i])
			_return_spline = TerrainSplineClass.new()
			if terrain and _return_spline.has_method("set_terrain"):
				_return_spline.set_terrain(terrain)
			if _return_spline.has_method("set_waypoints"):
				_return_spline.set_waypoints(reverse_waypoints)

			print("[TestCombined] Road splines created: %d waypoints" % _road_waypoints.size())


func _create_supply_convoy(rear_pos: Vector3) -> void:
	"""Create supply truck (1 truck, waits for road to be built)"""
	var truck := _spawn_truck(0, rear_pos)
	if truck:
		_supply_trucks.append(truck)
		truck.set_meta("state", "WAITING_FOR_ROAD")

	_convoy_state = "WAITING_FOR_ROAD"
	print("[TestCombined] Supply truck created - waiting for road to firebase")


func _spawn_truck(convoy_index: int, depot_pos: Vector3) -> Node3D:
	"""Spawn a single M35 truck"""
	var truck := Node3D.new()
	truck.name = "SupplyTruck_%d" % convoy_index

	# Position trucks at rear depot
	var offset := Vector3(-4 + convoy_index * 8, 0, 10)
	truck.position = depot_pos + offset
	truck.position.y = _get_terrain_height(truck.position.x, truck.position.z)
	add_child(truck)

	# Try to load real M35 model
	var model_scene: PackedScene = load(M35_TRUCK_MODEL)
	if model_scene:
		var model: Node3D = model_scene.instantiate()
		model.name = "M35Model"
		truck.add_child(model)
	else:
		# Fallback to placeholder geometry
		_create_placeholder_truck(truck)

	# Initialize truck state
	truck.set_meta("state", "IDLE")
	truck.set_meta("cargo", 0.0)
	truck.set_meta("spline_distance", 0.0)
	truck.set_meta("returning", false)
	truck.set_meta("convoy_index", convoy_index)
	truck.set_meta("base_speed", 12.0)

	return truck


func _create_placeholder_truck(truck: Node3D) -> void:
	"""Fallback placeholder truck geometry"""
	# Body
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.5, 2.0, 6.0)
	body.mesh = box
	body.position.y = 1.5

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.4, 0.3)  # OD green
	body.material_override = mat
	truck.add_child(body)

	# Cab
	var cab := MeshInstance3D.new()
	var cab_box := BoxMesh.new()
	cab_box.size = Vector3(2.3, 1.5, 2.0)
	cab.mesh = cab_box
	cab.position = Vector3(0, 2.75, -2)
	cab.material_override = mat
	truck.add_child(cab)


func _create_chinook_helicopter() -> void:
	"""Create CH-47 Chinook helicopter"""
	_chinook = Node3D.new()
	_chinook.name = "CH47_Chinook"
	_chinook.position = _chinook_waiting_pos
	add_child(_chinook)

	# Try to load real Chinook model
	var model_scene: PackedScene = load(CH47_CHINOOK_MODEL)
	if model_scene:
		var model: Node3D = model_scene.instantiate()
		model.name = "ChinookModel"
		_chinook.add_child(model)
		_find_and_store_rotors(model)
		print("[TestCombined] CH-47 Chinook loaded with model")
	else:
		_create_placeholder_chinook(_chinook)
		print("[TestCombined] CH-47 Chinook using placeholder")

	_chinook.set_meta("target_position", _chinook_waiting_pos)
	_chinook_state = "WAITING"
	_chinook_cargo = 0.0


func _find_and_store_rotors(model: Node3D) -> void:
	"""Find rotor nodes in the Chinook model for animation"""
	var front_rotor: Node3D = _find_node_recursive(model, "rotor")
	var rear_rotor: Node3D = _find_node_recursive(model, "rear")
	if front_rotor:
		_chinook.set_meta("front_rotor", front_rotor)
	if rear_rotor:
		_chinook.set_meta("rear_rotor", rear_rotor)


func _find_node_recursive(node: Node, name_contains: String) -> Node3D:
	"""Recursively find node containing name"""
	if name_contains.to_lower() in node.name.to_lower():
		if node is Node3D:
			return node
	for child in node.get_children():
		var found: Node3D = _find_node_recursive(child, name_contains)
		if found:
			return found
	return null


func _create_placeholder_chinook(parent: Node3D) -> void:
	"""Fallback placeholder Chinook geometry"""
	# Fuselage
	var fuselage := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.0, 3.0, 15.0)
	fuselage.mesh = box
	fuselage.position.y = 1.5

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.25)
	fuselage.material_override = mat
	parent.add_child(fuselage)

	# Front rotor disc
	var front_rotor := MeshInstance3D.new()
	front_rotor.name = "FrontRotor"
	var rotor_mesh := CylinderMesh.new()
	rotor_mesh.top_radius = 9.0
	rotor_mesh.bottom_radius = 9.0
	rotor_mesh.height = 0.15
	front_rotor.mesh = rotor_mesh
	front_rotor.position = Vector3(0, 4.0, -5.0)

	var rotor_mat := StandardMaterial3D.new()
	rotor_mat.albedo_color = Color(0.2, 0.2, 0.2, 0.4)
	rotor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	front_rotor.material_override = rotor_mat
	parent.add_child(front_rotor)
	parent.set_meta("front_rotor", front_rotor)

	# Rear rotor disc
	var rear_rotor := MeshInstance3D.new()
	rear_rotor.name = "RearRotor"
	rear_rotor.mesh = rotor_mesh.duplicate()
	rear_rotor.position = Vector3(0, 4.0, 5.0)
	rear_rotor.material_override = rotor_mat
	parent.add_child(rear_rotor)
	parent.set_meta("rear_rotor", rear_rotor)


func _register_depots_for_auto_roads() -> void:
	"""Register rear depot as main base with SupplyChainManager"""
	var supply_chain_manager: Node = get_node_or_null("/root/SupplyChainManager")
	if not supply_chain_manager:
		print("[TestCombined] SupplyChainManager not found - auto-roads disabled")
		return

	if not supply_chain_manager.has_method("manually_register_depot"):
		return

	if _rear_depot:
		supply_chain_manager.manually_register_depot(_rear_depot)
		print("[TestCombined] Registered rear depot as main base")
		print("[TestCombined] When player builds a Supply Depot at firebase, auto-road will be created")


func _on_road_construction_completed(from_pos: Vector3, to_pos: Vector3) -> void:
	"""Called when SupplyChainManager completes a road - start the supply truck"""
	print("[TestCombined] Road completed from %v to %v - starting supply run!" % [from_pos, to_pos])

	# Find the firebase depot (the one that was just connected)
	var supply_chain_manager: Node = get_node_or_null("/root/SupplyChainManager")
	if supply_chain_manager and supply_chain_manager.has_method("get_all_depots"):
		var depots: Array = supply_chain_manager.get_all_depots()
		for depot: Node3D in depots:
			if depot != _rear_depot:
				_firebase_depot = depot
				# Ensure depot has supply tracking metadata
				if not _firebase_depot.has_meta("supply_current"):
					_firebase_depot.set_meta("supply_current", INITIAL_FIREBASE_SUPPLY)
				if not _firebase_depot.has_meta("supply_max"):
					_firebase_depot.set_meta("supply_max", FIREBASE_DEPOT_CAPACITY)
				print("[TestCombined] Firebase depot found: %s (%.0f/%.0f supply)" % [
					depot.name,
					_firebase_depot.get_meta("supply_current"),
					_firebase_depot.get_meta("supply_max")
				])
				break

	# Setup road waypoints for the truck
	if _firebase_depot and _rear_depot:
		_setup_road_waypoints(_rear_depot.global_position, _firebase_depot.global_position)

	# Start the supply truck
	_dispatch_convoy()


# ============================================================================
# CONVOY UPDATE LOOP
# ============================================================================

func _update_convoy_loop(delta: float) -> void:
	"""Update all trucks in convoy"""
	if _supply_trucks.is_empty():
		return

	for i in _supply_trucks.size():
		var truck: Node3D = _supply_trucks[i]
		if is_instance_valid(truck):
			_update_single_truck(truck, delta, i)

	# Update overall convoy state based on lead truck
	if not _supply_trucks.is_empty() and is_instance_valid(_supply_trucks[0]):
		_convoy_state = _supply_trucks[0].get_meta("state", "IDLE")


func _update_single_truck(truck: Node3D, delta: float, convoy_index: int) -> void:
	"""Update a single truck's movement"""
	var state: String = truck.get_meta("state", "IDLE")
	var cargo: float = truck.get_meta("cargo", 0.0)
	var spline_dist: float = truck.get_meta("spline_distance", 0.0)
	var returning: bool = truck.get_meta("returning", false)
	var base_speed: float = truck.get_meta("base_speed", 12.0)

	match state:
		"IDLE":
			pass  # Waiting for dispatch

		"WAITING_FOR_ROAD":
			pass  # Road not built yet - truck waits at depot

		"LOADING":
			cargo += 100.0 * delta
			if cargo >= TRUCK_SUPPLY_AMOUNT:
				cargo = TRUCK_SUPPLY_AMOUNT
				state = "EN_ROUTE"
				spline_dist = -convoy_index * 12.0  # Stagger convoy
				returning = false
			truck.set_meta("cargo", cargo)
			truck.set_meta("state", state)
			truck.set_meta("spline_distance", spline_dist)

		"EN_ROUTE":
			var spline: RefCounted = _return_spline if returning else _road_spline
			if not spline or not spline.has_method("get_total_length"):
				# No spline - use simple waypoint movement
				_update_truck_waypoint_movement(truck, delta, convoy_index)
				return

			var spline_length: float = spline.get_total_length()

			# Wait for convoy spacing
			if spline_dist < 0:
				spline_dist += base_speed * delta
				truck.set_meta("spline_distance", spline_dist)
				return

			if spline_dist < spline_length:
				spline_dist += base_speed * delta

				var new_pos: Vector3 = spline.get_position_at_distance(spline_dist)
				var tangent: Vector3 = spline.get_tangent_at_distance(spline_dist)

				truck.position = new_pos
				if tangent.length_squared() > 0.001:
					truck.rotation.y = atan2(tangent.x, tangent.z)

				truck.set_meta("spline_distance", spline_dist)
			else:
				# Reached destination
				if returning:
					state = "IDLE"
					truck.position = _rear_depot.position + Vector3(convoy_index * 8, 0, 10)
					truck.position.y = _get_terrain_height(truck.position.x, truck.position.z)
					print("[TestCombined] Truck %d returned to depot" % convoy_index)
				else:
					state = "UNLOADING"
					truck.position = _firebase_depot.position + Vector3(-25 - convoy_index * 8, 0, 0)
					truck.position.y = _get_terrain_height(truck.position.x, truck.position.z)
				spline_dist = 0.0
				truck.set_meta("state", state)
				truck.set_meta("spline_distance", spline_dist)

		"UNLOADING":
			var unload_amount: float = 100.0 * delta
			cargo -= unload_amount

			# Add to firebase depot
			var fb_supply: float = _firebase_depot.get_meta("supply_current", 0.0)
			var fb_max: float = _firebase_depot.get_meta("supply_max", FIREBASE_DEPOT_CAPACITY)
			fb_supply = minf(fb_supply + unload_amount, fb_max)
			_firebase_depot.set_meta("supply_current", fb_supply)

			if cargo <= 0:
				cargo = 0
				state = "EN_ROUTE"
				spline_dist = -convoy_index * 12.0
				returning = true
				print("[TestCombined] Truck %d unloaded, returning" % convoy_index)

			truck.set_meta("cargo", cargo)
			truck.set_meta("state", state)
			truck.set_meta("returning", returning)
			truck.set_meta("spline_distance", spline_dist)


func _update_truck_waypoint_movement(truck: Node3D, delta: float, convoy_index: int) -> void:
	"""Simple waypoint movement when no spline available"""
	var returning: bool = truck.get_meta("returning", false)
	var waypoint_idx: int = truck.get_meta("waypoint_idx", 0)
	var base_speed: float = truck.get_meta("base_speed", 12.0)

	var waypoints: Array[Vector3] = _road_waypoints.duplicate()
	if returning:
		waypoints.reverse()

	if waypoint_idx >= waypoints.size():
		# Reached end
		var state: String = "IDLE" if returning else "UNLOADING"
		truck.set_meta("state", state)
		truck.set_meta("waypoint_idx", 0)
		return

	var target: Vector3 = waypoints[waypoint_idx]
	var direction: Vector3 = (target - truck.position).normalized()
	var distance: float = truck.position.distance_to(target)

	if distance > 2.0:
		truck.position += direction * base_speed * delta
		truck.position.y = _get_terrain_height(truck.position.x, truck.position.z)
		var look_dir := Vector3(direction.x, 0, direction.z)
		if look_dir.length() > 0.1:
			truck.rotation.y = atan2(look_dir.x, look_dir.z)
	else:
		truck.set_meta("waypoint_idx", waypoint_idx + 1)


func _dispatch_convoy() -> void:
	"""Manually dispatch truck convoy for a supply run"""
	if _supply_trucks.is_empty():
		print("[TestCombined] No trucks in convoy")
		return

	for i in _supply_trucks.size():
		var truck: Node3D = _supply_trucks[i]
		if is_instance_valid(truck):
			truck.set_meta("state", "LOADING")
			truck.set_meta("cargo", 0.0)
			truck.set_meta("spline_distance", 0.0)
			truck.set_meta("returning", false)
			truck.set_meta("waypoint_idx", 0)
			if _rear_depot:
				truck.position = _rear_depot.position + Vector3(i * 8, 0, 10)
				truck.position.y = _get_terrain_height(truck.position.x, truck.position.z)

	_convoy_state = "LOADING"
	print("[TestCombined] Truck convoy dispatched (%d trucks)" % _supply_trucks.size())


# ============================================================================
# CHINOOK HELICOPTER UPDATE LOOP
# ============================================================================

func _update_chinook_loop(delta: float) -> void:
	"""Update CH-47 Chinook helicopter movement and state"""
	if not is_instance_valid(_chinook):
		return

	_update_chinook_rotors(delta)

	match _chinook_state:
		"WAITING":
			_chinook_hover_at_position(delta, _chinook_waiting_pos)

		"FLYING_TO_DEPOT":
			var depot_pos := _rear_depot.position + Vector3(15, CHINOOK_CRUISE_ALTITUDE, 0) if _rear_depot else _chinook_waiting_pos
			if _chinook_fly_toward(delta, depot_pos, CHINOOK_SPEED):
				_chinook_state = "LANDING_AT_DEPOT"

		"LANDING_AT_DEPOT":
			var ground_pos := _rear_depot.position + Vector3(15, 2.0, 0) if _rear_depot else _chinook_waiting_pos
			if _chinook_descend_to(delta, ground_pos):
				_chinook_state = "LOADING"

		"LOADING":
			_chinook_cargo += 200.0 * delta
			if _chinook_cargo >= HELI_SUPPLY_AMOUNT:
				_chinook_cargo = HELI_SUPPLY_AMOUNT
				_chinook_state = "TAKING_OFF_DEPOT"

		"TAKING_OFF_DEPOT":
			var takeoff_pos := _rear_depot.position + Vector3(15, CHINOOK_CRUISE_ALTITUDE, 0) if _rear_depot else _chinook_waiting_pos
			if _chinook_ascend_to(delta, takeoff_pos):
				_chinook_state = "FLYING_TO_LZ"

		"FLYING_TO_LZ":
			var lz_pos := _firebase_depot.position + Vector3(-15, CHINOOK_CRUISE_ALTITUDE, 0) if _firebase_depot else _chinook_waiting_pos
			if _chinook_fly_toward(delta, lz_pos, CHINOOK_SPEED):
				_chinook_state = "LANDING_AT_LZ"

		"LANDING_AT_LZ":
			var ground_pos := _firebase_depot.position + Vector3(-15, 2.0, 0) if _firebase_depot else _chinook_waiting_pos
			if _chinook_descend_to(delta, ground_pos):
				_chinook_state = "UNLOADING"

		"UNLOADING":
			var unload_amount: float = 200.0 * delta
			_chinook_cargo -= unload_amount

			# Add to firebase depot
			if _firebase_depot:
				var fb_supply: float = _firebase_depot.get_meta("supply_current", 0.0)
				var fb_max: float = _firebase_depot.get_meta("supply_max", FIREBASE_DEPOT_CAPACITY)
				fb_supply = minf(fb_supply + unload_amount, fb_max)
				_firebase_depot.set_meta("supply_current", fb_supply)

			if _chinook_cargo <= 0:
				_chinook_cargo = 0
				_chinook_state = "TAKING_OFF_LZ"

		"TAKING_OFF_LZ":
			var takeoff_pos := _firebase_depot.position + Vector3(-15, CHINOOK_CRUISE_ALTITUDE, 0) if _firebase_depot else _chinook_waiting_pos
			if _chinook_ascend_to(delta, takeoff_pos):
				_chinook_state = "RETURNING"

		"RETURNING":
			if _chinook_fly_toward(delta, _chinook_waiting_pos, CHINOOK_SPEED):
				_chinook_state = "WAITING"
				print("[TestCombined] Chinook supply run complete")


func _update_chinook_rotors(delta: float) -> void:
	"""Spin Chinook rotors"""
	var target_speed: float = CHINOOK_ROTOR_MAX_SPEED
	if _chinook_state == "WAITING":
		target_speed = CHINOOK_ROTOR_MAX_SPEED * 0.8
	_chinook_rotor_speed = lerpf(_chinook_rotor_speed, target_speed, delta * 2.0)

	var front_rotor: Node3D = _chinook.get_meta("front_rotor", null)
	var rear_rotor: Node3D = _chinook.get_meta("rear_rotor", null)

	if is_instance_valid(front_rotor):
		front_rotor.rotate_y(_chinook_rotor_speed * delta)
	if is_instance_valid(rear_rotor):
		rear_rotor.rotate_y(-_chinook_rotor_speed * delta)


func _chinook_hover_at_position(delta: float, target: Vector3) -> void:
	"""Gentle hover drift at position"""
	var diff := target - _chinook.position
	if diff.length() > 1.0:
		_chinook.position = _chinook.position.lerp(target, delta * 0.5)


func _chinook_fly_toward(delta: float, target: Vector3, speed: float) -> bool:
	"""Fly toward target, returns true when arrived"""
	var direction: Vector3 = (target - _chinook.position).normalized()
	var distance: float = _chinook.position.distance_to(target)

	if distance > 5.0:
		var velocity := direction * speed
		if distance < 30.0:
			velocity *= distance / 30.0
		_chinook.position += velocity * delta

		var look_dir := Vector3(direction.x, 0, direction.z)
		if look_dir.length() > 0.1:
			var target_rot: float = atan2(look_dir.x, look_dir.z)
			_chinook.rotation.y = lerp_angle(_chinook.rotation.y, target_rot, delta * 2.0)
		return false
	else:
		_chinook.position = target
		return true


func _chinook_descend_to(delta: float, target: Vector3) -> bool:
	"""Descend vertically, returns true when landed"""
	var descent_speed := 6.0
	if _chinook.position.y > target.y + 0.5:
		_chinook.position.y -= descent_speed * delta
		_chinook.position.x = lerpf(_chinook.position.x, target.x, delta * 2.0)
		_chinook.position.z = lerpf(_chinook.position.z, target.z, delta * 2.0)
		return false
	else:
		_chinook.position = target
		return true


func _chinook_ascend_to(delta: float, target: Vector3) -> bool:
	"""Ascend vertically, returns true when at altitude"""
	var ascent_speed := 8.0
	if _chinook.position.y < target.y - 0.5:
		_chinook.position.y += ascent_speed * delta
		return false
	else:
		_chinook.position.y = target.y
		return true


func _request_chinook_supply() -> void:
	"""Request CH-47 Chinook supply run"""
	if _chinook_state != "WAITING":
		print("[TestCombined] Chinook is busy (state: %s)" % _chinook_state)
		return

	_chinook_state = "FLYING_TO_DEPOT"
	_chinook_cargo = 0.0
	print("[TestCombined] Chinook dispatched for supply run (%.0f capacity)" % HELI_SUPPLY_AMOUNT)


# ============================================================================
# SQUAD SUPPLY CONSUMPTION & RESUPPLY
# ============================================================================

const SUPPLY_CONSUMPTION_RATE := 2.0  # Supply consumed per second
const SUPPLY_RESUPPLY_RATE := 10.0  # Supply restored per second when near depot
const SUPPLY_RESUPPLY_RANGE := 50.0  # Range to receive resupply from depot

func _update_squad_supply(delta: float) -> void:
	"""Update supply consumption and resupply for combat squads"""
	if _combat_squads.is_empty():
		return

	for squad: Node3D in _combat_squads:
		if not is_instance_valid(squad):
			continue

		var current_supply: float = squad.get_meta("supply_current", 100.0)
		var max_supply: float = squad.get_meta("supply_max", 100.0)

		# Consume supply over time (combat operations)
		current_supply = maxf(0.0, current_supply - SUPPLY_CONSUMPTION_RATE * delta)

		# Check if near firebase depot for resupply
		if _firebase_depot and is_instance_valid(_firebase_depot):
			var dist_to_depot: float = squad.global_position.distance_to(_firebase_depot.global_position)
			if dist_to_depot <= SUPPLY_RESUPPLY_RANGE:
				var depot_supply: float = _firebase_depot.get_meta("supply_current", 0.0)
				if depot_supply > 0 and current_supply < max_supply:
					var resupply_amount: float = minf(SUPPLY_RESUPPLY_RATE * delta, depot_supply)
					resupply_amount = minf(resupply_amount, max_supply - current_supply)
					current_supply += resupply_amount
					depot_supply -= resupply_amount
					_firebase_depot.set_meta("supply_current", depot_supply)

		squad.set_meta("supply_current", current_supply)


func _get_squad_supply_status() -> String:
	"""Get formatted supply status for HUD"""
	var status := ""
	for squad: Node3D in _combat_squads:
		if not is_instance_valid(squad):
			continue
		var supply: float = squad.get_meta("supply_current", 0.0)
		var max_supply: float = squad.get_meta("supply_max", 100.0)
		var pct: int = int(supply / max_supply * 100.0) if max_supply > 0 else 0
		status += "  %s: %d%%\n" % [squad.name, pct]
	return status
