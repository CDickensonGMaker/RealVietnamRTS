class_name UnitAnimator extends Node
## Procedural animation system for static mesh units
## Adds visual life without requiring rigged skeletal animations

# Animation states
enum AnimState { IDLE, MOVING, FIRING, SUPPRESSED, DEAD, WORKING }

# Animation parameters
@export_group("Infantry Animation")
@export var infantry_bob_height: float = 0.08  # Vertical bob when walking
@export var infantry_bob_speed: float = 8.0  # Bob frequency
@export var infantry_sway_angle: float = 3.0  # Side-to-side sway (degrees)
@export var infantry_sway_speed: float = 4.0

@export_group("Vehicle Animation")
@export var vehicle_bounce_height: float = 0.03  # Suspension bounce
@export var vehicle_bounce_speed: float = 6.0
@export var turret_rotation_speed: float = 45.0  # Degrees per second

@export_group("Helicopter Animation")
@export var rotor_spin_speed: float = 720.0  # Degrees per second (2 rotations)
@export var hover_bob_height: float = 0.15
@export var hover_bob_speed: float = 2.0

@export_group("Combat Animation")
@export var fire_recoil_distance: float = 0.05
@export var fire_recoil_duration: float = 0.1
@export var suppression_shake_intensity: float = 0.02

@export_group("Bulldozer Animation")
@export var blade_cycle_speed: float = 2.0  # Full cycles per second
@export var blade_angle_min: float = -15.0  # Degrees - blade down (digging)
@export var blade_angle_max: float = 25.0   # Degrees - blade up (raised)

# Internal state
var _target_node: Node3D
var _model_node: Node3D
var _current_state: AnimState = AnimState.IDLE
var _anim_time: float = 0.0
var _base_position: Vector3 = Vector3.ZERO
var _base_rotation: Vector3 = Vector3.ZERO
var _is_vehicle: bool = false
var _is_helicopter: bool = false
var _is_bulldozer: bool = false
var _rotor_node: Node3D = null
var _turret_node: Node3D = null
var _blade_node: Node3D = null
var _blade_base_rotation: Vector3 = Vector3.ZERO
var _fire_recoil_timer: float = 0.0
var _target_turret_angle: float = 0.0


func setup(target: Node3D, model: Node3D, is_vehicle: bool = false, is_helicopter: bool = false, is_bulldozer: bool = false) -> void:
	_target_node = target
	_model_node = model
	_is_vehicle = is_vehicle
	_is_helicopter = is_helicopter
	_is_bulldozer = is_bulldozer

	if model:
		_base_position = model.position
		_base_rotation = model.rotation_degrees

		# Try to find rotor node for helicopters
		if is_helicopter:
			_rotor_node = _find_node_by_pattern(model, ["rotor", "blade", "prop"])

		# Try to find turret node for vehicles (non-bulldozers)
		if is_vehicle and not is_bulldozer:
			_turret_node = _find_node_by_pattern(model, ["turret", "tower", "gun"])

		# Try to find blade/arm node for bulldozers
		if is_bulldozer:
			_blade_node = _find_node_by_pattern(model, ["blade", "dozer", "arm", "bucket", "ripper", "plow", "scoop"])
			if _blade_node:
				_blade_base_rotation = _blade_node.rotation_degrees
				print("[UnitAnimator] Found bulldozer blade node: ", _blade_node.name)


func _find_node_by_pattern(root: Node, patterns: Array) -> Node3D:
	"""Recursively search for a node matching any of the name patterns."""
	for child in root.get_children():
		var child_name_lower: String = child.name.to_lower()
		for pattern in patterns:
			if pattern in child_name_lower:
				if child is Node3D:
					return child as Node3D

		# Recurse
		if child.get_child_count() > 0:
			var found: Node3D = _find_node_by_pattern(child, patterns)
			if found:
				return found

	return null


func set_state(new_state: int) -> void:
	_current_state = new_state as AnimState


func trigger_fire_recoil() -> void:
	_fire_recoil_timer = fire_recoil_duration


