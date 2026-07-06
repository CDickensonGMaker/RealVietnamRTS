class_name SuppressionZone extends Area3D
## SuppressionZone - Persistent area suppression effect (beaten zones)
##
## Used for:
## - Machine gun sustained fire (creates suppressed area)
## - Artillery barrage (pre-impact suppression)
## - Overwatch/suppressive fire mechanic
##
## Units in the zone accumulate suppression over time.
## Zone decays after weapon stops firing or duration expires.

## Self-reference for static factory methods
const _Self = preload("res://battle_system/combat/suppression_zone.gd")

signal zone_expired(zone: Area3D)  # Self-reference not allowed in signals
signal unit_suppressed(unit: Node, amount: float)

## Configuration
@export var duration: float = 3.0  # Lifetime after last refresh
@export var suppression_per_second: float = 15.0  # Suppression applied per second
@export var initial_radius: float = 5.0  # Zone radius
@export var fear_type: int = 0  # GameEnums.FearType for morale effects

## State
var _time_since_refresh: float = 0.0
var _units_in_zone: Array[Node] = []
var _is_active: bool = true
var _suppression_timer: float = 0.0
var _source_weapon: String = ""
var _source_unit: Node = null

## Visual
var _zone_indicator: MeshInstance3D = null
var _collision_shape: CollisionShape3D = null

## Physics layer (units)
const UNIT_LAYERS: int = 0b1110  # Layers 2, 3, 4 (US, VC, NVA)


func _ready() -> void:
	_setup_collision()
	_setup_visuals()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	if not _is_active:
		return

	_time_since_refresh += delta

	# Check expiration
	if _time_since_refresh >= duration:
		_expire()
		return

	# Apply suppression to units in zone
	_suppression_timer += delta
	if _suppression_timer >= 0.2:  # Suppression tick every 0.2s
		_apply_suppression(_suppression_timer)
		_suppression_timer = 0.0

	# Fade visual indicator
	_update_visuals()


func _setup_collision() -> void:
	_collision_shape = CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = initial_radius
	cylinder.height = 4.0  # Tall enough to catch all units
	_collision_shape.shape = cylinder
	add_child(_collision_shape)

	collision_layer = 0
	collision_mask = UNIT_LAYERS


func _setup_visuals() -> void:
	# Create a subtle ground indicator (danger zone)
	_zone_indicator = MeshInstance3D.new()

	var mesh := CylinderMesh.new()
	mesh.top_radius = initial_radius
	mesh.bottom_radius = initial_radius
	mesh.height = 0.1  # Flat disc
	_zone_indicator.mesh = mesh

	# Red transparent material
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.2, 0.2, 0.3)  # Red, semi-transparent
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_zone_indicator.material_override = material

	_zone_indicator.position.y = 0.1  # Slightly above ground
	add_child(_zone_indicator)


func _update_visuals() -> void:
	if not _zone_indicator:
		return

	# Fade based on remaining time
	var life_ratio: float = 1.0 - (_time_since_refresh / duration)
	var mat := _zone_indicator.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color.a = 0.3 * life_ratio


func _apply_suppression(delta_time: float) -> void:
	var suppression_amount := suppression_per_second * delta_time

	for unit in _units_in_zone:
		if not is_instance_valid(unit):
			continue

		# Apply suppression with fear type for morale effects
		if unit.has_method("apply_suppression_with_fear") and fear_type > 0:
			unit.apply_suppression_with_fear(suppression_amount, fear_type)
		elif unit.has_method("apply_suppression"):
			unit.apply_suppression(suppression_amount)
		elif "suppression_level" in unit:
			# Direct manipulation if no method available
			unit.suppression_level = minf(unit.suppression_level + suppression_amount / 100.0, 1.0)

		unit_suppressed.emit(unit, suppression_amount)

	# Clean up invalid references
	_units_in_zone = _units_in_zone.filter(func(u): return is_instance_valid(u))


func _expire() -> void:
	_is_active = false
	zone_expired.emit(self)
	queue_free()


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

## Refresh the zone (reset expiration timer).
## Call this when weapon continues firing to maintain the zone.
func refresh() -> void:
	_time_since_refresh = 0.0


## Set the zone radius
func set_radius(radius: float) -> void:
	initial_radius = radius
	if _collision_shape and _collision_shape.shape is CylinderShape3D:
		(_collision_shape.shape as CylinderShape3D).radius = radius
	if _zone_indicator and _zone_indicator.mesh is CylinderMesh:
		var mesh := _zone_indicator.mesh as CylinderMesh
		mesh.top_radius = radius
		mesh.bottom_radius = radius


## Set suppression intensity
func set_intensity(sps: float) -> void:
	suppression_per_second = sps


## Create a suppression zone at position (static factory method)
static func create_at(parent: Node, pos: Vector3, radius: float = 5.0,
		duration_sec: float = 3.0, sps: float = 15.0):  # Returns SuppressionZone
	var zone := _Self.new()
	zone.initial_radius = radius
	zone.duration = duration_sec
	zone.suppression_per_second = sps
	zone.global_position = pos
	parent.add_child(zone)
	return zone


## Create or refresh a suppression zone (for sustained fire)
## Returns the zone - caller should cache and call refresh() each fire tick
static func create_or_refresh(existing, parent: Node, pos: Vector3,
		radius: float = 5.0, duration_sec: float = 3.0, sps: float = 15.0):  # Returns SuppressionZone
	if existing and is_instance_valid(existing) and existing._is_active:
		existing.global_position = pos
		existing.refresh()
		return existing

	return create_at(parent, pos, radius, duration_sec, sps)


## Check if zone is active
func is_active() -> bool:
	return _is_active


## Force expire
func cancel() -> void:
	_expire()
