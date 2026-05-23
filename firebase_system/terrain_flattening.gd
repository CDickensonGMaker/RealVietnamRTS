extends Node
## TerrainFlatteningSystem - Autoload singleton for terrain flattening
##
## Handles the visual progression of FLATTEN_AREA jobs. As work progresses,
## terrain actually levels toward the target height using the heightmap system.
##
## This properly modifies the terrain heightmap like the original TerrainEngine.

signal flattening_started(position: Vector3, size: Vector2)
signal flattening_progress(position: Vector3, progress: float)
signal flattening_completed(position: Vector3)

const UnifiedJob = preload("res://firebase_system/job_system/unified_job.gd")

## Active flattening operations
var _operations: Dictionary = {}  # key -> FlatteningOperation

## Configuration
const GRID_RESOLUTION := 2.0  # Meters per height sample


class FlatteningOperation:
	var center: Vector3
	var size: Vector2
	var target_height: float
	var progress: float = 0.0
	var original_heights: Dictionary = {}  # Vector2i -> float (cell coords)
	var cell_bounds: Rect2i = Rect2i()


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

	# Sample and store original heights
	_sample_original_heights(op)

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
	var old_progress: float = op.progress
	op.progress = clampf(progress, 0.0, 1.0)

	# Only modify terrain if progress changed significantly
	if absf(op.progress - old_progress) > 0.01:
		_apply_terrain_modification(op)

	flattening_progress.emit(position, op.progress)

	if op.progress >= 1.0:
		_complete_operation(op, key)


## Set progress for a flattening job
func set_job_progress(job: UnifiedJob) -> void:
	if job.job_type != UnifiedJob.Type.FLATTEN_AREA:
		return

	var center: Vector3 = job.get_centroid()
	var size: Vector2 = Vector2(job.world_bounds.size.x, job.world_bounds.size.z)

	# Ensure operation exists
	var key: String = _make_key(center)
	if not _operations.has(key):
		start_flattening(center, size)

	var progress: float = job.work_progress / job.work_required if job.work_required > 0 else 0.0
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


func _get_terrain_system() -> Node:
	"""Get terrain system with fallback to scene-local terrain via group"""
	# Try TerrainIntegration autoload first
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain:
		# Check if it has a working terrain_manager
		if "terrain_manager" in terrain and terrain.terrain_manager:
			if terrain.terrain_manager.has_method("get_height_at"):
				return terrain.terrain_manager

	# Fallback: find any terrain manager in scene tree via group
	for node in get_tree().get_nodes_in_group("terrain_managers"):
		if node.has_method("get_height_at"):
			print("[TerrainFlattening] Using scene-local terrain: %s" % node.name)
			return node

	return null


func _calculate_target_height(position: Vector3, size: Vector2) -> float:
	"""Calculate target height by finding the largest flat area nearby.
	This ensures flattened areas connect cohesively with surroundings."""
	var terrain := _get_terrain_system()
	if not terrain:
		print("[TerrainFlattening] WARNING: No terrain system found, using position.y")
		return position.y

	# Sample heights in a larger search area (2x the flattening size)
	var search_radius := maxf(size.x, size.y)
	var step := GRID_RESOLUTION
	var height_counts: Dictionary = {}  # height_bucket -> count
	var bucket_size := 0.5  # 0.5m height buckets for grouping similar heights

	# Sample terrain heights in surrounding area
	var x := -search_radius
	while x <= search_radius:
		var z := -search_radius
		while z <= search_radius:
			var h: float = terrain.get_height_at(position + Vector3(x, 0, z))
			var bucket: int = int(h / bucket_size)
			height_counts[bucket] = height_counts.get(bucket, 0) + 1
			z += step
		x += step

	# Find the most common height (largest flat area)
	var best_bucket: int = 0
	var best_count: int = 0
	for bucket in height_counts:
		if height_counts[bucket] > best_count:
			best_count = height_counts[bucket]
			best_bucket = bucket

	# Check neighboring buckets (allow +/- 1 bucket for gentle slopes)
	# Use lowest of the common heights (prefer filling up, not cutting down)
	var target_bucket: int = best_bucket
	if height_counts.get(best_bucket - 1, 0) > height_counts.get(best_bucket, 0) / 2:
		target_bucket = best_bucket - 1  # Use lower bucket if significant presence

	var target_height := target_bucket * bucket_size + bucket_size * 0.5  # Center of bucket
	print("[TerrainFlattening] Target height %.2f (bucket %d, count %d)" % [
		target_height, target_bucket, best_count
	])
	return target_height


func _sample_original_heights(op: FlatteningOperation) -> void:
	"""Sample and store original terrain heights for the operation area"""
	var terrain := _get_terrain_system()
	if not terrain:
		return

	var half_x := op.size.x * 0.5
	var half_z := op.size.y * 0.5

	# Get heightmap reference for cell coordinate conversion
	var heightmap = null
	if "heightmap" in terrain:
		heightmap = terrain.heightmap
	elif terrain.has_method("get_heightmap"):
		heightmap = terrain.get_heightmap()

	# Sample heights at regular intervals and store original values
	var x := -half_x
	while x <= half_x:
		var z := -half_z
		while z <= half_z:
			var world_pos := op.center + Vector3(x, 0, z)
			var height: float = terrain.get_height_at(world_pos)

			# Convert to cell coordinates for storage
			var cell_key := Vector2i(int(world_pos.x), int(world_pos.z))
			op.original_heights[cell_key] = height

			z += GRID_RESOLUTION
		x += GRID_RESOLUTION


func _apply_terrain_modification(op: FlatteningOperation) -> void:
	"""Actually modify the terrain heightmap based on progress"""
	var terrain := _get_terrain_system()
	if not terrain or not terrain.has_method("modify_terrain"):
		# Fallback for terrain systems without modify_terrain
		return

	var radius := maxf(op.size.x, op.size.y) * 0.5

	# Create a modifier that lerps toward target height based on progress
	var target_h: float = op.target_height
	var progress: float = op.progress
	var original_heights: Dictionary = op.original_heights
	var center: Vector3 = op.center

	# The modifier receives (current_height, falloff) and returns new height
	var modifier := func(current_h: float, falloff: float) -> float:
		# Get world position from the iteration context
		# Since we're called per-cell, we interpolate toward target based on progress
		var new_h: float = lerpf(current_h, target_h, progress * falloff)
		return new_h

	terrain.modify_terrain(op.center, radius, modifier)


func _complete_operation(op: FlatteningOperation, key: String) -> void:
	"""Mark operation as complete"""
	flattening_completed.emit(op.center)

	# Final terrain pass at 100% progress
	_apply_terrain_modification(op)

	print("[TerrainFlatteningSystem] Completed flattening at %s" % op.center)

	# Clean up after a short delay
	await get_tree().create_timer(1.0).timeout

	if _operations.has(key):
		_operations.erase(key)


## Cleanup all operations
func clear_all() -> void:
	_operations.clear()
