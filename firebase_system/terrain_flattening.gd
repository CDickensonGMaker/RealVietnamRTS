extends Node
## TerrainFlatteningSystem - Autoload singleton for terrain flattening visuals
##
## Handles the visual progression of FLATTEN_AREA jobs. As work progresses,
## terrain visually levels toward the target height.
##
## Since modifying actual terrain heightmaps is complex and potentially
## expensive, this uses a flat decal mesh overlay approach as a fallback.

signal flattening_started(position: Vector3, size: Vector2)
signal flattening_progress(position: Vector3, progress: float)
signal flattening_completed(position: Vector3)

const JobTypes = preload("res://firebase_system/jobs/job_types.gd")
const JobNode = preload("res://firebase_system/jobs/job_node.gd")

## Active flattening operations
var _operations: Dictionary = {}  # key -> FlatteningOperation

## Configuration
const GRID_RESOLUTION := 2.0  # Meters per vertex for decal mesh


class FlatteningOperation:
	var center: Vector3
	var size: Vector2
	var target_height: float
	var progress: float = 0.0
	var decal_mesh: MeshInstance3D = null
	var original_heights: Array[float] = []
	var grid_width: int = 0
	var grid_depth: int = 0


func _ready() -> void:
	print("[TerrainFlatteningSystem] Initialized")


## Start a flattening operation at position with given size
func start_flattening(position: Vector3, size: Vector2) -> FlatteningOperation:
	var key: String = _make_key(position)

	if _operations.has(key):
		return _operations[key]

	var op := FlatteningOperation.new()
	op.center = position
	op.size = size
	op.target_height = _calculate_target_height(position, size)
	op.progress = 0.0

	# Sample original heights
	_sample_heights(op)

	# Create decal mesh
	_create_decal_mesh(op)

	_operations[key] = op

	flattening_started.emit(position, size)
	print("[TerrainFlatteningSystem] Started flattening at %s (target height: %.2f)" % [
		position, op.target_height
	])

	return op


## Set progress for a flattening operation (0.0 to 1.0)
func set_progress(position: Vector3, progress: float) -> void:
	var key: String = _make_key(position)

	if not _operations.has(key):
		return

	var op: FlatteningOperation = _operations[key]
	op.progress = clampf(progress, 0.0, 1.0)

	_update_decal_mesh(op)
	flattening_progress.emit(position, op.progress)

	if op.progress >= 1.0:
		_complete_operation(op, key)


## Set progress for a flattening job node
func set_job_progress(job: JobNode) -> void:
	if job.job_type != JobTypes.JobType.FLATTEN_AREA:
		return

	var center: Vector3 = job.area_bounds.get_center()
	var size := Vector2(job.area_bounds.size.x, job.area_bounds.size.z)

	# Ensure operation exists
	var key: String = _make_key(center)
	if not _operations.has(key):
		start_flattening(center, size)

	var progress: float = job.current_progress / job.total_work
	set_progress(center, progress)


## Get current progress for a position
func get_progress(position: Vector3) -> float:
	var key: String = _make_key(position)
	if _operations.has(key):
		return _operations[key].progress
	return 0.0


## Check if position is being flattened
func is_flattening(position: Vector3) -> bool:
	var key: String = _make_key(position)
	return _operations.has(key)


## Internal methods

func _make_key(position: Vector3) -> String:
	return "%d_%d" % [int(position.x), int(position.z)]


func _calculate_target_height(position: Vector3, size: Vector2) -> float:
	"""Calculate target height - average of terrain in area"""
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if not terrain or not terrain.has_method("get_height_at"):
		return position.y

	var total_height := 0.0
	var sample_count := 0

	var half_x := size.x * 0.5
	var half_z := size.y * 0.5
	var step := GRID_RESOLUTION

	var x := -half_x
	while x <= half_x:
		var z := -half_z
		while z <= half_z:
			total_height += terrain.get_height_at(position + Vector3(x, 0, z))
			sample_count += 1
			z += step
		x += step

	return total_height / float(sample_count) if sample_count > 0 else position.y


