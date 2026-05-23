class_name TrenchNode
extends Area3D
## TrenchNode - A defensive trench that provides cover to units inside
##
## Trenches are linear defensive positions that:
## - Provide cover to units standing inside
## - Can be extended to connect with other trenches
## - Have visual carved earth appearance

signal trench_dug()
signal trench_progress(progress: float)
signal trench_complete()
signal unit_entered_trench(unit: Node3D)
signal unit_exited_trench(unit: Node3D)

## Cover value provided (0.0 = none, 1.0 = full)
const TRENCH_COVER_VALUE: float = 0.7  # Heavy cover

## Trench dimensions
@export var length: float = 8.0
@export var width: float = 2.0
@export var depth: float = 1.5

## Current dig progress (0.0 to 1.0)
var current_progress: float = 0.0

## Whether digging has started
var is_digging: bool = false

## Whether trench is complete
var is_complete: bool = false

## Units currently in the trench
var units_inside: Array[Node3D] = []

## Connected trenches (for network building)
var connected_trenches: Array[TrenchNode] = []

## Visual components
var trench_mesh: MeshInstance3D
var dirt_pile_mesh: MeshInstance3D
var outline_mesh: MeshInstance3D

## Collision shape for detection
var collision_shape: CollisionShape3D
var box_shape: BoxShape3D

## Materials
var _trench_material: StandardMaterial3D
var _dirt_material: StandardMaterial3D
var _outline_material: StandardMaterial3D


func _ready() -> void:
	# Set up collision layers
	# Layer 7 = buildings (bit 64)
	collision_layer = 64
	collision_mask = 2 | 4 | 8  # Detect US, VC, NVA units

	# Add to groups
	add_to_group("trenches")
	add_to_group("cover_providers")

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Create collision shape
	_setup_collision()

	# Create visuals
	_setup_visuals()

	# Snap to terrain
	_snap_to_terrain()


func _setup_collision() -> void:
	collision_shape = CollisionShape3D.new()
	box_shape = BoxShape3D.new()
	box_shape.size = Vector3(length, depth, width)
	collision_shape.shape = box_shape
	collision_shape.position.y = -depth * 0.5
	add_child(collision_shape)


func _setup_visuals() -> void:
	# Trench wall material (dark earth)
	_trench_material = StandardMaterial3D.new()
	_trench_material.albedo_color = Color(0.3, 0.25, 0.15)
	_trench_material.roughness = 1.0

	# Dirt pile material (lighter earth)
	_dirt_material = StandardMaterial3D.new()
	_dirt_material.albedo_color = Color(0.45, 0.35, 0.2)
	_dirt_material.roughness = 0.95

	# Create trench mesh (starts empty, builds as progress increases)
	trench_mesh = MeshInstance3D.new()
	trench_mesh.material_override = _trench_material
	trench_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	trench_mesh.visible = false
	add_child(trench_mesh)

	# Create dirt pile mesh (excavated earth along edges)
	dirt_pile_mesh = MeshInstance3D.new()
	dirt_pile_mesh.material_override = _dirt_material
	dirt_pile_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	dirt_pile_mesh.visible = false
	add_child(dirt_pile_mesh)

	# Outline material (planning line)
	_outline_material = StandardMaterial3D.new()
	_outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_material.albedo_color = Color(0.4, 0.3, 0.2, 0.6)
	_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Create outline
	outline_mesh = MeshInstance3D.new()
	outline_mesh.mesh = _create_outline_mesh()
	outline_mesh.material_override = _outline_material
	outline_mesh.position.y = 0.05
	add_child(outline_mesh)


func _snap_to_terrain() -> void:
	var terrain: Node = get_node_or_null("/root/UnifiedTerrain")
	if terrain and terrain.has_method("get_height_at"):
		position.y = terrain.get_height_at(global_position)
		return

	var terrain_intg: Node = get_node_or_null("/root/TerrainIntegration")
	if terrain_intg and terrain_intg.has_method("get_height_at"):
		position.y = terrain_intg.get_height_at(global_position)


