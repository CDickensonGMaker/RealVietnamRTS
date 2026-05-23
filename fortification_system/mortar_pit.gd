class_name MortarPit extends Node3D
## Mortar Pit - Indirect fire emplacement with area effect
##
## 81mm mortar that provides fire support against ground targets.
## Can fire over obstacles, has area damage, slower ROF than MG.
## Uses DetectionArea for efficient target acquisition, SceneTreeTimer for impacts.

const DetectionArea = preload("res://battle_system/components/detection_area.gd")

signal target_engaged(target_position: Vector3)
signal round_fired(target_position: Vector3)
signal round_impact(impact_position: Vector3, damage: float)
signal emplacement_destroyed(emplacement: Node3D)
signal ammo_depleted()
signal reloaded()

enum MortarState { IDLE, ACQUIRING, FIRING, RELOADING, SUPPRESSED, DESTROYED }

## Configuration - 81mm Mortar stats from Game Bible
@export var min_range: float = 100.0        # Minimum range (dead zone)
@export var max_range: float = 3500.0       # 3.5km per CLAUDE.md
@export var damage_per_round: float = 80.0  # Direct hit damage
@export var blast_radius: float = 8.0       # Area effect radius
@export var fire_interval: float = 4.0      # Slow ROF (loading time)
@export var magazine_size: int = 12         # Rounds before resupply
@export var reload_time: float = 15.0       # Full resupply time
@export var detection_radius: float = 400.0 # Auto-detect enemies within
@export var crew_size: int = 3              # Gunner, loader, ammo bearer
@export var suppression_per_round: float = 60.0  # High suppression

## Accuracy - mortars have spread (per artillery.gd volley pattern)
@export var accuracy_deviation: float = 8.0  # Base meters of random spread
@export var rounds_per_volley: int = 3       # Fire multiple rounds per volley

## Health
@export var max_health: float = 150.0
@export var pit_damage_reduction: float = 0.4  # 40% from being in pit

## State
var state: MortarState = MortarState.IDLE
var current_target: Node3D = null
var target_position: Vector3 = Vector3.INF  # Can target positions directly
var ammo_remaining: int = 12
var current_health: float = 150.0
var _crew_alive: int = 3
var faction: int = 0  # GameEnums.Faction.US_ARMY
var is_player_controlled: bool = true
var _pending_impact_count: int = 0  # Track rounds in flight (for get_pending_rounds())

## Tweens for timing (replaces manual timers)
var _fire_tween: Tween = null
var _reload_tween: Tween = null
var _suppression_tween: Tween = null
var _acquiring_tween: Tween = null
var _rotation_tween: Tween = null

## Detection system (Area3D-based)
var _detection_area: DetectionArea = null

## Cached flight time for current volley
var _current_flight_time: float = 2.0

## Rotation tracking
var _current_rotation: float = 0.0

## Visual components
var _tube_mesh: MeshInstance3D = null
var _base_mesh: MeshInstance3D = null
var _bipod_mesh: MeshInstance3D = null


func _ready() -> void:
	add_to_group("mortar_pits")
	add_to_group("fortifications")
	add_to_group("defensive_emplacements")
	add_to_group("indirect_fire")
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

	print("[MortarPit] Initialized - Range: %.0f-%.0fm, Crew: %d" % [min_range, max_range, crew_size])


func _setup_detection_area() -> void:
	_detection_area = DetectionArea.new()
	_detection_area.detection_radius = detection_radius
	_detection_area.exclude_groups = ["helicopters", "aircraft"]  # Ground targets only

	if is_player_controlled:
		_detection_area.configure_for_player()
	else:
		_detection_area.configure_for_enemy()

	_detection_area.target_entered.connect(_on_target_detected)
	_detection_area.target_exited.connect(_on_target_lost)
	add_child(_detection_area)


func _on_target_detected(target: Node3D) -> void:
	if state == MortarState.IDLE and not current_target and target_position == Vector3.INF:
		# Check if target is within mortar range (not too close)
		var dist := global_position.distance_to(target.global_position)
		if dist >= min_range and dist <= max_range:
			current_target = target
			state = MortarState.ACQUIRING
			target_engaged.emit(target.global_position)
			print("[MortarPit] Acquiring target: %s at %.0fm" % [target.name, dist])


func _on_target_lost(target: Node3D) -> void:
	if current_target == target:
		_find_new_target()


