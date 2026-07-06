class_name CraterNode
extends Area3D
## CraterNode - An explosion crater that provides cover
##
## Craters are created by explosions and:
## - Provide cover to units inside
## - Can be filled by workers (FILL_CRATER job)
## - Have visual depressed terrain with rim

signal crater_created()
signal crater_filled()
signal unit_entered_crater(unit: Node3D)
signal unit_exited_crater(unit: Node3D)

## Cover value provided (0.0 = none, 1.0 = full)
const CRATER_COVER_VALUE: float = 0.5  # Medium cover

## Crater dimensions
@export var radius: float = 3.0
@export var depth: float = 1.0

## Fill progress (0.0 = empty, 1.0 = filled)
var fill_progress: float = 0.0

## Whether filling has started
var is_filling: bool = false

## Whether crater is filled (destroyed)
var is_filled: bool = false

## Units currently in the crater
var units_inside: Array[Node3D] = []

## Visual components
var crater_mesh: MeshInstance3D
var rim_mesh: MeshInstance3D
var outline_mesh: MeshInstance3D

## Collision shape
var collision_shape: CollisionShape3D
var cylinder_shape: CylinderShape3D

## Materials
var _crater_material: StandardMaterial3D
var _rim_material: StandardMaterial3D
var _outline_material: StandardMaterial3D


func _ready() -> void:
	# Set up collision layers
	# Layer 7 = buildings (bit 64)
	collision_layer = 64
	collision_mask = 2 | 4 | 8  # Detect US, VC, NVA units

	# Add to groups
	add_to_group("craters")
	add_to_group("cover_providers")
	add_to_group("terrain_damage")

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Create collision shape
	_setup_collision()

	# Create visuals
	_setup_visuals()

	# Snap to terrain
	_snap_to_terrain()

	crater_created.emit()


func _setup_collision() -> void:
	collision_shape = CollisionShape3D.new()
	cylinder_shape = CylinderShape3D.new()
	cylinder_shape.radius = radius
	cylinder_shape.height = depth
	collision_shape.shape = cylinder_shape
	collision_shape.position.y = -depth * 0.5
	add_child(collision_shape)


func _setup_visuals() -> void:
	# Crater material (scorched earth)
	_crater_material = StandardMaterial3D.new()
	_crater_material.albedo_color = Color(0.2, 0.18, 0.15)
	_crater_material.roughness = 1.0
	_crater_material.metallic = 0.0

	# Rim material (displaced dirt)
	_rim_material = StandardMaterial3D.new()
	_rim_material.albedo_color = Color(0.4, 0.32, 0.22)
	_rim_material.roughness = 0.95

	# Create crater mesh
	crater_mesh = MeshInstance3D.new()
	crater_mesh.mesh = _create_crater_mesh()
	crater_mesh.material_override = _crater_material
	crater_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(crater_mesh)

	# Create rim mesh
	rim_mesh = MeshInstance3D.new()
	rim_mesh.mesh = _create_rim_mesh()
	rim_mesh.material_override = _rim_material
	rim_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(rim_mesh)

	# Outline (for targeting)
	_outline_material = StandardMaterial3D.new()
	_outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_material.albedo_color = Color(0.3, 0.25, 0.2, 0.3)
	_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	outline_mesh = MeshInstance3D.new()
	outline_mesh.mesh = _create_outline_mesh()
	outline_mesh.material_override = _outline_material
	outline_mesh.position.y = 0.05
	outline_mesh.visible = false  # Only show when selected
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
	if is_filled:
		return

	if body.is_in_group("all_units") or body.is_in_group("squads"):
		if body not in units_inside:
			units_inside.append(body)
			unit_entered_crater.emit(body)
			_apply_cover_to_unit(body, true)


func _on_body_exited(body: Node3D) -> void:
	if body in units_inside:
		units_inside.erase(body)
		unit_exited_crater.emit(body)
		_apply_cover_to_unit(body, false)


func _apply_cover_to_unit(unit: Node3D, entering: bool) -> void:
	## Apply or remove cover bonus from unit
	if unit.has_method("set_cover_bonus"):
		if entering:
			unit.set_cover_bonus(CRATER_COVER_VALUE)
		else:
			unit.set_cover_bonus(0.0)
	elif "cover_bonus" in unit:
		unit.cover_bonus = CRATER_COVER_VALUE if entering else 0.0


## Add work to fill the crater (called by workers)
## Returns true if crater is now filled
func add_work(amount: float) -> bool:
	if not is_filling:
		is_filling = true

	var new_progress: float = minf(fill_progress + amount, 1.0)

	if new_progress != fill_progress:
		fill_progress = new_progress
		_update_visuals()

	if fill_progress >= 1.0:
		_complete_fill()
		return true

	return false


func _update_visuals() -> void:
	# Shrink crater depth as it fills
	var remaining_depth: float = depth * (1.0 - fill_progress)

	# Update collision
	cylinder_shape.height = maxf(remaining_depth, 0.1)
	collision_shape.position.y = -remaining_depth * 0.5

	# Update meshes
	crater_mesh.mesh = _create_crater_mesh_at_depth(remaining_depth)

	# Rim shrinks too
	rim_mesh.scale = Vector3.ONE * (1.0 - fill_progress * 0.7)

	# Crater gets lighter (filled with fresh dirt)
	_crater_material.albedo_color = Color(
		lerpf(0.2, 0.4, fill_progress),
		lerpf(0.18, 0.32, fill_progress),
		lerpf(0.15, 0.22, fill_progress)
	)