func _on_body_entered(body: Node3D) -> void:
	if not is_complete:
		return

	if body.is_in_group("all_units") or body.is_in_group("squads"):
		if body not in units_inside:
			units_inside.append(body)
			unit_entered_trench.emit(body)
			_apply_cover_to_unit(body, true)


func _on_body_exited(body: Node3D) -> void:
	if body in units_inside:
		units_inside.erase(body)
		unit_exited_trench.emit(body)
		_apply_cover_to_unit(body, false)


func _apply_cover_to_unit(unit: Node3D, entering: bool) -> void:
	## Apply or remove cover bonus from unit
	if unit.has_method("set_cover_bonus"):
		if entering:
			unit.set_cover_bonus(TRENCH_COVER_VALUE)
		else:
			unit.set_cover_bonus(0.0)
	elif "cover_bonus" in unit:
		unit.cover_bonus = TRENCH_COVER_VALUE if entering else 0.0


## Add work progress (called by workers)
## Returns true if digging is complete
func add_work(amount: float) -> bool:
	if not is_digging:
		is_digging = true
		trench_dug.emit()

	var new_progress: float = minf(current_progress + amount, 1.0)

	if new_progress != current_progress:
		current_progress = new_progress
		_update_visuals()
		trench_progress.emit(current_progress)

	if current_progress >= 1.0:
		_complete()
		return true

	return false


func _update_visuals() -> void:
	# Show trench mesh after 10% progress
	if current_progress > 0.1:
		trench_mesh.visible = true
		trench_mesh.mesh = _create_trench_mesh(current_progress)

		dirt_pile_mesh.visible = true
		dirt_pile_mesh.mesh = _create_dirt_pile_mesh(current_progress)

	# Fade outline as trench progresses
	_outline_material.albedo_color.a = lerpf(0.6, 0.2, current_progress)


func _complete() -> void:
	is_digging = false
	is_complete = true

	# Final visual update
	trench_mesh.mesh = _create_trench_mesh(1.0)
	dirt_pile_mesh.mesh = _create_dirt_pile_mesh(1.0)

	# Hide outline
	outline_mesh.visible = false

	trench_complete.emit()
	print("[TrenchNode] Complete! Length %.1fm at %s" % [length, global_position])


## Get cover value for units in this trench
func get_cover_value() -> float:
	return TRENCH_COVER_VALUE if is_complete else 0.0


## Check if a position is inside the trench
func is_position_inside(pos: Vector3) -> bool:
	var local_pos: Vector3 = to_local(pos)
	return absf(local_pos.x) <= length * 0.5 and absf(local_pos.z) <= width * 0.5


## Connect to another trench
func connect_to(other: TrenchNode) -> void:
	if other and other not in connected_trenches:
		connected_trenches.append(other)
		other.connected_trenches.append(self)


## Get progress as 0.0 - 1.0
func get_progress() -> float:
	return current_progress