func _create_visual() -> void:
	# Circular pit (dug into ground)
	_base_mesh = MeshInstance3D.new()
	var pit := CylinderMesh.new()
	pit.top_radius = 2.5
	pit.bottom_radius = 2.5
	pit.height = 0.6
	_base_mesh.mesh = pit

	var pit_mat := StandardMaterial3D.new()
	pit_mat.albedo_color = Color(0.35, 0.3, 0.25)  # Dirt/sandbag
	_base_mesh.material_override = pit_mat
	_base_mesh.position.y = 0.3
	add_child(_base_mesh)

	# Sandbag rim
	var rim := MeshInstance3D.new()
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = 2.0
	rim_mesh.outer_radius = 2.8
	rim.mesh = rim_mesh
	rim.material_override = pit_mat
	rim.position.y = 0.5
	add_child(rim)

	# Mortar tube
	_tube_mesh = MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.06
	tube.bottom_radius = 0.08
	tube.height = 1.2
	_tube_mesh.mesh = tube

	var tube_mat := StandardMaterial3D.new()
	tube_mat.albedo_color = Color(0.15, 0.15, 0.15)  # Dark metal
	_tube_mesh.material_override = tube_mat
	_tube_mesh.position = Vector3(0, 0.8, 0)
	_tube_mesh.rotation.x = deg_to_rad(-70)  # Angled for indirect fire
	add_child(_tube_mesh)

	# Baseplate
	var baseplate := MeshInstance3D.new()
	var bp := CylinderMesh.new()
	bp.top_radius = 0.4
	bp.bottom_radius = 0.5
	bp.height = 0.1
	baseplate.mesh = bp
	baseplate.material_override = tube_mat
	baseplate.position = Vector3(0, 0.05, 0.3)
	add_child(baseplate)

	# Bipod legs
	_bipod_mesh = MeshInstance3D.new()
	var bipod := BoxMesh.new()
	bipod.size = Vector3(0.6, 0.05, 0.05)
	_bipod_mesh.mesh = bipod
	_bipod_mesh.material_override = tube_mat
	_bipod_mesh.position = Vector3(0, 0.5, -0.4)
	add_child(_bipod_mesh)

	# Collision for selection/damage
	var body := StaticBody3D.new()
	body.name = "Body"
	var coll := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 2.5
	shape.height = 1.0
	coll.shape = shape
	coll.position.y = 0.5
	body.add_child(coll)
	body.collision_layer = 64  # Buildings layer
	add_child(body)


func _process(_delta: float) -> void:
	if state == MortarState.DESTROYED:
		return

	# State machine - most timing now handled by Tweens
	match state:
		MortarState.IDLE:
			_process_idle()
		MortarState.ACQUIRING:
			_process_acquiring()
		# FIRING and RELOADING states are now Tween-driven


func _process_idle() -> void:
	if target_position != Vector3.INF or (current_target and is_instance_valid(current_target)):
		state = MortarState.ACQUIRING


func _process_acquiring() -> void:
	# Determine target position
	var fire_pos: Vector3 = Vector3.INF

	if target_position != Vector3.INF:
		fire_pos = target_position
	elif current_target and is_instance_valid(current_target):
		if _is_target_dead(current_target):
			current_target = null
			state = MortarState.IDLE
			return
		fire_pos = current_target.global_position

	if fire_pos == Vector3.INF:
		state = MortarState.IDLE
		return

	# Check range
	var distance: float = global_position.distance_to(fire_pos)
	if distance < min_range:
		# Too close - mortars can't fire at close range
		_find_new_target()
		return
	if distance > max_range:
		_find_new_target()
		return

	# Aim tube at target (azimuth only, elevation is fixed for indirect)
	var direction: Vector3 = (fire_pos - global_position)
	direction.y = 0
	if direction.length() > 0.1:
		var target_angle := atan2(direction.x, direction.z)
		# Smooth rotation to face target
		_rotate_to_target(target_angle)

	# Ready to fire - start Tween-based firing loop
	if ammo_remaining > 0 and _crew_alive > 0:
		state = MortarState.FIRING
		target_engaged.emit(fire_pos)
		_start_firing()


## Start Tween-based firing loop
func _start_firing() -> void:
	if _fire_tween:
		_fire_tween.kill()

	# Fire first round after short delay (faster than full interval)
	_fire_tween = create_tween()
	_fire_tween.tween_callback(_fire_volley).set_delay(fire_interval * 0.5)


