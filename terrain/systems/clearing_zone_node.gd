class_name ClearingZoneNode
extends Area3D
## ClearingZoneNode - An expanding area that clears vegetation
##
## When a worker performs clearing work, this zone expands outward.
## Trees that overlap the zone are automatically cleared.
## This uses Godot's built-in collision detection instead of grid checks.

const WorkProgressBarClass = preload("res://battle_system/ui/work_progress_bar.gd")

signal clearing_started()
signal clearing_progress(progress: float)
signal clearing_complete()

## Target radius / footprint of the clearing area (in meters)
@export var target_radius: float = 10.0

## Whether clearing is active (progress > 0)
var is_clearing: bool = false

## Clearing progress 0..1, driven externally by worker tree-felling (felled / total).
var _progress: float = 0.0

## Visual components
var ground_decal: MeshInstance3D
var outline_mesh: MeshInstance3D
var progress_bar: Node3D  # WorkProgressBar
var edge_glow_mesh: MeshInstance3D  # Alpha polish: glowing edge ring

## Material for ground decal
var _decal_material: StandardMaterial3D
var _edge_glow_material: StandardMaterial3D

## Animation state for edge glow
var _glow_time: float = 0.0
var _glow_pulse_speed: float = 3.0  # Pulses per second

## Track if edge glow mesh was already created (avoid per-frame recreation)
var _edge_glow_mesh_created: bool = false


func _ready() -> void:
	# Passive footprint marker. Trees are felled by workers walking to them, not by an
	# expanding collision cylinder, so this zone no longer detects or clears vegetation.
	collision_layer = 0
	collision_mask = 0

	# Add to group so other systems can still locate clearing areas
	add_to_group("clearing_zones")

	# Create visuals (static decal sized to the full footprint)
	_setup_visuals()

	# Snap to terrain
	_snap_to_terrain()


func _setup_visuals() -> void:
	# Ground decal showing cleared area
	_decal_material = StandardMaterial3D.new()
	_decal_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_decal_material.albedo_color = Color(0.6, 0.4, 0.2, 0.4)  # Brown, semi-transparent
	_decal_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_decal_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	ground_decal = MeshInstance3D.new()
	ground_decal.mesh = _create_square_mesh(target_radius)  # Full footprint, static (square)
	ground_decal.material_override = _decal_material
	ground_decal.position.y = 0.1  # Just above terrain
	add_child(ground_decal)

	# Outline showing target area
	var outline_material := StandardMaterial3D.new()
	outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline_material.albedo_color = Color(0.2, 0.8, 0.2, 0.5)  # Green outline
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	outline_mesh = MeshInstance3D.new()
	outline_mesh.mesh = _create_square_outline_mesh(target_radius)
	outline_mesh.material_override = outline_material
	outline_mesh.position.y = 0.15
	add_child(outline_mesh)

	# Progress bar floating above the zone (higher for visibility from camera)
	progress_bar = WorkProgressBarClass.create_for_node(self, 8.0)
	if progress_bar:
		progress_bar.set_progress(0.0)
	else:
		push_warning("[ClearingZone] Failed to create progress bar")

	# Edge glow ring - shows active clearing boundary (alpha polish)
	_edge_glow_material = StandardMaterial3D.new()
	_edge_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_edge_glow_material.albedo_color = Color(1.0, 0.6, 0.1, 0.8)  # Orange glow
	_edge_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_edge_glow_material.no_depth_test = true
	_edge_glow_material.render_priority = 10

	edge_glow_mesh = MeshInstance3D.new()
	edge_glow_mesh.material_override = _edge_glow_material
	edge_glow_mesh.position.y = 0.2
	edge_glow_mesh.visible = false  # Hidden until clearing starts
	add_child(edge_glow_mesh)

	print("[ClearingZone] Progress bar and edge glow created")


func _snap_to_terrain() -> void:
	var terrain = get_node_or_null("/root/UnifiedTerrain")
	if terrain and terrain.has_method("get_height_at"):
		position.y = terrain.get_height_at(global_position)
		return

	var terrain_intg = get_node_or_null("/root/TerrainIntegration")
	if terrain_intg and terrain_intg.has_method("get_height_at"):
		position.y = terrain_intg.get_height_at(global_position)


func _process(delta: float) -> void:
	# Animate edge glow pulse during active clearing
	if is_clearing and edge_glow_mesh and edge_glow_mesh.visible:
		_glow_time += delta * _glow_pulse_speed
		var pulse := (sin(_glow_time * TAU) + 1.0) * 0.5  # 0.0 to 1.0
		var alpha := lerpf(0.4, 0.9, pulse)
		var brightness := lerpf(0.8, 1.2, pulse)
		_edge_glow_material.albedo_color = Color(
			minf(1.0, 0.9 * brightness),
			minf(1.0, 0.5 * brightness),
			0.1,
			alpha
		)


