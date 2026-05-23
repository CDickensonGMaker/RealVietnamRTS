class_name RoadSegmentNode
extends Node3D
## RoadSegmentNode - A segment of road that increases vehicle speed
##
## Road segments:
## - Follow a path between waypoints
## - Provide speed bonus to vehicles on them
## - Connect to form road networks
## - Have visual dirt/gravel track appearance

signal road_started()
signal road_progress(progress: float)
signal road_complete()
signal vehicle_entered(vehicle: Node3D)
signal vehicle_exited(vehicle: Node3D)

## Road width in meters
@export var road_width: float = 4.0

## Speed multiplier for vehicles on road
@export var speed_multiplier: float = 1.5

## Path points defining the road
var path_points: PackedVector3Array = PackedVector3Array()

## Current construction progress (0.0 to 1.0)
var current_progress: float = 0.0

## Whether construction has started
var is_building: bool = false

## Whether road is complete
var is_complete: bool = false

## Vehicles currently on the road
var vehicles_on_road: Array[Node3D] = []

## Connected road segments
var connected_segments: Array[RoadSegmentNode] = []

## Visual components
var road_mesh: MeshInstance3D
var outline_mesh: MeshInstance3D

## Detection areas along the road
var detection_areas: Array[Area3D] = []

## Materials
var _road_material: StandardMaterial3D
var _outline_material: StandardMaterial3D


func _ready() -> void:
	# Add to groups
	add_to_group("roads")
	add_to_group("road_segments")

	# Create visuals
	_setup_visuals()

	# Create detection areas along path
	_setup_detection_areas()


func _setup_visuals() -> void:
	# Road material (dirt/gravel)
	_road_material = StandardMaterial3D.new()
	_road_material.albedo_color = Color(0.5, 0.4, 0.3)
	_road_material.roughness = 0.95
	_road_material.metallic = 0.0

	# Create road mesh
	road_mesh = MeshInstance3D.new()
	road_mesh.material_override = _road_material
	road_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	road_mesh.visible = false
	add_child(road_mesh)

	# Outline material
	_outline_material = StandardMaterial3D.new()
	_outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_material.albedo_color = Color(0.6, 0.5, 0.3, 0.5)
	_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Create outline
	outline_mesh = MeshInstance3D.new()
	outline_mesh.material_override = _outline_material
	outline_mesh.position.y = 0.05
	add_child(outline_mesh)

	# Build initial outline from path
	if path_points.size() >= 2:
		outline_mesh.mesh = _create_path_outline_mesh()


func _setup_detection_areas() -> void:
	## Create Area3D nodes along the path to detect vehicles
	if path_points.size() < 2:
		return

	# Create one area per segment
	for i in range(path_points.size() - 1):
		var p1: Vector3 = path_points[i]
		var p2: Vector3 = path_points[i + 1]
		var segment_center: Vector3 = (p1 + p2) * 0.5
		var segment_length: float = p1.distance_to(p2)
		var segment_dir: Vector3 = (p2 - p1).normalized()

		var area := Area3D.new()
		area.position = segment_center - global_position
		area.collision_layer = 64  # Buildings layer
		area.collision_mask = 16 | 32  # Vehicles and helicopters

		# Look along segment direction
		if segment_dir.length() > 0.1:
			var look_target: Vector3 = area.position + segment_dir
			look_target.y = area.position.y
			if look_target.distance_to(area.position) > 0.1:
				area.look_at(look_target + global_position, Vector3.UP)

		# Create box collision
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(segment_length, 1.0, road_width)
		shape.shape = box
		shape.position.y = 0.5
		area.add_child(shape)

		# Connect signals
		area.body_entered.connect(_on_vehicle_entered)
		area.body_exited.connect(_on_vehicle_exited)

		add_child(area)
		detection_areas.append(area)


