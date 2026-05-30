extends Node3D

## Building System Test Scene
## Demonstrates the construction loop with PlacementController and JobSystem
##
## This test scene proves:
## 1. Ghost preview appears with red/green validation (PlacementController)
## 2. Jobs are created on placement commit (JobSystem)
## 3. Workers auto-assign to jobs (WorkerController)
## 4. Construction progresses through stages (ConstructionZone)
## 5. Building completes with model/placeholder
##
## Uses PlacementController for CoH-style ghost preview with real-time validation.
##
## Controls:
## - Left-click: Select units / Place building in placement mode
## - Right-click: Move selected units / Cancel placement
## - F: Place Firebase mode
## - C: Create Clear Terrain job
## - L: Create Flatten Area job
## - 1-9: Building placement hotkeys
## - E: Spawn Engineer
## - B: Spawn Bulldozer
## - ESC: Cancel placement mode

const TestSceneBase = preload("res://test_scenes/common/test_scene_base.gd")
const BuilderUnit = preload("res://firebase_system/test/builder_unit.gd")
const BuildingData = preload("res://firebase_system/building_data.gd")
const Firebase = preload("res://firebase_system/firebase.gd")
const PlacementController = preload("res://firebase_system/placement_controller.gd")

# Systems
var camera: Camera3D
var _placement_controller: Node3D  # PlacementController instance
var _job_system: Node  # JobSystem autoload

# Units
var engineers: Array[Node3D] = []
var bulldozers: Array[Node3D] = []

# State
var selected_firebase: Node3D = null
var placement_mode: bool = false
var placement_type: String = ""  # "firebase", "clearing", "flatten"

# HUD
var hud_label: Label


func _ready() -> void:
	# Get autoload references
	_job_system = get_node_or_null("/root/JobSystem")
	if not _job_system:
		push_warning("[BuildingTestScene] JobSystem autoload not found - some features disabled")

	# Use TestSceneBase for consistent environment setup
	var setup: Dictionary = TestSceneBase.setup_environment(self, {
		"seed": 54321,
		"size": 200.0,
		"name": "Building System Test",
		"camera_position": Vector3(0.0, 50.0, 50.0),
	})
	camera = setup.get("camera")

	_setup_placement_controller()
	_spawn_initial_units()
	_setup_test_terrain()
	_connect_job_signals()

	# Create minimal test-specific HUD (top-left info label)
	hud_label = TestSceneBase.make_hud(self)

	print("=== Building System Test Scene ===")
	print("F: Place Firebase | C: Clear Terrain | L: Flatten | ESC: Cancel")
	print("E: Spawn Engineer | B: Spawn Bulldozer")
	print("1-9: Building hotkeys (after selecting placement)")


func _setup_placement_controller() -> void:
	"""Initialize PlacementController for ghost preview"""
	_placement_controller = PlacementController.new()
	_placement_controller.name = "PlacementController"
	add_child(_placement_controller)

	# Connect signals
	_placement_controller.placement_committed.connect(_on_placement_committed)
	_placement_controller.placement_cancelled.connect(_on_placement_cancelled)
	_placement_controller.validation_changed.connect(_on_validation_changed)
	print("[BuildingTest] PlacementController initialized")


func _connect_job_signals() -> void:
	"""Connect to JobSystem signals for feedback"""
	if not _job_system:
		return

	if _job_system.has_signal("job_created"):
		_job_system.job_created.connect(_on_job_created)
	if _job_system.has_signal("job_completed"):
		_job_system.job_completed.connect(_on_job_completed)
	if _job_system.has_signal("job_progress"):
		_job_system.job_progress.connect(_on_job_progress)


