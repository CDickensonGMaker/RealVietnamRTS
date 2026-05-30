@tool
extends Control
## Building Composer Tool - Clean Rebuild
##
## A "Blender-lite" for composing buildings from pre-made models.
## Place models, transform them, export as construction data.
##
## Controls:
## - Double-click model in tree: Start placing
## - Left-click viewport: Place model / Select object
## - G: Grab mode (move selected, click to confirm)
## - R: Rotate mode (mouse controls rotation, click to confirm)
## - Shift+S: Scale mode (mouse controls scale, click to confirm)
## - ESC: Cancel current operation
## - Delete: Remove selected object
## - WASD: Pan camera
## - Scroll: Zoom
## - Middle-drag: Rotate/tilt camera

const ASSETS_PATH := "res://assets/models/"
const OUTPUT_PATH := "res://assets/buildings/composed/"
const GRID_SIZE := 0.5
const FOOTPRINT_CELL_SIZE := 2.0  # Coarse grid for fast painting (2m cells)

const BuildingData = preload("res://firebase_system/building_data.gd")

# =============================================================================
# STATE MACHINE
# =============================================================================
enum Mode { IDLE, PLACING, GRABBING, SCALING, PAINTING_FOOTPRINT }
var current_mode: Mode = Mode.IDLE

# =============================================================================
# UI REFERENCES
# =============================================================================
var model_tree: Tree
var viewport_container: SubViewportContainer
var viewport: SubViewport
var camera: Camera3D
var properties_panel: VBoxContainer
var name_edit: LineEdit
var category_option: OptionButton
var building_type_option: OptionButton
var link_building_check: CheckBox
var save_button: Button
var status_label: Label
var footprint_info_label: Label

# =============================================================================
# 3D SCENE
# =============================================================================
var workspace: Node3D
var grid_mesh: MeshInstance3D
var selection_box: MeshInstance3D
var preview_ghost: Node3D
var footprint_mesh: MeshInstance3D
var footprint_outline: MeshInstance3D

# =============================================================================
# STATE
# =============================================================================
var placed_objects: Array[Node3D] = []
var selected_object: Node3D = null
var current_model_path: String = ""

# Transform state (for cancel with ESC)
var original_position: Vector3
var original_rotation: Vector3
var original_scale: Vector3

# Footprint (cell-based)
var footprint_cells: Array[Vector2i] = []  # Relative to building origin
var footprint_size: Vector3 = Vector3(2.0, 2.0, 2.0)
var footprint_center: Vector3 = Vector3.ZERO
var footprint_locked: bool = false

# Footprint painting visuals
var footprint_grid_overlay: MeshInstance3D
var painted_cells_mesh: MeshInstance3D
var hover_cell_mesh: MeshInstance3D
var _is_shift_painting: bool = false
var _last_painted_cell: Vector2i = Vector2i(-999, -999)

# Camera
var camera_pivot: Node3D
var camera_distance: float = 15.0
var camera_angle: float = 0.0  # Horizontal rotation
var camera_tilt: float = -50.0  # Vertical tilt (degrees)
var is_camera_rotating: bool = false
var last_mouse_pos: Vector2

const MIN_ZOOM := 5.0
const MAX_ZOOM := 50.0
const MIN_TILT := -85.0
const MAX_TILT := -15.0

# Categories
const CATEGORIES := [
	"Firebase Perimeter", "Firebase Support", "Firebase Living", "Firebase Heavy",
	"Landing Zone", "Village", "Infrastructure", "Decoration", "Custom"
]


# =============================================================================
# LIFECYCLE
# =============================================================================
func _ready() -> void:
	_setup_ui()
	_setup_3d_scene()
	_scan_models()
	_update_camera()


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return

	_handle_camera_movement(_delta)
	_update_mode_visuals()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return

	# Get viewport rect and check if mouse is inside
	var vp_rect := viewport_container.get_global_rect()
	var mouse_pos := get_global_mouse_position()
	var in_viewport := vp_rect.has_point(mouse_pos)

	# Camera rotation with middle mouse
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			is_camera_rotating = mb.pressed
			last_mouse_pos = mb.position
		elif in_viewport:
			_handle_mouse_button(mb, mouse_pos - vp_rect.position)

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if is_camera_rotating:
			_handle_camera_drag(mm)
		elif current_mode == Mode.PAINTING_FOOTPRINT and _is_shift_painting and in_viewport:
			# Shift+drag painting
			var local_pos := mouse_pos - vp_rect.position
			var coord_scale := Vector2(viewport.size) / vp_rect.size
			var viewport_pos := local_pos * coord_scale
			var world_pos := _screen_to_ground(viewport_pos)
			_paint_cell_at(world_pos)

	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and in_viewport:
			_handle_key_press(key)


# =============================================================================
# INPUT HANDLERS
# =============================================================================
func _handle_mouse_button(mb: InputEventMouseButton, local_pos: Vector2) -> void:
	# Zoom
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		camera_distance = maxf(MIN_ZOOM, camera_distance - 2.0)
		_update_camera()
		return
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		camera_distance = minf(MAX_ZOOM, camera_distance + 2.0)
		_update_camera()
		return

	# Left click
	if mb.button_index == MOUSE_BUTTON_LEFT:
		# Convert from container space to viewport space (stretch = true)
		var vp_rect := viewport_container.get_global_rect()
		var coord_scale := Vector2(viewport.size) / vp_rect.size
		var viewport_pos := local_pos * coord_scale
		var world_pos := _screen_to_ground(viewport_pos)

		if current_mode == Mode.PAINTING_FOOTPRINT:
			# Handle footprint painting
			if mb.pressed:
				_is_shift_painting = mb.shift_pressed
				_paint_cell_at(world_pos)
			else:
				_is_shift_painting = false
				_last_painted_cell = Vector2i(-999, -999)
			return

		if mb.pressed:
			match current_mode:
				Mode.PLACING:
					_place_model_at(world_pos)
				Mode.GRABBING:
					# Click to confirm position
					_confirm_grab(world_pos)
				Mode.SCALING:
					_confirm_scale()
				Mode.IDLE:
					# Select and immediately start moving
					_try_select_and_grab(local_pos)


