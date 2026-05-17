extends Node
## Manages floating unit labels for all units in the battle.
## Creates/destroys labels as units spawn/die. Culls distant labels.

const FloatingUnitLabel = preload("res://battle_system/ui/floating_unit_label.gd")

# =============================================================================
# CONFIGURATION
# =============================================================================

## Show labels for enemy units
@export var show_enemy_labels: bool = true

## Show labels for friendly units
@export var show_friendly_labels: bool = true

## Labels beyond this distance are hidden (culled)
@export var label_culling_distance: float = 200.0

## How often to run culling checks (seconds)
const CULLING_INTERVAL: float = 0.5

# =============================================================================
# STATE
# =============================================================================

## Tracking: unit -> label
var _labels: Dictionary = {}

## Culling timer
var _culling_timer: float = 0.0

## Cached camera reference
var _camera: Camera3D = null


func _ready() -> void:
	# Connect to unit events
	if BattleSignals:
		BattleSignals.unit_spawned.connect(_on_unit_spawned)
		BattleSignals.unit_died.connect(_on_unit_died)

	# Find existing units
	_scan_existing_units()
	print("[FloatingLabelManager] Initialized")


func _process(delta: float) -> void:
	# Update camera reference
	if not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()

	# Periodic culling and orphan cleanup (batched for performance)
	_culling_timer -= delta
	if _culling_timer <= 0.0:
		_culling_timer = CULLING_INTERVAL
		_cleanup_orphans()  # Clean orphans first
		_perform_culling()


func _scan_existing_units() -> void:
	## Find all existing units and create labels for them
	var all_units: Array[Node] = get_tree().get_nodes_in_group("all_units")
	for unit in all_units:
		if unit is Node3D:
			_create_label(unit)


func _on_unit_spawned(unit: Node3D, _faction: int = 0) -> void:
	## Create label when unit spawns
	_create_label(unit)


func _on_unit_died(unit: Node3D, _killer: Node3D = null) -> void:
	## Remove label when unit dies
	_remove_label(unit)


func _create_label(unit: Node3D) -> void:
	## Create a floating label for a unit
	if unit in _labels:
		return  # Already has one

	# Check if we should show this unit's label
	var is_player: bool = false
	if unit.has_method("get") and unit.get("is_player_controlled") != null:
		is_player = unit.is_player_controlled
	else:
		is_player = unit.is_in_group("player_units")

	if is_player and not show_friendly_labels:
		return
	if not is_player and not show_enemy_labels:
		return

	# Create the label
	var label: Node3D = FloatingUnitLabel.new()
	add_child(label)
	label.setup(unit)

	_labels[unit] = label


func _remove_label(unit: Node3D) -> void:
	## Remove a unit's label
	if unit in _labels:
		var label: Node3D = _labels[unit]
		if is_instance_valid(label):
			label.queue_free()
		_labels.erase(unit)


func _perform_culling() -> void:
	## Hide/show labels based on camera distance
	if not is_instance_valid(_camera):
		return

	var camera_pos: Vector3 = _camera.global_position

	for unit in _labels:
		if not is_instance_valid(unit):
			continue

		var label: Node3D = _labels[unit]
		if not is_instance_valid(label):
			continue

		var dist: float = unit.global_position.distance_to(camera_pos)
		label.visible = dist <= label_culling_distance


func _cleanup_orphans() -> void:
	## Remove labels for freed units
	var to_remove: Array = []
	for unit in _labels:
		if not is_instance_valid(unit):
			to_remove.append(unit)

	for unit in to_remove:
		_remove_label(unit)


# =============================================================================
# PUBLIC API
# =============================================================================

## Force show label for a specific unit
func show_label(unit: Node3D) -> void:
	if unit in _labels:
		var label: Node3D = _labels[unit]
		if label.has_method("show_label"):
			label.show_label()


## Get label for a unit (if exists)
func get_label(unit: Node3D) -> Node3D:
	if unit in _labels:
		return _labels[unit]
	return null


## Refresh all labels (call after settings change)
func refresh_all() -> void:
	# Clear existing
	for unit in _labels.keys():
		_remove_label(unit)

	# Recreate
	_scan_existing_units()


## Toggle enemy label visibility
func set_show_enemy_labels(enabled: bool) -> void:
	show_enemy_labels = enabled
	refresh_all()


## Toggle friendly label visibility
func set_show_friendly_labels(enabled: bool) -> void:
	show_friendly_labels = enabled
	refresh_all()


## Set culling distance
func set_culling_distance(distance: float) -> void:
	label_culling_distance = distance
