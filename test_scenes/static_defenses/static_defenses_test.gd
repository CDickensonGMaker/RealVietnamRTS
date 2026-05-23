extends Node3D
## Static Defenses Test Scene
##
## Tests fortifications and emplacements:
## - Bunker garrison loading/unloading (squad enters -> fires from bunker -> exits)
## - Trench occupancy (squad stashes in trench, gets cover bonus)
## - AA Emplacement targeting (reuses existing AAEmplacement against an airborne unit)
## - Machine gun nest with fire arc
## - Mortar pit indirect fire
## - Static artillery piece
##
## Controls:
## - Select a squad, click on a bunker/trench/structure to garrison it
## - Press U to unload all garrisons
## - 1: spawn enemy squad approaching from the north
## - 2: spawn dummy helicopter (for AA test)
## - 3: spawn enemy at range (for static artillery test)

const TestSceneBase = preload("res://test_scenes/common/test_scene_base.gd")
const Bunker = preload("res://fortification_system/bunker.gd")
const Trench = preload("res://fortification_system/trench.gd")
const Artillery = preload("res://battle_system/units/artillery.gd")
const Squad = preload("res://battle_system/nodes/squad.gd")
const SquadData = preload("res://battle_system/data/squad_data.gd")
const MachineGunNest = preload("res://fortification_system/machine_gun_nest.gd")
const MortarPit = preload("res://fortification_system/mortar_pit.gd")
# Existing user assets
const AAEmplacement = preload("res://battle_system/ai/aa_emplacement.gd")

var hud: Label
var camera: Camera3D = null
var bunkers: Array[Node3D] = []
var trenches: Array[Node3D] = []
var aa_guns: Array[Node3D] = []
var mg_nests: Array[Node3D] = []
var mortar_pits: Array[Node3D] = []
var static_arty: Array[Node3D] = []
var player_squads: Array[Node3D] = []
var enemies: Array[Node3D] = []
var selected_squad: Node3D = null


func _ready() -> void:
	var setup: Dictionary = TestSceneBase.setup_environment(self, {
		"seed": 55555,
		"size": 800.0,
		"name": "Static Defenses Test Scene",
	})
	camera = setup.get("camera")

	hud = TestSceneBase.make_hud(self)

	_build_defensive_line()
	_spawn_garrison_squads()