func _handle_key_press(key: InputEventKey) -> void:
	match key.keycode:
		KEY_ESCAPE:
			_cancel_operation()
		KEY_DELETE, KEY_BACKSPACE:
			_delete_selected()
		KEY_G:
			_start_grab()
		KEY_R:
			# Rotate 10 degrees per press
			_rotate_selected(10.0)
		KEY_S:
			if key.shift_pressed:
				_start_scale()
			elif key.ctrl_pressed:
				_save_building()
		KEY_E:
			# Rotate -10 degrees (opposite direction)
			_rotate_selected(-10.0)


func _handle_camera_movement(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move.z -= 1
	if Input.is_key_pressed(KEY_S) and not Input.is_key_pressed(KEY_SHIFT): move.z += 1
	if Input.is_key_pressed(KEY_A): move.x -= 1
	if Input.is_key_pressed(KEY_D): move.x += 1

	if move != Vector3.ZERO:
		# Rotate movement by camera angle
		var rotated := move.rotated(Vector3.UP, deg_to_rad(camera_angle))
		camera_pivot.position += rotated.normalized() * 20.0 * delta
		_update_camera()


func _handle_camera_drag(mm: InputEventMouseMotion) -> void:
	var delta := mm.position - last_mouse_pos
	camera_angle += delta.x * 0.3
	camera_tilt = clampf(camera_tilt - delta.y * 0.3, MIN_TILT, MAX_TILT)
	last_mouse_pos = mm.position
	_update_camera()


# =============================================================================
# MODE OPERATIONS
# =============================================================================
func _start_placing() -> void:
	if current_model_path.is_empty():
		return

	current_mode = Mode.PLACING
	_create_preview_ghost()
	status_label.text = "PLACING: Click to place " + current_model_path.get_file()


func _place_model_at(world_pos: Vector3) -> void:
	if current_model_path.is_empty():
		return

	var scene: PackedScene = load(current_model_path)
	if not scene:
		status_label.text = "ERROR: Could not load model"
		return

	var instance: Node3D = scene.instantiate()
	instance.name = current_model_path.get_file().get_basename() + "_" + str(placed_objects.size())
	instance.position = _snap_to_grid(world_pos)

	workspace.add_child(instance)
	placed_objects.append(instance)

	# Select the new object
	_select_object(instance)

	# Stay in placing mode for multiple placements
	current_mode = Mode.IDLE
	_clear_preview_ghost()

	_recalculate_footprint()
	_update_objects_list()

	status_label.text = "Placed: " + instance.name + " | G=grab R=rotate Shift+S=scale | Double-click tree for more"


func _start_grab() -> void:
	if not selected_object:
		status_label.text = "Select an object first (click on it)"
		return

	original_position = selected_object.position
	original_rotation = selected_object.rotation
	original_scale = selected_object.scale
	current_mode = Mode.GRABBING
	status_label.text = "GRAB: Move mouse, click to confirm, ESC to cancel"


func _confirm_grab(world_pos: Vector3) -> void:
	if selected_object:
		selected_object.position = _snap_to_grid(world_pos)
		_recalculate_footprint()
		status_label.text = "Moved: " + selected_object.name
	current_mode = Mode.IDLE


func _rotate_selected(degrees: float) -> void:
	# Instant rotation by degrees (R = +10°, E = -10°)
	if not selected_object:
		status_label.text = "Select an object first (click on it)"
		return

	selected_object.rotation.y += deg_to_rad(degrees)
	_update_transform_ui()
	status_label.text = "Rotated: " + str(int(rad_to_deg(selected_object.rotation.y))) + "°"


func _start_scale() -> void:
	if not selected_object:
		status_label.text = "Select an object first (click on it)"
		return

	original_position = selected_object.position
	original_rotation = selected_object.rotation
	original_scale = selected_object.scale
	current_mode = Mode.SCALING
	status_label.text = "SCALE: Move mouse vertically, click to confirm, ESC to cancel"


func _confirm_scale() -> void:
	_recalculate_footprint()
	current_mode = Mode.IDLE
	if selected_object:
		status_label.text = "Scaled: " + selected_object.name


func _cancel_operation() -> void:
	if current_mode == Mode.PLACING:
		_clear_preview_ghost()
		current_mode = Mode.IDLE
		status_label.text = "Placement cancelled"
	elif current_mode == Mode.PAINTING_FOOTPRINT:
		# Exit paint mode without clearing cells
		current_mode = Mode.IDLE
		footprint_grid_overlay.visible = false
		painted_cells_mesh.visible = false
		hover_cell_mesh.visible = false
		_is_shift_painting = false

		var btn: Button = find_child("EditFootprintBtn", true, false)
		if btn:
			btn.text = "Edit Footprint"

		status_label.text = "Exited footprint paint mode | %d cells painted" % footprint_cells.size()
	elif current_mode in [Mode.GRABBING, Mode.SCALING]:
		# Restore original transform
		if selected_object:
			selected_object.position = original_position
			selected_object.rotation = original_rotation
			selected_object.scale = original_scale
			_update_transform_ui()
		current_mode = Mode.IDLE
		status_label.text = "Cancelled - object restored"
	else:
		_select_object(null)
		status_label.text = "Ready"


func _delete_selected() -> void:
	if not selected_object:
		return

	var obj_name := selected_object.name
	placed_objects.erase(selected_object)
	selected_object.queue_free()
	selected_object = null

	_recalculate_footprint()
	_update_objects_list()
	current_mode = Mode.IDLE
	status_label.text = "Deleted: " + obj_name


# =============================================================================
# VISUAL UPDATES (called every frame in _process)
# =============================================================================
func _update_mode_visuals() -> void:
	var vp_rect := viewport_container.get_global_rect()
	var mouse_pos := get_global_mouse_position()

	if not vp_rect.has_point(mouse_pos):
		return

	# Convert from container space to viewport space (stretch = true)
	var local_pos := mouse_pos - vp_rect.position
	var coord_scale := Vector2(viewport.size) / vp_rect.size
	var viewport_pos := local_pos * coord_scale
	var world_pos := _screen_to_ground(viewport_pos)

	match current_mode:
		Mode.PLACING:
			if preview_ghost:
				preview_ghost.position = _snap_to_grid(world_pos)

		Mode.GRABBING:
			# Object follows mouse while grabbing
			if selected_object:
				selected_object.position = _snap_to_grid(world_pos)
				_update_transform_ui()

		Mode.SCALING:
			if selected_object:
				# Scale based on mouse Y relative to viewport center
				var center_y := vp_rect.size.y * 0.5
				var scale_factor := 1.0 + (center_y - local_pos.y) / center_y
				scale_factor = clampf(scale_factor, 0.1, 5.0)
				selected_object.scale = Vector3.ONE * scale_factor

		Mode.PAINTING_FOOTPRINT:
			# Update hover cell preview
			if hover_cell_mesh:
				var cell := _world_to_cell(world_pos)
				var cell_center := _cell_to_world(cell)
				hover_cell_mesh.position = Vector3(cell_center.x, 0.02, cell_center.y)
				hover_cell_mesh.visible = true

	# Update selection box
	_update_selection_box()


func _update_selection_box() -> void:
	if not selection_box:
		return

	if selected_object and current_mode != Mode.PLACING:
		selection_box.visible = true
		var aabb := _get_aabb(selected_object)
		selection_box.position = selected_object.position + aabb.position + aabb.size * 0.5
		selection_box.scale = aabb.size * 1.05
	else:
		selection_box.visible = false


# =============================================================================
# SELECTION
# =============================================================================
func _try_select_and_grab(local_pos: Vector2) -> void:
	# Convert from container space to viewport space (stretch = true)
	var vp_rect := viewport_container.get_global_rect()
	var coord_scale := Vector2(viewport.size) / vp_rect.size
	var viewport_pos := local_pos * coord_scale
	var world_pos := _screen_to_ground(viewport_pos)

	# Distance-based detection (like town editor) - much easier to click than ray/AABB
	var closest_obj: Node3D = null
	var closest_dist: float = 4.0  # 4-unit click radius

	for obj in placed_objects:
		var dist: float = Vector2(world_pos.x, world_pos.z).distance_to(
			Vector2(obj.position.x, obj.position.z)
		)
		if dist < closest_dist:
			closest_dist = dist
			closest_obj = obj

	if closest_obj:
		# Select and immediately start grabbing
		_select_object(closest_obj)
		original_position = closest_obj.position
		original_rotation = closest_obj.rotation
		original_scale = closest_obj.scale
		current_mode = Mode.GRABBING
		status_label.text = "MOVING: " + closest_obj.name + " | Click to place, R/E rotate, Shift+S scale, ESC cancel"
	else:
		_select_object(null)


func _select_object(obj: Node3D) -> void:
	selected_object = obj

	if obj:
		status_label.text = "Selected: " + obj.name + " | G=grab R=rotate Shift+S=scale Delete=remove"
		_update_transform_ui()
	else:
		status_label.text = "No selection | Double-click model in tree to place"


func _ray_intersects_aabb(origin: Vector3, dir: Vector3, aabb: AABB) -> float:
	# Returns distance to intersection, or -1 if no hit
	var t_min := -INF
	var t_max := INF

	for i in 3:
		if absf(dir[i]) < 0.0001:
			if origin[i] < aabb.position[i] or origin[i] > aabb.position[i] + aabb.size[i]:
				return -1.0
		else:
			var t1 := (aabb.position[i] - origin[i]) / dir[i]
			var t2 := (aabb.position[i] + aabb.size[i] - origin[i]) / dir[i]
			if t1 > t2:
				var temp := t1
				t1 = t2
				t2 = temp
			t_min = maxf(t_min, t1)
			t_max = minf(t_max, t2)
			if t_min > t_max:
				return -1.0

	return t_min if t_min >= 0 else t_max


# =============================================================================
# PREVIEW GHOST
# =============================================================================
func _create_preview_ghost() -> void:
	_clear_preview_ghost()

	if current_model_path.is_empty():
		return

	var scene: PackedScene = load(current_model_path)
	if not scene:
		return

	preview_ghost = scene.instantiate()
	preview_ghost.name = "PreviewGhost"
	_make_transparent(preview_ghost)
	workspace.add_child(preview_ghost)


func _clear_preview_ghost() -> void:
	if preview_ghost:
		preview_ghost.queue_free()
		preview_ghost = null


func _make_transparent(node: Node) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.7, 1.0, 0.5)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		node.material_override = mat

	for child in node.get_children():
		_make_transparent(child)


