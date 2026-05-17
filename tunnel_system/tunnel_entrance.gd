extends Node3D
class_name TunnelEntrance

## Tunnel Entrance - A hidden entry/exit point in the VC tunnel network
## Units can hide, emerge for attacks, or travel underground

signal unit_entered(entrance: TunnelEntrance, unit: Node3D)
signal unit_emerged(entrance: TunnelEntrance, unit: Node3D)
signal entrance_discovered(entrance: TunnelEntrance)
signal entrance_destroyed(entrance: TunnelEntrance)

enum EntranceState { HIDDEN, DISCOVERED, DESTROYED }
enum EntranceType { STANDARD, SPIDER_HOLE, SUPPLY_CACHE, COMMAND_BUNKER }

## Configuration
@export var entrance_type: EntranceType = EntranceType.STANDARD
@export var capacity: int = 6  # How many units can hide here
@export var camouflage_rating: float = 0.8  # 0-1, higher = harder to find

## State
var state: EntranceState = EntranceState.HIDDEN
var hidden_units: Array[Node3D] = []
var connected_tunnels: Array = []  # Linked entrances
var supply_cache: float = 0.0  # For supply cache type
var discovery_progress: float = 0.0

## Network reference
var tunnel_network: Node = null


func _ready() -> void:
	add_to_group("tunnel_entrances")
	_create_visual()


func _create_visual() -> void:
	"""Create visual representation"""
	var mesh := MeshInstance3D.new()
	mesh.name = "EntranceMesh"

	# Hidden trapdoor appearance
	var box := BoxMesh.new()
	box.size = Vector3(1.5, 0.2, 1.5)
	mesh.mesh = box
	mesh.position.y = -0.05  # Slightly below ground

	var mat := StandardMaterial3D.new()
	match state:
		EntranceState.HIDDEN:
			mat.albedo_color = Color(0.3, 0.25, 0.15, 0.3)  # Camouflaged
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		EntranceState.DISCOVERED:
			mat.albedo_color = Color(0.2, 0.15, 0.1)  # Visible
		EntranceState.DESTROYED:
			mat.albedo_color = Color(0.1, 0.1, 0.1)  # Rubble

	mesh.material_override = mat
	add_child(mesh)

	# Add detection area
	var area := Area3D.new()
	area.name = "DetectionArea"

	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 3.0
	collision.shape = sphere
	area.add_child(collision)

	area.body_entered.connect(_on_body_entered)
	add_child(area)


func _on_body_entered(body: Node3D) -> void:
	"""Handle unit entering detection range"""
	if state != EntranceState.HIDDEN:
		return

	# Check if player unit
	if body.is_in_group("player_units"):
		# Chance to discover based on camouflage
		var detect_chance: float = 1.0 - camouflage_rating

		# Engineers have better detection
		if body.has_method("get") and body.get("unit_type") != null:
			if body.unit_type == GameEnums.UnitType.ENGINEERS:
				detect_chance += 0.3

		discovery_progress += detect_chance * 0.1

		if discovery_progress >= 1.0 or randf() < detect_chance * 0.1:
			discover()


func discover() -> void:
	"""Reveal this tunnel entrance"""
	if state == EntranceState.HIDDEN:
		state = EntranceState.DISCOVERED
		_update_visual()
		entrance_discovered.emit(self)
		print("[TunnelEntrance] Discovered at %s" % global_position)


func _update_visual() -> void:
	"""Update visual for current state"""
	var mesh: MeshInstance3D = get_node_or_null("EntranceMesh")
	if not mesh or not mesh.material_override:
		return

	var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D

	match state:
		EntranceState.HIDDEN:
			mat.albedo_color = Color(0.3, 0.25, 0.15, 0.3)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		EntranceState.DISCOVERED:
			mat.albedo_color = Color(0.4, 0.3, 0.2)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		EntranceState.DESTROYED:
			mat.albedo_color = Color(0.1, 0.1, 0.1)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED


## Public API

func hide_unit(unit: Node3D) -> bool:
	"""Hide a unit in this tunnel entrance"""
	if state == EntranceState.DESTROYED:
		return false

	if hidden_units.size() >= capacity:
		return false

	hidden_units.append(unit)
	unit.visible = false
	unit.set_physics_process(false)

	# Reparent to tunnel entrance
	if unit.get_parent():
		unit.get_parent().remove_child(unit)
	add_child(unit)

	unit_entered.emit(self, unit)
	return true


func emerge_unit(unit: Node3D = null) -> Node3D:
	"""Emerge a unit from the tunnel"""
	if hidden_units.is_empty():
		return null

	var emerged: Node3D
	if unit and unit in hidden_units:
		emerged = unit
		hidden_units.erase(unit)
	else:
		emerged = hidden_units.pop_back()

	# Reparent to scene
	remove_child(emerged)
	get_tree().current_scene.add_child(emerged)

	# Position at entrance with offset
	var offset := Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	emerged.global_position = global_position + offset
	emerged.visible = true
	emerged.set_physics_process(true)

	unit_emerged.emit(self, emerged)
	return emerged


func emerge_all() -> Array[Node3D]:
	"""Emerge all hidden units"""
	var emerged: Array[Node3D] = []
	while not hidden_units.is_empty():
		var unit: Node3D = emerge_unit()
		if unit:
			emerged.append(unit)
	return emerged


func destroy() -> void:
	"""Destroy this tunnel entrance"""
	if state == EntranceState.DESTROYED:
		return

	# Kill/strand any hidden units
	for unit in hidden_units:
		if is_instance_valid(unit) and unit.has_method("take_damage"):
			unit.take_damage(9999, null)
	hidden_units.clear()

	state = EntranceState.DESTROYED
	_update_visual()
	entrance_destroyed.emit(self)

	# Notify network
	if tunnel_network and tunnel_network.has_method("_on_entrance_destroyed"):
		tunnel_network._on_entrance_destroyed(self)


func connect_to(other: TunnelEntrance) -> void:
	"""Connect to another tunnel entrance"""
	if other not in connected_tunnels:
		connected_tunnels.append(other)
	if self not in other.connected_tunnels:
		other.connected_tunnels.append(self)


func get_travel_time_to(other: TunnelEntrance) -> float:
	"""Get underground travel time to another entrance"""
	if other not in connected_tunnels:
		return -1.0  # Not connected

	var distance: float = global_position.distance_to(other.global_position)
	return distance / 5.0  # 5 m/s underground movement


func can_accept_units() -> bool:
	return state != EntranceState.DESTROYED and hidden_units.size() < capacity


func get_hidden_count() -> int:
	return hidden_units.size()


func is_discovered() -> bool:
	return state == EntranceState.DISCOVERED


func is_destroyed() -> bool:
	return state == EntranceState.DESTROYED
