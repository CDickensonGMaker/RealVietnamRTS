class_name TestInfantry extends CharacterBody3D

## Simple selectable infantry unit for helicopter shuttle testing

signal selection_changed(unit: TestInfantry, is_selected: bool)

var is_selected: bool = false
var unit_color: Color = Color(0.2, 0.6, 0.2)

var _mesh: MeshInstance3D
var _selection_ring: MeshInstance3D


func _ready() -> void:
	add_to_group("selectable_units")
	add_to_group("test_infantry")
	_create_visual()
	_create_selection_ring()

	# Add collision for raycasting
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	collision.shape = capsule
	collision.position.y = 0.8
	add_child(collision)


func _create_visual() -> void:
	"""Create simple soldier mesh - capsule with head"""
	# Body
	_mesh = MeshInstance3D.new()
	_mesh.name = "Body"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.25
	capsule.height = 1.2
	_mesh.mesh = capsule
	_mesh.position.y = 0.7

	var mat := StandardMaterial3D.new()
	mat.albedo_color = unit_color
	_mesh.material_override = mat
	add_child(_mesh)

	# Head
	var head := MeshInstance3D.new()
	head.name = "Head"
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	head.mesh = sphere
	head.position.y = 1.5

	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.85, 0.7, 0.55)  # Skin tone
	head.material_override = head_mat
	add_child(head)


func _create_selection_ring() -> void:
	"""Create selection indicator ring on ground"""
	_selection_ring = MeshInstance3D.new()
	_selection_ring.name = "SelectionRing"

	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.65
	_selection_ring.mesh = torus
	_selection_ring.position.y = 0.05
	_selection_ring.rotation.x = -PI / 2  # Lay flat

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 0.2, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selection_ring.material_override = mat

	_selection_ring.visible = false
	add_child(_selection_ring)


func select() -> void:
	"""Select this unit"""
	if not is_selected:
		is_selected = true
		_selection_ring.visible = true
		selection_changed.emit(self, true)


func deselect() -> void:
	"""Deselect this unit"""
	if is_selected:
		is_selected = false
		_selection_ring.visible = false
		selection_changed.emit(self, false)


func toggle_selection() -> void:
	"""Toggle selection state"""
	if is_selected:
		deselect()
	else:
		select()


func set_color(color: Color) -> void:
	"""Change unit color"""
	unit_color = color
	if _mesh and _mesh.material_override:
		(_mesh.material_override as StandardMaterial3D).albedo_color = color
