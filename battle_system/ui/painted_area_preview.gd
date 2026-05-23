class_name PaintedAreaPreview
extends Node3D
## PaintedAreaPreview - Green-grid preview mesh that conforms to terrain
##
## Shows a grid pattern during area selection that follows the terrain height.
## Updates at capped rate (30Hz) for performance.

const UnifiedJob = preload("res://firebase_system/job_system/unified_job.gd")
const MilitaryTheme = preload("res://battle_system/ui/military_theme.gd")

## Grid spacing in meters
const GRID_SPACING := 2.0

## Update rate limiting
const UPDATE_INTERVAL := 0.033  # ~30Hz

## Height offset above terrain
const HEIGHT_OFFSET := 0.15

## Colors for different job types
var COLOR_CLEAR := Color(0.3, 0.8, 0.3, 0.35)  # Green
var COLOR_FLATTEN := Color(0.7, 0.5, 0.2, 0.35)  # Orange/brown
var COLOR_ROAD := Color(0.5, 0.4, 0.35, 0.5)  # Brown
var COLOR_BUILD := Color(0.3, 0.6, 0.8, 0.4)  # Blue
var COLOR_INVALID := Color(0.8, 0.2, 0.2, 0.4)  # Red

## Visual components
var grid_mesh: MeshInstance3D
var outline_mesh: MeshInstance3D
var grid_material: StandardMaterial3D
var outline_material: StandardMaterial3D

## State
var _update_timer: float = 0.0
var _current_job_type: UnifiedJob.Type = UnifiedJob.Type.CLEAR_TERRAIN
var _is_valid_placement: bool = true
var _area_bounds: Rect2 = Rect2()  # X, Z coordinates
var _polyline_points: PackedVector3Array = PackedVector3Array()
var _single_position: Vector3 = Vector3.ZERO
var _preview_mode: int = 0  # 0=area, 1=polyline, 2=single, 3=wall_line
var _wall_line_start: Vector3 = Vector3.ZERO
var _wall_line_end: Vector3 = Vector3.ZERO
var _wall_segment_spacing: float = 2.0

## Terrain reference
var _terrain: Node = null


func _ready() -> void:
	_setup_meshes()
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return

	_update_timer -= delta
	if _update_timer <= 0.0:
		_update_timer = UPDATE_INTERVAL
		_rebuild_preview()


func _setup_meshes() -> void:
	# Grid fill mesh
	grid_mesh = MeshInstance3D.new()
	grid_mesh.name = "GridFill"

	grid_material = StandardMaterial3D.new()
	grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	grid_material.albedo_color = COLOR_CLEAR
	grid_mesh.material_override = grid_material

	add_child(grid_mesh)

	# Outline mesh
	outline_mesh = MeshInstance3D.new()
	outline_mesh.name = "Outline"

	outline_material = StandardMaterial3D.new()
	outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_material.albedo_color = Color(1, 1, 1, 0.8)
	outline_material.no_depth_test = true
	outline_mesh.material_override = outline_material

	add_child(outline_mesh)


func _rebuild_preview() -> void:
	match _preview_mode:
		0:  # Area
			_rebuild_area_preview()
		1:  # Polyline
			_rebuild_polyline_preview()
		2:  # Single
			_rebuild_single_preview()
		3:  # Wall line
			_rebuild_wall_line_preview()


func _rebuild_area_preview() -> void:
	if _area_bounds.size.x < 1.0 or _area_bounds.size.y < 1.0:
		grid_mesh.mesh = null
		outline_mesh.mesh = null
		return

	_update_color()

	# Build grid mesh with terrain-conforming heights
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var x_steps: int = int(ceil(_area_bounds.size.x / GRID_SPACING)) + 1
	var z_steps: int = int(ceil(_area_bounds.size.y / GRID_SPACING)) + 1

	# Generate height grid
	var heights: Array[Array] = []
	for i in range(x_steps):
		var row: Array[float] = []
		for j in range(z_steps):
			var x: float = _area_bounds.position.x + i * GRID_SPACING
			var z: float = _area_bounds.position.y + j * GRID_SPACING
			x = minf(x, _area_bounds.position.x + _area_bounds.size.x)
			z = minf(z, _area_bounds.position.y + _area_bounds.size.y)
			row.append(_get_terrain_height(Vector3(x, 0, z)) + HEIGHT_OFFSET)
		heights.append(row)

	# Build triangles
	for i in range(x_steps - 1):
		for j in range(z_steps - 1):
			var x0: float = _area_bounds.position.x + i * GRID_SPACING
			var x1: float = _area_bounds.position.x + (i + 1) * GRID_SPACING
			var z0: float = _area_bounds.position.y + j * GRID_SPACING
			var z1: float = _area_bounds.position.y + (j + 1) * GRID_SPACING

			x1 = minf(x1, _area_bounds.position.x + _area_bounds.size.x)
			z1 = minf(z1, _area_bounds.position.y + _area_bounds.size.y)

			var v00 := Vector3(x0, heights[i][j], z0)
			var v10 := Vector3(x1, heights[i + 1][j], z1)
			var v01 := Vector3(x0, heights[i][j + 1], z0)
			var v11 := Vector3(x1, heights[i + 1][j + 1], z1)

			# Correct vertices
			v10.z = z0
			v01.x = x0
			v01.z = z1

			# Two triangles per cell
			st.add_vertex(v00)
			st.add_vertex(v10)
			st.add_vertex(v11)

			st.add_vertex(v00)
			st.add_vertex(v11)
			st.add_vertex(v01)

	grid_mesh.mesh = st.commit()

	# Build outline
	_build_rect_outline()