func _spawn_initial_units() -> void:
	"""Spawn starting engineers and bulldozers"""
	var terrain := get_node_or_null("/root/TerrainIntegration")

	# Spawn 4 engineers
	for i in 4:
		var angle: float = TAU * i / 4.0
		var pos := Vector3(cos(angle) * 5, 0, sin(angle) * 5)
		if terrain and terrain.has_method("get_height_at"):
			pos.y = terrain.get_height_at(pos)
		var engineer: Node3D = BuilderUnit.create_engineer(pos)
		add_child(engineer)
		engineers.append(engineer)

	# Spawn 2 bulldozers
	for i in 2:
		var pos := Vector3(-10 + i * 5, 0, -5)
		if terrain and terrain.has_method("get_height_at"):
			pos.y = terrain.get_height_at(pos)
		var bulldozer: Node3D = BuilderUnit.create_bulldozer(pos)
		add_child(bulldozer)
		bulldozers.append(bulldozer)

	print("[BuildingTest] Spawned %d engineers and %d bulldozers" % [engineers.size(), bulldozers.size()])


func _setup_test_terrain() -> void:
	"""Create some pre-cleared areas and jungle patches"""
	# Pre-clear the center area
	var terrain_system: Node = get_node_or_null("/root/TerrainClearingSystem")
	if terrain_system and terrain_system.has_method("instant_clear"):
		terrain_system.instant_clear(Vector3.ZERO, 20.0)

	# Create visual jungle patches (not cleared)
	_create_jungle_patch(Vector3(40, 0, 0), 15.0)
	_create_jungle_patch(Vector3(-40, 0, 0), 15.0)
	_create_jungle_patch(Vector3(0, 0, 40), 15.0)
	_create_jungle_patch(Vector3(0, 0, -40), 15.0)
	_create_jungle_patch(Vector3(30, 0, 30), 12.0)
	_create_jungle_patch(Vector3(-30, 0, -30), 12.0)


func _create_jungle_patch(center: Vector3, radius: float) -> void:
	"""Create visual representation of jungle"""
	var jungle := Node3D.new()
	jungle.name = "JunglePatch"
	jungle.position = center

	# Ground color change
	var ground_marker := MeshInstance3D.new()
	var circle := CylinderMesh.new()
	circle.top_radius = radius
	circle.bottom_radius = radius
	circle.height = 0.1
	ground_marker.mesh = circle
	ground_marker.position.y = 0.05

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.3, 0.1, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ground_marker.material_override = mat
	jungle.add_child(ground_marker)

	# Add some tree representations
	var tree_count: int = int(radius * 2)
	for i in tree_count:
		var tree := _create_simple_tree()
		var angle: float = randf() * TAU
		var dist: float = randf() * radius * 0.8
		tree.position = Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		tree.rotation.y = randf() * TAU
		jungle.add_child(tree)

	add_child(jungle)


func _create_simple_tree() -> Node3D:
	"""Create a simple tree mesh"""
	var tree := Node3D.new()

	# Trunk
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.15
	trunk_mesh.bottom_radius = 0.25
	trunk_mesh.height = 2.0
	trunk.mesh = trunk_mesh
	trunk.position.y = 1.0

	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.4, 0.25, 0.1)
	trunk.material_override = trunk_mat
	tree.add_child(trunk)

	# Foliage
	var foliage := MeshInstance3D.new()
	var foliage_mesh := SphereMesh.new()
	foliage_mesh.radius = 1.5
	foliage_mesh.height = 2.5
	foliage.mesh = foliage_mesh
	foliage.position.y = 3.0

	var foliage_mat := StandardMaterial3D.new()
	foliage_mat.albedo_color = Color(0.1, 0.4, 0.1)
	foliage.material_override = foliage_mat
	tree.add_child(foliage)

	return tree


func _process(_delta: float) -> void:
	_update_hud()
	_update_placement_cursor()


func _update_placement_cursor() -> void:
	"""Update PlacementController cursor position each frame"""
	if _placement_controller and _placement_controller.is_active() and camera:
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		var world_pos: Vector3 = _screen_to_world(mouse_pos)
		if world_pos != Vector3.INF:
			_placement_controller.update_cursor_position(world_pos)


