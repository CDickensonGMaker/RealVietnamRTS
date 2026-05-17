extends Control
class_name SelectionBoxVisual
## SelectionBoxVisual - Visual feedback for box selection
##
## Draws a rectangle with shader effect while dragging to select units.
## Units within the box are highlighted (made lighter) before confirming selection.
## Reference: BP RTS Dark Shadows style marquee selection.

signal selection_started(start_pos: Vector2)
signal selection_updated(rect: Rect2)
signal selection_finished(rect: Rect2)
signal selection_cancelled()

## Visual settings
@export_group("Colors")
@export var fill_color: Color = Color(0.2, 0.6, 1.0, 0.15)
@export var border_color: Color = Color(0.3, 0.7, 1.0, 0.9)
@export var scanline_color: Color = Color(0.4, 0.8, 1.0, 0.3)

@export_group("Style")
@export var border_width: float = 2.0
@export var scanline_spacing: float = 12.0
@export var scanline_speed: float = 30.0
@export var corner_radius: float = 3.0
@export var min_drag_distance: float = 5.0

var _start_pos: Vector2 = Vector2.ZERO
var _current_pos: Vector2 = Vector2.ZERO
var _is_dragging: bool = false

## Shader box ColorRect
var _shader_box: ColorRect
var _shader_material: ShaderMaterial

## Units currently being previewed (within box but not yet selected)
var _preview_units: Array[Node3D] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 100  # Draw on top of other UI

	_setup_shader_box()


func _setup_shader_box() -> void:
	# Create the shader material
	var shader: Shader = load("res://battle_system/ui/shaders/selection_box.gdshader")
	if shader:
		_shader_material = ShaderMaterial.new()
		_shader_material.shader = shader
		_update_shader_params()
	else:
		push_warning("[SelectionBoxVisual] Could not load selection box shader, using fallback")

	# Create ColorRect for shader rendering
	_shader_box = ColorRect.new()
	_shader_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shader_box.visible = false

	if _shader_material:
		_shader_box.material = _shader_material
		_shader_box.color = Color.WHITE  # Shader handles actual color
	else:
		# Fallback to simple colored box
		_shader_box.color = fill_color

	add_child(_shader_box)


func _update_shader_params() -> void:
	if not _shader_material:
		return

	_shader_material.set_shader_parameter("fill_color", fill_color)
	_shader_material.set_shader_parameter("border_color", border_color)
	_shader_material.set_shader_parameter("scanline_color", scanline_color)
	_shader_material.set_shader_parameter("border_width", border_width)
	_shader_material.set_shader_parameter("scanline_spacing", scanline_spacing)
	_shader_material.set_shader_parameter("scanline_speed", scanline_speed)
	_shader_material.set_shader_parameter("corner_radius", corner_radius)


func _get_selection_rect() -> Rect2:
	return Rect2(_start_pos, _current_pos - _start_pos).abs()


func _update_shader_box() -> void:
	if not _shader_box:
		return

	var rect: Rect2 = _get_selection_rect()

	# Only show if significant size
	if rect.size.length() < min_drag_distance:
		_shader_box.visible = false
		return

	_shader_box.visible = true
	_shader_box.position = rect.position
	_shader_box.size = rect.size


## Start a selection drag
func start_drag(screen_pos: Vector2) -> void:
	_start_pos = screen_pos
	_current_pos = screen_pos
	_is_dragging = true
	_preview_units.clear()
	selection_started.emit(screen_pos)
	_update_shader_box()


## Update the selection drag
func update_drag(screen_pos: Vector2) -> void:
	if not _is_dragging:
		return

	_current_pos = screen_pos
	selection_updated.emit(_get_selection_rect())
	_update_shader_box()


## Finish the selection drag
func finish_drag() -> Rect2:
	if not _is_dragging:
		return Rect2()

	var rect: Rect2 = _get_selection_rect()
	_is_dragging = false

	# Clear previews
	_clear_preview_highlights()

	# Hide shader box
	if _shader_box:
		_shader_box.visible = false

	selection_finished.emit(rect)

	return rect


