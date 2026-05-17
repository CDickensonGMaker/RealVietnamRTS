extends Node
## Selection Manager - Click, drag-box, and control group selection for RTS
## Adapted from BP_RTS_Dark_Shadows for RealVietnamRTS
##
## Features:
## - Click selection with shift/ctrl modifiers
## - Drag-box selection with visual rectangle feedback
## - Units in selection box are highlighted before confirmation
## - Control groups (0-9) with save/recall
## - Double-click to select all of same type

const SelectionBoxVisual = preload("res://battle_system/ui/selection_box_visual.gd")

# Selected units (will be Squad nodes once implemented)
var selected_units: Array[Node3D] = []
var saved_groups: Dictionary = {}  # int -> Array[Node3D]

# Drag selection state
var drag_start: Vector2 = Vector2.ZERO
var is_dragging: bool = false

# Selection box visual component
var _selection_box_visual: Control = null

# Double-click detection
var last_click_time: float = 0.0
var last_clicked_unit: Node3D = null
const DOUBLE_CLICK_TIME: float = 0.3

# Hover preview
var _hovered_unit: Node3D = null
var _hover_update_timer: float = 0.0
const HOVER_UPDATE_INTERVAL: float = 0.1

# Unit center height offset for screen-space selection (collision/visual center above ground)
const UNIT_CENTER_OFFSET_Y: float = 0.9


func _ready() -> void:
	# Defer visual creation to ensure scene tree is ready
	call_deferred("_create_selection_box_visual")
	print("[SelectionManager] Initialized")


func _create_selection_box_visual() -> void:
	# Create selection box visual as a child of the root viewport
	_selection_box_visual = SelectionBoxVisual.new()
	_selection_box_visual.name = "SelectionBoxVisual"

	# Add to scene tree - try to find a CanvasLayer first
	var canvas_layer: CanvasLayer = null
	var root: Node = get_tree().root
	if root:
		var scene: Node = root.get_child(root.get_child_count() - 1) if root.get_child_count() > 0 else null
		if scene:
			# Look for existing HUD layer
			for child in scene.get_children():
				if child is CanvasLayer:
					canvas_layer = child
					break

	if canvas_layer:
		canvas_layer.add_child(_selection_box_visual)
	else:
		# Create our own CanvasLayer
		var new_layer := CanvasLayer.new()
		new_layer.name = "SelectionUILayer"
		new_layer.layer = 100
		get_tree().root.call_deferred("add_child", new_layer)
		new_layer.call_deferred("add_child", _selection_box_visual)

	print("[SelectionManager] Selection box visual created")


func _process(delta: float) -> void:
	# Update hover state periodically
	_hover_update_timer += delta
	if _hover_update_timer >= HOVER_UPDATE_INTERVAL:
		_hover_update_timer = 0.0
		_update_hover_state()


func _input(event: InputEvent) -> void:
	# Left-click selection
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# CRITICAL: Ignore clicks over GUI elements (command panel, minimap, etc.)
		# This prevents selection from clearing when clicking UI buttons
		if _is_mouse_over_gui():
			return

		if event.pressed:
			drag_start = event.position
			is_dragging = false
			# Start visual drag box
			if _selection_box_visual:
				_selection_box_visual.start_drag(event.position)
		else:
			if is_dragging:
				_finish_drag_select(event.position)
			else:
				_single_select(event.position)
			is_dragging = false
			# End visual drag box
			if _selection_box_visual:
				_selection_box_visual.finish_drag()

	# Drag detection and preview update
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var dist: float = event.position.distance_to(drag_start)
		if dist > 5:
			is_dragging = true
			# Update visual drag box and preview highlights
			if _selection_box_visual:
				_selection_box_visual.update_drag(event.position)
				_update_selection_preview()

	# Keyboard input
	if event is InputEventKey and event.pressed:
		_handle_key_input(event)


