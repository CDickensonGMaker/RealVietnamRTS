extends RefCounted
class_name TerrainSpline

## TerrainSpline - Smooth terrain-following curves for roads and paths
##
## Features:
## - Catmull-Rom spline interpolation for smooth curves
## - Automatic terrain height sampling
## - Road mesh generation with proper width
## - Slope validation for passability checks
##
## Usage:
##   var spline := TerrainSpline.new()
##   spline.set_terrain(terrain_node)
##   spline.set_waypoints([point1, point2, point3])
##   var mesh := spline.generate_road_mesh(4.0)  # 4m wide road

# =============================================================================
# CONSTANTS
# =============================================================================

const SAMPLES_PER_SEGMENT := 10  # Curve samples between each waypoint pair
const HEIGHT_OFFSET := 0.08  # Slight offset above terrain to prevent z-fighting
const MIN_SEGMENT_LENGTH := 0.5  # Minimum distance between samples

# =============================================================================
# PROPERTIES
# =============================================================================

## Original waypoints provided by user
var waypoints: Array[Vector3] = []

## Cached smoothed curve points (rebuilt when waypoints change)
var _cached_points: PackedVector3Array = PackedVector3Array()

## Cached distances from start for each cached point
var _cached_distances: PackedFloat32Array = PackedFloat32Array()

## Total length of the spline
var _cached_length: float = 0.0

## Terrain reference for height sampling
var _terrain: Node = null

## Whether cache needs rebuilding
var _dirty: bool = true

# =============================================================================
# CONSTRUCTION
# =============================================================================

func set_terrain(terrain: Node) -> void:
	"""Set the terrain node for height sampling"""
	_terrain = terrain


func set_waypoints(points: Array[Vector3]) -> void:
	"""Set waypoints and mark for rebuild"""
	waypoints.clear()
	for p in points:
		waypoints.append(p)
	_dirty = true


func add_waypoint(point: Vector3) -> void:
	"""Add a waypoint to the end"""
	waypoints.append(point)
	_dirty = true


func clear_waypoints() -> void:
	"""Remove all waypoints"""
	waypoints.clear()
	_dirty = true


func rebuild() -> void:
	"""Regenerate the smoothed curve from waypoints"""
	_cached_points.clear()
	_cached_distances.clear()
	_cached_length = 0.0

	if waypoints.size() < 2:
		_dirty = false
		return

	# For each segment between waypoints, generate smooth curve points
	for i in range(waypoints.size() - 1):
		var p0: Vector3 = waypoints[maxi(0, i - 1)]
		var p1: Vector3 = waypoints[i]
		var p2: Vector3 = waypoints[mini(waypoints.size() - 1, i + 1)]
		var p3: Vector3 = waypoints[mini(waypoints.size() - 1, i + 2)]

		# Sample points along this segment
		for j in range(SAMPLES_PER_SEGMENT):
			var t: float = float(j) / float(SAMPLES_PER_SEGMENT)
			var pos: Vector3 = _catmull_rom(p0, p1, p2, p3, t)

			# Sample terrain height
			pos.y = _get_terrain_height(pos) + HEIGHT_OFFSET

			# Calculate distance from previous point
			if _cached_points.size() > 0:
				var prev: Vector3 = _cached_points[_cached_points.size() - 1]
				_cached_length += pos.distance_to(prev)

			_cached_points.append(pos)
			_cached_distances.append(_cached_length)

	# Add final waypoint
	var final_pos: Vector3 = waypoints[waypoints.size() - 1]
	final_pos.y = _get_terrain_height(final_pos) + HEIGHT_OFFSET

	if _cached_points.size() > 0:
		var prev: Vector3 = _cached_points[_cached_points.size() - 1]
		_cached_length += final_pos.distance_to(prev)

	_cached_points.append(final_pos)
	_cached_distances.append(_cached_length)

	_dirty = false


# =============================================================================
# QUERIES
# =============================================================================

func get_total_length() -> float:
	"""Get the total length of the spline in meters"""
	if _dirty:
		rebuild()
	return _cached_length


func get_position_at_distance(dist: float) -> Vector3:
	"""Get world position at a distance along the spline"""
	if _dirty:
		rebuild()

	if _cached_points.size() == 0:
		return Vector3.ZERO

	if dist <= 0.0:
		return _cached_points[0]

	if dist >= _cached_length:
		return _cached_points[_cached_points.size() - 1]

	# Binary search for the segment containing this distance
	var idx: int = _find_segment_index(dist)

	# Interpolate between cached points
	var d0: float = _cached_distances[idx]
	var d1: float = _cached_distances[idx + 1]
	var t: float = (dist - d0) / maxf(d1 - d0, 0.001)

	return _cached_points[idx].lerp(_cached_points[idx + 1], t)


func get_tangent_at_distance(dist: float) -> Vector3:
	"""Get the forward direction at a distance along the spline"""
	if _dirty:
		rebuild()

	if _cached_points.size() < 2:
		return Vector3.FORWARD

	# Get positions slightly before and after
	var delta: float = 0.5
	var pos_before: Vector3 = get_position_at_distance(dist - delta)
	var pos_after: Vector3 = get_position_at_distance(dist + delta)

	var tangent: Vector3 = (pos_after - pos_before).normalized()
	if tangent.length_squared() < 0.001:
		return Vector3.FORWARD

	return tangent


func get_normal_at_distance(dist: float) -> Vector3:
	"""Get the up-facing normal at a distance (for banking roads)"""
	var tangent: Vector3 = get_tangent_at_distance(dist)
	# Cross with world up to get perpendicular, then cross again for normal
	var right: Vector3 = tangent.cross(Vector3.UP).normalized()
	return right.cross(tangent).normalized()