# =============================================================================
# UTILITY
# =============================================================================
func _screen_to_ground(screen_pos: Vector2) -> Vector3:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)

	# Intersect with Y=0 plane
	if absf(dir.y) < 0.001:
		return Vector3.ZERO

	var t := -from.y / dir.y
	if t < 0:
		return Vector3.ZERO

	return from + dir * t


func _snap_to_grid(pos: Vector3) -> Vector3:
	return Vector3(
		roundf(pos.x / GRID_SIZE) * GRID_SIZE,
		0.0,  # Always on ground
		roundf(pos.z / GRID_SIZE) * GRID_SIZE
	)


func _world_to_cell(world_pos: Vector3) -> Vector2i:
	"""Convert world position to footprint cell coordinate."""
	# Cells are at even coordinates (0, 2, 4, ...) with FOOTPRINT_CELL_SIZE = 2.0
	var cell_x := int(floorf(world_pos.x / FOOTPRINT_CELL_SIZE))
	var cell_z := int(floorf(world_pos.z / FOOTPRINT_CELL_SIZE))
	return Vector2i(cell_x, cell_z)


func _cell_to_world(cell: Vector2i) -> Vector2:
	"""Convert footprint cell coordinate to world position (center of cell)."""
	var center_x: float = (cell.x + 0.5) * FOOTPRINT_CELL_SIZE
	var center_z: float = (cell.y + 0.5) * FOOTPRINT_CELL_SIZE
	return Vector2(center_x, center_z)


func _get_aabb(node: Node3D) -> AABB:
	var aabb := AABB()
	var found := false

	if node is MeshInstance3D:
		aabb = node.get_aabb()
		found = true

	for child in node.get_children():
		if child is Node3D:
			var child_aabb := _get_aabb(child)
			if not child_aabb.size.is_zero_approx():
				if found:
					aabb = aabb.merge(child_aabb)
				else:
					aabb = child_aabb
					found = true

	if not found:
		aabb = AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1, 1))

	return aabb


