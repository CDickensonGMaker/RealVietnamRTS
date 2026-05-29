class_name ConstructionSiteNode
extends Area3D
## ConstructionSiteNode - Visual representation of an active construction job
##
## Shows build footprint, scaffolding that grows with progress,
## and spawns the actual building when complete.
## Uses Godot's built-in collision for worker detection.

signal construction_started()
signal construction_progress(progress: float)
signal construction_complete(building: Node3D)
signal construction_cancelled()

## Building type being constructed (from BuildingData)
@export var building_type: int = 0

## Building rotation in radians
@export var building_rotation: float = 0.0

## Footprint size in meters
@export var footprint_size: Vector2 = Vector2(4.0, 4.0)

## Current construction progress (0.0 to 1.0)
var current_progress: float = 0.0

## Whether construction has started
var is_constructing: bool = false

## Visual components
var foundation_mesh: MeshInstance3D
var scaffolding_mesh: MeshInstance3D
var outline_mesh: MeshInstance3D
var progress_bar: Node3D  # Container for progress bar billboard
var corner_stakes: Array[MeshInstance3D] = []  # Alpha polish: corner stake markers

## Collision shape for footprint
var collision_shape: CollisionShape3D
var box_shape: BoxShape3D

## Materials
var _foundation_material: StandardMaterial3D
var _scaffolding_material: StandardMaterial3D
var _outline_material: StandardMaterial3D
var _progress_bg_material: StandardMaterial3D
var _progress_fill_material: StandardMaterial3D
var _stake_material: StandardMaterial3D

## Progress bar components
var _progress_bg_mesh: MeshInstance3D
var _progress_fill_mesh: MeshInstance3D
const PROGRESS_BAR_WIDTH: float = 2.0
const PROGRESS_BAR_HEIGHT: float = 0.15
const PROGRESS_BAR_Y_OFFSET: float = 4.0  # Height above ground


func _ready() -> void:
	# Set up collision layers
	# Layer 7 = buildings (bit 64)
	collision_layer = 64
	collision_mask = 0  # Don't detect anything, just be detectable

	# Add to group for queries
	add_to_group("construction_sites")

	# Create collision shape
	_setup_collision()

	# Create visuals
	_setup_visuals()

	# Apply building rotation to the entire construction site
	# This ensures the preview footprint matches the final building orientation
	if building_rotation != 0.0:
		rotation.y = building_rotation

	# Snap to terrain
	_snap_to_terrain()


func _setup_collision() -> void:
	collision_shape = CollisionShape3D.new()
	box_shape = BoxShape3D.new()
	box_shape.size = Vector3(footprint_size.x, 2.0, footprint_size.y)
	collision_shape.shape = box_shape
	collision_shape.position.y = 1.0
	add_child(collision_shape)


func _setup_visuals() -> void:
	# Foundation material (dirt/gravel)
	_foundation_material = StandardMaterial3D.new()
	_foundation_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_foundation_material.albedo_color = Color(0.5, 0.4, 0.3, 0.6)
	_foundation_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_foundation_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Create foundation (flat rectangle)
	foundation_mesh = MeshInstance3D.new()
	foundation_mesh.mesh = _create_foundation_mesh()
	foundation_mesh.material_override = _foundation_material
	foundation_mesh.position.y = 0.05
	add_child(foundation_mesh)

	# Scaffolding material (wood color)
	_scaffolding_material = StandardMaterial3D.new()
	_scaffolding_material.albedo_color = Color(0.6, 0.45, 0.3)
	_scaffolding_material.metallic = 0.0
	_scaffolding_material.roughness = 0.9

	# Create scaffolding (starts invisible, grows with progress)
	scaffolding_mesh = MeshInstance3D.new()
	scaffolding_mesh.mesh = _create_scaffolding_mesh(0.0)
	scaffolding_mesh.material_override = _scaffolding_material
	scaffolding_mesh.visible = false
	add_child(scaffolding_mesh)

	# Outline material (green dashed line effect)
	_outline_material = StandardMaterial3D.new()
	_outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_material.albedo_color = Color(0.2, 0.8, 0.2, 0.7)
	_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Create outline rectangle
	outline_mesh = MeshInstance3D.new()
	outline_mesh.mesh = _create_outline_mesh()
	outline_mesh.material_override = _outline_material
	outline_mesh.position.y = 0.1
	add_child(outline_mesh)

	# Create world-space progress bar (billboard)
	_setup_progress_bar()

	# Create corner stakes for clear boundary visualization (alpha polish)
	_setup_corner_stakes()