func _build_defensive_line() -> void:
	# Defensive line runs east-west at z=0, all firing arcs face north
	# (positive Z is "behind", negative Z is "front")
	var terrain := get_node_or_null("/root/TerrainIntegration")

	# Two main bunkers in the center
	for i in 2:
		var b: Bunker = Bunker.new()
		b.bunker_type = Bunker.BunkerType.SANDBAG_BUNKER
		b.bunker_name = "Bunker %s" % char(65 + i)  # A, B
		b.firing_arc_degrees = 180.0
		b.firing_arc_yaw_degrees = 180.0  # Facing north (-Z)
		b.max_garrison_capacity = 2
		add_child(b)
		var bunker_pos := Vector3(float(i) * 30.0 - 15.0, 0.0, 0.0)
		if terrain and terrain.has_method("get_height_at"):
			bunker_pos.y = terrain.get_height_at(bunker_pos)
		b.global_position = bunker_pos
		bunkers.append(b)

	# MG nest on each flank - uses new auto-firing MachineGunNest class
	for i in 2:
		var nest: MachineGunNest = MachineGunNest.new()
		nest.name = "MG Nest %s" % ("West" if i == 0 else "East")
		nest.firing_arc_degrees = 120.0
		nest.is_player_controlled = true
		add_child(nest)
		var nest_pos := Vector3(-50.0 + float(i) * 100.0, 0.0, 5.0)
		if terrain and terrain.has_method("get_height_at"):
			nest_pos.y = terrain.get_height_at(nest_pos)
		nest.global_position = nest_pos
		# Rotate to face north (-Z direction)
		nest.rotation.y = PI
		mg_nests.append(nest)

	# Mortar pit behind the line - uses auto-firing MortarPit class
	var pit: MortarPit = MortarPit.new()
	pit.name = "Mortar Pit Alpha"
	pit.is_player_controlled = true
	pit.detection_radius = 300.0  # Detect enemies within 300m
	add_child(pit)
	var pit_pos := Vector3(0.0, 0.0, 25.0)
	if terrain and terrain.has_method("get_height_at"):
		pit_pos.y = terrain.get_height_at(pit_pos)
	pit.global_position = pit_pos
	mortar_pits.append(pit)

	# Second mortar pit on the east flank
	var pit2: MortarPit = MortarPit.new()
	pit2.name = "Mortar Pit Bravo"
	pit2.is_player_controlled = true
	pit2.detection_radius = 300.0
	add_child(pit2)
	var pit2_pos := Vector3(40.0, 0.0, 30.0)
	if terrain and terrain.has_method("get_height_at"):
		pit2_pos.y = terrain.get_height_at(pit2_pos)
	pit2.global_position = pit2_pos
	mortar_pits.append(pit2)

	# Trench running between bunker A and bunker B
	var trench: Trench = Trench.new()
	trench.trench_name = "Trench"
	add_child(trench)
	var trench_pts: PackedVector3Array = PackedVector3Array([
		Vector3(-20.0, 0.0, -3.0),
		Vector3(-5.0, 0.0, -3.0),
		Vector3(10.0, 0.0, -3.0),
		Vector3(25.0, 0.0, -3.0),
	])
	# Snap each point to terrain (reuse terrain var from above)
	if terrain and terrain.has_method("get_height_at"):
		var snapped: PackedVector3Array = PackedVector3Array()
		for p in trench_pts:
			var sp: Vector3 = p
			sp.y = terrain.get_height_at(p)
			snapped.append(sp)
		trench.set_path(snapped)
	else:
		trench.set_path(trench_pts)
	trenches.append(trench)

	# AA gun on a hill behind the line
	var aa: AAEmplacement = AAEmplacement.new()
	aa.aa_type = 1  # 37mm
	add_child(aa)
	var aa_pos := Vector3(60.0, 0.0, 35.0)
	if terrain and terrain.has_method("get_height_at"):
		aa_pos.y = terrain.get_height_at(aa_pos)
	aa.global_position = aa_pos
	aa_guns.append(aa)

	# Static heavy artillery piece (cannot move)
	var heavy: Artillery = Artillery.new()
	var heavy_data := SquadData.new()
	heavy_data.display_name = "M115 8-inch Howitzer"
	heavy_data.faction = 0
	heavy_data.squad_size = 8
	heavy_data.health_per_soldier = 80.0
	heavy_data.attack_range = 15000.0
	heavy_data.move_speed = 0.0
	heavy_data.max_slope = 0.0
	heavy_data.can_redeploy = false  # STATIC
	heavy.data = heavy_data
	heavy.weapon_id = "m102_howitzer"  # Stand-in
	heavy.is_player_controlled = true
	add_child(heavy)
	var arty_pos := Vector3(-60.0, 0.0, 35.0)
	if terrain and terrain.has_method("get_height_at"):
		arty_pos.y = terrain.get_height_at(arty_pos)
	heavy.global_position = arty_pos
	static_arty.append(heavy)

	print("[StaticDefensesTest] Defensive line built. Bunkers/trench face north (-Z).")


func _spawn_garrison_squads() -> void:
	# Spawn squads BEHIND the bunkers (positive Z) so the player can order
	# them to garrison
	var terrain := get_node_or_null("/root/TerrainIntegration")
	for i in 4:
		var squad: Node3D = _make_rifle_squad()
		add_child(squad)
		var spawn_pos := Vector3(float(i) * 12.0 - 18.0, 0.0, 50.0)
		if terrain and terrain.has_method("get_height_at"):
			spawn_pos.y = terrain.get_height_at(spawn_pos) + 0.1
		squad.global_position = spawn_pos
		player_squads.append(squad)


func _make_rifle_squad() -> Node3D:
	var squad: Squad = Squad.new()
	var data := SquadData.new()
	data.display_name = "US Rifle Squad"
	data.faction = 0
	data.squad_size = 10
	data.health_per_soldier = 100.0
	data.attack_range = 25.0
	data.move_speed = 5.0
	data.max_slope = 0.65
	data.slope_speed_penalty = 0.7
	squad.data = data
	squad.is_player_controlled = true
	squad.primary_weapon = "m16"
	return squad


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click(mb.position)
	elif event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_1: _spawn_enemy_squad()
			KEY_2: _spawn_dummy_helicopter()
			KEY_3: _spawn_distant_enemy()
			KEY_U: _unload_all_garrisons()


func _handle_left_click(screen_pos: Vector2) -> void:
	# Try to select a player squad under cursor
	var hit: Node3D = _raycast_unit(screen_pos)
	if hit and hit in player_squads:
		selected_squad = hit
		print("[StaticDefensesTest] Selected %s" % hit.name)


