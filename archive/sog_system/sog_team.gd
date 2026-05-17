extends CharacterBody3D
class_name SOGTeam
## SOGTeam - Special Operations Group 6-man recon team
## MAC-V SOG elite reconnaissance units operating deep behind enemy lines

signal mission_started(mission_type: int)
signal mission_objective_complete(objective_id: String)
signal intel_gathered(intel_type: String, position: Vector3, data: Dictionary)
signal team_compromised()
signal contact_report(enemy_count: int, enemy_type: String, position: Vector3)
signal extraction_requested(priority: int)
signal extraction_inbound(eta: float)
signal team_extracted()
signal team_member_kia()
signal team_wiped()
signal prisoner_captured(prisoner: Node3D)
signal wire_tap_placed(position: Vector3)
signal trail_activity_detected(position: Vector3, unit_count: int)

const TEAM_SIZE := 6
const MAX_STEALTH := 1.0
const MIN_STEALTH := 0.0
const STEALTH_RECOVERY_RATE := 0.05  # Per second while hiding
const STEALTH_DECAY_MOVING := 0.02   # Per second while moving
const DETECTION_TIMEOUT := 45.0      # Seconds to lose pursuers

# Team identification
@export var team_name: String = "RT Python"
@export var one_zero: String = "SGT Smith"  # Team leader (American)
@export var one_one: String = "SGT Jones"   # Assistant team leader
@export var callsign: String = "Python One-Zero"

# Team composition (1-2 Americans, 4-5 indigenous personnel)
@export var american_count: int = 2
@export var indig_count: int = 4  # CIDG/Montagnard/Nung

# Movement
@export var move_speed: float = 4.0  # Slower for stealth
@export var run_speed: float = 7.0
@export var crawl_speed: float = 1.5
@export var rotation_speed: float = 5.0

# Combat (minimal - focus on recon)
@export var sight_range: float = 40.0
@export var stealth_rating: float = 1.0  # 1.0 = very stealthy, 0.0 = compromised

# Team status
var team_size: int = TEAM_SIZE
var team_health: float = 100.0
var morale: float = 100.0
var fatigue: float = 0.0  # 0-100, affects performance
var ammo: int = 200  # Limited ammo for SOG
var grenades: int = 12
var claymores: int = 2

# Special Equipment
var has_camera: bool = true       # Photo recon capability
var has_radio: bool = true        # Comms (can be damaged)
var has_wiretap_kit: bool = false # For WIRE_TAP missions
var has_prisoner_kit: bool = false # For PRISONER_SNATCH
var photos_taken: int = 0
var wire_taps_placed: int = 0

# Mission
var current_mission: int = GameEnums.SOGMissionType.RECON
var mission_objectives: Array = []  # Array of SOGObjective
var completed_objectives: Array[String] = []
var mission_start_time: float = 0.0
var max_mission_duration: float = 3600.0  # 1 hour in-game

# Insertion/Extraction
var insertion_lz = null  # LandingZone
var extraction_lz = null  # LandingZone
var primary_extraction: Vector3 = Vector3.ZERO
var alternate_extraction: Vector3 = Vector3.ZERO
var emergency_extraction: Vector3 = Vector3.ZERO
var is_inserted: bool = false
var extraction_pending: bool = false
var extraction_eta: float = 0.0

# Stealth
var is_compromised: bool = false
var detection_timer: float = 0.0
var enemies_tracking: Array[Node3D] = []
var last_known_position: Vector3 = Vector3.ZERO
var terrain_concealment: float = 0.0  # Bonus from terrain

# Trail watching (for TRAIL_WATCH missions)
var is_trail_watching: bool = false
var trail_watch_position: Vector3 = Vector3.ZERO
var trail_watch_data: Array[Dictionary] = []

# Captured prisoners
var prisoners: Array[Node3D] = []

# Navigation
var nav_agent: NavigationAgent3D
var move_target: Vector3 = Vector3.ZERO
var waypoints: Array[Vector3] = []
var movement_mode: MovementMode = MovementMode.STEALTH

enum TeamState { IDLE, MOVING, OBSERVING, EVADING, HIDING, EXTRACTED, SETTING_AMBUSH, CAPTURING, TRAIL_WATCHING }
enum MovementMode { STEALTH, TACTICAL, EMERGENCY, CRAWL }

var current_state: TeamState = TeamState.IDLE

# Ambush setup
var ambush_claymores: Array[Vector3] = []
var ambush_ready: bool = false

# Selection
var is_selected: bool = false

# Visual
var visual_mesh: MeshInstance3D = null

func _ready() -> void:
	add_to_group("sog_teams")
	add_to_group("player_units")
	add_to_group("us_forces")
	add_to_group("special_forces")

	# Setup navigation
	nav_agent = NavigationAgent3D.new()
	nav_agent.path_desired_distance = 1.0
	nav_agent.target_desired_distance = 2.0
	add_child(nav_agent)
	nav_agent.velocity_computed.connect(_on_velocity_computed)

	# Create visual placeholder
	_create_visual()

	# Initialize extraction points
	primary_extraction = global_position
	alternate_extraction = global_position + Vector3(100, 0, 0)
	emergency_extraction = global_position + Vector3(-100, 0, 0)

