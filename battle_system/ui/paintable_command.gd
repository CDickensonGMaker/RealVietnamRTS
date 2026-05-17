class_name PaintableCommand
extends Node
## PaintableCommand - Controller for drag-paint, polyline, and single-click input
##
## Handles the input for painting construction areas on the terrain.
## Provides three input modes:
## - RECT: Drag from corner to corner for area jobs (Clear, Flatten)
## - POLYLINE: Click points to form a path for line jobs (Road)
## - SINGLE: Single click for point jobs (Build, FillCrater)

const JobTypes = preload("res://firebase_system/jobs/job_types.gd")

## Signals
signal area_painted(min_corner: Vector3, max_corner: Vector3)
signal polyline_committed(points: PackedVector3Array)
signal single_placement(position: Vector3)
signal line_painted(start_pos: Vector3, end_pos: Vector3)  # For LINE mode (walls, sandbags)
signal paint_cancelled()
signal paint_updated(current_pos: Vector3)  # For live preview updates

## Input mode
enum InputMode {
	NONE,
	RECT,       # Drag-paint rectangle
	POLYLINE,   # Click points to form a line
	SINGLE,     # Single click placement
	LINE,       # Drag to paint a line (for walls, sandbags)
}

## Current state
var input_mode: InputMode = InputMode.NONE
var is_painting: bool = false
var drag_start: Vector3 = Vector3.INF
var current_position: Vector3 = Vector3.ZERO
var polyline_points: PackedVector3Array = PackedVector3Array()

## Associated job type (for visual feedback)
var current_job_type: JobTypes.JobType = JobTypes.JobType.CLEAR_TERRAIN

## Minimum drag distance to register as an area (prevents accidental tiny areas)
const MIN_DRAG_DISTANCE := 2.0

## Maximum points in a polyline
const MAX_POLYLINE_POINTS := 50

## Camera reference for raycasting
var camera: Camera3D = null

## Preview mesh
var preview: Node3D = null


func _ready() -> void:
	set_process_input(false)  # Only process when active


func _input(event: InputEvent) -> void:
	if input_mode == InputMode.NONE:
		return

	# Update camera reference
	if not camera:
		camera = get_viewport().get_camera_3d()
		if not camera:
			return

	# Handle mouse movement
	if event is InputEventMouseMotion:
		_update_cursor_position(event.position)
		paint_updated.emit(current_position)

	# Handle mouse buttons
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_handle_mouse_button(mb)

	# Handle keyboard
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed:
			_handle_key(key)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match input_mode:
		InputMode.RECT:
			_handle_rect_input(event)
		InputMode.POLYLINE:
			_handle_polyline_input(event)
		InputMode.SINGLE:
			_handle_single_input(event)
		InputMode.LINE:
			_handle_line_input(event)