func _handle_right_click(screen_pos: Vector2) -> void:
	if not selected_squad:
		return
	# Check if right-clicking on a bunker/trench
	var bunker_hit: Node3D = _raycast_at(screen_pos, ["bunkers", "fortifications"])
	if bunker_hit and bunker_hit is Bunker:
		var b := bunker_hit as Bunker
		# Move squad to bunker, then load
		selected_squad.move_to(b.global_position + Vector3(0, 0, 3))
		# Once close, garrison it (poll-based check)
		_pending_garrison(selected_squad, b)
		return

	var trench_hit: Node3D = _raycast_at(screen_pos, ["trenches"])
	if trench_hit and trench_hit is Trench:
		var t := trench_hit as Trench
		t.enter_trench(selected_squad)
		print("[StaticDefensesTest] %s entered trench" % selected_squad.name)
		return

	# Otherwise just move
	var ground: Vector3 = _raycast_ground(screen_pos)
	if ground != Vector3.INF and selected_squad.has_method("move_to"):
		selected_squad.move_to(ground)


## Hacky polling for "squad close enough to garrison". A real impl would
## use a Move-Then-Action queue on the squad.
func _pending_garrison(squad: Node3D, bunker: Bunker) -> void:
	var timer := get_tree().create_timer(0.5)
	timer.timeout.connect(func():
		if not is_instance_valid(squad) or not is_instance_valid(bunker):
			return
		if squad.global_position.distance_to(bunker.global_position) < 5.0:
			if bunker.load_squad(squad):
				print("[StaticDefensesTest] %s garrisoned in %s" % [squad.name, bunker.bunker_name])
			else:
				print("[StaticDefensesTest] Could not garrison: bunker full or invalid")
		else:
			# Try again in 0.5s
			_pending_garrison(squad, bunker)
	)


func _unload_all_garrisons() -> void:
	for b in bunkers:
		if is_instance_valid(b):
			b.unload_all()
	for t in trenches:
		if is_instance_valid(t):
			for s in t.get_occupants():
				t.leave_trench(s)


func _spawn_enemy_squad() -> void:
	var squad: Squad = Squad.new()
	var data := SquadData.new()
	data.display_name = "VC Infantry"
	data.faction = 2
	data.squad_size = 8
	data.health_per_soldier = 80.0
	data.attack_range = 20.0
	data.move_speed = 4.5
	data.max_slope = 0.65
	data.slope_speed_penalty = 0.7
	squad.data = data
	squad.is_player_controlled = false
	squad.primary_weapon = "ak47"
	add_child(squad)
	var spawn_pos := Vector3(randf_range(-50.0, 50.0), 0.0, -150.0)
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		spawn_pos.y = terrain.get_height_at(spawn_pos) + 0.1
	squad.global_position = spawn_pos
	enemies.append(squad)
	# Order them to advance south toward the bunker line
	squad.move_to(Vector3(0, 0, 0))
	print("[StaticDefensesTest] Enemy squad approaching")


func _spawn_dummy_helicopter() -> void:
	# Fake target for AA gun (in air, no terrain snap needed)
	var dummy := Node3D.new()
	dummy.name = "DummyHelicopter"
	dummy.add_to_group("helicopters")
	dummy.add_to_group("enemy_units")

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(8.0, 3.0, 4.0)
	mesh.mesh = bm
	dummy.add_child(mesh)
	add_child(dummy)
	dummy.global_position = Vector3(0.0, 50.0, -100.0)
	enemies.append(dummy)
	print("[StaticDefensesTest] Dummy helicopter spawned for AA test")


func _spawn_distant_enemy() -> void:
	var dummy: Squad = Squad.new()
	var data := SquadData.new()
	data.display_name = "Far Target"
	data.faction = 2
	data.squad_size = 5
	data.health_per_soldier = 100.0
	data.move_speed = 0.0
	data.max_slope = 0.0
	dummy.data = data
	dummy.is_player_controlled = false
	add_child(dummy)
	var spawn_pos := Vector3(0.0, 0.0, -800.0)
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		spawn_pos.y = terrain.get_height_at(spawn_pos) + 0.1
	dummy.global_position = spawn_pos
	enemies.append(dummy)
	# Order static artillery to fire at it
	for arty in static_arty:
		if is_instance_valid(arty):
			arty.fire_mission(dummy.global_position)
	print("[StaticDefensesTest] Distant target spawned - static arty engaging")


