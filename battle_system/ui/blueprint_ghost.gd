class_name BlueprintGhost
extends Node3D
## BlueprintGhost - Visual preview for building placement
##
## Shows a translucent "ghost" preview while placing structures, roads, trenches, etc.
## Changes color based on placement validity (green = valid, red = invalid).
## Supports different shapes for different job types.

enum GhostType {
	RECTANGLE,  # Buildings, clearing zones
	LINE,       # Roads, wires, trenches
	CIRCLE,     # Artillery pits, helipads
}

enum PlacementState {
	VALID,      # Can place here
	INVALID,    # Blocked/obstructed
	WARNING,    # Partially valid (e.g., overlaps existing)
}

## Configuration
@export var ghost_type: GhostType = GhostType.RECTANGLE
@export var base_size: Vector3 = Vector3(8, 3, 8)  # Width, height, depth
@export var line_width: float = 4.0  # For LINE type
@export var circle_radius: float = 6.0  # For CIRCLE type

## Visual settings
const VALID_COLOR := Color(0.2, 0.9, 0.3, 0.35)      # Green, translucent
const INVALID_COLOR := Color(0.9, 0.2, 0.2, 0.35)    # Red, translucent
const WARNING_COLOR := Color(0.9, 0.7, 0.2, 0.35)    # Yellow, translucent
const OUTLINE_VALID := Color(0.3, 1.0, 0.4, 0.8)     # Bright green outline
const OUTLINE_INVALID := Color(1.0, 0.3, 0.3, 0.8)   # Bright red outline
const OUTLINE_WARNING := Color(1.0, 0.8, 0.3, 0.8)   # Bright yellow outline
const GRID_COLOR := Color(0.5, 0.5, 0.5, 0.3)        # Grid lines inside ghost

## State
var placement_state: PlacementState = PlacementState.VALID
var _line_points: PackedVector3Array = []  # For LINE type

## Visual components
var _fill_mesh: MeshInstance3D
var _outline_mesh: MeshInstance3D
var _grid_mesh: MeshInstance3D  # Internal grid pattern
var _fill_material: StandardMaterial3D
var _outline_material: StandardMaterial3D
var _grid_material: StandardMaterial3D

## Height sampling
var _terrain: Node

## Smooth following - Alpha polish
var _target_position: Vector3 = Vector3.ZERO
var _smooth_speed: float = 20.0  # Higher = snappier following
var _terrain_conform: bool = true  # Sample terrain at corners

## Corner height cache for terrain conforming
var _corner_heights: Array[float] = [0.0, 0.0, 0.0, 0.0]  # BL, BR, TR, TL


func _ready() -> void:
	# Get terrain for height sampling - check multiple sources
	_terrain = get_node_or_null("/root/UnifiedTerrain")
	if not _terrain:
		_terrain = get_node_or_null("/root/TerrainIntegration")
	if not _terrain:
		# Check for local terrain in parent scene
		var parent := get_parent()
		if parent:
			_terrain = parent.get_node_or_null("LocalTerrain")

	_setup_materials()
	_setup_meshes()

	# Start hidden
	visible = false
	_target_position = global_position


func _process(_delta: float) -> void:
	# Snap position to target (no interpolation - ensures ghost matches cursor exactly)
	if visible and _target_position != Vector3.ZERO:
		global_position.x = _target_position.x
		global_position.z = _target_position.z
		# Simple height snap (terrain conforming disabled for performance)
		global_position.y = _get_height_at(global_position.x, global_position.z)


func _setup_materials() -> void:
	# Fill material - translucent colored fill
	_fill_material = StandardMaterial3D.new()
	_fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fill_material.no_depth_test = true
	_fill_material.render_priority = 15
	_fill_material.albedo_color = VALID_COLOR

	# Outline material - brighter, more opaque
	_outline_material = StandardMaterial3D.new()
	_outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_outline_material.no_depth_test = true
	_outline_material.render_priority = 16
	_outline_material.albedo_color = OUTLINE_VALID

	# Grid material - subtle internal pattern
	_grid_material = StandardMaterial3D.new()
	_grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_grid_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_grid_material.no_depth_test = true
	_grid_material.render_priority = 14
	_grid_material.albedo_color = GRID_COLOR