func _sample_heights(op: FlatteningOperation) -> void:
	"""Sample original terrain heights for the operation area"""
	var terrain := get_node_or_null("/root/TerrainIntegration")

	op.grid_width = int(ceil(op.size.x / GRID_RESOLUTION)) + 1
	op.grid_depth = int(ceil(op.size.y / GRID_RESOLUTION)) + 1
	op.original_heights.clear()

	var half_x := op.size.x * 0.5
	var half_z := op.size.y * 0.5

	for i in range(op.grid_width):
		for j in range(op.grid_depth):
			var local_x: float = -half_x + i * GRID_RESOLUTION
			var local_z: float = -half_z + j * GRID_RESOLUTION
			var world_pos := op.center + Vector3(local_x, 0, local_z)

			var height: float = op.target_height
			if terrain and terrain.has_method("get_height_at"):
				height = terrain.get_height_at(world_pos)

			op.original_heights.append(height)


func _create_decal_mesh(op: FlatteningOperation) -> void:
	"""Create the flattening progress decal mesh"""
	op.decal_mesh = MeshInstance3D.new()
	op.decal_mesh.name = "FlatteningDecal"

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.5, 0.4, 0.3, 0.7)  # Brown dirt
	op.decal_mesh.material_override = mat

	get_tree().current_scene.add_child(op.decal_mesh)

	_update_decal_mesh(op)


func _update_decal_mesh(op: FlatteningOperation) -> void:
	"""Update the decal mesh to show current flattening progress"""
	if not op.decal_mesh:
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_x := op.size.x * 0.5
	var half_z := op.size.y * 0.5

	# Color gradient: more flattened = more opaque/visible
	var base_color := Color(0.5, 0.4, 0.3)
	var alpha: float = 0.3 + op.progress * 0.5

	for i in range(op.grid_width - 1):
		for j in range(op.grid_depth - 1):
			var local_x := -half_x + i * GRID_RESOLUTION
			var local_z := -half_z + j * GRID_RESOLUTION

			# Get interpolated heights based on progress
			var idx00 := i * op.grid_depth + j
			var idx10 := (i + 1) * op.grid_depth + j
			var idx01 := i * op.grid_depth + (j + 1)
			var idx11 := (i + 1) * op.grid_depth + (j + 1)

			var h00 := lerpf(op.original_heights[idx00], op.target_height, op.progress)
			var h10 := lerpf(op.original_heights[idx10], op.target_height, op.progress)
			var h01 := lerpf(op.original_heights[idx01], op.target_height, op.progress)
			var h11 := lerpf(op.original_heights[idx11], op.target_height, op.progress)

			var v00 := op.center + Vector3(local_x, h00 + 0.05, local_z)
			var v10 := op.center + Vector3(local_x + GRID_RESOLUTION, h10 + 0.05, local_z)
			var v01 := op.center + Vector3(local_x, h01 + 0.05, local_z + GRID_RESOLUTION)
			var v11 := op.center + Vector3(local_x + GRID_RESOLUTION, h11 + 0.05, local_z + GRID_RESOLUTION)

			# Set color with alpha
			var color := base_color
			color.a = alpha
			st.set_color(color)
			st.set_normal(Vector3.UP)

			# Triangle 1
			st.add_vertex(v00)
			st.add_vertex(v10)
			st.add_vertex(v11)

			# Triangle 2
			st.add_vertex(v00)
			st.add_vertex(v11)
			st.add_vertex(v01)

	op.decal_mesh.mesh = st.commit()


func _complete_operation(op: FlatteningOperation, key: String) -> void:
	"""Mark operation as complete"""
	flattening_completed.emit(op.center)

	# Keep decal mesh visible as final flattened surface
	# In a real implementation, you might want to fade it out

	# Remove from active operations after a delay
	await get_tree().create_timer(2.0).timeout

	if _operations.has(key):
		var completed_op: FlatteningOperation = _operations[key]
		if completed_op.decal_mesh:
			completed_op.decal_mesh.queue_free()
		_operations.erase(key)


## Cleanup all operations
func clear_all() -> void:
	for key in _operations:
		var op: FlatteningOperation = _operations[key]
		if op.decal_mesh:
			op.decal_mesh.queue_free()
	_operations.clear()
