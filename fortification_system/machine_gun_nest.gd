class_name MachineGunNest extends Node3D
## Machine Gun Nest - Auto-firing defensive emplacement
##
## Unlike regular bunkers that require garrisoned squads to fire, the MG Nest
## has a crew that automatically engages enemy ground units within range.
##
## Uses DetectionArea for efficient target acquisition (Area3D signals).

const DetectionArea = preload("res://battle_system/components/detection_area.gd")

signal target_engaged(target: Node3D)
signal target_killed(target: Node3D)
signal emplacement_destroyed(emplacement: Node3D)
signal ammo_depleted()
signal reloaded()

enum MGState { IDLE, TRACKING, FIRING, RELOADING, SUPPRESSED, DESTROYED }

## Configuration - M60 stats from Game Bible
@export var engagement_range: float = 500.0  # 500m per CLAUDE.md
@export var damage_per_burst: float = 25.0   # M60 damage
@export var burst_interval: float = 0.3      # High ROF
@export var magazine_size: int = 100         # Belt-fed
@export var reload_time: float = 5.0         # Belt change
@export var detection_radius: float = 550.0  # Slightly beyond engagement
@export var crew_size: int = 2               # Gunner + assistant
@export var suppression_per_burst: float = 30.0  # High suppression
@export var firing_arc_degrees: float = 360.0    # Full traverse (on tripod)

## Health
@export var max_health: float = 200.0
@export var sandbag_damage_reduction: float = 0.5  # 50% reduction from cover

## State
var state: MGState = MGState.IDLE
var current_target: Node3D = null
var ammo_remaining: int = 100
var current_health: float = 200.0
var _crew_alive: int = 2
var faction: int = 0  # GameEnums.Faction.US_ARMY
var is_player_controlled: bool = true

## Tweens for timing (replaces manual timers)
var _fire_tween: Tween = null
var _reload_tween: Tween = null
var _suppression_tween: Tween = null
var _rotation_tween: Tween = null

## Detection system (Area3D-based)
var _detection_area: DetectionArea = null

## Rotation tracking
var _current_gun_angle: float = 0.0
var _target_gun_angle: float = 0.0

## Visual components
var _gun_mesh: MeshInstance3D = null
var _base_mesh: MeshInstance3D = null
var _muzzle_point: Node3D = null
var _muzzle_flash: OmniLight3D = null


func _ready() -> void:
	add_to_group("mg_nests")
	add_to_group("fortifications")
	add_to_group("defensive_emplacements")
	add_to_group("all_units")

	if is_player_controlled:
		add_to_group("player_structures")
		add_to_group("player_units")
	else:
		add_to_group("enemy_structures")
		add_to_group("enemy_units")

	current_health = max_health
	ammo_remaining = magazine_size
	_crew_alive = crew_size

	_create_visual()
	_setup_detection_area()

	print("[MachineGunNest] Initialized - Range: %.0fm, Crew: %d" % [engagement_range, crew_size])


func _setup_detection_area() -> void:
	_detection_area = DetectionArea.new()
	_detection_area.detection_radius = detection_radius
	_detection_area.exclude_groups = ["helicopters", "aircraft"]  # Ground only
	_detection_area.use_firing_arc = firing_arc_degrees < 360.0
	_detection_area.firing_arc_degrees = firing_arc_degrees

	if is_player_controlled:
		_detection_area.configure_for_player()
	else:
		_detection_area.configure_for_enemy()

	_detection_area.target_entered.connect(_on_target_detected)
	_detection_area.target_exited.connect(_on_target_lost)
	add_child(_detection_area)


func _on_target_detected(target: Node3D) -> void:
	if state == MGState.IDLE and not current_target:
		current_target = target
		state = MGState.TRACKING
		target_engaged.emit(target)
		print("[MachineGunNest] Engaging: %s" % target.name)


func _on_target_lost(target: Node3D) -> void:
	if current_target == target:
		_find_new_target()


