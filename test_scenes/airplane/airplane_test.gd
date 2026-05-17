extends Node3D
## Airplane Test Scene
##
## Tests the Airplane + Airport system:
## - Takeoff from runway
## - Patrol to a point
## - Attack runs with selectable ordnance: bombs / napalm / rockets / cannon
## - Return to base when ordnance depleted or fuel low
## - Refuel/rearm cycle at airport
##
## Controls:
## - T: take off
## - P: patrol to current cursor position
## - 1: bomb run on cursor position
## - 2: napalm run on cursor position
## - 3: rocket run on cursor position
## - 4: cannon strafe on cursor position
## - R: return to base
## - F: spawn target zone (visual marker for bombing practice)

const TestSceneBase = preload("res://test_scenes/common/test_scene_base.gd")
const Airplane = preload("res://airplane_system/airplane.gd")
const Airport = preload("res://airplane_system/airport.gd")
const Squad = preload("res://battle_system/nodes/squad.gd")
const SquadData = preload("res://battle_system/data/squad_data.gd")

var hud: Label
var camera: Camera3D = null
var airport: Airport = null
var plane: Airplane = null
var target_zones: Array[Node3D] = []
var last_cursor_ground: Vector3 = Vector3.ZERO


func _ready() -> void:
	var setup: Dictionary = TestSceneBase.setup_environment(self, {
		"seed": 77777,
		"size": 2000.0,
		"name": "Airplane Test Scene",
	})
	camera = setup.get("camera")
	# Higher camera for air ops
	if camera:
		camera.position = Vector3(0.0, 200.0, 200.0)
		camera.rotation_degrees = Vector3(-50.0, 0.0, 0.0)

	hud = TestSceneBase.make_hud(self)

	# Airport at the east edge of the map
	airport = Airport.new()
	airport.airport_name = "Bien Hoa"
	airport.runway_heading_degrees = 90.0  # Runway runs east-west
	airport.runway_length = 100.0
	airport.parking_capacity = 4
	add_child(airport)
	var airport_pos := Vector3(600.0, 0.0, 0.0)
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		airport_pos.y = terrain.get_height_at(airport_pos)
	airport.global_position = airport_pos

	# F-4 style fighter-bomber at the airport
	plane = Airplane.new()
	plane.name = "F-4 Phantom"
	plane.set_airport(airport.get_parking_spot(), airport.get_runway_heading_rad())
	add_child(plane)
	airport.park_aircraft(plane)

	# Connect signals for logging
	plane.took_off.connect(_on_took_off)
	plane.landed_at_airport.connect(_on_landed)
	plane.attack_run_started.connect(_on_attack_started)
	plane.attack_run_completed.connect(_on_attack_completed)
	plane.ordnance_depleted.connect(_on_ordnance_depleted)
	plane.refuel_complete.connect(_on_refuel_complete)

	# Pre-place some target zones to practice on
	_spawn_target_zone(Vector3(-200, 0, -300), "Bridge")
	_spawn_target_zone(Vector3(100, 0, -500), "Bunker Complex")
	_spawn_target_zone(Vector3(-400, 0, -200), "VC Base")

	print("[AirplaneTest] %s parked at %s" % [plane.name, airport.airport_name])
	print("[AirplaneTest] Press T to take off. Then 1/2/3/4 to drop ordnance at cursor.")


func _spawn_target_zone(pos: Vector3, label_text: String) -> Node3D:
	var zone := Node3D.new()
	zone.name = "Target_" + label_text
	zone.global_position = pos
	zone.add_to_group("airplane_targets")

	# Big visual ring
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 15.0
	mesh.outer_radius = 20.0
	ring.mesh = mesh
	ring.position.y = 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	zone.add_child(ring)

	var lbl := Label3D.new()
	lbl.text = label_text
	lbl.position = Vector3(0, 10.0, 0)
	lbl.pixel_size = 0.08
	lbl.modulate = Color(1, 0.7, 0.7)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	zone.add_child(lbl)

	add_child(zone)

	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		zone.position.y = terrain.get_height_at(pos)

	target_zones.append(zone)
	return zone


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var pos: Vector3 = _raycast_ground((event as InputEventMouseMotion).position)
		if pos != Vector3.INF:
			last_cursor_ground = pos
		return
	if not (event is InputEventKey and event.pressed):
		return
	match (event as InputEventKey).keycode:
		KEY_T: _take_off()
		KEY_P: _patrol()
		KEY_1: _attack_run(Airplane.Ordnance.BOMBS)
		KEY_2: _attack_run(Airplane.Ordnance.NAPALM)
		KEY_3: _attack_run(Airplane.Ordnance.ROCKETS)
		KEY_4: _attack_run(Airplane.Ordnance.CANNON)
		KEY_R: _return_to_base()
		KEY_F:
			# Spawn a new target zone where the cursor is
			_spawn_target_zone(last_cursor_ground, "Target %d" % target_zones.size())


