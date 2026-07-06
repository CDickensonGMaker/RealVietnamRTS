class_name FireHazard extends Area3D
## FireHazard - Persistent area-of-effect fire damage (napalm, incendiary)
##
## Creates a burning area that:
## - Damages units over time (burn damage)
## - Applies suppression continuously
## - Spreads slowly over time (vegetation burns)
## - Clears vegetation in area
## - Decays over time until extinguished

## Self-reference for static factory methods and recursive spawning
const _Self = preload("res://battle_system/combat/fire_hazard.gd")

signal hazard_expired(hazard: Area3D)  # Self-reference not allowed in signals
signal unit_burned(unit: Node, damage: float)
signal spread_started(new_hazard: Area3D)  # Self-reference not allowed in signals

## Configuration
@export var duration: float = 15.0  # Total lifetime in seconds
@export var damage_per_second: float = 25.0  # DPS to units in zone
@export var suppression_per_second: float = 20.0  # Suppression applied per second
@export var spread_rate: float = 0.5  # Meters expansion per second
@export var max_radius: float = 15.0  # Maximum spread radius
@export var initial_radius: float = 5.0  # Starting radius
@export var spread_chance: float = 0.2  # Chance per second to spawn adjacent fire
@export var burn_vegetation: bool = true  # Whether fire clears vegetation

## State
var _time_alive: float = 0.0
var _current_radius: float = 5.0
var _units_in_zone: Array[Node] = []
var _spread_timer: float = 0.0
var _damage_timer: float = 0.0
var _is_active: bool = true
var _source_weapon: String = "napalm"

## Visual
var _fire_particles: GPUParticles3D = null
var _light: OmniLight3D = null
var _collision_shape: CollisionShape3D = null

## Physics layer (units)
const UNIT_LAYERS: int = 0b1110  # Layers 2, 3, 4 (US, VC, NVA)


func _ready() -> void:
	# Setup collision detection area
	_setup_collision()
	_setup_visuals()

	# Connect area signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Set initial radius
	_current_radius = initial_radius
	_update_collision_radius()


func _physics_process(delta: float) -> void:
	if not _is_active:
		return

	_time_alive += delta

	# Check expiration
	if _time_alive >= duration:
		_expire()
		return

	# Apply damage to units in zone
	_damage_timer += delta
	if _damage_timer >= 0.25:  # Damage tick every 0.25s
		_apply_damage(_damage_timer)
		_damage_timer = 0.0

	# Spread over time
	if _current_radius < max_radius:
		_current_radius = minf(_current_radius + spread_rate * delta, max_radius)
		_update_collision_radius()

	# Random spread to adjacent areas
	_spread_timer += delta
	if _spread_timer >= 1.0:
		_spread_timer = 0.0
		if randf() < spread_chance:
			_attempt_spread()

	# Update visual intensity based on remaining time
	_update_visuals(delta)

	# Clear vegetation in area
	if burn_vegetation and _time_alive > 1.0:
		_burn_vegetation()


func _setup_collision() -> void:
	# Create collision shape for area detection
	_collision_shape = CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = initial_radius
	_collision_shape.shape = sphere
	add_child(_collision_shape)

	# Configure collision layers
	collision_layer = 0  # Fire hazard doesn't need its own layer
	collision_mask = UNIT_LAYERS


func _update_collision_radius() -> void:
	if _collision_shape and _collision_shape.shape is SphereShape3D:
		(_collision_shape.shape as SphereShape3D).radius = _current_radius


func _setup_visuals() -> void:
	# Create fire light
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.1)  # Orange fire color
	_light.light_energy = 3.0
	_light.omni_range = initial_radius * 2.0
	_light.position.y = 2.0
	add_child(_light)

	# Create fire particles (if particle system available)
	_fire_particles = GPUParticles3D.new()
	_fire_particles.amount = 100
	_fire_particles.lifetime = 1.5
	_fire_particles.emitting = true

	# Simple process material for fire
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0, 1, 0)
	material.initial_velocity_min = 2.0
	material.initial_velocity_max = 5.0
	material.gravity = Vector3(0, 1, 0)  # Fire rises
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = initial_radius
	material.color = Color(1.0, 0.5, 0.1, 0.8)
	material.color_ramp = _create_fire_gradient()
	_fire_particles.process_material = material

	# Simple quad mesh for particles
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.5, 0.5)
	_fire_particles.draw_pass_1 = mesh

	add_child(_fire_particles)