## Create trench mesh (carved depression)
func _create_trench_mesh(progress: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hl: float = length * 0.5
	var hw: float = width * 0.5
	var d: float = depth * progress

	if d < 0.1:
		d = 0.1

	# Trench floor
	st.add_vertex(Vector3(-hl, -d, -hw))
	st.add_vertex(Vector3(hl, -d, -hw))
	st.add_vertex(Vector3(hl, -d, hw))
	st.add_vertex(Vector3(-hl, -d, -hw))
	st.add_vertex(Vector3(hl, -d, hw))
	st.add_vertex(Vector3(-hl, -d, hw))

	# Front wall (internal)
	st.add_vertex(Vector3(-hl, 0, -hw))
	st.add_vertex(Vector3(-hl, -d, -hw))
	st.add_vertex(Vector3(hl, -d, -hw))
	st.add_vertex(Vector3(-hl, 0, -hw))
	st.add_vertex(Vector3(hl, -d, -hw))
	st.add_vertex(Vector3(hl, 0, -hw))

	# Back wall (internal)
	st.add_vertex(Vector3(hl, 0, hw))
	st.add_vertex(Vector3(hl, -d, hw))
	st.add_vertex(Vector3(-hl, -d, hw))
	st.add_vertex(Vector3(hl, 0, hw))
	st.add_vertex(Vector3(-hl, -d, hw))
	st.add_vertex(Vector3(-hl, 0, hw))

	# Left end wall
	st.add_vertex(Vector3(-hl, 0, hw))
	st.add_vertex(Vector3(-hl, -d, hw))
	st.add_vertex(Vector3(-hl, -d, -hw))
	st.add_vertex(Vector3(-hl, 0, hw))
	st.add_vertex(Vector3(-hl, -d, -hw))
	st.add_vertex(Vector3(-hl, 0, -hw))

	# Right end wall
	st.add_vertex(Vector3(hl, 0, -hw))
	st.add_vertex(Vector3(hl, -d, -hw))
	st.add_vertex(Vector3(hl, -d, hw))
	st.add_vertex(Vector3(hl, 0, -hw))
	st.add_vertex(Vector3(hl, -d, hw))
	st.add_vertex(Vector3(hl, 0, hw))

	st.generate_normals()
	return st.commit()


## Create dirt pile mesh (excavated earth)
func _create_dirt_pile_mesh(progress: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hl: float = length * 0.5
	var hw: float = width * 0.5
	var pile_width: float = 0.5
	var pile_height: float = depth * 0.4 * progress

	if pile_height < 0.05:
		pile_height = 0.05

	# Front pile (along -Z edge)
	_add_dirt_pile_segment(st, Vector3(-hl, 0, -hw - pile_width * 0.5), hl * 2, pile_width, pile_height)

	# Back pile (along +Z edge)
	_add_dirt_pile_segment(st, Vector3(-hl, 0, hw + pile_width * 0.5), hl * 2, pile_width, pile_height)

	st.generate_normals()
	return st.commit()


func _add_dirt_pile_segment(st: SurfaceTool, start: Vector3, seg_length: float, seg_width: float, height: float) -> void:
	## Add a mound of dirt along a line
	var hw: float = seg_width * 0.5

	# Triangular cross-section mound
	# Front face
	st.add_vertex(start + Vector3(0, 0, -hw))
	st.add_vertex(start + Vector3(seg_length, 0, -hw))
	st.add_vertex(start + Vector3(seg_length * 0.5, height, 0))

	st.add_vertex(start + Vector3(0, 0, -hw))
	st.add_vertex(start + Vector3(seg_length * 0.5, height, 0))
	st.add_vertex(start + Vector3(0, height * 0.5, -hw * 0.3))

	# Back face
	st.add_vertex(start + Vector3(seg_length, 0, hw))
	st.add_vertex(start + Vector3(0, 0, hw))
	st.add_vertex(start + Vector3(seg_length * 0.5, height, 0))

	st.add_vertex(start + Vector3(0, 0, hw))
	st.add_vertex(start + Vector3(0, height * 0.5, hw * 0.3))
	st.add_vertex(start + Vector3(seg_length * 0.5, height, 0))

	# Top ridge
	st.add_vertex(start + Vector3(0, height * 0.5, -hw * 0.3))
	st.add_vertex(start + Vector3(seg_length * 0.5, height, 0))
	st.add_vertex(start + Vector3(0, height * 0.5, hw * 0.3))


## Create outline mesh
func _create_outline_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var hl: float = length * 0.5
	var hw: float = width * 0.5

	# Rectangle outline
	st.add_vertex(Vector3(-hl, 0, -hw))
	st.add_vertex(Vector3(hl, 0, -hw))

	st.add_vertex(Vector3(hl, 0, -hw))
	st.add_vertex(Vector3(hl, 0, hw))

	st.add_vertex(Vector3(hl, 0, hw))
	st.add_vertex(Vector3(-hl, 0, hw))

	st.add_vertex(Vector3(-hl, 0, hw))
	st.add_vertex(Vector3(-hl, 0, -hw))

	return st.commit()


## Factory: Create a trench at a position
static func create(world_position: Vector3, trench_length: float = 8.0, trench_width: float = 2.0, rotation_y: float = 0.0) -> TrenchNode:
	var trench := TrenchNode.new()
	trench.position = world_position
	trench.length = trench_length
	trench.width = trench_width
	if rotation_y != 0.0:
		trench.rotate_y(rotation_y)
	return trench
