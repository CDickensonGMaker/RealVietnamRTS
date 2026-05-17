extends Node3D
## Main Scene - Entry point for Vietnam Firebase Defense
## Contains playable test scenario for development

# Preloaded classes (avoid forward reference issues)
const FirebaseClass = preload("res://firebase_system/firebase.gd")
const SquadClass = preload("res://battle_system/nodes/squad.gd")
const CampaignClass = preload("res://campaign/campaign.gd")
const UnitDataClass = preload("res://battle_system/data/vietnam_unit_data.gd")

# References
@onready var game_world: Node3D = $GameWorld
@onready var player_units: Node3D = $GameWorld/Units/PlayerUnits
@onready var enemy_units: Node3D = $GameWorld/Units/EnemyUnits
@onready var structures: Node3D = $GameWorld/Structures
@onready var firebases_node: Node3D = $GameWorld/Firebases
@onready var camera: Camera3D = $RTSCamera
@onready var hud: Control = $UI/HUD
@onready var supply_label: Label = $UI/HUD/TopBar/SupplyLabel
@onready var time_label: Label = $UI/HUD/TopBar/TimeLabel
@onready var weather_label: Label = $UI/HUD/TopBar/WeatherLabel
@onready var vc_controller: Node = $Controllers/VCController
@onready var nva_controller: Node = $Controllers/NVAController

# Game state
var supplies: int = 100
var is_paused: bool = false
var game_time: float = 0.0
var scenario_started: bool = false

# Current campaign/mission
var current_campaign = null  # Campaign
var current_mission = null  # Campaign.Mission

# Player firebase
var player_firebase = null  # Firebase

# Camera control
var camera_speed: float = 50.0
var camera_zoom_speed: float = 5.0
var camera_min_height: float = 20.0
var camera_max_height: float = 100.0
var camera_target_position: Vector3 = Vector3(100, 50, 100)
var camera_pitch: float = -45.0  # Looking down at 45 degrees

# Selection
var selected_units: Array[Node3D] = []
var selection_start: Vector2 = Vector2.ZERO
var is_box_selecting: bool = false

# Wave system
var current_wave: int = 0
var wave_timer: float = 0.0
var wave_interval: float = 120.0  # 2 minutes between waves
var wave_active: bool = false
var enemies_remaining: int = 0

# Test scenario config
const TEST_SCENARIO_WAVES: Array[Dictionary] = [
	{"vc_infantry": 5, "vc_sappers": 0, "delay": 60.0, "approach": "south"},
	{"vc_infantry": 8, "vc_sappers": 2, "delay": 120.0, "approach": "east"},
	{"vc_infantry": 10, "vc_sappers": 3, "nva_infantry": 5, "delay": 180.0, "approach": "south"},
	{"nva_infantry": 15, "nva_heavy": 3, "delay": 240.0, "approach": "north"},
	{"vc_infantry": 15, "vc_sappers": 5, "nva_infantry": 10, "nva_heavy": 5, "delay": 300.0, "approach": "all"},
]

func _ready() -> void:
	# Connect signals
	_connect_signals()

	# Initialize game
	_initialize_game()

	# Start test scenario or load mission
	_start_test_scenario()

	print("=== VIETNAM FIREBASE DEFENSE ===")
	print("Test Scenario Loaded - Firebase Alpha")
	print("WASD: Move camera | Scroll: Zoom | LMB: Select | RMB: Command")
	print("Defend the firebase against incoming waves!")

func _process(delta: float) -> void:
	if is_paused:
		return

	game_time += delta

	_process_camera(delta)
	_update_hud()
	_process_wave_system(delta)

func _physics_process(_delta: float) -> void:
	if is_paused:
		return

	_process_selection()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()

	# Selection input
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_start_selection(mouse_event.position)
			else:
				_end_selection(mouse_event.position)
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			_issue_command(mouse_event.position)

# =============================================================================
# INITIALIZATION
# =============================================================================

func _connect_signals() -> void:
	# Battle signals
	BattleSignals.unit_died.connect(_on_unit_died)
	BattleSignals.firebase_under_attack.connect(_on_firebase_under_attack)
	BattleSignals.reinforcement_arrived.connect(_on_reinforcement_arrived)
	BattleSignals.wave_started.connect(_on_wave_started)
	BattleSignals.wave_defeated.connect(_on_wave_defeated)

	# Weather signals
	if WeatherSystem.has_signal("weather_changing"):
		WeatherSystem.weather_changing.connect(_on_weather_changing)