func _snap_to_terrain() -> void:
	"""Snap construction site to terrain, sampling multiple points to prevent clipping"""
	var terrain: Node = get_node_or_null("/root/UnifiedTerrain")
	if not terrain or not terrain.has_method("get_height_at"):
		terrain = get_node_or_null("/root/TerrainIntegration")

	if not terrain or not terrain.has_method("get_height_at"):
		return

	# Sample 5 points: center + 4 corners
	var hx: float = footprint_size.x * 0.5
	var hz: float = footprint_size.y * 0.5
	var center: Vector3 = global_position

	var sample_points: Array[Vector2] = [
		Vector2(0, 0),  # Center
		Vector2(-hx, -hz),  # Bottom-left
		Vector2(hx, -hz),   # Bottom-right
		Vector2(hx, hz),    # Top-right
		Vector2(-hx, hz),   # Top-left
	]

	var max_height: float = -1000.0
	for offset in sample_points:
		var sample_pos := Vector3(center.x + offset.x, 0, center.z + offset.y)
		var height: float = terrain.get_height_at(sample_pos)
		if height > max_height:
			max_height = height

	# Add small offset to ensure building is above terrain
	position.y = max_height + 0.05


func _setup_progress_bar() -> void:
	"""Create world-space progress bar above construction site"""
	# Container for billboard behavior
	progress_bar = Node3D.new()
	progress_bar.name = "ProgressBar"
	progress_bar.position.y = PROGRESS_BAR_Y_OFFSET
	add_child(progress_bar)

	# Background (dark gray)
	_progress_bg_material = StandardMaterial3D.new()
	_progress_bg_material.albedo_color = Color(0.2, 0.2, 0.2, 0.8)
	_progress_bg_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_progress_bg_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_progress_bg_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED

	_progress_bg_mesh = MeshInstance3D.new()
	var bg_quad := QuadMesh.new()
	bg_quad.size = Vector2(PROGRESS_BAR_WIDTH + 0.1, PROGRESS_BAR_HEIGHT + 0.05)
	_progress_bg_mesh.mesh = bg_quad
	_progress_bg_mesh.material_override = _progress_bg_material
	progress_bar.add_child(_progress_bg_mesh)

	# Fill bar (green, scales with progress)
	_progress_fill_material = StandardMaterial3D.new()
	_progress_fill_material.albedo_color = Color(0.2, 0.8, 0.2, 0.9)
	_progress_fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_progress_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_progress_fill_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED

	_progress_fill_mesh = MeshInstance3D.new()
	var fill_quad := QuadMesh.new()
	fill_quad.size = Vector2(0.01, PROGRESS_BAR_HEIGHT)  # Start tiny
	_progress_fill_mesh.mesh = fill_quad
	_progress_fill_mesh.material_override = _progress_fill_material
	_progress_fill_mesh.position.z = -0.01  # Slightly in front of background
	progress_bar.add_child(_progress_fill_mesh)

	# Hide until work starts
	progress_bar.visible = false


func _setup_corner_stakes() -> void:
	"""Create wooden stake markers at each corner of the construction site"""
	# Stake material (bright orange/yellow for visibility)
	_stake_material = StandardMaterial3D.new()
	_stake_material.albedo_color = Color(0.9, 0.6, 0.1)  # Orange-yellow
	_stake_material.metallic = 0.0
	_stake_material.roughness = 0.8

	var hx: float = footprint_size.x * 0.5
	var hz: float = footprint_size.y * 0.5
	var stake_height: float = 1.2  # Tall enough to see
	var stake_radius: float = 0.06

	# Corner positions
	var corners: Array[Vector2] = [
		Vector2(-hx, -hz),
		Vector2(hx, -hz),
		Vector2(hx, hz),
		Vector2(-hx, hz)
	]

	# Create stake mesh (tapered cylinder)
	var stake_mesh := CylinderMesh.new()
	stake_mesh.top_radius = stake_radius * 0.3  # Pointed top
	stake_mesh.bottom_radius = stake_radius
	stake_mesh.height = stake_height

	for corner in corners:
		var stake := MeshInstance3D.new()
		stake.mesh = stake_mesh
		stake.material_override = _stake_material
		stake.position = Vector3(corner.x, stake_height * 0.5, corner.y)
		add_child(stake)
		corner_stakes.append(stake)