func _create_visual() -> void:
	## Create placeholder SOG team visual (green beret style)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.4
	mesh.bottom_radius = 0.5
	mesh.height = 1.8

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.35, 0.2)  # Dark green (tiger stripes implied)
	mat.roughness = 0.9

	visual_mesh = MeshInstance3D.new()
	visual_mesh.mesh = mesh
	visual_mesh.material_override = mat
	visual_mesh.position.y = 0.9

	add_child(visual_mesh)

	# Beret indicator (small sphere on top)
	var beret := MeshInstance3D.new()
	var beret_mesh := SphereMesh.new()
	beret_mesh.radius = 0.25
	beret.mesh = beret_mesh

	var beret_mat := StandardMaterial3D.new()
	beret_mat.albedo_color = Color(0.1, 0.4, 0.1)  # Green beret
	beret.material_override = beret_mat
	beret.position.y = 1.0

	visual_mesh.add_child(beret)

func _physics_process(delta: float) -> void:
	if current_state == TeamState.EXTRACTED:
		return

	_update_stealth(delta)
	_update_detection(delta)
	_update_fatigue(delta)
	_update_mission_timer(delta)
	_update_terrain_concealment()
	_update_extraction_eta(delta)
	_process_suppression(delta)

	match current_state:
		TeamState.MOVING:
			_process_movement(delta)
		TeamState.OBSERVING:
			_process_observation(delta)
		TeamState.EVADING:
			_process_evasion(delta)
		TeamState.HIDING:
			_process_hiding(delta)
		TeamState.SETTING_AMBUSH:
			_process_ambush_setup(delta)
		TeamState.CAPTURING:
			_process_capture(delta)
		TeamState.TRAIL_WATCHING:
			_process_trail_watch(delta)

	# Update visual based on stealth
	_update_visual()

func _update_fatigue(delta: float) -> void:
	# Fatigue increases during movement, decreases while hiding
	if current_state == TeamState.MOVING or current_state == TeamState.EVADING:
		fatigue = minf(100.0, fatigue + 0.5 * delta)
	elif current_state == TeamState.HIDING:
		fatigue = maxf(0.0, fatigue - 1.0 * delta)

	# High fatigue affects movement speed
	if fatigue > 75.0:
		move_speed = 3.0
		run_speed = 5.5

func _update_mission_timer(delta: float) -> void:
	if not is_inserted:
		return

	mission_start_time += delta

	# Warn when mission is running long
	if mission_start_time > max_mission_duration * 0.8:
		# Should consider extraction
		if not extraction_pending:
			BattleSignals.sog_mission_overtime.emit(self)

func _update_terrain_concealment() -> void:
	# Get terrain type at current position
	# Triple canopy provides excellent concealment
	terrain_concealment = 0.3  # Default moderate concealment

	# This would check actual terrain type
	# var terrain := TerrainClearingSystem.get_terrain_type(global_position)
	# match terrain:
	#     ClearingState.JUNGLE: terrain_concealment = 0.5
	#     ClearingState.PARTIALLY_CLEARED: terrain_concealment = 0.2
	#     ClearingState.CLEARED: terrain_concealment = 0.0

func _update_extraction_eta(delta: float) -> void:
	if extraction_eta > 0:
		extraction_eta -= delta
		if extraction_eta <= 0:
			extraction_eta = 0.0

func _update_visual() -> void:
	if not visual_mesh:
		return

	# Fade visual based on stealth (indicates visibility to enemies)
	var mat := visual_mesh.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color.a = 1.0 - (stealth_rating * 0.5)

# =============================================================================
# STEALTH SYSTEM
# =============================================================================

func _update_stealth(delta: float) -> void:
	# Stealth recovery/decay based on state
	match current_state:
		TeamState.HIDING:
			# Recover stealth while hidden
			stealth_rating = minf(MAX_STEALTH, stealth_rating + STEALTH_RECOVERY_RATE * delta)
		TeamState.MOVING:
			# Movement mode affects stealth decay
			var decay := STEALTH_DECAY_MOVING
			match movement_mode:
				MovementMode.CRAWL:
					decay *= 0.2  # Almost no decay when crawling
				MovementMode.STEALTH:
					decay *= 1.0
				MovementMode.TACTICAL:
					decay *= 2.0
				MovementMode.EMERGENCY:
					decay *= 5.0  # Running is very visible
			stealth_rating = maxf(0.2, stealth_rating - decay * delta)
		TeamState.EVADING:
			# Running away is loud
			stealth_rating = maxf(MIN_STEALTH, stealth_rating - 0.1 * delta)
		TeamState.TRAIL_WATCHING, TeamState.OBSERVING:
			# Stationary observation - slow recovery
			stealth_rating = minf(MAX_STEALTH, stealth_rating + STEALTH_RECOVERY_RATE * 0.5 * delta)

	# Terrain concealment bonus
	stealth_rating = minf(MAX_STEALTH, stealth_rating + terrain_concealment * 0.1 * delta)

func _update_detection(delta: float) -> void:
	# Clean up invalid trackers
	enemies_tracking = enemies_tracking.filter(func(e): return is_instance_valid(e))

	if is_compromised:
		detection_timer += delta
		last_known_position = global_position

		# After timeout and no trackers, can recover
		if detection_timer > DETECTION_TIMEOUT and enemies_tracking.is_empty():
			_recover_stealth()
		return

	# Check for enemy detection
	var enemies := SpatialHashGrid.get_enemies_in_radius(
		global_position, sight_range, GameEnums.Faction.US_ARMY
	)

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		var distance := global_position.distance_to(enemy.global_position)
		var detection_chance := _calculate_detection_chance(enemy, distance)

		if randf() < detection_chance * delta:
			_go_loud(enemy)
			break

