extends Node3D

## Building System Test Scene
## Demonstrates automated base building with engineers and bulldozers
##
## Uses BattleHUD autoload for unified selection/command UI.
## Scene-specific status shown in top-left HUD label.
##
## Controls:
## - Left-click: Select units / Click terrain when in placement mode
## - Right-click: Move selected units / Cancel placement
## - F: Place Firebase mode
## - C: Clear Terrain mode
## - 1-9: Building hotkeys (when firebase selected)
## - E: Spawn Engineer
## - B: Spawn Bulldozer
## - ESC: Cancel placement mode

const TestSceneBase = preload("res://test_scenes/common/test_scene_base.gd")
const BuilderUnit = preload("res://firebase_system/test/builder_unit.gd")
const BuilderAI = preload("res://firebase_system/builder_ai.gd")
const BuildingData = preload("res://firebase_system/building_data.gd")
const Firebase = preload("res://firebase_system/firebase.gd")

# Systems
var builder_ai: BuilderAI
var camera: Camera3D

# Units
var engineers: Array[Node3D] = []
var bulldozers: Array[Node3D] = []

# State
var selected_firebase: Node3D = null
var placement_mode: bool = false
var placement_type: String = ""  # "firebase" or "clearing"

# HUD
var hud_label: Label


func _ready() -> void:
	# Use TestSceneBase for consistent environment setup
	var setup: Dictionary = TestSceneBase.setup_environment(self, {
		"seed": 54321,
		"size": 200.0,
		"name": "Building System Test",
		"camera_position": Vector3(0.0, 50.0, 50.0),
	})
	camera = setup.get("camera")

	_setup_builder_ai()
	_spawn_initial_units()
	_setup_test_terrain()

	# Create minimal test-specific HUD (top-left info label)
	hud_label = TestSceneBase.make_hud(self)

	print("=== Building System Test Scene ===")
	print("F: Place Firebase | C: Clear Terrain | ESC: Cancel")
	print("E: Spawn Engineer | B: Spawn Bulldozer")
	print("Select firebase then press 1-9 for buildings")


func _setup_builder_ai() -> void:
	"""Initialize the builder AI system"""
	builder_ai = BuilderAI.new()
	builder_ai.name = "BuilderAI"
	add_child(builder_ai)

	# Connect signals
	builder_ai.work_assigned.connect(_on_work_assigned)
	builder_ai.work_completed.connect(_on_work_completed)
	builder_ai.firebase_construction_started.connect(_on_firebase_started)


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
		builder_ai.register_engineer(engineer)

	# Spawn 2 bulldozers
	for i in 2:
		var pos := Vector3(-10 + i * 5, 0, -5)
		if terrain and terrain.has_method("get_height_at"):
			pos.y = terrain.get_height_at(pos)
		var bulldozer: Node3D = BuilderUnit.create_bulldozer(pos)
		add_child(bulldozer)
		bulldozers.append(bulldozer)
		builder_ai.register_bulldozer(bulldozer)


func _setup_test_terrain() -> void:
	"""Create some pre-cleared areas and jungle patches"""
	# Pre-clear the center area
	var terrain_system: Node = get_node_or_null("/root/TerrainClearingSystem")
	if terrain_system:
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
	_update_unit_displays()


func _update_hud() -> void:
	"""Update HUD status display"""
	if not hud_label:
		return

	var idle_counts: Dictionary = builder_ai.get_idle_count()
	var firebase_count: int = get_tree().get_nodes_in_group("firebases").size()

	var lines: PackedStringArray = [
		"BUILDING SYSTEM TEST",
		"Engineers: %d (%d idle)" % [engineers.size(), idle_counts["engineers"]],
		"Bulldozers: %d (%d idle)" % [bulldozers.size(), idle_counts["bulldozers"]],
		"Firebases: %d" % firebase_count,
	]

	if selected_firebase:
		lines.append("")
		lines.append("Selected: %s" % selected_firebase.firebase_name)
		lines.append("Supply: %d/%d" % [int(selected_firebase.supply_level), int(selected_firebase.max_supply)])
		lines.append("Level: %s" % selected_firebase.get_level_name())

	if placement_mode:
		lines.append("")
		lines.append("[MODE: %s]" % placement_type.to_upper())
		lines.append("Click terrain to place")

	hud_label.text = "\n".join(lines)


