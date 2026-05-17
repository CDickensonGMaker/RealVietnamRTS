extends Node3D
## Test Arena - Testing area for unit selection, movement, and construction
## Uses TerrainIntegration with modified terrain for flat start + hilly far end

const Squad = preload("res://battle_system/nodes/squad.gd")

# Test arena configuration
# Player starts in center-ish area, enemy at far end
const MAP_SIZE := 3000.0  # Full map size from terrain engine
const HQ_POSITION_XZ := Vector2(500, 500)  # In playable area, not at edge
const CLEARING_RADIUS := 60.0  # Pre-cleared area around HQ

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

# References
var _hq_structures: Array[Node3D] = []
var _terrain_integration: Node = null
var _terrain_engine: Node = null
var _terrain_ready: bool = false
var _hq_center: Vector3 = Vector3.ZERO


func _ready() -> void:
	print("========================================")
	print("  TEST ARENA - Selection, Movement & Construction")
	print("  Map: %.0fm x %.0fm" % [MAP_SIZE, MAP_SIZE])
	print("  Firebase HQ with structures")
	print("========================================")
	print("")

	# Get terrain systems
	_terrain_integration = get_node_or_null("/root/TerrainIntegration")
	_terrain_engine = get_node_or_null("/root/TerrainEngine")

	if not _terrain_integration:
		push_error("[TestArena] TerrainIntegration autoload not found!")
		_create_fallback_terrain()
		return

	# Configure terrain engine for test arena
	_configure_terrain_for_test()

	# Position camera above HQ first
	_setup_camera()

	# Initialize terrain with camera reference
	_init_terrain()

	print("")
	print("Controls:")
	print("  WASD: Pan camera")
	print("  Mouse Wheel: Zoom")
	print("  Left Click: Select unit")
	print("  Right Click: Move order")
	print("  Shift+Click: Add to selection")
	print("  B: Open build menu (with engineers selected)")
	print("")


func _configure_terrain_for_test() -> void:
	"""Configure terrain engine for flat start + hilly end"""
	if not _terrain_engine:
		print("[TestArena] TerrainEngine not found - using default terrain")
		return

	# Set terrain to COASTAL_HILLS for gentler terrain
	if _terrain_engine.has_method("set_preset"):
		_terrain_engine.set_preset(3)  # COASTAL_HILLS
		print("[TestArena] Set terrain preset to COASTAL_HILLS")

	# Reduce height scale for flatter terrain
	if "height_scale" in _terrain_engine:
		_terrain_engine.height_scale = 80.0  # Much flatter (was 280)
		print("[TestArena] Reduced height scale to 80m")


func _init_terrain() -> void:
	"""Initialize terrain engine and create cleared HQ area"""
	print("[TestArena] Initializing terrain engine...")

	# Connect to terrain ready signal
	if _terrain_integration.has_signal("terrain_ready"):
		_terrain_integration.terrain_ready.connect(_on_terrain_ready)

	# Initialize terrain with camera
	# Use a fixed seed for reproducible test terrain
	_terrain_integration.init_terrain(camera, 42)


func _on_terrain_ready() -> void:
	"""Called when terrain generation is complete"""
	_terrain_ready = true
	print("[TestArena] Terrain ready - setting up test area")

	# Use deferred call to ensure terrain system is fully initialized
	call_deferred("_setup_hq_area")


func _setup_hq_area() -> void:
	"""Set up the HQ area after terrain is fully ready"""
	# Find a good spot for HQ
	var best_pos := _find_good_hq_location()

	# Get terrain height at HQ position
	var hq_height: float = _terrain_integration.get_height_at(best_pos)
	_hq_center = Vector3(best_pos.x, hq_height, best_pos.z)

	print("[TestArena] HQ position: %s (height: %.1f)" % [_hq_center, hq_height])

	# Create a cleared zone for the HQ area
	_create_cleared_hq_area(_hq_center)

	# Spawn HQ structures (gate, tents, bunkers)
	_spawn_hq_structures(_hq_center)

	# Spawn units near HQ
	_spawn_test_units(_hq_center)

	# Update camera to focus on actual HQ position
	_focus_camera_on_hq(_hq_center)

	print("[TestArena] Test arena setup complete!")