## Fire a volley and schedule next if still in FIRING state
func _fire_volley() -> void:
	if state != MortarState.FIRING:
		return

	# Determine target position
	var fire_pos: Vector3 = Vector3.INF
	if target_position != Vector3.INF:
		fire_pos = target_position
	elif current_target and is_instance_valid(current_target):
		if _is_target_dead(current_target):
			current_target = null
			target_position = Vector3.INF
			state = MortarState.IDLE
			return
		fire_pos = current_target.global_position

	if fire_pos == Vector3.INF:
		state = MortarState.IDLE
		return

	# Check still in range
	var distance: float = global_position.distance_to(fire_pos)
	if distance < min_range or distance > max_range:
		state = MortarState.ACQUIRING
		return

	# Fire the round
	_fire_round(fire_pos)

	# Schedule next volley if still in firing state and has ammo
	if state == MortarState.FIRING and ammo_remaining > 0:
		if _fire_tween:
			_fire_tween.kill()
		_fire_tween = create_tween()
		_fire_tween.tween_callback(_fire_volley).set_delay(fire_interval)


## Stop firing loop
func _stop_firing() -> void:
	if _fire_tween:
		_fire_tween.kill()
		_fire_tween = null


## Start Tween-based reload
func _start_reloading() -> void:
	state = MortarState.RELOADING
	ammo_depleted.emit()
	print("[MortarPit] Out of ammo - reloading")

	if _reload_tween:
		_reload_tween.kill()

	_reload_tween = create_tween()
	_reload_tween.tween_callback(_finish_reloading).set_delay(reload_time)


## Complete reload - requires firebase supply
const MORTAR_RELOAD_COST: int = 5  # Supply cost per reload

func _finish_reloading() -> void:
	# Find nearest firebase and consume supply
	var firebase := _find_nearest_firebase()
	if firebase and firebase.has_method("consume_supply") and firebase.consume_supply(MORTAR_RELOAD_COST):
		ammo_remaining = magazine_size
		state = MortarState.IDLE
		reloaded.emit()
		print("[MortarPit] Reloaded - %d rounds" % ammo_remaining)
	else:
		# No supply - stay empty, retry later
		print("[MortarPit] Cannot reload - no firebase supply")
		state = MortarState.IDLE
		# Try again in 5 seconds
		if _reload_tween:
			_reload_tween.kill()
		_reload_tween = create_tween()
		_reload_tween.tween_callback(_start_reloading).set_delay(5.0)


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


## Start suppression recovery timer
func _start_suppression_recovery(duration: float) -> void:
	if _suppression_tween:
		_suppression_tween.kill()

	_suppression_tween = create_tween()
	_suppression_tween.tween_callback(_recover_from_suppression).set_delay(duration)


## Recover from suppression
func _recover_from_suppression() -> void:
	if state == MortarState.SUPPRESSED:
		state = MortarState.IDLE
		print("[MortarPit] Recovered from suppression")


func _rotate_to_target(target_angle: float) -> void:
	# Skip if already at target angle
	if absf(angle_difference(_current_rotation, target_angle)) < 0.01:
		return

	if _rotation_tween:
		_rotation_tween.kill()

	_rotation_tween = create_tween()
	_rotation_tween.set_trans(Tween.TRANS_SINE)
	_rotation_tween.set_ease(Tween.EASE_OUT)
	_rotation_tween.tween_property(self, "rotation:y", target_angle, 0.3)
	_rotation_tween.tween_callback(func(): _current_rotation = target_angle)


func _find_new_target() -> void:
	current_target = null
	target_position = Vector3.INF

	# Use DetectionArea to find targets (no manual scanning needed)
	if not _detection_area:
		state = MortarState.IDLE
		return

	# Get targets from DetectionArea, sorted by distance
	var targets := _detection_area.get_targets_by_distance()

	# Find best target - prioritize groups (mortars are area weapons)
	var best_target: Node3D = null
	var best_priority: float = 0.0

	for target in targets:
		if not is_instance_valid(target):
			continue

		var distance: float = global_position.distance_to(target.global_position)

		# Must be within firing range (not too close)
		if distance < min_range or distance > max_range:
			continue

		# Prioritize groups of enemies
		var priority: float = 1.0

		# Bonus for squads (multiple soldiers)
		if "squad_size" in target:
			priority += float(target.squad_size) * 0.2

		# Bonus for stationary targets (easier to hit)
		if "velocity" in target:
			var speed: float = (target.velocity as Vector3).length()
			if speed < 1.0:
				priority += 0.5

		if priority > best_priority:
			best_target = target
			best_priority = priority

	if best_target:
		current_target = best_target
		state = MortarState.ACQUIRING
		print("[MortarPit] Acquiring target: %s at %.0fm" % [best_target.name, global_position.distance_to(best_target.global_position)])
	else:
		state = MortarState.IDLE


