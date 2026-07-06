class_name TransportTruck extends CharacterBody3D
## Transport Truck - M35 "Deuce and a half" 2.5 ton cargo truck.
## Transports troops and supplies between firebases. Unarmored and vulnerable.
## Uses Men of War style component damage for realistic vehicle degradation.
## Now supports actual M35 GLB model with animated wheels.
##
## Serves Pillar 3 (Physical Supply Chains) - Trucks are THE supply chain.
## Cut the roads, destroy the trucks, and firebases starve.

const SquadDataScript = preload("res://battle_system/data/squad_data.gd")
const VehicleComponentScript = preload("res://battle_system/units/vehicle_component.gd")
const M35_MODEL_PATH: String = "res://assets/models/vehicles/m35_deuce_truck.glb"

signal cargo_loaded(truck: TransportTruck, cargo_type: int, amount: float)
signal cargo_unloaded(truck: TransportTruck, cargo_type: int, amount: float)
signal passengers_loaded(truck: TransportTruck, count: int)
signal passengers_unloaded(truck: TransportTruck, passengers: Array[Node3D])
signal truck_destroyed(truck: TransportTruck)
signal component_hit(component_type: int, damage: float)
signal path_blocked_by_slope(position: Vector3, slope: float)
signal ambush_detected(truck: TransportTruck, attacker: Node3D)

enum State { IDLE, MOVING, LOADING, UNLOADING, DISABLED, DESTROYED }
enum TruckVariant { M35_CARGO, M35_TROOP, M35_FUEL, M35_AMMO }
enum CargoType { SUPPLIES, AMMUNITION, FUEL, CONSTRUCTION, MEDICAL }

@export var data: Resource  # SquadData
@export var variant: TruckVariant = TruckVariant.M35_CARGO
@export var use_placeholder_visual: bool = false  # Set true to use box placeholder

## Movement characteristics
@export var turn_rate_deg: float = 90.0
@export var reverse_speed_mult: float = 0.4
@export var acceleration: float = 4.0

## Cargo capacity
@export var cargo_capacity: float = 2500.0  # kg
@export var passenger_capacity: int = 20  # M35 can carry ~20 troops

## State
var state: State = State.IDLE
var current_health: float = 100.0
var max_health: float = 100.0
var move_target: Vector3 = Vector3.ZERO
var has_move_order: bool = false
var is_player_controlled: bool = true

## Cargo
var cargo: Dictionary = {}  # CargoType -> amount
var current_cargo_weight: float = 0.0
var passengers: Array[Node3D] = []

## Component system
var vehicle_components: VehicleComponentScript = null

## Route following (for convoy system)
var waypoints: Array[Vector3] = []
var current_waypoint: int = 0
var is_following_route: bool = false

## Visuals
var _cab_node: Node3D = null
var _bed_node: Node3D = null
var _model_root: Node3D = null

## Wheel animation
var _wheel_rotation: float = 0.0
const WHEEL_RADIUS: float = 0.5  # Meters - for calculating rotation from distance

## Slope cache
const SLOPE_QUERY_INTERVAL: float = 0.1
var _slope_query_timer: float = 0.0
var _cached_slope: float = 0.0

## Loading timing
const LOAD_TIME_PER_UNIT: float = 0.5
var _load_timer: float = 0.0


func _ready() -> void:
	add_to_group("trucks")
	add_to_group("vehicles")
	add_to_group("all_units")
	if is_player_controlled:
		add_to_group("player_units")
		add_to_group("selectable_units")
	else:
		add_to_group("enemy_units")

	_setup_components()
	_apply_data()

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
	vehicle_components.crew_member_killed.connect(_on_crew_killed)