func _find_good_hq_location() -> Vector3:
	"""Find a good location for the HQ compound"""
	# Start with target position
	var target := Vector3(HQ_POSITION_XZ.x, 0, HQ_POSITION_XZ.y)
	var best_pos := target
	var best_variance := INF

	# Sample a grid of points to find flattest area
	var search_radius := 100.0
	var sample_step := 25.0

	for x in range(-int(search_radius / sample_step), int(search_radius / sample_step) + 1):
		for z in range(-int(search_radius / sample_step), int(search_radius / sample_step) + 1):
			var sample_pos := Vector3(
				target.x + x * sample_step,
				0,
				target.z + z * sample_step
			)

			# Skip if too close to map edge
			if sample_pos.x < 100 or sample_pos.x > MAP_SIZE - 100:
				continue
			if sample_pos.z < 100 or sample_pos.z > MAP_SIZE - 100:
				continue

			# Calculate height variance in this area
			var variance := _calculate_height_variance(sample_pos, 40.0)

			if variance < best_variance:
				best_variance = variance
				best_pos = sample_pos

	print("[TestArena] Found flat area at %s (variance: %.2f)" % [best_pos, best_variance])
	return best_pos


func _calculate_height_variance(center: Vector3, radius: float) -> float:
	"""Calculate terrain height variance around a point"""
	var heights: Array[float] = []
	var samples := 8

	for i in range(samples):
		var angle := float(i) / samples * TAU
		var sample_pos := center + Vector3(cos(angle), 0, sin(angle)) * radius
		var h: float = _terrain_integration.get_height_at(sample_pos)
		heights.append(h)

	# Also sample center
	heights.append(_terrain_integration.get_height_at(center))

	# Calculate variance
	var mean := 0.0
	for h in heights:
		mean += h
	mean /= heights.size()

	var variance := 0.0
	for h in heights:
		variance += (h - mean) * (h - mean)
	variance /= heights.size()

	return variance


func _create_cleared_hq_area(hq_pos: Vector3) -> void:
	"""Create a cleared zone around the HQ for construction"""
	print("[TestArena] Creating cleared zone at HQ (radius: %.0fm)" % CLEARING_RADIUS)

	# Check if terrain integration is ready
	if not _terrain_integration.is_ready():
		print("[TestArena] Terrain not ready yet - skipping clearing zone")
		return

	# Use terrain integration to create clearing zone
	var zone_id: int = _terrain_integration.start_clearing_zone(hq_pos, CLEARING_RADIUS)
	if zone_id >= 0:
		# Immediately set to CLEARED stage for testing
		_terrain_integration.set_clearing_stage(zone_id, 2)  # CLEARED
		print("[TestArena] Clearing zone %d created and set to CLEARED" % zone_id)
	else:
		print("[TestArena] WARNING: Failed to create clearing zone")