func _fire_round(target_pos: Vector3) -> void:
	if ammo_remaining <= 0:
		_start_reloading()
		return

	if _crew_alive <= 0:
		return  # No crew to operate

	# Calculate flight time based on distance (ballistic arc)
	var distance: float = global_position.distance_to(target_pos)
	_current_flight_time = 2.0 + distance / 200.0  # 2-4+ seconds flight time

	# Accuracy deviation - per artillery.gd volley pattern
	var deviation: float = accuracy_deviation
	if _crew_alive < crew_size:
		deviation *= 1.5  # Less accurate with fewer crew

	# Fire volley of rounds with randomized spread (like artillery.gd)
	var rounds_fired: int = 0
	for i in rounds_per_volley:
		if ammo_remaining <= 0:
			break

		ammo_remaining -= 1
		rounds_fired += 1
		_pending_impact_count += 1

		# Random spread for each round in volley (artillery.gd pattern)
		var spread := Vector3(
			randf_range(-deviation, deviation),
			0,
			randf_range(-deviation, deviation)
		)
		var impact_pos: Vector3 = target_pos + spread

		# Stagger flight times slightly for realism (0.2s between impacts)
		var staggered_flight := _current_flight_time + i * 0.2

		# Schedule impact using SceneTreeTimer (no manual array tracking)
		var timer := get_tree().create_timer(staggered_flight)
		timer.timeout.connect(_on_impact_timer.bind(impact_pos, damage_per_round))

	round_fired.emit(target_pos)

	# Visual/audio feedback
	_spawn_launch_effect()

	# Emit signal for audio
	if BattleSignals:
		BattleSignals.projectile_fired.emit(global_position, target_pos)

	print("[MortarPit] Volley of %d rounds at %.0fm - flight time %.1fs (spread: %.1fm)" % [
		rounds_fired, distance, _current_flight_time, deviation
	])


## Called when a round's flight timer expires
func _on_impact_timer(impact_pos: Vector3, damage: float) -> void:
	_pending_impact_count -= 1
	_apply_impact_at(impact_pos, damage)


func _apply_impact_at(impact_pos: Vector3, damage: float) -> void:
	round_impact.emit(impact_pos, damage)

	# Spawn impact effect
	_spawn_impact_effect(impact_pos)

	# Use physics overlap query for blast damage (more efficient than group iteration)
	var space := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = blast_radius
	params.shape = sphere
	params.transform.origin = impact_pos
	params.collision_mask = 0b1110  # Layers 2,3,4 (US, VC, NVA units)

	var results := space.intersect_shape(params)
	var units_hit: int = 0

	for result in results:
		var collider: Object = result.collider
		if not is_instance_valid(collider):
			continue

		# Get the unit (could be the collider itself or its parent)
		var unit: Node3D = null
		if collider is Node3D and collider.has_method("take_damage"):
			unit = collider
		elif collider.get_parent() is Node3D and collider.get_parent().has_method("take_damage"):
			unit = collider.get_parent()

		if not unit:
			continue

		var dist: float = unit.global_position.distance_to(impact_pos)
		if dist > blast_radius:
			continue

		units_hit += 1

		# Damage falloff from center
		var falloff: float = 1.0 - (dist / blast_radius)
		falloff = maxf(0.2, falloff)  # Minimum 20% damage at edge
		var applied_damage: float = damage * falloff

		# Apply damage
		unit.take_damage(applied_damage, self)

		# Apply suppression (mortars are very suppressive)
		var applied_suppression: float = suppression_per_round * falloff
		if unit.has_method("apply_suppression"):
			unit.apply_suppression(applied_suppression)
		elif "suppression" in unit:
			var current_sup: float = unit.suppression
			unit.suppression = minf(100.0, current_sup + applied_suppression)

	print("[MortarPit] Impact at (%.0f, %.0f) - %d units in blast" % [
		impact_pos.x, impact_pos.z, units_hit
	])


func _spawn_launch_effect() -> void:
	# Simple smoke puff at tube exit
	# In full implementation, would spawn particle effect
	pass