# =============================================================================
# CAMERA
# =============================================================================
func _update_camera() -> void:
	if not camera or not camera_pivot:
		return

	# Position camera relative to pivot
	var offset := Vector3(0, 0, camera_distance)
	offset = offset.rotated(Vector3.RIGHT, deg_to_rad(camera_tilt))
	offset = offset.rotated(Vector3.UP, deg_to_rad(camera_angle))

	camera.position = camera_pivot.position + offset
	camera.look_at(camera_pivot.position, Vector3.UP)


# =============================================================================
# UI SETUP
# =============================================================================
func _setup_ui() -> void:
	# Main horizontal split
	var main_split := HSplitContainer.new()
	main_split.anchor_right = 1.0
	main_split.anchor_bottom = 1.0
	add_child(main_split)

	# Left panel - Model browser
	var left_panel := VBoxContainer.new()
	left_panel.custom_minimum_size.x = 250
	main_split.add_child(left_panel)

	var browser_label := Label.new()
	browser_label.text = "Models (Double-click to place)"
	browser_label.add_theme_font_size_override("font_size", 14)
	left_panel.add_child(browser_label)

	var search_box := LineEdit.new()
	search_box.placeholder_text = "Search..."
	search_box.text_changed.connect(_on_search_changed)
	left_panel.add_child(search_box)

	model_tree = Tree.new()
	model_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	model_tree.item_activated.connect(_on_model_activated)
	model_tree.item_selected.connect(_on_model_selected)
	left_panel.add_child(model_tree)

	# Center - 3D viewport
	var center_panel := VBoxContainer.new()
	center_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.add_child(center_panel)

	# Toolbar
	var toolbar := HBoxContainer.new()
	center_panel.add_child(toolbar)

	var grid_check := CheckBox.new()
	grid_check.text = "Grid"
	grid_check.button_pressed = true
	grid_check.toggled.connect(func(on): grid_mesh.visible = on if grid_mesh else null)
	toolbar.add_child(grid_check)

	var snap_check := CheckBox.new()
	snap_check.text = "Snap (0.5m)"
	snap_check.button_pressed = true
	toolbar.add_child(snap_check)

	# Viewport
	viewport_container = SubViewportContainer.new()
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.stretch = true
	center_panel.add_child(viewport_container)

	viewport = SubViewport.new()
	viewport.size = Vector2i(800, 600)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(viewport)

	# Status bar
	status_label = Label.new()
	status_label.text = "Ready | Double-click a model to start placing"
	status_label.add_theme_font_size_override("font_size", 12)
	center_panel.add_child(status_label)

	# Right panel - Properties
	var right_panel := VBoxContainer.new()
	right_panel.custom_minimum_size.x = 220
	main_split.add_child(right_panel)

	var props_label := Label.new()
	props_label.text = "Building Properties"
	props_label.add_theme_font_size_override("font_size", 14)
	right_panel.add_child(props_label)

	right_panel.add_child(HSeparator.new())

	# Name
	right_panel.add_child(_make_label("Name:"))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "my_building"
	right_panel.add_child(name_edit)

	# Category
	right_panel.add_child(_make_label("Category:"))
	category_option = OptionButton.new()
	for cat in CATEGORIES:
		category_option.add_item(cat)
	right_panel.add_child(category_option)

	right_panel.add_child(HSeparator.new())

	# Building type link
	link_building_check = CheckBox.new()
	link_building_check.text = "Link to building type"
	link_building_check.toggled.connect(func(on): building_type_option.visible = on)
	right_panel.add_child(link_building_check)

	building_type_option = OptionButton.new()
	building_type_option.visible = false
	_populate_building_types()
	right_panel.add_child(building_type_option)

	right_panel.add_child(HSeparator.new())

	# Footprint info
	right_panel.add_child(_make_label("Footprint:"))
	footprint_info_label = Label.new()
	footprint_info_label.text = "Place models to calculate"
	right_panel.add_child(footprint_info_label)

	var lock_btn := Button.new()
	lock_btn.text = "Lock Footprint"
	lock_btn.name = "LockFootprintBtn"
	lock_btn.pressed.connect(_on_lock_footprint)
	right_panel.add_child(lock_btn)

	# Footprint painting buttons
	var edit_fp_btn := Button.new()
	edit_fp_btn.text = "Edit Footprint"
	edit_fp_btn.name = "EditFootprintBtn"
	edit_fp_btn.pressed.connect(_on_edit_footprint)
	right_panel.add_child(edit_fp_btn)

	var clear_fp_btn := Button.new()
	clear_fp_btn.text = "Clear Footprint"
	clear_fp_btn.name = "ClearFootprintBtn"
	clear_fp_btn.pressed.connect(_on_clear_footprint)
	right_panel.add_child(clear_fp_btn)

	var fp_cell_label := Label.new()
	fp_cell_label.name = "FootprintCellLabel"
	fp_cell_label.text = "0 cells"
	right_panel.add_child(fp_cell_label)

	right_panel.add_child(HSeparator.new())

	# Transform controls
	properties_panel = VBoxContainer.new()
	right_panel.add_child(properties_panel)
	_add_transform_controls(properties_panel)

	right_panel.add_child(HSeparator.new())

	# Objects list
	right_panel.add_child(_make_label("Placed Objects:"))
	var objects_list := ItemList.new()
	objects_list.custom_minimum_size.y = 120
	objects_list.name = "ObjectsList"
	right_panel.add_child(objects_list)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(spacer)

	# Buttons
	var clear_btn := Button.new()
	clear_btn.text = "Clear All"
	clear_btn.pressed.connect(_clear_all)
	right_panel.add_child(clear_btn)

	save_button = Button.new()
	save_button.text = "Save Building (.tscn)"
	save_button.pressed.connect(_save_building)
	right_panel.add_child(save_button)

	var export_btn := Button.new()
	export_btn.text = "Export & Link"
	export_btn.pressed.connect(_export_and_link)
	right_panel.add_child(export_btn)

	var help_btn := Button.new()
	help_btn.text = "Help"
	help_btn.pressed.connect(_show_help)
	right_panel.add_child(help_btn)


func _make_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	return lbl