func _on_vehicle_entered(body: Node3D) -> void:
	if not is_complete:
		return

	if body.is_in_group("vehicles"):
		if body not in vehicles_on_road:
			vehicles_on_road.append(body)
			_apply_speed_bonus(body, true)
			vehicle_entered.emit(body)


func _on_vehicle_exited(body: Node3D) -> void:
	if body in vehicles_on_road:
		vehicles_on_road.erase(body)
		_apply_speed_bonus(body, false)
		vehicle_exited.emit(body)


func _apply_speed_bonus(vehicle: Node3D, entering: bool) -> void:
	## Apply or remove speed bonus from vehicle
	if vehicle.has_method("set_terrain_speed_modifier"):
		if entering:
			vehicle.set_terrain_speed_modifier(speed_multiplier)
		else:
			vehicle.set_terrain_speed_modifier(1.0)
	elif "terrain_speed_modifier" in vehicle:
		vehicle.terrain_speed_modifier = speed_multiplier if entering else 1.0


## Set the path points for this road
func set_path(points: PackedVector3Array) -> void:
	path_points = points

	# Rebuild outline
	if outline_mesh:
		outline_mesh.mesh = _create_path_outline_mesh()

	# Rebuild detection areas
	for area in detection_areas:
		area.queue_free()
	detection_areas.clear()
	_setup_detection_areas()


## Add work progress (called by workers)
## Returns true if construction is complete
func add_work(amount: float) -> bool:
	if not is_building:
		is_building = true
		road_started.emit()

	var new_progress: float = minf(current_progress + amount, 1.0)

	if new_progress != current_progress:
		current_progress = new_progress
		_update_visuals()
		road_progress.emit(current_progress)

	if current_progress >= 1.0:
		_complete()
		return true

	return false


func _update_visuals() -> void:
	# Show road after 10% progress
	if current_progress > 0.1:
		road_mesh.visible = true
		road_mesh.mesh = _create_road_mesh(current_progress)

	# Fade outline
	_outline_material.albedo_color.a = lerpf(0.5, 0.1, current_progress)


func _complete() -> void:
	is_building = false
	is_complete = true

	# Final visual update
	road_mesh.mesh = _create_road_mesh(1.0)

	# Hide outline
	outline_mesh.visible = false

	# Darken road color for "worn in" look
	_road_material.albedo_color = Color(0.45, 0.35, 0.25)

	road_complete.emit()
	print("[RoadSegment] Complete! %d points, %.1fm total" % [path_points.size(), get_total_length()])


## Get total road length
func get_total_length() -> float:
	var total: float = 0.0
	for i in range(path_points.size() - 1):
		total += path_points[i].distance_to(path_points[i + 1])
	return total


## Connect to another road segment
func connect_to(other: RoadSegmentNode) -> void:
	if other and other not in connected_segments:
		connected_segments.append(other)
		other.connected_segments.append(self)


## Get closest point on road to a position
func get_closest_point(pos: Vector3) -> Vector3:
	if path_points.size() < 2:
		return pos

	var closest: Vector3 = path_points[0]
	var closest_dist: float = INF

	for i in range(path_points.size() - 1):
		var p1: Vector3 = path_points[i]
		var p2: Vector3 = path_points[i + 1]

		# Project pos onto line segment
		var segment: Vector3 = p2 - p1
		var seg_length: float = segment.length()
		if seg_length < 0.01:
			continue

		var t: float = clampf((pos - p1).dot(segment) / (seg_length * seg_length), 0.0, 1.0)
		var projected: Vector3 = p1 + segment * t

		var dist: float = pos.distance_to(projected)
		if dist < closest_dist:
			closest_dist = dist
			closest = projected

	return closest


## Check if position is on the road
func is_on_road(pos: Vector3) -> bool:
	var closest: Vector3 = get_closest_point(pos)
	return pos.distance_to(closest) <= road_width * 0.6


## Get progress as 0.0 - 1.0
func get_progress() -> float:
	return current_progress