func _handle_key_input(event: InputEventKey) -> void:
	# Ctrl+G: Create next available group (1-9)
	if event.ctrl_pressed and event.keycode == KEY_G:
		_create_next_group()
		return

	# Control groups: Ctrl+0-9 save, 0-9 recall, Shift+0-9 add to selection
	for i in range(10):
		var key: int = KEY_0 + i
		if event.keycode == key:
			if event.ctrl_pressed:
				_save_group(i)
			elif event.shift_pressed:
				_add_group_to_selection(i)
			else:
				_recall_group(i)
			return

	# Space: Focus camera on selected units
	if event.keycode == KEY_SPACE and not selected_units.is_empty():
		_camera_focus_selected()
		return


func _single_select(screen_pos: Vector2) -> void:
	print("[SelectionManager] Click at screen pos: ", screen_pos)
	var unit: Node3D = _raycast_unit(screen_pos)
	var current_time: float = Time.get_unix_time_from_system()

	if unit:
		print("[SelectionManager] Found unit: ", unit.name, " at ", unit.global_position)
	else:
		print("[SelectionManager] No unit found at click position")

	# Check for double-click on same unit
	if unit and unit == last_clicked_unit:
		if current_time - last_click_time < DOUBLE_CLICK_TIME:
			_select_all_of_type(unit)
			last_clicked_unit = null
			return

	last_click_time = current_time
	last_clicked_unit = unit

	# Shift+click: add to selection
	# Ctrl+click: toggle in selection
	if Input.is_key_pressed(KEY_SHIFT):
		if unit and _is_player_unit(unit):
			_add_to_selection(unit)
	elif Input.is_key_pressed(KEY_CTRL):
		if unit and _is_player_unit(unit):
			if unit in selected_units:
				_remove_from_selection(unit)
			else:
				_add_to_selection(unit)
	else:
		# Normal click: clear and select
		clear_selection()
		if unit and _is_player_unit(unit):
			_add_to_selection(unit)


func _finish_drag_select(end_pos: Vector2) -> void:
	# Shift or Ctrl: add to existing selection
	if not Input.is_key_pressed(KEY_CTRL) and not Input.is_key_pressed(KEY_SHIFT):
		clear_selection()

	var box: Rect2 = Rect2(drag_start, end_pos - drag_start).abs()
	for unit in get_tree().get_nodes_in_group("player_units"):
		if _unit_in_screen_rect(unit, box):
			_add_to_selection(unit)


## Update selection preview highlights during drag
func _update_selection_preview() -> void:
	if not _selection_box_visual or not _selection_box_visual.is_dragging():
		return

	var box: Rect2 = _selection_box_visual.get_selection_rect()

	# Only preview if box is large enough
	if box.size.length() < 5:
		_selection_box_visual.set_preview_units([])
		return

	# Find units in box
	var preview_units: Array[Node3D] = []
	for unit in get_tree().get_nodes_in_group("player_units"):
		if _unit_in_screen_rect(unit, box):
			preview_units.append(unit as Node3D)

	_selection_box_visual.set_preview_units(preview_units)


func _add_to_selection(unit: Node3D) -> void:
	if unit not in selected_units:
		selected_units.append(unit)
		# Show selection visual if unit supports it
		if unit.has_method("set_selected_visual"):
			unit.set_selected_visual(true)
		BattleSignals.unit_selected.emit(unit)
		BattleSignals.selection_changed.emit(selected_units)


func _remove_from_selection(unit: Node3D) -> void:
	var idx: int = selected_units.find(unit)
	if idx >= 0:
		selected_units.remove_at(idx)
		if unit.has_method("set_selected_visual"):
			unit.set_selected_visual(false)
		BattleSignals.unit_deselected.emit(unit)
		BattleSignals.selection_changed.emit(selected_units)


func clear_selection() -> void:
	for u in selected_units:
		if is_instance_valid(u) and u.has_method("set_selected_visual"):
			u.set_selected_visual(false)
		BattleSignals.unit_deselected.emit(u)
	selected_units.clear()
	BattleSignals.selection_changed.emit([])


func _save_group(id: int) -> void:
	if selected_units.is_empty():
		return
	saved_groups[id] = selected_units.duplicate()
	print("[SelectionManager] Saved group %d with %d units" % [id, selected_units.size()])


