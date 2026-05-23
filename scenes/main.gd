extends Node3D
## Main Scene - Phase 2: Units & Movement
## RealVietnamRTS entry point

const Squad = preload("res://battle_system/nodes/squad.gd")
const AudioManager = preload("res://battle_system/systems/audio_manager.gd")

# Loaded at runtime to avoid parse-time dependency issues
var VCControllerScript: GDScript = null
var AIDirectorScript: GDScript = null

# Unit data resources
var us_rifle_data: Resource = preload("res://battle_system/data/units/us_rifle_platoon.tres")
var us_engineer_data: Resource = preload("res://battle_system/data/units/us_engineers.tres")
var us_bulldozer_data: Resource = preload("res://battle_system/data/units/us_bulldozer.tres")
var us_apc_data: Resource = preload("res://battle_system/data/units/us_m113_apc.tres")
var vc_infantry_data: Resource = preload("res://battle_system/data/units/vc_infantry.tres")

@onready var camera: Camera3D = $RTSCamera

# System managers
var _ai_director: Node = null
var _vc_ai: Node = null
var _audio_manager: Node = null
var _terrain_ready: bool = false


func _ready() -> void:
	print("========================================")
	print("  RealVietnamRTS - Phase 2")
	print("  Units & Movement System")
	print("========================================")
	print("")
	print("Autoloads initialized:")
	print("  - GameEnums: ", GameEnums != null)
	print("  - BattleSignals: ", BattleSignals != null)
	print("  - SelectionManager: ", get_node_or_null("/root/SelectionManager") != null)
	print("  - MoveOrderHandler: ", get_node_or_null("/root/MoveOrderHandler") != null)
	print("  - CombatManager: ", CombatManager != null)
	print("  - TerrainIntegration: ", get_node_or_null("/root/TerrainIntegration") != null)
	print("")

	# Initialize terrain first (async)
	_init_terrain()

	# Initialize systems
	_init_systems()

	# Spawn test units after terrain is ready
	# For now spawn immediately on flat ground
	_spawn_test_units()

	# Set camera bounds to match map size (3000m x 3000m)
	if camera and camera.has_method("set_map_bounds"):
		camera.set_map_bounds(Vector3(0, 0, 0), Vector3(3000, 500, 3000))

	# Center camera on map center where units are
	if camera and camera.has_method("center_on_position"):
		camera.center_on_position(Vector3(1500.0, 0.0, 1500.0), true)

	print("")
	print("Controls:")
	print("  WASD: Pan camera")
	print("  Mouse Wheel: Zoom")
	print("  Middle Mouse: Rotate/Tilt")
	print("  Left Click: Select unit")
	print("  Left Drag: Box select")
	print("  Right Click: Move order")
	print("  Shift+Right Click: Clear terrain (engineers)")
	print("  A: Attack nearest enemy")
	print("  C: Clear terrain at cursor (engineers)")
	print("  Shift+Click: Add to selection")
	print("  Ctrl+0-9: Save group")
	print("  0-9: Recall group")
	print("  ESC: Quit")
	print("")


func _init_terrain() -> void:
	"""Initialize terrain via TerrainIntegration autoload"""
	var terrain_integration: Node = get_node_or_null("/root/TerrainIntegration")
	if not terrain_integration:
		push_warning("[Main] TerrainIntegration autoload not found")
		return

	# Remove old ground plane if exists
	var old_ground: Node = get_node_or_null("GroundPlane")
	if old_ground:
		old_ground.queue_free()

	# Initialize terrain with camera reference
	if terrain_integration.has_method("init_terrain") and camera:
		terrain_integration.init_terrain(camera)
		print("  - Terrain initialized via TerrainIntegration")
	else:
		print("  - TerrainIntegration.init_terrain() not found or no camera")

	_terrain_ready = true


func _init_systems() -> void:
	"""Initialize game systems"""
	# Audio manager
	_audio_manager = AudioManager.new()
	_audio_manager.name = "AudioManager"
	add_child(_audio_manager)

	# Load AI scripts at runtime (avoids parse-time dependency issues)
	AIDirectorScript = load("res://battle_system/ai/ai_director.gd")
	VCControllerScript = load("res://battle_system/ai/vc_controller.gd")

	# AI Director (controls pacing and coordinates enemy AI)
	if AIDirectorScript:
		_ai_director = AIDirectorScript.new()
		_ai_director.name = "AIDirector"
		add_child(_ai_director)

	# Enemy AI controller (VC guerrilla tactics)
	if VCControllerScript:
		_vc_ai = VCControllerScript.new()
		_vc_ai.name = "VCController"
		_vc_ai.add_to_group("enemy_controllers")
		_vc_ai.enable_waves = true  # Enable wave spawning
		_vc_ai.wave_interval = 45.0  # First wave at 45 seconds
		add_child(_vc_ai)

	print("Systems initialized:")
	print("  - AudioManager")
	print("  - AIDirector: %s" % (AIDirectorScript != null))
	print("  - VCController: %s" % (VCControllerScript != null))


