extends Node
## SelectionManager - Handles unit/structure selection and commands
## Supports single click, box select, and right-click commands

signal selection_changed(selected_units: Array)
signal command_issued(command_type: String, target: Variant)

# Current selection
var selected_units: Array[Node3D] = []
var selection_box_start: Vector2 = Vector2.ZERO
var is_box_selecting: bool = false

# References
var camera: Camera3D
var selection_box_visual: Control  # UI element for drawing selection box

# Layers
const UNIT_LAYER := 2
const STRUCTURE_LAYER := 3
const TERRAIN_LAYER := 1


func _ready() -> void:
	# Find camera after scene is ready
	await get_tree().process_frame
	camera = get_viewport().get_camera_3d()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("select"):
		_start_selection(event.position)
	elif event.is_action_released("select"):
		_end_selection(event.position)
	elif event is InputEventMouseMotion and is_box_selecting:
		_update_selection_box(event.position)
	elif event.is_action_pressed("command"):
		_issue_command(event.position)


func _start_selection(screen_pos: Vector2) -> void:
	selection_box_start = screen_pos
	is_box_selecting = true


func _end_selection(screen_pos: Vector2) -> void:
	is_box_selecting = false

	var box_size := (screen_pos - selection_box_start).abs()

	if box_size.length() < 5.0:
		# Single click selection
		_single_select(screen_pos)
	else:
		# Box selection
		_box_select(selection_box_start, screen_pos)

	# Hide selection box visual
	if selection_box_visual:
		selection_box_visual.hide()


func _update_selection_box(screen_pos: Vector2) -> void:
	if selection_box_visual:
		# Update visual rect
		var rect := Rect2(selection_box_start, screen_pos - selection_box_start).abs()
		selection_box_visual.position = rect.position
		selection_box_visual.size = rect.size
		selection_box_visual.show()


func _single_select(screen_pos: Vector2) -> void:
	var hit := _raycast_from_screen(screen_pos, UNIT_LAYER | STRUCTURE_LAYER)

	# Clear previous selection unless shift held
	if not Input.is_key_pressed(KEY_SHIFT):
		_clear_selection()

	if hit and hit.collider:
		var unit := _get_selectable_parent(hit.collider)
		if unit:
			_add_to_selection(unit)


func _box_select(start: Vector2, end: Vector2) -> void:
	if not Input.is_key_pressed(KEY_SHIFT):
		_clear_selection()

	var rect := Rect2(start, end - start).abs()

	# Check all player squads
	for squad in GameManager.player_squads:
		if _is_in_screen_rect(squad, rect):
			_add_to_selection(squad)


func _is_in_screen_rect(unit: Node3D, rect: Rect2) -> bool:
	if not camera:
		return false

	var screen_pos := camera.unproject_position(unit.global_position)
	return rect.has_point(screen_pos) and not camera.is_position_behind(unit.global_position)


func _raycast_from_screen(screen_pos: Vector2, collision_mask: int) -> Dictionary:
	if not camera:
		return {}

	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 1000.0

	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask)

	return space_state.intersect_ray(query)


func _get_selectable_parent(node: Node) -> Node3D:
	## Walk up tree to find a node with "is_selectable" property
	var current := node
	while current:
		if current.has_method("select"):
			return current as Node3D
		current = current.get_parent()
	return null


func _add_to_selection(unit: Node3D) -> void:
	if unit not in selected_units:
		selected_units.append(unit)
		if unit.has_method("select"):
			unit.select()
	selection_changed.emit(selected_units)


func _remove_from_selection(unit: Node3D) -> void:
	if unit in selected_units:
		selected_units.erase(unit)
		if unit.has_method("deselect"):
			unit.deselect()
	selection_changed.emit(selected_units)


func _clear_selection() -> void:
	for unit in selected_units:
		if unit.has_method("deselect"):
			unit.deselect()
	selected_units.clear()
	selection_changed.emit(selected_units)


func _issue_command(screen_pos: Vector2) -> void:
	if selected_units.is_empty():
		return

	# First check if clicking on an enemy or structure
	var hit := _raycast_from_screen(screen_pos, UNIT_LAYER | STRUCTURE_LAYER)

	if hit and hit.collider:
		var target := _get_selectable_parent(hit.collider)
		if target and target.has_method("is_enemy") and target.is_enemy():
			# Attack command
			for unit in selected_units:
				if unit.has_method("attack"):
					unit.attack(target)
			command_issued.emit("attack", target)
			return

	# Otherwise, move command to ground
	var ground_hit := _raycast_from_screen(screen_pos, TERRAIN_LAYER)
	if ground_hit:
		var target_pos: Vector3 = ground_hit.position

		# Queue if shift held
		var queue := Input.is_key_pressed(KEY_SHIFT)

		for unit in selected_units:
			if unit.has_method("move_to"):
				unit.move_to(target_pos, queue)

		command_issued.emit("move", target_pos)


func get_selected_units() -> Array[Node3D]:
	return selected_units


func has_selection() -> bool:
	return not selected_units.is_empty()
