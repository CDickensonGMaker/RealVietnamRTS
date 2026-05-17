extends Node3D
class_name AAEmplacement

## Anti-Aircraft Gun Emplacement
## NVA AA position that denies helicopter operations in area

signal helicopter_engaged(helicopter: Node3D)
signal helicopter_shot_down(helicopter: Node3D)
signal emplacement_destroyed(emplacement: Node3D)

enum AAState { HIDDEN, TRACKING, FIRING, RELOADING, DESTROYED }

## Configuration
@export var aa_type: int = 0  # 0 = ZPU-4, 1 = 37mm, 2 = 57mm
@export var engagement_range: float = 150.0
@export var damage_per_burst: float = 50.0
@export var burst_interval: float = 1.0
@export var magazine_size: int = 20
@export var reload_time: float = 8.0
@export var detection_radius: float = 200.0
@export var crew_size: int = 4

## State
var state: AAState = AAState.HIDDEN
var current_target: Node3D = null
var ammo_remaining: int = 20
var _fire_timer: float = 0.0
var _reload_timer: float = 0.0
var _detection_timer: float = 0.0
var _crew_health: int = 4
var _is_revealed: bool = false

## Visual components
var _gun_mesh: MeshInstance3D = null
var _muzzle_point: Node3D = null


func _ready() -> void:
	add_to_group("aa_emplacements")
	add_to_group("enemy_units")

	_configure_aa_type()
	_create_visual()
	ammo_remaining = magazine_size

	print("[AAEmplacement] Initialized - Type: %d, Range: %.0fm" % [aa_type, engagement_range])


func _configure_aa_type() -> void:
	"""Configure based on AA type"""
	match aa_type:
		0:  # ZPU-4 (quad 14.5mm)
			engagement_range = 150.0
			damage_per_burst = 40.0
			burst_interval = 0.5
			magazine_size = 40
			reload_time = 6.0
		1:  # 37mm
			engagement_range = 300.0
			damage_per_burst = 80.0
			burst_interval = 1.5
			magazine_size = 15
			reload_time = 10.0
		2:  # 57mm
			engagement_range = 400.0
			damage_per_burst = 150.0
			burst_interval = 3.0
			magazine_size = 8
			reload_time = 15.0


func _create_visual() -> void:
	"""Create AA gun visual"""
	# Base platform
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 1.5
	base_mesh.bottom_radius = 2.0
	base_mesh.height = 0.5
	base.mesh = base_mesh

	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.3, 0.35, 0.25)  # Olive drab
	base.material_override = base_mat
	base.position.y = 0.25
	add_child(base)

	# Gun barrel(s)
	_gun_mesh = MeshInstance3D.new()
	var barrel_mesh := BoxMesh.new()
	barrel_mesh.size = Vector3(0.15, 0.15, 2.0)
	_gun_mesh.mesh = barrel_mesh

	var gun_mat := StandardMaterial3D.new()
	gun_mat.albedo_color = Color(0.2, 0.2, 0.2)  # Dark metal
	_gun_mesh.material_override = gun_mat
	_gun_mesh.position = Vector3(0, 1.0, 0)
	_gun_mesh.rotation.x = deg_to_rad(45)  # Angled up
	add_child(_gun_mesh)

	# Muzzle point
	_muzzle_point = Node3D.new()
	_muzzle_point.position = Vector3(0, 0, 1.0)
	_gun_mesh.add_child(_muzzle_point)

	# Collision
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 2.0, 3.0)
	collision.shape = shape
	collision.position.y = 1.0

	var area := Area3D.new()
	area.add_child(collision)
	add_child(area)


func _process(delta: float) -> void:
	if state == AAState.DESTROYED:
		return

	_detection_timer += delta

	# Scan for helicopters periodically
	if _detection_timer >= 0.5:
		_detection_timer = 0.0
		_scan_for_helicopters()

	# Update based on state
	match state:
		AAState.HIDDEN:
			_process_hidden()
		AAState.TRACKING:
			_process_tracking(delta)
		AAState.FIRING:
			_process_firing(delta)
		AAState.RELOADING:
			_process_reloading(delta)


func _process_hidden() -> void:
	"""Hidden state - wait for target"""
	if current_target and is_instance_valid(current_target):
		state = AAState.TRACKING
		_is_revealed = true