func _initialize_game() -> void:
	# Set initial weather
	if WeatherSystem.has_method("set_weather"):
		WeatherSystem.set_weather(GameEnums.WeatherCondition.CLEAR)

	# Position camera
	camera_target_position = Vector3(100, 50, 150)
	_update_camera_transform()

func _start_test_scenario() -> void:
	## Start Firebase Defense test scenario
	scenario_started = true

	# Create player firebase at center of map
	player_firebase = _create_firebase(Vector3(100, 0, 100), "Firebase Alpha")

	# Create some initial buildings
	_build_initial_defenses(player_firebase)

	# Spawn initial garrison
	_spawn_initial_garrison(player_firebase)

	# Set up enemy controller with tunnel network
	_setup_enemy_network()

	# Start wave timer
	wave_timer = TEST_SCENARIO_WAVES[0].delay
	current_wave = 0

	print("First wave incoming in %.0f seconds!" % wave_timer)

func _create_firebase(position: Vector3, fb_name: String) -> Node3D:  # Firebase
	var firebase := FirebaseClass.new()
	firebase.firebase_name = fb_name
	firebase.firebase_callsign = fb_name.split(" ")[-1].to_upper()
	firebase.global_position = position
	firebases_node.add_child(firebase)

	# Add visual representation
	var visual := CSGBox3D.new()
	visual.size = Vector3(20, 0.5, 20)
	visual.material = _create_material(Color(0.6, 0.5, 0.3))
	firebase.add_child(visual)

	return firebase

func _build_initial_defenses(firebase) -> void:  # firebase: Firebase
	## Build some starting structures

	# Place sandbag perimeter
	for i in range(8):
		var angle: float = (TAU / 8) * i
		var pos: Vector3 = firebase.global_position + Vector3(
			cos(angle) * 25, 0, sin(angle) * 25
		)
		_place_sandbag_visual(pos, angle)

	# Place wire obstacle ring
	for i in range(12):
		var angle: float = (TAU / 12) * i
		var start: Vector3 = firebase.global_position + Vector3(
			cos(angle) * 35, 0, sin(angle) * 35
		)
		var end: Vector3 = firebase.global_position + Vector3(
			cos(angle + TAU/12) * 35, 0, sin(angle + TAU/12) * 35
		)
		firebase.add_wire_segment(start, end)

	# Place claymores
	for i in range(4):
		var angle: float = (TAU / 4) * i
		var pos: Vector3 = firebase.global_position + Vector3(
			cos(angle) * 40, 0, sin(angle) * 40
		)
		var direction: Vector3 = -Vector3(cos(angle), 0, sin(angle))  # Pointing outward
		firebase.place_claymore(pos, direction)

func _place_sandbag_visual(pos: Vector3, angle: float) -> void:
	var sandbag := CSGBox3D.new()
	sandbag.size = Vector3(6, 1.2, 1)
	sandbag.global_position = pos + Vector3(0, 0.6, 0)
	sandbag.rotation.y = angle
	sandbag.material = _create_material(Color(0.5, 0.45, 0.3))
	structures.add_child(sandbag)

func _spawn_initial_garrison(firebase) -> void:  # firebase: Firebase
	## Spawn starting units

	# 2 Rifle Platoons
	for i in range(2):
		var angle: float = (TAU / 4) * i
		var pos: Vector3 = firebase.global_position + Vector3(cos(angle) * 15, 0, sin(angle) * 15)
		var squad: Node3D = _create_player_squad(GameEnums.UnitType.RIFLE_PLATOON, pos)
		firebase.add_to_garrison(squad)

	# 1 Weapons Squad
	var weapons_pos: Vector3 = firebase.global_position + Vector3(0, 0, 15)
	var weapons: Node3D = _create_player_squad(GameEnums.UnitType.WEAPONS_SQUAD, weapons_pos)
	firebase.add_to_garrison(weapons)

	# 1 Engineer Squad
	var eng_pos: Vector3 = firebase.global_position + Vector3(0, 0, -15)
	var engineers: Node3D = _create_player_squad(GameEnums.UnitType.ENGINEERS, eng_pos)
	firebase.add_to_garrison(engineers)