func _calculate_detection_chance(enemy: Node3D, distance: float) -> float:
	var base_chance := 0.05  # Base 5% per second at close range

	# Distance factor (inverse square falloff)
	var distance_factor := 1.0 - (distance / sight_range)
	distance_factor = maxf(0.0, distance_factor * distance_factor)
	base_chance *= distance_factor

	# Stealth rating significantly reduces detection
	base_chance *= (1.0 - stealth_rating * 0.9)

	# Terrain concealment helps
	base_chance *= (1.0 - terrain_concealment)

	# Team size affects detection (more people = easier to spot)
	base_chance *= (team_size / float(TEAM_SIZE))

	# Movement mode affects detection
	match movement_mode:
		MovementMode.CRAWL:
			base_chance *= 0.3
		MovementMode.STEALTH:
			base_chance *= 0.6
		MovementMode.TACTICAL:
			base_chance *= 1.2
		MovementMode.EMERGENCY:
			base_chance *= 3.0

	# Current state affects detection
	if current_state == TeamState.HIDING:
		base_chance *= 0.2

	# Time of day
	if WeatherSystem.is_night():
		base_chance *= 0.4

	# Weather conditions
	var effects := WeatherSystem.get_weather_effects()
	if effects.has("detection_modifier"):
		base_chance *= effects.detection_modifier
	else:
		base_chance *= effects.get("detection_range", 1.0)

	# Prisoners slow down and make noise
	if prisoners.size() > 0:
		base_chance *= 1.5

	# Fatigue makes team sloppy
	if fatigue > 50.0:
		base_chance *= 1.0 + (fatigue - 50.0) / 100.0

	return clampf(base_chance, 0.0, 1.0)

func _go_loud(spotter: Node3D = null) -> void:
	## Cover blown - team is compromised
	if is_compromised:
		# Already compromised, just add another tracker
		if spotter and spotter not in enemies_tracking:
			enemies_tracking.append(spotter)
		return

	is_compromised = true
	stealth_rating = MIN_STEALTH
	detection_timer = 0.0
	last_known_position = global_position

	if spotter:
		enemies_tracking.append(spotter)

	team_compromised.emit()
	BattleSignals.sog_compromised.emit(self)

	# Report contact
	var enemy_count := enemies_tracking.size()
	contact_report.emit(enemy_count, "enemy_infantry", global_position)

	# Automatically request emergency extraction
	request_emergency_extraction()

func _recover_stealth() -> void:
	## Team has broken contact
	is_compromised = false
	stealth_rating = 0.5  # Partial recovery
	detection_timer = 0.0
	enemies_tracking.clear()

	BattleSignals.sog_contact_broken.emit(self)

func break_contact() -> void:
	## Manually attempt to break contact
	if not is_compromised:
		return

	# Move away from last known position
	var escape_direction := (global_position - last_known_position).normalized()
	if escape_direction.length() < 0.1:
		escape_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()

	var escape_point := global_position + escape_direction * 50.0
	move_to(escape_point, false)  # Fast escape movement
	current_state = TeamState.EVADING
	movement_mode = MovementMode.EMERGENCY

func get_stealth_percentage() -> float:
	return stealth_rating * 100.0

func is_detected() -> bool:
	return is_compromised

# =============================================================================
# MOVEMENT
# =============================================================================

func move_to(target: Vector3, stealth: bool = true) -> void:
	move_target = target
	nav_agent.target_position = target

	if stealth:
		current_state = TeamState.MOVING
		movement_mode = MovementMode.STEALTH
	else:
		# Faster but louder movement
		current_state = TeamState.EVADING
		movement_mode = MovementMode.EMERGENCY

func move_to_tactical(target: Vector3) -> void:
	## Tactical movement - balanced speed and stealth
	move_target = target
	nav_agent.target_position = target
	current_state = TeamState.MOVING
	movement_mode = MovementMode.TACTICAL

func crawl_to(target: Vector3) -> void:
	## Very slow but extremely stealthy movement
	move_target = target
	nav_agent.target_position = target
	current_state = TeamState.MOVING
	movement_mode = MovementMode.CRAWL

func set_movement_mode(mode: MovementMode) -> void:
	movement_mode = mode

func _get_current_speed() -> float:
	match movement_mode:
		MovementMode.CRAWL:
			return crawl_speed
		MovementMode.STEALTH:
			return move_speed
		MovementMode.TACTICAL:
			return (move_speed + run_speed) / 2.0
		MovementMode.EMERGENCY:
			return run_speed
	return move_speed

func _process_movement(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		current_state = TeamState.IDLE
		_check_waypoint_completion()
		return

	var next_pos := nav_agent.get_next_path_position()
	var direction := (next_pos - global_position).normalized()

	# Face movement direction
	if direction.length() > 0.1:
		var target_rotation := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)

	var speed := _get_current_speed()

	# Fatigue reduces speed
	if fatigue > 50.0:
		speed *= 1.0 - (fatigue - 50.0) / 200.0  # Up to 25% slower at max fatigue

	# Prisoners slow movement
	if prisoners.size() > 0:
		speed *= 0.7

	velocity = direction * speed
	nav_agent.set_velocity(velocity)

func _check_waypoint_completion() -> void:
	## Check if we've reached a waypoint in our route
	if waypoints.is_empty():
		return

	var current_wp := waypoints[0]
	if global_position.distance_to(current_wp) < 3.0:
		waypoints.remove_at(0)

		# If more waypoints, continue
		if not waypoints.is_empty():
			move_to(waypoints[0], movement_mode == MovementMode.STEALTH)