func _process_tracking(delta: float) -> void:
	"""Track target helicopter"""
	if not current_target or not is_instance_valid(current_target):
		_find_new_target()
		if not current_target:
			state = AAState.HIDDEN
			return

	# Rotate gun to track target
	var target_pos: Vector3 = current_target.global_position
	var direction: Vector3 = (target_pos - global_position).normalized()

	if _gun_mesh:
		_gun_mesh.look_at(target_pos)
		# Keep elevation angle within limits
		_gun_mesh.rotation.x = clampf(_gun_mesh.rotation.x, deg_to_rad(10), deg_to_rad(85))

	# Check if in range and can fire
	var distance: float = global_position.distance_to(target_pos)
	if distance <= engagement_range:
		if ammo_remaining > 0:
			state = AAState.FIRING
			_fire_timer = 0.0


func _process_firing(delta: float) -> void:
	"""Fire at target"""
	_fire_timer += delta

	if not current_target or not is_instance_valid(current_target):
		state = AAState.TRACKING
		return

	# Check still in range
	var distance: float = global_position.distance_to(current_target.global_position)
	if distance > engagement_range:
		state = AAState.TRACKING
		return

	# Fire bursts
	if _fire_timer >= burst_interval:
		_fire_timer = 0.0
		_fire_burst()


func _process_reloading(delta: float) -> void:
	"""Reload magazine"""
	_reload_timer += delta

	if _reload_timer >= reload_time:
		_reload_timer = 0.0
		ammo_remaining = magazine_size
		state = AAState.TRACKING
		print("[AAEmplacement] Reloaded")


func _scan_for_helicopters() -> void:
	"""Scan for helicopters in detection range"""
	if current_target and is_instance_valid(current_target):
		return  # Already have target

	var helicopters: Array[Node] = get_tree().get_nodes_in_group("helicopters")

	for heli in helicopters:
		if not is_instance_valid(heli):
			continue

		# Only target player helicopters
		if not heli.is_in_group("player_units"):
			continue

		var distance: float = global_position.distance_to(heli.global_position)
		if distance <= detection_radius:
			current_target = heli
			helicopter_engaged.emit(heli)
			print("[AAEmplacement] Engaging helicopter: %s" % heli.name)
			break


func _find_new_target() -> void:
	"""Find a new target helicopter"""
	current_target = null
	_scan_for_helicopters()


func _fire_burst() -> void:
	"""Fire a burst at target"""
	if ammo_remaining <= 0:
		state = AAState.RELOADING
		_reload_timer = 0.0
		return

	ammo_remaining -= 1

	# Calculate hit chance (helicopters are harder to hit)
	var hit_chance: float = 0.3  # Base 30%
	var distance: float = global_position.distance_to(current_target.global_position)

	# Better accuracy at closer range
	hit_chance += (1.0 - distance / engagement_range) * 0.3

	# Worse accuracy if target is moving fast
	if current_target.has_method("get") and current_target.get("velocity"):
		var speed: float = current_target.velocity.length()
		hit_chance -= speed * 0.01

	hit_chance = clampf(hit_chance, 0.1, 0.7)

	# Check for hit
	if randf() < hit_chance:
		# Apply damage
		if current_target.has_method("take_damage"):
			current_target.take_damage(damage_per_burst, self)

			# Check if destroyed
			if current_target.has_method("get") and current_target.get("current_health"):
				if current_target.current_health <= 0:
					helicopter_shot_down.emit(current_target)
					print("[AAEmplacement] Helicopter shot down!")
					current_target = null

	# Visual effect
	_spawn_tracer_effect()

	# Emit signal
	if BattleSignals:
		BattleSignals.projectile_fired.emit(global_position, current_target.global_position if current_target else Vector3.ZERO)


func _spawn_tracer_effect() -> void:
	"""Spawn tracer fire visual"""
	# Simple tracer line
	if not current_target:
		return

	# Would spawn actual tracer projectile here
	# For now, just emit the signal


func take_damage(amount: float, _source: Node = null) -> void:
	"""Take damage from attack"""
	_crew_health -= int(amount / 25.0)  # Rough conversion

	if _crew_health <= 0:
		_destroy()


func _destroy() -> void:
	"""Destroy the AA emplacement"""
	state = AAState.DESTROYED
	emplacement_destroyed.emit(self)

	# Visual destruction
	if _gun_mesh:
		_gun_mesh.rotation = Vector3(randf() * 0.5, randf() * TAU, randf() * 0.5)

	# Remove from groups
	remove_from_group("aa_emplacements")
	remove_from_group("enemy_units")

	print("[AAEmplacement] Destroyed")


## Public API

func get_denial_radius() -> float:
	"""Get the radius this AA denies helicopter operations"""
	return engagement_range


func is_operational() -> bool:
	return state != AAState.DESTROYED and _crew_health > 0


func reveal() -> void:
	"""Reveal the AA position (spotted by player)"""
	_is_revealed = true


func is_revealed() -> bool:
	return _is_revealed


func get_state_name() -> String:
	return AAState.keys()[state]