func _create_player_squad(unit_type: int, position: Vector3) -> Node3D:  # Squad
	var squad = SquadClass.new()
	squad.set("faction", GameEnums.Faction.US_ARMY)

	# Set unit data based on type (use set() for dynamic property access)
	match unit_type:
		GameEnums.UnitType.RIFLE_PLATOON:
			squad.set("unit_data", UnitDataClass.create_rifle_platoon())
		GameEnums.UnitType.WEAPONS_SQUAD:
			squad.set("unit_data", UnitDataClass.create_weapons_squad())
		GameEnums.UnitType.ENGINEERS:
			squad.set("unit_data", UnitDataClass.create_engineers())
		_:
			squad.set("unit_data", UnitDataClass.create_rifle_platoon())

	squad.global_position = position
	player_units.add_child(squad)

	# Add visual
	_add_squad_visual(squad, Color(0.2, 0.4, 0.2))

	return squad

func _create_enemy_squad(unit_type: int, position: Vector3) -> Node3D:  # Squad
	var squad = SquadClass.new()

	# Determine faction (use set() for dynamic property access)
	var faction_value: int
	if unit_type in [GameEnums.UnitType.VC_INFANTRY, GameEnums.UnitType.VC_SAPPERS,
					  GameEnums.UnitType.VC_MORTAR, GameEnums.UnitType.VC_LOCAL_FORCE]:
		faction_value = GameEnums.Faction.VC
	else:
		faction_value = GameEnums.Faction.NVA
	squad.set("faction", faction_value)

	# Set unit data (use set() for dynamic property access)
	match unit_type:
		GameEnums.UnitType.VC_INFANTRY:
			squad.set("unit_data", UnitDataClass.create_vc_infantry())
		GameEnums.UnitType.VC_SAPPERS:
			squad.set("unit_data", UnitDataClass.create_vc_sappers())
		GameEnums.UnitType.NVA_INFANTRY:
			squad.set("unit_data", UnitDataClass.create_nva_infantry())
		GameEnums.UnitType.NVA_HEAVY_WEAPONS:
			squad.set("unit_data", UnitDataClass.create_nva_heavy_weapons())
		_:
			squad.set("unit_data", UnitDataClass.create_vc_infantry())

	squad.global_position = position
	enemy_units.add_child(squad)

	# Add visual
	var color: Color = Color(0.6, 0.2, 0.2) if faction_value == GameEnums.Faction.VC else Color(0.4, 0.3, 0.2)
	_add_squad_visual(squad, color)

	return squad

func _add_squad_visual(squad, color: Color) -> void:  # squad: Squad
	var visual := CSGCylinder3D.new()
	visual.radius = 1.0
	visual.height = 2.0
	visual.global_position = squad.global_position + Vector3(0, 1, 0)
	visual.material = _create_material(color)
	squad.add_child(visual)

func _create_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat

func _setup_enemy_network() -> void:
	## Set up VC tunnel network around the map

	# Create tunnels in jungle areas around firebase
	var tunnel_positions: Array[Vector3] = [
		Vector3(30, 0, 30),    # Southwest
		Vector3(170, 0, 30),   # Southeast
		Vector3(30, 0, 170),   # Northwest
		Vector3(170, 0, 170),  # Northeast
	]

	for pos in tunnel_positions:
		if vc_controller.has_method("create_tunnel_entrance"):
			vc_controller.create_tunnel_entrance(pos)

	# Give controllers some starting resources
	vc_controller.manpower = 100
	vc_controller.supplies = 50
	nva_controller.manpower = 150
	nva_controller.supplies = 80

# =============================================================================
# CAMERA CONTROLS
# =============================================================================