func _take_off() -> void:
	if not plane:
		return
	# Move plane to runway start
	plane.global_position = airport.get_takeoff_start()
	plane.rotation.y = airport.get_runway_heading_rad()
	if plane.take_off():
		airport.release_aircraft(plane)
		print("[AirplaneTest] Taking off from %s" % airport.airport_name)
	else:
		print("[AirplaneTest] Cannot take off - state: %s, fuel: %.0f" % [plane.get_state_name(), plane.current_fuel])


func _patrol() -> void:
	if not plane:
		return
	plane.patrol_to(last_cursor_ground)
	print("[AirplaneTest] Patrolling to %s" % last_cursor_ground)


func _attack_run(ordnance: int) -> void:
	if not plane:
		return
	var ord_name: String = Airplane.Ordnance.keys()[ordnance]
	if plane.attack_position(last_cursor_ground, ordnance):
		print("[AirplaneTest] Attack run (%s) on %s" % [ord_name, last_cursor_ground])
	else:
		var summary: Dictionary = plane.get_ordnance_summary()
		print("[AirplaneTest] Cannot attack (%s) - state: %s, ordnance: %s" % [ord_name, plane.get_state_name(), summary])


func _return_to_base() -> void:
	if plane:
		plane.start_return_to_base()


func _on_took_off() -> void:
	print("[AirplaneTest] %s airborne" % plane.name)


func _on_landed() -> void:
	print("[AirplaneTest] %s landed - refueling/rearming" % plane.name)
	airport.park_aircraft(plane)


func _on_attack_started(target: Vector3, ordnance: String) -> void:
	print("[AirplaneTest] Attack run started (%s) on %s" % [ordnance, target])


func _on_attack_completed() -> void:
	print("[AirplaneTest] Attack run completed")


func _on_ordnance_depleted() -> void:
	print("[AirplaneTest] Ordnance depleted - returning to base")


func _on_refuel_complete() -> void:
	print("[AirplaneTest] %s ready to fly again" % plane.name)


func _raycast_ground(screen_pos: Vector2) -> Vector3:
	if not camera:
		return Vector3.INF
	var space: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var ro: Vector3 = camera.project_ray_origin(screen_pos)
	var rd: Vector3 = camera.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(ro, ro + rd * 5000.0)
	q.collision_mask = 1
	var r: Dictionary = space.intersect_ray(q)
	if r and "position" in r:
		return r.position
	if rd.y != 0:
		var t: float = -ro.y / rd.y
		if t > 0:
			return ro + rd * t
	return Vector3.INF


func _process(_delta: float) -> void:
	if not hud:
		return
	var lines: Array = ["AIRPLANE TEST"]
	if plane:
		var s: Dictionary = plane.get_ordnance_summary()
		lines.append("Plane state: %s" % plane.get_state_name())
		lines.append("  Fuel:    %.0f / %.0f" % [s.fuel, plane.max_fuel])
		lines.append("  Bombs:   %d / %d" % [s.bombs, plane.bomb_count])
		lines.append("  Napalm:  %d / %d" % [s.napalm, plane.napalm_count])
		lines.append("  Rockets: %d / %d" % [s.rockets, plane.rocket_pods])
		lines.append("  Cannon:  %d / %d" % [s.cannon, plane.cannon_rounds])
	lines.append("Targets: %d" % target_zones.size())
	lines.append("Cursor ground: %s" % last_cursor_ground)
	lines.append("")
	lines.append("T: takeoff   P: patrol to cursor   R: return to base")
	lines.append("1: BOMB   2: NAPALM   3: ROCKETS   4: CANNON   (drops at cursor)")
	lines.append("F: spawn target zone at cursor")
	hud.text = "\n".join(lines)
