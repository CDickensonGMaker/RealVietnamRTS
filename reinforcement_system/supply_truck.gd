class_name SupplyTruck extends CharacterBody3D
## Supply Truck - M35 "Deuce and a half" dedicated logistics vehicle.
## Runs between supply depots and firebases on scheduled routes.
## Uses actual M35 model with animated wheels driven by vehicle speed.
##
## Serves Pillar 3 (Physical Supply Chains) - This IS the supply chain.
## A firebase only survives as long as trucks keep rolling.

const VehicleComponentScript = preload("res://battle_system/units/vehicle_component.gd")
const M35_MODEL_PATH: String = "res://assets/models/vehicles/m35_deuce_truck.glb"

signal supply_delivered(truck: SupplyTruck, destination: Node3D, amount: float)
signal supply_picked_up(truck: SupplyTruck, source: Node3D, amount: float)
signal route_completed(truck: SupplyTruck)
signal truck_destroyed(truck: SupplyTruck, cargo_lost: float)
signal ambushed(truck: SupplyTruck, position: Vector3)
signal arrived_at_waypoint(truck: SupplyTruck, waypoint_index: int)
signal stuck(truck: SupplyTruck, reason: String)

enum State { IDLE, EN_ROUTE_TO_DEPOT, LOADING, EN_ROUTE_TO_FIREBASE, UNLOADING, RETURNING, DISABLED, DESTROYED }
enum SupplyType { GENERAL, AMMUNITION, FUEL, MEDICAL, CONSTRUCTION }

@export var faction: int = 0  # GameEnums.Faction
@export var use_placeholder_visual: bool = false  # Set true to use box placeholder

## Movement
@export var max_speed: float = 12.0  # m/s (~43 km/h) on roads
@export var off_road_speed_mult: float = 0.5
@export var turn_rate_deg: float = 80.0

## Capacity
@export var supply_capacity: float = 2000.0

## State
var state: State = State.IDLE
var current_health: float = 80.0
var max_health: float = 80.0

## Supply cargo
var current_supply: float = 0.0
var supply_type: int = SupplyType.GENERAL

## Route
var route: Array[Vector3] = []
var current_waypoint_index: int = 0
var origin: Node3D = null  # Supply depot
var destination: Node3D = null  # Firebase

## Spline-based navigation (smooth terrain-following curves)
var _current_spline: RefCounted = null  # TerrainSpline for smooth navigation
var _distance_along_spline: float = 0.0
var _spline_total_length: float = 0.0

## Component system
var vehicle_components: VehicleComponentScript = null

## Timers
const LOAD_TIME: float = 5.0
const UNLOAD_TIME: float = 5.0
var _operation_timer: float = 0.0

## Stuck detection
var _last_position: Vector3 = Vector3.ZERO
var _stuck_timer: float = 0.0
const STUCK_THRESHOLD: float = 5.0
const STUCK_DISTANCE: float = 1.0

## Model and wheel animation
var _model_root: Node3D = null
var _wheel_rotation: float = 0.0
const WHEEL_RADIUS: float = 0.5  # Meters - used to calculate rotation from distance


func _ready() -> void:
	add_to_group("supply_trucks")
	add_to_group("trucks")
	add_to_group("vehicles")
	add_to_group("all_units")

	# Supply trucks are always player-controlled (logistics)
	if GameEnums.is_us_faction(faction):
		add_to_group("player_units")
	else:
		add_to_group("enemy_units")

	_setup_components()

	if use_placeholder_visual:
		_build_placeholder_visual()
	else:
		_load_m35_model()


func _setup_components() -> void:
	vehicle_components = VehicleComponentScript.new()
	vehicle_components.setup_truck_components()
	vehicle_components.setup_truck_crew(1.0)

	vehicle_components.component_damaged.connect(_on_component_damaged)
	vehicle_components.component_destroyed.connect(_on_component_destroyed)