func _process_camera(delta: float) -> void:
	var input_dir := Vector3.ZERO

	# WASD movement
	if Input.is_action_pressed("camera_pan_up"):
		input_dir.z -= 1
	if Input.is_action_pressed("camera_pan_down"):
		input_dir.z += 1
	if Input.is_action_pressed("camera_pan_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("camera_pan_right"):
		input_dir.x += 1

	# Apply movement
	if input_dir != Vector3.ZERO:
		input_dir = input_dir.normalized()
		camera_target_position += input_dir * camera_speed * delta

	# Clamp to map bounds
	camera_target_position.x = clampf(camera_target_position.x, 0, 200)
	camera_target_position.z = clampf(camera_target_position.z, 0, 200)

	# Zoom with scroll wheel
	if Input.is_action_just_pressed("camera_zoom_in"):
		camera_target_position.y = maxf(camera_min_height, camera_target_position.y - camera_zoom_speed)
	if Input.is_action_just_pressed("camera_zoom_out"):
		camera_target_position.y = minf(camera_max_height, camera_target_position.y + camera_zoom_speed)

	_update_camera_transform()

func _update_camera_transform() -> void:
	# Position camera looking at target from above and behind
	var offset := Vector3(0, 0, camera_target_position.y * 0.7)
	offset = offset.rotated(Vector3.UP, 0)

	camera.global_position = camera_target_position + offset
	camera.look_at(Vector3(camera_target_position.x, 0, camera_target_position.z - 20), Vector3.UP)

# =============================================================================
# SELECTION SYSTEM
# =============================================================================

func _process_selection() -> void:
	# Visual feedback for selection would go here
	pass

func _start_selection(mouse_pos: Vector2) -> void:
	selection_start = mouse_pos
	is_box_selecting = true

	# Try single click selection
	var clicked := _raycast_unit(mouse_pos)
	if clicked:
		_select_unit(clicked)

func _end_selection(mouse_pos: Vector2) -> void:
	is_box_selecting = false

	# If dragged, do box selection
	if selection_start.distance_to(mouse_pos) > 10:
		_box_select(selection_start, mouse_pos)

func _select_unit(unit: Node3D) -> void:
	# Clear previous selection if not shift-held
	if not Input.is_action_pressed("add_to_selection"):
		_clear_selection()

	if unit not in selected_units:
		selected_units.append(unit)
		if unit.has_method("select"):
			unit.select()
		BattleSignals.unit_selected.emit(unit)

func _clear_selection() -> void:
	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("deselect"):
			unit.deselect()
		BattleSignals.unit_deselected.emit(unit)
	selected_units.clear()

func _box_select(start: Vector2, end: Vector2) -> void:
	# Get all player units in box
	_clear_selection()

	for unit in player_units.get_children():
		if unit is SquadClass:
			var screen_pos := camera.unproject_position(unit.global_position)
			var rect := Rect2(start, end - start).abs()
			if rect.has_point(screen_pos):
				selected_units.append(unit)
				if unit.has_method("select"):
					unit.select()

func _raycast_unit(screen_pos: Vector2) -> Node3D:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 1000

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0b00000110  # US and VC unit layers

	var result := space.intersect_ray(query)
	if result:
		return result.collider

	return null

func _issue_command(mouse_pos: Vector2) -> void:
	if selected_units.is_empty():
		return

	# Raycast to find target
	var from := camera.project_ray_origin(mouse_pos)
	var to := from + camera.project_ray_normal(mouse_pos) * 1000

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)

	var result := space.intersect_ray(query)
	if result:
		var target_pos: Vector3 = result.position
		var target_unit: Node3D = result.collider if result.collider.is_in_group("enemy_units") else null

		for unit in selected_units:
			if not is_instance_valid(unit):
				continue

			if target_unit and unit.has_method("attack"):
				unit.attack(target_unit)
			elif unit.has_method("move_to"):
				unit.move_to(target_pos)

		BattleSignals.command_issued.emit("move" if not target_unit else "attack", target_pos)

# =============================================================================
# WAVE SYSTEM
# =============================================================================

func _process_wave_system(delta: float) -> void:
	if not scenario_started:
		return

	if current_wave >= TEST_SCENARIO_WAVES.size():
		# All waves complete - victory!
		return

	if wave_active:
		# Check if wave is defeated
		enemies_remaining = enemy_units.get_child_count()
		if enemies_remaining == 0:
			_wave_defeated()
	else:
		# Count down to next wave
		wave_timer -= delta
		if wave_timer <= 0:
			_spawn_wave(current_wave)