func _apply_data() -> void:
	if not data:
		max_health = 100.0
		current_health = 100.0
		return

	max_health = data.get_total_health()
	current_health = max_health

	# Apply variant modifications
	match variant:
		TruckVariant.M35_CARGO:
			cargo_capacity = 2500.0
			passenger_capacity = 20
		TruckVariant.M35_TROOP:
			cargo_capacity = 500.0  # Less cargo, optimized for troops
			passenger_capacity = 25
		TruckVariant.M35_FUEL:
			cargo_capacity = 3000.0  # Fuel tanker
			passenger_capacity = 2
		TruckVariant.M35_AMMO:
			cargo_capacity = 2000.0
			passenger_capacity = 4


func _build_placeholder_visual() -> void:
	# Cab
	_cab_node = Node3D.new()
	_cab_node.name = "Cab"
	add_child(_cab_node)

	var cab_mesh := MeshInstance3D.new()
	var cab_box := BoxMesh.new()
	cab_box.size = Vector3(2.3, 1.8, 1.8)
	cab_mesh.mesh = cab_box
	cab_mesh.position = Vector3(0, 1.2, 1.8)

	var cab_mat := StandardMaterial3D.new()
	cab_mat.albedo_color = data.get_faction_color() if data else Color(0.35, 0.4, 0.25)
	cab_mesh.material_override = cab_mat
	_cab_node.add_child(cab_mesh)

	# Hood
	var hood := MeshInstance3D.new()
	var hood_mesh := BoxMesh.new()
	hood_mesh.size = Vector3(2.1, 0.8, 1.5)
	hood.mesh = hood_mesh
	hood.position = Vector3(0, 0.7, 3.2)
	hood.material_override = cab_mat
	_cab_node.add_child(hood)

	# Bed
	_bed_node = Node3D.new()
	_bed_node.name = "Bed"
	add_child(_bed_node)

	var bed_floor := MeshInstance3D.new()
	var bed_floor_mesh := BoxMesh.new()
	bed_floor_mesh.size = Vector3(2.4, 0.2, 4.0)
	bed_floor.mesh = bed_floor_mesh
	bed_floor.position = Vector3(0, 0.9, -1.2)
	bed_floor.material_override = cab_mat
	_bed_node.add_child(bed_floor)

	# Bed sides
	for side in [-1, 1]:
		var bed_side := MeshInstance3D.new()
		var side_mesh := BoxMesh.new()
		side_mesh.size = Vector3(0.1, 1.0, 4.0)
		bed_side.mesh = side_mesh
		bed_side.position = Vector3(1.15 * side, 1.5, -1.2)
		bed_side.material_override = cab_mat
		_bed_node.add_child(bed_side)

	# Canvas cover (for cargo/troop variants)
	if variant in [TruckVariant.M35_CARGO, TruckVariant.M35_TROOP]:
		var canvas := MeshInstance3D.new()
		var canvas_mesh := BoxMesh.new()
		canvas_mesh.size = Vector3(2.2, 0.1, 4.0)
		canvas.mesh = canvas_mesh
		canvas.position = Vector3(0, 2.3, -1.2)
		var canvas_mat := StandardMaterial3D.new()
		canvas_mat.albedo_color = Color(0.4, 0.45, 0.35)
		canvas.material_override = canvas_mat
		_bed_node.add_child(canvas)

		# Canvas ribs
		for i in range(4):
			var rib := MeshInstance3D.new()
			var rib_mesh := CylinderMesh.new()
			rib_mesh.top_radius = 0.05
			rib_mesh.bottom_radius = 0.05
			rib_mesh.height = 2.4
			rib.mesh = rib_mesh
			rib.rotation_degrees = Vector3(0, 0, 90)
			rib.position = Vector3(0, 1.8, 0.3 - i * 1.0)
			rib.material_override = canvas_mat
			_bed_node.add_child(rib)

	# Fuel tanker bed
	if variant == TruckVariant.M35_FUEL:
		var tank := MeshInstance3D.new()
		var tank_mesh := CylinderMesh.new()
		tank_mesh.top_radius = 1.0
		tank_mesh.bottom_radius = 1.0
		tank_mesh.height = 4.0
		tank.mesh = tank_mesh
		tank.rotation_degrees = Vector3(90, 0, 0)
		tank.position = Vector3(0, 1.6, -1.2)
		var tank_mat := StandardMaterial3D.new()
		tank_mat.albedo_color = Color(0.3, 0.3, 0.3)
		tank.material_override = tank_mat
		_bed_node.add_child(tank)

	# Wheels (6 - front 2, rear 4 dual)
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.1, 0.1, 0.1)

	# Front wheels
	for side in [-1, 1]:
		var wheel := MeshInstance3D.new()
		var wheel_mesh := CylinderMesh.new()
		wheel_mesh.top_radius = 0.5
		wheel_mesh.bottom_radius = 0.5
		wheel_mesh.height = 0.3
		wheel.mesh = wheel_mesh
		wheel.rotation_degrees = Vector3(0, 0, 90)
		wheel.position = Vector3(1.1 * side, 0.5, 2.8)
		wheel.material_override = wheel_mat
		add_child(wheel)

	# Rear dual wheels
	for axle in [0, 1]:
		for side in [-1, 1]:
			var wheel := MeshInstance3D.new()
			var wheel_mesh := CylinderMesh.new()
			wheel_mesh.top_radius = 0.5
			wheel_mesh.bottom_radius = 0.5
			wheel_mesh.height = 0.5
			wheel.mesh = wheel_mesh
			wheel.rotation_degrees = Vector3(0, 0, 90)
			wheel.position = Vector3(1.2 * side, 0.5, -1.5 - axle * 1.3)
			wheel.material_override = wheel_mat
			add_child(wheel)

	# Collision shape for placeholder
	var coll := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.5, 2.5, 6.5)
	coll.shape = box
	coll.position = Vector3(0, 1.2, 0.5)
	add_child(coll)

	_setup_collision_layer()