func _build_placeholder_visual() -> void:
	# Simplified truck visual for supply runs (fallback if model not available)
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(2.2, 1.5, 5.5)
	body.mesh = body_mesh
	body.position.y = 1.0

	var mat := StandardMaterial3D.new()
	match faction:
		GameEnums.Faction.US_ARMY, GameEnums.Faction.ARVN:
			mat.albedo_color = Color(0.35, 0.4, 0.25)  # OD green
		GameEnums.Faction.VC, GameEnums.Faction.NVA:
			mat.albedo_color = Color(0.4, 0.35, 0.25)  # Khaki
		_:
			mat.albedo_color = Color(0.4, 0.4, 0.4)

	body.material_override = mat
	add_child(body)

	# Supply icon on top (box)
	var cargo_marker := MeshInstance3D.new()
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(1.5, 0.8, 2.5)
	cargo_marker.mesh = marker_mesh
	cargo_marker.position = Vector3(0, 2.0, -0.5)

	var cargo_mat := StandardMaterial3D.new()
	cargo_mat.albedo_color = Color(0.5, 0.45, 0.3)
	cargo_marker.material_override = cargo_mat
	add_child(cargo_marker)

	_setup_collision()


func _load_m35_model() -> void:
	# Load the M35 Deuce and a Half GLB model
	var model_scene: PackedScene = load(M35_MODEL_PATH) as PackedScene
	if not model_scene:
		push_warning("SupplyTruck: Could not load M35 model, falling back to placeholder")
		_build_placeholder_visual()
		return

	_model_root = model_scene.instantiate() as Node3D
	if not _model_root:
		push_warning("SupplyTruck: Failed to instantiate M35 model, falling back to placeholder")
		_build_placeholder_visual()
		return

	_model_root.name = "M35_Model"
	add_child(_model_root)

	# Model may need rotation adjustment depending on export orientation
	# GLB typically exports with -Z forward, Godot uses +Z forward
	# Adjust if needed after testing

	_setup_collision()

	# Initialize wheel rotation
	_wheel_rotation = 0.0
	_update_wheel_animation(0.0)


func _setup_collision() -> void:
	# Create collision shape sized for M35 truck
	# M35 dimensions approximately: 7.4m long, 2.5m wide, 2.9m tall
	var coll := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.5, 2.5, 7.0)
	coll.shape = box
	coll.position = Vector3(0, 1.25, 0)
	add_child(coll)

	# Set collision layer based on faction
	if GameEnums.is_us_faction(faction):
		collision_layer = 2
	else:
		collision_layer = 4


func _update_wheel_animation(delta: float) -> void:
	# Update wheel rotation based on vehicle speed
	# The GLB has a "wheel_rotation" custom property on the root empty
	# that drives all 10 wheels when animated

	if not _model_root:
		return

	# Calculate rotation increment based on current speed
	var current_speed: float = velocity.length()
	if current_speed > 0.1:
		# Convert linear speed to angular rotation
		# rotation (radians) = distance / wheel_radius
		var distance_this_frame: float = current_speed * delta
		var rotation_increment: float = distance_this_frame / WHEEL_RADIUS
		_wheel_rotation += rotation_increment

		# Keep wheel_rotation in reasonable bounds (wrap around)
		if _wheel_rotation > TAU * 100.0:
			_wheel_rotation = fmod(_wheel_rotation, TAU)

	# Apply the wheel_rotation to the model
	# The GLB model uses a custom property "wheel_rotation" on the root node
	# that drives all wheel rotations via animation or driver constraints
	if _model_root.has_method("set"):
		_model_root.set("wheel_rotation", _wheel_rotation)

	# Alternative: If the model has an AnimationPlayer with wheel animation
	var anim_player := _model_root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim_player and anim_player.has_animation("wheel_spin"):
		# Seek to position based on wheel_rotation
		var anim_length: float = anim_player.get_animation("wheel_spin").length
		var seek_pos: float = fmod(_wheel_rotation / TAU, 1.0) * anim_length
		anim_player.seek(seek_pos, true)

	# If model uses direct wheel node references, rotate them manually
	_rotate_wheel_nodes()


func _physics_process(delta: float) -> void:
	if state == State.DESTROYED or state == State.DISABLED:
		return

	match state:
		State.LOADING:
			_process_loading(delta)
		State.UNLOADING:
			_process_unloading(delta)
		State.EN_ROUTE_TO_DEPOT, State.EN_ROUTE_TO_FIREBASE, State.RETURNING:
			_process_movement(delta)
			_check_stuck(delta)

	_snap_to_terrain()

	# Update wheel animation based on movement
	if _model_root:
		_update_wheel_animation(delta)


func _process_loading(delta: float) -> void:
	_operation_timer -= delta
	if _operation_timer <= 0.0:
		# Load supplies from depot
		if origin and origin.has_method("withdraw_supply"):
			var to_load: float = minf(supply_capacity - current_supply, supply_capacity)
			var loaded: float = origin.withdraw_supply(to_load)
			current_supply += loaded
			supply_picked_up.emit(self, origin, loaded)

		_start_delivery()


