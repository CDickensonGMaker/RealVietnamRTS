class_name Bulldozer extends CharacterBody3D
## Bulldozer - D7 Caterpillar terrain clearing vehicle.
## Essential for Pillar 1 (Carve the Map) - clears jungle to make room for firebases.
##
## Three clearing modes:
##   - CLEAR_ZONE: Clear a designated construction zone
##   - CLEAR_PATH: Cut a road/path between two points
##   - FLATTEN: Prepare terrain for firebase foundation
##
## Works with TerrainClearingSystem autoload to update terrain state:
##   JUNGLE -> PARTIALLY_CLEARED -> CLEARED -> FORTIFIED
##
## Slow but heavily armored for a utility vehicle. Vulnerable to sappers and RPGs.

const VehicleComponentScript = preload("res://battle_system/units/vehicle_component.gd")
const SquadDataScript = preload("res://battle_system/data/squad_data.gd")
const BULLDOZER_MODEL_PATH: String = "res://assets/models/vehicles/us_bulldozer.glb"

signal clearing_progress(zone_id: int, progress: float)
signal clearing_completed(zone_id: int)
signal path_segment_cleared(segment_index: int)
signal bulldozer_destroyed(dozer: Bulldozer)
signal blade_lowered
signal blade_raised
signal terrain_updated(position: Vector3, new_state: int)
signal path_blocked_by_slope(position: Vector3, slope: float)
signal stuck(reason: String)

enum State { IDLE, MOVING, CLEARING, FLATTENING, PATH_CUTTING, DISABLED, DESTROYED }
enum ClearingMode { NONE, CLEAR_ZONE, CLEAR_PATH, FLATTEN }

@export var data: Resource  # SquadData
@export var faction: int = 0  # GameEnums.Faction
@export var use_placeholder_visual: bool = false  # Set true to use box placeholder

## Movement
@export var max_speed: float = 6.0  # m/s (~22 km/h) - slow but steady
@export var turn_rate_deg: float = 40.0  # Treaded vehicle, slow turns
@export var reverse_speed_mult: float = 0.4

## Clearing capabilities
@export var clearing_rate: float = 0.05  # Progress per second (20 seconds per zone)
@export var clearing_radius: float = 8.0  # Effective clearing radius in meters
@export var path_width: float = 6.0  # Width of cleared path

## State
var state: State = State.IDLE
var current_health: float = 150.0
var max_health: float = 150.0
var is_player_controlled: bool = true

## Clearing
var clearing_mode: ClearingMode = ClearingMode.NONE
var current_zone_id: int = -1
var clearing_target: Vector3 = Vector3.ZERO
var clearing_progress_value: float = 0.0
var _blade_down: bool = false

## Path cutting
var path_waypoints: Array[Vector3] = []
var path_segment_index: int = 0

## Movement
var move_target: Vector3 = Vector3.ZERO
var has_move_order: bool = false

## Component system
var vehicle_components: VehicleComponentScript = null

## Slope cache
const SLOPE_QUERY_INTERVAL: float = 0.1
var _slope_query_timer: float = 0.0
var _cached_slope: float = 0.0

## Stuck detection
var _last_position: Vector3 = Vector3.ZERO
var _stuck_timer: float = 0.0
const STUCK_THRESHOLD: float = 8.0
const STUCK_DISTANCE: float = 0.5

## Visual
var _hull: Node3D = null
var _blade: Node3D = null
var _tracks: Array[MeshInstance3D] = []
var _model_root: Node3D = null


func _ready() -> void:
	add_to_group("bulldozers")
	add_to_group("vehicles")
	add_to_group("all_units")

	if GameEnums.is_us_faction(faction):
		add_to_group("player_units")
		add_to_group("selectable_units")
	else:
		add_to_group("enemy_units")

	_setup_components()
	_apply_data()

	if use_placeholder_visual:
		_build_placeholder_visual()
	else:
		_load_bulldozer_model()


