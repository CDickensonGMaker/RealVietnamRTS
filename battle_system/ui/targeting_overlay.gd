extends Node3D
class_name TargetingOverlay
## 3D overlay for targeting visuals - move paths, fire mission circles, etc.
## Renders directly in 3D space using ImmediateMesh.

const MilitaryTheme = preload("res://battle_system/ui/military_theme.gd")
const CursorModeScript = preload("res://battle_system/ui/cursor_mode.gd")
const PaintedAreaPreview = preload("res://battle_system/ui/painted_area_preview.gd")
const PaintableCommand = preload("res://battle_system/ui/paintable_command.gd")
const UnifiedJob = preload("res://firebase_system/job_system/unified_job.gd")

# =============================================================================
# CONFIGURATION
# =============================================================================

## Circle segments for range indicators
const CIRCLE_SEGMENTS: int = 32

## Path line height offset above terrain
const PATH_HEIGHT_OFFSET: float = 0.5

# =============================================================================
# STATE
# =============================================================================

var _current_mode: int = CursorModeScript.Mode.NORMAL
var _cursor_world_pos: Vector3 = Vector3.ZERO
var _selected_units: Array[Node3D] = []

## Mode-specific context data
var _context: Dictionary = {}

# =============================================================================
# VISUAL COMPONENTS
# =============================================================================

var _path_mesh: MeshInstance3D
var _range_mesh: MeshInstance3D
#var _ghost_mesh: MeshInstance3D  # Reserved for future ghost visualization

var _immediate_path: ImmediateMesh
var _immediate_range: ImmediateMesh

var _path_material: StandardMaterial3D
var _range_material: StandardMaterial3D

## Paint area preview component
var _paint_preview: PaintedAreaPreview = null
var _paint_controller: PaintableCommand = null
var _paint_drag_start: Vector3 = Vector3.INF


func _ready() -> void:
	_setup_meshes()
	visible = false


func _process(_delta: float) -> void:
	if _current_mode == CursorModeScript.Mode.NORMAL:
		visible = false
		return

	# Update every frame for precise mouse tracking
	_update_cursor_position()
	_rebuild_overlay()


func _setup_meshes() -> void:
	# Path lines mesh
	_path_mesh = MeshInstance3D.new()
	_immediate_path = ImmediateMesh.new()
	_path_mesh.mesh = _immediate_path

	_path_material = StandardMaterial3D.new()
	_path_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_path_material.albedo_color = MilitaryTheme.COL_MOVE_PATH
	_path_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_path_material.no_depth_test = true
	_path_material.render_priority = 5
	_path_mesh.material_override = _path_material

	add_child(_path_mesh)

	# Range circles mesh
	_range_mesh = MeshInstance3D.new()
	_immediate_range = ImmediateMesh.new()
	_range_mesh.mesh = _immediate_range

	_range_material = StandardMaterial3D.new()
	_range_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_range_material.albedo_color = MilitaryTheme.COL_FIRE_MISSION_VALID
	_range_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_range_material.no_depth_test = true
	_range_material.render_priority = 4
	_range_mesh.material_override = _range_material

	add_child(_range_mesh)

	# Paint area preview
	_paint_preview = PaintedAreaPreview.new()
	_paint_preview.name = "PaintPreview"
	add_child(_paint_preview)


func _update_cursor_position() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return

	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(mouse_pos)

	# Raycast to terrain
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin, ray_origin + ray_dir * 1000.0
	)
	query.collision_mask = 1  # Terrain layer

	var result: Dictionary = space.intersect_ray(query)
	if result:
		_cursor_world_pos = result.position
	else:
		# Fallback: intersect Y=0 plane
		if ray_dir.y != 0:
			var t: float = -ray_origin.y / ray_dir.y
			if t > 0:
				_cursor_world_pos = ray_origin + ray_dir * t


