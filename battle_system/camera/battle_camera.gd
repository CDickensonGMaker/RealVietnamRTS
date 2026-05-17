extends Camera3D
class_name BattleCamera
## BattleCamera - RTS camera with pan, zoom, rotation, and edge scroll

signal zoom_level_changed(level: float)
signal camera_moved(new_position: Vector3)

# Camera bounds
@export var min_height: float = 10.0
@export var max_height: float = 150.0
@export var map_size: Vector2 = Vector2(200, 200)

# Movement speeds
@export var pan_speed: float = 40.0
@export var zoom_speed: float = 10.0
@export var rotation_speed: float = 2.0
@export var edge_scroll_margin: int = 20
@export var edge_scroll_speed: float = 30.0

# Current state
var target_position: Vector3 = Vector3(100, 0, 100)
var target_height: float = 50.0
var current_rotation: float = 0.0

# Smoothing
var position_smoothing: float = 8.0
var height_smoothing: float = 6.0

# Pivot point (camera looks at this)
var pivot_point: Vector3 = Vector3(100, 0, 100)

# Edge scroll enabled
var edge_scroll_enabled: bool = true

func _ready() -> void:
	_update_camera_transform()

func _process(delta: float) -> void:
	_handle_keyboard_input(delta)

	if edge_scroll_enabled:
		_handle_edge_scroll(delta)

	_smooth_camera_movement(delta)

func _unhandled_input(event: InputEvent) -> void:
	# Mouse wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_height = maxf(min_height, target_height - zoom_speed)
			zoom_level_changed.emit(get_zoom_level())
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_height = minf(max_height, target_height + zoom_speed)
			zoom_level_changed.emit(get_zoom_level())

	# Middle mouse drag for rotation
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		current_rotation -= event.relative.x * rotation_speed * 0.01

# =============================================================================
# INPUT HANDLING
# =============================================================================

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

	# Keyboard rotation
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

	# Check edges
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
	target_position.x = clampf(target_position.x, 0, map_size.x)
	target_position.z = clampf(target_position.z, 0, map_size.y)

	camera_moved.emit(target_position)

# =============================================================================
# CAMERA TRANSFORM
# =============================================================================

func _smooth_camera_movement(delta: float) -> void:
	# Smooth position
	pivot_point = pivot_point.lerp(target_position, position_smoothing * delta)

	# Smooth height
	var current_height := global_position.y
	var new_height := lerpf(current_height, target_height, height_smoothing * delta)

	_update_camera_transform(new_height)

func _update_camera_transform(height: float = -1.0) -> void:
	if height < 0:
		height = target_height

	# Calculate camera offset based on height
	var tilt_factor := remap(height, min_height, max_height, 0.5, 0.15)
	var offset_distance := height * tilt_factor

	# Position camera behind and above pivot
	var offset := Vector3(0, height, offset_distance)
	offset = offset.rotated(Vector3.UP, current_rotation)

	global_position = pivot_point + offset

	# Look at pivot point
	look_at(pivot_point, Vector3.UP)

# =============================================================================
# PUBLIC INTERFACE
# =============================================================================

func get_zoom_level() -> float:
	## Returns 0.0 (close) to 1.0 (far)
	return remap(target_height, min_height, max_height, 0.0, 1.0)

func is_strategic_view() -> bool:
	## Returns true if zoomed out far enough for strategic icons
	return get_zoom_level() > 0.7

func focus_on(world_position: Vector3) -> void:
	## Instantly focus on a position
	target_position = world_position
	target_position.y = 0
	pivot_point = target_position

func smooth_focus_on(world_position: Vector3) -> void:
	## Smoothly pan to a position
	target_position = world_position
	target_position.y = 0

func get_ground_position_under_mouse() -> Vector3:
	## Get world position under mouse cursor
	var mouse_pos := get_viewport().get_mouse_position()
	var from := project_ray_origin(mouse_pos)
	var direction := project_ray_normal(mouse_pos)

	var plane := Plane(Vector3.UP, 0)
	var intersection: Variant = plane.intersects_ray(from, direction)

	if intersection:
		return intersection as Vector3

	return Vector3.ZERO

func set_edge_scroll_enabled(enabled: bool) -> void:
	edge_scroll_enabled = enabled

func set_map_bounds(size: Vector2) -> void:
	map_size = size