func _load_m35_model() -> void:
	# Load the M35 Deuce and a Half GLB model with animated wheels
	var model_scene: PackedScene = load(M35_MODEL_PATH) as PackedScene
	if not model_scene:
		push_warning("TransportTruck: Could not load M35 model, falling back to placeholder")
		_build_placeholder_visual()
		return

	_model_root = model_scene.instantiate() as Node3D
	if not _model_root:
		push_warning("TransportTruck: Failed to instantiate M35 model, falling back to placeholder")
		_build_placeholder_visual()
		return

	_model_root.name = "M35_Model"
	add_child(_model_root)

	# Setup collision
	var coll := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.5, 2.5, 7.0)
	coll.shape = box
	coll.position = Vector3(0, 1.25, 0)
	add_child(coll)

	_setup_collision_layer()

	# Initialize wheel rotation
	_wheel_rotation = 0.0


func _setup_collision_layer() -> void:
	# Set collision layer based on faction
	if data:
		match data.faction:
			GameEnums.Faction.US_ARMY, GameEnums.Faction.ARVN:
				collision_layer = 2
			GameEnums.Faction.VC, GameEnums.Faction.NVA:
				collision_layer = 4
	else:
		collision_layer = 2


func _update_wheel_animation(delta: float) -> void:
	# Update wheel rotation based on vehicle speed
	if not _model_root:
		return

	var current_speed: float = velocity.length()
	if current_speed > 0.1:
		# Convert linear speed to angular rotation
		var distance_this_frame: float = current_speed * delta
		var rotation_increment: float = distance_this_frame / WHEEL_RADIUS
		_wheel_rotation += rotation_increment

		# Keep wheel_rotation in reasonable bounds
		if _wheel_rotation > TAU * 100.0:
			_wheel_rotation = fmod(_wheel_rotation, TAU)

	# Apply wheel_rotation to the model via custom property
	if _model_root.has_method("set"):
		_model_root.set("wheel_rotation", _wheel_rotation)

	# Alternative: AnimationPlayer seek
	var anim_player := _model_root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim_player and anim_player.has_animation("wheel_spin"):
		var anim_length: float = anim_player.get_animation("wheel_spin").length
		var seek_pos: float = fmod(_wheel_rotation / TAU, 1.0) * anim_length
		anim_player.seek(seek_pos, true)

	# Direct wheel node rotation
	_rotate_wheel_nodes()


