extends Node3D
## Artillery Test Scene
##
## Tests Artillery class:
## - Mobile pieces: limber up, drive to position, deploy, fire
## - Static pieces: cannot move, must fire from spawn position
## - Indirect fire at long range (M102 howitzer max 11,500m, capped to ~3km
##   on this map)
## - Multiple pieces firing simultaneously
##
## Layout:
## - Battery position (south, near spawn)
## - Long firing range running north (extends to map edge)
## - Multiple target circles at 200m, 500m, 1000m, 2000m
##
## Controls:
## - Left-click drag: select pieces
## - Right-click on ground: move (mobile pieces only)
## - 1: fire mission at 500m target
## - 2: fire mission at 1000m
## - 3: fire mission at 2000m
## - Click any target circle to fire mission there

const TestSceneBase = preload("res://test_scenes/common/test_scene_base.gd")
const Artillery = preload("res://battle_system/units/artillery.gd")
const SquadData = preload("res://battle_system/data/squad_data.gd")

var hud: Label
var mobile_pieces: Array[Node3D] = []
var static_pieces: Array[Node3D] = []
var camera: Camera3D = null
var selected_piece: Node3D = null


func _ready() -> void:
	var setup: Dictionary = TestSceneBase.setup_environment(self, {
		"seed": 44444,
		"size": 3200.0,  # Larger map for artillery ranges
		"name": "Artillery Test Scene",
	})
	camera = setup.get("camera")

	# Position camera for artillery overview
	if camera:
		camera.position = Vector3(0.0, 200.0, 150.0)
		camera.rotation_degrees = Vector3(-55.0, 0.0, 0.0)

	hud = TestSceneBase.make_hud(self)

	# Spawn 2 mobile M102 howitzers
	var terrain := get_node_or_null("/root/TerrainIntegration")
	for i in 2:
		var piece: Node3D = _make_artillery(true)
		add_child(piece)
		var spawn_pos := Vector3(float(i) * 12.0 - 6.0, 0.0, 30.0)
		if terrain and terrain.has_method("get_height_at"):
			spawn_pos.y = terrain.get_height_at(spawn_pos) + 0.1
		piece.global_position = spawn_pos
		mobile_pieces.append(piece)

	# Spawn 1 static piece (e.g. heavy gun emplaced at firebase)
	var static_piece: Node3D = _make_artillery(false)
	add_child(static_piece)
	var static_pos := Vector3(-20.0, 0.0, 30.0)
	if terrain and terrain.has_method("get_height_at"):
		static_pos.y = terrain.get_height_at(static_pos) + 0.1
	static_piece.global_position = static_pos
	static_pieces.append(static_piece)

	# Spawn target markers north
	_spawn_target_marker(Vector3(0, 0, -200), "200m")
	_spawn_target_marker(Vector3(-50, 0, -500), "500m")
	_spawn_target_marker(Vector3(50, 0, -1000), "1km")
	_spawn_target_marker(Vector3(0, 0, -2000), "2km")
	_spawn_target_marker(Vector3(-100, 0, -3000), "3km")

	for piece in mobile_pieces + static_pieces:
		piece.state_changed.connect(_on_artillery_state_changed.bind(piece))
		piece.fired_volley.connect(_on_volley_fired)

	print("[ArtilleryTest] Spawned %d mobile + %d static pieces" % [mobile_pieces.size(), static_pieces.size()])
	print("[ArtilleryTest] Mobile pieces can be moved (limber->drive->deploy ~8s)")
	print("[ArtilleryTest] Press 1/2/3 to fire missions at preset ranges")


func _make_artillery(mobile: bool) -> Node3D:
	var arty: Artillery = Artillery.new()
	var data := SquadData.new()
	data.display_name = "M102 105mm Howitzer" if mobile else "Static 155mm Gun"
	data.faction = 0
	data.squad_size = 8  # Crew
	data.health_per_soldier = 50.0
	data.attack_range = 11000.0
	data.move_speed = 4.0  # Slow tow
	data.max_slope = 0.20  # Wheeled artillery, very slope-limited
	data.slope_speed_penalty = 0.8
	data.is_vehicle = true
	data.can_redeploy = mobile  # KEY DIFFERENCE
	arty.data = data
	arty.weapon_id = "m102_howitzer"
	arty.is_player_controlled = true
	arty.rounds_per_volley = 3
	arty.min_indirect_range = 100.0
	return arty


func _spawn_target_marker(pos: Vector3, label: String) -> void:
	var marker := Node3D.new()
	marker.name = "Target_%s" % label
	marker.add_to_group("artillery_targets")
	marker.position = pos

	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 8.0
	mesh.outer_radius = 10.0
	ring.mesh = mesh
	ring.position.y = 0.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	marker.add_child(ring)

	# Floating label
	var lbl := Label3D.new()
	lbl.text = label
	lbl.position = Vector3(0, 5.0, 0)
	lbl.pixel_size = 0.05
	lbl.modulate = Color(1, 0.5, 0.5)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.add_child(lbl)

	add_child(marker)

	# Snap to terrain
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		marker.position.y = terrain.get_height_at(pos)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_1: _fire_at(Vector3(-50.0, 0.0, -500.0))
			KEY_2: _fire_at(Vector3(50.0, 0.0, -1000.0))
			KEY_3: _fire_at(Vector3(0.0, 0.0, -2000.0))


func _fire_at(target: Vector3) -> void:
	var ordered: int = 0
	for piece in mobile_pieces + static_pieces:
		if is_instance_valid(piece) and piece.has_method("fire_mission"):
			if piece.fire_mission(target):
				ordered += 1
	print("[ArtilleryTest] Fire mission at %s - %d pieces engaging" % [target, ordered])


func _on_artillery_state_changed(new_state: int, piece: Node) -> void:
	var state_name: String = piece.get_current_state_name()
	print("[ArtilleryTest] %s -> %s" % [piece.name, state_name])


func _on_volley_fired(target_pos: Vector3, rounds: int) -> void:
	print("[ArtilleryTest] Volley of %d rounds -> %s" % [rounds, target_pos])


func _process(_delta: float) -> void:
	if not hud:
		return
	var lines: Array = ["ARTILLERY TEST",
		"Mobile: %d  Static: %d" % [mobile_pieces.size(), static_pieces.size()],
	]
	for piece in mobile_pieces:
		if is_instance_valid(piece):
			lines.append("  %s: %s  ammo:%d" % [piece.name, piece.get_current_state_name(), piece.current_ammo])
	for piece in static_pieces:
		if is_instance_valid(piece):
			lines.append("  [STATIC] %s: %s  ammo:%d" % [piece.name, piece.get_current_state_name(), piece.current_ammo])
	lines.append("")
	lines.append("1/2/3: fire at 500m / 1km / 2km")
	lines.append("Right-click ground: move mobile piece (limber/deploy)")
	hud.text = "\n".join(lines)