func _spawn_impact_effect(pos: Vector3) -> void:
	# Use particle pool if available (GPU-accelerated)
	if ParticlePool and ParticlePool.instance:
		ParticlePool.spawn_mortar_impact(pos)
		return

	# Fallback: Create mesh-based explosion visual
	var explosion := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = blast_radius * 0.3
	explosion.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.2, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.1)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	explosion.material_override = mat
	explosion.position = pos
	explosion.position.y += 1.0

	get_tree().root.add_child(explosion)

	# Fade out and remove
	var tween := create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tween.parallel().tween_property(explosion, "scale", Vector3(2, 2, 2), 0.5)
	tween.tween_callback(explosion.queue_free)


func _is_target_dead(target: Node) -> bool:
	if not is_instance_valid(target):
		return true

	if target.has_method("get"):
		var health = target.get("current_health")
		if health != null and health <= 0:
			return true
		health = target.get("health")
		if health != null and health <= 0:
			return true

	if target.has_method("is_dead"):
		return target.is_dead()

	if target.has_method("is_destroyed"):
		return target.is_destroyed()

	return false


# =============================================================================
# DAMAGE & SUPPRESSION
# =============================================================================

func take_damage(amount: float, _source: Node = null) -> void:
	# Pit provides some protection
	var reduced_damage: float = amount * (1.0 - pit_damage_reduction)
	current_health -= reduced_damage

	# Chance to kill crew member
	if randf() < reduced_damage / 40.0:
		_crew_alive = maxi(0, _crew_alive - 1)
		print("[MortarPit] Crew casualty! %d remaining" % _crew_alive)

	if current_health <= 0:
		_destroy()
	elif _crew_alive <= 0:
		state = MortarState.IDLE
		print("[MortarPit] Crew eliminated - mortar unmanned")


func apply_suppression(amount: float) -> void:
	if state == MortarState.DESTROYED:
		return

	# Mortar crews are easier to suppress (exposed position)
	var effective_suppression: float = amount * 0.8

	if effective_suppression > 25.0:
		_stop_firing()
		state = MortarState.SUPPRESSED
		var recovery_time := 3.0 + randf() * 3.0  # 3-6 seconds
		_start_suppression_recovery(recovery_time)
		print("[MortarPit] Suppressed!")


func _destroy() -> void:
	state = MortarState.DESTROYED
	current_target = null
	target_position = Vector3.INF

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
	if _acquiring_tween:
		_acquiring_tween.kill()
		_acquiring_tween = null
	if _rotation_tween:
		_rotation_tween.kill()
		_rotation_tween = null

	# Visual destruction
	if _tube_mesh:
		_tube_mesh.rotation = Vector3(randf() * 0.5 - 0.25, randf() * TAU, randf() * 0.3)
	if _base_mesh:
		var mat := _base_mesh.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.15, 0.15, 0.15)  # Charred

	emplacement_destroyed.emit(self)

	remove_from_group("mortar_pits")
	remove_from_group("defensive_emplacements")
	remove_from_group("indirect_fire")
	remove_from_group("player_units")
	remove_from_group("enemy_units")

	print("[MortarPit] Destroyed")


# =============================================================================
# PUBLIC API
# =============================================================================

func is_operational() -> bool:
	return state != MortarState.DESTROYED and _crew_alive > 0


func is_destroyed() -> bool:
	return state == MortarState.DESTROYED


func get_ammo_percent() -> float:
	return float(ammo_remaining) / float(magazine_size)


func get_crew_percent() -> float:
	return float(_crew_alive) / float(crew_size)


func get_state_name() -> String:
	return MortarState.keys()[state]


func get_current_target() -> Node3D:
	return current_target


func get_pending_rounds() -> int:
	return _pending_impact_count


func set_faction(new_faction: int, player_controlled: bool) -> void:
	faction = new_faction
	is_player_controlled = player_controlled

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


## Fire at a specific world position (manual targeting)
func fire_at_position(pos: Vector3) -> bool:
	var distance: float = global_position.distance_to(pos)
	if distance < min_range or distance > max_range:
		return false
	if _crew_alive <= 0 or ammo_remaining <= 0:
		return false

	target_position = pos
	current_target = null
	state = MortarState.ACQUIRING
	return true


## Clear manual target and return to auto-targeting
func clear_target() -> void:
	target_position = Vector3.INF
	current_target = null
	state = MortarState.IDLE


## Resupply ammo
func resupply(rounds: int) -> void:
	ammo_remaining = mini(ammo_remaining + rounds, magazine_size)


## Replace crew casualties
func reinforce_crew(count: int) -> void:
	_crew_alive = mini(_crew_alive + count, crew_size)
	if _crew_alive > 0 and state == MortarState.IDLE:
		state = MortarState.ACQUIRING