func _rotate_wheel_nodes() -> void:
	# Directly rotate wheel nodes if they exist in the model hierarchy
	if not _model_root:
		return
	_rotate_wheels_recursive(_model_root, _wheel_rotation)


func _rotate_wheels_recursive(node: Node, angle: float) -> void:
	var node_name_lower: String = node.name.to_lower()
	if "wheel" in node_name_lower or "tire" in node_name_lower:
		if node is Node3D:
			var wheel_node: Node3D = node as Node3D
			wheel_node.rotation.x = angle

	for child in node.get_children():
		_rotate_wheels_recursive(child, angle)


func _physics_process(delta: float) -> void:
	if state == State.DESTROYED:
		return

	match state:
		State.LOADING, State.UNLOADING:
			_process_loading(delta)
		State.DISABLED:
			pass  # Can't move, waiting for repair
		_:
			if has_move_order:
				_process_movement(delta)
			elif is_following_route:
				_process_route_following(delta)

	_snap_to_terrain()

	# Update wheel animation based on movement
	if _model_root:
		_update_wheel_animation(delta)


func _process_loading(delta: float) -> void:
	_load_timer -= delta
	if _load_timer <= 0.0:
		state = State.IDLE


func _process_movement(delta: float) -> void:
	var direction: Vector3 = move_target - global_position
	direction.y = 0
	var distance: float = direction.length()

	if distance < 2.0:
		has_move_order = false
		velocity = Vector3.ZERO
		state = State.IDLE
		return

	var seek_direction: Vector3 = direction.normalized()

	# Slope check
	_slope_query_timer -= delta
	if _slope_query_timer <= 0.0:
		_slope_query_timer = SLOPE_QUERY_INTERVAL
		_cached_slope = _sample_slope_ahead(seek_direction)

	var base_speed: float
	if data and data.has_method("get_speed_at_slope"):
		base_speed = data.get_speed_at_slope(_cached_slope)
	else:
		base_speed = data.move_speed if data else 15.0

	# Apply movement efficiency from components
	var move_eff: float = vehicle_components.get_movement_efficiency() if vehicle_components else 1.0

	# Cargo weight affects speed
	var cargo_penalty: float = 1.0 - (current_cargo_weight / cargo_capacity) * 0.3
	var speed: float = base_speed * move_eff * cargo_penalty

	if speed <= 0.0:
		velocity = Vector3.ZERO
		has_move_order = false
		state = State.DISABLED
		path_blocked_by_slope.emit(global_position, _cached_slope)
		return

	# Truck rotation (wheeled vehicle, can turn tighter at low speeds)
	var target_yaw: float = atan2(seek_direction.x, seek_direction.z)
	var current_yaw: float = rotation.y
	var yaw_diff: float = angle_difference(current_yaw, target_yaw)
	var speed_factor: float = clampf(velocity.length() / base_speed, 0.3, 1.0)
	var max_step: float = deg_to_rad(turn_rate_deg / speed_factor) * delta
	rotation.y = current_yaw + clampf(yaw_diff, -max_step, max_step)

	# Only move if facing target
	var alignment: float = cos(yaw_diff)
	if alignment < 0.0:
		alignment = 0.0
	speed *= alignment

	var forward: Vector3 = Vector3(sin(rotation.y), 0, cos(rotation.y))
	velocity = forward * speed
	move_and_slide()
	state = State.MOVING


func _process_route_following(_delta: float) -> void:
	if current_waypoint >= waypoints.size():
		is_following_route = false
		return

	move_target = waypoints[current_waypoint]
	has_move_order = true

	var dist: float = global_position.distance_to(move_target)
	if dist < 3.0:
		current_waypoint += 1