func set_turret_target(target_position: Vector3) -> void:
	if not _target_node or not _turret_node:
		return

	var direction: Vector3 = (target_position - _target_node.global_position).normalized()
	_target_turret_angle = rad_to_deg(atan2(direction.x, direction.z))


func set_working(working: bool) -> void:
	"""Set the working state for bulldozers/construction units"""
	if working:
		_current_state = AnimState.WORKING
	elif _current_state == AnimState.WORKING:
		_current_state = AnimState.IDLE


func process_animation(delta: float) -> void:
	if not _model_node:
		return

	_anim_time += delta

	# Process fire recoil
	if _fire_recoil_timer > 0.0:
		_fire_recoil_timer -= delta

	# Apply animation based on unit type
	if _is_helicopter:
		_animate_helicopter(delta)
	elif _is_vehicle:
		_animate_vehicle(delta)
	else:
		_animate_infantry(delta)


func _animate_infantry(_delta: float) -> void:
	var pos_offset := Vector3.ZERO
	var rot_offset := Vector3.ZERO

	match _current_state:
		AnimState.MOVING:
			# Vertical bob
			pos_offset.y = sin(_anim_time * infantry_bob_speed) * infantry_bob_height
			# Side sway
			rot_offset.z = sin(_anim_time * infantry_sway_speed) * infantry_sway_angle
			# Forward lean when moving
			rot_offset.x = 5.0

		AnimState.FIRING:
			# Slight crouch/brace
			pos_offset.y = -0.03
			# Fire recoil
			if _fire_recoil_timer > 0.0:
				var recoil_factor: float = _fire_recoil_timer / fire_recoil_duration
				pos_offset.z = -fire_recoil_distance * recoil_factor
				rot_offset.x = -5.0 * recoil_factor

		AnimState.SUPPRESSED:
			# Duck down and shake
			pos_offset.y = -0.1
			pos_offset.x = randf_range(-suppression_shake_intensity, suppression_shake_intensity)
			pos_offset.z = randf_range(-suppression_shake_intensity, suppression_shake_intensity)

		AnimState.IDLE:
			# Subtle breathing motion
			pos_offset.y = sin(_anim_time * 1.5) * 0.01
			rot_offset.z = sin(_anim_time * 0.8) * 0.5

		AnimState.WORKING:
			# Engineer kneeling work animation - picking up debris/clearing
			# Slower, deeper crouch than walking
			var kneel_cycle := sin(_anim_time * 1.2 * TAU)  # Slow cycle
			pos_offset.y = -0.15 + kneel_cycle * 0.05  # Base crouch + small bob

			# Reach forward motion (picking up debris)
			var reach_cycle := sin(_anim_time * 0.6 * TAU)  # Half speed of kneel
			pos_offset.z = reach_cycle * 0.08

			# Lean forward while working
			rot_offset.x = 8.0 + kneel_cycle * 2.0  # Forward lean with slight motion

			# Slight side-to-side weight shift
			rot_offset.z = sin(_anim_time * 0.9 * TAU) * 2.0

		AnimState.DEAD:
			# Fall over (one-time, handled elsewhere)
			pass

	_model_node.position = _base_position + pos_offset
	_model_node.rotation_degrees = _base_rotation + rot_offset


