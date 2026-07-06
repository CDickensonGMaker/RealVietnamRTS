extends Node3D
class_name TerrainSplineVisualizer

## TerrainSplineVisualizer - Debug visualization for TerrainSpline
##
## Shows:
## - Spline curve as a colored line
## - Waypoints as spheres
## - Slope coloring (green = safe, yellow = steep, red = impassable)

# =============================================================================
# CONSTANTS
# =============================================================================

const SLOPE_SAFE_DEGREES := 15.0
const SLOPE_WARN_DEGREES := 25.0
const SLOPE_MAX_DEGREES := 30.0

const COLOR_SAFE := Color(0.2, 0.8, 0.2, 0.8)  # Green
const COLOR_WARN := Color(0.9, 0.7, 0.1, 0.8)  # Yellow
const COLOR_DANGER := Color(0.9, 0.2, 0.1, 0.8)  # Red
const COLOR_WAYPOINT := Color(0.3, 0.5, 1.0, 0.9)  # Blue

# =============================================================================
# PROPERTIES
# =============================================================================

@export var line_width: float = 0.15
@export var waypoint_radius: float = 0.5
@export var sample_count: int = 50
@export var show_waypoints: bool = true
@export var show_slope_colors: bool = true

var _spline: TerrainSpline = null
var _line_mesh: MeshInstance3D = null
var _waypoint_meshes: Array[MeshInstance3D] = []
var _material: StandardMaterial3D = null

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_setup_material()
	_setup_line_mesh()


func _setup_material() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _setup_line_mesh() -> void:
	_line_mesh = MeshInstance3D.new()
	_line_mesh.material_override = _material
	add_child(_line_mesh)


# =============================================================================
# PUBLIC API
# =============================================================================

func set_spline(spline: TerrainSpline) -> void:
	"""Set the spline to visualize"""
	_spline = spline
	rebuild_visualization()


func rebuild_visualization() -> void:
	"""Rebuild all visual elements"""
	_clear_waypoint_meshes()

	if not _spline:
		if _line_mesh:
			_line_mesh.mesh = null
		return

	_rebuild_line()

	if show_waypoints:
		_rebuild_waypoints()


func clear() -> void:
	"""Clear all visualization"""
	_spline = null
	if _line_mesh:
		_line_mesh.mesh = null
	_clear_waypoint_meshes()


# =============================================================================
# INTERNAL
# =============================================================================

func _rebuild_line() -> void:
	"""Rebuild the line mesh from spline samples"""
	# Ensure line mesh exists (may be called before _ready via factory method)
	if not _line_mesh:
		_setup_material()
		_setup_line_mesh()

	if not _spline or _spline.get_total_length() <= 0.0:
		_line_mesh.mesh = null
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var total_length: float = _spline.get_total_length()
	var step: float = total_length / float(sample_count)

	var prev_pos: Vector3 = Vector3.ZERO
	var prev_color: Color = COLOR_SAFE
	var first: bool = true

	for i in range(sample_count + 1):
		var dist: float = float(i) * step
		var pos: Vector3 = _spline.get_position_at_distance(dist)
		var tangent: Vector3 = _spline.get_tangent_at_distance(dist)

		# Calculate color based on slope
		var color: Color = COLOR_SAFE
		if show_slope_colors:
			var slope_deg: float = absf(rad_to_deg(atan(_spline.get_slope_at_distance(dist))))
			if slope_deg > SLOPE_MAX_DEGREES:
				color = COLOR_DANGER
			elif slope_deg > SLOPE_WARN_DEGREES:
				color = COLOR_WARN.lerp(COLOR_DANGER, (slope_deg - SLOPE_WARN_DEGREES) / (SLOPE_MAX_DEGREES - SLOPE_WARN_DEGREES))
			elif slope_deg > SLOPE_SAFE_DEGREES:
				color = COLOR_SAFE.lerp(COLOR_WARN, (slope_deg - SLOPE_SAFE_DEGREES) / (SLOPE_WARN_DEGREES - SLOPE_SAFE_DEGREES))

		# Create line segment as thin quad strip
		var perp: Vector3 = Vector3(-tangent.z, 0.0, tangent.x).normalized() * line_width * 0.5
		var up: Vector3 = Vector3.UP * line_width * 0.5

		if not first:
			# Create quad between previous and current position
			var pl := prev_pos - perp + up
			var pr := prev_pos + perp + up
			var cl := pos - perp + up
			var cr := pos + perp + up

			# Top face
			st.set_color(prev_color)
			st.add_vertex(pl)
			st.set_color(color)
			st.add_vertex(cl)
			st.set_color(prev_color)
			st.add_vertex(pr)

			st.set_color(color)
			st.add_vertex(cl)
			st.set_color(color)
			st.add_vertex(cr)
			st.set_color(prev_color)
			st.add_vertex(pr)

		prev_pos = pos
		prev_color = color
		first = false

	_line_mesh.mesh = st.commit()


func _rebuild_waypoints() -> void:
	"""Create sphere meshes at each waypoint"""
	_clear_waypoint_meshes()

	if not _spline:
		return

	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = waypoint_radius
	sphere_mesh.height = waypoint_radius * 2.0
	sphere_mesh.radial_segments = 8
	sphere_mesh.rings = 4

	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR_WAYPOINT
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for i in range(_spline.get_waypoint_count()):
		var wp: Vector3 = _spline.get_waypoint(i)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = sphere_mesh
		mesh_instance.material_override = mat
		mesh_instance.position = wp
		add_child(mesh_instance)
		_waypoint_meshes.append(mesh_instance)


func _clear_waypoint_meshes() -> void:
	"""Remove all waypoint sphere meshes"""
	for mesh in _waypoint_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_waypoint_meshes.clear()


# =============================================================================
# FACTORY
# =============================================================================

static func create(spline: TerrainSpline) -> TerrainSplineVisualizer:
	"""Factory method to create a visualizer for a spline"""
	var viz := TerrainSplineVisualizer.new()
	viz.set_spline(spline)
	return viz
