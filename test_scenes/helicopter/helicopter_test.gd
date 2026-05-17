extends Node3D
## Helicopter Test Scene
##
## Tests three helicopter behaviors at once:
## - Shuttle: UH-1 Huey ferrying squads between LZ A and LZ B
## - Gunship: AH-1 Cobra performing rocket runs and MG strafing with
##   GunshipBehavior
## - WAITING zone: shuttle parks at the staging area when no squads are
##   waiting to be moved, instead of pestering the player to load more troops
##
## Controls:
## - 1: order shuttle to ferry next ready squad
## - 2: order gunship to rocket-run nearest enemy
## - 3: order gunship to strafe nearest enemy
## - 4: order gunship to patrol the AO
## - F: spawn enemy squad in the AO

const TestSceneBase = preload("res://test_scenes/common/test_scene_base.gd")
const Squad = preload("res://battle_system/nodes/squad.gd")
const SquadData = preload("res://battle_system/data/squad_data.gd")
const GunshipBehavior = preload("res://battle_system/units/gunship_behavior.gd")
# Existing user assets
const Helicopter = preload("res://helicopter_system/helicopter.gd")
const ShuttleHelicopter = preload("res://helicopter_system/test/shuttle_helicopter.gd")
const LandingZone = preload("res://helicopter_system/landing_zone.gd")

var hud: Label
var shuttle: Node3D = null
var gunship: Node3D = null
var gunship_behavior: GunshipBehavior = null
var lz_pickup: Node3D = null
var lz_dropoff: Node3D = null
var waiting_zone: Node3D = null
var pickup_squads: Array[Node3D] = []
var enemies: Array[Node3D] = []


func _ready() -> void:
	TestSceneBase.setup_environment(self, {
		"seed": 66666,
		"size": 800.0,
		"name": "Helicopter Test Scene",
	})

	hud = TestSceneBase.make_hud(self)

	var terrain := get_node_or_null("/root/TerrainIntegration")

	# Pickup LZ (south)
	lz_pickup = LandingZone.new()
	lz_pickup.name = "LZ_Pickup"
	add_child(lz_pickup)
	var pickup_pos := Vector3(0.0, 0.0, 80.0)
	if terrain and terrain.has_method("get_height_at"):
		pickup_pos.y = terrain.get_height_at(pickup_pos)
	lz_pickup.global_position = pickup_pos

	# Dropoff LZ (north, across the AO)
	lz_dropoff = LandingZone.new()
	lz_dropoff.name = "LZ_Dropoff"
	add_child(lz_dropoff)
	var dropoff_pos := Vector3(0.0, 0.0, -200.0)
	if terrain and terrain.has_method("get_height_at"):
		dropoff_pos.y = terrain.get_height_at(dropoff_pos)
	lz_dropoff.global_position = dropoff_pos

	# Waiting zone marker - where shuttle hovers when idle
	waiting_zone = Node3D.new()
	waiting_zone.name = "WaitingZone"
	waiting_zone.global_position = Vector3(120.0, 60.0, 80.0)
	add_child(waiting_zone)
	_build_waiting_marker(waiting_zone)

	# Spawn squads waiting at pickup LZ
	for i in 3:
		var squad: Node3D = _make_rifle_squad()
		add_child(squad)
		var squad_pos := lz_pickup.global_position + Vector3(float(i) * 5.0 - 5.0, 0.0, 3.0)
		if terrain and terrain.has_method("get_height_at"):
			squad_pos.y = terrain.get_height_at(squad_pos) + 0.1
		squad.global_position = squad_pos
		pickup_squads.append(squad)

	# Spawn shuttle helicopter (in air, no terrain snap needed)
	shuttle = ShuttleHelicopter.new()
	shuttle.name = "Huey Shuttle"
	add_child(shuttle)
	shuttle.global_position = waiting_zone.global_position
	if "pickup_lz" in shuttle:
		shuttle.pickup_lz = lz_pickup
	if "dropoff_lz" in shuttle:
		shuttle.dropoff_lz = lz_dropoff
	if "waiting_position" in shuttle:
		shuttle.waiting_position = waiting_zone.global_position

	# Spawn gunship with GunshipBehavior attached (in air, no terrain snap needed)
	gunship = Helicopter.new()
	gunship.name = "Cobra Gunship"
	add_child(gunship)
	gunship.global_position = Vector3(-100.0, 60.0, 80.0)
	if "heli_type" in gunship:
		gunship.heli_type = 1  # AH-1 Cobra style
	if "is_armed" in gunship:
		gunship.is_armed = true
	if "cruise_altitude" in gunship:
		gunship.cruise_altitude = 60.0
	if "max_speed" in gunship:
		gunship.max_speed = 50.0

	gunship_behavior = GunshipBehavior.new()
	gunship_behavior.name = "GunshipBehavior"
	gunship.add_child(gunship_behavior)

	# Signal hookups
	if gunship_behavior:
		gunship_behavior.rocket_run_started.connect(_on_gunship_rocket_run)
		gunship_behavior.strafe_started.connect(_on_gunship_strafe)
		gunship_behavior.target_acquired.connect(_on_gunship_acquired)

	print("[HelicopterTest] Shuttle parked at WaitingZone")
	print("[HelicopterTest] Gunship in standby - press 2/3/4 for action")
	print("[HelicopterTest] Press F to spawn enemy in AO")