func _update_hud() -> void:
	"""Update HUD status display"""
	if not hud_label:
		return

	var idle_engineers: int = _count_idle_units(engineers)
	var idle_bulldozers: int = _count_idle_units(bulldozers)
	var firebase_count: int = get_tree().get_nodes_in_group("firebases").size()

	# Get job counts
	var pending_jobs: int = 0
	var active_jobs: int = 0
	if _job_system:
		if _job_system.has_method("get_pending_job_count"):
			pending_jobs = _job_system.get_pending_job_count()
		if _job_system.has_method("get_in_progress_job_count"):
			active_jobs = _job_system.get_in_progress_job_count()

	var lines: PackedStringArray = [
		"BUILDING SYSTEM TEST",
		"Engineers: %d (%d idle)" % [engineers.size(), idle_engineers],
		"Bulldozers: %d (%d idle)" % [bulldozers.size(), idle_bulldozers],
		"Firebases: %d" % firebase_count,
		"Jobs: %d pending, %d active" % [pending_jobs, active_jobs],
	]

	if selected_firebase:
		lines.append("")
		lines.append("Selected: %s" % selected_firebase.firebase_name)
		var supply: float = selected_firebase.supply_level if "supply_level" in selected_firebase else 0.0
		var max_supply: float = selected_firebase.max_supply if "max_supply" in selected_firebase else 1000.0
		lines.append("Supply: %d/%d" % [int(supply), int(max_supply)])
		if selected_firebase.has_method("get_level_name"):
			lines.append("Level: %s" % selected_firebase.get_level_name())

	if _placement_controller and _placement_controller.is_active():
		lines.append("")
		lines.append("[PLACEMENT MODE: %s]" % _placement_controller.get_current_building_name())
		var msg: String = _placement_controller.get_validation_message()
		if msg != "":
			lines.append("Status: %s" % msg)
		else:
			lines.append("Click to place")
	elif placement_mode:
		lines.append("")
		lines.append("[MODE: %s]" % placement_type.to_upper())
		lines.append("Click terrain to place")

	hud_label.text = "\n".join(lines)


func _count_idle_units(units: Array[Node3D]) -> int:
	"""Count units that are idle (not working on a job)"""
	var count: int = 0
	for unit in units:
		if not is_instance_valid(unit):
			continue
		# Check if unit has a WorkerController with state
		var worker_ctrl: Node = unit.get_node_or_null("WorkerController")
		if is_instance_valid(worker_ctrl) and "state" in worker_ctrl:
			# WorkerController.State.IDLE == 0
			if worker_ctrl.state == WorkerController.State.IDLE:
				count += 1
		else:
			# Assume idle if no state tracking
			count += 1
	return count


func _input(event: InputEvent) -> void:
	# Let PlacementController handle input when active
	if _placement_controller and _placement_controller.is_active():
		if event is InputEventMouseButton or event is InputEventKey:
			var world_pos: Vector3 = Vector3.ZERO
			if event is InputEventMouseButton:
				world_pos = _screen_to_world((event as InputEventMouseButton).position)
			if _placement_controller.handle_input(event, world_pos):
				get_viewport().set_input_as_handled()
				return

	# Handle placement clicks for non-building modes
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if placement_mode:
				_handle_placement_click(event.position)
			else:
				# Try to select a firebase
				var world_pos: Vector3 = _screen_to_world(event.position)
				if world_pos != Vector3.INF:
					_try_select_firebase(world_pos)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if placement_mode:
				_cancel_placement()

	# Handle hotkeys
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_hotkey(event)