func follow_route(route: Array[Vector3]) -> void:
	## Follow a predefined route (waypoints)
	waypoints = route.duplicate()
	if not waypoints.is_empty():
		move_to(waypoints[0])

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity = safe_velocity
	move_and_slide()

func halt() -> void:
	## Stop all movement immediately
	current_state = TeamState.IDLE
	velocity = Vector3.ZERO
	waypoints.clear()

func is_moving() -> bool:
	return current_state == TeamState.MOVING or current_state == TeamState.EVADING

# =============================================================================
# MISSION OPERATIONS
# =============================================================================

func set_mission(mission_type: int, objectives: Array[SOGObjective]) -> void:
	current_mission = mission_type
	mission_objectives = objectives
	completed_objectives.clear()
	mission_start_time = 0.0

	# Equip based on mission
	match mission_type:
		GameEnums.SOGMissionType.WIRE_TAP:
			has_wiretap_kit = true
		GameEnums.SOGMissionType.PRISONER_SNATCH:
			has_prisoner_kit = true

	mission_started.emit(mission_type)
	BattleSignals.sog_mission_started.emit(self, mission_type)

func complete_objective(objective_id: String) -> void:
	## Mark an objective as complete
	if objective_id in completed_objectives:
		return

	completed_objectives.append(objective_id)

	for obj in mission_objectives:
		if obj.id == objective_id:
			obj.is_complete = true
			break

	mission_objective_complete.emit(objective_id)
	BattleSignals.sog_objective_complete.emit(self, objective_id)

	# Check if all objectives complete
	var all_complete := true
	for obj in mission_objectives:
		if not obj.is_optional and not obj.is_complete:
			all_complete = false
			break

	if all_complete:
		BattleSignals.sog_mission_complete.emit(self)

func get_current_objective() -> SOGObjective:
	## Get the next incomplete objective
	for obj in mission_objectives:
		if not obj.is_complete:
			return obj
	return null

func observe_position(position: Vector3, duration: float = 30.0) -> void:
	## Set up observation of a position
	move_to(position)
	# After reaching position, enter observation mode
	await nav_agent.navigation_finished
	current_state = TeamState.OBSERVING

var observation_timer: float = 0.0
var observation_target: Vector3 = Vector3.ZERO
var observed_enemies: Dictionary = {}  # enemy -> first_seen_time

func _process_observation(delta: float) -> void:
	observation_timer += delta

	# Gather intel on nearby enemies
	var enemies := SpatialHashGrid.get_enemies_in_radius(
		global_position, sight_range * 1.5, GameEnums.Faction.US_ARMY
	)

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		# Track observed enemies
		if enemy not in observed_enemies:
			observed_enemies[enemy] = observation_timer

			# Report new contact
			var enemy_type := "unknown"
			if enemy.has_method("get_unit_type"):
				enemy_type = str(enemy.get_unit_type())

			intel_gathered.emit("enemy_contact", enemy.global_position, {
				"unit_type": enemy_type,
				"direction": enemy.global_position - global_position,
				"distance": global_position.distance_to(enemy.global_position)
			})

	# Take photos if observing for recon mission
	if current_mission == GameEnums.SOGMissionType.RECON:
		if has_camera and observation_timer > 5.0:
			_take_photo()
			observation_timer = 0.0

func _take_photo() -> void:
	## Take reconnaissance photo
	if not has_camera:
		return

	photos_taken += 1

	var photo_data := {
		"position": global_position,
		"direction": -global_transform.basis.z,
		"enemies_visible": observed_enemies.size(),
		"timestamp": Time.get_ticks_msec()
	}

	intel_gathered.emit("photo_recon", global_position, photo_data)

	# Check if this completes a BDA or RECON objective
	for obj in mission_objectives:
		if obj.objective_type in [GameEnums.SOGMissionType.RECON, GameEnums.SOGMissionType.BDA]:
			if global_position.distance_to(obj.position) < 50.0:
				complete_objective(obj.id)

func hide() -> void:
	## Enter hiding mode to recover stealth
	current_state = TeamState.HIDING
	halt()

func _process_hiding(delta: float) -> void:
	# Stay still and recover stealth
	# Already handled in _update_stealth
	pass

func _process_evasion(delta: float) -> void:
	# Fast movement to extraction
	_process_movement(delta)

	# Check if we've lost pursuers
	enemies_tracking = enemies_tracking.filter(func(e): return is_instance_valid(e))

	# If no one tracking and moved far from last known, can try to hide
	if enemies_tracking.is_empty():
		if global_position.distance_to(last_known_position) > 100.0:
			_recover_stealth()
			hide()

# =============================================================================
# TRAIL WATCH OPERATIONS
# =============================================================================

func setup_trail_watch(position: Vector3) -> void:
	## Set up observation post overlooking a trail
	trail_watch_position = position
	move_to(position)
	await nav_agent.navigation_finished
	current_state = TeamState.TRAIL_WATCHING
	is_trail_watching = true

func _process_trail_watch(delta: float) -> void:
	if not is_trail_watching:
		return

	# Monitor trail for enemy movement
	var trail_enemies := SpatialHashGrid.get_enemies_in_radius(
		trail_watch_position, 30.0, GameEnums.Faction.US_ARMY
	)

	if trail_enemies.size() > 0:
		var unit_count := 0
		for enemy in trail_enemies:
			if enemy.has_method("get_squad_size"):
				unit_count += enemy.get_squad_size()
			else:
				unit_count += 1

		# Log trail activity
		var entry := {
			"timestamp": Time.get_ticks_msec(),
			"unit_count": unit_count,
			"position": trail_watch_position,
			"direction": Vector3.ZERO  # Would calculate from enemy movement
		}
		trail_watch_data.append(entry)

		trail_activity_detected.emit(trail_watch_position, unit_count)
		intel_gathered.emit("trail_activity", trail_watch_position, entry)

		# Check for objective completion
		for obj in mission_objectives:
			if obj.objective_type == GameEnums.SOGMissionType.TRAIL_WATCH:
				if trail_watch_data.size() >= 3:  # Observed enough
					complete_objective(obj.id)