func _build_rect_outline() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var corners: Array[Vector3] = [
		Vector3(_area_bounds.position.x, 0, _area_bounds.position.y),
		Vector3(_area_bounds.position.x + _area_bounds.size.x, 0, _area_bounds.position.y),
		Vector3(_area_bounds.position.x + _area_bounds.size.x, 0, _area_bounds.position.y + _area_bounds.size.y),
		Vector3(_area_bounds.position.x, 0, _area_bounds.position.y + _area_bounds.size.y),
	]

	# Get terrain heights for corners
	for i in range(4):
		corners[i].y = _get_terrain_height(corners[i]) + HEIGHT_OFFSET + 0.1

	# Draw rectangle
	for i in range(4):
		st.add_vertex(corners[i])
		st.add_vertex(corners[(i + 1) % 4])

	# Draw grid lines
	var x_lines: int = int(_area_bounds.size.x / GRID_SPACING)
	var z_lines: int = int(_area_bounds.size.y / GRID_SPACING)

	# Vertical grid lines
	for i in range(1, x_lines + 1):
		var x: float = _area_bounds.position.x + i * GRID_SPACING
		if x >= _area_bounds.position.x + _area_bounds.size.x:
			break
		var p1 := Vector3(x, 0, _area_bounds.position.y)
		var p2 := Vector3(x, 0, _area_bounds.position.y + _area_bounds.size.y)
		p1.y = _get_terrain_height(p1) + HEIGHT_OFFSET + 0.1
		p2.y = _get_terrain_height(p2) + HEIGHT_OFFSET + 0.1
		st.add_vertex(p1)
		st.add_vertex(p2)

	# Horizontal grid lines
	for i in range(1, z_lines + 1):
		var z: float = _area_bounds.position.y + i * GRID_SPACING
		if z >= _area_bounds.position.y + _area_bounds.size.y:
			break
		var p1 := Vector3(_area_bounds.position.x, 0, z)
		var p2 := Vector3(_area_bounds.position.x + _area_bounds.size.x, 0, z)
		p1.y = _get_terrain_height(p1) + HEIGHT_OFFSET + 0.1
		p2.y = _get_terrain_height(p2) + HEIGHT_OFFSET + 0.1
		st.add_vertex(p1)
		st.add_vertex(p2)

	outline_mesh.mesh = st.commit()