## Create road mesh
func _create_road_mesh(progress: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	if path_points.size() < 2:
		return st.commit()

	var hw: float = road_width * 0.5
	var total_length: float = get_total_length()
	var built_length: float = total_length * progress
	var current_length: float = 0.0

	for i in range(path_points.size() - 1):
		var p1: Vector3 = path_points[i]
		var p2: Vector3 = path_points[i + 1]
		var segment_length: float = p1.distance_to(p2)

		# Check if we've built past this segment
		if current_length >= built_length:
			break

		# Calculate how much of this segment to build
		var segment_progress: float = 1.0
		if current_length + segment_length > built_length:
			segment_progress = (built_length - current_length) / segment_length
			p2 = p1.lerp(p2, segment_progress)

		current_length += segment_length * segment_progress

		# Calculate perpendicular direction
		var dir: Vector3 = (p2 - p1).normalized()
		dir.y = 0
		var perp: Vector3 = Vector3(-dir.z, 0, dir.x) * hw

		# Snap Y to terrain
		p1.y = _get_terrain_height(p1) + 0.02
		p2.y = _get_terrain_height(p2) + 0.02

		# Quad for this segment
		var v1: Vector3 = p1 - perp - global_position
		var v2: Vector3 = p1 + perp - global_position
		var v3: Vector3 = p2 + perp - global_position
		var v4: Vector3 = p2 - perp - global_position

		# First triangle
		st.add_vertex(v1)
		st.add_vertex(v2)
		st.add_vertex(v3)

		# Second triangle
		st.add_vertex(v1)
		st.add_vertex(v3)
		st.add_vertex(v4)

	st.generate_normals()
	return st.commit()


## Create outline mesh showing planned path
func _create_path_outline_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	if path_points.size() < 2:
		return st.commit()

	var hw: float = road_width * 0.5

	for i in range(path_points.size() - 1):
		var p1: Vector3 = path_points[i] - global_position
		var p2: Vector3 = path_points[i + 1] - global_position

		# Calculate perpendicular
		var dir: Vector3 = (p2 - p1).normalized()
		dir.y = 0
		var perp: Vector3 = Vector3(-dir.z, 0, dir.x) * hw

		# Left edge
		st.add_vertex(p1 - perp)
		st.add_vertex(p2 - perp)

		# Right edge
		st.add_vertex(p1 + perp)
		st.add_vertex(p2 + perp)

	# End caps
	if path_points.size() >= 2:
		var p1: Vector3 = path_points[0] - global_position
		var p2: Vector3 = path_points[path_points.size() - 1] - global_position
		var dir1: Vector3 = (path_points[1] - path_points[0]).normalized()
		var dir2: Vector3 = (path_points[path_points.size() - 1] - path_points[path_points.size() - 2]).normalized()

		dir1.y = 0
		dir2.y = 0
		var perp1: Vector3 = Vector3(-dir1.z, 0, dir1.x) * hw
		var perp2: Vector3 = Vector3(-dir2.z, 0, dir2.x) * hw

		# Start cap
		st.add_vertex(p1 - perp1)
		st.add_vertex(p1 + perp1)

		# End cap
		st.add_vertex(p2 - perp2)
		st.add_vertex(p2 + perp2)

	return st.commit()


func _get_terrain_height(pos: Vector3) -> float:
	var terrain: Node = get_node_or_null("/root/UnifiedTerrain")
	if terrain and terrain.has_method("get_height_at"):
		return terrain.get_height_at(pos)

	var terrain_intg: Node = get_node_or_null("/root/TerrainIntegration")
	if terrain_intg and terrain_intg.has_method("get_height_at"):
		return terrain_intg.get_height_at(pos)

	return pos.y


## Factory: Create a road segment with path
static func create(points: PackedVector3Array, width: float = 4.0) -> RoadSegmentNode:
	var road := RoadSegmentNode.new()
	if points.size() > 0:
		road.position = points[0]
	road.road_width = width
	road.path_points = points
	return road
