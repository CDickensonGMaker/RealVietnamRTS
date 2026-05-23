extends Camera3D
## RTS Camera - WASD pan, mouse wheel zoom, middle-drag rotate/tilt
## Adapted from BP_RTS_Dark_Shadows for RealVietnamRTS

@export var pan_speed: float = 30.0
@export var zoom_speed: float = 2.0
@export var rotate_speed: float = 0.005
@export var tilt_speed: float = 0.003
@export var min_zoom: float = 10.0
@export var max_zoom: float = 500.0  # High for tactical overview
@export var min_tilt: float = -85.0  # Almost straight down
@export var max_tilt: float = -15.0  # Shallow angle
@export var center_lerp_speed: float = 5.0

## Camera boundary limits - prevents camera from going too far outside playable area
## Default to 3000m map size (can be overridden via set_map_bounds)
@export var map_bounds_min: Vector3 = Vector3(0, 0, 0)
@export var map_bounds_max: Vector3 = Vector3(3000, 500, 3000)

## Edge scrolling
@export var edge_scroll_enabled: bool = true
@export var edge_margin: int = 20

## Minimum height above terrain
@export var min_terrain_clearance: float = 20.0

var target_position: Vector3
var current_zoom: float = 30.0
var _terrain_integration: Node = null
var current_tilt: float = -45.0
var is_rotating: bool = false
var last_mouse_pos: Vector2
var _centering_on_target: bool = false
var camera_locked: bool = false  # When true, disables edge scrolling and WASD

# Camera bookmarks (F5-F8)
var _camera_bookmarks: Dictionary = {}


func _ready() -> void:
	add_to_group("battle_camera")
	target_position = global_position
	current_zoom = clampf(global_position.y, min_zoom, max_zoom)
	rotation_degrees.x = current_tilt

	# Get terrain integration for height queries
	_terrain_integration = get_node_or_null("/root/TerrainIntegration")

	print("[RTSCamera] Initialized at position %s" % global_position)


func _input(event: InputEvent) -> void:
	# Mouse wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			current_zoom = maxf(min_zoom, current_zoom - zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			current_zoom = minf(max_zoom, current_zoom + zoom_speed)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			is_rotating = event.pressed
			last_mouse_pos = event.position

	# Middle mouse drag to rotate (X) and tilt (Y)
	if event is InputEventMouseMotion and is_rotating:
		var delta: Vector2 = event.position - last_mouse_pos
		# Horizontal drag = rotate around Y axis
		rotate_y(-delta.x * rotate_speed)
		# Vertical drag = tilt camera angle
		current_tilt -= delta.y * tilt_speed * 50.0
		current_tilt = clampf(current_tilt, min_tilt, max_tilt)
		rotation_degrees.x = current_tilt
		last_mouse_pos = event.position

	# Camera bookmark hotkeys (F5-F8 save, Shift+F5-F8 recall)
	if event is InputEventKey and event.pressed:
		for i in 4:
			var key: int = KEY_F5 + i
			if event.keycode == key:
				if event.shift_pressed:
					snap_to_bookmark(i)
				else:
					save_bookmark(i)
				return


func _process(delta: float) -> void:
	var input_dir := Vector3.ZERO

	# Only process movement input if camera is not locked
	if not camera_locked:
		# WASD movement (using input actions if available, fallback to raw keys)
		if Input.is_action_pressed("camera_pan_up") or Input.is_key_pressed(KEY_W):
			input_dir.z -= 1
		if Input.is_action_pressed("camera_pan_down") or Input.is_key_pressed(KEY_S):
			input_dir.z += 1
		if Input.is_action_pressed("camera_pan_left") or Input.is_key_pressed(KEY_A):
			input_dir.x -= 1
		if Input.is_action_pressed("camera_pan_right") or Input.is_key_pressed(KEY_D):
			input_dir.x += 1

		# Edge scrolling
		if edge_scroll_enabled:
			var viewport := get_viewport()
			if viewport:
				var mouse_pos: Vector2 = viewport.get_mouse_position()
				var screen_size: Vector2 = viewport.get_visible_rect().size

				if mouse_pos.x < edge_margin:
					input_dir.x -= 1
				elif mouse_pos.x > screen_size.x - edge_margin:
					input_dir.x += 1
				if mouse_pos.y < edge_margin:
					input_dir.z -= 1
				elif mouse_pos.y > screen_size.y - edge_margin:
					input_dir.z += 1

		# Apply movement relative to camera rotation
		if input_dir != Vector3.ZERO:
			var move_dir: Vector3 = (global_transform.basis * input_dir).normalized()
			move_dir.y = 0
			target_position += move_dir * pan_speed * delta
			_centering_on_target = false

	# Apply zoom - account for terrain height
	var terrain_height: float = _get_terrain_height_at(target_position)
	target_position.y = terrain_height + current_zoom

	# Clamp camera position to map bounds
	target_position.x = clampf(target_position.x, map_bounds_min.x, map_bounds_max.x)
	target_position.z = clampf(target_position.z, map_bounds_min.z, map_bounds_max.z)

	# Smooth movement
	var lerp_speed: float = center_lerp_speed if _centering_on_target else 8.0
	global_position = global_position.lerp(target_position, delta * lerp_speed)


## Center the camera on a world position
func center_on(world_position: Vector3) -> void:
	# Keep XZ from target, Y stays as zoom height
	target_position.x = world_position.x
	target_position.z = world_position.z + current_zoom * 0.7  # Offset back so target is visible
	_centering_on_target = true


## Center the camera on a unit's position
func center_on_unit(unit: Node3D) -> void:
	if unit and is_instance_valid(unit):
		center_on(unit.global_position)


## Smoothly center the camera on a world position
func center_on_position(world_pos: Vector3, instant: bool = false) -> void:
	if instant:
		global_position.x = world_pos.x
		global_position.z = world_pos.z + current_zoom * 0.7
		target_position = global_position
		_centering_on_target = false
	else:
		center_on(world_pos)


## Save current camera position to a bookmark slot (0-3 for F5-F8)
func save_bookmark(slot: int) -> void:
	_camera_bookmarks[slot] = global_position
	print("[RTSCamera] Saved bookmark %d at %s" % [slot, global_position])


## Snap camera to a saved bookmark slot
func snap_to_bookmark(slot: int) -> void:
	if _camera_bookmarks.has(slot):
		var pos: Vector3 = _camera_bookmarks[slot]
		target_position = pos
		current_zoom = pos.y
		_centering_on_target = true
		print("[RTSCamera] Recalled bookmark %d" % slot)


## Check if a bookmark exists
func has_bookmark(slot: int) -> bool:
	return _camera_bookmarks.has(slot)


## Set map bounds (call when map loads)
func set_map_bounds(min_bound: Vector3, max_bound: Vector3) -> void:
	map_bounds_min = min_bound
	map_bounds_max = max_bound
	print("[RTSCamera] Map bounds set: %s to %s" % [min_bound, max_bound])


## Lock/unlock camera movement (for cutscenes, etc.)
func set_locked(locked: bool) -> void:
	camera_locked = locked


## Get terrain height at a position
func _get_terrain_height_at(pos: Vector3) -> float:
	if _terrain_integration and _terrain_integration.has_method("get_height_at"):
		if _terrain_integration.has_method("is_ready") and _terrain_integration.is_ready():
			return _terrain_integration.get_height_at(pos)
	return 0.0


## Move camera to look at a world position (called from minimap)
func focus_on(world_pos: Vector3) -> void:
	target_position.x = world_pos.x
	target_position.z = world_pos.z + current_zoom * 0.7  # Offset back so target is visible
	_centering_on_target = true