func sample_points(count: int) -> PackedVector3Array:
	"""Get evenly-spaced sample points along the spline"""
	if _dirty:
		rebuild()

	var result := PackedVector3Array()
	if count <= 0 or _cached_length <= 0.0:
		return result

	var step: float = _cached_length / float(count - 1) if count > 1 else 0.0

	for i in range(count):
		var dist: float = float(i) * step
		result.append(get_position_at_distance(dist))

	return result


func get_waypoint_count() -> int:
	"""Get the number of waypoints"""
	return waypoints.size()


func get_waypoint(index: int) -> Vector3:
	"""Get a specific waypoint"""
	if index < 0 or index >= waypoints.size():
		return Vector3.ZERO
	return waypoints[index]


# =============================================================================
# MESH GENERATION
# =============================================================================

func generate_road_mesh(width: float, segments_per_meter: float = 0.5) -> ArrayMesh:
	"""Generate a road mesh following the spline"""
	if _dirty:
		rebuild()

	if _cached_points.size() < 2:
		return ArrayMesh.new()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_width: float = width * 0.5
	var segment_count: int = maxi(2, int(_cached_length * segments_per_meter))
	var step: float = _cached_length / float(segment_count)

	var prev_left: Vector3 = Vector3.ZERO
	var prev_right: Vector3 = Vector3.ZERO
	var first: bool = true

	for i in range(segment_count + 1):
		var dist: float = float(i) * step
		var center: Vector3 = get_position_at_distance(dist)
		var tangent: Vector3 = get_tangent_at_distance(dist)

		# Calculate perpendicular direction (horizontal only)
		var perp: Vector3 = Vector3(-tangent.z, 0.0, tangent.x).normalized() * half_width

		var left: Vector3 = center - perp
		var right: Vector3 = center + perp

		# Sample terrain height for left and right edges
		left.y = _get_terrain_height(left) + HEIGHT_OFFSET
		right.y = _get_terrain_height(right) + HEIGHT_OFFSET

		# UV coordinates based on distance
		var u: float = dist / _cached_length

		if not first:
			# Create two triangles for this quad
			# Triangle 1: prev_left, left, prev_right
			st.set_uv(Vector2(0.0, u - step / _cached_length))
			st.add_vertex(prev_left)
			st.set_uv(Vector2(0.0, u))
			st.add_vertex(left)
			st.set_uv(Vector2(1.0, u - step / _cached_length))
			st.add_vertex(prev_right)

			# Triangle 2: left, right, prev_right
			st.set_uv(Vector2(0.0, u))
			st.add_vertex(left)
			st.set_uv(Vector2(1.0, u))
			st.add_vertex(right)
			st.set_uv(Vector2(1.0, u - step / _cached_length))
			st.add_vertex(prev_right)

		prev_left = left
		prev_right = right
		first = false

	st.generate_normals()
	return st.commit()


# =============================================================================
# VALIDATION
# =============================================================================

func get_max_slope() -> float:
	"""Get the steepest slope along the spline (0.0 = flat, 1.0 = vertical)"""
	if _dirty:
		rebuild()

	if _cached_points.size() < 2:
		return 0.0

	var max_slope: float = 0.0

	for i in range(_cached_points.size() - 1):
		var p1: Vector3 = _cached_points[i]
		var p2: Vector3 = _cached_points[i + 1]

		var horizontal_dist: float = Vector2(p2.x - p1.x, p2.z - p1.z).length()
		var vertical_dist: float = absf(p2.y - p1.y)

		if horizontal_dist > 0.01:
			var slope: float = vertical_dist / horizontal_dist
			max_slope = maxf(max_slope, slope)

	return max_slope


func get_max_slope_degrees() -> float:
	"""Get the steepest slope in degrees"""
	return rad_to_deg(atan(get_max_slope()))


func is_passable(max_slope_degrees: float = 30.0) -> bool:
	"""Check if the entire spline is passable (no slopes too steep)"""
	return get_max_slope_degrees() <= max_slope_degrees


func get_slope_at_distance(dist: float) -> float:
	"""Get the slope at a specific distance (0.0 = flat, positive = uphill)"""
	var delta: float = 1.0
	var p1: Vector3 = get_position_at_distance(dist - delta * 0.5)
	var p2: Vector3 = get_position_at_distance(dist + delta * 0.5)

	var horizontal_dist: float = Vector2(p2.x - p1.x, p2.z - p1.z).length()
	if horizontal_dist < 0.01:
		return 0.0

	return (p2.y - p1.y) / horizontal_dist


# =============================================================================
# INTERNAL HELPERS
# =============================================================================

func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	"""Catmull-Rom spline interpolation"""
	var t2: float = t * t
	var t3: float = t2 * t

	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


func _get_terrain_height(pos: Vector3) -> float:
	"""Sample terrain height at a position"""
	if _terrain and _terrain.has_method("get_height_at"):
		return _terrain.get_height_at(pos)

	# Fallback: return the input Y
	return pos.y


func _find_segment_index(dist: float) -> int:
	"""Binary search to find the segment containing a distance"""
	var low: int = 0
	var high: int = _cached_distances.size() - 1

	while low < high - 1:
		var mid: int = (low + high) / 2
		if _cached_distances[mid] <= dist:
			low = mid
		else:
			high = mid

	return low


# =============================================================================
# STATIC FACTORY
# =============================================================================

static func create_from_points(points: Array[Vector3], terrain: Node = null) -> TerrainSpline:
	"""Factory method to create a spline from points"""
	var spline := TerrainSpline.new()
	if terrain:
		spline.set_terrain(terrain)
	spline.set_waypoints(points)
	return spline
