extends Node3D
class_name FloatingHealthBar

## Floating health bar that follows a unit
## Shows health, suppression, and ammo status

## Configuration
@export var bar_width: float = 1.5
@export var bar_height: float = 0.15
@export var bar_offset: float = 2.5  # Height above unit
@export var show_when_full: bool = false
@export var fade_delay: float = 3.0  # Seconds before fading after damage

## Colors
var health_color_full: Color = Color(0.2, 0.8, 0.2)  # Green
var health_color_mid: Color = Color(0.9, 0.9, 0.2)   # Yellow
var health_color_low: Color = Color(0.9, 0.2, 0.2)   # Red
var background_color: Color = Color(0.1, 0.1, 0.1, 0.8)
var suppression_color: Color = Color(0.9, 0.5, 0.1, 0.7)  # Orange

## State
var _target_unit: Node3D = null
var _health_ratio: float = 1.0
var _suppression_ratio: float = 0.0
var _visible_timer: float = 0.0
var _is_visible: bool = false

## Visual components
var _background_mesh: MeshInstance3D
var _health_mesh: MeshInstance3D
var _suppression_mesh: MeshInstance3D
var _health_material: StandardMaterial3D
var _suppression_material: StandardMaterial3D


func _ready() -> void:
	_setup_visuals()
	visible = false


func _process(delta: float) -> void:
	if not is_instance_valid(_target_unit):
		queue_free()
		return

	# Update position to follow unit
	global_position = _target_unit.global_position + Vector3(0, bar_offset, 0)

	# Billboard - face camera
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		look_at(camera.global_position, Vector3.UP)

	# Handle visibility timer
	if _visible_timer > 0:
		_visible_timer -= delta
		if _visible_timer <= 0:
			_set_bar_visible(false)


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

	# Health bar
	_health_mesh = MeshInstance3D.new()
	var health_quad := QuadMesh.new()
	health_quad.size = Vector2(bar_width - 0.05, bar_height - 0.03)
	_health_mesh.mesh = health_quad
	_health_mesh.position.z = 0.01  # Slightly in front

	_health_material = StandardMaterial3D.new()
	_health_material.albedo_color = health_color_full
	_health_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_health_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_health_material.no_depth_test = true
	_health_material.render_priority = 11
	_health_mesh.material_override = _health_material

	add_child(_health_mesh)

	# Suppression overlay (below health bar)
	_suppression_mesh = MeshInstance3D.new()
	var supp_quad := QuadMesh.new()
	supp_quad.size = Vector2(bar_width - 0.05, bar_height * 0.4)
	_suppression_mesh.mesh = supp_quad
	_suppression_mesh.position.y = -bar_height * 0.7
	_suppression_mesh.position.z = 0.01

	_suppression_material = StandardMaterial3D.new()
	_suppression_material.albedo_color = suppression_color
	_suppression_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_suppression_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_suppression_material.no_depth_test = true
	_suppression_material.render_priority = 11
	_suppression_mesh.material_override = _suppression_material
	_suppression_mesh.visible = false

	add_child(_suppression_mesh)


func setup(unit: Node3D) -> void:
	"""Attach to a unit"""
	_target_unit = unit

	# Connect to unit signals
	if unit.has_signal("health_changed"):
		unit.health_changed.connect(_on_health_changed)
	if unit.has_signal("suppression_changed"):
		unit.suppression_changed.connect(_on_suppression_changed)

	# Initial update
	if unit.has_method("get"):
		if unit.get("current_health") != null and unit.get("max_health") != null:
			_update_health(unit.current_health, unit.max_health)
		if unit.get("suppression_level") != null:
			_on_suppression_changed(unit.suppression_level)


func _on_health_changed(current: float, maximum: float) -> void:
	_update_health(current, maximum)
	_show_bar()


func _update_health(current: float, maximum: float) -> void:
	_health_ratio = clampf(current / maximum, 0.0, 1.0) if maximum > 0 else 0.0

	# Update health bar scale (shrink from right)
	var health_width: float = (bar_width - 0.05) * _health_ratio
	if _health_mesh.mesh is QuadMesh:
		(_health_mesh.mesh as QuadMesh).size.x = health_width

	# Offset to align left edge
	_health_mesh.position.x = -(bar_width - 0.05) * (1.0 - _health_ratio) * 0.5

	# Update color based on health
	var color: Color
	if _health_ratio > 0.6:
		color = health_color_full.lerp(health_color_mid, (1.0 - _health_ratio) / 0.4)
	elif _health_ratio > 0.3:
		color = health_color_mid.lerp(health_color_low, (0.6 - _health_ratio) / 0.3)
	else:
		color = health_color_low

	_health_material.albedo_color = color


func _on_suppression_changed(level: float) -> void:
	_suppression_ratio = clampf(level, 0.0, 1.0)

	# Show suppression bar if suppressed
	_suppression_mesh.visible = _suppression_ratio > 0.1

	if _suppression_mesh.visible:
		# Update suppression bar width
		var supp_width: float = (bar_width - 0.05) * _suppression_ratio
		if _suppression_mesh.mesh is QuadMesh:
			(_suppression_mesh.mesh as QuadMesh).size.x = supp_width
		_suppression_mesh.position.x = -(bar_width - 0.05) * (1.0 - _suppression_ratio) * 0.5

		_show_bar()


func _show_bar() -> void:
	"""Show the health bar temporarily"""
	if not show_when_full and _health_ratio >= 1.0 and _suppression_ratio <= 0.1:
		return

	_set_bar_visible(true)
	_visible_timer = fade_delay


func _set_bar_visible(vis: bool) -> void:
	_is_visible = vis
	visible = vis


## Force show the bar
func show_bar() -> void:
	_show_bar()


## Check if bar is currently visible
func is_bar_visible() -> bool:
	return _is_visible