func _raycast_unit(screen_pos: Vector2) -> Node3D:
	if not camera:
		return null
	var space: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var ro: Vector3 = camera.project_ray_origin(screen_pos)
	var rd: Vector3 = camera.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(ro, ro + rd * 1000.0)
	q.collision_mask = 2 | 4 | 8
	var r: Dictionary = space.intersect_ray(q)
	if r and "collider" in r:
		var c: Node = r.collider
		while c:
			if c.is_in_group("squads") or c.is_in_group("all_units"):
				return c as Node3D
			c = c.get_parent()
	return null


func _raycast_at(screen_pos: Vector2, groups: Array) -> Node3D:
	if not camera:
		return null
	var space: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var ro: Vector3 = camera.project_ray_origin(screen_pos)
	var rd: Vector3 = camera.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(ro, ro + rd * 1000.0)
	q.collision_mask = 1
	var r: Dictionary = space.intersect_ray(q)
	if r and "collider" in r:
		var c: Node = r.collider
		while c:
			for g in groups:
				if c.is_in_group(g):
					return c as Node3D
			c = c.get_parent()
	return null


func _raycast_ground(screen_pos: Vector2) -> Vector3:
	if not camera:
		return Vector3.INF
	var space: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var ro: Vector3 = camera.project_ray_origin(screen_pos)
	var rd: Vector3 = camera.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(ro, ro + rd * 1000.0)
	q.collision_mask = 1
	var r: Dictionary = space.intersect_ray(q)
	if r and "position" in r:
		return r.position
	return Vector3.INF


func _process(_delta: float) -> void:
	if not hud:
		return
	var lines: Array = ["STATIC DEFENSES TEST"]
	lines.append("Bunkers: %d  MG Nests: %d  Trenches: %d  AA: %d" % [bunkers.size(), mg_nests.size(), trenches.size(), aa_guns.size()])
	lines.append("Squads: %d  Enemies: %d" % [player_squads.size(), enemies.size()])

	# Bunker garrison status (now with auto-fire)
	for b in bunkers:
		if is_instance_valid(b):
			var bunker_target: String = "---"
			if b.current_target and is_instance_valid(b.current_target):
				bunker_target = b.current_target.name
			var suppressed: String = " (SUPPRESSED)" if b._is_suppressed else ""
			lines.append("  %s: %d/%d garrison Target: %s%s" % [
				b.bunker_name,
				b.garrison.size(),
				b.max_garrison_capacity,
				bunker_target,
				suppressed
			])

	# MG Nest auto-fire status
	for mg in mg_nests:
		if is_instance_valid(mg):
			var target_name: String = "---"
			if mg.current_target and is_instance_valid(mg.current_target):
				target_name = mg.current_target.name
			lines.append("  %s: [%s] Ammo: %d/%d Crew: %d/%d Target: %s" % [
				mg.name,
				mg.get_state_name(),
				mg.ammo_remaining,
				mg.magazine_size,
				mg._crew_alive,
				mg.crew_size,
				target_name
			])

	# Mortar Pit status
	for pit in mortar_pits:
		if is_instance_valid(pit):
			var pit_target: String = "---"
			if pit.current_target and is_instance_valid(pit.current_target):
				pit_target = pit.current_target.name
			elif pit.target_position != Vector3.INF:
				pit_target = "(%.0f, %.0f)" % [pit.target_position.x, pit.target_position.z]
			lines.append("  %s: [%s] Ammo: %d/%d Crew: %d/%d Pending: %d Target: %s" % [
				pit.name,
				pit.get_state_name(),
				pit.ammo_remaining,
				pit.magazine_size,
				pit._crew_alive,
				pit.crew_size,
				pit.get_pending_rounds(),
				pit_target
			])

	# AA status
	for aa in aa_guns:
		if is_instance_valid(aa):
			var aa_target: String = "---"
			if aa.current_target and is_instance_valid(aa.current_target):
				aa_target = aa.current_target.name
			lines.append("  AA: [%s] Ammo: %d Target: %s" % [aa.get_state_name(), aa.ammo_remaining, aa_target])

	lines.append("")
	lines.append("L-click squad to select, R-click bunker/trench to garrison")
	lines.append("1: enemy infantry  2: helicopter (AA test)  3: distant target (static arty)")
	lines.append("U: unload all garrisons")
	if selected_squad:
		lines.append("Selected: %s" % selected_squad.name)
	hud.text = "\n".join(lines)