func _complete_fill() -> void:
	is_filling = false
	is_filled = true

	# Release units
	for unit in units_inside:
		if is_instance_valid(unit):
			_apply_cover_to_unit(unit, false)

	crater_filled.emit()
	print("[CraterNode] Filled at %s" % global_position)

	queue_free()


## Get cover value for units in this crater
func get_cover_value() -> float:
	if is_filled:
		return 0.0
	# Cover decreases as crater fills
	return CRATER_COVER_VALUE * (1.0 - fill_progress)


## Get fill progress as 0.0 - 1.0
func get_fill_progress() -> float:
	return fill_progress


## Show/hide selection outline
func set_selected(selected: bool) -> void:
	outline_mesh.visible = selected


## Create crater depression mesh
func _create_crater_mesh() -> ArrayMesh:
	return _create_crater_mesh_at_depth(depth)


func _create_crater_mesh_at_depth(d: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var segments: int = 16

	# Crater floor (center disc)
	var floor_radius: float = radius * 0.3
	for i in range(segments):
		var angle1: float = TAU * float(i) / float(segments)
		var angle2: float = TAU * float(i + 1) / float(segments)

		var x1: float = cos(angle1) * floor_radius
		var z1: float = sin(angle1) * floor_radius
		var x2: float = cos(angle2) * floor_radius
		var z2: float = sin(angle2) * floor_radius

		st.add_vertex(Vector3(0, -d, 0))
		st.add_vertex(Vector3(x1, -d, z1))
		st.add_vertex(Vector3(x2, -d, z2))

	# Crater walls (slope from floor to rim)
	for i in range(segments):
		var angle1: float = TAU * float(i) / float(segments)
		var angle2: float = TAU * float(i + 1) / float(segments)

		var inner_x1: float = cos(angle1) * floor_radius
		var inner_z1: float = sin(angle1) * floor_radius
		var inner_x2: float = cos(angle2) * floor_radius
		var inner_z2: float = sin(angle2) * floor_radius

		var outer_x1: float = cos(angle1) * radius
		var outer_z1: float = sin(angle1) * radius
		var outer_x2: float = cos(angle2) * radius
		var outer_z2: float = sin(angle2) * radius

		# Quad as two triangles
		st.add_vertex(Vector3(inner_x1, -d, inner_z1))
		st.add_vertex(Vector3(outer_x1, 0, outer_z1))
		st.add_vertex(Vector3(outer_x2, 0, outer_z2))

		st.add_vertex(Vector3(inner_x1, -d, inner_z1))
		st.add_vertex(Vector3(outer_x2, 0, outer_z2))
		st.add_vertex(Vector3(inner_x2, -d, inner_z2))

	st.generate_normals()
	return st.commit()


## Create rim mesh (raised edge)
func _create_rim_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var segments: int = 16
	var rim_inner: float = radius
	var rim_outer: float = radius * 1.3
	var rim_height: float = depth * 0.3

	for i in range(segments):
		var angle1: float = TAU * float(i) / float(segments)
		var angle2: float = TAU * float(i + 1) / float(segments)

		var inner_x1: float = cos(angle1) * rim_inner
		var inner_z1: float = sin(angle1) * rim_inner
		var inner_x2: float = cos(angle2) * rim_inner
		var inner_z2: float = sin(angle2) * rim_inner

		var outer_x1: float = cos(angle1) * rim_outer
		var outer_z1: float = sin(angle1) * rim_outer
		var outer_x2: float = cos(angle2) * rim_outer
		var outer_z2: float = sin(angle2) * rim_outer

		# Top face (sloped outward)
		st.add_vertex(Vector3(inner_x1, rim_height * 0.5, inner_z1))
		st.add_vertex(Vector3(outer_x1, 0, outer_z1))
		st.add_vertex(Vector3(outer_x2, 0, outer_z2))

		st.add_vertex(Vector3(inner_x1, rim_height * 0.5, inner_z1))
		st.add_vertex(Vector3(outer_x2, 0, outer_z2))
		st.add_vertex(Vector3(inner_x2, rim_height * 0.5, inner_z2))

		# Inner face (vertical drop to crater edge)
		st.add_vertex(Vector3(inner_x1, rim_height * 0.5, inner_z1))
		st.add_vertex(Vector3(inner_x2, rim_height * 0.5, inner_z2))
		st.add_vertex(Vector3(inner_x2, 0, inner_z2))

		st.add_vertex(Vector3(inner_x1, rim_height * 0.5, inner_z1))
		st.add_vertex(Vector3(inner_x2, 0, inner_z2))
		st.add_vertex(Vector3(inner_x1, 0, inner_z1))

	st.generate_normals()
	return st.commit()


## Create outline mesh (circle)
func _create_outline_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var segments: int = 24
	for i in range(segments):
		var angle1: float = TAU * float(i) / float(segments)
		var angle2: float = TAU * float(i + 1) / float(segments)

		st.add_vertex(Vector3(cos(angle1) * radius, 0, sin(angle1) * radius))
		st.add_vertex(Vector3(cos(angle2) * radius, 0, sin(angle2) * radius))

	return st.commit()


## Factory: Create a crater at a position
static func create(world_position: Vector3, crater_radius: float = 3.0, crater_depth: float = 1.0) -> CraterNode:
	var crater := CraterNode.new()
	crater.position = world_position
	crater.radius = crater_radius
	crater.depth = crater_depth
	return crater


## Factory: Create crater from explosion
static func create_from_explosion(world_position: Vector3, explosion_power: float) -> CraterNode:
	# Scale crater size based on explosion power
	var crater_radius: float = clampf(explosion_power * 0.05, 1.0, 8.0)
	var crater_depth: float = clampf(explosion_power * 0.02, 0.3, 2.0)
	return create(world_position, crater_radius, crater_depth)