## Set clearing progress directly (0..1). Driven by worker tree-felling (felled / total).
func set_progress(p: float) -> void:
	var new_progress := clampf(p, 0.0, 1.0)
	if new_progress == _progress:
		return
	_progress = new_progress

	if not is_clearing and _progress > 0.0:
		is_clearing = true
		clearing_started.emit()

	if progress_bar and progress_bar.has_method("set_progress"):
		progress_bar.set_progress(_progress)

	# Edge glow ring pulses around the footprint while clearing is underway
	if edge_glow_mesh:
		edge_glow_mesh.visible = _progress > 0.0 and _progress < 1.0
		# Only create mesh once, not every frame (avoids per-frame allocation)
		if edge_glow_mesh.visible and not _edge_glow_mesh_created:
			edge_glow_mesh.mesh = _create_square_ring_mesh(target_radius, 0.3)
			_edge_glow_mesh_created = true

	clearing_progress.emit(_progress)

	if _progress >= 1.0:
		_complete()


## Legacy entry point (still called by ConstructionManager / TreeNodeManager helpers).
## Now just advances the progress indicator - no radius expansion, no tree removal.
## Returns true when complete.
func add_work(amount: float) -> bool:
	var frac: float = amount
	if frac > 1.0:
		frac = frac / 100.0  # Convert 0-100 scale to 0-1
	set_progress(_progress + frac)
	return _progress >= 1.0


func _complete() -> void:
	is_clearing = false
	clearing_complete.emit()

	# Change outline to show completion
	var mat := outline_mesh.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(0.5, 0.5, 0.5, 0.3)  # Gray, faded

	# Hide edge glow - clearing is done
	if edge_glow_mesh:
		edge_glow_mesh.visible = false

	print("[ClearingZone] Footprint cleared (%.1fm)" % target_radius)


## Get progress as 0.0 - 1.0
func get_progress() -> float:
	return _progress


## Create a filled square mesh for the ground decal
func _create_square_mesh(half_size: float) -> ArrayMesh:
	if half_size < 0.01:
		half_size = 0.01

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Two triangles forming a square
	st.add_vertex(Vector3(-half_size, 0, -half_size))
	st.add_vertex(Vector3(half_size, 0, -half_size))
	st.add_vertex(Vector3(half_size, 0, half_size))

	st.add_vertex(Vector3(-half_size, 0, -half_size))
	st.add_vertex(Vector3(half_size, 0, half_size))
	st.add_vertex(Vector3(-half_size, 0, half_size))

	return st.commit()


## Create a square outline mesh
func _create_square_outline_mesh(half_size: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var corners := [
		Vector3(-half_size, 0, -half_size),
		Vector3(half_size, 0, -half_size),
		Vector3(half_size, 0, half_size),
		Vector3(-half_size, 0, half_size),
	]

	for i in range(4):
		st.add_vertex(corners[i])
		st.add_vertex(corners[(i + 1) % 4])

	return st.commit()


## Create a square ring mesh for the edge glow effect
func _create_square_ring_mesh(half_size: float, thickness: float) -> ArrayMesh:
	if half_size < thickness:
		return _create_square_mesh(half_size)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var inner := half_size - thickness
	var outer := half_size

	# Each side of the ring = 2 triangles
	var inner_corners := [
		Vector3(-inner, 0, -inner),
		Vector3(inner, 0, -inner),
		Vector3(inner, 0, inner),
		Vector3(-inner, 0, inner),
	]
	var outer_corners := [
		Vector3(-outer, 0, -outer),
		Vector3(outer, 0, -outer),
		Vector3(outer, 0, outer),
		Vector3(-outer, 0, outer),
	]

	for i in range(4):
		var next := (i + 1) % 4
		# Triangle 1
		st.add_vertex(inner_corners[i])
		st.add_vertex(outer_corners[i])
		st.add_vertex(outer_corners[next])
		# Triangle 2
		st.add_vertex(inner_corners[i])
		st.add_vertex(outer_corners[next])
		st.add_vertex(inner_corners[next])

	return st.commit()


## Factory: Create a clearing zone at a position with a target radius
static func create(world_position: Vector3, radius: float) -> ClearingZoneNode:
	var zone := ClearingZoneNode.new()
	zone.position = world_position
	zone.target_radius = radius
	return zone