func _spawn_hq_structures(hq_pos: Vector3) -> void:
	"""Spawn firebase structures at HQ location"""
	print("[TestArena] Spawning HQ structures...")

	# Gate entrance at front of compound
	var gate := _spawn_structure(GATE_MODEL, hq_pos + Vector3(0, 0, -25), 0, "HQ_Gate")

	# TOC (Tactical Operations Center) at center-back
	var toc := _spawn_structure(TOC_MODEL, hq_pos + Vector3(0, 0, 10), 0, "HQ_TOC")

	# Hootches (living quarters) on sides
	var hootch1 := _spawn_structure(HOOTCH_MODEL, hq_pos + Vector3(-20, 0, -5), 0, "HQ_Hootch_1")
	var hootch2 := _spawn_structure(HOOTCH_MODEL, hq_pos + Vector3(20, 0, -5), 0, "HQ_Hootch_2")

	# Sandbag bunkers for defense
	var bunker1 := _spawn_structure(SANDBAG_BUNKER_MODEL, hq_pos + Vector3(-15, 0, -20), -45, "HQ_Bunker_1")
	var bunker2 := _spawn_structure(SANDBAG_BUNKER_MODEL, hq_pos + Vector3(15, 0, -20), 45, "HQ_Bunker_2")

	# MG nest overlooking approach
	var mg := _spawn_structure(MG_NEST_MODEL, hq_pos + Vector3(0, 0, -30), 0, "HQ_MG_Nest")

	# Ammo bunker
	var ammo := _spawn_structure(AMMO_BUNKER_MODEL, hq_pos + Vector3(-25, 0, 10), 0, "HQ_Ammo")

	print("[TestArena] Spawned 8 HQ structures")


func _spawn_structure(model_path: String, pos: Vector3, rotation_deg: float, struct_name: String) -> Node3D:
	"""Spawn a structure model at the given position"""
	# Get terrain height at position
	var terrain_height: float = _terrain_integration.get_height_at(pos)
	pos.y = terrain_height

	var structure := Node3D.new()
	structure.name = struct_name
	structure.position = pos
	structure.rotation_degrees.y = rotation_deg

	# Load and add the model
	var model_scene := load(model_path) as PackedScene
	if model_scene:
		var model := model_scene.instantiate()
		structure.add_child(model)
	else:
		# Fallback visual if model doesn't load
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(4, 2, 4)
		mesh.mesh = box
		mesh.position.y = 1
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.4, 0.3)
		mesh.material_override = mat
		structure.add_child(mesh)
		print("[TestArena] WARNING: Could not load model: %s" % model_path)

	add_child(structure)
	_hq_structures.append(structure)

	# Clear vegetation around the building (5m buffer per game design)
	if _terrain_integration and _terrain_integration.has_method("clear_vegetation_around_building"):
		_terrain_integration.clear_vegetation_around_building(pos, 7.0)  # 5m buffer + ~2m footprint radius

	return structure


func _spawn_test_units(hq_pos: Vector3) -> void:
	"""Spawn test units around HQ"""
	print("[TestArena] Spawning test units...")

	# US forces - around HQ (player controlled)
	# Position them near the gate entrance
	_spawn_squad(us_rifle_data, hq_pos + Vector3(-10, 0, -35), "US_Rifle_1")
	_spawn_squad(us_rifle_data, hq_pos + Vector3(10, 0, -35), "US_Rifle_2")
	_spawn_squad(us_engineer_data, hq_pos + Vector3(0, 0, -40), "US_Engineers")

	# Bulldozer for terrain flattening
	_spawn_squad(us_bulldozer_data, hq_pos + Vector3(25, 0, 5), "US_Bulldozer")

	# VC forces - at far end of map (enemy)
	var enemy_z: float = hq_pos.z + 300.0  # 300m away
	var enemy_height: float = _terrain_integration.get_height_at(Vector3(hq_pos.x, 0, enemy_z))
	_spawn_squad(vc_infantry_data, Vector3(hq_pos.x - 20, enemy_height, enemy_z), "VC_Squad_1")
	_spawn_squad(vc_infantry_data, Vector3(hq_pos.x + 20, enemy_height, enemy_z), "VC_Squad_2")

	print("[TestArena] Spawned 4 US units (incl. bulldozer), 2 VC units")