## Cancel the selection drag
func cancel_drag() -> void:
	if not _is_dragging:
		return

	_is_dragging = false
	_clear_preview_highlights()

	# Hide shader box
	if _shader_box:
		_shader_box.visible = false

	selection_cancelled.emit()


## Check if currently dragging
func is_dragging() -> bool:
	return _is_dragging


## Get the current selection rectangle
func get_selection_rect() -> Rect2:
	return _get_selection_rect()


## Update preview highlights for units in selection box
## Called by SelectionManager to show which units will be selected
func set_preview_units(units: Array[Node3D]) -> void:
	# Remove highlight from old previews that are no longer in selection
	for unit in _preview_units:
		if is_instance_valid(unit) and unit not in units:
			_remove_highlight(unit)

	# Add highlight to new previews
	for unit in units:
		if is_instance_valid(unit) and unit not in _preview_units:
			_apply_highlight(unit)

	_preview_units = units


## Clear all preview highlights
func _clear_preview_highlights() -> void:
	for unit in _preview_units:
		if is_instance_valid(unit):
			_remove_highlight(unit)
	_preview_units.clear()


## Apply highlight effect to unit (make it lighter)
func _apply_highlight(unit: Node3D) -> void:
	if unit.has_method("set_preview_highlight"):
		unit.set_preview_highlight(true)
	else:
		# Fallback: try to brighten materials
		_set_unit_brightness(unit, 1.5)


## Remove highlight effect from unit
func _remove_highlight(unit: Node3D) -> void:
	if unit.has_method("set_preview_highlight"):
		unit.set_preview_highlight(false)
	else:
		# Fallback: restore normal brightness
		_set_unit_brightness(unit, 1.0)


## Set brightness multiplier on unit's materials
func _set_unit_brightness(unit: Node3D, brightness: float) -> void:
	# Store original materials if not already stored
	if brightness > 1.0 and not unit.has_meta("_original_materials"):
		_store_original_materials(unit)

	# Apply brightness to all mesh instances
	_apply_brightness_recursive(unit, brightness)


## Store original materials for later restoration
func _store_original_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		var original_mats: Array = []
		if mesh_inst.mesh:
			for i in mesh_inst.mesh.get_surface_count():
				var mat: Material = mesh_inst.get_active_material(i)
				original_mats.append(mat)
		mesh_inst.set_meta("_original_materials", original_mats)

	for child in node.get_children():
		_store_original_materials(child)


## Apply brightness to all materials recursively
func _apply_brightness_recursive(node: Node, brightness: float) -> void:
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node as MeshInstance3D

		if brightness == 1.0 and mesh_inst.has_meta("_original_materials"):
			# Restore original materials
			var original_mats: Array = mesh_inst.get_meta("_original_materials")
			for i in mini(original_mats.size(), mesh_inst.mesh.get_surface_count() if mesh_inst.mesh else 0):
				mesh_inst.set_surface_override_material(i, original_mats[i])
			mesh_inst.remove_meta("_original_materials")
		elif brightness > 1.0:
			# Create brightened material copies
			if mesh_inst.mesh:
				for i in mesh_inst.mesh.get_surface_count():
					var base_mat: Material = mesh_inst.get_active_material(i)
					if base_mat is StandardMaterial3D:
						var bright_mat: StandardMaterial3D = base_mat.duplicate() as StandardMaterial3D
						bright_mat.emission_enabled = true
						bright_mat.emission = bright_mat.albedo_color * (brightness - 1.0)
						bright_mat.emission_energy_multiplier = 0.5
						mesh_inst.set_surface_override_material(i, bright_mat)

	for child in node.get_children():
		_apply_brightness_recursive(child, brightness)


## Switch to blue color scheme
func set_blue_theme() -> void:
	fill_color = Color(0.2, 0.6, 1.0, 0.15)
	border_color = Color(0.3, 0.7, 1.0, 0.9)
	scanline_color = Color(0.4, 0.8, 1.0, 0.3)
	_update_shader_params()


## Switch to green color scheme
func set_green_theme() -> void:
	fill_color = Color(0.2, 1.0, 0.4, 0.15)
	border_color = Color(0.3, 1.0, 0.5, 0.9)
	scanline_color = Color(0.4, 1.0, 0.6, 0.3)
	_update_shader_params()