func _create_fire_gradient() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.8, 0.2, 1.0))  # Yellow core
	gradient.add_point(0.3, Color(1.0, 0.4, 0.1, 0.8))  # Orange
	gradient.add_point(0.6, Color(0.8, 0.1, 0.0, 0.5))  # Red
	gradient.add_point(1.0, Color(0.2, 0.2, 0.2, 0.0))  # Smoke/fade

	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _update_visuals(_delta: float) -> void:
	# Fade intensity as fire dies
	var life_ratio: float = 1.0 - (_time_alive / duration)

	if _light:
		_light.light_energy = 3.0 * life_ratio
		_light.omni_range = _current_radius * 2.0

	if _fire_particles:
		_fire_particles.amount = int(100 * life_ratio)
		if _fire_particles.process_material is ParticleProcessMaterial:
			var mat := _fire_particles.process_material as ParticleProcessMaterial
			mat.emission_sphere_radius = _current_radius


func _apply_damage(delta_time: float) -> void:
	var damage := damage_per_second * delta_time
	var suppression := suppression_per_second * delta_time

	for unit in _units_in_zone:
		if not is_instance_valid(unit):
			continue

		# Apply burn damage
		if unit.has_method("take_damage"):
			unit.take_damage(damage, self)
			unit_burned.emit(unit, damage)

		# Apply suppression (fire is terrifying)
		if unit.has_method("apply_suppression"):
			unit.apply_suppression(suppression)
		elif "suppression_level" in unit:
			unit.suppression_level = minf(unit.suppression_level + suppression / 100.0, 1.0)

	# Clean up invalid references
	_units_in_zone = _units_in_zone.filter(func(u): return is_instance_valid(u))


func _attempt_spread() -> void:
	# Spread fire to adjacent area
	var spread_dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	var spread_pos := global_position + spread_dir * (_current_radius + 2.0)

	# Check if position is valid (on terrain, not water)
	if not _can_spread_to(spread_pos):
		return

	# Create new fire hazard
	var new_fire := _Self.new()
	new_fire.duration = duration * 0.5  # Spread fires burn shorter
	new_fire.damage_per_second = damage_per_second * 0.75
	new_fire.initial_radius = initial_radius * 0.5
	new_fire.max_radius = max_radius * 0.5
	new_fire.spread_chance = spread_chance * 0.5  # Less likely to spread further
	new_fire.global_position = spread_pos

	get_parent().add_child(new_fire)
	spread_started.emit(new_fire)


func _can_spread_to(pos: Vector3) -> bool:
	# Check terrain type at position
	if TerrainEngine and TerrainEngine.has_method("get_terrain_type_at"):
		var terrain_type = TerrainEngine.get_terrain_type_at(pos)
		# Don't spread to water or cleared areas
		if terrain_type == GameEnums.TerrainType.WATER:
			return false
		if terrain_type == GameEnums.TerrainType.CLEARED:
			return false
	return true


func _burn_vegetation() -> void:
	# Clear vegetation in the fire area
	if TerrainClearingSystem and TerrainClearingSystem.has_method("apply_clearing_damage"):
		# Fire does rapid clearing damage
		TerrainClearingSystem.apply_clearing_damage(global_position, _current_radius, 0.1)

	# Notify tree manager to remove trees
	if TreeNodeManager and TreeNodeManager.has_method("burn_trees_in_radius"):
		TreeNodeManager.burn_trees_in_radius(global_position, _current_radius)


func _expire() -> void:
	_is_active = false
	hazard_expired.emit(self)

	# Fade out over 2 seconds
	var tween := create_tween()
	if _light:
		tween.tween_property(_light, "light_energy", 0.0, 2.0)
	if _fire_particles:
		_fire_particles.emitting = false
	tween.tween_callback(queue_free)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("all_units") and body not in _units_in_zone:
		_units_in_zone.append(body)


func _on_body_exited(body: Node3D) -> void:
	var idx := _units_in_zone.find(body)
	if idx >= 0:
		_units_in_zone.remove_at(idx)


# =============================================================================
# PUBLIC API
# =============================================================================

## Create a fire hazard at position (static factory method)
static func create_at(parent: Node, pos: Vector3, radius: float = 5.0,
		duration_sec: float = 15.0, dps: float = 25.0):  # Returns FireHazard
	var fire := _Self.new()
	fire.initial_radius = radius
	fire.max_radius = radius * 3.0
	fire.duration = duration_sec
	fire.damage_per_second = dps
	fire.global_position = pos
	parent.add_child(fire)
	return fire


## Get remaining duration
func get_remaining_duration() -> float:
	return maxf(0.0, duration - _time_alive)


## Get current radius
func get_current_radius() -> float:
	return _current_radius


## Force extinguish (e.g., from rain, firefighting)
func extinguish() -> void:
	_expire()


## Check if fire is still active
func is_active() -> bool:
	return _is_active