func _rebuild_polyline_preview() -> void:
	if _polyline_points.size() < 1:
		grid_mesh.mesh = null
		outline_mesh.mesh = null
		return

	_update_color()

	var road_width := 3.0
	var half_width := road_width * 0.5

	# Build road strip mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(_polyline_points.size() - 1):
		var p1: Vector3 = _polyline_points[i]
		var p2: Vector3 = _polyline_points[i + 1]

		# Direction and perpendicular
		var dir: Vector3 = (p2 - p1).normalized()
		dir.y = 0
		dir = dir.normalized()
		var perp := Vector3(-dir.z, 0, dir.x) * half_width

		# Get heights
		var h1: float = _get_terrain_height(p1) + HEIGHT_OFFSET
		var h2: float = _get_terrain_height(p2) + HEIGHT_OFFSET

		var v1l := Vector3(p1.x + perp.x, h1, p1.z + perp.z)
		var v1r := Vector3(p1.x - perp.x, h1, p1.z - perp.z)
		var v2l := Vector3(p2.x + perp.x, h2, p2.z + perp.z)
		var v2r := Vector3(p2.x - perp.x, h2, p2.z - perp.z)

		# Two triangles
		st.add_vertex(v1l)
		st.add_vertex(v1r)
		st.add_vertex(v2r)

		st.add_vertex(v1l)
		st.add_vertex(v2r)
		st.add_vertex(v2l)

	grid_mesh.mesh = st.commit()

	# Build polyline outline
	var ost := SurfaceTool.new()
	ost.begin(Mesh.PRIMITIVE_LINES)

	for i in range(_polyline_points.size() - 1):
		var p1: Vector3 = _polyline_points[i]
		var p2: Vector3 = _polyline_points[i + 1]
		p1.y = _get_terrain_height(p1) + HEIGHT_OFFSET + 0.1
		p2.y = _get_terrain_height(p2) + HEIGHT_OFFSET + 0.1
		ost.add_vertex(p1)
		ost.add_vertex(p2)

	# Draw markers at each point
	for pt in _polyline_points:
		var h: float = _get_terrain_height(pt) + HEIGHT_OFFSET + 0.1
		_add_cross_to_surface(ost, Vector3(pt.x, h, pt.z), 0.5)

	outline_mesh.mesh = ost.commit()


func _rebuild_single_preview() -> void:
	_update_color()

	var radius := 2.0
	var h: float = _get_terrain_height(_single_position) + HEIGHT_OFFSET

	# Build circle mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var segments := 16
	for i in range(segments):
		var angle1: float = TAU * float(i) / float(segments)
		var angle2: float = TAU * float(i + 1) / float(segments)

		var v1 := Vector3(
			_single_position.x + cos(angle1) * radius,
			h,
			_single_position.z + sin(angle1) * radius
		)
		var v2 := Vector3(
			_single_position.x + cos(angle2) * radius,
			h,
			_single_position.z + sin(angle2) * radius
		)
		var center := Vector3(_single_position.x, h, _single_position.z)

		st.add_vertex(center)
		st.add_vertex(v1)
		st.add_vertex(v2)

	grid_mesh.mesh = st.commit()

	# Build outline
	var ost := SurfaceTool.new()
	ost.begin(Mesh.PRIMITIVE_LINES)

	for i in range(segments):
		var angle1: float = TAU * float(i) / float(segments)
		var angle2: float = TAU * float(i + 1) / float(segments)

		ost.add_vertex(Vector3(
			_single_position.x + cos(angle1) * radius,
			h + 0.1,
			_single_position.z + sin(angle1) * radius
		))
		ost.add_vertex(Vector3(
			_single_position.x + cos(angle2) * radius,
			h + 0.1,
			_single_position.z + sin(angle2) * radius
		))

	_add_cross_to_surface(ost, Vector3(_single_position.x, h + 0.1, _single_position.z), 1.0)

	outline_mesh.mesh = ost.commit()


func _add_cross_to_surface(st: SurfaceTool, pos: Vector3, size: float) -> void:
	var half := size * 0.5
	st.add_vertex(pos + Vector3(-half, 0, 0))
	st.add_vertex(pos + Vector3(half, 0, 0))
	st.add_vertex(pos + Vector3(0, 0, -half))
	st.add_vertex(pos + Vector3(0, 0, half))