func _handle_rect_input(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Start drag
			drag_start = current_position
			is_painting = true
		else:
			# End drag - commit area
			if is_painting and drag_start != Vector3.INF:
				var min_corner := Vector3(
					minf(drag_start.x, current_position.x),
					0,
					minf(drag_start.z, current_position.z)
				)
				var max_corner := Vector3(
					maxf(drag_start.x, current_position.x),
					0,
					maxf(drag_start.z, current_position.z)
				)

				# Check minimum size
				var size := max_corner - min_corner
				if size.x >= MIN_DRAG_DISTANCE and size.z >= MIN_DRAG_DISTANCE:
					area_painted.emit(min_corner, max_corner)
				else:
					# Too small - treat as click at center
					var center := (min_corner + max_corner) * 0.5
					single_placement.emit(center)

			is_painting = false
			drag_start = Vector3.INF

	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# Cancel
		_cancel()


func _handle_polyline_input(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Add point to polyline
		if polyline_points.size() < MAX_POLYLINE_POINTS:
			polyline_points.append(current_position)
			paint_updated.emit(current_position)

	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if polyline_points.size() >= 2:
			# Commit polyline
			polyline_committed.emit(polyline_points)
			polyline_points.clear()
		else:
			# Not enough points - cancel
			_cancel()


func _handle_single_input(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		single_placement.emit(current_position)

	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel()


func _handle_line_input(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Start line
			drag_start = current_position
			is_painting = true
		else:
			# End line - commit if long enough
			if is_painting and drag_start != Vector3.INF:
				var length: float = (current_position - drag_start).length()
				if length >= MIN_DRAG_DISTANCE:
					line_painted.emit(drag_start, current_position)
				else:
					# Too short - treat as single click at end
					single_placement.emit(current_position)

			is_painting = false
			drag_start = Vector3.INF

	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel()


func _handle_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ESCAPE:
			_cancel()

		KEY_ENTER, KEY_KP_ENTER:
			# Commit polyline if we have enough points
			if input_mode == InputMode.POLYLINE and polyline_points.size() >= 2:
				polyline_committed.emit(polyline_points)
				polyline_points.clear()
				deactivate()

		KEY_BACKSPACE:
			# Remove last polyline point
			if input_mode == InputMode.POLYLINE and polyline_points.size() > 0:
				polyline_points.resize(polyline_points.size() - 1)
				paint_updated.emit(current_position)


func _update_cursor_position(screen_pos: Vector2) -> void:
	if not camera:
		return

	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)

	# Raycast to terrain
	var space: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		ray_origin, ray_origin + ray_dir * 2000.0
	)
	query.collision_mask = 1  # Terrain layer

	var result: Dictionary = space.intersect_ray(query)
	if not result.is_empty() and result.has("position"):
		current_position = result["position"] as Vector3
	else:
		# Fallback: intersect Y=0 plane
		if ray_dir.y != 0:
			var t: float = -ray_origin.y / ray_dir.y
			if t > 0:
				current_position = ray_origin + ray_dir * t


func _cancel() -> void:
	is_painting = false
	drag_start = Vector3.INF
	polyline_points.clear()
	paint_cancelled.emit()
	deactivate()


## Activate the controller for a specific input mode
func activate(mode: InputMode, job_type: JobTypes.JobType = JobTypes.JobType.CLEAR_TERRAIN) -> void:
	input_mode = mode
	current_job_type = job_type
	is_painting = false
	drag_start = Vector3.INF
	polyline_points.clear()
	set_process_input(true)

	camera = get_viewport().get_camera_3d()


## Deactivate the controller
func deactivate() -> void:
	input_mode = InputMode.NONE
	is_painting = false
	drag_start = Vector3.INF
	polyline_points.clear()
	set_process_input(false)


## Check if currently active
func is_active() -> bool:
	return input_mode != InputMode.NONE


## Get the current drag rectangle (for preview)
func get_drag_rect() -> Rect2:
	if not is_painting or drag_start == Vector3.INF:
		return Rect2()

	var min_x: float = minf(drag_start.x, current_position.x)
	var min_z: float = minf(drag_start.z, current_position.z)
	var max_x: float = maxf(drag_start.x, current_position.x)
	var max_z: float = maxf(drag_start.z, current_position.z)

	return Rect2(min_x, min_z, max_x - min_x, max_z - min_z)


## Get polyline points including current cursor position
func get_polyline_preview() -> PackedVector3Array:
	var result := polyline_points.duplicate()
	if input_mode == InputMode.POLYLINE and polyline_points.size() > 0:
		result.append(current_position)
	return result


## Get line endpoints for LINE mode preview (returns [start, end])
func get_line_preview() -> PackedVector3Array:
	var result := PackedVector3Array()
	if is_painting and drag_start != Vector3.INF:
		result.append(drag_start)
		result.append(current_position)
	return result


## Get line length for status display
func get_line_length() -> float:
	if is_painting and drag_start != Vector3.INF:
		return (current_position - drag_start).length()
	return 0.0


## Get status text for UI
func get_status_text() -> String:
	match input_mode:
		InputMode.RECT:
			if is_painting:
				var rect := get_drag_rect()
				return "Area: %.0f x %.0f m" % [rect.size.x, rect.size.y]
			return "Click + drag to select area"

		InputMode.POLYLINE:
			return "Road: %d points (ENTER to finish, ESC to cancel)" % polyline_points.size()

		InputMode.SINGLE:
			return "Click to place"

		InputMode.LINE:
			if is_painting:
				var length := get_line_length()
				return "Wall: %.1f m" % length
			return "Click + drag to draw wall"

		_:
			return ""
