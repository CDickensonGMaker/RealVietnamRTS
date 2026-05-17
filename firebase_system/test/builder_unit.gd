extends Node3D
class_name BuilderUnit

## Builder Unit - Visual representation of engineer or bulldozer
## Handles its own display and animation

enum UnitType { ENGINEER, BULLDOZER }

@export var unit_type: UnitType = UnitType.ENGINEER
@export var unit_color: Color = Color(0.2, 0.6, 0.2)

var _mesh: MeshInstance3D
var _status_label: Label3D
var _work_particles: GPUParticles3D
var _current_task: String = "Idle"

# Animation
var _bob_time: float = 0.0
var _is_working: bool = false


func _ready() -> void:
	_create_visual()
	_create_status_label()
	_create_work_particles()


func _process(delta: float) -> void:
	_update_animation(delta)
	_update_status_label()


func _create_visual() -> void:
	"""Create the unit's visual mesh"""
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"

	if unit_type == UnitType.ENGINEER:
		# Engineer: Cylinder (person shape)
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.3
		capsule.height = 1.6
		_mesh.mesh = capsule
		_mesh.position.y = 0.8
	else:
		# Bulldozer: Box (vehicle shape)
		var box := BoxMesh.new()
		box.size = Vector3(2.0, 1.2, 3.0)
		_mesh.mesh = box
		_mesh.position.y = 0.6

		# Add blade
		var blade_mesh := MeshInstance3D.new()
		var blade := BoxMesh.new()
		blade.size = Vector3(2.5, 0.8, 0.2)
		blade_mesh.mesh = blade
		blade_mesh.position = Vector3(0, 0.2, 1.6)

		var blade_mat := StandardMaterial3D.new()
		blade_mat.albedo_color = Color(0.3, 0.3, 0.3)
		blade_mesh.material_override = blade_mat
		_mesh.add_child(blade_mesh)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = unit_color
	_mesh.material_override = mat

	add_child(_mesh)


func _create_status_label() -> void:
	"""Create floating status text"""
	_status_label = Label3D.new()
	_status_label.name = "StatusLabel"
	_status_label.text = "Idle"
	_status_label.font_size = 32
	_status_label.position.y = 2.5 if unit_type == UnitType.ENGINEER else 2.2
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.no_depth_test = true
	_status_label.modulate = Color(1, 1, 1, 0.8)
	add_child(_status_label)


func _create_work_particles() -> void:
	"""Create particles for when working"""
	_work_particles = GPUParticles3D.new()
	_work_particles.name = "WorkParticles"
	_work_particles.emitting = false
	_work_particles.amount = 10
	_work_particles.lifetime = 0.5

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.5
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 45.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 2.0
	mat.gravity = Vector3(0, -5, 0)
	mat.scale_min = 0.1
	mat.scale_max = 0.2

	if unit_type == UnitType.BULLDOZER:
		mat.color = Color(0.5, 0.4, 0.2)  # Dirt
		_work_particles.position = Vector3(0, 0.3, 1.5)
	else:
		mat.color = Color(0.6, 0.5, 0.3)  # Sawdust
		_work_particles.position = Vector3(0, 0.5, 0.5)

	_work_particles.process_material = mat

	# Simple quad mesh for particles
	var quad := QuadMesh.new()
	quad.size = Vector2(0.1, 0.1)
	_work_particles.draw_pass_1 = quad

	add_child(_work_particles)


func _update_animation(delta: float) -> void:
	"""Update unit animation"""
	_bob_time += delta

	if _is_working:
		# Working animation
		if unit_type == UnitType.ENGINEER:
			# Bobbing up and down while working
			_mesh.position.y = 0.8 + sin(_bob_time * 8.0) * 0.05
			_mesh.rotation.x = sin(_bob_time * 4.0) * 0.1
		else:
			# Bulldozer shaking
			_mesh.position.x = sin(_bob_time * 15.0) * 0.02
			_mesh.rotation.z = sin(_bob_time * 10.0) * 0.02
	else:
		# Idle animation
		if unit_type == UnitType.ENGINEER:
			_mesh.position.y = 0.8 + sin(_bob_time * 2.0) * 0.02
		_mesh.rotation.x = 0
		_mesh.rotation.z = 0


func _update_status_label() -> void:
	"""Update the status label text"""
	_status_label.text = _current_task


## Public API

func set_task_status(status: String) -> void:
	"""Set the displayed task status"""
	_current_task = status
	_is_working = status in ["Clearing", "Building"]
	_work_particles.emitting = _is_working


func set_color(color: Color) -> void:
	"""Change unit color"""
	unit_color = color
	if _mesh and _mesh.material_override:
		(_mesh.material_override as StandardMaterial3D).albedo_color = color


static func create_engineer(pos: Vector3 = Vector3.ZERO) -> BuilderUnit:
	"""Factory method to create an engineer"""
	var unit := new()
	unit.unit_type = UnitType.ENGINEER
	unit.unit_color = Color(0.2, 0.5, 0.2)  # Green
	unit.name = "Engineer_%d" % randi()
	unit.position = pos
	return unit


static func create_bulldozer(pos: Vector3 = Vector3.ZERO) -> BuilderUnit:
	"""Factory method to create a bulldozer"""
	var unit := new()
	unit.unit_type = UnitType.BULLDOZER
	unit.unit_color = Color(0.7, 0.5, 0.1)  # Yellow/orange
	unit.name = "Bulldozer_%d" % randi()
	unit.position = pos
	return unit