func _recall_group(id: int) -> void:
	if not saved_groups.has(id):
		return
	clear_selection()
	for u in saved_groups[id]:
		if is_instance_valid(u):
			_add_to_selection(u)
	print("[SelectionManager] Recalled group %d" % id)


func _add_group_to_selection(id: int) -> void:
	if not saved_groups.has(id):
		return
	for u in saved_groups[id]:
		if is_instance_valid(u):
			_add_to_selection(u)


func _create_next_group() -> void:
	if selected_units.is_empty():
		return

	# Find first empty slot (1-9)
	for i in range(1, 10):
		var is_empty: bool = not saved_groups.has(i) or saved_groups.get(i, []).is_empty()
		# Check if all units in group are dead
		if saved_groups.has(i):
			var any_valid: bool = false
			for u in saved_groups[i]:
				if is_instance_valid(u):
					any_valid = true
					break
			if not any_valid:
				is_empty = true

		if is_empty:
			_save_group(i)
			return

	# All full - overwrite group 9
	push_warning("[SelectionManager] All 9 control groups are full - overwriting group 9")
	_save_group(9)


func _raycast_unit(screen_pos: Vector2, verbose: bool = true) -> Node3D:
	var camera: Camera3D = _get_battle_camera()
	if not camera:
		if verbose:
			print("[SelectionManager] ERROR: No battle camera found!")
		return null

	var viewport: Viewport = get_viewport()
	var world_3d: World3D = viewport.get_world_3d() if viewport else null
	if not world_3d:
		if verbose:
			print("[SelectionManager] ERROR: No world_3d!")
		return null

	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	var ray_end: Vector3 = ray_origin + ray_dir * 1000

	var space: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	# Check layers 2, 3, 4 (us_units, vc_units, nva_units per project.godot)
	query.collision_mask = 0b1110  # Layers 2, 3, 4

	if verbose:
		print("[SelectionManager] Raycast mask: ", query.collision_mask, " (layers 2,3,4)")

	var result: Dictionary = space.intersect_ray(query)
	if result:
		var collider: Node = result.collider
		if verbose:
			print("[SelectionManager] Raycast HIT: ", collider.name, " (layer: ", collider.collision_layer if collider is CollisionObject3D else "N/A", ")")
		# Walk up to find unit node
		var parent: Node = collider.get_parent()
		while parent:
			if parent.is_in_group("all_units") or parent.is_in_group("player_units"):
				if verbose:
					print("[SelectionManager] Found unit via raycast: ", parent.name)
				return parent as Node3D
			parent = parent.get_parent()
		if verbose:
			print("[SelectionManager] Raycast hit something but no unit in parent chain")
	else:
		if verbose:
			print("[SelectionManager] Raycast missed all units (mask 0b1110)")

	# Fallback: screen-space distance check
	# Use visual center (ground + offset) for accurate click detection
	var closest_unit: Node3D = null
	var closest_dist: float = 30.0  # Slightly increased tolerance

	var all_units: Array[Node] = get_tree().get_nodes_in_group("all_units")

	if verbose:
		print("[SelectionManager] Fallback check - units in 'all_units' group: ", all_units.size())

	for unit in all_units:
		if unit is Node3D:
			# Use visual center position (above ground level)
			var unit_center: Vector3 = unit.global_position + Vector3(0, UNIT_CENTER_OFFSET_Y, 0)
			if camera.is_position_behind(unit_center):
				continue
			var unit_screen_pos: Vector2 = camera.unproject_position(unit_center)
			var dist: float = screen_pos.distance_to(unit_screen_pos)
			if verbose:
				print("[SelectionManager]   - %s at screen dist %.1f px (world: %s, layer: %d)" % [unit.name, dist, unit.global_position, unit.collision_layer if unit is CollisionObject3D else -1])
			if dist < closest_dist:
				closest_dist = dist
				closest_unit = unit

	if verbose:
		if closest_unit:
			print("[SelectionManager] Fallback found: ", closest_unit.name, " at ", closest_dist, " px")
		else:
			print("[SelectionManager] Fallback found nothing within 30px")

	return closest_unit


