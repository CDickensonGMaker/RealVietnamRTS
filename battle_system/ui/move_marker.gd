extends Node3D
class_name MoveMarker

## Steel Division style move destination marker
## Shows a downward-pointing chevron at the move target, fades out over time

## Configuration
const MARKER_HEIGHT: float = 0.5  # Height above ground
const CHEVRON_SIZE: float = 0.8   # Size of the chevron
const FADE_DURATION: float = 2.5  # Seconds to fade out
const BOB_AMPLITUDE: float = 0.1  # Vertical bob amount
const BOB_SPEED: float = 3.0      # Bob frequency

## Faction colors (matching Steel Division style)
const COLOR_PLAYER: Color = Color(0.2, 0.7, 0.2, 0.9)      # Green
const COLOR_ALLY: Color = Color(0.2, 0.5, 0.9, 0.9)        # Blue
const COLOR_ENEMY: Color = Color(0.9, 0.2, 0.2, 0.9)       # Red
const COLOR_ATTACK_MOVE: Color = Color(0.9, 0.6, 0.1, 0.9) # Orange

## State
var _fade_timer: float = 0.0
var _is_fading: bool = false
var _base_position: Vector3
var _time_alive: float = 0.0
var _marker_color: Color = COLOR_PLAYER
var _is_attack_move: bool = false

## Visual components
var _chevron_mesh: MeshInstance3D
var _chevron_material: StandardMaterial3D
var _stem_mesh: MeshInstance3D
var _stem_material: StandardMaterial3D

## Offset for stacking
var _stack_offset: Vector3 = Vector3.ZERO


func _ready() -> void:
	_setup_visuals()
	_start_fade()


func _process(delta: float) -> void:
	_time_alive += delta

	# Vertical bob animation
	var bob_offset: float = sin(_time_alive * BOB_SPEED) * BOB_AMPLITUDE
	global_position = _base_position + _stack_offset + Vector3(0, MARKER_HEIGHT + bob_offset, 0)

	# Billboard - face camera (only rotate Y axis)
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		var cam_pos: Vector3 = camera.global_position
		var direction: Vector3 = (cam_pos - global_position)
		direction.y = 0
		if direction.length_squared() > 0.01:
			look_at(global_position - direction, Vector3.UP)

	# Handle fade
	if _is_fading:
		_fade_timer -= delta
		var alpha: float = clampf(_fade_timer / FADE_DURATION, 0.0, 1.0)
		_update_alpha(alpha)

		if _fade_timer <= 0:
			queue_free()


func _setup_visuals() -> void:
	# Create chevron (downward pointing arrow)
	_chevron_mesh = MeshInstance3D.new()
	var chevron := _create_chevron_mesh()
	_chevron_mesh.mesh = chevron

	_chevron_material = StandardMaterial3D.new()
	_chevron_material.albedo_color = _marker_color
	_chevron_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_chevron_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_chevron_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_chevron_material.no_depth_test = true
	_chevron_material.render_priority = 5
	_chevron_mesh.material_override = _chevron_material

	add_child(_chevron_mesh)

	# Create stem (vertical line below chevron)
	_stem_mesh = MeshInstance3D.new()
	var stem := _create_stem_mesh()
	_stem_mesh.mesh = stem
	_stem_mesh.position.y = -CHEVRON_SIZE * 0.4

	_stem_material = StandardMaterial3D.new()
	_stem_material.albedo_color = _marker_color
	_stem_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_stem_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_stem_material.no_depth_test = true
	_stem_material.render_priority = 5
	_stem_mesh.material_override = _stem_material

	add_child(_stem_mesh)


func _create_chevron_mesh() -> ArrayMesh:
	## Create a downward-pointing chevron/arrow shape
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()

	# Chevron pointing down (V shape)
	var half_width: float = CHEVRON_SIZE * 0.5
	var height: float = CHEVRON_SIZE * 0.4
	var thickness: float = CHEVRON_SIZE * 0.15

	# Left arm of chevron
	vertices.append(Vector3(-half_width, height, 0))          # 0: top left
	vertices.append(Vector3(-half_width + thickness, height, 0))  # 1: top left inner
	vertices.append(Vector3(0, 0, 0))                          # 2: bottom point
	vertices.append(Vector3(0, thickness, 0))                  # 3: bottom point inner

	# Right arm of chevron
	vertices.append(Vector3(half_width, height, 0))           # 4: top right
	vertices.append(Vector3(half_width - thickness, height, 0))   # 5: top right inner

	# Left arm triangles
	indices.append_array([0, 2, 1])
	indices.append_array([1, 2, 3])

	# Right arm triangles
	indices.append_array([4, 5, 2])
	indices.append_array([5, 3, 2])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _create_stem_mesh() -> ArrayMesh:
	## Create a vertical stem line
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()

	var stem_width: float = CHEVRON_SIZE * 0.08
	var stem_height: float = CHEVRON_SIZE * 0.5

	vertices.append(Vector3(-stem_width, 0, 0))           # 0: top left
	vertices.append(Vector3(stem_width, 0, 0))            # 1: top right
	vertices.append(Vector3(stem_width, -stem_height, 0)) # 2: bottom right
	vertices.append(Vector3(-stem_width, -stem_height, 0))# 3: bottom left

	indices.append_array([0, 3, 1])
	indices.append_array([1, 3, 2])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _start_fade() -> void:
	_is_fading = true
	_fade_timer = FADE_DURATION


func _update_alpha(alpha: float) -> void:
	var color: Color = _marker_color
	color.a = alpha * _marker_color.a
	_chevron_material.albedo_color = color
	_stem_material.albedo_color = color


## Setup the marker at a world position
func setup(world_pos: Vector3, is_player: bool = true, is_attack_move: bool = false) -> void:
	_base_position = world_pos
	_is_attack_move = is_attack_move

	# Choose color based on type
	if is_attack_move:
		_marker_color = COLOR_ATTACK_MOVE
	elif is_player:
		_marker_color = COLOR_PLAYER
	else:
		_marker_color = COLOR_ALLY

	# Apply color
	if _chevron_material:
		_chevron_material.albedo_color = _marker_color
	if _stem_material:
		_stem_material.albedo_color = _marker_color

	global_position = _base_position + Vector3(0, MARKER_HEIGHT, 0)


## Set stack offset for multiple markers in same area
func set_stack_offset(offset: Vector3) -> void:
	_stack_offset = offset


## Get remaining fade time
func get_fade_time_remaining() -> float:
	return _fade_timer


## Check if this marker is for attack-move
func is_attack_move() -> bool:
	return _is_attack_move