func _spawn_test_units() -> void:
	print("Spawning test units...")

	# Map center - map is 3000m, so center is at 1500
	var center := Vector3(1500.0, 0.0, 1500.0)

	# Spawn US forces (player controlled) - west of center
	_spawn_squad(us_rifle_data, center + Vector3(-10, 0, 0), "US_Rifle_1")
	_spawn_squad(us_rifle_data, center + Vector3(-10, 0, 5), "US_Rifle_2")
	_spawn_squad(us_engineer_data, center + Vector3(-15, 0, 2.5), "US_Engineers")
	_spawn_squad(us_bulldozer_data, center + Vector3(-20, 0, 0), "US_Bulldozer")
	_spawn_squad(us_apc_data, center + Vector3(-20, 0, 5), "US_APC")

	# Spawn VC forces (enemy) - east of center
	_spawn_squad(vc_infantry_data, center + Vector3(30, 0, 0), "VC_Squad_1")
	_spawn_squad(vc_infantry_data, center + Vector3(30, 0, 5), "VC_Squad_2")
	_spawn_squad(vc_infantry_data, center + Vector3(35, 0, 2.5), "VC_Squad_3")

	print("  Spawned 5 US units (green) - includes Bulldozer")
	print("  Spawned 3 VC units (brown)")


func _spawn_squad(squad_data: Resource, spawn_pos: Vector3, unit_name: String) -> Squad:
	var squad := Squad.new()
	squad.name = unit_name
	squad.data = squad_data

	# Get terrain height at spawn position
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		spawn_pos.y = terrain.get_height_at(spawn_pos)

	squad.position = spawn_pos
	add_child(squad)

	# Emit spawn signal for systems (health bars, etc.)
	var faction: int = squad_data.faction if squad_data.has_method("get") else GameEnums.Faction.US_ARMY
	BattleSignals.unit_spawned.emit(squad, faction)

	return squad


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()

	# A key triggers attack-move (attack nearest enemy)
	if event is InputEventKey and event.pressed and event.keycode == KEY_A:
		_attack_move_selected()

	# C key triggers clearing at cursor position (engineers only)
	if event is InputEventKey and event.pressed and event.keycode == KEY_C:
		_clear_at_cursor()


func _attack_move_selected() -> void:
	var sel_mgr: Node = get_node_or_null("/root/SelectionManager")
	if not sel_mgr:
		return
	var selected: Array = sel_mgr.get_selected_units()
	if selected.is_empty():
		return

	# Find nearest enemy for each selected unit
	for unit in selected:
		if not is_instance_valid(unit):
			continue
		if not unit.is_player_controlled:
			continue

		var nearest_enemy: Node = _find_nearest_enemy(unit)
		if nearest_enemy:
			unit.attack(nearest_enemy)
			print("  %s attacking %s" % [unit.name, nearest_enemy.name])


func _clear_at_cursor() -> void:
	var sel_mgr: Node = get_node_or_null("/root/SelectionManager")
	if not sel_mgr:
		return
	var selected: Array = sel_mgr.get_selected_units()
	if selected.is_empty():
		return

	# Raycast to get cursor world position
	var cursor_pos: Vector3 = _get_cursor_world_position()
	if cursor_pos == Vector3.INF:
		return

	# Issue clearing orders to engineers
	for unit in selected:
		if not is_instance_valid(unit):
			continue
		if not unit.is_player_controlled:
			continue

		if unit.has_method("can_clear") and unit.can_clear():
			if unit.has_method("start_clearing"):
				unit.start_clearing(cursor_pos, 15.0)
				print("  %s clearing at %s" % [unit.name, cursor_pos])


func _get_cursor_world_position() -> Vector3:
	"""Raycast from cursor to get world position"""
	if not camera:
		return Vector3.INF

	var viewport: Viewport = get_viewport()
	if not viewport:
		return Vector3.INF

	var mouse_pos: Vector2 = viewport.get_mouse_position()
	var world_3d: World3D = viewport.get_world_3d()
	if not world_3d:
		return Vector3.INF

	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(mouse_pos)
	var ray_end: Vector3 = ray_origin + ray_dir * 1000

	var space: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1  # Terrain layer only

	var result: Dictionary = space.intersect_ray(query)
	if result:
		return result.position

	# Fallback: intersect with Y=0 plane
	if ray_dir.y != 0:
		var t: float = -ray_origin.y / ray_dir.y
		if t > 0:
			return ray_origin + ray_dir * t

	return Vector3.INF


func _find_nearest_enemy(unit: Node) -> Node:
	var enemies: Array = get_tree().get_nodes_in_group("enemy_units")
	var nearest: Node = null
	var nearest_dist: float = INF

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("get") and enemy.get("state") == Squad.State.DEAD:
			continue

		var dist: float = unit.global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy

	return nearest
