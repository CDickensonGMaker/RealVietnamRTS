@tool
extends Control
## Simple building model viewer with orbit camera and auto-rotate

const STRUCTURES_PATH := "res://assets/models/structures/"

@onready var model_dropdown: OptionButton = $VBoxContainer/Header/ModelDropdown
@onready var auto_rotate_check: CheckButton = $VBoxContainer/Header/AutoRotateCheck
@onready var viewport_container: SubViewportContainer = $VBoxContainer/ViewportContainer
@onready var camera_3d: Camera3D = $VBoxContainer/ViewportContainer/SubViewport/Camera3D
@onready var model_root: Node3D = $VBoxContainer/ViewportContainer/SubViewport/ModelRoot

var model_paths: Array[String] = []
var current_model: Node3D = null

# Camera orbit state
var orbit_angle: float = 0.0
var orbit_distance: float = 5.0
var orbit_height: float = 3.0
var is_orbiting: bool = false
var last_mouse_pos: Vector2


func _ready() -> void:
	_populate_dropdown()
	_update_camera_position()

	if model_dropdown:
		model_dropdown.item_selected.connect(_on_model_selected)


func _process(delta: float) -> void:
	# Auto-rotate when enabled
	if auto_rotate_check and auto_rotate_check.button_pressed and current_model:
		orbit_angle += delta * 0.5
		_update_camera_position()

	# Manual orbit dragging
	if is_orbiting:
		var mouse_pos := get_viewport().get_mouse_position()
		var mouse_delta := mouse_pos - last_mouse_pos
		orbit_angle += mouse_delta.x * 0.01
		orbit_height = clampf(orbit_height - mouse_delta.y * 0.05, 1.0, 15.0)
		_update_camera_position()
		last_mouse_pos = mouse_pos


func _populate_dropdown() -> void:
	if not model_dropdown:
		return

	model_dropdown.clear()
	model_paths.clear()

	model_dropdown.add_item("-- Select Building --")
	model_paths.append("")

	# Group models by category (subfolder)
	var categories: Dictionary = {}
	_scan_structures(STRUCTURES_PATH, "", categories)

	# Add items sorted by category
	var sorted_cats: Array = categories.keys()
	sorted_cats.sort()

	for category in sorted_cats:
		var paths: Array = categories[category]
		paths.sort()
		for path in paths:
			var display_name: String = path.get_file().get_basename().replace("_", " ").capitalize()
			var label: String = "%s / %s" % [category, display_name] if category else display_name
			model_dropdown.add_item(label)
			model_paths.append(path)


func _scan_structures(path: String, category: String, categories: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir() and not file_name.begins_with("."):
			_scan_structures(path + file_name + "/", file_name, categories)
		elif file_name.ends_with(".glb"):
			if not categories.has(category):
				categories[category] = []
			categories[category].append(path + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


func _on_model_selected(index: int) -> void:
	if index <= 0 or index >= model_paths.size():
		return
	_load_model(model_paths[index])


func _load_model(path: String) -> void:
	# Clear existing
	if current_model:
		current_model.queue_free()
		current_model = null

	var packed := load(path) as PackedScene
	if not packed:
		return

	current_model = packed.instantiate() as Node3D
	if not current_model:
		return

	model_root.add_child(current_model)

	# Auto-fit camera to model
	var aabb := _calculate_aabb(current_model)
	var model_size := aabb.size.length()
	orbit_distance = maxf(model_size * 2.0, 3.0)
	orbit_height = maxf(model_size * 0.8, 2.0)
	orbit_angle = 0.0
	_update_camera_position()


func _update_camera_position() -> void:
	if not camera_3d:
		return
	camera_3d.position = Vector3(
		sin(orbit_angle) * orbit_distance,
		orbit_height,
		cos(orbit_angle) * orbit_distance
	)
	camera_3d.look_at(Vector3(0, 1.0, 0), Vector3.UP)


func _calculate_aabb(node: Node3D) -> AABB:
	var result := AABB()
	var first := true

	for child in node.get_children():
		if child is MeshInstance3D and child.mesh:
			var mesh_aabb: AABB = child.transform * child.mesh.get_aabb()
			if first:
				result = mesh_aabb
				first = false
			else:
				result = result.merge(mesh_aabb)

		if child is Node3D:
			var child_aabb := _calculate_aabb(child)
			if child_aabb.size != Vector3.ZERO:
				var transformed: AABB = child.transform * child_aabb
				if first:
					result = transformed
					first = false
				else:
					result = result.merge(transformed)

	return result


func _gui_input(event: InputEvent) -> void:
	if not viewport_container:
		return

	var in_viewport := viewport_container.get_global_rect().has_point(get_global_mouse_position())
	if not in_viewport:
		return

	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_MIDDLE:
				is_orbiting = event.pressed
				if event.pressed:
					last_mouse_pos = get_viewport().get_mouse_position()
			MOUSE_BUTTON_WHEEL_UP:
				orbit_distance = maxf(2.0, orbit_distance - 0.5)
				_update_camera_position()
			MOUSE_BUTTON_WHEEL_DOWN:
				orbit_distance = minf(20.0, orbit_distance + 0.5)
				_update_camera_position()
