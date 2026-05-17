class_name InfantrySquad extends CharacterBody3D
## Squad of infantry soldiers that moves and fights as one unit
## Uses MultiMesh for efficient rendering (2 draw calls instead of 20+)
## Squad sizes: Rifle=12, Engineer=6, MG Team=4, Mortar=3, etc.

signal squad_selected(squad: InfantrySquad)
signal squad_deselected(squad: InfantrySquad)
signal soldiers_killed(squad: InfantrySquad, count: int)
signal squad_wiped(squad: InfantrySquad)
signal squad_moved(squad: InfantrySquad, position: Vector3)

enum Formation { LINE, WEDGE, COLUMN, SPREAD }
enum SquadType { RIFLE, ENGINEER, MG_TEAM, MORTAR, RECON, COMMAND }

## Squad type determines size and behavior
const SQUAD_SIZES: Dictionary = {
	SquadType.RIFLE: 12,
	SquadType.ENGINEER: 6,
	SquadType.MG_TEAM: 4,
	SquadType.MORTAR: 3,
	SquadType.RECON: 6,
	SquadType.COMMAND: 4,
}

## Configuration
@export var squad_type: SquadType = SquadType.RIFLE
@export var squad_name: String = "Squad"
@export var formation: Formation = Formation.WEDGE
@export var formation_spacing: float = 1.5
@export var soldier_color: Color = Color(0.2, 0.5, 0.2)  # OD Green
@export var move_speed: float = 5.0
@export var rotation_speed: float = 3.0

## State
var alive_count: int = 0
var max_soldiers: int = 12
var is_selected: bool = false

## Movement
var move_target: Vector3 = Vector3.ZERO
var has_move_order: bool = false

## Soldier tracking (local positions and rotations for each soldier)
var _soldier_positions: PackedVector3Array = PackedVector3Array()
var _soldier_rotations: PackedFloat32Array = PackedFloat32Array()  # Y-axis rotation
var _soldier_alive: PackedByteArray = PackedByteArray()  # 1 = alive, 0 = dead
var _soldier_death_progress: PackedFloat32Array = PackedFloat32Array()  # 0-1 death anim

## MultiMesh rendering
var _body_multimesh_instance: MultiMeshInstance3D = null
var _head_multimesh_instance: MultiMeshInstance3D = null
var _body_mesh: CapsuleMesh = null
var _head_mesh: SphereMesh = null
var _body_material: StandardMaterial3D = null
var _head_material: StandardMaterial3D = null

## Visual
var _selection_ring: MeshInstance3D = null
var _squad_marker: MeshInstance3D = null

## Animation timing
var _sway_time: float = 0.0
const SWAY_AMPLITUDE: float = 0.03
const SWAY_FREQ: float = 0.8
const DEATH_ANIM_DURATION: float = 0.5

## Cached transform buffer for MultiMesh updates
var _body_transform_buffer: PackedFloat32Array = PackedFloat32Array()
var _head_transform_buffer: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	add_to_group("squads")
	add_to_group("selectable_units")
	add_to_group("player_units")

	# Set squad size based on type
	max_soldiers = SQUAD_SIZES.get(squad_type, 12)
	alive_count = max_soldiers

	_setup_collision()
	_create_shared_meshes()
	_spawn_soldiers()
	_create_selection_ring()
	_create_squad_marker()


func _setup_collision() -> void:
	"""Add collision for physics and selection raycast"""
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Collision box covers the formation area
	var size: float = formation_spacing * 3.0
	box.size = Vector3(size, 2.0, size)
	collision.shape = box
	collision.position.y = 1.0
	add_child(collision)

	collision_layer = 2  # US units layer
	collision_mask = 1   # Terrain


func _create_shared_meshes() -> void:
	"""Create mesh resources shared by all soldiers in squad"""
	# Body capsule mesh
	_body_mesh = CapsuleMesh.new()
	_body_mesh.radius = 0.2
	_body_mesh.height = 1.0

	# Head sphere mesh
	_head_mesh = SphereMesh.new()
	_head_mesh.radius = 0.12

	# Body material (OD Green)
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = soldier_color

	# Head material (skin tone)
	_head_material = StandardMaterial3D.new()
	_head_material.albedo_color = Color(0.85, 0.7, 0.55)


