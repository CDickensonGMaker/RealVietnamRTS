class_name InfantrySquad extends CharacterBody3D
## Squad of infantry soldiers that moves and fights as one unit
## Visual soldiers are spawned in formation (like BP RTS Dark Shadows pattern)
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
var soldiers: Array[Node3D] = []  # Visual soldier instances
var alive_count: int = 0
var max_soldiers: int = 12
var is_selected: bool = false

## Movement
var move_target: Vector3 = Vector3.ZERO
var has_move_order: bool = false

## Visual
var _selection_ring: MeshInstance3D = null
var _squad_marker: MeshInstance3D = null

## Animation timing
var _sway_time: float = 0.0
const SWAY_AMPLITUDE: float = 0.03
const SWAY_FREQ: float = 0.8


func _ready() -> void:
	add_to_group("squads")
	add_to_group("selectable_units")
	add_to_group("player_units")

	# Set squad size based on type
	max_soldiers = SQUAD_SIZES.get(squad_type, 12)
	alive_count = max_soldiers

	_setup_collision()
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


func _spawn_soldiers() -> void:
	"""Create visual soldier instances in formation"""
	var positions: Array[Vector3] = _get_formation_positions(max_soldiers, formation)

	for i in max_soldiers:
		var soldier := _create_soldier_visual()
		soldier.name = "Soldier_%d" % (i + 1)
		soldier.position = positions[i] if i < positions.size() else Vector3.ZERO

		# Random slight rotation for natural look
		soldier.rotation.y = randf_range(-0.1, 0.1)

		add_child(soldier)
		soldiers.append(soldier)


func _create_soldier_visual() -> Node3D:
	"""Create a simple soldier visual (capsule body + head)"""
	var soldier := Node3D.new()

	# Body (capsule)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.2
	capsule.height = 1.0
	body.mesh = capsule
	body.position.y = 0.6

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = soldier_color
	body.material_override = body_mat
	soldier.add_child(body)

	# Head (sphere)
	var head := MeshInstance3D.new()
	head.name = "Head"
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	head.mesh = sphere
	head.position.y = 1.25

	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.85, 0.7, 0.55)  # Skin tone
	head.material_override = head_mat
	soldier.add_child(head)

	return soldier


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

	_update_soldier_sway(delta)


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

	# Update soldier walk animations
	for soldier in soldiers:
		if soldier.visible:
			_animate_soldier_walk(soldier, delta)


func _update_soldier_sway(delta: float) -> void:
	"""Subtle idle sway for soldiers when not moving"""
	if has_move_order:
		return

	_sway_time += delta

	for i in soldiers.size():
		var soldier: Node3D = soldiers[i]
		if not soldier.visible:
			continue

		# Per-soldier phase offset
		var phase: float = i * 0.7
		var sway_x: float = sin(_sway_time * SWAY_FREQ + phase) * SWAY_AMPLITUDE
		var sway_z: float = sin(_sway_time * SWAY_FREQ * 0.7 + phase * 1.3) * SWAY_AMPLITUDE

		soldier.rotation.x = sway_z * 0.5
		soldier.rotation.z = sway_x * 0.3


func _animate_soldier_walk(soldier: Node3D, _delta: float) -> void:
	"""Simple walk bob animation"""
	var body: Node3D = soldier.get_node_or_null("Body")
	if body:
		body.position.y = 0.6 + abs(sin(_sway_time * 8.0)) * 0.05


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
	for i in range(soldiers.size() - 1, -1, -1):
		if killed >= amount:
			break
		var soldier: Node3D = soldiers[i]
		if soldier.visible:
			_play_death_animation(soldier)
			killed += 1
			alive_count -= 1

	soldiers_killed.emit(self, killed)

	if alive_count <= 0:
		squad_wiped.emit(self)


func _play_death_animation(soldier: Node3D) -> void:
	"""Animate soldier death"""
	var tween: Tween = create_tween()
	tween.tween_property(soldier, "rotation:x", -PI / 2, 0.3)
	tween.tween_property(soldier, "position:y", 0.2, 0.2)
	tween.tween_callback(func(): soldier.visible = false)


func take_damage(amount: float, _source: Node = null) -> void:
	"""Convert damage to casualties"""
	# Simple: 100 damage = 1 casualty
	var casualties: int = int(amount / 100.0)
	if casualties > 0:
		kill_soldiers(casualties)


## Public API - Helicopter transport

func board_transport() -> void:
	"""Hide all soldiers (boarding helicopter)"""
	for soldier in soldiers:
		soldier.visible = false
	_selection_ring.visible = false
	_squad_marker.visible = false
	set_physics_process(false)
	collision_layer = 0


func disembark_around(center: Vector3, radius: float = 5.0) -> void:
	"""Show soldiers in circle around position"""
	global_position = center
	collision_layer = 2
	set_physics_process(true)
	_squad_marker.visible = true

	# Reposition soldiers around new center
	var positions: Array[Vector3] = _get_formation_positions(alive_count, formation)
	for i in soldiers.size():
		var soldier: Node3D = soldiers[i]
		if i < alive_count:
			soldier.visible = true
			soldier.position = positions[i] if i < positions.size() else Vector3.ZERO
			soldier.rotation = Vector3.ZERO


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
	for i in soldiers.size():
		if i < positions.size() and soldiers[i].visible:
			soldiers[i].position = positions[i]


func set_soldier_color(color: Color) -> void:
	"""Set color for all soldiers"""
	soldier_color = color
	for soldier in soldiers:
		var body: Node3D = soldier.get_node_or_null("Body")
		if body and body is MeshInstance3D:
			var mat: StandardMaterial3D = (body as MeshInstance3D).material_override
			if mat:
				mat.albedo_color = color