func _add_transform_controls(parent: Control) -> void:
	parent.add_child(_make_label("Selected Transform:"))

	var grid := GridContainer.new()
	grid.columns = 4
	parent.add_child(grid)

	# Position row
	grid.add_child(_make_label("Pos"))
	for axis in ["X", "Y", "Z"]:
		var spin := SpinBox.new()
		spin.name = "Pos" + axis
		spin.min_value = -100
		spin.max_value = 100
		spin.step = 0.5
		spin.custom_minimum_size.x = 55
		spin.value_changed.connect(_on_transform_changed)
		grid.add_child(spin)

	# Rotation row
	grid.add_child(_make_label("Rot"))
	for axis in ["X", "Y", "Z"]:
		var spin := SpinBox.new()
		spin.name = "Rot" + axis
		spin.min_value = -180
		spin.max_value = 180
		spin.step = 15
		spin.custom_minimum_size.x = 55
		spin.value_changed.connect(_on_transform_changed)
		grid.add_child(spin)

	# Scale row
	grid.add_child(_make_label("Scale"))
	var scale_spin := SpinBox.new()
	scale_spin.name = "Scale"
	scale_spin.min_value = 0.1
	scale_spin.max_value = 10.0
	scale_spin.step = 0.1
	scale_spin.value = 1.0
	scale_spin.custom_minimum_size.x = 55
	scale_spin.value_changed.connect(_on_transform_changed)
	grid.add_child(scale_spin)


# =============================================================================
# 3D SCENE SETUP
# =============================================================================
func _setup_3d_scene() -> void:
	# World
	var world := World3D.new()
	viewport.world_3d = world

	# Camera pivot (for orbiting)
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	viewport.add_child(camera_pivot)

	# Camera
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 50
	viewport.add_child(camera)

	# Workspace
	workspace = Node3D.new()
	workspace.name = "Workspace"
	viewport.add_child(workspace)

	# Lighting
	var dir_light := DirectionalLight3D.new()
	dir_light.rotation_degrees = Vector3(-45, 45, 0)
	dir_light.light_energy = 1.0
	dir_light.shadow_enabled = true
	viewport.add_child(dir_light)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.15, 0.18, 0.22)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.6)
	env.ambient_light_energy = 0.5
	env_node.environment = env
	viewport.add_child(env_node)

	# Grid
	_create_grid()

	# Selection box
	selection_box = MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3.ONE
	selection_box.mesh = box_mesh
	var sel_mat := StandardMaterial3D.new()
	sel_mat.albedo_color = Color(0.2, 0.8, 1.0, 0.3)
	sel_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	selection_box.material_override = sel_mat
	selection_box.visible = false
	viewport.add_child(selection_box)

	# Footprint visualization (hidden by default)
	_create_footprint_visuals()


func _create_grid() -> void:
	grid_mesh = MeshInstance3D.new()
	var im := ImmediateMesh.new()
	grid_mesh.mesh = im

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.4, 0.4, 0.4, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_mesh.material_override = mat

	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var extent := 20
	for i in range(-extent, extent + 1):
		var _c := 0.3 if i % 5 == 0 else 0.5  # TODO: use for variable grid line colors
		# X lines
		im.surface_add_vertex(Vector3(i, 0, -extent))
		im.surface_add_vertex(Vector3(i, 0, extent))
		# Z lines
		im.surface_add_vertex(Vector3(-extent, 0, i))
		im.surface_add_vertex(Vector3(extent, 0, i))
	im.surface_end()

	viewport.add_child(grid_mesh)


func _create_footprint_visuals() -> void:
	# Ground fill (for locked footprint display)
	footprint_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2, 2)
	footprint_mesh.mesh = plane

	var fill_mat := StandardMaterial3D.new()
	fill_mat.albedo_color = Color(0.2, 0.8, 0.2, 0.3)
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	footprint_mesh.material_override = fill_mat
	footprint_mesh.position.y = 0.01
	footprint_mesh.visible = false  # Hidden until locked
	viewport.add_child(footprint_mesh)

	# Outline
	footprint_outline = MeshInstance3D.new()
	footprint_outline.visible = false  # Hidden until locked
	viewport.add_child(footprint_outline)

	# Footprint grid overlay (shown during PAINTING_FOOTPRINT mode)
	footprint_grid_overlay = MeshInstance3D.new()
	footprint_grid_overlay.name = "FootprintGridOverlay"
	var grid_mat := StandardMaterial3D.new()
	grid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_mat.albedo_color = Color(0.8, 0.8, 0.2, 0.4)
	grid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	footprint_grid_overlay.material_override = grid_mat
	footprint_grid_overlay.visible = false
	viewport.add_child(footprint_grid_overlay)

	# Painted cells mesh (green squares for painted cells)
	painted_cells_mesh = MeshInstance3D.new()
	painted_cells_mesh.name = "PaintedCellsMesh"
	var painted_mat := StandardMaterial3D.new()
	painted_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	painted_mat.albedo_color = Color(0.2, 0.9, 0.2, 0.5)
	painted_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	painted_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	painted_cells_mesh.material_override = painted_mat
	painted_cells_mesh.visible = false
	viewport.add_child(painted_cells_mesh)

	# Hover cell preview (shows cell about to be toggled)
	hover_cell_mesh = MeshInstance3D.new()
	hover_cell_mesh.name = "HoverCellMesh"
	var hover_plane := PlaneMesh.new()
	hover_plane.size = Vector2(FOOTPRINT_CELL_SIZE - 0.1, FOOTPRINT_CELL_SIZE - 0.1)
	hover_cell_mesh.mesh = hover_plane
	var hover_mat := StandardMaterial3D.new()
	hover_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hover_mat.albedo_color = Color(1.0, 1.0, 0.3, 0.4)
	hover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hover_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	hover_cell_mesh.material_override = hover_mat
	hover_cell_mesh.position.y = 0.02
	hover_cell_mesh.visible = false
	viewport.add_child(hover_cell_mesh)


# =============================================================================
# MODEL BROWSER
# =============================================================================
func _scan_models() -> void:
	model_tree.clear()
	var root := model_tree.create_item()
	root.set_text(0, "Models")
	_scan_directory(ASSETS_PATH, root)