func _setup_components() -> void:
	vehicle_components = VehicleComponentScript.new()
	# Bulldozers are heavily built - more HP than trucks
	vehicle_components.setup_truck_components()
	# Override hull HP for bulldozer durability
	if vehicle_components.components.has(VehicleComponentScript.ComponentType.HULL):
		vehicle_components.components[VehicleComponentScript.ComponentType.HULL].max_hp = 200.0
		vehicle_components.components[VehicleComponentScript.ComponentType.HULL].current_hp = 200.0

	vehicle_components.setup_truck_crew(1.0)

	vehicle_components.component_damaged.connect(_on_component_damaged)
	vehicle_components.component_destroyed.connect(_on_component_destroyed)


func _apply_data() -> void:
	if data:
		max_health = data.get_total_health()
		current_health = max_health
	else:
		max_health = 150.0
		current_health = 150.0


func _load_bulldozer_model() -> void:
	# Load the D7 Caterpillar GLB model
	var model_scene: PackedScene = load(BULLDOZER_MODEL_PATH) as PackedScene
	if not model_scene:
		push_warning("Bulldozer: Could not load model, falling back to placeholder")
		_build_placeholder_visual()
		return

	_model_root = model_scene.instantiate() as Node3D
	if not _model_root:
		push_warning("Bulldozer: Failed to instantiate model, falling back to placeholder")
		_build_placeholder_visual()
		return

	_model_root.name = "D7_Model"
	add_child(_model_root)

	# Find blade node for animation (may be named "blade", "Blade", "dozer_blade", etc.)
	_blade = _find_node_by_pattern(_model_root, ["blade", "Blade", "BLADE", "dozer"])
	if _blade:
		# Store original blade position for raise/lower animation
		_blade.set_meta("original_y", _blade.position.y)

	# Setup collision
	_setup_collision()


func _find_node_by_pattern(root: Node, patterns: Array) -> Node3D:
	for pattern in patterns:
		var found := _find_node_recursive(root, pattern)
		if found:
			return found
	return null


func _find_node_recursive(node: Node, pattern: String) -> Node3D:
	if pattern.to_lower() in node.name.to_lower():
		if node is Node3D:
			return node as Node3D
	for child in node.get_children():
		var found := _find_node_recursive(child, pattern)
		if found:
			return found
	return null


func _setup_collision() -> void:
	# Create collision shape sized for bulldozer
	var coll := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.2, 2.0, 4.5)
	coll.shape = box
	coll.position.y = 1.0
	add_child(coll)

	collision_layer = 2 if GameEnums.is_us_faction(faction) else 4


func _build_placeholder_visual() -> void:
	# Hull - low, wide tractor body
	_hull = Node3D.new()
	_hull.name = "Hull"
	add_child(_hull)

	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(3.0, 1.2, 4.0)
	body.mesh = body_mesh
	body.position.y = 0.8

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.65, 0.2)  # Caterpillar yellow
	body.material_override = mat
	_hull.add_child(body)

	# Cab
	var cab := MeshInstance3D.new()
	var cab_mesh := BoxMesh.new()
	cab_mesh.size = Vector3(1.8, 1.2, 1.5)
	cab.mesh = cab_mesh
	cab.position = Vector3(0, 1.6, -0.8)
	cab.material_override = mat
	_hull.add_child(cab)

	# Engine cowl
	var cowl := MeshInstance3D.new()
	var cowl_mesh := BoxMesh.new()
	cowl_mesh.size = Vector3(2.4, 0.8, 2.0)
	cowl.mesh = cowl_mesh
	cowl.position = Vector3(0, 1.4, 0.8)
	cowl.material_override = mat
	_hull.add_child(cowl)

	# Exhaust stack
	var exhaust := MeshInstance3D.new()
	var exhaust_mesh := CylinderMesh.new()
	exhaust_mesh.top_radius = 0.1
	exhaust_mesh.bottom_radius = 0.12
	exhaust_mesh.height = 1.5
	exhaust.mesh = exhaust_mesh
	exhaust.position = Vector3(-0.8, 2.2, 0.5)
	var exhaust_mat := StandardMaterial3D.new()
	exhaust_mat.albedo_color = Color(0.2, 0.2, 0.2)
	exhaust.material_override = exhaust_mat
	_hull.add_child(exhaust)

	# Tracks
	var track_mat := StandardMaterial3D.new()
	track_mat.albedo_color = Color(0.15, 0.15, 0.15)

	for side in [-1, 1]:
		var track := MeshInstance3D.new()
		var track_mesh := BoxMesh.new()
		track_mesh.size = Vector3(0.6, 0.8, 4.2)
		track.mesh = track_mesh
		track.position = Vector3(1.5 * side, 0.4, 0)
		track.material_override = track_mat
		_hull.add_child(track)
		_tracks.append(track)

	# Blade - the business end
	_blade = Node3D.new()
	_blade.name = "Blade"
	_blade.position = Vector3(0, 0.6, 2.2)
	add_child(_blade)

	var blade_mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.8, 1.2, 0.3)
	blade_mesh.mesh = bm

	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.3, 0.3, 0.3)  # Steel blade
	blade_mesh.material_override = blade_mat
	_blade.add_child(blade_mesh)

	# Blade push frame (C-frame)
	for side in [-1, 1]:
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.15, 0.8, 1.0)
		arm.mesh = arm_mesh
		arm.position = Vector3(1.5 * side, 0.2, -0.5)
		arm.material_override = blade_mat
		_blade.add_child(arm)

	# Collision
	_setup_collision()