func _update_progress_bar() -> void:
	"""Update progress bar fill width"""
	if not is_instance_valid(_progress_fill_mesh):
		return

	# Show progress bar once work starts
	if current_progress > 0.0 and progress_bar:
		progress_bar.visible = true

	# Scale fill based on progress
	var fill_width: float = PROGRESS_BAR_WIDTH * current_progress
	if fill_width < 0.01:
		fill_width = 0.01

	var fill_quad := _progress_fill_mesh.mesh as QuadMesh
	if fill_quad:
		fill_quad.size = Vector2(fill_width, PROGRESS_BAR_HEIGHT)

	# Offset to left-align the fill bar
	_progress_fill_mesh.position.x = (fill_width - PROGRESS_BAR_WIDTH) * 0.5

	# Color transition: green -> yellow -> full green
	var color: Color
	if current_progress < 0.5:
		color = Color(0.2 + current_progress * 0.6, 0.8, 0.2, 0.9)  # Green to yellow-green
	else:
		color = Color(0.8 - (current_progress - 0.5) * 0.6, 0.8, 0.2, 0.9)  # Yellow-green back to green
	_progress_fill_material.albedo_color = color


## Add work progress (called by workers via JobSystem)
## Returns true if construction is complete
func add_work(amount: float) -> bool:
	if not is_constructing:
		is_constructing = true
		construction_started.emit()

	var new_progress: float = minf(current_progress + amount, 1.0)

	if new_progress != current_progress:
		current_progress = new_progress
		_update_visuals()
		construction_progress.emit(current_progress)

	if current_progress >= 1.0:
		_complete()
		return true

	return false


func _update_visuals() -> void:
	# Update foundation color (gets darker as work progresses)
	_foundation_material.albedo_color = Color(
		lerpf(0.5, 0.3, current_progress),
		lerpf(0.4, 0.25, current_progress),
		lerpf(0.3, 0.2, current_progress),
		lerpf(0.6, 0.8, current_progress)
	)

	# Show scaffolding after 10% progress
	if current_progress > 0.1:
		scaffolding_mesh.visible = true
		scaffolding_mesh.mesh = _create_scaffolding_mesh(current_progress)

	# Update progress bar
	_update_progress_bar()


func _complete() -> void:
	is_constructing = false

	# Change outline to show completion
	_outline_material.albedo_color = Color(0.5, 0.8, 0.5, 0.5)

	# Spawn the actual building
	var building: Node3D = _spawn_building()

	construction_complete.emit(building)

	# CRITICAL: Emit BattleSignals for systems like SupplyChainManager
	if BattleSignals:
		BattleSignals.construction_complete.emit(building)

	print("[ConstructionSite] Complete! Building type %d at %s" % [building_type, global_position])

	# Queue self for removal (building replaces us)
	queue_free()


func _spawn_building() -> Node3D:
	## Spawn the actual building scene
	var construction_mgr: Node = get_node_or_null("/root/ConstructionManager")
	if construction_mgr and construction_mgr.has_method("spawn_building_at"):
		return construction_mgr.spawn_building_at(global_position, building_type, building_rotation)

	# Fallback: create a placeholder
	var placeholder := MeshInstance3D.new()
	placeholder.mesh = BoxMesh.new()
	(placeholder.mesh as BoxMesh).size = Vector3(footprint_size.x, 3.0, footprint_size.y)
	placeholder.position = global_position
	placeholder.position.y += 1.5
	get_parent().add_child(placeholder)
	return placeholder


## Get progress as 0.0 - 1.0
func get_progress() -> float:
	return current_progress


## Cancel construction and clean up
func cancel() -> void:
	is_constructing = false

	# Visual feedback - turn outline red briefly
	if _outline_material:
		_outline_material.albedo_color = Color(0.8, 0.3, 0.3, 0.5)

	construction_cancelled.emit()
	print("[ConstructionSite] Cancelled at %.0f%% progress" % (current_progress * 100))

	# Queue for removal
	queue_free()


## Create foundation mesh (flat rectangle)
func _create_foundation_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hx: float = footprint_size.x * 0.5
	var hz: float = footprint_size.y * 0.5

	# Two triangles for rectangle
	st.add_vertex(Vector3(-hx, 0, -hz))
	st.add_vertex(Vector3(hx, 0, -hz))
	st.add_vertex(Vector3(hx, 0, hz))

	st.add_vertex(Vector3(-hx, 0, -hz))
	st.add_vertex(Vector3(hx, 0, hz))
	st.add_vertex(Vector3(-hx, 0, hz))

	return st.commit()