func _scan_directory(path: String, parent_item: TreeItem) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	var folders: Array[String] = []
	var files: Array[String] = []

	while file_name != "":
		if dir.current_is_dir() and not file_name.begins_with("."):
			folders.append(file_name)
		elif file_name.ends_with(".glb") or file_name.ends_with(".gltf") or file_name.ends_with(".tscn"):
			files.append(file_name)
		file_name = dir.get_next()

	dir.list_dir_end()
	folders.sort()
	files.sort()

	for folder in folders:
		var item := model_tree.create_item(parent_item)
		item.set_text(0, folder)
		_scan_directory(path + folder + "/", item)

	for file in files:
		var item := model_tree.create_item(parent_item)
		item.set_text(0, file.get_basename())
		item.set_metadata(0, path + file)


func _on_model_selected() -> void:
	var selected := model_tree.get_selected()
	if selected and selected.get_metadata(0):
		current_model_path = selected.get_metadata(0)


func _on_model_activated() -> void:
	var selected := model_tree.get_selected()
	if selected and selected.get_metadata(0):
		current_model_path = selected.get_metadata(0)
		_start_placing()


func _on_search_changed(text: String) -> void:
	_filter_tree(model_tree.get_root(), text.to_lower())


func _filter_tree(item: TreeItem, filter: String) -> bool:
	if not item:
		return false

	var dominated := filter.is_empty()
	var child := item.get_first_child()

	while child:
		if _filter_tree(child, filter):
			dominated = true
		child = child.get_next()

	var matches := filter.is_empty() or item.get_text(0).to_lower().contains(filter)
	item.visible = matches or dominated
	return matches or dominated


# =============================================================================
# TRANSFORM UI
# =============================================================================
func _update_transform_ui() -> void:
	if not selected_object:
		return

	var pos_x: SpinBox = properties_panel.find_child("PosX", true, false)
	var pos_y: SpinBox = properties_panel.find_child("PosY", true, false)
	var pos_z: SpinBox = properties_panel.find_child("PosZ", true, false)
	var rot_x: SpinBox = properties_panel.find_child("RotX", true, false)
	var rot_y: SpinBox = properties_panel.find_child("RotY", true, false)
	var rot_z: SpinBox = properties_panel.find_child("RotZ", true, false)
	var scale_spin: SpinBox = properties_panel.find_child("Scale", true, false)

	if pos_x: pos_x.set_value_no_signal(selected_object.position.x)
	if pos_y: pos_y.set_value_no_signal(selected_object.position.y)
	if pos_z: pos_z.set_value_no_signal(selected_object.position.z)
	if rot_x: rot_x.set_value_no_signal(rad_to_deg(selected_object.rotation.x))
	if rot_y: rot_y.set_value_no_signal(rad_to_deg(selected_object.rotation.y))
	if rot_z: rot_z.set_value_no_signal(rad_to_deg(selected_object.rotation.z))
	if scale_spin: scale_spin.set_value_no_signal(selected_object.scale.x)


func _on_transform_changed(_value: float) -> void:
	if not selected_object:
		return

	var pos_x: SpinBox = properties_panel.find_child("PosX", true, false)
	var pos_y: SpinBox = properties_panel.find_child("PosY", true, false)
	var pos_z: SpinBox = properties_panel.find_child("PosZ", true, false)
	var rot_x: SpinBox = properties_panel.find_child("RotX", true, false)
	var rot_y: SpinBox = properties_panel.find_child("RotY", true, false)
	var rot_z: SpinBox = properties_panel.find_child("RotZ", true, false)
	var scale_spin: SpinBox = properties_panel.find_child("Scale", true, false)

	if pos_x and pos_y and pos_z:
		selected_object.position = Vector3(pos_x.value, pos_y.value, pos_z.value)
	if rot_x and rot_y and rot_z:
		selected_object.rotation = Vector3(deg_to_rad(rot_x.value), deg_to_rad(rot_y.value), deg_to_rad(rot_z.value))
	if scale_spin:
		selected_object.scale = Vector3.ONE * scale_spin.value


# =============================================================================
# OBJECTS LIST
# =============================================================================
func _update_objects_list() -> void:
	var list: ItemList = find_child("ObjectsList", true, false)
	if not list:
		return

	list.clear()
	for obj in placed_objects:
		list.add_item(obj.name)


func _clear_all() -> void:
	for obj in placed_objects:
		obj.queue_free()
	placed_objects.clear()
	selected_object = null
	current_mode = Mode.IDLE
	_clear_preview_ghost()
	_update_objects_list()
	footprint_locked = false
	_recalculate_footprint()
	status_label.text = "Cleared all objects"


# =============================================================================
# FOOTPRINT
# =============================================================================
func _on_lock_footprint() -> void:
	# If we're about to lock, recalculate first to get accurate bounds
	if not footprint_locked:
		_recalculate_footprint()

	footprint_locked = not footprint_locked

	var btn: Button = find_child("LockFootprintBtn", true, false)
	if btn:
		btn.text = "Unlock Footprint" if footprint_locked else "Lock Footprint"

	# Show/hide footprint visualization
	footprint_mesh.visible = footprint_locked
	footprint_outline.visible = footprint_locked

	status_label.text = "Footprint " + ("LOCKED" if footprint_locked else "unlocked")


func _recalculate_footprint() -> void:
	if footprint_locked:
		return

	if placed_objects.is_empty():
		footprint_size = Vector3(2.0, 2.0, 2.0)
		footprint_info_label.text = "Place models first"
		return

	# Calculate combined AABB
	var combined := AABB()
	var first := true

	for obj in placed_objects:
		var aabb := _get_aabb(obj)
		aabb.position += obj.position
		if first:
			combined = aabb
			first = false
		else:
			combined = combined.merge(aabb)

	# Make square + padding
	var padding := 1.0
	var max_side: float = maxf(combined.size.x, combined.size.z) + padding * 2
	var height: float = combined.size.y + padding

	max_side = ceilf(max_side * 2) / 2.0
	height = ceilf(height * 2) / 2.0

	footprint_size = Vector3(max_side, height, max_side)
	footprint_center = Vector3(
		combined.position.x + combined.size.x * 0.5,
		0,
		combined.position.z + combined.size.z * 0.5
	)

	footprint_info_label.text = "%.1fm x %.1fm" % [footprint_size.x, footprint_size.z]

	# Update visual position (even if hidden)
	if footprint_mesh and footprint_mesh.mesh is PlaneMesh:
		var plane: PlaneMesh = footprint_mesh.mesh
		plane.size = Vector2(footprint_size.x, footprint_size.z)
		footprint_mesh.position = Vector3(footprint_center.x, 0.01, footprint_center.z)