func _process_unloading(delta: float) -> void:
	_operation_timer -= delta
	if _operation_timer <= 0.0:
		# Deliver supplies to firebase
		if destination and destination.has_method("add_supply"):
			destination.add_supply(current_supply)
			supply_delivered.emit(self, destination, current_supply)

			if BattleSignals:
				BattleSignals.supply_delivered.emit(destination, current_supply)

		current_supply = 0.0
		_start_return()


func _process_movement(delta: float) -> void:
	# Use spline navigation if spline is available
	if _current_spline:
		_process_spline_movement(delta)
		return

	if route.is_empty() or current_waypoint_index >= route.size():
		_on_route_segment_complete()
		return

	var target: Vector3 = route[current_waypoint_index]
	var direction: Vector3 = target - global_position
	direction.y = 0
	var distance: float = direction.length()

	if distance < 3.0:
		current_waypoint_index += 1
		arrived_at_waypoint.emit(self, current_waypoint_index - 1)

		if current_waypoint_index >= route.size():
			_on_route_segment_complete()
		return

	var seek_direction: Vector3 = direction.normalized()

	# Get speed (check if on road for bonus)
	var speed: float = max_speed
	var move_eff: float = vehicle_components.get_movement_efficiency() if vehicle_components else 1.0
	speed *= move_eff

	# Check road network for speed multiplier (accounts for road state: damaged/cratered)
	var road_network := get_node_or_null("/root/RoadNetwork")
	if road_network and road_network.has_method("is_on_road"):
		if road_network.is_on_road(global_position):
			var road_mult: float = road_network.get_speed_multiplier_at(global_position)
			speed *= road_mult
		else:
			# Off road - check terrain type
			var terrain := get_node_or_null("/root/TerrainIntegration")
			if terrain and terrain.has_method("get_terrain_type_at"):
				var terrain_type: int = terrain.get_terrain_type_at(global_position)
				if terrain_type == GameEnums.TerrainType.ROAD:
					speed *= 1.25  # Road terrain without RoadNetwork segment
				elif terrain_type != GameEnums.TerrainType.CLEARED and terrain_type != GameEnums.TerrainType.CLEARED_FIREBASE:
					speed *= off_road_speed_mult
	else:
		# Fallback: check terrain for road bonus
		var terrain := get_node_or_null("/root/TerrainIntegration")
		if terrain and terrain.has_method("get_terrain_type_at"):
			var terrain_type: int = terrain.get_terrain_type_at(global_position)
			if terrain_type == GameEnums.TerrainType.ROAD:
				speed *= 1.25  # Road speed bonus
			elif terrain_type != GameEnums.TerrainType.CLEARED and terrain_type != GameEnums.TerrainType.CLEARED_FIREBASE:
				speed *= off_road_speed_mult

	# Rotate toward target
	var target_yaw: float = atan2(seek_direction.x, seek_direction.z)
	var current_yaw: float = rotation.y
	var yaw_diff: float = angle_difference(current_yaw, target_yaw)
	var max_step: float = deg_to_rad(turn_rate_deg) * delta
	rotation.y = current_yaw + clampf(yaw_diff, -max_step, max_step)

	# Only move forward when aligned
	var alignment: float = maxf(0.0, cos(yaw_diff))
	speed *= alignment

	var forward: Vector3 = Vector3(sin(rotation.y), 0, cos(rotation.y))
	velocity = forward * speed
	move_and_slide()