func _create_visual() -> void:
	# Sandbag ring base
	_base_mesh = MeshInstance3D.new()
	var base := CylinderMesh.new()
	base.top_radius = 2.0
	base.bottom_radius = 2.5
	base.height = 1.0
	_base_mesh.mesh = base

	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.55, 0.45, 0.35)  # Sandbag tan
	_base_mesh.material_override = base_mat
	_base_mesh.position.y = 0.5
	add_child(_base_mesh)

	# M60 on tripod
	_gun_mesh = MeshInstance3D.new()
	var gun := BoxMesh.new()
	gun.size = Vector3(0.15, 0.12, 1.2)  # Long barrel
	_gun_mesh.mesh = gun

	var gun_mat := StandardMaterial3D.new()
	gun_mat.albedo_color = Color(0.15, 0.15, 0.15)  # Dark metal
	_gun_mesh.material_override = gun_mat
	_gun_mesh.position = Vector3(0, 1.2, 0)
	add_child(_gun_mesh)

	# Tripod legs (simple representation)
	var tripod := MeshInstance3D.new()
	var tri := BoxMesh.new()
	tri.size = Vector3(0.6, 0.3, 0.6)
	tripod.mesh = tri
	tripod.material_override = gun_mat
	tripod.position = Vector3(0, 0.95, 0)
	add_child(tripod)

	# Muzzle point for effects
	_muzzle_point = Node3D.new()
	_muzzle_point.position = Vector3(0, 0, 0.6)
	_gun_mesh.add_child(_muzzle_point)

	# Muzzle flash light (hidden by default)
	_muzzle_flash = OmniLight3D.new()
	_muzzle_flash.light_color = Color(1.0, 0.8, 0.3)
	_muzzle_flash.light_energy = 3.0
	_muzzle_flash.omni_range = 5.0
	_muzzle_flash.visible = false
	_muzzle_point.add_child(_muzzle_flash)

	# Collision for selection/damage
	var body := StaticBody3D.new()
	body.name = "Body"
	var coll := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 2.0
	shape.height = 1.5
	coll.shape = shape
	coll.position.y = 0.75
	body.add_child(coll)
	body.collision_layer = 64  # Buildings layer
	add_child(body)


func _process(delta: float) -> void:
	if state == MGState.DESTROYED:
		return

	# State machine (suppression/reload handled by Tweens)
	match state:
		MGState.IDLE:
			_process_idle()
		MGState.TRACKING:
			_process_tracking(delta)
		MGState.FIRING:
			_process_firing(delta)
		MGState.RELOADING:
			pass  # Handled by Tween
		MGState.SUPPRESSED:
			pass  # Handled by Tween


func _process_idle() -> void:
	if current_target and is_instance_valid(current_target):
		state = MGState.TRACKING


func _process_tracking(delta: float) -> void:
	if not current_target or not is_instance_valid(current_target):
		_find_new_target()
		if not current_target:
			state = MGState.IDLE
			return

	# Check target still alive
	if _is_target_dead(current_target):
		current_target = null
		state = MGState.IDLE
		return

	# Rotate gun to track target (smooth)
	var target_pos: Vector3 = current_target.global_position
	_rotate_gun_to_target(target_pos)

	# Check firing arc
	if not _is_in_firing_arc(target_pos):
		_find_new_target()
		return

	# Check range and fire
	var distance: float = global_position.distance_to(target_pos)
	if distance <= engagement_range:
		if ammo_remaining > 0 and _crew_alive > 0:
			state = MGState.FIRING


func _process_firing(_delta: float) -> void:
	if not current_target or not is_instance_valid(current_target):
		_stop_firing()
		state = MGState.TRACKING
		return

	# Check target dead
	if _is_target_dead(current_target):
		target_killed.emit(current_target)
		current_target = null
		_stop_firing()
		state = MGState.IDLE
		return

	# Check still in range
	var distance: float = global_position.distance_to(current_target.global_position)
	if distance > engagement_range:
		_stop_firing()
		state = MGState.TRACKING
		return

	# Check firing arc
	if not _is_in_firing_arc(current_target.global_position):
		_stop_firing()
		state = MGState.TRACKING
		return

	# Keep tracking while firing
	_rotate_gun_to_target(current_target.global_position)

	# Start fire tween if not running
	if not _fire_tween or not _fire_tween.is_running():
		_start_firing()


func _start_firing() -> void:
	if _fire_tween:
		_fire_tween.kill()
	_fire_tween = create_tween().set_loops()
	_fire_tween.tween_callback(_fire_burst).set_delay(burst_interval)
	_fire_burst()  # Fire immediately


func _stop_firing() -> void:
	if _fire_tween:
		_fire_tween.kill()
		_fire_tween = null


func _start_reload() -> void:
	state = MGState.RELOADING
	ammo_depleted.emit()
	print("[MachineGunNest] Magazine empty - reloading")

	if _reload_tween:
		_reload_tween.kill()
	_reload_tween = create_tween()
	_reload_tween.tween_callback(_finish_reload).set_delay(reload_time)


## Supply cost for MG nest reload
const MG_RELOAD_COST: int = 2

func _finish_reload() -> void:
	# Find nearest firebase and consume supply
	var firebase := _find_nearest_firebase()
	if firebase and firebase.has_method("consume_supply") and firebase.consume_supply(MG_RELOAD_COST):
		ammo_remaining = magazine_size
		state = MGState.TRACKING
		reloaded.emit()
		print("[MachineGunNest] Reloaded - %d rounds" % ammo_remaining)
	else:
		# No supply - stay empty, retry later
		print("[MachineGunNest] Cannot reload - no firebase supply")
		state = MGState.IDLE
		# Try again in 5 seconds
		if _reload_tween:
			_reload_tween.kill()
		_reload_tween = create_tween()
		_reload_tween.tween_callback(_start_reload).set_delay(5.0)