func _on_edit_footprint() -> void:
	"""Toggle footprint painting mode."""
	if current_mode == Mode.PAINTING_FOOTPRINT:
		# Exit paint mode
		current_mode = Mode.IDLE
		footprint_grid_overlay.visible = false
		painted_cells_mesh.visible = false
		hover_cell_mesh.visible = false
		_is_shift_painting = false

		var btn: Button = find_child("EditFootprintBtn", true, false)
		if btn:
			btn.text = "Edit Footprint"

		status_label.text = "Exited footprint paint mode | %d cells painted" % footprint_cells.size()
	else:
		# Enter paint mode
		current_mode = Mode.PAINTING_FOOTPRINT
		_update_footprint_grid_overlay()
		_update_painted_cells_mesh()
		footprint_grid_overlay.visible = true
		painted_cells_mesh.visible = true

		var btn: Button = find_child("EditFootprintBtn", true, false)
		if btn:
			btn.text = "Done Editing"

		status_label.text = "PAINTING FOOTPRINT: Click cells to toggle, Shift+drag to paint multiple"


func _on_clear_footprint() -> void:
	"""Clear all painted footprint cells."""
	footprint_cells.clear()
	_update_painted_cells_mesh()
	_update_footprint_cell_label()
	status_label.text = "Footprint cleared"


func _paint_cell_at(world_pos: Vector3) -> void:
	"""Toggle a cell at the given world position."""
	var cell := _world_to_cell(world_pos)

	# Avoid re-painting the same cell during shift+drag
	if cell == _last_painted_cell:
		return
	_last_painted_cell = cell

	# Toggle cell
	var idx := footprint_cells.find(cell)
	if idx >= 0:
		footprint_cells.remove_at(idx)
	else:
		footprint_cells.append(cell)

	_update_painted_cells_mesh()
	_update_footprint_cell_label()
	_recalculate_footprint_from_cells()


func _update_painted_cells_mesh() -> void:
	"""Rebuild the mesh showing all painted cells."""
	if not painted_cells_mesh:
		return

	var im := ImmediateMesh.new()
	painted_cells_mesh.mesh = im

	if footprint_cells.is_empty():
		return

	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var half := (FOOTPRINT_CELL_SIZE - 0.1) * 0.5
	var y := 0.015  # Slightly above ground

	for cell in footprint_cells:
		var center := _cell_to_world(cell)
		var cx: float = center.x
		var cz: float = center.y

		# Two triangles for a quad
		# Triangle 1
		im.surface_add_vertex(Vector3(cx - half, y, cz - half))
		im.surface_add_vertex(Vector3(cx + half, y, cz - half))
		im.surface_add_vertex(Vector3(cx + half, y, cz + half))
		# Triangle 2
		im.surface_add_vertex(Vector3(cx - half, y, cz - half))
		im.surface_add_vertex(Vector3(cx + half, y, cz + half))
		im.surface_add_vertex(Vector3(cx - half, y, cz + half))

	im.surface_end()


func _update_footprint_grid_overlay() -> void:
	"""Rebuild the grid overlay showing cell boundaries."""
	if not footprint_grid_overlay:
		return

	var im := ImmediateMesh.new()
	footprint_grid_overlay.mesh = im

	im.surface_begin(Mesh.PRIMITIVE_LINES)

	# Fixed grid centered at world origin, covering 80m x 80m (-40 to +40)
	var extent := 40.0  # meters
	var y := 0.005  # Just above ground

	# Lines at every FOOTPRINT_CELL_SIZE interval
	var pos: float = -extent
	while pos <= extent:
		# X-parallel lines (along Z)
		im.surface_add_vertex(Vector3(pos, y, -extent))
		im.surface_add_vertex(Vector3(pos, y, extent))
		# Z-parallel lines (along X)
		im.surface_add_vertex(Vector3(-extent, y, pos))
		im.surface_add_vertex(Vector3(extent, y, pos))
		pos += FOOTPRINT_CELL_SIZE

	im.surface_end()


func _update_footprint_cell_label() -> void:
	"""Update the cell count label with approximate dimensions."""
	var label: Label = find_child("FootprintCellLabel", true, false)
	if not label:
		return

	if footprint_cells.is_empty():
		label.text = "0 cells"
		return

	# Calculate bounding box of cells
	var min_cell := footprint_cells[0]
	var max_cell := footprint_cells[0]
	for cell in footprint_cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)

	var width := (max_cell.x - min_cell.x + 1) * int(FOOTPRINT_CELL_SIZE)
	var depth := (max_cell.y - min_cell.y + 1) * int(FOOTPRINT_CELL_SIZE)

	label.text = "%d cells (%dx%d approx)" % [footprint_cells.size(), width, depth]


func _recalculate_footprint_from_cells() -> void:
	"""Calculate footprint size and center from painted cells."""
	if footprint_locked or footprint_cells.is_empty():
		return

	# Calculate bounding box of cells
	var min_cell := footprint_cells[0]
	var max_cell := footprint_cells[0]
	for cell in footprint_cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)

	# Convert to world coordinates
	var min_world := Vector2(min_cell.x * FOOTPRINT_CELL_SIZE, min_cell.y * FOOTPRINT_CELL_SIZE)
	var max_world := Vector2((max_cell.x + 1) * FOOTPRINT_CELL_SIZE, (max_cell.y + 1) * FOOTPRINT_CELL_SIZE)

	var width: float = max_world.x - min_world.x
	var depth: float = max_world.y - min_world.y

	# Get height from placed objects
	var height := 2.0
	if not placed_objects.is_empty():
		for obj in placed_objects:
			var aabb := _get_aabb(obj)
			height = maxf(height, aabb.size.y + 1.0)

	footprint_size = Vector3(width, height, depth)
	footprint_center = Vector3(
		(min_world.x + max_world.x) * 0.5,
		0,
		(min_world.y + max_world.y) * 0.5
	)

	footprint_info_label.text = "%.1fm x %.1fm" % [footprint_size.x, footprint_size.z]

	# Update visual position (even if hidden)
	if footprint_mesh and footprint_mesh.mesh is PlaneMesh:
		var plane: PlaneMesh = footprint_mesh.mesh
		plane.size = Vector2(footprint_size.x, footprint_size.z)
		footprint_mesh.position = Vector3(footprint_center.x, 0.01, footprint_center.z)


