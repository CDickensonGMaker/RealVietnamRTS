class_name Trench extends Node3D
## Trench - Linear defensive position carved into terrain.
##
## Unlike a Bunker (which is a structure), a Trench is a linked sequence of
## occupancy slots along a path. The actual terrain deformation is handled
## by EngineeringSystem.DIG_TRENCH; this class manages who's in the trench
## and what cover bonus they get.
##
## Squads "stashed" in a trench:
##   - Are visible but prone (lowered visual)
##   - Get heavy cover bonus (60-70%) to incoming fire
##   - Get +10% accuracy bonus (rest position)
##   - Move at reduced speed if they continue along the trench
##
## Trench is created by passing in the path points after EngineeringSystem
## carves the actual ground.

signal squad_entered(squad: Node3D, slot_index: int)
signal squad_left(squad: Node3D, slot_index: int)

@export var trench_name: String = "Trench"
@export var cover_bonus: float = 0.65  # 65% damage reduction
@export var accuracy_bonus: float = 0.1
@export var slot_spacing: float = 3.0   # Meters between occupancy slots

## Path defining the trench (world coordinates)
var path_points: PackedVector3Array = []

## Occupancy: slot_index -> squad node
var occupied_slots: Dictionary = {}

## Ownership
var is_player_controlled: bool = true

## Visual
var _trench_line: MeshInstance3D = null


func _ready() -> void:
	add_to_group("trenches")
	add_to_group("fortifications")
	add_to_group("all_units")
	if is_player_controlled:
		add_to_group("player_structures")
		add_to_group("selectable_units")
	else:
		add_to_group("enemy_structures")


## Set up the trench from a list of world-space points.
## This should be called after EngineeringSystem.DIG_TRENCH has carved the ground.
func set_path(points: PackedVector3Array) -> void:
	path_points = points
	_build_placeholder_visual()


func _build_placeholder_visual() -> void:
	if _trench_line:
		_trench_line.queue_free()

	if path_points.size() < 2:
		return

	# Visualize the trench as a series of dark rectangles along the path
	var container := Node3D.new()
	container.name = "TrenchVisual"
	add_child(container)
	_trench_line = MeshInstance3D.new()

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in path_points.size() - 1:
		im.surface_add_vertex(path_points[i] - global_position)
		im.surface_add_vertex(path_points[i + 1] - global_position)
	im.surface_end()

	var line := MeshInstance3D.new()
	line.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.15, 0.1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.material_override = mat
	container.add_child(line)


## Get the nearest available occupancy slot to a position.
## Returns slot_index, or -1 if none available.
func find_available_slot(world_pos: Vector3) -> int:
	if path_points.size() < 2:
		return -1

	var slot_count: int = _get_slot_count()
	var best_idx: int = -1
	var best_dist: float = 1e9
	for i in slot_count:
		if i in occupied_slots:
			continue
		var slot_pos: Vector3 = _get_slot_position(i)
		var d: float = slot_pos.distance_to(world_pos)
		if d < best_dist:
			best_dist = d
			best_idx = i
	return best_idx


func _get_slot_count() -> int:
	if path_points.size() < 2:
		return 0
	var total_len: float = 0.0
	for i in path_points.size() - 1:
		total_len += path_points[i].distance_to(path_points[i + 1])
	return max(1, int(total_len / slot_spacing))


func _get_slot_position(slot_index: int) -> Vector3:
	if path_points.size() < 2:
		return Vector3.ZERO
	var target_dist: float = float(slot_index) * slot_spacing + slot_spacing * 0.5
	var traveled: float = 0.0
	for i in path_points.size() - 1:
		var seg_len: float = path_points[i].distance_to(path_points[i + 1])
		if traveled + seg_len >= target_dist:
			var t: float = (target_dist - traveled) / seg_len
			return path_points[i].lerp(path_points[i + 1], t)
		traveled += seg_len
	return path_points[path_points.size() - 1]


## Load a squad into the trench at the nearest available slot.
func enter_trench(squad: Node3D) -> bool:
	var slot: int = find_available_slot(squad.global_position)
	if slot < 0:
		return false
	occupied_slots[slot] = squad

	var slot_pos: Vector3 = _get_slot_position(slot)
	squad.global_position = slot_pos
	if squad.has_method("set"):
		squad.set("is_in_cover", true)
		squad.set("is_prone", true)

	squad_entered.emit(squad, slot)
	return true


func leave_trench(squad: Node3D) -> bool:
	var slot_to_clear: int = -1
	for slot in occupied_slots:
		if occupied_slots[slot] == squad:
			slot_to_clear = slot
			break
	if slot_to_clear < 0:
		return false
	occupied_slots.erase(slot_to_clear)
	if squad.has_method("set"):
		squad.set("is_in_cover", false)
		squad.set("is_prone", false)
	squad_left.emit(squad, slot_to_clear)
	return true


func get_cover_bonus_for(squad: Node3D) -> float:
	for slot in occupied_slots:
		if occupied_slots[slot] == squad:
			return cover_bonus
	return 0.0


func get_occupants() -> Array[Node3D]:
	var list: Array[Node3D] = []
	for slot in occupied_slots:
		list.append(occupied_slots[slot])
	return list