func _spawn_wave(wave_index: int) -> void:
	if wave_index >= TEST_SCENARIO_WAVES.size():
		return

	var wave_data: Dictionary = TEST_SCENARIO_WAVES[wave_index]
	var spawn_direction: String = wave_data.get("approach", "south")

	print("=== WAVE %d INCOMING ===" % (wave_index + 1))

	# Determine spawn positions based on approach direction
	var spawn_positions := _get_spawn_positions(spawn_direction)

	# Spawn VC Infantry
	var vc_count: int = wave_data.get("vc_infantry", 0)
	for i in range(vc_count):
		var pos: Vector3 = spawn_positions[i % spawn_positions.size()]
		pos += Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
		_create_enemy_squad(GameEnums.UnitType.VC_INFANTRY, pos)

	# Spawn VC Sappers
	var sapper_count: int = wave_data.get("vc_sappers", 0)
	for i in range(sapper_count):
		var pos: Vector3 = spawn_positions[i % spawn_positions.size()]
		pos += Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
		_create_enemy_squad(GameEnums.UnitType.VC_SAPPERS, pos)

	# Spawn NVA Infantry
	var nva_count: int = wave_data.get("nva_infantry", 0)
	for i in range(nva_count):
		var pos: Vector3 = spawn_positions[i % spawn_positions.size()]
		pos += Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
		_create_enemy_squad(GameEnums.UnitType.NVA_INFANTRY, pos)

	# Spawn NVA Heavy Weapons
	var nva_heavy: int = wave_data.get("nva_heavy", 0)
	for i in range(nva_heavy):
		var pos: Vector3 = spawn_positions[i % spawn_positions.size()]
		pos += Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
		_create_enemy_squad(GameEnums.UnitType.NVA_HEAVY_WEAPONS, pos)

	wave_active = true
	enemies_remaining = enemy_units.get_child_count()

	BattleSignals.wave_started.emit(wave_index + 1)
	print("Enemies spawned: %d" % enemies_remaining)

func _get_spawn_positions(direction: String) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var center := Vector3(100, 0, 100)

	match direction:
		"south":
			for i in range(3):
				positions.append(Vector3(70 + i * 30, 0, 10))
		"north":
			for i in range(3):
				positions.append(Vector3(70 + i * 30, 0, 190))
		"east":
			for i in range(3):
				positions.append(Vector3(190, 0, 70 + i * 30))
		"west":
			for i in range(3):
				positions.append(Vector3(10, 0, 70 + i * 30))
		"all":
			positions.append(Vector3(100, 0, 10))   # South
			positions.append(Vector3(100, 0, 190))  # North
			positions.append(Vector3(190, 0, 100))  # East
			positions.append(Vector3(10, 0, 100))   # West

	return positions

func _wave_defeated() -> void:
	wave_active = false
	current_wave += 1

	BattleSignals.wave_defeated.emit(current_wave)

	if current_wave >= TEST_SCENARIO_WAVES.size():
		print("=== ALL WAVES DEFEATED - VICTORY! ===")
	else:
		wave_timer = TEST_SCENARIO_WAVES[current_wave].delay
		print("Wave %d defeated! Next wave in %.0f seconds." % [current_wave, wave_timer])

# =============================================================================
# HUD UPDATE
# =============================================================================

func _update_hud() -> void:
	# Supply display
	var supply_text := "Supplies: %d" % supplies
	if player_firebase:
		supply_text += " | Ammo: %.0f%%" % player_firebase.supplies.ammunition
		supply_text += " | Alert: %s" % FirebaseClass.AlertLevel.keys()[player_firebase.alert_level]
	supply_label.text = supply_text

	# Time display
	var time_str := "Time: %02d:%02d" % [int(game_time / 60) % 24, int(game_time) % 60]
	if WeatherSystem.has_method("get_time_string"):
		time_str = WeatherSystem.get_time_string()
	time_label.text = time_str

	# Wave/weather display
	var status := ""
	if wave_active:
		status = "WAVE %d | Enemies: %d" % [current_wave + 1, enemies_remaining]
	elif current_wave < TEST_SCENARIO_WAVES.size():
		status = "Next wave in: %.0fs" % wave_timer
	else:
		status = "VICTORY!"

	if WeatherSystem.has_method("get_weather_name"):
		status += " | " + WeatherSystem.get_weather_name()

	weather_label.text = status

# =============================================================================
# GAME CONTROL
# =============================================================================

func _toggle_pause() -> void:
	is_paused = not is_paused
	get_tree().paused = is_paused
	print("Game %s" % ("PAUSED" if is_paused else "RESUMED"))

func add_supplies(amount: int) -> void:
	supplies += amount
	if player_firebase:
		player_firebase.add_supply("ammunition", amount * 0.5)
		player_firebase.add_supply("construction", amount * 0.3)

func spend_supplies(amount: int) -> bool:
	if supplies >= amount:
		supplies -= amount
		return true
	return false