func _process_spline_movement(delta: float) -> void:
	"""Navigate along a TerrainSpline for smooth terrain-following movement."""
	if not _current_spline or not _current_spline.has_method("get_position_at_distance"):
		_current_spline = null  # Invalid spline, fall back to waypoint nav
		return

	# Check if reached end of spline
	if _distance_along_spline >= _spline_total_length:
		_current_spline = null
		_on_route_segment_complete()
		return

	# Calculate speed
	var speed: float = max_speed
	var move_eff: float = vehicle_components.get_movement_efficiency() if vehicle_components else 1.0
	speed *= move_eff

	# Check road network for speed multiplier
	var road_network := get_node_or_null("/root/RoadNetwork")
	if road_network and road_network.has_method("get_speed_multiplier_at"):
		var road_mult: float = road_network.get_speed_multiplier_at(global_position)
		speed *= road_mult

	# Advance along spline
	_distance_along_spline += speed * delta

	# Get new position and tangent from spline
	var new_pos: Vector3 = _current_spline.get_position_at_distance(_distance_along_spline)
	var tangent: Vector3 = _current_spline.get_tangent_at_distance(_distance_along_spline)

	# Smoothly interpolate position for physics
	var prev_pos: Vector3 = global_position
	global_position = new_pos

	# Calculate velocity for physics and wheel animation
	velocity = (global_position - prev_pos) / maxf(delta, 0.001)

	# Rotate to face tangent direction (smooth turning)
	if tangent.length_squared() > 0.001:
		var target_yaw: float = atan2(tangent.x, tangent.z)
		var max_step: float = deg_to_rad(turn_rate_deg) * delta
		var yaw_diff: float = angle_difference(rotation.y, target_yaw)
		rotation.y = rotation.y + clampf(yaw_diff, -max_step, max_step)

	move_and_slide()


func _check_stuck(delta: float) -> void:
	var distance_moved: float = global_position.distance_to(_last_position)
	if distance_moved < STUCK_DISTANCE:
		_stuck_timer += delta
		if _stuck_timer > STUCK_THRESHOLD:
			stuck.emit(self, "Cannot reach waypoint")
			_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0
		_last_position = global_position


func _on_route_segment_complete() -> void:
	match state:
		State.EN_ROUTE_TO_DEPOT:
			state = State.LOADING
			_operation_timer = LOAD_TIME
		State.EN_ROUTE_TO_FIREBASE:
			state = State.UNLOADING
			_operation_timer = UNLOAD_TIME
		State.RETURNING:
			route_completed.emit(self)
			state = State.IDLE


func _start_delivery() -> void:
	if not destination:
		state = State.IDLE
		return

	# Generate route to destination
	route = _generate_route(global_position, destination.global_position)
	current_waypoint_index = 0
	state = State.EN_ROUTE_TO_FIREBASE


func _start_return() -> void:
	if not origin:
		state = State.IDLE
		return

	route = _generate_route(global_position, origin.global_position)
	current_waypoint_index = 0
	state = State.RETURNING


func _generate_route(from: Vector3, to: Vector3) -> Array[Vector3]:
	# Simple waypoint generation - in full implementation, use pathfinding
	var result: Array[Vector3] = []

	# Check for road network
	var road_network := get_node_or_null("/root/RoadNetwork")
	if road_network and road_network.has_method("find_path"):
		result = road_network.find_path(from, to)
		if not result.is_empty():
			return result

	# Fallback: direct line with intermediate waypoints
	var segments: int = int(from.distance_to(to) / 50.0) + 1
	for i in range(1, segments + 1):
		var t: float = float(i) / float(segments)
		result.append(from.lerp(to, t))

	return result


func _rotate_wheel_nodes() -> void:
	# Directly rotate wheel nodes if they exist in the model hierarchy
	# The M35 has 10 wheels: 2 front + 4 dual rear on each side
	# Typical naming: wheel_front_left, wheel_front_right, wheel_rear_1_left, etc.

	if not _model_root:
		return

	# Common wheel node name patterns to search for
	var wheel_patterns: Array[String] = [
		"wheel", "Wheel", "WHEEL",
		"tire", "Tire", "TIRE"
	]

	# Find and rotate all wheel nodes
	_rotate_wheels_recursive(_model_root, _wheel_rotation)


func _rotate_wheels_recursive(node: Node, angle: float) -> void:
	# Check if this node is a wheel (by name)
	var node_name_lower: String = node.name.to_lower()
	if "wheel" in node_name_lower or "tire" in node_name_lower:
		if node is Node3D:
			var wheel_node: Node3D = node as Node3D
			# Wheels rotate around their local X axis (assuming standard orientation)
			wheel_node.rotation.x = angle

	# Recurse into children
	for child in node.get_children():
		_rotate_wheels_recursive(child, angle)


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
		stuck.emit(self, "Engine destroyed")

	if vehicle_components.is_vehicle_destroyed():
		_destroy()


# =============================================================================
# PUBLIC API
# =============================================================================