func _physics_process(delta: float) -> void:
	if state == State.DESTROYED:
		return

	match state:
		State.CLEARING:
			_process_clearing(delta)
		State.FLATTENING:
			_process_flattening(delta)
		State.PATH_CUTTING:
			_process_path_cutting(delta)
		State.MOVING:
			_process_movement(delta)
			_check_stuck(delta)
		State.DISABLED:
			pass
		_:
			pass

	_snap_to_terrain()


func _process_clearing(delta: float) -> void:
	# Move toward clearing target if not in range
	var dist: float = global_position.distance_to(clearing_target)
	if dist > clearing_radius:
		_move_toward(clearing_target, delta)
		return

	# In range - clear terrain
	clearing_progress_value += clearing_rate * delta
	clearing_progress.emit(current_zone_id, clearing_progress_value)

	# Update terrain via TerrainClearingSystem
	if TerrainClearingSystem:
		TerrainClearingSystem.apply_clearing_damage(global_position, clearing_radius, clearing_rate * delta * 2.0)

	# Check completion
	if clearing_progress_value >= 1.0:
		_complete_clearing()


func _process_flattening(delta: float) -> void:
	# Similar to clearing but for preparing foundations
	var dist: float = global_position.distance_to(clearing_target)
	if dist > clearing_radius:
		_move_toward(clearing_target, delta)
		return

	clearing_progress_value += clearing_rate * delta * 1.5  # Flattening is faster than clearing
	clearing_progress.emit(current_zone_id, clearing_progress_value)

	# Update terrain state to FORTIFIED when done
	if clearing_progress_value >= 1.0:
		if TerrainClearingSystem and TerrainClearingSystem.has_method("set_terrain_state"):
			TerrainClearingSystem.set_terrain_state(clearing_target, GameEnums.ClearingState.FORTIFIED)
		terrain_updated.emit(clearing_target, GameEnums.ClearingState.FORTIFIED)
		_complete_clearing()


func _process_path_cutting(delta: float) -> void:
	if path_waypoints.is_empty() or path_segment_index >= path_waypoints.size():
		_complete_path_cutting()
		return

	var target: Vector3 = path_waypoints[path_segment_index]
	var dist: float = global_position.distance_to(target)

	# Clear while moving along path
	if TerrainClearingSystem:
		TerrainClearingSystem.apply_clearing_damage(global_position, path_width * 0.5, clearing_rate * delta * 3.0)

	if dist < 2.0:
		path_segment_cleared.emit(path_segment_index)
		path_segment_index += 1
		return

	_move_toward(target, delta)


func _process_movement(delta: float) -> void:
	var direction: Vector3 = move_target - global_position
	direction.y = 0
	var dist: float = direction.length()

	if dist < 2.0:
		has_move_order = false
		velocity = Vector3.ZERO
		state = State.IDLE
		return

	_move_toward(move_target, delta)


