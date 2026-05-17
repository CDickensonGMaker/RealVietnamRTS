extends Node3D
## Infantry Test Scene
##
## Tests:
## - Squad formation and movement
## - Firing range with markers at 25m, 100m, 200m, 300m, 550m (M16 max)
## - Pathfinding around buildings
## - Slope-aware movement: gradual hills to test verticality cutoff
## - Morale/suppression under fire
##
## Controls (via autoloads):
## - WASD: Pan camera
## - Mouse wheel: Zoom
## - Middle-drag: Rotate/tilt camera
## - Left-click drag: Select squads
## - Right-click: Move selected units
## - Shift+click: Add to selection
## - Ctrl+1-9: Save control group
## - 1-9: Recall control group
## - A: Toggle attack-move mode
##
## Test controls:
## - 1/2/3: Spawn targets at various ranges
## - F: Spawn enemy squad to test morale

const TestSceneBase = preload("res://test_scenes/common/test_scene_base.gd")
const Squad = preload("res://battle_system/nodes/squad.gd")
const SquadData = preload("res://battle_system/data/squad_data.gd")

var player_squads: Array[Node3D] = []
var enemy_squads: Array[Node3D] = []
var target_dummies: Array[Node3D] = []


func _ready() -> void:
	TestSceneBase.setup_environment(self, {
		"seed": 11111,
		"size": 400.0,
		"name": "Infantry Test Scene",
	})

	# Create starter HQ base - cleared area with sandbags, wire, towers, barracks
	var hq_center := Vector3(0.0, 0.0, 30.0)
	var hq_data: Dictionary = TestSceneBase.spawn_starter_hq(self, hq_center, 60.0)
	var spawn_points: Array = hq_data.get("spawn_points", [])

	# Building obstacle field east of HQ (units must path around)
	var buildings: Array = [
		Vector3(80.0, 0.0, 30.0),
		Vector3(95.0, 0.0, 15.0),
		Vector3(85.0, 0.0, 0.0),
		Vector3(100.0, 0.0, 35.0),
		Vector3(110.0, 0.0, 20.0),
	]
	TestSceneBase.spawn_obstacle_buildings(self, buildings)

	# Firing range down the road from HQ (north direction, negative Z)
	# Range markers at 25m, 100m, 200m, 300m, 400m, 550m from HQ
	TestSceneBase.spawn_range_markers(
		self, hq_center + Vector3(0.0, 0.0, -40.0), Vector3(0.0, 0.0, -1.0),
		[25, 100, 200, 300, 400, 550]
	)

	# Spawn player rifle squads inside the HQ base
	var terrain := get_node_or_null("/root/TerrainIntegration")
	var num_squads: int = mini(4, spawn_points.size())  # Spawn up to 4 squads
	for i in num_squads:
		var squad: Node3D = _make_squad(true)
		add_child(squad)
		var spawn_pos: Vector3 = spawn_points[i] if i < spawn_points.size() else hq_center
		# Place on terrain surface (HQ ground is slightly elevated)
		if terrain and terrain.has_method("get_height_at"):
			var terrain_h: float = terrain.get_height_at(spawn_pos)
			spawn_pos.y = maxf(spawn_pos.y, terrain_h + 0.1)
		squad.global_position = spawn_pos
		player_squads.append(squad)

	# Connect signals on each squad for morale/slope debug
	for squad in player_squads:
		if squad.has_signal("suppression_changed"):
			squad.suppression_changed.connect(_on_suppression_changed.bind(squad))
		if squad.has_signal("path_blocked_by_slope"):
			squad.path_blocked_by_slope.connect(_on_slope_blocked.bind(squad))

	print("[InfantryTest] Spawned %d player squads" % player_squads.size())
	print("[InfantryTest] Hills are placed at the NORTH end (positive Z). Try ordering squads to walk up them - they should slow and eventually stop.")
	print("[InfantryTest] Firing range runs NORTH from HQ (negative Z). Press 1/2/3 for targets at different ranges.")
	print("[InfantryTest] Press F to spawn enemy squad to test morale.")


func _make_squad(player: bool, faction: int = 0) -> Node3D:
	var squad: Squad = Squad.new()
	var data := SquadData.new()
	data.display_name = "US Rifle Squad" if player else "VC Infantry"
	data.faction = 0 if player else 2  # US_ARMY vs VC
	data.squad_size = 10
	data.health_per_soldier = 100.0
	data.attack_range = 25.0
	data.move_speed = 5.0
	data.training_level = 1  # REGULAR
	# Slope parameters: infantry has the highest verticality
	data.max_slope = 0.65          # Can climb up to ~60 degrees
	data.slope_speed_penalty = 0.7 # At max slope, moves at 30% speed
	data.can_capture = true
	squad.data = data
	squad.is_player_controlled = player
	squad.primary_weapon = "m16" if player else "ak47"

	# Add to groups for selection and unit management
	squad.add_to_group("all_units")
	if player:
		squad.add_to_group("player_units")
		squad.add_to_group("selectable_units")
	else:
		squad.add_to_group("enemy_units")

	return squad


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not event.pressed:
		return
	var key := event as InputEventKey
	match key.keycode:
		KEY_1:
			_spawn_target(Vector3(-50.0, 0.0, 0.0))
		KEY_2:
			_spawn_target(Vector3(-200.0, 0.0, 0.0))
		KEY_3:
			_spawn_target(Vector3(-400.0, 0.0, 0.0))
		KEY_F:
			_spawn_enemy_squad()


func _spawn_target(pos: Vector3) -> void:
	# Simple stationary target dummy with HP
	var dummy: Squad = Squad.new()
	var data := SquadData.new()
	data.display_name = "Target Dummy"
	data.faction = 2  # Enemy
	data.squad_size = 1
	data.health_per_soldier = 200.0
	data.move_speed = 0.0
	data.max_slope = 0.0  # Can't move
	dummy.data = data
	dummy.is_player_controlled = false
	add_child(dummy)
	# Place on terrain surface
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		pos.y = terrain.get_height_at(pos) + 0.1
	dummy.global_position = pos
	target_dummies.append(dummy)
	print("[InfantryTest] Spawned target at range %.0fm" % pos.length())


func _spawn_enemy_squad() -> void:
	var squad: Node3D = _make_squad(false)
	add_child(squad)
	var spawn_pos := Vector3(-80.0, 0.0, 0.0)
	# Place on terrain surface
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		spawn_pos.y = terrain.get_height_at(spawn_pos) + 0.1
	squad.global_position = spawn_pos
	enemy_squads.append(squad)
	# Make it attack the closest player squad
	if player_squads.size() > 0 and squad.has_method("attack"):
		squad.attack(player_squads[0])
	print("[InfantryTest] Spawned enemy squad - will engage")


func _on_suppression_changed(amount: float, squad: Node) -> void:
	print("[InfantryTest] %s suppression: %.2f" % [squad.name, amount])


func _on_slope_blocked(pos: Vector3, slope: float, squad: Node) -> void:
	print("[InfantryTest] %s blocked by slope %.2f at %s" % [squad.name, slope, pos])