func _rebuild_overlay() -> void:
	_immediate_path.clear_surfaces()
	_immediate_range.clear_surfaces()

	# Hide paint preview for non-paint modes
	if not CursorModeScript.is_paint_mode(_current_mode):
		if _paint_preview:
			_paint_preview.hide_preview()

	match _current_mode:
		CursorModeScript.Mode.MOVE_PREVIEW:
			_draw_move_paths(MilitaryTheme.COL_MOVE_PATH)
		CursorModeScript.Mode.ATTACK_MOVE:
			_draw_move_paths(MilitaryTheme.COL_ATTACK_MOVE_PATH)
		CursorModeScript.Mode.FIRE_MISSION:
			_draw_fire_mission_overlay()
		CursorModeScript.Mode.UNLOAD:
			_draw_unload_formation()
		CursorModeScript.Mode.BOMB_RUN, CursorModeScript.Mode.NAPALM_RUN, \
		CursorModeScript.Mode.ROCKET_RUN, CursorModeScript.Mode.STRAFE_RUN:
			_draw_attack_run_overlay()
		CursorModeScript.Mode.BUILDING_PLACE:
			_draw_building_ghost()
		CursorModeScript.Mode.GARRISON:
			_draw_garrison_targets()
		# Paint modes
		CursorModeScript.Mode.PAINT_CLEAR:
			_update_paint_preview(UnifiedJob.Type.CLEAR_TERRAIN)
		CursorModeScript.Mode.PAINT_FLATTEN:
			_update_paint_preview(UnifiedJob.Type.FLATTEN_AREA)
		CursorModeScript.Mode.PAINT_ROAD:
			_update_paint_preview(UnifiedJob.Type.BUILD_ROAD)
		CursorModeScript.Mode.PAINT_BUILD:
			_update_paint_preview(UnifiedJob.Type.BUILD_STRUCTURE)
		CursorModeScript.Mode.PAINT_FILL:
			_update_paint_preview(UnifiedJob.Type.FILL_CRATER)
		CursorModeScript.Mode.PAINT_DOZER_LINE:
			_draw_dozer_line_preview()


func _draw_move_paths(color: Color) -> void:
	if _selected_units.is_empty():
		return

	_path_material.albedo_color = color
	_immediate_path.surface_begin(Mesh.PRIMITIVE_LINES)

	for unit in _selected_units:
		if not is_instance_valid(unit):
			continue

		var start: Vector3 = unit.global_position + Vector3(0, PATH_HEIGHT_OFFSET, 0)
		var end: Vector3 = _cursor_world_pos + Vector3(0, PATH_HEIGHT_OFFSET, 0)

		_immediate_path.surface_add_vertex(start)
		_immediate_path.surface_add_vertex(end)

	_immediate_path.surface_end()


func _draw_fire_mission_overlay() -> void:
	var min_range: float = _context.get("min_range", 100.0)
	var max_range: float = _context.get("max_range", 11000.0)
	var impact_radius: float = _context.get("impact_radius", 30.0)

	# Get artillery unit position
	var arty_pos: Vector3 = Vector3.ZERO
	if not _selected_units.is_empty():
		arty_pos = _selected_units[0].global_position

	var dist_to_cursor: float = arty_pos.distance_to(_cursor_world_pos)
	var is_valid: bool = dist_to_cursor >= min_range and dist_to_cursor <= max_range

	# Draw min range circle (red)
	_draw_circle(arty_pos, min_range, MilitaryTheme.COL_FIRE_MISSION_MIN_RANGE)

	# Draw max range circle (amber or red based on validity)
	var max_color: Color = MilitaryTheme.COL_FIRE_MISSION_VALID if is_valid else MilitaryTheme.COL_FIRE_MISSION_INVALID
	_draw_circle(arty_pos, max_range, max_color)

	# Draw impact circle at cursor
	var impact_color: Color = MilitaryTheme.COL_FIRE_MISSION_VALID if is_valid else MilitaryTheme.COL_FIRE_MISSION_INVALID
	_draw_circle(_cursor_world_pos, impact_radius, impact_color)


func _draw_unload_formation() -> void:
	# Draw ghost markers in formation spread
	var unit_count: int = _context.get("unit_count", 4)
	var spacing: float = 3.0

	_range_material.albedo_color = MilitaryTheme.COL_GHOST

	_immediate_range.surface_begin(Mesh.PRIMITIVE_LINES)

	var half_width: float = spacing * (unit_count - 1) * 0.5
	for i in unit_count:
		var offset_x: float = -half_width + i * spacing
		var pos: Vector3 = _cursor_world_pos + Vector3(offset_x, 0, 0)

		# Draw small cross
		_draw_cross_lines(pos, 0.5)

	_immediate_range.surface_end()