func _rebuild_wall_line_preview() -> void:
	_update_color()

	var line_vec: Vector3 = _wall_line_end - _wall_line_start
	line_vec.y = 0
	var length: float = line_vec.length()
	if length < 0.1:
		grid_mesh.mesh = null
		outline_mesh.mesh = null
		return

	var direction: Vector3 = line_vec.normalized()
	var perpendicular: Vector3 = Vector3(-direction.z, 0, direction.x)  # Perpendicular for wall width

	# Calculate number of segments
	var num_segments: int = maxi(1, int(length / _wall_segment_spacing))
	var segment_width: float = 0.5  # Wall visual width

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var ost := SurfaceTool.new()
	ost.begin(Mesh.PRIMITIVE_LINES)

	# Draw each segment along the line
	for i in range(num_segments):
		var t: float = (float(i) + 0.5) / float(num_segments)
		var center: Vector3 = _wall_line_start.lerp(_wall_line_end, t)
		var h: float = _get_terrain_height(center) + HEIGHT_OFFSET

		# Segment corners (oriented along the wall)
		var half_len: float = (_wall_segment_spacing * 0.45)  # Slight gap between segments
		var half_width: float = segment_width * 0.5

		var v1 := Vector3(center.x - direction.x * half_len - perpendicular.x * half_width,
			h, center.z - direction.z * half_len - perpendicular.z * half_width)
		var v2 := Vector3(center.x + direction.x * half_len - perpendicular.x * half_width,
			h, center.z + direction.z * half_len - perpendicular.z * half_width)
		var v3 := Vector3(center.x + direction.x * half_len + perpendicular.x * half_width,
			h, center.z + direction.z * half_len + perpendicular.z * half_width)
		var v4 := Vector3(center.x - direction.x * half_len + perpendicular.x * half_width,
			h, center.z - direction.z * half_len + perpendicular.z * half_width)

		# Fill triangles
		st.add_vertex(v1)
		st.add_vertex(v2)
		st.add_vertex(v3)

		st.add_vertex(v1)
		st.add_vertex(v3)
		st.add_vertex(v4)

		# Outline
		var oh: float = h + 0.1
		var o1 := Vector3(v1.x, oh, v1.z)
		var o2 := Vector3(v2.x, oh, v2.z)
		var o3 := Vector3(v3.x, oh, v3.z)
		var o4 := Vector3(v4.x, oh, v4.z)

		ost.add_vertex(o1); ost.add_vertex(o2)
		ost.add_vertex(o2); ost.add_vertex(o3)
		ost.add_vertex(o3); ost.add_vertex(o4)
		ost.add_vertex(o4); ost.add_vertex(o1)

	# Draw the main line connecting start to end
	var start_h: float = _get_terrain_height(_wall_line_start) + HEIGHT_OFFSET + 0.15
	var end_h: float = _get_terrain_height(_wall_line_end) + HEIGHT_OFFSET + 0.15
	ost.add_vertex(Vector3(_wall_line_start.x, start_h, _wall_line_start.z))
	ost.add_vertex(Vector3(_wall_line_end.x, end_h, _wall_line_end.z))

	grid_mesh.mesh = st.commit()
	outline_mesh.mesh = ost.commit()


func _update_color() -> void:
	var color: Color

	if not _is_valid_placement:
		color = COLOR_INVALID
	else:
		match _current_job_type:
			UnifiedJob.Type.CLEAR_TERRAIN:
				color = COLOR_CLEAR
			UnifiedJob.Type.FLATTEN_AREA:
				color = COLOR_FLATTEN
			UnifiedJob.Type.BUILD_ROAD:
				color = COLOR_ROAD
			UnifiedJob.Type.BUILD_STRUCTURE:
				color = COLOR_BUILD
			_:
				color = COLOR_CLEAR

	grid_material.albedo_color = color

	# Outline is brighter version
	var outline_color := color
	outline_color.a = 0.9
	outline_material.albedo_color = outline_color


func _get_terrain_height(pos: Vector3) -> float:
	if not _terrain:
		_terrain = get_node_or_null("/root/TerrainIntegration")

	if _terrain and _terrain.has_method("get_height_at"):
		return _terrain.get_height_at(pos)

	return 0.0


## Show area preview
func show_area(bounds: Rect2, job_type: UnifiedJob.Type, is_valid: bool = true) -> void:
	_preview_mode = 0
	_area_bounds = bounds
	_current_job_type = job_type
	_is_valid_placement = is_valid
	visible = true
	_update_timer = 0.0  # Force immediate update


## Show polyline preview
func show_polyline(points: PackedVector3Array, job_type: UnifiedJob.Type, is_valid: bool = true) -> void:
	_preview_mode = 1
	_polyline_points = points
	_current_job_type = job_type
	_is_valid_placement = is_valid
	visible = true
	_update_timer = 0.0


## Show single placement preview
func show_single(position: Vector3, job_type: UnifiedJob.Type, is_valid: bool = true) -> void:
	_preview_mode = 2
	_single_position = position
	_current_job_type = job_type
	_is_valid_placement = is_valid
	visible = true
	_update_timer = 0.0


## Show wall line preview (for sandbags, trenches, wire)
func show_wall_line(start_pos: Vector3, end_pos: Vector3, job_type: UnifiedJob.Type,
		segment_spacing: float = 2.0, is_valid: bool = true) -> void:
	_preview_mode = 3
	_wall_line_start = start_pos
	_wall_line_end = end_pos
	_wall_segment_spacing = segment_spacing
	_current_job_type = job_type
	_is_valid_placement = is_valid
	visible = true
	_update_timer = 0.0


## Hide the preview
func hide_preview() -> void:
	visible = false
	grid_mesh.mesh = null
	outline_mesh.mesh = null