func _unit_in_screen_rect(unit: Node3D, rect: Rect2) -> bool:
	var camera: Camera3D = _get_battle_camera()
	if not camera:
		return false
	# Use visual center position for accurate drag selection
	var unit_center: Vector3 = unit.global_position + Vector3(0, UNIT_CENTER_OFFSET_Y, 0)
	var screen_pos: Vector2 = camera.unproject_position(unit_center)
	return rect.has_point(screen_pos)


func _is_player_unit(unit: Node3D) -> bool:
	# Check if unit is player-controlled
	if unit.is_in_group("player_units"):
		return true
	if unit.has_method("is_player_controlled"):
		return unit.is_player_controlled()
	if "is_player_controlled" in unit:
		return unit.is_player_controlled
	return false


## Check if mouse is currently over a GUI element (command panel, minimap, etc.)
## This prevents clicks from clearing selection when clicking buttons
func _is_mouse_over_gui() -> bool:
	var viewport: Viewport = get_viewport()
	if not viewport:
		return false

	# Check if any control has mouse focus
	var focused: Control = viewport.gui_get_focus_owner()
	if focused:
		return true

	# Check if mouse is over any HUD control using the GUI system
	# This checks all controls with MOUSE_FILTER_STOP
	var mouse_pos: Vector2 = viewport.get_mouse_position()

	# Walk through HUD layer to find controls under mouse
	var hud_layer: CanvasLayer = get_node_or_null("/root/BattleHUD/HUDLayer")
	if hud_layer:
		for child in hud_layer.get_children():
			if child is Control:
				if _is_point_in_control(child as Control, mouse_pos):
					return true

	return false


## Recursively check if a point is inside a control or its children
func _is_point_in_control(control: Control, point: Vector2) -> bool:
	if not control.visible:
		return false

	# Skip controls that pass through mouse events
	if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		# Check children anyway
		for child in control.get_children():
			if child is Control:
				if _is_point_in_control(child as Control, point):
					return true
		return false

	# Check if point is in this control's rect
	var rect: Rect2 = control.get_global_rect()
	if rect.has_point(point):
		# If this control stops mouse events, we're over GUI
		if control.mouse_filter == Control.MOUSE_FILTER_STOP:
			return true

		# Check children
		for child in control.get_children():
			if child is Control:
				if _is_point_in_control(child as Control, point):
					return true

		# Control passes through but point is inside
		return false

	return false


func _select_all_of_type(unit: Node3D) -> void:
	"""Select all units of the same type on screen"""
	clear_selection()

	# Get unit type - check for unit_type property or data.unit_type
	var target_type = null
	if "unit_type" in unit:
		target_type = unit.unit_type
	elif "data" in unit and unit.data and "unit_type" in unit.data:
		target_type = unit.data.unit_type

	if target_type == null:
		# Just select the one unit
		_add_to_selection(unit)
		return

	for u in get_tree().get_nodes_in_group("player_units"):
		var u_type = null
		if "unit_type" in u:
			u_type = u.unit_type
		elif "data" in u and u.data and "unit_type" in u.data:
			u_type = u.data.unit_type

		if u_type == target_type:
			_add_to_selection(u)


# === CAMERA SHORTCUTS ===

var _last_focused_index: int = 0

func _camera_focus_selected() -> void:
	if selected_units.is_empty():
		return
	var camera: Camera3D = _get_battle_camera()
	if not camera:
		return

	# Cycle through selected if multiple
	var target: Node3D = selected_units[_last_focused_index % selected_units.size()]
	_last_focused_index += 1

	if camera.has_method("center_on_unit"):
		camera.center_on_unit(target)
	elif camera.has_method("center_on"):
		camera.center_on(target.global_position)


func _get_battle_camera() -> Camera3D:
	var cameras: Array[Node] = get_tree().get_nodes_in_group("battle_camera")
	return cameras[0] as Camera3D if cameras.size() > 0 else null


# === HOVER PREVIEW ===