func _setup_meshes() -> void:
	# Fill mesh
	_fill_mesh = MeshInstance3D.new()
	_fill_mesh.material_override = _fill_material
	add_child(_fill_mesh)

	# Outline mesh
	_outline_mesh = MeshInstance3D.new()
	_outline_mesh.material_override = _outline_material
	add_child(_outline_mesh)

	# Grid mesh
	_grid_mesh = MeshInstance3D.new()
	_grid_mesh.material_override = _grid_material
	add_child(_grid_mesh)

	# Build initial meshes
	_rebuild_meshes()


func _rebuild_meshes() -> void:
	match ghost_type:
		GhostType.RECTANGLE:
			_build_rectangle_meshes()
		GhostType.LINE:
			_build_line_meshes()
		GhostType.CIRCLE:
			_build_circle_meshes()


## ==================== RECTANGLE GHOST ====================

func _build_rectangle_meshes() -> void:
	var hw := base_size.x * 0.5
	var hd := base_size.z * 0.5
	var h := base_size.y

	# Fill: Box with open top (shows building volume)
	_fill_mesh.mesh = _create_box_mesh(base_size)
	_fill_mesh.position = Vector3(0, h * 0.5, 0)

	# Outline: Rectangle at base + vertical corner posts
	_outline_mesh.mesh = _create_rectangle_outline(hw, hd, h)

	# Grid: Lines inside the footprint
	_grid_mesh.mesh = _create_footprint_grid(hw, hd, 2.0)  # 2m grid spacing