func _move_toward(target: Vector3, delta: float) -> void:
	var direction: Vector3 = target - global_position
	direction.y = 0
	var seek_direction: Vector3 = direction.normalized()

	# Slope check
	_slope_query_timer -= delta
	if _slope_query_timer <= 0.0:
		_slope_query_timer = SLOPE_QUERY_INTERVAL
		_cached_slope = _sample_slope_ahead(seek_direction)

	# Bulldozers can handle steeper terrain than most vehicles
	var max_slope: float = data.max_slope if data else 0.5
	var speed: float = max_speed

	if _cached_slope > max_slope:
		velocity = Vector3.ZERO
		path_blocked_by_slope.emit(global_position, _cached_slope)
		return

	# Apply slope penalty
	var slope_penalty: float = data.slope_speed_penalty if data else 0.6
	speed *= 1.0 - (_cached_slope / max_slope) * (1.0 - slope_penalty)

	# Apply movement efficiency from components
	var move_eff: float = vehicle_components.get_movement_efficiency() if vehicle_components else 1.0
	speed *= move_eff

	# Rotate toward target
	var target_yaw: float = atan2(seek_direction.x, seek_direction.z)
	var current_yaw: float = rotation.y
	var yaw_diff: float = angle_difference(current_yaw, target_yaw)
	var max_step: float = deg_to_rad(turn_rate_deg) * delta
	rotation.y = current_yaw + clampf(yaw_diff, -max_step, max_step)

	# Move forward when aligned
	var alignment: float = maxf(0.0, cos(yaw_diff))
	speed *= alignment

	var forward: Vector3 = Vector3(sin(rotation.y), 0, cos(rotation.y))
	velocity = forward * speed
	move_and_slide()
	state = State.MOVING


func _check_stuck(delta: float) -> void:
	var distance_moved: float = global_position.distance_to(_last_position)
	if distance_moved < STUCK_DISTANCE:
		_stuck_timer += delta
		if _stuck_timer > STUCK_THRESHOLD:
			stuck.emit("Cannot reach destination")
			_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0
		_last_position = global_position


func _complete_clearing() -> void:
	clearing_completed.emit(current_zone_id)

	if BattleSignals:
		BattleSignals.terrain_cleared.emit(clearing_target, current_zone_id)

	# Reset state
	clearing_mode = ClearingMode.NONE
	current_zone_id = -1
	clearing_progress_value = 0.0
	state = State.IDLE
	_raise_blade()


func _complete_path_cutting() -> void:
	clearing_mode = ClearingMode.NONE
	path_waypoints.clear()
	path_segment_index = 0
	state = State.IDLE
	_raise_blade()


func _lower_blade() -> void:
	if _blade_down:
		return
	_blade_down = true
	blade_lowered.emit()

	if _blade:
		# For model: lower from original position
		# For placeholder: lower to 0.2
		var target_y: float = 0.2
		if _blade.has_meta("original_y"):
			target_y = _blade.get_meta("original_y") - 0.4
		var tween: Tween = create_tween()
		tween.tween_property(_blade, "position:y", target_y, 0.5)


func _raise_blade() -> void:
	if not _blade_down:
		return
	_blade_down = false
	blade_raised.emit()

	if _blade:
		# For model: return to original position
		# For placeholder: raise to 0.6
		var target_y: float = 0.6
		if _blade.has_meta("original_y"):
			target_y = _blade.get_meta("original_y")
		var tween: Tween = create_tween()
		tween.tween_property(_blade, "position:y", target_y, 0.5)


func _sample_slope_ahead(move_dir: Vector3) -> float:
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if not terrain:
		return 0.0
	var probe_pos: Vector3 = global_position + move_dir * 3.0
	if terrain.has_method("get_normal_at"):
		var normal: Vector3 = terrain.get_normal_at(probe_pos)
		return clampf(1.0 - normal.y, 0.0, 1.0)
	if terrain.has_method("get_height_at"):
		var h0: float = terrain.get_height_at(global_position)
		var h1: float = terrain.get_height_at(probe_pos)
		var rise: float = absf(h1 - h0)
		return clampf(atan2(rise, 3.0) / (PI * 0.5), 0.0, 1.0)
	return 0.0


func _snap_to_terrain() -> void:
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		global_position.y = terrain.get_height_at(global_position)


