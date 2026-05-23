extends Node3D
class_name AAEmplacement

## Anti-Aircraft Gun Emplacement
## NVA AA position that denies helicopter operations in area
## Uses DetectionArea for target acquisition, Tween-based firing.

const DetectionArea = preload("res://battle_system/components/detection_area.gd")

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
var _crew_health: int = 4
var _is_revealed: bool = false

## Tweens for timing (replaces manual timers)
var _fire_tween: Tween = null
var _reload_tween: Tween = null
var _rotation_tween: Tween = null

## Detection system (Area3D-based, targeting aircraft)
var _detection_area: DetectionArea = null

## Visual components
var _gun_mesh: MeshInstance3D = null
var _muzzle_point: Node3D = null


func _ready() -> void:
	add_to_group("aa_emplacements")
	add_to_group("enemy_units")

	_configure_aa_type()
	_create_visual()
	_setup_detection_area()
	ammo_remaining = magazine_size

	print("[AAEmplacement] Initialized - Type: %d, Range: %.0fm" % [aa_type, engagement_range])


func _setup_detection_area() -> void:
	_detection_area = DetectionArea.new()
	_detection_area.detection_radius = detection_radius
	# AA emplacement specifically targets aircraft
	_detection_area.configure_for_aa()
	_detection_area.target_groups = ["helicopters", "aircraft", "player_units"]

	_detection_area.target_entered.connect(_on_target_detected)
	_detection_area.target_exited.connect(_on_target_lost)
	add_child(_detection_area)


func _on_target_detected(target: Node3D) -> void:
	# Only engage helicopters/aircraft that are player-controlled
	if not target.is_in_group("helicopters") and not target.is_in_group("aircraft"):
		return
	if not target.is_in_group("player_units"):
		return

	if not current_target or not is_instance_valid(current_target):
		current_target = target
		helicopter_engaged.emit(target)
		state = AAState.TRACKING
		_is_revealed = true
		print("[AAEmplacement] Engaging helicopter: %s" % target.name)


func _on_target_lost(target: Node3D) -> void:
	if current_target == target:
		_find_new_target()


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


func _process(_delta: float) -> void:
	if state == AAState.DESTROYED:
		return

	# State machine - most timing now handled by Tweens
	match state:
		AAState.HIDDEN:
			_process_hidden()
		AAState.TRACKING:
			_process_tracking()
		# FIRING and RELOADING states are now Tween-driven


func _process_hidden() -> void:
	"""Hidden state - wait for target"""
	if current_target and is_instance_valid(current_target):
		state = AAState.TRACKING
		_is_revealed = true


func _process_tracking() -> void:
	"""Track target helicopter"""
	if not current_target or not is_instance_valid(current_target):
		_find_new_target()
		if not current_target:
			state = AAState.HIDDEN
			return

	# Rotate gun to track target (smooth)
	var target_pos: Vector3 = current_target.global_position
	_rotate_gun_to_target(target_pos)

	# Check if in range and can fire
	var distance: float = global_position.distance_to(target_pos)
	if distance <= engagement_range:
		if ammo_remaining > 0:
			state = AAState.FIRING
			_start_firing()


## Smooth rotation to track target
func _rotate_gun_to_target(target_pos: Vector3) -> void:
	if not _gun_mesh:
		return

	# Calculate target rotation
	var direction := (target_pos - global_position).normalized()
	var target_yaw := atan2(direction.x, direction.z)
	var target_pitch := -asin(direction.y)  # Negative because look_at uses different convention
	target_pitch = clampf(target_pitch, deg_to_rad(10), deg_to_rad(85))

	# Use tween for smooth rotation (fast for AA tracking)
	if _rotation_tween:
		_rotation_tween.kill()

	_rotation_tween = create_tween()
	_rotation_tween.set_trans(Tween.TRANS_SINE)
	_rotation_tween.set_ease(Tween.EASE_OUT)
	_rotation_tween.set_parallel(true)
	_rotation_tween.tween_property(_gun_mesh, "rotation:y", target_yaw, 0.1)
	_rotation_tween.tween_property(_gun_mesh, "rotation:x", target_pitch, 0.1)