func _create_box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _create_rectangle_outline(hw: float, hd: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var y_base := 0.1  # Slightly above ground
	var y_top := height

	# Base rectangle
	var corners: Array[Vector3] = [
		Vector3(-hw, y_base, -hd),
		Vector3(hw, y_base, -hd),
		Vector3(hw, y_base, hd),
		Vector3(-hw, y_base, hd),
	]
	for i in range(4):
		st.add_vertex(corners[i])
		st.add_vertex(corners[(i + 1) % 4])

	# Top rectangle
	for i in range(4):
		var top: Vector3 = corners[i] + Vector3(0, y_top - y_base, 0)
		var next_top: Vector3 = corners[(i + 1) % 4] + Vector3(0, y_top - y_base, 0)
		st.add_vertex(top)
		st.add_vertex(next_top)

	# Vertical posts at corners
	for corner: Vector3 in corners:
		st.add_vertex(corner)
		st.add_vertex(corner + Vector3(0, y_top - y_base, 0))

	return st.commit()


func _create_footprint_grid(hw: float, hd: float, spacing: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var y := 0.15

	# Vertical lines (along Z)
	var x := -hw + spacing
	while x < hw:
		st.add_vertex(Vector3(x, y, -hd))
		st.add_vertex(Vector3(x, y, hd))
		x += spacing

	# Horizontal lines (along X)
	var z := -hd + spacing
	while z < hd:
		st.add_vertex(Vector3(-hw, y, z))
		st.add_vertex(Vector3(hw, y, z))
		z += spacing

	return st.commit()


## Rebuild outline mesh with terrain-conforming heights
## Called each frame when moving over hilly terrain
func _rebuild_terrain_conforming_outline() -> void:
	if not _outline_mesh or ghost_type != GhostType.RECTANGLE:
		return

	var hw := base_size.x * 0.5
	var hd := base_size.z * 0.5
	var h := base_size.y

	# Convert corner heights to local space (relative to ghost center)
	var avg_height := global_position.y
	var local_heights: Array[float] = [
		_corner_heights[0] - avg_height,
		_corner_heights[1] - avg_height,
		_corner_heights[2] - avg_height,
		_corner_heights[3] - avg_height,
	]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var y_offset := 0.1  # Slightly above ground

	# Terrain-conforming base rectangle
	var corners: Array[Vector3] = [
		Vector3(-hw, y_offset + local_heights[0], -hd),  # BL
		Vector3(hw, y_offset + local_heights[1], -hd),   # BR
		Vector3(hw, y_offset + local_heights[2], hd),    # TR
		Vector3(-hw, y_offset + local_heights[3], hd),   # TL
	]

	# Draw base outline following terrain
	for i in range(4):
		st.add_vertex(corners[i])
		st.add_vertex(corners[(i + 1) % 4])

	# Top rectangle (flat, at building height)
	var y_top := h
	for i in range(4):
		var top := Vector3(corners[i].x, y_top, corners[i].z)
		var next_top := Vector3(corners[(i + 1) % 4].x, y_top, corners[(i + 1) % 4].z)
		st.add_vertex(top)
		st.add_vertex(next_top)

	# Vertical posts at corners (from terrain to building height)
	for i in range(4):
		st.add_vertex(corners[i])
		st.add_vertex(Vector3(corners[i].x, y_top, corners[i].z))

	_outline_mesh.mesh = st.commit()


## ==================== LINE GHOST (Roads, Wires, Trenches) ====================

func set_line_points(points: PackedVector3Array) -> void:
	_line_points = points
	if ghost_type == GhostType.LINE:
		_build_line_meshes()


func _build_line_meshes() -> void:
	if _line_points.size() < 2:
		_fill_mesh.mesh = null
		_outline_mesh.mesh = null
		_grid_mesh.mesh = null
		return

	# Fill: Extruded path with width
	_fill_mesh.mesh = _create_line_fill(_line_points, line_width)
	_fill_mesh.position = Vector3.ZERO

	# Outline: Path edges
	_outline_mesh.mesh = _create_line_outline(_line_points, line_width)

	# Grid: Cross lines along path
	_grid_mesh.mesh = _create_line_grid(_line_points, line_width, 4.0)


func _create_line_fill(points: PackedVector3Array, width: float) -> ArrayMesh:
	if points.size() < 2:
		return ArrayMesh.new()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hw := width * 0.5
	var y := 0.2  # Above ground

	for i in range(points.size() - 1):
		var p1 := points[i]
		var p2 := points[i + 1]

		# Direction and perpendicular
		var dir := (p2 - p1).normalized()
		var perp := Vector3(-dir.z, 0, dir.x)

		# Four corners of this segment
		var bl := Vector3(p1.x - perp.x * hw, y, p1.z - perp.z * hw)
		var br := Vector3(p1.x + perp.x * hw, y, p1.z + perp.z * hw)
		var tl := Vector3(p2.x - perp.x * hw, y, p2.z - perp.z * hw)
		var tr := Vector3(p2.x + perp.x * hw, y, p2.z + perp.z * hw)

		# Two triangles
		st.add_vertex(bl)
		st.add_vertex(br)
		st.add_vertex(tr)

		st.add_vertex(bl)
		st.add_vertex(tr)
		st.add_vertex(tl)

	return st.commit()


func _create_line_outline(points: PackedVector3Array, width: float) -> ArrayMesh:
	if points.size() < 2:
		return ArrayMesh.new()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var hw := width * 0.5
	var y := 0.25

	# Build left and right edge paths
	var left_edge: PackedVector3Array = []
	var right_edge: PackedVector3Array = []

	for i in range(points.size()):
		var p := points[i]
		var dir: Vector3

		if i == 0:
			dir = (points[1] - points[0]).normalized()
		elif i == points.size() - 1:
			dir = (points[i] - points[i - 1]).normalized()
		else:
			dir = ((points[i + 1] - points[i - 1]) * 0.5).normalized()

		var perp := Vector3(-dir.z, 0, dir.x)
		left_edge.append(Vector3(p.x - perp.x * hw, y, p.z - perp.z * hw))
		right_edge.append(Vector3(p.x + perp.x * hw, y, p.z + perp.z * hw))

	# Draw edges
	for i in range(left_edge.size() - 1):
		st.add_vertex(left_edge[i])
		st.add_vertex(left_edge[i + 1])
		st.add_vertex(right_edge[i])
		st.add_vertex(right_edge[i + 1])

	# End caps
	st.add_vertex(left_edge[0])
	st.add_vertex(right_edge[0])
	st.add_vertex(left_edge[left_edge.size() - 1])
	st.add_vertex(right_edge[right_edge.size() - 1])

	return st.commit()


func _create_line_grid(points: PackedVector3Array, width: float, spacing: float) -> ArrayMesh:
	if points.size() < 2:
		return ArrayMesh.new()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var hw := width * 0.5
	var y := 0.2

	# Cross lines at intervals along the path
	var dist_accum := 0.0
	for i in range(points.size() - 1):
		var p1 := points[i]
		var p2 := points[i + 1]
		var seg_len := p1.distance_to(p2)
		var dir := (p2 - p1).normalized()
		var perp := Vector3(-dir.z, 0, dir.x)

		# Add cross lines at spacing intervals
		var t := spacing - fmod(dist_accum, spacing)
		while t < seg_len:
			var pos := p1 + dir * t
			st.add_vertex(Vector3(pos.x - perp.x * hw, y, pos.z - perp.z * hw))
			st.add_vertex(Vector3(pos.x + perp.x * hw, y, pos.z + perp.z * hw))
			t += spacing

		dist_accum += seg_len

	return st.commit()


## ==================== CIRCLE GHOST (Helipads, Artillery) ====================

func _build_circle_meshes() -> void:
	# Fill: Flat disc
	_fill_mesh.mesh = _create_circle_fill(circle_radius)
	_fill_mesh.position = Vector3(0, 0.15, 0)

	# Outline: Circle edge
	_outline_mesh.mesh = _create_circle_outline(circle_radius)

	# Grid: Concentric rings + radial lines
	_grid_mesh.mesh = _create_circle_grid(circle_radius)


func _create_circle_fill(radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var segments := 32
	for i in range(segments):
		var angle1 := TAU * float(i) / float(segments)
		var angle2 := TAU * float(i + 1) / float(segments)

		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(angle1) * radius, 0, sin(angle1) * radius))
		st.add_vertex(Vector3(cos(angle2) * radius, 0, sin(angle2) * radius))

	return st.commit()


func _create_circle_outline(radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var segments := 32
	var y := 0.05
	for i in range(segments):
		var angle1 := TAU * float(i) / float(segments)
		var angle2 := TAU * float(i + 1) / float(segments)

		st.add_vertex(Vector3(cos(angle1) * radius, y, sin(angle1) * radius))
		st.add_vertex(Vector3(cos(angle2) * radius, y, sin(angle2) * radius))

	return st.commit()


func _create_circle_grid(radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var y := 0.1

	# Concentric rings at 1/3 and 2/3 radius
	var ring_pcts: Array[float] = [0.33, 0.66]
	for ring_pct: float in ring_pcts:
		var r: float = radius * ring_pct
		var segments := 24
		for i in range(segments):
			var angle1 := TAU * float(i) / float(segments)
			var angle2 := TAU * float(i + 1) / float(segments)
			st.add_vertex(Vector3(cos(angle1) * r, y, sin(angle1) * r))
			st.add_vertex(Vector3(cos(angle2) * r, y, sin(angle2) * r))

	# Radial lines (8 spokes)
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(angle) * radius, y, sin(angle) * radius))

	return st.commit()


## ==================== STATE MANAGEMENT ====================

func set_placement_state(state: PlacementState) -> void:
	if placement_state == state:
		return

	placement_state = state
	_update_colors()


func _update_colors() -> void:
	var fill_color: Color
	var outline_color: Color

	match placement_state:
		PlacementState.VALID:
			fill_color = VALID_COLOR
			outline_color = OUTLINE_VALID
		PlacementState.INVALID:
			fill_color = INVALID_COLOR
			outline_color = OUTLINE_INVALID
		PlacementState.WARNING:
			fill_color = WARNING_COLOR
			outline_color = OUTLINE_WARNING

	_fill_material.albedo_color = fill_color
	_outline_material.albedo_color = outline_color


## ==================== POSITIONING ====================

func update_position(world_pos: Vector3) -> void:
	# Set target for smooth interpolation (actual movement happens in _process)
	_target_position = world_pos

	# For immediate placement (no smooth), directly set position
	if not visible:
		var y := _get_height_at(world_pos.x, world_pos.z)
		global_position = Vector3(world_pos.x, y, world_pos.z)


## Get terrain height at a world position
func _get_height_at(x: float, z: float) -> float:
	# Try terrain manager with heightmap
	if _terrain:
		# TerrainManager or LocalTerrain with heightmap
		if _terrain.has_method("get") and _terrain.get("heightmap"):
			var hm = _terrain.get("heightmap")
			if hm and hm.has_method("sample_world"):
				return hm.sample_world(x, z)

		# TerrainIntegration with terrain_manager
		if _terrain.has_method("get") and _terrain.get("terrain_manager"):
			var tm = _terrain.get("terrain_manager")
			if tm and tm.has_method("get") and tm.get("heightmap"):
				var hm = tm.get("heightmap")
				if hm and hm.has_method("sample_world"):
					return hm.sample_world(x, z)

		# Direct get_height_at method
		if _terrain.has_method("get_height_at"):
			return _terrain.get_height_at(Vector3(x, 0, z))

	return 0.0


## Update terrain-conforming visuals for rectangle ghosts
func _update_terrain_conform() -> void:
	if ghost_type != GhostType.RECTANGLE:
		return

	var hw := base_size.x * 0.5
	var hd := base_size.z * 0.5
	var cx := global_position.x
	var cz := global_position.z

	# Sample height at all 4 corners
	_corner_heights[0] = _get_height_at(cx - hw, cz - hd)  # BL
	_corner_heights[1] = _get_height_at(cx + hw, cz - hd)  # BR
	_corner_heights[2] = _get_height_at(cx + hw, cz + hd)  # TR
	_corner_heights[3] = _get_height_at(cx - hw, cz + hd)  # TL

	# Center height is average of corners
	var avg_height := (_corner_heights[0] + _corner_heights[1] + _corner_heights[2] + _corner_heights[3]) / 4.0
	global_position.y = avg_height

	# Rebuild outline mesh with terrain-conforming corners
	_rebuild_terrain_conforming_outline()


func set_size(size: Vector3) -> void:
	base_size = size
	if ghost_type == GhostType.RECTANGLE:
		_rebuild_meshes()


func set_radius(radius: float) -> void:
	circle_radius = radius
	if ghost_type == GhostType.CIRCLE:
		_rebuild_meshes()


func set_width(width: float) -> void:
	line_width = width
	if ghost_type == GhostType.LINE:
		_rebuild_meshes()


## Configure smooth following behavior
func set_smooth_speed(speed: float) -> void:
	_smooth_speed = speed


## Enable/disable terrain conforming
func set_terrain_conform(enabled: bool) -> void:
	_terrain_conform = enabled


## Set terrain reference explicitly (for test scenes with local terrain)
func set_terrain(terrain_node: Node) -> void:
	_terrain = terrain_node


## ==================== SHOW/HIDE ====================

func show_ghost() -> void:
	visible = true


func hide_ghost() -> void:
	visible = false


## ==================== FACTORY METHODS ====================

static func create_rectangle(size: Vector3) -> BlueprintGhost:
	var ghost := BlueprintGhost.new()
	ghost.ghost_type = GhostType.RECTANGLE
	ghost.base_size = size
	return ghost


static func create_line(width: float) -> BlueprintGhost:
	var ghost := BlueprintGhost.new()
	ghost.ghost_type = GhostType.LINE
	ghost.line_width = width
	return ghost


static func create_circle(radius: float) -> BlueprintGhost:
	var ghost := BlueprintGhost.new()
	ghost.ghost_type = GhostType.CIRCLE
	ghost.circle_radius = radius
	return ghost


## Create ghost for a specific job type
static func create_for_job_type(job_type: int, size: Vector3 = Vector3(8, 3, 8)) -> BlueprintGhost:
	# Import job types
	const UnifiedJob = preload("res://firebase_system/job_system/unified_job.gd")

	match job_type:
		UnifiedJob.Type.CLEAR_TERRAIN:
			return create_rectangle(Vector3(size.x, 1.0, size.z))
		UnifiedJob.Type.FLATTEN_AREA:
			return create_rectangle(Vector3(size.x, 0.5, size.z))
		UnifiedJob.Type.BUILD_STRUCTURE:
			return create_rectangle(size)
		UnifiedJob.Type.BUILD_ROAD:
			return create_line(4.0)
		UnifiedJob.Type.DIG_TRENCH:
			return create_line(2.0)
		UnifiedJob.Type.LAY_WIRE:
			return create_line(1.5)
		_:
			return create_rectangle(size)
