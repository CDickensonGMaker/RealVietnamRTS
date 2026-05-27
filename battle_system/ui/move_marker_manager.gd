extends Node
class_name MoveMarkerManager

## Manages Steel Division style move destination markers
## Handles spawning, pooling, and stacking of markers

const MoveMarker = preload("res://battle_system/ui/move_marker.gd")

## Configuration
const STACK_RADIUS: float = 2.0          # Markers within this radius are considered stacked
const STACK_OFFSET_HORIZONTAL: float = 0.5  # Horizontal offset between stacked markers
const MAX_MARKERS: int = 20              # Maximum active markers before oldest are removed

## Active markers
var _active_markers: Array[Node3D] = []

## Spatial tracking for stacking
var _marker_positions: Dictionary = {}  # Vector2i (grid cell) -> Array[MoveMarker]


func _ready() -> void:
	print("[MoveMarkerManager] Initialized")


func _process(_delta: float) -> void:
	# Clean up freed markers - filter in place using indices
	var i := _active_markers.size() - 1
	while i >= 0:
		if not is_instance_valid(_active_markers[i]):
			# Remove from spatial tracking first (uses the reference before removal)
			_remove_invalid_from_spatial_tracking()
			_active_markers.remove_at(i)
		i -= 1


## Remove invalid markers from spatial tracking
func _remove_invalid_from_spatial_tracking() -> void:
	var cells_to_remove: Array = []
	for cell in _marker_positions:
		var markers: Array = _marker_positions[cell]
		# Filter to only valid markers
		var valid_markers: Array = []
		for m in markers:
			if is_instance_valid(m):
				valid_markers.append(m)
		if valid_markers.is_empty():
			cells_to_remove.append(cell)
		else:
			_marker_positions[cell] = valid_markers
	for cell in cells_to_remove:
		_marker_positions.erase(cell)


## Spawn a move marker at the target position
func spawn_marker(world_pos: Vector3, is_player: bool = true, is_attack_move: bool = false) -> MoveMarker:
	# Enforce marker limit - remove oldest if at capacity
	while _active_markers.size() >= MAX_MARKERS:
		var oldest: Node3D = _active_markers[0]
		if is_instance_valid(oldest):
			oldest.queue_free()
		_active_markers.remove_at(0)

	# Create new marker
	var marker := MoveMarker.new()
	add_child(marker)
	marker.setup(world_pos, is_player, is_attack_move)

	# Calculate stack offset
	var nearby: Array[Node3D] = _get_nearby_markers(world_pos)
	if nearby.size() > 0:
		var offset := _calculate_stack_offset(nearby.size())
		marker.set_stack_offset(offset)

	# Track the marker
	_active_markers.append(marker)
	_add_to_spatial_tracking(marker, world_pos)

	return marker


## Spawn markers for multiple units moving to formation positions
func spawn_formation_markers(positions: Array[Vector3], is_player: bool = true, is_attack_move: bool = false) -> void:
	for pos in positions:
		spawn_marker(pos, is_player, is_attack_move)


## Clear all active markers
func clear_all_markers() -> void:
	for marker in _active_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_active_markers.clear()
	_marker_positions.clear()


## Get count of active markers
func get_active_marker_count() -> int:
	return _active_markers.size()


## Convert world position to grid cell for spatial tracking
func _world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(
		floori(pos.x / STACK_RADIUS),
		floori(pos.z / STACK_RADIUS)
	)


## Add marker to spatial tracking
func _add_to_spatial_tracking(marker: Node3D, pos: Vector3) -> void:
	var cell := _world_to_cell(pos)
	if not _marker_positions.has(cell):
		_marker_positions[cell] = []
	_marker_positions[cell].append(marker)


## Remove marker from spatial tracking
func _remove_from_spatial_tracking(marker: Node3D) -> void:
	for cell in _marker_positions:
		var markers: Array = _marker_positions[cell]
		if marker in markers:
			markers.erase(marker)
			if markers.is_empty():
				_marker_positions.erase(cell)
			return


## Get markers near a position
func _get_nearby_markers(pos: Vector3) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var center_cell := _world_to_cell(pos)

	# Check surrounding cells
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var cell := Vector2i(center_cell.x + dx, center_cell.y + dz)
			if _marker_positions.has(cell):
				for marker in _marker_positions[cell]:
					if is_instance_valid(marker):
						var dist: float = pos.distance_to(marker.global_position)
						if dist < STACK_RADIUS:
							result.append(marker)

	return result


## Calculate offset for stacked markers
func _calculate_stack_offset(stack_index: int) -> Vector3:
	# Spiral pattern for stacking
	var angle: float = stack_index * 0.8  # Radians, ~45 degrees per marker
	var radius: float = STACK_OFFSET_HORIZONTAL * (1.0 + stack_index * 0.3)
	return Vector3(
		cos(angle) * radius,
		stack_index * 0.1,  # Slight vertical offset
		sin(angle) * radius
	)