# =============================================================================
# SAVE / EXPORT
# =============================================================================
func _save_building() -> void:
	if placed_objects.is_empty():
		status_label.text = "ERROR: No objects to save"
		return

	# Make sure footprint is calculated
	if not footprint_cells.is_empty():
		_recalculate_footprint_from_cells()
	elif not footprint_locked:
		_recalculate_footprint()

	var building_name := name_edit.text.strip_edges()
	if building_name.is_empty():
		building_name = "building_" + str(Time.get_unix_time_from_system())
	building_name = building_name.replace(" ", "_").to_lower()

	# Create output dir
	var dir := DirAccess.open("res://")
	if dir and not dir.dir_exists(OUTPUT_PATH):
		dir.make_dir_recursive(OUTPUT_PATH)

	# Build scene with StaticBody3D root for collision
	var root := StaticBody3D.new()
	root.name = building_name.to_pascal_case()
	root.set_meta("category", CATEGORIES[category_option.selected])
	root.set_meta("composed_building", true)

	# Store footprint cells (primary footprint data)
	if not footprint_cells.is_empty():
		# Convert Array[Vector2i] to Array for JSON-safe storage
		var cells_array: Array = []
		for cell in footprint_cells:
			cells_array.append([cell.x, cell.y])
		root.set_meta("footprint_cells", cells_array)

	# Store bounding box for backward compatibility
	root.set_meta("footprint_size", footprint_size.x)
	root.set_meta("footprint_height", footprint_size.y)
	root.set_meta("footprint_center", footprint_center)

	# Add collision shape based on footprint
	var collision := CollisionShape3D.new()
	collision.name = "FootprintCollision"
	var box := BoxShape3D.new()
	box.size = Vector3(footprint_size.x, footprint_size.y, footprint_size.z)
	collision.shape = box
	# Center the collision at footprint center, half height up
	collision.position = Vector3(footprint_center.x, footprint_size.y * 0.5, footprint_center.z)
	root.add_child(collision)
	collision.owner = root

	# Add visual models container
	var visuals := Node3D.new()
	visuals.name = "Visuals"
	root.add_child(visuals)
	visuals.owner = root

	# Copy placed objects (strip any existing collisions - we use footprint collision)
	for obj in placed_objects:
		var copy := _duplicate_visual_only(obj)
		visuals.add_child(copy)
		copy.owner = root
		_set_owner_recursive(copy, root)

	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.queue_free()

	if err != OK:
		status_label.text = "ERROR: Failed to pack scene"
		return

	var save_path := OUTPUT_PATH + building_name + ".tscn"
	err = ResourceSaver.save(packed, save_path)

	if err == OK:
		status_label.text = "Saved: " + save_path
		print("[BuildingComposer] Saved: " + save_path)
	else:
		status_label.text = "ERROR: Save failed"


func _duplicate_visual_only(node: Node3D) -> Node3D:
	"""Duplicate a node but strip collision shapes - we use footprint collision instead"""
	var copy := node.duplicate()

	# Remove any CollisionShape3D children recursively
	_strip_collisions(copy)

	return copy


func _strip_collisions(node: Node) -> void:
	"""Remove all CollisionShape3D nodes from a tree"""
	var to_remove: Array[Node] = []

	for child in node.get_children():
		if child is CollisionShape3D or child is CollisionPolygon3D:
			to_remove.append(child)
		else:
			_strip_collisions(child)

	for child in to_remove:
		child.queue_free()


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_set_owner_recursive(child, owner_node)


func _export_and_link() -> void:
	_save_building()
	# TODO: Create BuildingData resource linking


func _populate_building_types() -> void:
	building_type_option.clear()
	building_type_option.add_item("-- Select Type --")
	building_type_option.add_separator("US Perimeter")
	building_type_option.add_item("Sandbag (Light)", BuildingData.BuildingType.SANDBAG_LIGHT)
	building_type_option.add_item("Sandbag (Heavy)", BuildingData.BuildingType.SANDBAG_HEAVY)
	building_type_option.add_item("Wire Obstacle", BuildingData.BuildingType.WIRE_OBSTACLE)
	building_type_option.add_item("Bunker", BuildingData.BuildingType.BUNKER)
	building_type_option.add_item("MG Nest", BuildingData.BuildingType.MACHINE_GUN_NEST)
	building_type_option.add_item("Mortar Pit", BuildingData.BuildingType.MORTAR_PIT)
	building_type_option.add_item("Watchtower", BuildingData.BuildingType.WATCHTOWER)
	building_type_option.add_separator("US Support")
	building_type_option.add_item("Helipad", BuildingData.BuildingType.HELIPAD)
	building_type_option.add_item("Supply Depot", BuildingData.BuildingType.SUPPLY_DEPOT)
	building_type_option.add_item("Medical Station", BuildingData.BuildingType.MEDICAL_STATION)
	building_type_option.add_item("TOC", BuildingData.BuildingType.TOC)


func _show_help() -> void:
	var popup := AcceptDialog.new()
	popup.title = "Building Composer Help"
	popup.dialog_text = """
BUILDING COMPOSER - Compose buildings from 3D models

WORKFLOW:
1. Double-click a model in the left panel to start placing
2. Click in the viewport to place it
3. Click on placed models to select them
4. Use hotkeys to transform:
   - G = Grab/Move (click to confirm)
   - R/E = Rotate +10/-10 degrees
   - Shift+S = Scale (click to confirm)
   - ESC = Cancel
   - Delete = Remove selected
5. Click "Edit Footprint" to paint the building's gameplay footprint
6. Save when done

FOOTPRINT PAINTING:
- Click "Edit Footprint" to enter paint mode
- Yellow 2m grid shows cell boundaries
- Click cells to toggle them on/off (green = painted)
- Shift+drag to paint multiple cells quickly
- Click "Done Editing" or press ESC to exit
- Footprint defines gameplay collision, not visual bounds

CAMERA:
- WASD = Pan
- Scroll = Zoom
- Middle-drag = Rotate view

TIPS:
- Objects snap to 0.5m grid
- Paint footprint for irregular building shapes
- Saved footprint is stored as cell coordinates for precise placement
"""
	add_child(popup)
	popup.popup_centered()