func end_trail_watch() -> void:
	is_trail_watching = false
	current_state = TeamState.IDLE

func get_trail_watch_report() -> Array[Dictionary]:
	return trail_watch_data

# =============================================================================
# PRISONER SNATCH OPERATIONS
# =============================================================================

func attempt_capture(target: Node3D) -> bool:
	## Attempt to capture an enemy (usually officer or courier)
	if not has_prisoner_kit:
		return false

	if not is_instance_valid(target):
		return false

	var distance := global_position.distance_to(target.global_position)
	if distance > 5.0:
		return false  # Too far

	# Must be stealthy
	if stealth_rating < 0.5:
		return false

	current_state = TeamState.CAPTURING

	# Check capture success
	var success_chance := 0.7  # 70% base chance
	success_chance *= stealth_rating  # Stealth affects success

	if randf() < success_chance:
		_capture_prisoner(target)
		return true
	else:
		# Failed - now compromised
		_go_loud(target)
		return false

func _capture_prisoner(target: Node3D) -> void:
	prisoners.append(target)

	# Disable the captured unit
	if target.has_method("capture"):
		target.capture()
	else:
		target.set_process(false)
		target.visible = false

	prisoner_captured.emit(target)

	# Complete PRISONER_SNATCH objective
	for obj in mission_objectives:
		if obj.objective_type == GameEnums.SOGMissionType.PRISONER_SNATCH:
			complete_objective(obj.id)

func _process_capture(delta: float) -> void:
	# Capture animation/delay would go here
	current_state = TeamState.IDLE

func release_prisoners() -> void:
	## Release prisoners (usually at extraction)
	for prisoner in prisoners:
		if is_instance_valid(prisoner):
			# Hand over to command
			pass
	prisoners.clear()

# =============================================================================
# WIRE TAP OPERATIONS
# =============================================================================

func place_wire_tap(position: Vector3) -> bool:
	## Place wire tap on enemy communications line
	if not has_wiretap_kit:
		return false

	if global_position.distance_to(position) > 5.0:
		return false

	# Takes time and makes noise
	await get_tree().create_timer(5.0).timeout

	wire_taps_placed += 1
	wire_tap_placed.emit(position)
	intel_gathered.emit("wire_tap", position, {"tap_id": wire_taps_placed})

	# Complete WIRE_TAP objective
	for obj in mission_objectives:
		if obj.objective_type == GameEnums.SOGMissionType.WIRE_TAP:
			if obj.position.distance_to(position) < 20.0:
				complete_objective(obj.id)

	return true

# =============================================================================
# AMBUSH SETUP
# =============================================================================

func setup_ambush(position: Vector3) -> void:
	## Set up ambush position with claymores
	move_to(position)
	await nav_agent.navigation_finished
	current_state = TeamState.SETTING_AMBUSH

func _process_ambush_setup(delta: float) -> void:
	if claymores <= 0:
		current_state = TeamState.IDLE
		ambush_ready = true
		return

	# Place claymore
	if claymores > 0:
		_place_claymore(global_position + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10)))
		claymores -= 1

func _place_claymore(position: Vector3) -> void:
	ambush_claymores.append(position)
	# Create claymore node
	# var claymore := preload("res://weapons/claymore.tscn").instantiate()
	# claymore.global_position = position
	# get_tree().current_scene.add_child(claymore)

func trigger_ambush() -> void:
	## Detonate claymores and open fire
	if not ambush_ready:
		return

	# Detonate all claymores
	for claymore_pos in ambush_claymores:
		BattleSignals.explosion.emit(claymore_pos, 15.0, 100.0)

		# Damage enemies in radius
		var victims := SpatialHashGrid.get_all_units_in_radius(claymore_pos, 15.0)
		for victim in victims:
			if is_instance_valid(victim) and victim.has_method("take_damage"):
				if victim.has_method("get_faction"):
					if not GameEnums.is_us_faction(victim.get_faction()):
						victim.take_damage(100.0, self)

	ambush_claymores.clear()
	ambush_ready = false

	# Now compromised
	_go_loud()

# =============================================================================
# DIRECT ACTION
# =============================================================================

func assault_target(target: Node3D) -> void:
	## Direct action assault on a target
	if not is_instance_valid(target):
		return

	# Trigger ambush if set up
	if ambush_ready:
		trigger_ambush()

	# Move to engage
	movement_mode = MovementMode.TACTICAL
	move_to(target.global_position, false)

	# Will be compromised during assault
	_go_loud()

func silent_kill(target: Node3D) -> bool:
	## Attempt silent kill on isolated enemy
	if not is_instance_valid(target):
		return false

	var distance := global_position.distance_to(target.global_position)
	if distance > 3.0:
		return false  # Too far

	# Check if target is isolated
	var nearby := SpatialHashGrid.get_enemies_in_radius(
		target.global_position, 20.0, GameEnums.Faction.US_ARMY
	)

	if nearby.size() > 1:
		return false  # Not isolated

	# Success based on stealth
	var success_chance := 0.8 * stealth_rating

	if randf() < success_chance:
		if target.has_method("take_damage"):
			target.take_damage(999.0, self)  # Instant kill
		return true
	else:
		_go_loud(target)
		return false

