class_name RoadDecalRenderer
extends MeshInstance3D
## RoadDecalRenderer - Generates dirt road mesh along waypoints
##
## Creates a flat textured mesh strip along an array of road waypoints.
## Updates progressively as the BUILD_ROAD job progresses, showing only
## the completed portion of the road.

const JobTypes = preload("res://firebase_system/jobs/job_types.gd")
const JobNode = preload("res://firebase_system/jobs/job_node.gd")

## Road configuration
const DEFAULT_ROAD_WIDTH := 3.0
const HEIGHT_OFFSET := 0.05  # Slightly above terrain to avoid z-fighting
const UV_SCALE := 0.25  # UV tiling along road length

## Road colors
const DIRT_COLOR := Color(0.35, 0.32, 0.28)  # Brown dirt
const WORN_COLOR := Color(0.42, 0.38, 0.32)  # Lighter worn path

## Road segments (for progressive rendering)
var _waypoints: PackedVector3Array = PackedVector3Array()
var _road_width: float = DEFAULT_ROAD_WIDTH
var _progress: float = 0.0  # 0.0 to 1.0

## Connected job node (if any)
var _job_node: JobNode = null

## Terrain reference
var _terrain: Node = null

## Material
var _road_material: StandardMaterial3D


func _init() -> void:
	_setup_material()


func _ready() -> void:
	_terrain = get_node_or_null("/root/TerrainIntegration")


func _setup_material() -> void:
	_road_material = StandardMaterial3D.new()
	_road_material.albedo_color = DIRT_COLOR
	_road_material.roughness = 0.9
	_road_material.metallic = 0.0
	_road_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_road_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = _road_material


## Setup road with waypoints
func setup(waypoints: PackedVector3Array, width: float = DEFAULT_ROAD_WIDTH) -> void:
	_waypoints = waypoints
	_road_width = width
	_progress = 0.0
	rebuild_mesh()


## Connect to a job node for progressive rendering
func connect_to_job(job: JobNode) -> void:
	if _job_node and _job_node.job_progress_updated.is_connected(_on_job_progress):
		_job_node.job_progress_updated.disconnect(_on_job_progress)

	_job_node = job

	if _job_node:
		_job_node.job_progress_updated.connect(_on_job_progress)
		_waypoints = _job_node.path_points
		_progress = _job_node.current_progress / _job_node.total_work
		rebuild_mesh()


## Set progress manually (0.0 to 1.0)
func set_progress(progress: float) -> void:
	_progress = clampf(progress, 0.0, 1.0)
	rebuild_mesh()


## Complete the road (show full length)
func complete() -> void:
	_progress = 1.0
	rebuild_mesh()


## Rebuild the road mesh based on current progress
func rebuild_mesh() -> void:
	if _waypoints.size() < 2:
		mesh = null
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Calculate total path length
	var total_length := 0.0
	for i in range(_waypoints.size() - 1):
		total_length += _waypoints[i].distance_to(_waypoints[i + 1])

	# Determine how much of the path to render based on progress
	var render_length: float = total_length * _progress

	if render_length <= 0:
		mesh = null
		return

	# Build road segments
	var accumulated_length := 0.0
	var half_width := _road_width * 0.5
	var uv_offset := 0.0

	for i in range(_waypoints.size() - 1):
		var p1: Vector3 = _waypoints[i]
		var p2: Vector3 = _waypoints[i + 1]

		var segment_length: float = p1.distance_to(p2)

		# Check if this segment is within render progress
		if accumulated_length >= render_length:
			break

		var segment_end_length: float = accumulated_length + segment_length

		# Calculate how much of this segment to render
		var segment_progress: float = 1.0
		if segment_end_length > render_length:
			segment_progress = (render_length - accumulated_length) / segment_length
			p2 = p1.lerp(p2, segment_progress)
			segment_length *= segment_progress

		# Build segment mesh
		_build_road_segment(st, p1, p2, half_width, uv_offset)

		accumulated_length += segment_length
		uv_offset += segment_length * UV_SCALE

	mesh = st.commit()