## Start a supply run from depot to firebase
func start_supply_run(depot: Node3D, firebase: Node3D, type: int = SupplyType.GENERAL) -> void:
	origin = depot
	destination = firebase
	supply_type = type

	# Route to depot first
	route = _generate_route(global_position, depot.global_position)
	current_waypoint_index = 0
	state = State.EN_ROUTE_TO_DEPOT

	# Emit signal for tracking
	if BattleSignals:
		BattleSignals.supply_truck_departed.emit(self, depot, firebase)


## Start a direct delivery (already loaded)
func start_delivery(firebase: Node3D, supplies: float, type: int = SupplyType.GENERAL) -> void:
	destination = firebase
	current_supply = supplies
	supply_type = type

	route = _generate_route(global_position, firebase.global_position)
	current_waypoint_index = 0
	state = State.EN_ROUTE_TO_FIREBASE


## Load supplies manually
func load_supplies(amount: float, type: int = SupplyType.GENERAL) -> float:
	var to_load: float = minf(amount, supply_capacity - current_supply)
	current_supply += to_load
	supply_type = type
	return to_load


## Set a spline route for smooth navigation
func set_spline_route(spline: RefCounted) -> void:
	"""Set a TerrainSpline for smooth terrain-following navigation.

	When a spline is set, the truck follows the curve instead of discrete waypoints.
	The spline should have get_position_at_distance() and get_tangent_at_distance() methods.
	"""
	_current_spline = spline
	_distance_along_spline = 0.0
	if spline and spline.has_method("get_total_length"):
		_spline_total_length = spline.get_total_length()
	else:
		_spline_total_length = 0.0


## Clear spline route (fall back to waypoint navigation)
func clear_spline_route() -> void:
	_current_spline = null
	_distance_along_spline = 0.0
	_spline_total_length = 0.0


## Cancel current mission and stop
func abort_mission() -> void:
	state = State.IDLE
	route.clear()
	current_waypoint_index = 0
	clear_spline_route()


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

		# Ammo cargo can explode
		if supply_type == SupplyType.AMMUNITION and randf() < amount / 150.0:
			_explode()
			return
	else:
		current_health = maxf(0.0, current_health - amount)
		if current_health <= 0.0:
			_destroy()

	# Report ambush
	if source:
		ambushed.emit(self, global_position)
		if BattleSignals:
			BattleSignals.supply_truck_ambushed.emit(self, global_position)
			BattleSignals.vc_ambush_triggered.emit(global_position, 1)


func _destroy() -> void:
	state = State.DESTROYED
	truck_destroyed.emit(self, current_supply)

	# Apply destroyed material to all mesh instances
	var destroyed_mat := StandardMaterial3D.new()
	destroyed_mat.albedo_color = Color(0.15, 0.12, 0.08)  # Charred/burnt look
	_apply_material_recursive(self, destroyed_mat)

	var t := get_tree().create_timer(15.0)
	t.timeout.connect(queue_free)


func _apply_material_recursive(node: Node, mat: Material) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_inst: MeshInstance3D = child as MeshInstance3D
			mesh_inst.material_override = mat
		_apply_material_recursive(child, mat)


func _explode() -> void:
	var explosion_radius: float = 12.0
	var explosion_damage: float = 150.0

	# Use SpatialHashGrid for efficient spatial query instead of O(n) group iteration
	var nearby: Array[Node3D] = SpatialHashGrid.get_units_in_radius(global_position, explosion_radius)
	for unit in nearby:
		if unit == self:
			continue
		if not is_instance_valid(unit):
			continue
		var dist: float = global_position.distance_to(unit.global_position)
		var falloff: float = 1.0 - (dist / explosion_radius)
		if unit.has_method("take_damage"):
			unit.take_damage(explosion_damage * falloff, self)

	_destroy()


func get_supply_amount() -> float:
	return current_supply


func get_supply_type() -> int:
	return supply_type


func get_state_name() -> String:
	return State.keys()[state]


func is_available() -> bool:
	return state == State.IDLE


func get_progress() -> float:
	# Spline-based progress
	if _current_spline and _spline_total_length > 0.0:
		return clampf(_distance_along_spline / _spline_total_length, 0.0, 1.0)
	# Waypoint-based progress
	if route.is_empty():
		return 0.0
	return float(current_waypoint_index) / float(route.size())


func get_status() -> Dictionary:
	return {
		"state": get_state_name(),
		"supply": current_supply,
		"supply_type": SupplyType.keys()[supply_type],
		"capacity": supply_capacity,
		"progress": get_progress(),
		"origin": origin.name if origin else "None",
		"destination": destination.name if destination else "None",
	}