func _sample_slope_ahead(move_dir: Vector3) -> float:
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if not terrain:
		return 0.0
	var probe_pos: Vector3 = global_position + move_dir * 4.0
	if terrain.has_method("get_normal_at"):
		var normal: Vector3 = terrain.get_normal_at(probe_pos)
		return clampf(1.0 - normal.y, 0.0, 1.0)
	return 0.0


func _snap_to_terrain() -> void:
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		global_position.y = terrain.get_height_at(global_position)


func _on_component_damaged(component_type: int, current_hp: float, max_hp: float) -> void:
	component_hit.emit(component_type, max_hp - current_hp)
	if component_type == VehicleComponentScript.ComponentType.HULL:
		current_health = current_hp


func _on_component_destroyed(component_type: int) -> void:
	# Engine destroyed = disabled
	if component_type == VehicleComponentScript.ComponentType.ENGINE:
		state = State.DISABLED

	# Fuel tank destroyed on fuel truck = explosion
	if component_type == VehicleComponentScript.ComponentType.FUEL_TANK:
		if variant == TruckVariant.M35_FUEL:
			_explode()
			return

	if vehicle_components.is_vehicle_destroyed():
		_destroy()


func _on_crew_killed(_position: int) -> void:
	# Driver dead = vehicle stopped
	if vehicle_components.get_alive_crew_count() == 0:
		state = State.DISABLED


# =============================================================================
# PUBLIC API
# =============================================================================

func move_to(target: Vector3) -> void:
	if state == State.LOADING or state == State.UNLOADING or state == State.DISABLED:
		return
	move_target = target
	has_move_order = true


func attack_move_to(target: Vector3) -> void:
	# Trucks don't attack, just move
	move_to(target)


func follow_route(route: Array[Vector3]) -> void:
	waypoints = route
	current_waypoint = 0
	is_following_route = true


func stop() -> void:
	has_move_order = false
	is_following_route = false
	velocity = Vector3.ZERO
	state = State.IDLE


func load_cargo(cargo_type: int, amount: float) -> float:
	var space: float = cargo_capacity - current_cargo_weight
	var to_load: float = minf(amount, space)

	if not cargo.has(cargo_type):
		cargo[cargo_type] = 0.0
	cargo[cargo_type] += to_load
	current_cargo_weight += to_load

	state = State.LOADING
	_load_timer = LOAD_TIME_PER_UNIT * (to_load / 100.0)

	cargo_loaded.emit(self, cargo_type, to_load)
	return to_load


func unload_cargo(cargo_type: int, amount: float = -1.0) -> float:
	if not cargo.has(cargo_type):
		return 0.0

	var available: float = cargo[cargo_type]
	var to_unload: float = available if amount < 0.0 else minf(amount, available)

	cargo[cargo_type] -= to_unload
	current_cargo_weight -= to_unload

	if cargo[cargo_type] <= 0.0:
		cargo.erase(cargo_type)

	state = State.UNLOADING
	_load_timer = LOAD_TIME_PER_UNIT * (to_unload / 100.0)

	cargo_unloaded.emit(self, cargo_type, to_unload)
	return to_unload


func unload_all_cargo() -> Dictionary:
	var unloaded: Dictionary = cargo.duplicate()
	cargo.clear()
	current_cargo_weight = 0.0
	state = State.UNLOADING
	_load_timer = 1.0
	return unloaded


func load_passenger(unit: Node3D) -> bool:
	if passengers.size() >= passenger_capacity:
		return false
	if state == State.DESTROYED:
		return false

	passengers.append(unit)
	unit.visible = false
	unit.set_physics_process(false)

	state = State.LOADING
	_load_timer = LOAD_TIME_PER_UNIT

	passengers_loaded.emit(self, passengers.size())
	return true