func _update_hover_state() -> void:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var unit: Node3D = _raycast_unit(mouse_pos, false)  # silent mode for hover

	# Don't hover units that are already selected
	if unit and unit in selected_units:
		unit = null

	_set_hovered_unit(unit)


func _set_hovered_unit(unit: Node3D) -> void:
	if unit == _hovered_unit:
		return

	_hovered_unit = unit


func get_hovered_unit() -> Node3D:
	return _hovered_unit


# === PUBLIC API ===

## Select a single unit (e.g., from UI)
func select_unit(unit: Node3D) -> void:
	if not unit or not _is_player_unit(unit):
		return
	clear_selection()
	_add_to_selection(unit)


## Add a unit to current selection
func add_to_selection(unit: Node3D) -> void:
	if not unit or not _is_player_unit(unit):
		return
	_add_to_selection(unit)


## Get currently selected units
func get_selected_units() -> Array[Node3D]:
	return selected_units


## Check if any units are selected
func has_selection() -> bool:
	return not selected_units.is_empty()


## Find which control group (if any) contains this unit
func find_group_for(unit: Node3D) -> int:
	for group_id: int in saved_groups.keys():
		var group_members: Array = saved_groups[group_id]
		if unit in group_members:
			return group_id
	return -1


## Check if currently in a drag selection
func is_drag_selecting() -> bool:
	return is_dragging and _selection_box_visual != null and _selection_box_visual.is_dragging()


## Get the current drag selection rectangle in screen coordinates
func get_drag_rect() -> Rect2:
	if _selection_box_visual and _selection_box_visual.is_dragging():
		return _selection_box_visual.get_selection_rect()
	return Rect2()


## Convert screen rect to world bounds (for clearing commands)
## Returns a dictionary with {min_pos: Vector3, max_pos: Vector3}
func screen_rect_to_world_bounds(screen_rect: Rect2) -> Dictionary:
	var camera: Camera3D = _get_battle_camera()
	if not camera:
		return {}

	# Get world positions for all four corners of the screen rect
	var corners: Array[Vector2] = [
		screen_rect.position,  # Top-left
		Vector2(screen_rect.position.x + screen_rect.size.x, screen_rect.position.y),  # Top-right
		screen_rect.position + screen_rect.size,  # Bottom-right
		Vector2(screen_rect.position.x, screen_rect.position.y + screen_rect.size.y)  # Bottom-left
	]

	var world_corners: Array[Vector3] = []
	for corner in corners:
		var world_pos: Vector3 = _raycast_ground(corner)
		if world_pos != Vector3.INF:
			world_corners.append(world_pos)

	if world_corners.is_empty():
		return {}

	# Find min/max bounds
	var min_pos := Vector3(INF, 0, INF)
	var max_pos := Vector3(-INF, 0, -INF)

	for pos in world_corners:
		min_pos.x = minf(min_pos.x, pos.x)
		min_pos.z = minf(min_pos.z, pos.z)
		max_pos.x = maxf(max_pos.x, pos.x)
		max_pos.z = maxf(max_pos.z, pos.z)

	return {
		"min_pos": min_pos,
		"max_pos": max_pos,
		"center": (min_pos + max_pos) * 0.5,
		"size": Vector2(max_pos.x - min_pos.x, max_pos.z - min_pos.z)
	}


## Raycast from screen position to ground plane
func _raycast_ground(screen_pos: Vector2) -> Vector3:
	var camera: Camera3D = _get_battle_camera()
	if not camera:
		return Vector3.INF

	var viewport: Viewport = get_viewport()
	var world_3d: World3D = viewport.get_world_3d() if viewport else null
	if not world_3d:
		return Vector3.INF

	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	var ray_end: Vector3 = ray_origin + ray_dir * 2000

	var space: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1  # Terrain layer

	var result: Dictionary = space.intersect_ray(query)
	if result and result.has("position"):
		return result["position"] as Vector3

	# Fallback: intersect with Y=0 plane
	if ray_dir.y != 0:
		var t: float = -ray_origin.y / ray_dir.y
		if t > 0:
			return ray_origin + ray_dir * t

	return Vector3.INF
