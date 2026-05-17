extends Camera3D
## RTSCamera - Supreme Commander-style strategic zoom camera
## Supports WASD pan, scroll zoom (ground to strategic), rotation, edge scroll

signal zoom_level_changed(level: float)

# Camera bounds
@export var min_height: float = 5.0   # Ground level view
@export var max_height: float = 100.0  # Strategic overview
@export var map_bounds: Vector2 = Vector2(200, 200)  # Map size limits

# Movement speeds
@export var pan_speed: float = 30.0
@export var zoom_speed: float = 8.0
@export var rotation_speed: float = 2.0
@export var edge_scroll_margin: int = 20
@export var edge_scroll_speed: float = 20.0

# Current state
var target_position: Vector3 = Vector3.ZERO
var target_height: float = 20.0
var current_rotation: float = 0.0  # Y-axis rotation in radians

# Smoothing
var position_smoothing: float = 8.0
var height_smoothing: float = 6.0

# Camera arm (the camera rotates around this point)
var pivot_point: Vector3 = Vector3.ZERO


func _ready() -> void:
	# Initialize camera position
	target_position = Vector3(map_bounds.x / 2, 0, map_bounds.y / 2)
	pivot_point = target_position  # Start looking at center, not origin
	target_height = 30.0
	_update_camera_transform()


func _process(delta: float) -> void:
	_handle_keyboard_input(delta)
	_handle_edge_scroll(delta)
	_smooth_camera_movement(delta)


func _unhandled_input(event: InputEvent) -> void:
	# Mouse wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_height = max(min_height, target_height - zoom_speed)
			zoom_level_changed.emit(_get_zoom_level())
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_height = min(max_height, target_height + zoom_speed)
			zoom_level_changed.emit(_get_zoom_level())

	# Middle mouse drag for rotation
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		current_rotation -= event.relative.x * rotation_speed * 0.01


func _handle_keyboard_input(delta: float) -> void:
	var input_dir := Vector2.ZERO

	if Input.is_action_pressed("camera_pan_up"):
		input_dir.y -= 1
	if Input.is_action_pressed("camera_pan_down"):
		input_dir.y += 1
	if Input.is_action_pressed("camera_pan_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("camera_pan_right"):
		input_dir.x += 1

	if Input.is_action_pressed("camera_rotate_left"):
		current_rotation += rotation_speed * delta
	if Input.is_action_pressed("camera_rotate_right"):
		current_rotation -= rotation_speed * delta

	if input_dir != Vector2.ZERO:
		_apply_movement(input_dir.normalized() * pan_speed * delta)


func _handle_edge_scroll(delta: float) -> void:
	var viewport := get_viewport()
	if not viewport:
		return

	var mouse_pos := viewport.get_mouse_position()
	var screen_size := viewport.get_visible_rect().size
	var input_dir := Vector2.ZERO

	if mouse_pos.x < edge_scroll_margin:
		input_dir.x -= 1
	elif mouse_pos.x > screen_size.x - edge_scroll_margin:
		input_dir.x += 1

	if mouse_pos.y < edge_scroll_margin:
		input_dir.y -= 1
	elif mouse_pos.y > screen_size.y - edge_scroll_margin:
		input_dir.y += 1

	if input_dir != Vector2.ZERO:
		_apply_movement(input_dir.normalized() * edge_scroll_speed * delta)


func _apply_movement(movement: Vector2) -> void:
	# Transform movement based on camera rotation
	var rotated := movement.rotated(-current_rotation)
	target_position.x += rotated.x
	target_position.z += rotated.y

	# Clamp to map bounds
	target_position.x = clamp(target_position.x, 0, map_bounds.x)
	target_position.z = clamp(target_position.z, 0, map_bounds.y)


func _smooth_camera_movement(delta: float) -> void:
	# Smooth position
	pivot_point = pivot_point.lerp(target_position, position_smoothing * delta)

	# Smooth height
	var current_height := global_position.y
	var new_height := lerpf(current_height, target_height, height_smoothing * delta)

	_update_camera_transform(new_height)


func _update_camera_transform(height: float = target_height) -> void:
	# Calculate camera offset based on height (higher = further back)
	var tilt_factor := remap(height, min_height, max_height, 0.5, 0.1)
	var offset_distance := height * tilt_factor

	# Position camera behind and above pivot
	var offset := Vector3(0, height, offset_distance)
	offset = offset.rotated(Vector3.UP, current_rotation)

	global_position = pivot_point + offset

	# Look at pivot point
	look_at(pivot_point, Vector3.UP)


func _get_zoom_level() -> float:
	## Returns 0.0 (ground) to 1.0 (strategic)
	return remap(target_height, min_height, max_height, 0.0, 1.0)


func is_strategic_view() -> bool:
	## Returns true if zoomed out far enough for NATO symbols
	return _get_zoom_level() > 0.7


func focus_on(world_position: Vector3) -> void:
	## Snap camera focus to a world position
	target_position = world_position
	target_position.y = 0
	pivot_point = target_position  # Snap immediately


func get_ground_position_under_mouse() -> Vector3:
	## Raycast from mouse to ground plane
	var mouse_pos := get_viewport().get_mouse_position()
	var from := project_ray_origin(mouse_pos)
	var to := from + project_ray_normal(mouse_pos) * 1000.0

	# Intersect with Y=0 plane
	var plane := Plane(Vector3.UP, 0)
	var intersection: Variant = plane.intersects_ray(from, to - from)

	if intersection:
		return intersection as Vector3

	return Vector3.ZERO