func _handle_hotkey(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ESCAPE:
			_cancel_placement()
			if _placement_controller:
				_placement_controller.cancel_placement()
		KEY_F:
			_start_firebase_placement()
		KEY_C:
			_start_clearing_placement()
		KEY_L:
			_start_flatten_placement()
		KEY_E:
			_spawn_engineer()
		KEY_B:
			_spawn_bulldozer()
		# Building hotkeys 1-9 - use PlacementController for ghost preview
		KEY_1:
			_start_building_placement(BuildingData.BuildingType.SANDBAG_LIGHT)
		KEY_2:
			_start_building_placement(BuildingData.BuildingType.SANDBAG_HEAVY)
		KEY_3:
			_start_building_placement(BuildingData.BuildingType.BUNKER)
		KEY_4:
			_start_building_placement(BuildingData.BuildingType.MACHINE_GUN_NEST)
		KEY_5:
			_start_building_placement(BuildingData.BuildingType.MORTAR_PIT)
		KEY_6:
			_start_building_placement(BuildingData.BuildingType.WATCHTOWER)
		KEY_7:
			_start_building_placement(BuildingData.BuildingType.HELIPAD)
		KEY_8:
			_start_building_placement(BuildingData.BuildingType.SUPPLY_DEPOT)
		KEY_9:
			_start_building_placement(BuildingData.BuildingType.MEDICAL_STATION)


func _start_building_placement(building_type: int) -> void:
	"""Start building placement with ghost preview using PlacementController"""
	if not _placement_controller:
		print("[BuildingTest] PlacementController not available")
		return

	_cancel_placement()  # Cancel any terrain placement mode
	_placement_controller.start_placement(building_type)
	print("[BuildingTest] Building placement started - press ESC to cancel")


func _start_firebase_placement() -> void:
	if _placement_controller:
		_placement_controller.cancel_placement()
	placement_mode = true
	placement_type = "firebase"
	print("[BuildingTest] Click to place firebase...")


func _start_clearing_placement() -> void:
	if _placement_controller:
		_placement_controller.cancel_placement()
	placement_mode = true
	placement_type = "clearing"
	print("[BuildingTest] Click to create CLEAR_TERRAIN job...")


func _start_flatten_placement() -> void:
	if _placement_controller:
		_placement_controller.cancel_placement()
	placement_mode = true
	placement_type = "flatten"
	print("[BuildingTest] Click to create FLATTEN_AREA job...")


func _cancel_placement() -> void:
	"""Cancel current placement mode"""
	if placement_mode:
		placement_mode = false
		placement_type = ""
		print("[BuildingTest] Placement cancelled")


func _handle_placement_click(screen_pos: Vector2) -> void:
	"""Handle left click during terrain placement mode"""
	var world_pos: Vector3 = _screen_to_world(screen_pos)
	if world_pos == Vector3.INF:
		return

	match placement_type:
		"firebase":
			_create_firebase_at(world_pos)
		"clearing":
			_create_clear_job_at(world_pos)
		"flatten":
			_create_flatten_job_at(world_pos)

	placement_mode = false
	placement_type = ""


func _create_firebase_at(world_pos: Vector3) -> void:
	"""Create a firebase at the given position"""
	var firebase: Node3D = Firebase.new()
	firebase.name = "Firebase_%d" % (get_tree().get_nodes_in_group("firebases").size() + 1)
	firebase.firebase_name = firebase.name
	firebase.global_position = world_pos
	add_child(firebase)
	print("[BuildingTest] Firebase created at %v" % world_pos)


func _create_clear_job_at(world_pos: Vector3) -> void:
	"""Create a CLEAR_TERRAIN job at the given position"""
	if not _job_system:
		print("[BuildingTest] JobSystem not available")
		return

	if _job_system.has_method("create_area_job"):
		var clear_size: float = 15.0  # 15m radius
		var half_size: float = clear_size * 0.5
		var min_corner := Vector3(world_pos.x - half_size, 0, world_pos.z - half_size)
		var max_corner := Vector3(world_pos.x + half_size, 0, world_pos.z + half_size)
		var job: Node = _job_system.create_area_job(0, min_corner, max_corner)  # 0 = CLEAR_TERRAIN
		if job:
			print("[BuildingTest] CLEAR_TERRAIN job created at %v (15m radius)" % world_pos)
	else:
		print("[BuildingTest] JobSystem.create_area_job() not available")


func _create_flatten_job_at(world_pos: Vector3) -> void:
	"""Create a FLATTEN_AREA job at the given position"""
	if not _job_system:
		print("[BuildingTest] JobSystem not available")
		return

	if _job_system.has_method("create_area_job"):
		var flatten_size: float = 20.0  # 20m radius
		var half_size: float = flatten_size * 0.5
		var min_corner := Vector3(world_pos.x - half_size, 0, world_pos.z - half_size)
		var max_corner := Vector3(world_pos.x + half_size, 0, world_pos.z + half_size)
		var job: Node = _job_system.create_area_job(1, min_corner, max_corner)  # 1 = FLATTEN_AREA
		if job:
			print("[BuildingTest] FLATTEN_AREA job created at %v (20m radius)" % world_pos)
	else:
		print("[BuildingTest] JobSystem.create_area_job() not available")


func _screen_to_world(screen_pos: Vector2) -> Vector3:
	"""Convert screen position to world position on ground plane"""
	if not camera:
		return Vector3.INF

	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)

	# Try physics raycast first
	var space: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 2000.0)
	query.collision_mask = 1

	var result: Dictionary = space.intersect_ray(query)
	if not result.is_empty() and result.has("position"):
		return result["position"] as Vector3

	# Fallback: intersect with y=0 plane
	if absf(dir.y) < 0.001:
		return Vector3.INF

	var t: float = -from.y / dir.y
	if t < 0:
		return Vector3.INF

	return from + dir * t


