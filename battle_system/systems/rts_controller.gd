class_name RTSController extends Node
## Reusable RTS input controller for selection and movement
## Handles: drag-box selection, right-click move, control groups
## Drop into any test scene and connect to camera

signal selection_changed(selected_units: Array[Node3D])
signal move_order_issued(units: Array[Node3D], target: Vector3)
signal attack_order_issued(units: Array[Node3D], target: Node3D)

## Configuration
@export var camera: Camera3D
@export var selection_color: Color = Color(0.2, 0.8, 0.2, 0.3)
@export var selection_border_color: Color = Color(0.2, 0.9, 0.2, 0.8)
@export var ground_layer: int = 1
@export var unit_layers: Array[int] = [2, 3, 4]  # US, VC, NVA

## State
var selected_units: Array[Node3D] = []
var control_groups: Dictionary = {}  # int -> Array[Node3D]

## Drag selection
var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_current: Vector2 = Vector2.ZERO
var _selection_box: Control = null

## Hover
var _hovered_unit: Node3D = null


func _ready() -> void:
	_create_selection_box()

	# Find camera if not assigned
	if not camera:
		camera = get_viewport().get_camera_3d()


func _create_selection_box() -> void:
	"""Create the drag selection box UI"""
	_selection_box = Control.new()
	_selection_box.name = "SelectionBox"
	_selection_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_box.visible = false

	# We'll draw the box in _draw
	var canvas := CanvasLayer.new()
	canvas.name = "SelectionBoxLayer"
	canvas.layer = 100
	add_child(canvas)

	var drawer := SelectionBoxDrawer.new()
	drawer.controller = self
	drawer.name = "SelectionBoxDrawer"
	canvas.add_child(drawer)


