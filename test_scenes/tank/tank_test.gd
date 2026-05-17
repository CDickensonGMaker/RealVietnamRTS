extends Node3D
## Tank Test Scene
##
## Tests Tank class:
## - Independent turret rotation (turret tracks target, hull turns slowly)
## - Tank main gun firing at long range
## - Coaxial MG at close range
## - Slope rejection at steep hills (max_slope ~0.35 for tanks)
## - Pathfinding around buildings
##
## Controls:
## - Left-click drag: select tanks
## - Right-click: move
## - Right-click on enemy: attack
## - 1/2/3: spawn target at 100m / 200m / 400m
## - F: spawn enemy tank

const TestSceneBase = preload("res://test_scenes/common/test_scene_base.gd")
const Tank = preload("res://battle_system/units/tank.gd")
const Squad = preload("res://battle_system/nodes/squad.gd")
const SquadData = preload("res://battle_system/data/squad_data.gd")

var hud: Label
var player_tanks: Array[Node3D] = []
var enemy_units: Array[Node3D] = []


func _ready() -> void:
	TestSceneBase.setup_environment(self, {
		"seed": 33333,
		"size": 500.0,
		"name": "Tank Test Scene",
	})

	hud = TestSceneBase.make_hud(self)

	# Building obstacles - tanks must path around (and may crush smaller obstacles in future)
	var buildings: Array = [
		Vector3(50.0, 0.0, 20.0),
		Vector3(50.0, 0.0, -20.0),
		Vector3(80.0, 0.0, 0.0),
	]
	var building_sizes: Array = [
		Vector3(10.0, 6.0, 10.0),
		Vector3(10.0, 6.0, 10.0),
		Vector3(15.0, 8.0, 15.0),
	]
	TestSceneBase.spawn_obstacle_buildings(self, buildings, building_sizes)

	# Range markers - tanks reach further than infantry
	TestSceneBase.spawn_range_markers(
		self, Vector3(-10.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0),
		[100, 200, 400, 800, 1500]
	)

	# Spawn 2 M48 Patton tanks
	var terrain := get_node_or_null("/root/TerrainIntegration")
	for i in 2:
		var tank: Node3D = _make_tank(true)
		add_child(tank)
		var spawn_pos := Vector3(float(i) * 8.0 - 4.0, 0.0, 40.0)
		if terrain and terrain.has_method("get_height_at"):
			spawn_pos.y = terrain.get_height_at(spawn_pos) + 0.1
		tank.global_position = spawn_pos
		player_tanks.append(tank)

	for tank in player_tanks:
		if tank.has_signal("path_blocked_by_slope"):
			tank.path_blocked_by_slope.connect(_on_slope_blocked.bind(tank))
		if tank.has_signal("fired_main_gun"):
			tank.fired_main_gun.connect(_on_main_gun_fired)

	print("[TankTest] Spawned %d player tanks (M48 Patton)" % player_tanks.size())
	print("[TankTest] Tanks have max_slope = 0.35 (steeper than infantry's 0.65)")
	print("[TankTest] Try ordering tanks up the hills - they will stop sooner than infantry would.")


func _make_tank(player: bool) -> Node3D:
	var tank: Tank = Tank.new()
	var data := SquadData.new()
	data.display_name = "M48 Patton" if player else "T-54"
	data.faction = 0 if player else 3
	data.squad_size = 1  # Vehicle = 1 "unit"
	data.health_per_soldier = 1500.0
	data.armor = 50.0
	data.attack_range = 1500.0  # M48 effective range
	data.move_speed = 12.0
	data.rotation_speed = 1.5
	# Tanks: stricter verticality
	data.max_slope = 0.35
	data.slope_speed_penalty = 0.6
	data.is_vehicle = true
	tank.data = data
	tank.is_player_controlled = player
	tank.tank_class = Tank.TankClass.MEDIUM
	tank.main_gun_id = "m48_main_gun"
	tank.coax_gun_id = "coax_mg"
	return tank


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_1: _spawn_target(Vector3(-100.0, 0.0, 0.0))
			KEY_2: _spawn_target(Vector3(-200.0, 0.0, 0.0))
			KEY_3: _spawn_target(Vector3(-400.0, 0.0, 0.0))
			KEY_F: _spawn_enemy_tank()


func _spawn_target(pos: Vector3) -> void:
	var dummy: Squad = Squad.new()
	var data := SquadData.new()
	data.display_name = "Tank Target"
	data.faction = 2
	data.squad_size = 1
	data.health_per_soldier = 800.0
	data.armor = 20.0
	data.move_speed = 0.0
	data.max_slope = 0.0
	dummy.data = data
	dummy.is_player_controlled = false
	add_child(dummy)
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		pos.y = terrain.get_height_at(pos) + 0.1
	dummy.global_position = pos
	enemy_units.append(dummy)
	print("[TankTest] Target spawned at %.0fm" % pos.length())


func _spawn_enemy_tank() -> void:
	var tank: Node3D = _make_tank(false)
	add_child(tank)
	var spawn_pos := Vector3(-150.0, 0.0, 0.0)
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		spawn_pos.y = terrain.get_height_at(spawn_pos) + 0.1
	tank.global_position = spawn_pos
	enemy_units.append(tank)
	if player_tanks.size() > 0 and tank.has_method("attack"):
		tank.attack(player_tanks[0])
	print("[TankTest] Enemy T-54 spawned and engaging")


func _on_slope_blocked(pos: Vector3, slope: float, tank: Node) -> void:
	print("[TankTest] %s blocked by slope %.2f at %s" % [tank.name, slope, pos])


func _on_main_gun_fired(target_pos: Vector3) -> void:
	print("[TankTest] Main gun fired at %s" % target_pos)


func _process(_delta: float) -> void:
	if not hud:
		return
	var lines: Array = ["TANK TEST",
		"Player tanks: %d" % player_tanks.size(),
		"Enemies: %d" % enemy_units.size(),
	]
	for tank in player_tanks:
		if is_instance_valid(tank) and tank.has_method("get_main_gun_ammo"):
			lines.append("  %s: main %d / coax %d" % [tank.name, tank.get_main_gun_ammo(), tank.get_coax_ammo()])
	lines.append("")
	lines.append("1/2/3: target at 100m/200m/400m")
	lines.append("F: spawn enemy T-54")
	hud.text = "\n".join(lines)