func _draw_attack_run_overlay() -> void:
	# Draw attack vector arrow + impact pattern
	if _selected_units.is_empty():
		return

	var plane_pos: Vector3 = _selected_units[0].global_position
	var approach_dir: Vector3 = (plane_pos - _cursor_world_pos).normalized()
	approach_dir.y = 0
	approach_dir = approach_dir.normalized()

	var run_length: float = 100.0
	var run_start: Vector3 = _cursor_world_pos + approach_dir * run_length
	var run_end: Vector3 = _cursor_world_pos - approach_dir * 50.0

	_path_material.albedo_color = MilitaryTheme.COL_FIRE_MISSION_VALID
	_immediate_path.surface_begin(Mesh.PRIMITIVE_LINES)

	# Main arrow line
	var h: float = PATH_HEIGHT_OFFSET
	_immediate_path.surface_add_vertex(run_start + Vector3(0, h, 0))
	_immediate_path.surface_add_vertex(run_end + Vector3(0, h, 0))

	# Arrowhead
	var arrow_size: float = 5.0
	var perp: Vector3 = Vector3(-approach_dir.z, 0, approach_dir.x)
	_immediate_path.surface_add_vertex(_cursor_world_pos + Vector3(0, h, 0))
	_immediate_path.surface_add_vertex(_cursor_world_pos + approach_dir * arrow_size + perp * arrow_size * 0.5 + Vector3(0, h, 0))
	_immediate_path.surface_add_vertex(_cursor_world_pos + Vector3(0, h, 0))
	_immediate_path.surface_add_vertex(_cursor_world_pos + approach_dir * arrow_size - perp * arrow_size * 0.5 + Vector3(0, h, 0))

	_immediate_path.surface_end()

	# Impact pattern along run (spacing/count reserved for future multi-bomb visualization)
	var _impact_spacing: float = 15.0
	var _impact_count: int = 5
	_draw_circle(_cursor_world_pos, 20.0, MilitaryTheme.COL_FIRE_MISSION_VALID)


func _draw_building_ghost() -> void:
	var footprint_size: Vector2 = _context.get("footprint", Vector2(10, 10))
	var is_valid: bool = _context.get("placement_valid", true)

	var color: Color = MilitaryTheme.COL_GHOST if is_valid else MilitaryTheme.COL_GHOST_INVALID

	_range_material.albedo_color = color
	_immediate_range.surface_begin(Mesh.PRIMITIVE_LINES)

	var half_x: float = footprint_size.x * 0.5
	var half_z: float = footprint_size.y * 0.5
	var pos: Vector3 = _cursor_world_pos
	var h: float = PATH_HEIGHT_OFFSET

	# Draw rectangle
	var corners: Array[Vector3] = [
		pos + Vector3(-half_x, h, -half_z),
		pos + Vector3(half_x, h, -half_z),
		pos + Vector3(half_x, h, half_z),
		pos + Vector3(-half_x, h, half_z),
	]

	for i in 4:
		_immediate_range.surface_add_vertex(corners[i])
		_immediate_range.surface_add_vertex(corners[(i + 1) % 4])

	_immediate_range.surface_end()


func _draw_circle(center: Vector3, radius: float, color: Color) -> void:
	_range_material.albedo_color = color
	_immediate_range.surface_begin(Mesh.PRIMITIVE_LINES)

	var h: float = PATH_HEIGHT_OFFSET
	for i in CIRCLE_SEGMENTS:
		var angle1: float = TAU * i / CIRCLE_SEGMENTS
		var angle2: float = TAU * (i + 1) / CIRCLE_SEGMENTS

		var p1: Vector3 = center + Vector3(cos(angle1) * radius, h, sin(angle1) * radius)
		var p2: Vector3 = center + Vector3(cos(angle2) * radius, h, sin(angle2) * radius)

		_immediate_range.surface_add_vertex(p1)
		_immediate_range.surface_add_vertex(p2)

	_immediate_range.surface_end()


func _draw_cross_lines(center: Vector3, size: float) -> void:
	var h: float = PATH_HEIGHT_OFFSET
	_immediate_range.surface_add_vertex(center + Vector3(-size, h, 0))
	_immediate_range.surface_add_vertex(center + Vector3(size, h, 0))
	_immediate_range.surface_add_vertex(center + Vector3(0, h, -size))
	_immediate_range.surface_add_vertex(center + Vector3(0, h, size))