func _unhandled_input(event: InputEvent) -> void:
	if not camera:
		return

	# Mouse button events
	if event is InputEventMouseButton:
		_handle_mouse_button(event)

	# Mouse motion for drag
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event)

	# Control groups (1-9)
	if event is InputEventKey and event.pressed:
		_handle_control_group_key(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_drag_select(event.position)
			else:
				_finish_drag_select(event.position)

		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_handle_right_click(event.position)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _is_dragging:
		_drag_current = event.position
	else:
		# Hover detection
		_update_hover(event.position)


func _handle_control_group_key(event: InputEventKey) -> void:
	var key: int = event.keycode
	if key < KEY_1 or key > KEY_9:
		return

	var group_id: int = key - KEY_1  # 0-8

	if Input.is_key_pressed(KEY_CTRL):
		# Ctrl+# = Save group
		_save_control_group(group_id)
	elif Input.is_key_pressed(KEY_SHIFT):
		# Shift+# = Add to group
		_add_to_control_group(group_id)
	else:
		# # = Recall group
		_recall_control_group(group_id)


## Drag Selection

func _start_drag_select(pos: Vector2) -> void:
	_is_dragging = true
	_drag_start = pos
	_drag_current = pos


func _finish_drag_select(pos: Vector2) -> void:
	if not _is_dragging:
		return

	_is_dragging = false
	_drag_current = pos

	var drag_dist: float = _drag_start.distance_to(_drag_current)

	if drag_dist < 5.0:
		# Click select (small drag = click)
		_single_select(_drag_start)
	else:
		# Box select
		_box_select(_drag_start, _drag_current)


func _single_select(screen_pos: Vector2) -> void:
	"""Handle single click selection"""
	var clicked: Node3D = _raycast_unit(screen_pos)

	if clicked:
		if Input.is_key_pressed(KEY_SHIFT):
			# Shift+click: toggle
			_toggle_selection(clicked)
		elif Input.is_key_pressed(KEY_CTRL):
			# Ctrl+click: add/remove
			_toggle_selection(clicked)
		else:
			# Regular click: select only this
			_clear_selection()
			_add_to_selection(clicked)
	else:
		# Clicked empty space
		if not Input.is_key_pressed(KEY_SHIFT) and not Input.is_key_pressed(KEY_CTRL):
			_clear_selection()


func _box_select(start: Vector2, end: Vector2) -> void:
	"""Select all units within the drag box"""
	var rect := Rect2(
		Vector2(minf(start.x, end.x), minf(start.y, end.y)),
		Vector2(absf(end.x - start.x), absf(end.y - start.y))
	)

	# Clear unless shift held
	if not Input.is_key_pressed(KEY_SHIFT):
		_clear_selection()

	# Check all selectable units
	var selectable: Array[Node] = get_tree().get_nodes_in_group("selectable_units")

	for node in selectable:
		if not node is Node3D:
			continue
		var unit: Node3D = node

		# Project unit position to screen
		var screen_pos: Vector2 = camera.unproject_position(unit.global_position)

		if rect.has_point(screen_pos):
			_add_to_selection(unit)


## Selection Management

func _add_to_selection(unit: Node3D) -> void:
	"""Add unit to selection"""
	if unit in selected_units:
		return

	selected_units.append(unit)

	# Call select method if it exists
	if unit.has_method("select"):
		unit.select()

	selection_changed.emit(selected_units)


func _remove_from_selection(unit: Node3D) -> void:
	"""Remove unit from selection"""
	if unit not in selected_units:
		return

	selected_units.erase(unit)

	# Call deselect method if it exists
	if unit.has_method("deselect"):
		unit.deselect()

	selection_changed.emit(selected_units)


func _toggle_selection(unit: Node3D) -> void:
	"""Toggle unit selection"""
	if unit in selected_units:
		_remove_from_selection(unit)
	else:
		_add_to_selection(unit)


func _clear_selection() -> void:
	"""Clear all selection"""
	for unit in selected_units.duplicate():
		if unit.has_method("deselect"):
			unit.deselect()
	selected_units.clear()
	selection_changed.emit(selected_units)


## Right Click Actions

func _handle_right_click(screen_pos: Vector2) -> void:
	"""Handle right-click for move/attack"""
	if selected_units.is_empty():
		return

	# Check for enemy under cursor
	var enemy: Node3D = _raycast_enemy(screen_pos)
	if enemy:
		_issue_attack_order(enemy)
		return

	# Otherwise, move to ground position
	var ground_pos: Vector3 = _raycast_ground(screen_pos)
	if ground_pos != Vector3.INF:
		_issue_move_order(ground_pos)


func _issue_move_order(target: Vector3) -> void:
	"""Issue move order to selected units"""
	for unit in selected_units:
		if unit.has_method("move_to"):
			unit.move_to(target)

	move_order_issued.emit(selected_units, target)


func _issue_attack_order(target: Node3D) -> void:
	"""Issue attack order to selected units"""
	for unit in selected_units:
		if unit.has_method("attack"):
			unit.attack(target)

	attack_order_issued.emit(selected_units, target)


## Control Groups

func _save_control_group(id: int) -> void:
	"""Save current selection as control group"""
	control_groups[id] = selected_units.duplicate()


func _recall_control_group(id: int) -> void:
	"""Recall control group"""
	if not control_groups.has(id):
		return

	_clear_selection()
	var group: Array = control_groups[id]
	for unit in group:
		if is_instance_valid(unit):
			_add_to_selection(unit)


func _add_to_control_group(id: int) -> void:
	"""Add current selection to control group"""
	if not control_groups.has(id):
		control_groups[id] = []

	for unit in selected_units:
		if unit not in control_groups[id]:
			control_groups[id].append(unit)


## Raycasting

func _raycast_unit(screen_pos: Vector2) -> Node3D:
	"""Raycast to find unit under cursor"""
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	var ray_end: Vector3 = ray_origin + ray_dir * 1000.0

	var space_state: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)

	# Build collision mask from unit layers
	var mask: int = 0
	for layer in unit_layers:
		mask |= 1 << (layer - 1)
	query.collision_mask = mask
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return null

	var collider: Node = result.collider

	# Check if collider or parent is selectable
	if collider.is_in_group("selectable_units"):
		return collider

	var parent: Node = collider.get_parent()
	while parent:
		if parent.is_in_group("selectable_units"):
			return parent as Node3D
		parent = parent.get_parent()

	return null


func _raycast_enemy(screen_pos: Vector2) -> Node3D:
	"""Raycast to find enemy under cursor"""
	var unit: Node3D = _raycast_unit(screen_pos)
	if unit and unit.is_in_group("enemy_units"):
		return unit
	return null


func _raycast_ground(screen_pos: Vector2) -> Vector3:
	"""Raycast to find ground position"""
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	var ray_end: Vector3 = ray_origin + ray_dir * 1000.0

	var space_state: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1 << (ground_layer - 1)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return Vector3.INF

	return result.position


func _update_hover(screen_pos: Vector2) -> void:
	"""Update hovered unit"""
	var hovered: Node3D = _raycast_unit(screen_pos)

	if hovered != _hovered_unit:
		# TODO: Visual feedback for hover
		_hovered_unit = hovered


## Getters

func get_selection_rect() -> Rect2:
	"""Get current drag selection rectangle"""
	if not _is_dragging:
		return Rect2()

	return Rect2(
		Vector2(minf(_drag_start.x, _drag_current.x), minf(_drag_start.y, _drag_current.y)),
		Vector2(absf(_drag_current.x - _drag_start.x), absf(_drag_current.y - _drag_start.y))
	)


func is_dragging() -> bool:
	return _is_dragging


## Inner class for drawing selection box

class SelectionBoxDrawer extends Control:
	var controller: RTSController

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if not controller or not controller.is_dragging():
			return

		var rect: Rect2 = controller.get_selection_rect()
		if rect.size.length() < 2.0:
			return

		# Fill
		draw_rect(rect, controller.selection_color, true)
		# Border
		draw_rect(rect, controller.selection_border_color, false, 2.0)