func _spawn_soldiers() -> void:
	"""Create MultiMesh instances and initialize soldier positions"""
	var positions: Array[Vector3] = _get_formation_positions(max_soldiers, formation)

	# Initialize soldier tracking arrays
	_soldier_positions.resize(max_soldiers)
	_soldier_rotations.resize(max_soldiers)
	_soldier_alive.resize(max_soldiers)
	_soldier_death_progress.resize(max_soldiers)

	for i in max_soldiers:
		_soldier_positions[i] = positions[i] if i < positions.size() else Vector3.ZERO
		_soldier_rotations[i] = randf_range(-0.1, 0.1)  # Slight random rotation
		_soldier_alive[i] = 1
		_soldier_death_progress[i] = 0.0

	# Pre-allocate transform buffers (12 floats per instance)
	_body_transform_buffer.resize(max_soldiers * 12)
	_head_transform_buffer.resize(max_soldiers * 12)

	# Create body MultiMesh
	var body_multimesh := MultiMesh.new()
	body_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	body_multimesh.mesh = _body_mesh
	body_multimesh.instance_count = max_soldiers

	_body_multimesh_instance = MultiMeshInstance3D.new()
	_body_multimesh_instance.name = "BodyMultiMesh"
	_body_multimesh_instance.multimesh = body_multimesh
	_body_multimesh_instance.material_override = _body_material
	add_child(_body_multimesh_instance)

	# Create head MultiMesh
	var head_multimesh := MultiMesh.new()
	head_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	head_multimesh.mesh = _head_mesh
	head_multimesh.instance_count = max_soldiers

	_head_multimesh_instance = MultiMeshInstance3D.new()
	_head_multimesh_instance.name = "HeadMultiMesh"
	_head_multimesh_instance.multimesh = head_multimesh
	_head_multimesh_instance.material_override = _head_material
	add_child(_head_multimesh_instance)

	# Initial transform update
	_update_multimesh_transforms()


func _get_formation_positions(count: int, form: Formation) -> Array[Vector3]:
	"""Calculate soldier positions for formation"""
	var positions: Array[Vector3] = []
	var sp: float = formation_spacing

	match form:
		Formation.LINE:
			# Wide line, 2-3 ranks deep
			var cols: int = ceili(sqrt(float(count) * 2.0))
			var rows_needed: int = ceili(float(count) / float(cols))
			for i in count:
				var row: int = i / cols
				var col: int = i % cols
				var x: float = (col - cols / 2.0) * sp + randf_range(-0.1, 0.1)
				var z: float = (row - rows_needed / 2.0) * sp + randf_range(-0.1, 0.1)
				# Stagger alternating rows
				if row % 2 == 1:
					x += sp * 0.3
				positions.append(Vector3(x, 0, z))

		Formation.WEDGE:
			# V formation - leader front, others spread back
			positions.append(Vector3(0, 0, -sp))  # Leader at front
			var placed: int = 1
			var row: int = 1
			while placed < count:
				var soldiers_in_row: int = row + 1
				for col in soldiers_in_row:
					if placed >= count:
						break
					var x: float = (col - soldiers_in_row / 2.0) * sp + randf_range(-0.1, 0.1)
					var z: float = row * sp * 0.8 + randf_range(-0.1, 0.1)
					positions.append(Vector3(x, 0, z))
					placed += 1
				row += 1

		Formation.COLUMN:
			# Single/double file column
			var files: int = 2 if count > 4 else 1
			for i in count:
				var file: int = i % files
				var rank: int = i / files
				var x: float = (file - files / 2.0 + 0.5) * sp * 0.8 + randf_range(-0.05, 0.05)
				var z: float = rank * sp + randf_range(-0.05, 0.05)
				positions.append(Vector3(x, 0, z))

		Formation.SPREAD:
			# Circular spread
			for i in count:
				var angle: float = TAU * i / count
				var radius: float = sp * 1.5
				positions.append(Vector3(cos(angle) * radius, 0, sin(angle) * radius))

	return positions