func _draw_dozer_line_preview() -> void:
	## Draw a 3-wide (6m) line preview from selected bulldozer to cursor
	if _selected_units.is_empty():
		return

	# Find bulldozer position
	var dozer_pos: Vector3 = _selected_units[0].global_position
	var target_pos: Vector3 = _cursor_world_pos

	# Line width: 6m total (3m on each side of centerline)
	var line_width: float = 6.0
	var half_width: float = line_width * 0.5

	# Calculate direction and perpendicular
	var line_dir: Vector3 = (target_pos - dozer_pos)
	line_dir.y = 0
	if line_dir.length() < 0.1:
		return
	line_dir = line_dir.normalized()

	var perp: Vector3 = Vector3(-line_dir.z, 0, line_dir.x)
	var h: float = PATH_HEIGHT_OFFSET

	# Draw the 3-wide corridor outline
	_range_material.albedo_color = MilitaryTheme.COL_GHOST
	_immediate_range.surface_begin(Mesh.PRIMITIVE_LINES)

	# Four corners of the line corridor
	var corners: Array[Vector3] = [
		dozer_pos + perp * half_width + Vector3(0, h, 0),
		dozer_pos - perp * half_width + Vector3(0, h, 0),
		target_pos - perp * half_width + Vector3(0, h, 0),
		target_pos + perp * half_width + Vector3(0, h, 0),
	]

	# Draw rectangle
	for i in 4:
		_immediate_range.surface_add_vertex(corners[i])
		_immediate_range.surface_add_vertex(corners[(i + 1) % 4])

	# Draw centerline (dashed via segments)
	var line_length: float = dozer_pos.distance_to(target_pos)
	var dash_length: float = 5.0
	var num_dashes: int = int(line_length / (dash_length * 2.0))

	for i in range(num_dashes):
		var t1: float = (float(i) * 2.0 * dash_length) / line_length
		var t2: float = ((float(i) * 2.0 + 1.0) * dash_length) / line_length
		t2 = minf(t2, 1.0)

		var p1: Vector3 = dozer_pos.lerp(target_pos, t1) + Vector3(0, h, 0)
		var p2: Vector3 = dozer_pos.lerp(target_pos, t2) + Vector3(0, h, 0)

		_immediate_range.surface_add_vertex(p1)
		_immediate_range.surface_add_vertex(p2)

	# Draw arrowhead at target
	var arrow_size: float = 3.0
	_immediate_range.surface_add_vertex(target_pos + Vector3(0, h, 0))
	_immediate_range.surface_add_vertex(target_pos - line_dir * arrow_size + perp * arrow_size * 0.5 + Vector3(0, h, 0))
	_immediate_range.surface_add_vertex(target_pos + Vector3(0, h, 0))
	_immediate_range.surface_add_vertex(target_pos - line_dir * arrow_size - perp * arrow_size * 0.5 + Vector3(0, h, 0))

	_immediate_range.surface_end()


func _draw_garrison_targets() -> void:
	## Draw highlight circles around valid garrison targets near cursor
	const GARRISON_SEARCH_RADIUS: float = 50.0
	const HIGHLIGHT_RADIUS: float = 5.0

	# Find garrisonable structures nearby
	var garrisonable: Array[Node3D] = []
	var bunkers: Array[Node] = get_tree().get_nodes_in_group("bunkers")

	for bunker in bunkers:
		if not bunker is Node3D:
			continue
		var b: Node3D = bunker as Node3D
		var dist: float = _cursor_world_pos.distance_to(b.global_position)
		if dist <= GARRISON_SEARCH_RADIUS:
			# Check if bunker has room
			if b.has_method("get") and b.get("garrison_capacity") != null:
				var capacity: int = b.garrison_capacity
				var current: int = 0
				if b.get("garrison_count") != null:
					current = b.garrison_count
				if current < capacity:
					garrisonable.append(b)
			else:
				garrisonable.append(b)

	# Draw circles around valid targets
	for target in garrisonable:
		_draw_circle(target.global_position, HIGHLIGHT_RADIUS, MilitaryTheme.COL_GARRISON_VALID)


# =============================================================================
# PUBLIC API
# =============================================================================

## Set the current cursor mode and context
func set_mode(mode: int, context: Dictionary = {}) -> void:
	_current_mode = mode
	_context = context
	visible = CursorModeScript.shows_overlay(mode)

	if visible:
		_update_cursor_position()  # Immediate update for responsiveness