## Find the nearest firebase within range
func _find_nearest_firebase() -> Node3D:
	const SUPPLY_RADIUS: float = 150.0
	var firebases: Array[Node] = get_tree().get_nodes_in_group("firebases")
	var nearest: Node3D = null
	var nearest_dist: float = SUPPLY_RADIUS

	for fb in firebases:
		if not is_instance_valid(fb) or not fb is Node3D:
			continue
		var dist: float = global_position.distance_to(fb.global_position)
		if dist < nearest_dist:
			nearest = fb as Node3D
			nearest_dist = dist

	return nearest


func _rotate_gun_to_target(target_pos: Vector3, instant: bool = false) -> void:
	var direction: Vector3 = (target_pos - global_position)
	direction.y = 0
	if not _gun_mesh or direction.length() < 0.1:
		return

	var target_angle := atan2(direction.x, direction.z)

	# Skip if already at target angle
	if absf(angle_difference(_current_gun_angle, target_angle)) < 0.01:
		return

	_target_gun_angle = target_angle

	if instant:
		_gun_mesh.rotation.y = target_angle
		_current_gun_angle = target_angle
		return

	# Smooth rotation via Tween (fast for responsive tracking)
	if _rotation_tween:
		_rotation_tween.kill()

	_rotation_tween = create_tween()
	_rotation_tween.set_trans(Tween.TRANS_SINE)
	_rotation_tween.set_ease(Tween.EASE_OUT)
	_rotation_tween.tween_property(_gun_mesh, "rotation:y", target_angle, 0.15)
	_rotation_tween.tween_callback(func(): _current_gun_angle = target_angle)


func _find_new_target() -> void:
	current_target = null

	if not _detection_area:
		return

	# Use DetectionArea to get closest valid target
	var new_target := _detection_area.get_closest_target_in_arc()
	if new_target:
		current_target = new_target
		state = MGState.TRACKING
		target_engaged.emit(new_target)
		print("[MachineGunNest] Engaging: %s" % new_target.name)
	else:
		state = MGState.IDLE


func _fire_burst() -> void:
	if ammo_remaining <= 0:
		_stop_firing()
		_start_reload()
		return

	if _crew_alive <= 0:
		_stop_firing()
		return  # No crew to operate

	ammo_remaining -= 1

	# Muzzle flash (use particle pool if available, fallback to light)
	var muzzle_pos := _muzzle_point.global_position if _muzzle_point else global_position + Vector3(0, 1.2, 0)
	if ParticlePool and ParticlePool.instance:
		ParticlePool.spawn_muzzle_flash(muzzle_pos)
	elif _muzzle_flash:
		_muzzle_flash.visible = true
		get_tree().create_timer(0.05).timeout.connect(func():
			if _muzzle_flash: _muzzle_flash.visible = false
		)

	# Calculate hit chance
	var hit_chance: float = 0.5  # Base 50%
	var distance: float = global_position.distance_to(current_target.global_position)

	# Better accuracy at closer range
	hit_chance += (1.0 - distance / engagement_range) * 0.3

	# Reduced accuracy with fewer crew
	if _crew_alive < crew_size:
		hit_chance *= 0.7

	# Worse accuracy if target is moving fast
	if current_target.has_method("get") and current_target.get("velocity"):
		var speed: float = (current_target.velocity as Vector3).length()
		hit_chance -= speed * 0.02

	hit_chance = clampf(hit_chance, 0.15, 0.8)

	# Apply damage if hit
	if randf() < hit_chance:
		if current_target.has_method("take_damage"):
			current_target.take_damage(damage_per_burst, self)

		# Apply suppression
		if current_target.has_method("apply_suppression"):
			current_target.apply_suppression(suppression_per_burst)
		elif current_target.has_method("set") and current_target.get("suppression") != null:
			var current_sup: float = current_target.suppression
			current_target.suppression = minf(100.0, current_sup + suppression_per_burst)

	# Emit projectile signal for visual/audio
	if BattleSignals:
		BattleSignals.projectile_fired.emit(muzzle_pos, current_target.global_position)


func _is_in_firing_arc(target_pos: Vector3) -> bool:
	if firing_arc_degrees >= 360.0:
		return true

	var to_target: Vector3 = target_pos - global_position
	to_target.y = 0
	if to_target.length() < 0.1:
		return true

	var target_angle: float = atan2(to_target.x, to_target.z)
	var gun_angle: float = _gun_mesh.rotation.y if _gun_mesh else 0.0
	var half_arc: float = deg_to_rad(firing_arc_degrees * 0.5)
	var diff: float = abs(angle_difference(gun_angle, target_angle))
	return diff <= half_arc