## Build a single road segment
func _build_road_segment(
	st: SurfaceTool,
	p1: Vector3,
	p2: Vector3,
	half_width: float,
	uv_offset: float
) -> void:
	# Direction and perpendicular
	var dir: Vector3 = (p2 - p1)
	var dir_2d := Vector2(dir.x, dir.z).normalized()
	var perp := Vector2(-dir_2d.y, dir_2d.x) * half_width

	# Get terrain heights
	var h1: float = _get_terrain_height(p1) + HEIGHT_OFFSET
	var h2: float = _get_terrain_height(p2) + HEIGHT_OFFSET

	# Also sample heights at edges for better terrain conforming
	var h1l: float = _get_terrain_height(Vector3(p1.x + perp.x, 0, p1.z + perp.y)) + HEIGHT_OFFSET
	var h1r: float = _get_terrain_height(Vector3(p1.x - perp.x, 0, p1.z - perp.y)) + HEIGHT_OFFSET
	var h2l: float = _get_terrain_height(Vector3(p2.x + perp.x, 0, p2.z + perp.y)) + HEIGHT_OFFSET
	var h2r: float = _get_terrain_height(Vector3(p2.x - perp.x, 0, p2.z - perp.y)) + HEIGHT_OFFSET

	# Build vertices
	var v1l := Vector3(p1.x + perp.x, h1l, p1.z + perp.y)
	var v1r := Vector3(p1.x - perp.x, h1r, p1.z - perp.y)
	var v1c := Vector3(p1.x, h1, p1.z)

	var v2l := Vector3(p2.x + perp.x, h2l, p2.z + perp.y)
	var v2r := Vector3(p2.x - perp.x, h2r, p2.z - perp.y)
	var v2c := Vector3(p2.x, h2, p2.z)

	var segment_length: float = p1.distance_to(p2)
	var uv_end: float = uv_offset + segment_length * UV_SCALE

	# Set normal (up)
	st.set_normal(Vector3.UP)

	# Color variation for worn center
	st.set_color(WORN_COLOR)

	# Left half (edge darker)
	st.set_color(DIRT_COLOR)
	st.set_uv(Vector2(0.0, uv_offset))
	st.add_vertex(v1l)

	st.set_color(WORN_COLOR)
	st.set_uv(Vector2(0.5, uv_offset))
	st.add_vertex(v1c)

	st.set_uv(Vector2(0.5, uv_end))
	st.add_vertex(v2c)

	st.set_color(DIRT_COLOR)
	st.set_uv(Vector2(0.0, uv_offset))
	st.add_vertex(v1l)

	st.set_color(WORN_COLOR)
	st.set_uv(Vector2(0.5, uv_end))
	st.add_vertex(v2c)

	st.set_color(DIRT_COLOR)
	st.set_uv(Vector2(0.0, uv_end))
	st.add_vertex(v2l)

	# Right half
	st.set_color(WORN_COLOR)
	st.set_uv(Vector2(0.5, uv_offset))
	st.add_vertex(v1c)

	st.set_color(DIRT_COLOR)
	st.set_uv(Vector2(1.0, uv_offset))
	st.add_vertex(v1r)

	st.set_uv(Vector2(1.0, uv_end))
	st.add_vertex(v2r)

	st.set_color(WORN_COLOR)
	st.set_uv(Vector2(0.5, uv_offset))
	st.add_vertex(v1c)

	st.set_color(DIRT_COLOR)
	st.set_uv(Vector2(1.0, uv_end))
	st.add_vertex(v2r)

	st.set_color(WORN_COLOR)
	st.set_uv(Vector2(0.5, uv_end))
	st.add_vertex(v2c)


func _get_terrain_height(pos: Vector3) -> float:
	if not _terrain:
		_terrain = get_node_or_null("/root/TerrainIntegration")

	if _terrain and _terrain.has_method("get_height_at"):
		return _terrain.get_height_at(pos)

	return pos.y


func _on_job_progress(_progress_amount: float) -> void:
	if _job_node:
		_progress = _job_node.current_progress / _job_node.total_work
		rebuild_mesh()


## Static factory method
static func create_for_waypoints(waypoints: PackedVector3Array, width: float = DEFAULT_ROAD_WIDTH) -> RoadDecalRenderer:
	var road := RoadDecalRenderer.new()
	road.name = "RoadDecal"
	road.setup(waypoints, width)
	road.complete()  # Show full road immediately
	return road


static func create_for_job(job: JobNode) -> RoadDecalRenderer:
	var road := RoadDecalRenderer.new()
	road.name = "RoadDecal_Job%d" % job.job_id
	road.connect_to_job(job)
	return road