## Update the selected units for path drawing
func set_selected_units(units: Array[Node3D]) -> void:
	_selected_units = units


## Get current cursor world position
## If force_update is true, performs a fresh raycast instead of using cached position
func get_cursor_position(force_update: bool = false) -> Vector3:
	if force_update:
		_update_cursor_position()
	return _cursor_world_pos


## Check if cursor is in a valid position for current mode
func is_cursor_valid() -> bool:
	match _current_mode:
		CursorModeScript.Mode.FIRE_MISSION:
			var min_range: float = _context.get("min_range", 100.0)
			var max_range: float = _context.get("max_range", 11000.0)
			if _selected_units.is_empty():
				return false
			var dist: float = _selected_units[0].global_position.distance_to(_cursor_world_pos)
			return dist >= min_range and dist <= max_range
		CursorModeScript.Mode.BUILDING_PLACE:
			return _context.get("placement_valid", true)
		_:
			return true


# =============================================================================
# PAINT MODE SUPPORT
# =============================================================================

## Update paint area preview based on context
func _update_paint_preview(job_type: UnifiedJob.Type) -> void:
	if not _paint_preview:
		return

	var is_valid: bool = _context.get("placement_valid", true)

	match job_type:
		UnifiedJob.Type.CLEAR_TERRAIN, UnifiedJob.Type.FLATTEN_AREA:
			# Area paint mode - show rectangle if dragging
			if _paint_drag_start != Vector3.INF:
				var min_x: float = minf(_paint_drag_start.x, _cursor_world_pos.x)
				var min_z: float = minf(_paint_drag_start.z, _cursor_world_pos.z)
				var max_x: float = maxf(_paint_drag_start.x, _cursor_world_pos.x)
				var max_z: float = maxf(_paint_drag_start.z, _cursor_world_pos.z)
				var bounds := Rect2(min_x, min_z, max_x - min_x, max_z - min_z)
				_paint_preview.show_area(bounds, job_type, is_valid)
			else:
				# Just show cursor position indicator
				_paint_preview.show_single(_cursor_world_pos, job_type, is_valid)

		UnifiedJob.Type.BUILD_ROAD:
			# Polyline mode
			var points: PackedVector3Array = _context.get("road_points", PackedVector3Array())
			if points.size() > 0:
				# Add current cursor as preview point
				var preview_points := points.duplicate()
				preview_points.append(_cursor_world_pos)
				_paint_preview.show_polyline(preview_points, job_type, is_valid)
			else:
				_paint_preview.show_single(_cursor_world_pos, job_type, is_valid)

		UnifiedJob.Type.BUILD_STRUCTURE:
			# Single placement with footprint
			var footprint: Vector2 = _context.get("footprint", Vector2(4, 4))
			var bounds := Rect2(
				_cursor_world_pos.x - footprint.x * 0.5,
				_cursor_world_pos.z - footprint.y * 0.5,
				footprint.x,
				footprint.y
			)
			_paint_preview.show_area(bounds, job_type, is_valid)

		UnifiedJob.Type.FILL_CRATER:
			_paint_preview.show_single(_cursor_world_pos, job_type, is_valid)


## Start paint drag operation
func start_paint_drag(start_pos: Vector3) -> void:
	_paint_drag_start = start_pos


## End paint drag operation
func end_paint_drag() -> void:
	_paint_drag_start = Vector3.INF


## Set road points for polyline preview
func set_road_points(points: PackedVector3Array) -> void:
	_context["road_points"] = points


## Get paint drag bounds (for committing)
## Forces cursor position update for accurate drag end position
func get_paint_bounds() -> Rect2:
	if _paint_drag_start == Vector3.INF:
		return Rect2()

	# Force update cursor position for accurate drag end
	_update_cursor_position()

	var min_x: float = minf(_paint_drag_start.x, _cursor_world_pos.x)
	var min_z: float = minf(_paint_drag_start.z, _cursor_world_pos.z)
	var max_x: float = maxf(_paint_drag_start.x, _cursor_world_pos.x)
	var max_z: float = maxf(_paint_drag_start.z, _cursor_world_pos.z)

	return Rect2(min_x, min_z, max_x - min_x, max_z - min_z)
