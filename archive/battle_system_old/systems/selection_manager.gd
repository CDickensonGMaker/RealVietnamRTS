extends Node
class_name SelectionManager
## SelectionManager - Handles unit selection, box selection, and command input

signal selection_changed(selected: Array[Node3D])
signal command_issued(command_type: String, target: Variant)

# Current selection
var selected_units: Array[Node3D] = []

# Selection state
var is_box_selecting: bool = false
var box_start: Vector2 = Vector2.ZERO
var box_end: Vector2 = Vector2.ZERO

# References
var camera: Camera3D

func _ready() -> void:
	camera = get_viewport().get_camera_3d()

func _unhandled_input(event: InputEvent) -> void:
	if not camera:
		camera = get_viewport().get_camera_3d()

	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

# =============================================================================
# INPUT HANDLING
# =============================================================================

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_selection(event.position)
		else:
			_end_selection(event.position)

	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and not selected_units.is_empty():
			_issue_command(event.position)

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if is_box_selecting:
		box_end = event.position

func _start_selection(position: Vector2) -> void:
	box_start = position
	box_end = position
	is_box_selecting = true

func _end_selection(position: Vector2) -> void:
	is_box_selecting = false
	box_end = position

	var box_size := (box_end - box_start).abs()

	if box_size.x < 5 and box_size.y < 5:
		# Click selection
		_click_select(position)
	else:
		# Box selection
		_box_select()

# =============================================================================
# SELECTION METHODS
# =============================================================================

func _click_select(position: Vector2) -> void:
	var result := _raycast_from_mouse(position)

	if result.is_empty():
		_clear_selection()
		return

	var clicked: Node3D = result.collider

	# Check if it's a selectable unit
	if clicked.is_in_group("player_units") or clicked.is_in_group("squads"):
		var add_to := Input.is_action_pressed("add_to_selection")
		_select_unit(clicked, add_to)
	else:
		_clear_selection()

func _box_select() -> void:
	var min_pos := Vector2(
		minf(box_start.x, box_end.x),
		minf(box_start.y, box_end.y)
	)
	var max_pos := Vector2(
		maxf(box_start.x, box_end.x),
		maxf(box_start.y, box_end.y)
	)

	var new_selection: Array[Node3D] = []

	# Find all player units in box
	for unit_node: Node in get_tree().get_nodes_in_group("player_units"):
		var unit := unit_node as Node3D
		if not unit:
			continue

		var screen_pos := camera.unproject_position(unit.global_position)

		if screen_pos.x >= min_pos.x and screen_pos.x <= max_pos.x:
			if screen_pos.y >= min_pos.y and screen_pos.y <= max_pos.y:
				new_selection.append(unit)

	_set_selection(new_selection)

func _select_unit(unit: Node3D, add_to: bool = false) -> void:
	if add_to:
		if unit in selected_units:
			_deselect_unit(unit)
		else:
			selected_units.append(unit)
			if unit.has_method("select"):
				unit.select()
	else:
		_clear_selection()
		selected_units.append(unit)
		if unit.has_method("select"):
			unit.select()

	selection_changed.emit(selected_units)
	BattleSignals.selection_changed.emit(selected_units)

func _deselect_unit(unit: Node3D) -> void:
	selected_units.erase(unit)
	if unit.has_method("deselect"):
		unit.deselect()

func _clear_selection() -> void:
	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("deselect"):
			unit.deselect()

	selected_units.clear()
	selection_changed.emit(selected_units)
	BattleSignals.selection_changed.emit(selected_units)

func _set_selection(units: Array[Node3D]) -> void:
	_clear_selection()

	for unit in units:
		selected_units.append(unit)
		if unit.has_method("select"):
			unit.select()

	selection_changed.emit(selected_units)
	BattleSignals.selection_changed.emit(selected_units)

# =============================================================================
# COMMAND ISSUING
# =============================================================================

func _issue_command(position: Vector2) -> void:
	var result := _raycast_from_mouse(position)

	if result.is_empty():
		# Move command to ground
		var ground_pos := _get_ground_position(position)
		if ground_pos != Vector3.ZERO:
			_move_command(ground_pos)
	else:
		var target: Node3D = result.collider

		if target.is_in_group("enemy_units"):
			# Attack command
			_attack_command(target)
		elif target.is_in_group("buildings"):
			# Interact with building
			_interact_command(target)
		else:
			# Move to position
			var ground_pos := _get_ground_position(position)
			if ground_pos != Vector3.ZERO:
				_move_command(ground_pos)

func _move_command(position: Vector3) -> void:
	var queue := Input.is_action_pressed("add_to_selection")

	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("move_to"):
			unit.move_to(position, queue)

	command_issued.emit("move", position)
	BattleSignals.command_issued.emit("move", position)

func _attack_command(target: Node3D) -> void:
	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("attack"):
			unit.attack(target)

	command_issued.emit("attack", target)
	BattleSignals.command_issued.emit("attack", target)

func _interact_command(target: Node3D) -> void:
	# Context-sensitive interaction
	command_issued.emit("interact", target)

# =============================================================================
# UTILITY
# =============================================================================

func _raycast_from_mouse(position: Vector2) -> Dictionary:
	var from := camera.project_ray_origin(position)
	var to := from + camera.project_ray_normal(position) * 1000.0

	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)

	return space_state.intersect_ray(query)

func _get_ground_position(position: Vector2) -> Vector3:
	var from := camera.project_ray_origin(position)
	var direction := camera.project_ray_normal(position)

	var plane := Plane(Vector3.UP, 0)
	var intersection: Variant = plane.intersects_ray(from, direction)

	if intersection:
		return intersection as Vector3

	return Vector3.ZERO

func get_selection() -> Array[Node3D]:
	return selected_units

func has_selection() -> bool:
	return not selected_units.is_empty()

func get_selection_box() -> Rect2:
	if not is_box_selecting:
		return Rect2()

	var min_pos := Vector2(
		minf(box_start.x, box_end.x),
		minf(box_start.y, box_end.y)
	)
	var size := (box_end - box_start).abs()

	return Rect2(min_pos, size)