func _update_unit_displays() -> void:
	"""Update unit status displays based on their tasks"""
	for unit in engineers + bulldozers:
		if not is_instance_valid(unit):
			continue

		var task: Dictionary = builder_ai.get_unit_task(unit)
		var task_type: int = task.get("type", 0)

		var status: String = "Idle"
		match task_type:
			1:  # MOVING
				status = "Moving"
			2:  # CLEARING
				status = "Clearing"
			3:  # BUILDING
				status = "Building"

		if unit.has_method("set_task_status"):
			unit.set_task_status(status)


func _input(event: InputEvent) -> void:
	# Handle placement clicks
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if placement_mode:
				_handle_placement_click(event.position)
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
		KEY_F:
			_start_firebase_placement()
		KEY_C:
			_start_clearing_placement()
		KEY_E:
			_spawn_engineer()
		KEY_B:
			_spawn_bulldozer()
		# Building hotkeys 1-9
		KEY_1:
			_request_building(BuildingData.BuildingType.SANDBAG_LIGHT)
		KEY_2:
			_request_building(BuildingData.BuildingType.SANDBAG_HEAVY)
		KEY_3:
			_request_building(BuildingData.BuildingType.BUNKER)
		KEY_4:
			_request_building(BuildingData.BuildingType.MACHINE_GUN_NEST)
		KEY_5:
			_request_building(BuildingData.BuildingType.MORTAR_PIT)
		KEY_6:
			_request_building(BuildingData.BuildingType.WATCHTOWER)
		KEY_7:
			_request_building(BuildingData.BuildingType.HELIPAD)
		KEY_8:
			_request_building(BuildingData.BuildingType.AMMO_BUNKER)
		KEY_9:
			_request_building(BuildingData.BuildingType.MEDICAL_STATION)


func _start_firebase_placement() -> void:
	placement_mode = true
	placement_type = "firebase"
	print("[BuildingTest] Click to place firebase...")


func _start_clearing_placement() -> void:
	placement_mode = true
	placement_type = "clearing"
	print("[BuildingTest] Click to request terrain clearing...")


func _cancel_placement() -> void:
	"""Cancel current placement mode"""
	if placement_mode:
		placement_mode = false
		placement_type = ""
		print("[BuildingTest] Placement cancelled")


func _handle_placement_click(screen_pos: Vector2) -> void:
	"""Handle left click during placement mode"""
	var world_pos: Vector3 = _screen_to_world(screen_pos)
	if world_pos == Vector3.INF:
		return

	if placement_type == "firebase":
		builder_ai.request_firebase(world_pos, "Firebase %d" % (get_tree().get_nodes_in_group("firebases").size() + 1))
	elif placement_type == "clearing":
		builder_ai.request_clearing(world_pos)

	placement_mode = false
	placement_type = ""


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
		if fb.global_position.distance_to(world_pos) < fb.get_firebase_radius():
			selected_firebase = fb
			print("[BuildingTest] Selected firebase: %s" % fb.firebase_name)
			return


func _request_building(building_type: int) -> void:
	"""Request a building at the selected firebase"""
	if not selected_firebase:
		print("[BuildingTest] Select a firebase first! (click on one)")
		return

	if builder_ai.request_building(selected_firebase, building_type):
		print("[BuildingTest] Building queued!")
	else:
		print("[BuildingTest] Cannot build - check supply or zones")


func _spawn_engineer() -> void:
	var pos := Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		pos.y = terrain.get_height_at(pos)
	var engineer: Node3D = BuilderUnit.create_engineer(pos)
	add_child(engineer)
	engineers.append(engineer)
	builder_ai.register_engineer(engineer)
	print("[BuildingTest] Spawned new engineer")


func _spawn_bulldozer() -> void:
	var pos := Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		pos.y = terrain.get_height_at(pos)
	var bulldozer: Node3D = BuilderUnit.create_bulldozer(pos)
	add_child(bulldozer)
	bulldozers.append(bulldozer)
	builder_ai.register_bulldozer(bulldozer)
	print("[BuildingTest] Spawned new bulldozer")


# BuilderAI Callbacks

func _on_work_assigned(unit: Node3D, task: Dictionary) -> void:
	print("[BuildingTest] Work assigned to %s: %s" % [unit.name, task.get("type", "unknown")])


func _on_work_completed(unit: Node3D, _task: Dictionary) -> void:
	print("[BuildingTest] Work completed by %s" % unit.name)


func _on_firebase_started(position: Vector3) -> void:
	print("[BuildingTest] Firebase construction started at %s" % position)