func _update_multimesh_transforms() -> void:
	"""Update all soldier transforms in MultiMesh buffers"""
	for i in max_soldiers:
		var pos: Vector3 = _soldier_positions[i]
		var rot_y: float = _soldier_rotations[i]
		var is_alive: bool = _soldier_alive[i] == 1
		var death_progress: float = _soldier_death_progress[i]

		# Calculate body transform
		var body_transform := Transform3D.IDENTITY

		if not is_alive and death_progress >= 1.0:
			# Fully dead - scale to zero to hide
			body_transform = body_transform.scaled(Vector3.ZERO)
			body_transform.origin = pos
		elif not is_alive:
			# Death animation - fall over
			var fall_angle: float = -PI / 2.0 * death_progress
			body_transform = body_transform.rotated(Vector3.RIGHT, fall_angle)
			body_transform = body_transform.rotated(Vector3.UP, rot_y)
			var fall_height: float = lerpf(0.6, 0.2, death_progress)
			body_transform.origin = pos + Vector3(0, fall_height, 0)
		else:
			# Alive - normal position with rotation
			body_transform = body_transform.rotated(Vector3.UP, rot_y)
			body_transform.origin = pos + Vector3(0, 0.6, 0)  # Body center height

		_write_transform_to_buffer(_body_transform_buffer, i, body_transform)

		# Calculate head transform
		var head_transform := Transform3D.IDENTITY

		if not is_alive and death_progress >= 1.0:
			# Fully dead - scale to zero to hide
			head_transform = head_transform.scaled(Vector3.ZERO)
			head_transform.origin = pos
		elif not is_alive:
			# Death animation - fall with body
			var fall_angle: float = -PI / 2.0 * death_progress
			head_transform = head_transform.rotated(Vector3.RIGHT, fall_angle)
			head_transform = head_transform.rotated(Vector3.UP, rot_y)
			# Head moves forward and down as body falls
			var head_offset := Vector3(0, 1.25, 0).rotated(Vector3.RIGHT, fall_angle)
			head_transform.origin = pos + head_offset
		else:
			# Alive - normal position
			head_transform = head_transform.rotated(Vector3.UP, rot_y)
			head_transform.origin = pos + Vector3(0, 1.25, 0)  # Head height

		_write_transform_to_buffer(_head_transform_buffer, i, head_transform)

	# Upload buffers to MultiMesh
	if _body_multimesh_instance and _body_multimesh_instance.multimesh:
		_body_multimesh_instance.multimesh.buffer = _body_transform_buffer
	if _head_multimesh_instance and _head_multimesh_instance.multimesh:
		_head_multimesh_instance.multimesh.buffer = _head_transform_buffer


func _write_transform_to_buffer(buffer: PackedFloat32Array, index: int, t: Transform3D) -> void:
	"""Write a Transform3D to the packed buffer at the given index"""
	var b: int = index * 12
	buffer[b + 0] = t.basis.x.x; buffer[b + 1] = t.basis.y.x
	buffer[b + 2] = t.basis.z.x; buffer[b + 3] = t.origin.x
	buffer[b + 4] = t.basis.x.y; buffer[b + 5] = t.basis.y.y
	buffer[b + 6] = t.basis.z.y; buffer[b + 7] = t.origin.y
	buffer[b + 8] = t.basis.x.z; buffer[b + 9] = t.basis.y.z
	buffer[b + 10] = t.basis.z.z; buffer[b + 11] = t.origin.z


func _create_selection_ring() -> void:
	"""Create squad-level selection indicator"""
	_selection_ring = MeshInstance3D.new()
	_selection_ring.name = "SelectionRing"

	var torus := TorusMesh.new()
	var ring_radius: float = formation_spacing * 2.5
	torus.inner_radius = ring_radius
	torus.outer_radius = ring_radius + 0.25
	_selection_ring.mesh = torus
	_selection_ring.position.y = 0.1
	_selection_ring.rotation.x = -PI / 2

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 0.2, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selection_ring.material_override = mat

	_selection_ring.visible = false
	add_child(_selection_ring)


func _create_squad_marker() -> void:
	"""Create squad center marker"""
	_squad_marker = MeshInstance3D.new()
	_squad_marker.name = "SquadMarker"

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.3
	cylinder.bottom_radius = 0.3
	cylinder.height = 0.1
	_squad_marker.mesh = cylinder
	_squad_marker.position.y = 0.05

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.6, 0.1, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_squad_marker.material_override = mat

	add_child(_squad_marker)


func _physics_process(delta: float) -> void:
	if has_move_order:
		_process_movement(delta)

	_update_soldier_animations(delta)


func _process_movement(delta: float) -> void:
	"""Move squad toward target"""
	var direction: Vector3 = (move_target - global_position)
	direction.y = 0

	var distance: float = direction.length()

	if distance < 0.5:
		has_move_order = false
		velocity = Vector3.ZERO
		return

	direction = direction.normalized()
	velocity = direction * move_speed

	# Face movement direction
	var target_rot: float = atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_rot, delta * rotation_speed)

	move_and_slide()


