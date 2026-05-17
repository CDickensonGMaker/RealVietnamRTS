extends Node
class_name HealthBarManager

## Manages floating health bars for all units in the battle
## Automatically creates/destroys health bars as units spawn/die

const FloatingHealthBar = preload("res://battle_system/ui/floating_health_bar.gd")

## Configuration
@export var show_enemy_health: bool = true
@export var show_friendly_health: bool = true

## Tracking
var _health_bars: Dictionary = {}  # unit -> health_bar


func _ready() -> void:
	# Connect to unit events
	if BattleSignals:
		BattleSignals.unit_spawned.connect(_on_unit_spawned)
		BattleSignals.unit_died.connect(_on_unit_died)

	# Find existing units
	_scan_existing_units()
	print("[HealthBarManager] Initialized")


func _scan_existing_units() -> void:
	"""Find all existing units and create health bars for them"""
	var all_units: Array[Node] = get_tree().get_nodes_in_group("all_units")
	for unit in all_units:
		if unit is Node3D:
			_create_health_bar(unit)


func _on_unit_spawned(unit: Node3D, _faction: int = 0) -> void:
	"""Create health bar when unit spawns"""
	_create_health_bar(unit)


func _on_unit_died(unit: Node3D, _killer: Node3D = null) -> void:
	"""Remove health bar when unit dies"""
	_remove_health_bar(unit)


func _create_health_bar(unit: Node3D) -> void:
	"""Create a floating health bar for a unit"""
	if unit in _health_bars:
		return  # Already has one

	# Check if we should show this unit's health bar
	var is_player: bool = false
	if unit.has_method("get") and unit.get("is_player_controlled") != null:
		is_player = unit.is_player_controlled
	else:
		is_player = unit.is_in_group("player_units")

	if is_player and not show_friendly_health:
		return
	if not is_player and not show_enemy_health:
		return

	# Create the health bar
	var health_bar: Node3D = FloatingHealthBar.new()
	add_child(health_bar)
	health_bar.setup(unit)

	_health_bars[unit] = health_bar


func _remove_health_bar(unit: Node3D) -> void:
	"""Remove a unit's health bar"""
	if unit in _health_bars:
		var health_bar: Node3D = _health_bars[unit]
		if is_instance_valid(health_bar):
			health_bar.queue_free()
		_health_bars.erase(unit)


func _process(_delta: float) -> void:
	# Clean up any orphaned health bars
	var to_remove: Array = []
	for unit in _health_bars:
		if not is_instance_valid(unit):
			to_remove.append(unit)

	for unit in to_remove:
		_remove_health_bar(unit)


## Force show health bar for a specific unit
func show_health_bar(unit: Node3D) -> void:
	if unit in _health_bars:
		var bar: Node3D = _health_bars[unit]
		if bar.has_method("show_bar"):
			bar.show_bar()


## Get health bar for a unit (if exists)
func get_health_bar(unit: Node3D) -> Node3D:
	if unit in _health_bars:
		return _health_bars[unit]
	return null