# =============================================================================
# EXTRACTION
# =============================================================================

func set_extraction_points(primary: Vector3, alternate: Vector3, emergency: Vector3) -> void:
	## Set mission extraction points
	primary_extraction = primary
	alternate_extraction = alternate
	emergency_extraction = emergency

func request_extraction(priority: int = 5) -> void:
	## Request routine extraction
	if extraction_pending:
		return

	extraction_pending = true

	extraction_requested.emit(priority)

	# Request from InsertionManager
	var result := InsertionManager.request_extraction(
		primary_extraction, [self], priority, false
	)

	if result.has("eta"):
		extraction_eta = result.eta
		extraction_inbound.emit(extraction_eta)

func request_emergency_extraction() -> void:
	## Request emergency extraction (compromised team)
	if extraction_pending:
		return

	extraction_pending = true
	var priority := 10  # Maximum priority

	extraction_requested.emit(priority)

	# Use emergency extraction point
	var extract_point := emergency_extraction
	if extract_point == Vector3.ZERO:
		extract_point = global_position

	var result := InsertionManager.request_extraction(
		extract_point, [self], priority, true
	)

	if result.has("eta"):
		extraction_eta = result.eta
		extraction_inbound.emit(extraction_eta)

	# Move to extraction point
	move_to(extract_point, false)  # Fast movement, stealth doesn't matter
	movement_mode = MovementMode.EMERGENCY

func set_extraction_lz(lz) -> void:  # lz: LandingZone
	extraction_lz = lz
	move_to(lz.global_position, not is_compromised)

	if is_compromised:
		current_state = TeamState.EVADING
		movement_mode = MovementMode.EMERGENCY
	else:
		current_state = TeamState.MOVING
		movement_mode = MovementMode.TACTICAL

func move_to_extraction() -> void:
	## Move to primary extraction point
	if is_compromised:
		move_to(emergency_extraction, false)
		movement_mode = MovementMode.EMERGENCY
	else:
		move_to(primary_extraction, true)
		movement_mode = MovementMode.STEALTH

func on_extraction_helicopter_inbound(eta: float) -> void:
	extraction_eta = eta
	extraction_inbound.emit(eta)

	# Move to extraction point if not already
	if not is_moving():
		move_to_extraction()

func on_extracted() -> void:
	current_state = TeamState.EXTRACTED
	is_inserted = false
	extraction_pending = false
	extraction_eta = 0.0

	# Release prisoners to command
	release_prisoners()

	# Calculate mission success
	var mission_result := _calculate_mission_result()

	team_extracted.emit()
	BattleSignals.sog_extracted.emit(self, mission_result)

func _calculate_mission_result() -> Dictionary:
	var objectives_completed := 0
	var total_objectives := 0

	for obj in mission_objectives:
		if not obj.is_optional:
			total_objectives += 1
			if obj.is_complete:
				objectives_completed += 1

	var success_rate := 0.0
	if total_objectives > 0:
		success_rate = float(objectives_completed) / float(total_objectives)

	return {
		"objectives_completed": objectives_completed,
		"total_objectives": total_objectives,
		"success_rate": success_rate,
		"team_casualties": TEAM_SIZE - team_size,
		"prisoners_captured": prisoners.size(),
		"photos_taken": photos_taken,
		"wire_taps": wire_taps_placed,
		"was_compromised": is_compromised or stealth_rating < 0.5,
		"mission_duration": mission_start_time
	}

func abort_mission() -> void:
	## Abort mission and request immediate extraction
	request_emergency_extraction()

func get_extraction_eta() -> float:
	return extraction_eta

func is_extraction_pending() -> bool:
	return extraction_pending

# =============================================================================
# COMBAT (Limited - SOG avoids prolonged firefights)
# =============================================================================

var suppression: float = 0.0
const MAX_SUPPRESSION := 100.0

func take_damage(amount: float, source: Node3D = null) -> void:
	team_health -= amount

	# Taking fire compromises team
	if not is_compromised and source:
		_go_loud(source)

	# Record attacker for tracking
	if source and source not in enemies_tracking:
		enemies_tracking.append(source)

	if team_health <= 0:
		_casualty()

func apply_suppression(amount: float) -> void:
	## Apply suppression effect
	suppression = minf(MAX_SUPPRESSION, suppression + amount)

	# High suppression forces team to ground
	if suppression > 75.0:
		hide()

func _process_suppression(delta: float) -> void:
	# Suppression decays over time
	suppression = maxf(0.0, suppression - 10.0 * delta)

	# Heavy suppression affects accuracy
	if suppression > 50.0:
		# Would reduce combat effectiveness
		pass

func _casualty() -> void:
	team_size -= 1
	team_health = 100.0

	# Determine if American or Indig
	var was_american := false
	if american_count > 0 and randf() < float(american_count) / float(team_size + 1):
		american_count -= 1
		was_american = true
	else:
		indig_count -= 1

	team_member_kia.emit()
	BattleSignals.sog_casualty.emit(self, was_american)

	# Losing team members affects morale
	morale -= 20.0

	# If one-zero is killed, team effectiveness drops
	if team_size == TEAM_SIZE - 1 and was_american:
		# Team leader potentially down
		if randf() < 0.5:
			morale -= 30.0

	if team_size <= 0:
		_team_wiped()
	elif team_size <= 2:
		# Critical casualties - must extract
		request_emergency_extraction()

