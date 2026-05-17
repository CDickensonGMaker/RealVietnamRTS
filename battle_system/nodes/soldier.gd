class_name Soldier extends CharacterBody3D
## Individual soldier unit - part of a Squad
## Handles individual health, position, death

signal soldier_died(soldier: Soldier)
signal soldier_health_changed(soldier: Soldier, current: float, max_health: float)

enum SoldierState { IDLE, MOVING, COMBAT, PRONE, DEAD }

## Configuration
@export var max_health: float = 100.0
@export var move_speed: float = 5.0
@export var rotation_speed: float = 5.0

## State
var current_health: float = 100.0
var state: SoldierState = SoldierState.IDLE
var squad: Node = null  # Reference to parent squad

## Movement
var move_target: Vector3 = Vector3.ZERO
var formation_offset: Vector3 = Vector3.ZERO  # Offset from squad center
var nav_agent: NavigationAgent3D = null

## Visual
var _body_mesh: MeshInstance3D = null
var _head_mesh: MeshInstance3D = null
var _selection_ring: MeshInstance3D = null
var _model: Node3D = null

## Colors
var base_color: Color = Color(0.2, 0.5, 0.2)  # OD Green default


func _ready() -> void:
	add_to_group("soldiers")
	_setup_navigation()
	_setup_collision()
	_create_visual()
	current_health = max_health


func _setup_navigation() -> void:
	"""Setup NavigationAgent3D for pathfinding"""
	nav_agent = NavigationAgent3D.new()
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	nav_agent.avoidance_enabled = true
	nav_agent.radius = 0.4
	nav_agent.neighbor_distance = 5.0
	nav_agent.max_neighbors = 10
	nav_agent.max_speed = move_speed
	add_child(nav_agent)


func _setup_collision() -> void:
	"""Add collision shape for physics and selection raycast"""
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	collision.shape = capsule
	collision.position.y = 0.8
	add_child(collision)

	# Set collision layer (layer 2 for US units by default)
	collision_layer = 2
	collision_mask = 1  # Collide with terrain


func _create_visual() -> void:
	"""Create placeholder soldier visual"""
	# Body (capsule)
	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "Body"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.25
	capsule.height = 1.2
	_body_mesh.mesh = capsule
	_body_mesh.position.y = 0.7

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = base_color
	_body_mesh.material_override = body_mat
	add_child(_body_mesh)

	# Head (sphere)
	_head_mesh = MeshInstance3D.new()
	_head_mesh.name = "Head"
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	_head_mesh.mesh = sphere
	_head_mesh.position.y = 1.45

	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.85, 0.7, 0.55)  # Skin tone
	_head_mesh.material_override = head_mat
	add_child(_head_mesh)


func load_model(model_path: String) -> void:
	"""Load a GLB model for this soldier"""
	var scene: PackedScene = load(model_path)
	if scene:
		if _model:
			_model.queue_free()
		_model = scene.instantiate()
		add_child(_model)
		# Hide placeholder
		if _body_mesh:
			_body_mesh.visible = false
		if _head_mesh:
			_head_mesh.visible = false


func _physics_process(delta: float) -> void:
	if state == SoldierState.DEAD:
		return

	if state == SoldierState.MOVING:
		_process_movement(delta)


func _process_movement(delta: float) -> void:
	"""Move toward target using navigation or direct movement"""
	var direction: Vector3
	var arrived: bool = false

	# Try navigation agent first
	if nav_agent and not nav_agent.is_navigation_finished():
		var next_pos: Vector3 = nav_agent.get_next_path_position()
		direction = (next_pos - global_position)
		direction.y = 0

		if direction.length() < 0.5:
			arrived = true
	else:
		# Fallback to direct movement if no navmesh
		direction = (move_target - global_position)
		direction.y = 0

		if direction.length() < 0.5:
			arrived = true

	if arrived:
		state = SoldierState.IDLE
		velocity = Vector3.ZERO
		return

	direction = direction.normalized()

	if direction.length() > 0.1:
		velocity = direction * move_speed

		# Face movement direction
		var target_rot: float = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rot, delta * rotation_speed)
	else:
		velocity = Vector3.ZERO

	move_and_slide()


## Public API

func move_to(target: Vector3) -> void:
	"""Set movement target"""
	move_target = target
	if nav_agent:
		nav_agent.target_position = target
	state = SoldierState.MOVING


func move_to_formation(squad_position: Vector3, offset: Vector3) -> void:
	"""Move to formation position relative to squad"""
	formation_offset = offset
	var target: Vector3 = squad_position + offset
	move_to(target)


func take_damage(amount: float, _source: Node = null) -> void:
	"""Apply damage to this soldier"""
	if state == SoldierState.DEAD:
		return

	current_health -= amount
	soldier_health_changed.emit(self, current_health, max_health)

	if current_health <= 0:
		die()


func heal(amount: float) -> void:
	"""Heal this soldier"""
	current_health = minf(current_health + amount, max_health)
	soldier_health_changed.emit(self, current_health, max_health)


func die() -> void:
	"""Kill this soldier"""
	if state == SoldierState.DEAD:
		return

	state = SoldierState.DEAD
	current_health = 0.0

	# Visual death - fall over
	var tween: Tween = create_tween()
	tween.tween_property(self, "rotation:x", -PI / 2, 0.3)
	tween.tween_callback(_on_death_complete)

	soldier_died.emit(self)


func _on_death_complete() -> void:
	"""Called after death animation"""
	# Keep body on ground, disable physics
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0


func set_color(color: Color) -> void:
	"""Set soldier body color"""
	base_color = color
	if _body_mesh and _body_mesh.material_override:
		(_body_mesh.material_override as StandardMaterial3D).albedo_color = color


func show_selection(show: bool) -> void:
	"""Show/hide selection indicator"""
	if not _selection_ring:
		_create_selection_ring()
	_selection_ring.visible = show


func _create_selection_ring() -> void:
	"""Create selection ring at feet"""
	_selection_ring = MeshInstance3D.new()
	_selection_ring.name = "SelectionRing"

	var torus := TorusMesh.new()
	torus.inner_radius = 0.35
	torus.outer_radius = 0.45
	_selection_ring.mesh = torus
	_selection_ring.position.y = 0.05
	_selection_ring.rotation.x = -PI / 2

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 0.2, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selection_ring.material_override = mat

	_selection_ring.visible = false
	add_child(_selection_ring)


func is_alive() -> bool:
	return state != SoldierState.DEAD


func get_health_percent() -> float:
	return current_health / max_health if max_health > 0 else 0.0