## Start Tween-based firing loop
func _start_firing() -> void:
	if _fire_tween:
		_fire_tween.kill()

	# Fire first burst after short delay
	_fire_tween = create_tween()
	_fire_tween.tween_callback(_fire_volley).set_delay(burst_interval * 0.5)


## Fire a burst and schedule next
func _fire_volley() -> void:
	if state != AAState.FIRING:
		return

	if not current_target or not is_instance_valid(current_target):
		state = AAState.TRACKING
		return

	# Check still in range
	var distance: float = global_position.distance_to(current_target.global_position)
	if distance > engagement_range:
		state = AAState.TRACKING
		return

	# Fire the burst
	_fire_burst()

	# Schedule next burst if still firing
	if state == AAState.FIRING and ammo_remaining > 0:
		if _fire_tween:
			_fire_tween.kill()
		_fire_tween = create_tween()
		_fire_tween.tween_callback(_fire_volley).set_delay(burst_interval)


## Stop firing loop
func _stop_firing() -> void:
	if _fire_tween:
		_fire_tween.kill()
		_fire_tween = null


## Start reload using Tween
func _start_reloading() -> void:
	state = AAState.RELOADING

	if _reload_tween:
		_reload_tween.kill()

	_reload_tween = create_tween()
	_reload_tween.tween_callback(_finish_reloading).set_delay(reload_time)


## Finish reloading
func _finish_reloading() -> void:
	ammo_remaining = magazine_size
	state = AAState.TRACKING
	print("[AAEmplacement] Reloaded")


func _find_new_target() -> void:
	"""Find a new target helicopter using DetectionArea"""
	current_target = null
	_stop_firing()

	if not _detection_area:
		state = AAState.HIDDEN
		return

	# Get closest target from DetectionArea
	var new_target := _detection_area.get_closest_target()

	if new_target:
		# Verify it's a helicopter/aircraft and player-controlled
		if (new_target.is_in_group("helicopters") or new_target.is_in_group("aircraft")) \
				and new_target.is_in_group("player_units"):
			current_target = new_target
			state = AAState.TRACKING
			helicopter_engaged.emit(new_target)
			print("[AAEmplacement] Engaging helicopter: %s" % new_target.name)
			return

	state = AAState.HIDDEN


func _fire_burst() -> void:
	"""Fire a burst at target"""
	if ammo_remaining <= 0:
		_start_reloading()
		return

	if not current_target or not is_instance_valid(current_target):
		return

	ammo_remaining -= 1

	# Calculate hit chance (helicopters are harder to hit)
	var hit_chance: float = 0.3  # Base 30%
	var distance: float = global_position.distance_to(current_target.global_position)

	# Better accuracy at closer range
	hit_chance += (1.0 - distance / engagement_range) * 0.3

	# Worse accuracy if target is moving fast
	if "velocity" in current_target:
		var speed: float = current_target.velocity.length()
		hit_chance -= speed * 0.01

	hit_chance = clampf(hit_chance, 0.1, 0.7)

	# Check for hit
	if randf() < hit_chance:
		# Apply damage
		if current_target.has_method("take_damage"):
			current_target.take_damage(damage_per_burst, self)

			# Check if destroyed
			if "current_health" in current_target:
				if current_target.current_health <= 0:
					helicopter_shot_down.emit(current_target)
					print("[AAEmplacement] Helicopter shot down!")
					current_target = null
					_stop_firing()

	# Visual effect
	_spawn_tracer_effect()

	# Emit signal
	if BattleSignals:
		var target_pos := current_target.global_position if current_target else Vector3.ZERO
		BattleSignals.projectile_fired.emit(global_position, target_pos)


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

	# Stop all tweens
	if _fire_tween:
		_fire_tween.kill()
		_fire_tween = null
	if _reload_tween:
		_reload_tween.kill()
		_reload_tween = null
	if _rotation_tween:
		_rotation_tween.kill()
		_rotation_tween = null

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