func _update_soldier_animations(delta: float) -> void:
	"""Update soldier sway/walk animations and death progress"""
	_sway_time += delta
	var needs_update: bool = false

	# Update death animations
	for i in max_soldiers:
		if _soldier_alive[i] == 0 and _soldier_death_progress[i] < 1.0:
			_soldier_death_progress[i] = minf(_soldier_death_progress[i] + delta / DEATH_ANIM_DURATION, 1.0)
			needs_update = true

	# Apply idle sway or walk bob to alive soldiers
	if not has_move_order:
		# Idle sway
		for i in max_soldiers:
			if _soldier_alive[i] == 1:
				var phase: float = i * 0.7
				var sway_x: float = sin(_sway_time * SWAY_FREQ + phase) * SWAY_AMPLITUDE
				var sway_z: float = sin(_sway_time * SWAY_FREQ * 0.7 + phase * 1.3) * SWAY_AMPLITUDE
				# Encode sway into rotation (subtle body lean)
				_soldier_rotations[i] = _soldier_rotations[i] + sway_x * 0.01  # Very subtle
				needs_update = true
	else:
		# Walk bob - we encode this in a slight position offset
		needs_update = true

	if needs_update:
		_update_multimesh_transforms()


## Public API - Selection

func select() -> void:
	if is_selected:
		return
	is_selected = true
	_selection_ring.visible = true
	squad_selected.emit(self)


func deselect() -> void:
	if not is_selected:
		return
	is_selected = false
	_selection_ring.visible = false
	squad_deselected.emit(self)


func toggle_selection() -> void:
	if is_selected:
		deselect()
	else:
		select()


## Public API - Movement

func move_to(target: Vector3) -> void:
	"""Set movement target"""
	move_target = target
	move_target.y = global_position.y
	has_move_order = true
	squad_moved.emit(self, target)


func stop() -> void:
	has_move_order = false
	velocity = Vector3.ZERO


## Public API - Combat/Casualties

func kill_soldiers(amount: int) -> void:
	"""Kill soldiers from back of formation"""
	var killed: int = 0
	for i in range(max_soldiers - 1, -1, -1):
		if killed >= amount:
			break
		if _soldier_alive[i] == 1:
			_soldier_alive[i] = 0
			_soldier_death_progress[i] = 0.0  # Start death animation
			killed += 1
			alive_count -= 1

	soldiers_killed.emit(self, killed)

	if alive_count <= 0:
		squad_wiped.emit(self)

	# Immediate visual update
	_update_multimesh_transforms()


func take_damage(amount: float, _source: Node = null) -> void:
	"""Convert damage to casualties"""
	# Simple: 100 damage = 1 casualty
	var casualties: int = int(amount / 100.0)
	if casualties > 0:
		kill_soldiers(casualties)


## Public API - Helicopter transport

func board_transport() -> void:
	"""Hide all soldiers (boarding helicopter)"""
	if _body_multimesh_instance:
		_body_multimesh_instance.visible = false
	if _head_multimesh_instance:
		_head_multimesh_instance.visible = false
	_selection_ring.visible = false
	_squad_marker.visible = false
	set_physics_process(false)
	collision_layer = 0


func disembark_around(center: Vector3, _radius: float = 5.0) -> void:
	"""Show soldiers in circle around position"""
	global_position = center
	collision_layer = 2
	set_physics_process(true)
	_squad_marker.visible = true

	# Reposition soldiers around new center
	var positions: Array[Vector3] = _get_formation_positions(alive_count, formation)
	for i in max_soldiers:
		if i < alive_count and _soldier_alive[i] == 1:
			_soldier_positions[i] = positions[i] if i < positions.size() else Vector3.ZERO
			_soldier_rotations[i] = randf_range(-0.1, 0.1)

	# Show MultiMesh instances
	if _body_multimesh_instance:
		_body_multimesh_instance.visible = true
	if _head_multimesh_instance:
		_head_multimesh_instance.visible = true

	_update_multimesh_transforms()


## Public API - State queries

func get_alive_count() -> int:
	return alive_count


func get_max_soldiers() -> int:
	return max_soldiers


func is_alive() -> bool:
	return alive_count > 0


func get_health_percent() -> float:
	return float(alive_count) / float(max_soldiers) if max_soldiers > 0 else 0.0


func set_formation(new_formation: Formation) -> void:
	"""Change squad formation"""
	formation = new_formation
	var positions: Array[Vector3] = _get_formation_positions(alive_count, formation)

	var pos_idx: int = 0
	for i in max_soldiers:
		if _soldier_alive[i] == 1 and pos_idx < positions.size():
			_soldier_positions[i] = positions[pos_idx]
			pos_idx += 1

	_update_multimesh_transforms()


func set_soldier_color(color: Color) -> void:
	"""Set color for all soldiers"""
	soldier_color = color
	if _body_material:
		_body_material.albedo_color = color