func _animate_vehicle(delta: float) -> void:
	var pos_offset := Vector3.ZERO
	var rot_offset := Vector3.ZERO

	match _current_state:
		AnimState.MOVING:
			# Suspension bounce
			pos_offset.y = sin(_anim_time * vehicle_bounce_speed) * vehicle_bounce_height
			# Slight pitch variation
			rot_offset.x = sin(_anim_time * vehicle_bounce_speed * 0.7) * 1.0
			# Roll on turns (would need velocity direction)
			rot_offset.z = sin(_anim_time * vehicle_bounce_speed * 0.5) * 0.5

		AnimState.FIRING:
			# Recoil shake
			if _fire_recoil_timer > 0.0:
				var recoil_factor: float = _fire_recoil_timer / fire_recoil_duration
				pos_offset.z = -fire_recoil_distance * 2.0 * recoil_factor
				rot_offset.x = -3.0 * recoil_factor

		AnimState.WORKING:
			# Bulldozer work motion - forward/back push while blade cycles
			# This makes it look like the dozer is pushing earth/debris
			var push_offset := sin(_anim_time * blade_cycle_speed * TAU * 0.5) * 0.4  # 0.4m forward/back
			pos_offset.z = push_offset

			# Working vibration - more intense than idle
			pos_offset.y = sin(_anim_time * 12.0) * 0.02
			pos_offset.x = sin(_anim_time * 15.0) * 0.01

			# Slight pitch from digging - synced with push motion
			rot_offset.x = 3.0 + sin(_anim_time * blade_cycle_speed * TAU * 0.5) * 2.0

		AnimState.IDLE:
			# Engine idle vibration
			pos_offset.y = randf_range(-0.005, 0.005)

	_model_node.position = _base_position + pos_offset
	_model_node.rotation_degrees = _base_rotation + rot_offset

	# Animate turret rotation toward target (non-bulldozers)
	if _turret_node:
		var current_angle: float = _turret_node.rotation_degrees.y
		var angle_diff: float = _target_turret_angle - current_angle
		# Normalize angle difference
		while angle_diff > 180.0:
			angle_diff -= 360.0
		while angle_diff < -180.0:
			angle_diff += 360.0

		var rotation_step: float = turret_rotation_speed * delta
		if absf(angle_diff) < rotation_step:
			_turret_node.rotation_degrees.y = _target_turret_angle
		else:
			_turret_node.rotation_degrees.y += signf(angle_diff) * rotation_step

	# Animate bulldozer blade
	if _blade_node and _is_bulldozer:
		_animate_blade(delta)


func _animate_blade(_delta: float) -> void:
	"""Animate bulldozer blade based on current state"""
	if not _blade_node:
		return

	var target_angle: float = 0.0

	match _current_state:
		AnimState.WORKING:
			# Oscillate blade up and down while working
			# Use sin wave to create smooth back-and-forth motion
			var cycle: float = sin(_anim_time * blade_cycle_speed * TAU)
			# Map -1..1 to min..max angle range
			target_angle = lerpf(blade_angle_min, blade_angle_max, (cycle + 1.0) * 0.5)

		AnimState.MOVING:
			# Keep blade raised while moving
			target_angle = blade_angle_max * 0.8

		AnimState.IDLE:
			# Rest position - slightly raised
			target_angle = lerpf(blade_angle_min, blade_angle_max, 0.3)

		_:
			# Default rest position
			target_angle = 0.0

	# Apply rotation to blade (X axis for pitch up/down)
	_blade_node.rotation_degrees.x = _blade_base_rotation.x + target_angle


func _animate_helicopter(delta: float) -> void:
	var pos_offset := Vector3.ZERO
	var rot_offset := Vector3.ZERO

	# Always spin rotor if helicopter is active
	if _rotor_node and _current_state != AnimState.DEAD:
		_rotor_node.rotation_degrees.y += rotor_spin_speed * delta

	match _current_state:
		AnimState.MOVING:
			# Nose down when moving forward
			rot_offset.x = 15.0
			# Hover bob still present
			pos_offset.y = sin(_anim_time * hover_bob_speed * 1.5) * hover_bob_height * 0.5

		AnimState.IDLE:
			# Gentle hover bob
			pos_offset.y = sin(_anim_time * hover_bob_speed) * hover_bob_height
			# Slight yaw drift
			rot_offset.y = sin(_anim_time * 0.5) * 2.0

		AnimState.FIRING:
			# Stabilize for firing
			rot_offset.x = 5.0  # Slight nose down
			pos_offset.y = sin(_anim_time * hover_bob_speed) * hover_bob_height * 0.3

	_model_node.position = _base_position + pos_offset
	_model_node.rotation_degrees = _base_rotation + rot_offset