func request_reinforcements(unit_type: int) -> void:
	## Request reinforcements via helicopter

	if supplies < 50:
		print("Not enough supplies for reinforcements!")
		return

	spend_supplies(50)

	if player_firebase and player_firebase.has_helipad():
		# Request through ReinforcementManager
		if ReinforcementManager.has_method("request_reinforcements"):
			ReinforcementManager.request_reinforcements(
				unit_type,
				player_firebase.get_available_lz(),
				1  # priority
			)
		print("Reinforcements requested - ETA 30 seconds")
	else:
		print("No helipad available for reinforcements!")

func call_airstrike(strike_type: int, target: Vector3) -> void:
	## Call in air support

	if player_firebase and player_firebase.has_comms():
		BattleSignals.airstrike_requested.emit(strike_type, target)
		print("Airstrike requested at position: ", target)
	else:
		print("No communications - cannot call air support!")

# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_unit_died(unit: Node3D, killer: Node3D) -> void:
	if unit.is_in_group("player_units") or unit in player_units.get_children():
		print("Friendly KIA: ", unit.name if unit else "unknown")

		# Remove from selection
		selected_units.erase(unit)

		# Update garrison
		if player_firebase:
			player_firebase.remove_from_garrison(unit)

func _on_firebase_under_attack(firebase: Node3D, attacker: Node3D) -> void:
	print("!!! FIREBASE UNDER ATTACK !!!")
	if firebase == player_firebase:
		# Flash HUD red or something
		pass

func _on_reinforcement_arrived(units: Array, destination: Node3D) -> void:
	print("Reinforcements arrived: ", units.size(), " units")
	for unit in units:
		if is_instance_valid(unit) and player_firebase:
			player_firebase.add_to_garrison(unit)

func _on_weather_changing(new_weather: int, _transition_time: float) -> void:
	var weather_name := "Unknown"
	if WeatherSystem.has_method("get_weather_name"):
		weather_name = WeatherSystem.get_weather_name()
	print("Weather changing to: ", weather_name)

func _on_wave_started(wave_number: int) -> void:
	print("Wave %d has begun!" % wave_number)

func _on_wave_defeated(wave_number: int) -> void:
	print("Wave %d defeated!" % wave_number)
	add_supplies(25)  # Bonus for surviving

# =============================================================================
# CAMPAIGN/MISSION
# =============================================================================

func load_campaign(campaign) -> void:  # campaign: Campaign
	current_campaign = campaign
	var mission = campaign.get_current_mission()
	if mission:
		load_mission(mission)

func load_mission(mission) -> void:  # mission: Campaign.Mission
	current_mission = mission
	scenario_started = false

	# Clear existing game state
	for child in player_units.get_children():
		child.queue_free()
	for child in enemy_units.get_children():
		child.queue_free()
	for child in firebases_node.get_children():
		child.queue_free()

	# Load mission map scene if specified (use get() for untyped mission parameter)
	var map_scene_path: String = mission.get("map_scene") if mission.get("map_scene") else ""
	if not map_scene_path.is_empty() and ResourceLoader.exists(map_scene_path):
		var map_scene = load(map_scene_path) as PackedScene
		if map_scene:
			var map = map_scene.instantiate()
			game_world.add_child(map)

	mission.start()
	scenario_started = true

func complete_objective(objective_id: String) -> void:
	if current_mission:
		current_mission.complete_objective(objective_id)

func fail_mission(reason: String) -> void:
	if current_mission:
		current_mission.fail(reason)

# =============================================================================
# DEBUG COMMANDS
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	# Debug keys
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1:
				# Spawn friendly reinforcements
				request_reinforcements(GameEnums.UnitType.RIFLE_PLATOON)
			KEY_F2:
				# Skip to next wave
				if not wave_active:
					wave_timer = 0.0
					print("Forcing next wave...")
			KEY_F3:
				# Kill all enemies (debug)
				for enemy in enemy_units.get_children():
					enemy.queue_free()
				print("DEBUG: All enemies eliminated")
			KEY_F4:
				# Print game state
				print("=== GAME STATE ===")
				print("Wave: %d/%d" % [current_wave + 1, TEST_SCENARIO_WAVES.size()])
				print("Enemies: %d" % enemy_units.get_child_count())
				print("Player units: %d" % player_units.get_child_count())
				print("Supplies: %d" % supplies)
				if player_firebase:
					print("Firebase: %s" % player_firebase.get_full_status())