func _team_wiped() -> void:
	team_wiped.emit()
	BattleSignals.sog_wiped.emit(self)

	# Drop any intel/prisoners
	prisoners.clear()

	queue_free()

func engage_targets() -> void:
	## Open fire on visible enemies
	var enemies := SpatialHashGrid.get_enemies_in_radius(
		global_position, sight_range, GameEnums.Faction.US_ARMY
	)

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		if enemy.has_method("take_damage"):
			# SOG uses CAR-15s, very effective at close range
			var distance := global_position.distance_to(enemy.global_position)
			var accuracy := 0.8 * (1.0 - distance / sight_range)
			accuracy *= (1.0 - suppression / MAX_SUPPRESSION)

			if randf() < accuracy:
				enemy.take_damage(25.0, self)

	# Firing compromises team
	_go_loud()

	# Use ammo
	ammo -= 10

func throw_grenade(target_position: Vector3) -> void:
	## Throw fragmentation grenade
	if grenades <= 0:
		return

	grenades -= 1

	var distance := global_position.distance_to(target_position)
	if distance > 30.0:
		return  # Too far to throw

	# Schedule explosion
	await get_tree().create_timer(2.5).timeout

	BattleSignals.explosion.emit(target_position, 8.0, 80.0)

	# Damage enemies
	var victims := SpatialHashGrid.get_all_units_in_radius(target_position, 8.0)
	for victim in victims:
		if is_instance_valid(victim) and victim.has_method("take_damage"):
			var dist := victim.global_position.distance_to(target_position)
			var damage := 80.0 * (1.0 - dist / 8.0)
			victim.take_damage(damage, self)

	# Grenades are loud
	_go_loud()

func fire_mad_minute() -> void:
	## "Mad minute" - everyone fires on full auto to break contact
	if ammo < 50:
		return

	ammo -= 50

	# Suppress everything in front
	var enemies := SpatialHashGrid.get_enemies_in_radius(
		global_position, sight_range, GameEnums.Faction.US_ARMY
	)

	for enemy in enemies:
		if is_instance_valid(enemy):
			if enemy.has_method("apply_suppression"):
				enemy.apply_suppression(80.0)
			if enemy.has_method("take_damage"):
				enemy.take_damage(15.0 * team_size, self)

	# Very loud - everyone knows where we are
	_go_loud()

func get_combat_effectiveness() -> float:
	## Return current combat effectiveness (0-1)
	var effectiveness := 1.0

	# Team size affects effectiveness
	effectiveness *= team_size / float(TEAM_SIZE)

	# Morale affects effectiveness
	effectiveness *= morale / 100.0

	# Suppression reduces effectiveness
	effectiveness *= (1.0 - suppression / MAX_SUPPRESSION)

	# Fatigue affects effectiveness
	effectiveness *= (1.0 - fatigue / 200.0)

	# Low ammo is a problem
	if ammo < 50:
		effectiveness *= 0.5

	return clampf(effectiveness, 0.0, 1.0)

# =============================================================================
# SELECTION & UI
# =============================================================================

func select() -> void:
	is_selected = true
	# Visual feedback
	if visual_mesh:
		var mat := visual_mesh.material_override as StandardMaterial3D
		if mat:
			mat.emission_enabled = true
			mat.emission = Color(0.0, 0.5, 0.0)

func deselect() -> void:
	is_selected = false
	# Remove visual feedback
	if visual_mesh:
		var mat := visual_mesh.material_override as StandardMaterial3D
		if mat:
			mat.emission_enabled = false

func get_faction() -> int:
	return GameEnums.Faction.US_ARMY

func get_display_name() -> String:
	return team_name + " (" + callsign + ")"

func get_status_text() -> String:
	var status := ""

	match current_state:
		TeamState.IDLE: status = "Standing by"
		TeamState.MOVING: status = "Moving"
		TeamState.OBSERVING: status = "Observing"
		TeamState.EVADING: status = "Evading!"
		TeamState.HIDING: status = "Concealed"
		TeamState.EXTRACTED: status = "Extracted"
		TeamState.SETTING_AMBUSH: status = "Setting ambush"
		TeamState.CAPTURING: status = "Capturing target"
		TeamState.TRAIL_WATCHING: status = "Trail watch"

	if is_compromised:
		status += " [COMPROMISED]"

	if extraction_pending:
		status += " [Extract ETA: " + str(int(extraction_eta)) + "s]"

	return status

func get_team_info() -> Dictionary:
	return {
		"name": team_name,
		"callsign": callsign,
		"one_zero": one_zero,
		"team_size": team_size,
		"americans": american_count,
		"indig": indig_count,
		"stealth": get_stealth_percentage(),
		"state": current_state,
		"compromised": is_compromised,
		"morale": morale,
		"ammo": ammo,
		"grenades": grenades,
		"claymores": claymores,
		"prisoners": prisoners.size(),
		"photos": photos_taken
	}

func get_mission_status() -> Dictionary:
	var completed := 0
	var total := 0

	for obj in mission_objectives:
		if not obj.is_optional:
			total += 1
			if obj.is_complete:
				completed += 1

	return {
		"mission_type": current_mission,
		"objectives_completed": completed,
		"objectives_total": total,
		"duration": mission_start_time,
		"photos_taken": photos_taken,
		"wire_taps": wire_taps_placed,
		"prisoners": prisoners.size()
	}

# =============================================================================
# INSERTION
# =============================================================================