func _spawn_squad(squad_data: Resource, spawn_pos: Vector3, unit_name: String) -> Squad:
	"""Spawn a squad at the given position"""
	# Get terrain height at spawn position
	var terrain_height: float = _terrain_integration.get_height_at(spawn_pos)
	spawn_pos.y = terrain_height

	var squad := Squad.new()
	squad.name = unit_name
	squad.data = squad_data
	squad.position = spawn_pos

	add_child(squad)

	# Emit spawn signal
	var faction: int = squad_data.faction if squad_data else GameEnums.Faction.US_ARMY
	BattleSignals.unit_spawned.emit(squad, faction)

	print("[TestArena]   %s at %s (layer: %d)" % [unit_name, spawn_pos, squad.collision_layer])
	return squad


func _setup_camera() -> void:
	"""Initial camera setup - sets bounds, actual position set after terrain ready"""
	if not camera:
		push_warning("[TestArena] No camera found!")
		return

	# Set camera bounds for full map
	if "map_bounds_min" in camera:
		camera.map_bounds_min = Vector3(0, 0, 0)
		camera.map_bounds_max = Vector3(MAP_SIZE, 0, MAP_SIZE)

	# Set initial zoom level
	if "current_zoom" in camera:
		camera.current_zoom = 50.0  # Good overview height

	print("[TestArena] Camera bounds set: 0 to %.0f" % MAP_SIZE)


func _focus_camera_on_hq(hq_pos: Vector3) -> void:
	"""Focus camera on the actual HQ position after terrain is ready"""
	if not camera:
		return

	# Use camera's focus_on method if available (sets target_position properly)
	if camera.has_method("focus_on"):
		camera.focus_on(hq_pos)
	elif camera.has_method("center_on"):
		camera.center_on(hq_pos)
	else:
		# Direct fallback - set both position and target_position
		var cam_height: float = hq_pos.y + 50.0
		var cam_pos := Vector3(hq_pos.x, cam_height, hq_pos.z + 40)
		camera.position = cam_pos
		if "target_position" in camera:
			camera.target_position = cam_pos
		camera.look_at(hq_pos)

	print("[TestArena] Camera focused on HQ at %s (terrain height: %.1f)" % [hq_pos, hq_pos.y])


func _create_fallback_terrain() -> void:
	"""Create simple fallback terrain if terrain engine isn't available"""
	print("[TestArena] Creating fallback terrain...")

	# Simple ground plane
	var ground := MeshInstance3D.new()
	ground.name = "FallbackGround"

	var plane := PlaneMesh.new()
	plane.size = Vector2(500, 500)
	ground.mesh = plane
	ground.position = Vector3(250, 0, 250)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.45, 0.25)
	ground.material_override = mat

	add_child(ground)

	# Add collision
	var static_body := StaticBody3D.new()
	static_body.collision_layer = 1

	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(500, 0.5, 500)
	collision.shape = box
	collision.position = Vector3(250, -0.25, 250)

	static_body.add_child(collision)
	add_child(static_body)

	# Manually trigger unit spawn since terrain won't send ready signal
	call_deferred("_spawn_fallback_units")


func _spawn_fallback_units() -> void:
	"""Spawn units for fallback terrain mode"""
	_hq_center = Vector3(250, 0, 250)
	_spawn_hq_structures(_hq_center)

	# US forces
	_spawn_squad(us_rifle_data, _hq_center + Vector3(-10, 0, -35), "US_Rifle_1")
	_spawn_squad(us_rifle_data, _hq_center + Vector3(10, 0, -35), "US_Rifle_2")
	_spawn_squad(us_engineer_data, _hq_center + Vector3(0, 0, -40), "US_Engineers")
	_spawn_squad(us_bulldozer_data, _hq_center + Vector3(25, 0, 5), "US_Bulldozer")

	# VC forces at far end
	_spawn_squad(vc_infantry_data, Vector3(235, 0, 450), "VC_Squad_1")
	_spawn_squad(vc_infantry_data, Vector3(265, 0, 450), "VC_Squad_2")

	_focus_camera_on_hq(_hq_center)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
		elif event.keycode == KEY_R:
			# Reload scene
			get_tree().reload_current_scene()