func _on_component_damaged(component_type: int, current_hp: float, max_hp: float) -> void:
	if component_type == VehicleComponentScript.ComponentType.HULL:
		current_health = current_hp


func _on_component_destroyed(component_type: int) -> void:
	if component_type == VehicleComponentScript.ComponentType.ENGINE:
		state = State.DISABLED
		stuck.emit("Engine destroyed")

	if vehicle_components.is_vehicle_destroyed():
		_destroy()


# =============================================================================
# PUBLIC API
# =============================================================================

## Returns true if bulldozer is destroyed
func is_dead() -> bool:
	return state == State.DESTROYED or current_health <= 0.0


## Clear a construction zone
func clear_zone(zone_id: int, zone_center: Vector3) -> void:
	current_zone_id = zone_id
	clearing_target = zone_center
	clearing_progress_value = 0.0
	clearing_mode = ClearingMode.CLEAR_ZONE
	state = State.CLEARING
	_lower_blade()


## Flatten terrain for firebase foundation
func flatten_zone(zone_id: int, zone_center: Vector3) -> void:
	current_zone_id = zone_id
	clearing_target = zone_center
	clearing_progress_value = 0.0
	clearing_mode = ClearingMode.FLATTEN
	state = State.FLATTENING
	_lower_blade()


## Cut a path/road between waypoints
func cut_path(waypoints: Array[Vector3]) -> void:
	if waypoints.size() < 2:
		return
	path_waypoints = waypoints
	path_segment_index = 0
	clearing_mode = ClearingMode.CLEAR_PATH
	state = State.PATH_CUTTING
	_lower_blade()


## Simple move order
func move_to(target: Vector3) -> void:
	if state == State.CLEARING or state == State.FLATTENING or state == State.PATH_CUTTING:
		# Abort current job
		clearing_mode = ClearingMode.NONE
		_raise_blade()

	move_target = target
	has_move_order = true
	state = State.MOVING


## Attack-move: for bulldozers, just move (they don't have weapons)
func attack_move_to(target: Vector3) -> void:
	move_to(target)


## Stop current operation
func stop() -> void:
	has_move_order = false
	clearing_mode = ClearingMode.NONE
	path_waypoints.clear()
	state = State.IDLE
	_raise_blade()


func take_damage(amount: float, source: Node = null) -> void:
	if state == State.DESTROYED:
		return

	if vehicle_components:
		var hit_angle: float = 0.0
		if source and is_instance_valid(source):
			var to_source: Vector3 = source.global_position - global_position
			to_source.y = 0.0
			if to_source.length() > 0.1:
				hit_angle = atan2(to_source.x, to_source.z) - rotation.y

		vehicle_components.take_directional_damage(amount, hit_angle, VehicleComponentScript.AmmoType.HE)
	else:
		# Fallback damage
		var armor_val: float = data.armor if data else 20.0
		var reduction: float = clampf(armor_val * 0.02, 0.0, 0.5)
		current_health = maxf(0.0, current_health - amount * (1.0 - reduction))
		if current_health <= 0.0:
			_destroy()


func _destroy() -> void:
	state = State.DESTROYED
	bulldozer_destroyed.emit(self)

	# Visual destruction
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.15, 0.1)
	for child in get_children():
		if child is MeshInstance3D:
			child.material_override = mat
		elif child is Node3D:
			for subchild in child.get_children():
				if subchild is MeshInstance3D:
					subchild.material_override = mat

	var t := get_tree().create_timer(30.0)  # Wrecks persist longer
	t.timeout.connect(queue_free)


func get_clearing_progress() -> float:
	return clearing_progress_value


func is_clearing() -> bool:
	return state in [State.CLEARING, State.FLATTENING, State.PATH_CUTTING]


func is_available() -> bool:
	return state == State.IDLE


func get_state_name() -> String:
	return State.keys()[state]


func get_status() -> Dictionary:
	return {
		"state": get_state_name(),
		"clearing_mode": ClearingMode.keys()[clearing_mode],
		"progress": clearing_progress_value,
		"zone_id": current_zone_id,
		"blade_down": _blade_down,
		"health_percent": current_health / max_health * 100.0,
	}