func _try_select_firebase(world_pos: Vector3) -> void:
	"""Try to select a firebase near the click position"""
	selected_firebase = null

	for fb in get_tree().get_nodes_in_group("firebases"):
		var radius: float = 30.0  # Default radius
		if fb.has_method("get_firebase_radius"):
			radius = fb.get_firebase_radius()
		if fb.global_position.distance_to(world_pos) < radius:
			selected_firebase = fb
			print("[BuildingTest] Selected firebase: %s" % fb.name)
			return


func _spawn_engineer() -> void:
	var pos := Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		pos.y = terrain.get_height_at(pos)
	var engineer: Node3D = BuilderUnit.create_engineer(pos)
	add_child(engineer)
	engineers.append(engineer)
	print("[BuildingTest] Spawned new engineer at %v" % pos)


func _spawn_bulldozer() -> void:
	var pos := Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		pos.y = terrain.get_height_at(pos)
	var bulldozer: Node3D = BuilderUnit.create_bulldozer(pos)
	add_child(bulldozer)
	bulldozers.append(bulldozer)
	print("[BuildingTest] Spawned new bulldozer at %v" % pos)


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_placement_committed(building_type: int, position: Vector3) -> void:
	"""Handle successful building placement"""
	var data: BuildingData = BuildingData.get_building_data(building_type)
	var building_name: String = data.display_name if data else "Building"
	print("[BuildingTest] Building placed: %s at %v" % [building_name, position])


func _on_placement_cancelled() -> void:
	"""Handle placement cancellation"""
	print("[BuildingTest] Building placement cancelled")


func _on_validation_changed(valid: bool, message: String) -> void:
	"""Handle validation status change"""
	if not valid and message != "":
		# Could show visual feedback here
		pass


func _on_job_created(job: Node) -> void:
	"""Handle job creation notification"""
	if job and "job_type" in job:
		print("[BuildingTest] Job created: type=%d" % job.job_type)


func _on_job_completed(job: Node) -> void:
	"""Handle job completion notification"""
	if job and "job_type" in job:
		print("[BuildingTest] Job completed: type=%d" % job.job_type)


func _on_job_progress(job: Node, progress: float) -> void:
	"""Handle job progress notification"""
	# Could update visual feedback
	pass