func unload_passengers() -> Array[Node3D]:
	if passengers.is_empty():
		return []

	var unload_pos: Vector3 = global_position - transform.basis.z * 5.0
	var offset_angle: float = 0.0
	var unloaded: Array[Node3D] = []

	for passenger in passengers:
		if is_instance_valid(passenger):
			var offset := Vector3(cos(offset_angle), 0, sin(offset_angle)) * 3.0
			passenger.global_position = unload_pos + offset
			passenger.visible = true
			passenger.set_physics_process(true)
			unloaded.append(passenger)
			offset_angle += TAU / maxf(passengers.size(), 1.0)

	passengers.clear()
	state = State.UNLOADING
	_load_timer = LOAD_TIME_PER_UNIT * unloaded.size()

	passengers_unloaded.emit(self, unloaded)
	return unloaded


func take_damage(amount: float, source: Node = null) -> void:
	if state == State.DESTROYED:
		return

	# Trucks are unarmored - full damage
	if vehicle_components:
		var hit_angle: float = 0.0
		if source and is_instance_valid(source):
			var to_source: Vector3 = source.global_position - global_position
			to_source.y = 0.0
			if to_source.length() > 0.1:
				hit_angle = atan2(to_source.x, to_source.z) - rotation.y

		vehicle_components.take_directional_damage(amount, hit_angle, VehicleComponentScript.AmmoType.HE)

		# Passengers very vulnerable in open truck
		if not passengers.is_empty() and randf() < 0.5:
			var victim: Node3D = passengers.pick_random()
			if is_instance_valid(victim) and victim.has_method("take_damage"):
				victim.take_damage(amount * 0.6, source)

		# Cargo damage (especially ammo/fuel)
		if randf() < 0.3:
			_damage_cargo(amount)
	else:
		current_health = maxf(0.0, current_health - amount)
		if current_health <= 0.0:
			_destroy()

	# Ambush detection
	if source:
		ambush_detected.emit(self, source)


func _damage_cargo(amount: float) -> void:
	# Ammo can cook off
	if cargo.has(CargoType.AMMUNITION) and cargo[CargoType.AMMUNITION] > 0:
		if randf() < amount / 100.0:
			_explode()
			return

	# Fuel can ignite
	if cargo.has(CargoType.FUEL) and cargo[CargoType.FUEL] > 0:
		if randf() < amount / 150.0:
			_explode()
			return


func _destroy() -> void:
	state = State.DESTROYED
	truck_destroyed.emit(self)

	# Kill passengers
	for passenger in passengers:
		if is_instance_valid(passenger) and passenger.has_method("take_damage"):
			passenger.take_damage(9999, self)
	passengers.clear()

	# Visual destruction
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.12, 0.08)
	_apply_material_recursive(self, mat)

	var t := get_tree().create_timer(10.0)
	t.timeout.connect(queue_free)


func _explode() -> void:
	# Catastrophic explosion - damages nearby units
	var explosion_radius: float = 15.0 if variant == TruckVariant.M35_FUEL else 10.0
	var explosion_damage: float = 200.0 if variant == TruckVariant.M35_AMMO else 100.0

	# Damage nearby units using SpatialHashGrid for efficient spatial query
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


func _apply_material_recursive(node: Node, mat: Material) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			child.material_override = mat
		_apply_material_recursive(child, mat)


func get_cargo_weight() -> float:
	return current_cargo_weight


func get_available_space() -> float:
	return cargo_capacity - current_cargo_weight


func get_cargo_amount(cargo_type: int) -> float:
	return cargo.get(cargo_type, 0.0)


func get_passenger_count() -> int:
	return passengers.size()


func has_space_for_passengers() -> bool:
	return passengers.size() < passenger_capacity


func get_status() -> Dictionary:
	var move_eff: float = vehicle_components.get_movement_efficiency() if vehicle_components else 1.0

	return {
		"state": State.keys()[state],
		"health_percent": (vehicle_components.get_total_hp() / vehicle_components.get_max_hp() * 100.0) if vehicle_components else (current_health / max_health * 100.0),
		"movement_efficiency": move_eff * 100.0,
		"cargo_weight": current_cargo_weight,
		"cargo_capacity": cargo_capacity,
		"passengers": passengers.size(),
		"passenger_capacity": passenger_capacity,
	}
