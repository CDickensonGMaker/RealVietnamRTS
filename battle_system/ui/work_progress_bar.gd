extends Node3D
class_name WorkProgressBar

## Floating progress bar for work jobs (clearing, construction, etc.)
## Shows progress toward completion with color transition

## Configuration
@export var bar_width: float = 5.0  # Wider for visibility from high camera
@export var bar_height: float = 0.5  # Taller for visibility
@export var bar_offset: float = 5.0  # Height above job center

## Colors
var background_color: Color = Color(0.15, 0.15, 0.15, 0.85)
var progress_color_start: Color = Color(0.9, 0.7, 0.1)  # Yellow/orange at start
var progress_color_mid: Color = Color(0.7, 0.8, 0.2)    # Yellow-green at mid
var progress_color_end: Color = Color(0.2, 0.8, 0.2)    # Green at completion

## State
var _progress: float = 0.0
var _target_position: Vector3 = Vector3.ZERO

## Visual components
var _background_mesh: MeshInstance3D
var _fill_mesh: MeshInstance3D
var _fill_material: StandardMaterial3D


func _ready() -> void:
	_setup_visuals()


func _process(_delta: float) -> void:
	# Update position to stay above target
	if _target_position != Vector3.ZERO:
		global_position = _target_position + Vector3(0, bar_offset, 0)

	# Billboard - face camera (handle top-down camera properly)
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		var to_camera: Vector3 = camera.global_position - global_position
		# Only billboard horizontally if camera isn't directly above
		if absf(to_camera.x) > 0.1 or absf(to_camera.z) > 0.1:
			look_at(camera.global_position, Vector3.UP)
		else:
			# Camera directly above - keep bar horizontal, face north
			rotation = Vector3.ZERO


func _setup_visuals() -> void:
	# Background bar
	_background_mesh = MeshInstance3D.new()
	var bg_quad := QuadMesh.new()
	bg_quad.size = Vector2(bar_width, bar_height)
	_background_mesh.mesh = bg_quad

	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = background_color
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 10
	_background_mesh.material_override = bg_mat

	add_child(_background_mesh)

	# Progress fill bar
	_fill_mesh = MeshInstance3D.new()
	var fill_quad := QuadMesh.new()
	fill_quad.size = Vector2(bar_width - 0.08, bar_height - 0.06)
	_fill_mesh.mesh = fill_quad
	_fill_mesh.position.z = 0.01  # Slightly in front

	_fill_material = StandardMaterial3D.new()
	_fill_material.albedo_color = progress_color_start
	_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_material.no_depth_test = true
	_fill_material.render_priority = 11
	_fill_mesh.material_override = _fill_material

	add_child(_fill_mesh)

	# Initial update
	_update_fill()


## Set the target position for the progress bar to float above
func set_target_position(pos: Vector3) -> void:
	_target_position = pos
	global_position = pos + Vector3(0, bar_offset, 0)


## Set progress value (0.0 to 1.0)
func set_progress(value: float) -> void:
	_progress = clampf(value, 0.0, 1.0)
	_update_fill()


## Get current progress
func get_progress() -> float:
	return _progress


func _update_fill() -> void:
	if not _fill_mesh or not _fill_material:
		return

	# Update fill bar width
	var fill_width: float = (bar_width - 0.08) * _progress
	fill_width = maxf(fill_width, 0.01)  # Minimum width to stay visible

	if _fill_mesh.mesh is QuadMesh:
		(_fill_mesh.mesh as QuadMesh).size.x = fill_width

	# Offset to align left edge
	_fill_mesh.position.x = -(bar_width - 0.08) * (1.0 - _progress) * 0.5

	# Color transition: yellow -> yellow-green -> green
	var color: Color
	if _progress < 0.5:
		# Yellow to yellow-green
		color = progress_color_start.lerp(progress_color_mid, _progress * 2.0)
	else:
		# Yellow-green to green
		color = progress_color_mid.lerp(progress_color_end, (_progress - 0.5) * 2.0)

	_fill_material.albedo_color = color


## Static factory: Create a progress bar at a world position
static func create_at(world_position: Vector3, height_offset: float = 3.0) -> Node3D:
	var script: GDScript = load("res://battle_system/ui/work_progress_bar.gd")
	var bar: Node3D = script.new()
	bar.bar_offset = height_offset
	bar.set_target_position(world_position)
	return bar


## Static factory: Create and attach to a job node
static func create_for_node(node: Node3D, height_offset: float = 3.0) -> Node3D:
	var script: GDScript = load("res://battle_system/ui/work_progress_bar.gd")
	var bar: Node3D = script.new()
	bar.bar_offset = height_offset
	node.add_child(bar)
	# Bar will follow parent node automatically
	bar._target_position = Vector3.ZERO  # Disable manual position tracking
	bar.position = Vector3(0, height_offset, 0)
	return bar