func on_inserted(lz) -> void:  # lz: LandingZone
	## Called when team is inserted at LZ
	insertion_lz = lz
	is_inserted = true
	mission_start_time = 0.0
	current_state = TeamState.IDLE

	# Set extraction points based on insertion
	primary_extraction = lz.global_position
	alternate_extraction = lz.global_position + Vector3(200, 0, 0)

	BattleSignals.sog_inserted.emit(self, lz)

func get_time_on_ground() -> float:
	return mission_start_time

# =============================================================================
# RADIO COMMUNICATIONS
# =============================================================================

func send_sitrep() -> void:
	## Send situation report to command
	if not has_radio:
		return

	var sitrep := {
		"team": team_name,
		"position": global_position,
		"status": get_status_text(),
		"team_size": team_size,
		"compromised": is_compromised,
		"objectives": get_mission_status()
	}

	BattleSignals.sog_sitrep.emit(self, sitrep)

func call_for_fire(target: Vector3, fire_type: String = "HE") -> void:
	## Request fire support (artillery or air)
	if not has_radio:
		return

	# This would interface with AirSupportManager or Firebase artillery
	BattleSignals.fire_support_request.emit(target, fire_type, self)

func request_covey_support() -> void:
	## Request Covey (FAC) overhead support
	if not has_radio:
		return

	BattleSignals.covey_support_request.emit(self, global_position)

func radio_damaged() -> void:
	## Radio has been damaged
	has_radio = false
	# Team is now isolated
	BattleSignals.sog_radio_lost.emit(self)

# =============================================================================
# SOG OBJECTIVE CLASS
# =============================================================================

class SOGObjective:
	extends RefCounted

	var id: String
	var objective_type: int  # SOGMissionType
	var position: Vector3
	var description: String
	var is_complete: bool = false
	var is_optional: bool = false
	var time_limit: float = 0.0  # 0 = no limit
	var target_node: Node3D = null  # For capture/destroy objectives
	var intel_required: int = 0  # For observation objectives

	static func create(obj_id: String, obj_type: int, pos: Vector3, desc: String) -> SOGObjective:
		var obj := SOGObjective.new()
		obj.id = obj_id
		obj.objective_type = obj_type
		obj.position = pos
		obj.description = desc
		return obj

	static func create_recon(obj_id: String, pos: Vector3, desc: String) -> SOGObjective:
		var obj := create(obj_id, GameEnums.SOGMissionType.RECON, pos, desc)
		obj.intel_required = 1  # Need 1 photo
		return obj

	static func create_trail_watch(obj_id: String, pos: Vector3, duration: float) -> SOGObjective:
		var obj := create(obj_id, GameEnums.SOGMissionType.TRAIL_WATCH, pos,
			"Observe trail for enemy movement")
		obj.time_limit = duration
		return obj

	static func create_prisoner_snatch(obj_id: String, target: Node3D) -> SOGObjective:
		var obj := create(obj_id, GameEnums.SOGMissionType.PRISONER_SNATCH,
			target.global_position if target else Vector3.ZERO,
			"Capture high-value target")
		obj.target_node = target
		return obj

	static func create_wire_tap(obj_id: String, pos: Vector3) -> SOGObjective:
		var obj := create(obj_id, GameEnums.SOGMissionType.WIRE_TAP, pos,
			"Place wire tap on enemy communications")
		return obj

	static func create_bda(obj_id: String, pos: Vector3) -> SOGObjective:
		var obj := create(obj_id, GameEnums.SOGMissionType.BDA, pos,
			"Assess bomb damage at target area")
		obj.intel_required = 3  # Need multiple photos
		return obj

	static func create_direct_action(obj_id: String, target: Node3D, desc: String) -> SOGObjective:
		var obj := create(obj_id, GameEnums.SOGMissionType.DIRECT_ACTION,
			target.global_position if target else Vector3.ZERO, desc)
		obj.target_node = target
		return obj

# =============================================================================
# FACTORY METHODS
# =============================================================================

static func create_recon_team(pos: Vector3, name: String = "") -> SOGTeam:
	## Factory method to create a new SOG recon team
	var team := SOGTeam.new()

	if name.is_empty():
		# Generate random team name (RT = Recon Team)
		var names: Array[String] = ["Python", "Viper", "Cobra", "Asp", "Mamba", "Adder",
					  "Idaho", "Iowa", "Ohio", "Texas", "Maine", "Vermont"]
		team.team_name = "RT " + names[randi() % names.size()]

	team.global_position = pos
	return team

static func create_hatchet_force(pos: Vector3, name: String = "") -> SOGTeam:
	## Factory method for larger Hatchet Force (30-40 men)
	## Used for direct action, company-sized operations
	var team := create_recon_team(pos, name)
	team.team_name = team.team_name.replace("RT", "HF")
	team.american_count = 4
	team.indig_count = 30
	team.team_size = 34
	team.ammo = 800
	team.grenades = 40
	team.claymores = 8
	return team

# =============================================================================
# DEBUG
# =============================================================================

func _get_debug_info() -> String:
	var info := team_name + "\n"
	info += "State: " + str(current_state) + "\n"
	info += "Stealth: " + str(int(stealth_rating * 100)) + "%\n"
	info += "Team: " + str(team_size) + "/" + str(TEAM_SIZE) + "\n"
	info += "Morale: " + str(int(morale)) + "%\n"
	info += "Ammo: " + str(ammo) + "\n"
	if is_compromised:
		info += "*** COMPROMISED ***\n"
	if extraction_pending:
		info += "Extract ETA: " + str(int(extraction_eta)) + "s\n"
	return info