func _build_waiting_marker(parent: Node3D) -> void:
	# Visual cone showing where shuttle should park when idle
	var marker := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 8.0
	mesh.height = 4.0
	marker.mesh = mesh
	marker.position.y = -30.0  # Project down toward ground

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 0.9, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = mat
	parent.add_child(marker)


func _make_rifle_squad(player: bool = true) -> Node3D:
	var squad: Squad = Squad.new()
	var data := SquadData.new()
	data.display_name = "US Rifle Squad" if player else "VC Infantry"
	data.faction = 0 if player else 2
	data.squad_size = 10
	data.health_per_soldier = 100.0
	data.attack_range = 25.0
	data.move_speed = 5.0
	data.max_slope = 0.65
	data.slope_speed_penalty = 0.7
	squad.data = data
	squad.is_player_controlled = player
	squad.primary_weapon = "m16" if player else "ak47"
	return squad


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match (event as InputEventKey).keycode:
		KEY_1: _order_shuttle()
		KEY_2: _order_gunship_rocket()
		KEY_3: _order_gunship_strafe()
		KEY_4: _order_gunship_patrol()
		KEY_F: _spawn_enemy()


func _order_shuttle() -> void:
	if pickup_squads.is_empty():
		print("[HelicopterTest] No squads waiting to ferry. Shuttle stays at waiting zone.")
		return
	if not shuttle:
		return
	var squad: Node3D = pickup_squads.pop_front()
	if shuttle.has_method("ferry_squad"):
		shuttle.ferry_squad(squad)
	elif shuttle.has_method("pickup_squad"):
		shuttle.pickup_squad(squad)
	else:
		print("[HelicopterTest] Shuttle has no ferry method - check shuttle_helicopter.gd API")
	print("[HelicopterTest] Ordered shuttle to ferry %s. Remaining: %d" % [squad.name, pickup_squads.size()])


func _order_gunship_rocket() -> void:
	var target: Node3D = _nearest_enemy()
	if not target:
		print("[HelicopterTest] No enemy to target")
		return
	if gunship_behavior:
		gunship_behavior.rocket_run(target.global_position)


func _order_gunship_strafe() -> void:
	var target: Node3D = _nearest_enemy()
	if not target:
		print("[HelicopterTest] No enemy to target")
		return
	if gunship_behavior:
		gunship_behavior.strafe(target)


func _order_gunship_patrol() -> void:
	if gunship_behavior:
		gunship_behavior.patrol_area(Vector3(0, 0, -100), 120.0)


func _spawn_enemy() -> void:
	var squad: Node3D = _make_rifle_squad(false)
	add_child(squad)
	var spawn_pos := Vector3(randf_range(-100.0, 100.0), 0.0, randf_range(-200.0, -50.0))
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		spawn_pos.y = terrain.get_height_at(spawn_pos) + 0.1
	squad.global_position = spawn_pos
	enemies.append(squad)
	print("[HelicopterTest] Enemy squad spawned in AO")


func _nearest_enemy() -> Node3D:
	var nearest: Node3D = null
	var best: float = 1e9
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var d: float = (e as Node3D).global_position.distance_to(gunship.global_position) if gunship else 0.0
		if d < best:
			best = d
			nearest = e
	return nearest


func _on_gunship_rocket_run(target: Vector3) -> void:
	print("[HelicopterTest] Gunship rocket run -> %s" % target)


func _on_gunship_strafe(target: Node3D) -> void:
	print("[HelicopterTest] Gunship strafing %s" % target.name)


func _on_gunship_acquired(target: Node3D) -> void:
	print("[HelicopterTest] Gunship acquired %s on patrol" % target.name)


func _process(_delta: float) -> void:
	if not hud:
		return
	var lines: Array = ["HELICOPTER TEST"]
	lines.append("Squads waiting: %d   Enemies: %d" % [pickup_squads.size(), enemies.size()])
	if shuttle and is_instance_valid(shuttle):
		var state_str: String = "?"
		if "state" in shuttle:
			state_str = str(shuttle.state)
		lines.append("Shuttle: %s" % state_str)
	if gunship_behavior:
		var ammo: Dictionary = gunship_behavior.get_ammo_summary()
		lines.append("Gunship: rockets %d  MG %d  action %s" % [ammo.rockets, ammo.mg, GunshipBehavior.Action.keys()[gunship_behavior.action]])
	lines.append("")
	lines.append("1: ferry squad   F: spawn enemy")
	lines.append("2: rocket run  3: strafe  4: patrol AO")
	hud.text = "\n".join(lines)