func _is_target_dead(target: Node) -> bool:
	if not is_instance_valid(target):
		return true

	# Check health property
	if target.has_method("get"):
		var health = target.get("current_health")
		if health != null and health <= 0:
			return true
		health = target.get("health")
		if health != null and health <= 0:
			return true

	# Check is_dead method
	if target.has_method("is_dead"):
		return target.is_dead()

	# Check destroyed state
	if target.has_method("is_destroyed"):
		return target.is_destroyed()

	return false


# =============================================================================
# DAMAGE & SUPPRESSION
# =============================================================================

func take_damage(amount: float, source: Node = null) -> void:
	# Sandbag cover reduces incoming damage
	var reduced_damage: float = amount * (1.0 - sandbag_damage_reduction)
	current_health -= reduced_damage

	# Chance to kill crew member
	if randf() < reduced_damage / 50.0:
		_crew_alive = maxi(0, _crew_alive - 1)
		print("[MachineGunNest] Crew casualty! %d remaining" % _crew_alive)

	if current_health <= 0:
		_destroy()
	elif _crew_alive <= 0:
		state = MGState.IDLE
		print("[MachineGunNest] Crew eliminated - emplacement unmanned")


func apply_suppression(amount: float) -> void:
	if state == MGState.DESTROYED:
		return

	# MG nests are harder to suppress due to cover
	var effective_suppression: float = amount * 0.5

	if effective_suppression > 30.0:
		_stop_firing()
		state = MGState.SUPPRESSED
		print("[MachineGunNest] Suppressed!")

		# Use Tween for suppression recovery
		if _suppression_tween:
			_suppression_tween.kill()
		_suppression_tween = create_tween()
		var recovery_time := 2.0 + randf() * 2.0  # 2-4 seconds
		_suppression_tween.tween_callback(_recover_from_suppression).set_delay(recovery_time)


func _recover_from_suppression() -> void:
	if state == MGState.SUPPRESSED:
		state = MGState.IDLE
		print("[MachineGunNest] Recovered from suppression")


func _destroy() -> void:
	state = MGState.DESTROYED
	current_target = null

	# Stop all tweens
	if _fire_tween:
		_fire_tween.kill()
		_fire_tween = null
	if _reload_tween:
		_reload_tween.kill()
		_reload_tween = null
	if _suppression_tween:
		_suppression_tween.kill()
		_suppression_tween = null
	if _rotation_tween:
		_rotation_tween.kill()
		_rotation_tween = null

	# Visual destruction
	if _gun_mesh:
		_gun_mesh.rotation = Vector3(randf() * 0.5 - 0.25, randf() * TAU, randf() * 0.3)
	if _base_mesh:
		var mat := _base_mesh.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.2, 0.2, 0.2)  # Charred

	emplacement_destroyed.emit(self)

	# Remove from combat groups
	remove_from_group("mg_nests")
	remove_from_group("defensive_emplacements")
	remove_from_group("player_units")
	remove_from_group("enemy_units")

	print("[MachineGunNest] Destroyed")


# =============================================================================
# PUBLIC API
# =============================================================================

func is_operational() -> bool:
	return state != MGState.DESTROYED and _crew_alive > 0


func is_destroyed() -> bool:
	return state == MGState.DESTROYED


func get_ammo_percent() -> float:
	return float(ammo_remaining) / float(magazine_size)


func get_crew_percent() -> float:
	return float(_crew_alive) / float(crew_size)


func get_state_name() -> String:
	return MGState.keys()[state]


func get_current_target() -> Node3D:
	return current_target


func set_faction(new_faction: int, player_controlled: bool) -> void:
	faction = new_faction
	is_player_controlled = player_controlled

	# Update groups
	remove_from_group("player_structures")
	remove_from_group("player_units")
	remove_from_group("enemy_structures")
	remove_from_group("enemy_units")

	if is_player_controlled:
		add_to_group("player_structures")
		add_to_group("player_units")
	else:
		add_to_group("enemy_structures")
		add_to_group("enemy_units")

	# Reconfigure detection area
	if _detection_area:
		if is_player_controlled:
			_detection_area.configure_for_player()
		else:
			_detection_area.configure_for_enemy()
		_detection_area.revalidate_targets()


## Manually set a priority target
func set_priority_target(target: Node3D) -> void:
	if is_instance_valid(target) and not _is_target_dead(target):
		current_target = target
		state = MGState.TRACKING


## Resupply ammo (e.g., from ammo bunker)
func resupply(rounds: int) -> void:
	ammo_remaining = mini(ammo_remaining + rounds, magazine_size)


## Replace crew casualties
func reinforce_crew(count: int) -> void:
	_crew_alive = mini(_crew_alive + count, crew_size)
	if _crew_alive > 0 and state == MGState.IDLE:
		state = MGState.TRACKING