## Create scaffolding mesh based on progress
func _create_scaffolding_mesh(progress: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hx: float = footprint_size.x * 0.5 - 0.2
	var hz: float = footprint_size.y * 0.5 - 0.2
	var height: float = 3.0 * progress  # Max 3m height
	var pole_radius: float = 0.08

	if height < 0.1:
		height = 0.1

	# Four corner poles
	var corners: Array[Vector2] = [
		Vector2(-hx, -hz),
		Vector2(hx, -hz),
		Vector2(hx, hz),
		Vector2(-hx, hz)
	]

	for corner in corners:
		_add_pole(st, Vector3(corner.x, 0, corner.y), height, pole_radius)

	# Cross bracing at intervals
	var brace_count: int = int(progress * 3) + 1
	var brace_spacing: float = height / float(brace_count)

	for i in range(brace_count):
		var y: float = (i + 0.5) * brace_spacing
		if y < height:
			# Horizontal braces
			_add_horizontal_brace(st, Vector3(-hx, y, -hz), Vector3(hx, y, -hz), pole_radius * 0.7)
			_add_horizontal_brace(st, Vector3(-hx, y, hz), Vector3(hx, y, hz), pole_radius * 0.7)
			_add_horizontal_brace(st, Vector3(-hx, y, -hz), Vector3(-hx, y, hz), pole_radius * 0.7)
			_add_horizontal_brace(st, Vector3(hx, y, -hz), Vector3(hx, y, hz), pole_radius * 0.7)

	st.generate_normals()
	return st.commit()


func _add_pole(st: SurfaceTool, base: Vector3, height: float, radius: float) -> void:
	## Add a vertical pole (simple rectangular prism)
	var top := base + Vector3(0, height, 0)

	# Front face
	st.add_vertex(base + Vector3(-radius, 0, -radius))
	st.add_vertex(base + Vector3(radius, 0, -radius))
	st.add_vertex(top + Vector3(radius, 0, -radius))
	st.add_vertex(base + Vector3(-radius, 0, -radius))
	st.add_vertex(top + Vector3(radius, 0, -radius))
	st.add_vertex(top + Vector3(-radius, 0, -radius))

	# Back face
	st.add_vertex(base + Vector3(radius, 0, radius))
	st.add_vertex(base + Vector3(-radius, 0, radius))
	st.add_vertex(top + Vector3(-radius, 0, radius))
	st.add_vertex(base + Vector3(radius, 0, radius))
	st.add_vertex(top + Vector3(-radius, 0, radius))
	st.add_vertex(top + Vector3(radius, 0, radius))

	# Left face
	st.add_vertex(base + Vector3(-radius, 0, radius))
	st.add_vertex(base + Vector3(-radius, 0, -radius))
	st.add_vertex(top + Vector3(-radius, 0, -radius))
	st.add_vertex(base + Vector3(-radius, 0, radius))
	st.add_vertex(top + Vector3(-radius, 0, -radius))
	st.add_vertex(top + Vector3(-radius, 0, radius))

	# Right face
	st.add_vertex(base + Vector3(radius, 0, -radius))
	st.add_vertex(base + Vector3(radius, 0, radius))
	st.add_vertex(top + Vector3(radius, 0, radius))
	st.add_vertex(base + Vector3(radius, 0, -radius))
	st.add_vertex(top + Vector3(radius, 0, radius))
	st.add_vertex(top + Vector3(radius, 0, -radius))


func _add_horizontal_brace(st: SurfaceTool, from: Vector3, to: Vector3, radius: float) -> void:
	## Add a horizontal brace between two points
	var dir: Vector3 = (to - from).normalized()
	var perp := Vector3(-dir.z, 0, dir.x) * radius
	var up := Vector3(0, radius, 0)

	# Top face
	st.add_vertex(from + up - perp)
	st.add_vertex(from + up + perp)
	st.add_vertex(to + up + perp)
	st.add_vertex(from + up - perp)
	st.add_vertex(to + up + perp)
	st.add_vertex(to + up - perp)

	# Bottom face
	st.add_vertex(from - up + perp)
	st.add_vertex(from - up - perp)
	st.add_vertex(to - up - perp)
	st.add_vertex(from - up + perp)
	st.add_vertex(to - up - perp)
	st.add_vertex(to - up + perp)


## Create outline mesh (rectangle lines)
func _create_outline_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var hx: float = footprint_size.x * 0.5
	var hz: float = footprint_size.y * 0.5

	# Four sides
	st.add_vertex(Vector3(-hx, 0, -hz))
	st.add_vertex(Vector3(hx, 0, -hz))

	st.add_vertex(Vector3(hx, 0, -hz))
	st.add_vertex(Vector3(hx, 0, hz))

	st.add_vertex(Vector3(hx, 0, hz))
	st.add_vertex(Vector3(-hx, 0, hz))

	st.add_vertex(Vector3(-hx, 0, hz))
	st.add_vertex(Vector3(-hx, 0, -hz))

	return st.commit()


## Factory: Create a construction site at a position
static func create(world_position: Vector3, type: int, rotation: float = 0.0, size: Vector2 = Vector2(4.0, 4.0)) -> Node:
	var site := new()
	site.position = world_position
	site.building_type = type
	site.building_rotation = rotation
	site.footprint_size = size
	return site
