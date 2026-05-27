extends Node3D
class_name PlacementController

## PlacementController - CoH/MoW-style building placement coordinator
##
## Central coordinator that connects:
## - BuildMenu/UI → selects building type
## - BlueprintGhost → shows preview with red/green validation
## - JobSystem → validates placement and creates jobs
##
## Supports two placement modes:
## - SINGLE: Click to place a building (bunker, helipad, etc.)
## - LINEAR: Click-drag to paint segments (sandbags, wire)

const BlueprintGhost = preload("res://battle_system/ui/blueprint_ghost.gd")
const BuildingData = preload("res://firebase_system/building_data.gd")
const UnifiedJob = preload("res://firebase_system/job_system/unified_job.gd")

## Placement state machine
enum State {
	IDLE,           # No placement active
	SINGLE_PLACING, # Single building follows cursor
	LINEAR_START,   # Waiting for first click (linear placement)
	LINEAR_DRAGGING # Dragging to extend line
}

## Signals
signal placement_started(building_type: int)
signal placement_committed(building_type: int, position: Vector3)
signal placement_cancelled()
signal linear_segment_committed(building_type: int, positions: Array)
signal validation_changed(valid: bool, message: String)

## Current state
var state: State = State.IDLE
var _current_building_type: int = -1
var _current_building_data: BuildingData = null

## Ghost preview
var _ghost: Node3D = null  # BlueprintGhost instance

## Linear placement
var _linear_start_pos: Vector3 = Vector3.INF
var _linear_segment_positions: Array[Vector3] = []
var _linear_valid_segments: Array[bool] = []
var _linear_rotation_y: float = 0.0  # Rotation perpendicular to drag direction

## Bridge placement (special handling for span preview)
var _bridge_rotation_y: float = 0.0  # Rotation for bridge span direction
var _bridge_span_start: Vector3 = Vector3.ZERO
var _bridge_span_end: Vector3 = Vector3.ZERO

## Arc rotation (left-click to anchor, then mouse movement rotates facing, left-click to confirm)
var _arc_facing: float = 0.0  # Current facing direction in degrees (0 = north/+Z)
var _arc_anchored: bool = false  # True after right-click anchors position for rotation
var _arc_anchor_pos: Vector3 = Vector3.ZERO  # World position where building is anchored

## Activation frame tracking (prevents menu click from immediately committing)
var _activation_frame: int = -1

## Cursor tracking
var _cursor_world_pos: Vector3 = Vector3.ZERO
var _last_validation_result: Dictionary = {"valid": true, "error": 0, "message": ""}

## Systems
var _job_system: Node = null
var _terrain: Node = null


func _ready() -> void:
	# Get references to required systems
	_job_system = get_node_or_null("/root/JobSystem")
	_terrain = get_node_or_null("/root/TerrainIntegration")
	if not _terrain:
		_terrain = get_node_or_null("/root/UnifiedTerrain")


func _process(_delta: float) -> void:
	if state == State.IDLE:
		return

	# Update ghost position based on cursor
	if is_instance_valid(_ghost) and _cursor_world_pos != Vector3.ZERO:
		match state:
			State.SINGLE_PLACING:
				_update_single_placement()
			State.LINEAR_START:
				_update_linear_start()
			State.LINEAR_DRAGGING:
				_update_linear_dragging()


## =============================================================================
## PUBLIC API
## =============================================================================

func is_active() -> bool:
	"""Check if placement is currently active"""
	return state != State.IDLE


func get_state() -> State:
	"""Get current placement state"""
	return state


func start_placement(building_type: int, initial_cursor_pos: Vector3 = Vector3.INF) -> void:
	"""Begin placement mode for a building type.
	   Pass initial_cursor_pos to position ghost immediately (avoids origin flash)."""
	# Cancel any existing placement
	if state != State.IDLE:
		cancel_placement()

	# Get building data
	_current_building_type = building_type
	_current_building_data = BuildingData.get_building_data(building_type)
	if not _current_building_data:
		push_error("[PlacementController] Invalid building type: %d" % building_type)
		return

	# Set initial cursor position if provided (prevents ghost appearing at origin)
	# Validate that the position is reasonable (within expected map bounds)
	if initial_cursor_pos != Vector3.INF:
		# Check for NaN or extremely out-of-bounds positions
		if not is_nan(initial_cursor_pos.x) and not is_nan(initial_cursor_pos.z):
			# Reasonable bounds check (most maps are under 5000 units)
			if absf(initial_cursor_pos.x) < 10000.0 and absf(initial_cursor_pos.z) < 10000.0:
				_cursor_world_pos = initial_cursor_pos

	# Create ghost preview
	_create_ghost_for_building()

	# Position ghost immediately if we have a valid cursor position
	# Don't position at zero (likely invalid) or extreme positions
	var valid_pos: bool = _cursor_world_pos != Vector3.ZERO
	valid_pos = valid_pos and absf(_cursor_world_pos.x) < 10000.0
	valid_pos = valid_pos and absf(_cursor_world_pos.z) < 10000.0
	if is_instance_valid(_ghost) and valid_pos:
		_ghost.update_position(_cursor_world_pos)

	# Track activation frame to prevent menu click from immediately committing
	_activation_frame = Engine.get_process_frames()

	# Choose mode based on building properties
	if _current_building_data.is_linear_placement:
		state = State.LINEAR_START
		print("[PlacementController] Linear placement started: %s" % _current_building_data.display_name)
	else:
		state = State.SINGLE_PLACING
		print("[PlacementController] Single placement started: %s" % _current_building_data.display_name)

	placement_started.emit(building_type)


func cancel_placement() -> void:
	"""Cancel current placement"""
	if state == State.IDLE:
		return

	_destroy_ghost()
	_reset_state()
	placement_cancelled.emit()
	print("[PlacementController] Placement cancelled")


func update_cursor_position(world_pos: Vector3) -> void:
	"""Update cursor world position (called by BattleHUD each frame)"""
	_cursor_world_pos = world_pos


func handle_input(event: InputEvent, world_pos: Vector3) -> bool:
	"""Handle input events during placement. Returns true if event was consumed."""
	if state == State.IDLE:
		return false

	# Always consume input during active placement to prevent propagation
	# This prevents clicks from clearing selection or triggering other systems

	# Skip input on the same frame we were activated (prevents menu click from committing)
	if Engine.get_process_frames() == _activation_frame:
		return true  # Consume the event but don't act on it

	_cursor_world_pos = world_pos

	# Mouse button events
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton

		# Left-click: commit placement (may fail validation, but still consume)
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			# Validate world position before attempting placement
			# Invalid positions (zero, NaN, extreme) suggest clicking on UI
			var pos_valid: bool = world_pos != Vector3.ZERO
			pos_valid = pos_valid and not is_nan(world_pos.x) and not is_nan(world_pos.z)
			pos_valid = pos_valid and absf(world_pos.x) < 10000.0 and absf(world_pos.z) < 10000.0
			if not pos_valid:
				# Invalid position - don't consume, let UI handle
				return false
			_handle_left_click(world_pos)
			return true  # Always consume, even if validation fails

		# Right-click: always cancel placement (consistent RTS UX - right-click = cancel/orders)
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			cancel_placement()
			return true

	# Key events
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed:
			match key_event.keycode:
				KEY_ESCAPE:
					cancel_placement()
					return true
				KEY_Q:
					# Rotate counter-clockwise (bridges only)
					if _is_bridge_placement():
						rotate_bridge(false)
						return true
				KEY_E:
					# Rotate clockwise (bridges only)
					if _is_bridge_placement():
						rotate_bridge(true)
						return true

	# Mouse motion for arc rotation (when anchored, mouse position sets facing)
	if event is InputEventMouseMotion and _arc_anchored:
		_update_arc_facing_from_cursor()
		return true

	# Consume all other input during placement (mouse motion, etc.)
	return true


## =============================================================================
## SINGLE PLACEMENT MODE
## =============================================================================

func _update_single_placement() -> void:
	"""Update ghost for single building placement"""
	if not is_instance_valid(_ghost):
		return

	# For arc buildings when anchored, keep position locked and update facing
	if _arc_anchored and _is_arc_building():
		_ghost.update_position(_arc_anchor_pos)
		_update_arc_facing_from_cursor()
		# Validate at anchor position
		var saved_cursor := _cursor_world_pos
		_cursor_world_pos = _arc_anchor_pos
		_validate_current_position()
		_cursor_world_pos = saved_cursor
		return

	# Update ghost position
	_ghost.update_position(_cursor_world_pos)

	# Special handling for bridges - show span preview
	if _is_bridge_placement():
		_update_bridge_preview()

	# Validate placement
	_validate_current_position()


func _commit_single_placement(position: Vector3) -> bool:
	"""Commit single building placement"""
	if not _last_validation_result.get("valid", false):
		var error_msg: String = _last_validation_result.get("message", "Unknown error")
		print("[PlacementController] Cannot place - invalid location: %s" % error_msg)
		# Cancel placement after failed validation so user can interact with UI
		cancel_placement()
		return false

	# Get rotation for this building
	# - Bridges have custom rotation via Q/E keys
	# - Arc buildings use arc facing set via right-click drag
	# - Other buildings use 0 rotation
	var rotation_y: float = 0.0
	if _is_bridge_placement():
		rotation_y = _bridge_rotation_y
	elif _is_arc_building():
		# Use rotation_y to encode arc facing direction (degrees)
		# DefensiveStructure will read this as facing_direction
		rotation_y = deg_to_rad(_arc_facing)
		# Also store in building_data for the spawn process
		_current_building_data.initial_facing = _arc_facing

	# Create build job through JobSystem
	# Signature: create_build_job(center, building_type, rotation, footprint_size, skip_validation)
	if _job_system and _job_system.has_method("create_build_job"):
		var job = _job_system.create_build_job(
			position,
			_current_building_type,
			rotation_y,
			_current_building_data.footprint_size,
			false  # don't skip validation
		)
		var job_id: int = job.job_id if is_instance_valid(job) else -1
		if job_id >= 0:
			print("[PlacementController] Created build job #%d for %s at %v (rot: %.1f deg)" % [
				job_id, _current_building_data.display_name, position, rad_to_deg(rotation_y)
			])

			# For bridges, also register with road network when construction completes
			if _is_bridge_placement():
				_queue_bridge_road_segment(job, _bridge_span_start, _bridge_span_end)

			placement_committed.emit(_current_building_type, position)
			_destroy_ghost()
			_reset_state()
			return true
		else:
			print("[PlacementController] Failed to create build job")
			# Cancel placement after job creation failure
			cancel_placement()
			return false
	else:
		push_warning("[PlacementController] JobSystem not available")
		# Cancel placement if no job system
		cancel_placement()
		return false


## =============================================================================
## LINEAR PLACEMENT MODE (Sandbags/Wire)
## =============================================================================

func _update_linear_start() -> void:
	"""Update ghost when waiting for first click"""
	if not is_instance_valid(_ghost):
		return

	# Show single segment at cursor
	_ghost.update_position(_cursor_world_pos)
	_validate_current_position()


func _update_linear_dragging() -> void:
	"""Update ghost while dragging to extend line"""
	if not is_instance_valid(_ghost) or _linear_start_pos == Vector3.INF:
		return

	# Calculate segments along the line
	_calculate_linear_segments(_linear_start_pos, _cursor_world_pos)

	# Update ghost line (continuous line showing overall direction)
	var points: PackedVector3Array = [_linear_start_pos, _cursor_world_pos]
	_ghost.set_line_points(points)

	# Validate all segments and update ghost state
	_validate_linear_segments()

	# Update segment markers at actual placement positions
	_update_segment_markers()


func _calculate_linear_segments(start: Vector3, end: Vector3) -> void:
	"""Calculate segment positions along a line"""
	_linear_segment_positions.clear()
	_linear_valid_segments.clear()

	var segment_length: float = _current_building_data.footprint_size.x
	if segment_length <= 0:
		segment_length = 3.0  # Default

	# Tighten spacing to close visual gaps between segments
	# The footprint is the collision size; visual models are slightly smaller
	var segment_spacing: float = segment_length * 0.85

	var direction := (end - start)
	direction.y = 0  # Keep on horizontal plane
	var total_length := direction.length()

	if total_length < segment_spacing * 0.5:
		return  # Too short for any segments

	direction = direction.normalized()

	# Calculate rotation perpendicular to drag direction
	# Sandbags/wire should form a wall ALONG the paint line, facing outward
	# atan2(x, z) gives the drag direction; add PI/2 to face perpendicular
	_linear_rotation_y = atan2(direction.x, direction.z) + PI / 2.0

	var count := int(total_length / segment_spacing)

	for i in range(count):
		var pos := start + direction * (segment_spacing * (i + 0.5))
		# Snap to terrain height
		if _terrain and _terrain.has_method("get_height_at"):
			pos.y = _terrain.get_height_at(pos)
		_linear_segment_positions.append(pos)
		_linear_valid_segments.append(true)  # Will be validated next


func _validate_linear_segments() -> void:
	"""Validate each segment in linear placement"""
	if not _job_system:
		return

	var valid_count := 0
	var footprint := _current_building_data.footprint_size

	for i in range(_linear_segment_positions.size()):
		var pos: Vector3 = _linear_segment_positions[i]
		var result: Dictionary

		if _job_system.has_method("validate_placement_real_time"):
			result = _job_system.validate_placement_real_time(pos, footprint, _current_building_type, _linear_rotation_y)
		else:
			result = _job_system.validate_placement(pos, footprint, _current_building_type, _linear_rotation_y)

		var is_valid: bool = result.get("valid", false)
		_linear_valid_segments[i] = is_valid
		if is_valid:
			valid_count += 1

	# Update ghost state based on validation
	if is_instance_valid(_ghost):
		if _linear_segment_positions.is_empty():
			_ghost.set_placement_state(BlueprintGhost.PlacementState.WARNING)
		elif valid_count == _linear_segment_positions.size():
			_ghost.set_placement_state(BlueprintGhost.PlacementState.VALID)
		elif valid_count > 0:
			_ghost.set_placement_state(BlueprintGhost.PlacementState.WARNING)
		else:
			_ghost.set_placement_state(BlueprintGhost.PlacementState.INVALID)

	# Emit validation status
	var message := "%d/%d segments valid" % [valid_count, _linear_segment_positions.size()]
	validation_changed.emit(valid_count > 0, message)


func _update_segment_markers() -> void:
	"""Update segment marker visualization at actual placement positions"""
	if not is_instance_valid(_ghost):
		return

	if _linear_segment_positions.is_empty():
		_ghost.clear_segment_markers()
		return

	# Get segment footprint size from building data
	var segment_size := Vector2(
		_current_building_data.footprint_size.x,
		_current_building_data.footprint_size.y
	)

	# Pass segment data to ghost for rendering
	# Rotation is perpendicular to drag direction (calculated in _calculate_segments)
	_ghost.set_segment_markers(
		_linear_segment_positions,
		_linear_valid_segments,
		_linear_rotation_y,
		segment_size
	)


func _start_linear_drag(position: Vector3) -> void:
	"""Begin linear drag from starting position"""
	_linear_start_pos = position
	state = State.LINEAR_DRAGGING

	# Switch ghost to LINE type - use _destroy_ghost() for proper cleanup
	_destroy_ghost()
	_ghost = BlueprintGhost.create_line(_current_building_data.footprint_size.y)  # Width
	_ghost.name = "LinearPlacementGhost"
	add_child(_ghost)
	_ghost.show_ghost()


func _commit_linear_placement() -> bool:
	"""Commit all valid segments in linear placement"""
	if _linear_segment_positions.is_empty():
		print("[PlacementController] No segments to place")
		cancel_placement()
		return false

	var placed_positions: Array[Vector3] = []
	var footprint := _current_building_data.footprint_size

	for i in range(_linear_segment_positions.size()):
		if not _linear_valid_segments[i]:
			continue

		var pos: Vector3 = _linear_segment_positions[i]

		# Create build job for this segment
		# Signature: create_build_job(center, building_type, rotation, footprint_size, skip_validation)
		if _job_system and _job_system.has_method("create_build_job"):
			var job = _job_system.create_build_job(
				pos,
				_current_building_type,
				_linear_rotation_y,  # perpendicular to drag direction
				footprint,
				false  # don't skip validation
			)
			var job_id: int = job.job_id if is_instance_valid(job) else -1
			if job_id >= 0:
				placed_positions.append(pos)
				print("[PlacementController] Created linear segment job #%d at %v" % [job_id, pos])

	if placed_positions.size() > 0:
		print("[PlacementController] Placed %d/%d segments of %s" % [
			placed_positions.size(),
			_linear_segment_positions.size(),
			_current_building_data.display_name
		])
		linear_segment_committed.emit(_current_building_type, placed_positions)
		_destroy_ghost()
		_reset_state()
		return true
	else:
		print("[PlacementController] No valid segments to place")
		cancel_placement()
		return false


## =============================================================================
## INPUT HANDLING
## =============================================================================

func _handle_left_click(position: Vector3) -> bool:
	"""Handle left-click during placement.
	   For arc buildings (MG nest, mortar pit): first click anchors, second click confirms.
	   For other buildings: single click places."""
	match state:
		State.SINGLE_PLACING:
			if _is_arc_building():
				if not _arc_anchored:
					# First left-click: anchor position and enter rotation mode
					_arc_anchored = true
					_arc_anchor_pos = position
					print("[PlacementController] Arc building anchored at %v - move mouse to aim, left-click to confirm" % _arc_anchor_pos)
					return true
				else:
					# Second left-click: commit at anchor position with current facing
					return _commit_single_placement(_arc_anchor_pos)
			else:
				# Non-arc building: immediate placement
				return _commit_single_placement(position)

		State.LINEAR_START:
			_start_linear_drag(position)
			return true

		State.LINEAR_DRAGGING:
			return _commit_linear_placement()

	return false


## =============================================================================
## VALIDATION
## =============================================================================

func _validate_current_position() -> void:
	"""Validate current cursor position for placement"""
	if not _job_system or not _current_building_data:
		return

	var footprint := _current_building_data.footprint_size

	# Get rotation (bridges use _bridge_rotation_y, others use 0)
	var rotation_y: float = _bridge_rotation_y if _is_bridge_placement() else 0.0

	if _job_system.has_method("validate_placement_real_time"):
		_last_validation_result = _job_system.validate_placement_real_time(
			_cursor_world_pos, footprint, _current_building_type, rotation_y
		)
	else:
		_last_validation_result = _job_system.validate_placement(
			_cursor_world_pos, footprint, _current_building_type, rotation_y
		)

	# Update ghost color based on validation
	var is_valid: bool = _last_validation_result.get("valid", false)
	if is_instance_valid(_ghost):
		if is_valid:
			_ghost.set_placement_state(BlueprintGhost.PlacementState.VALID)
		else:
			_ghost.set_placement_state(BlueprintGhost.PlacementState.INVALID)

	# Emit validation change
	var error_msg: String = _last_validation_result.get("message", "")
	validation_changed.emit(is_valid, error_msg)


## =============================================================================
## BRIDGE PLACEMENT HELPERS
## =============================================================================

func _is_bridge_placement() -> bool:
	"""Check if current placement is a bridge"""
	return _current_building_type == BuildingData.BuildingType.MODULAR_BRIDGE


func _is_arc_building() -> bool:
	"""Check if current building has a directional fire arc (not 360 degree)"""
	if not _current_building_data:
		return false
	# Buildings with arc < 360 and weapon_range > 0 are directional weapons
	return _current_building_data.fire_arc < 360.0 and _current_building_data.weapon_range > 0.0


func _update_arc_facing_from_cursor() -> void:
	"""Update arc facing based on direction from anchored position to cursor.
	   Called continuously after first left-click anchors position.
	   User moves mouse to aim, then left-clicks again to confirm placement."""
	if not _arc_anchored or not is_instance_valid(_ghost):
		return

	# Calculate direction from anchor to cursor in world space
	var direction: Vector3 = _cursor_world_pos - _arc_anchor_pos
	direction.y = 0  # Only consider horizontal direction

	# Only update if cursor has moved enough from anchor
	if direction.length() < 1.0:
		return

	# Convert to facing angle (0 = north/+Z, clockwise positive)
	# atan2(x, z) gives angle from +Z axis
	_arc_facing = rad_to_deg(atan2(direction.x, direction.z))

	# Update ghost visualization
	if _ghost.has_method("update_arc_facing"):
		_ghost.update_arc_facing(_arc_facing)


func _update_bridge_preview() -> void:
	"""Update bridge span preview based on cursor position and rotation.

	Bridges can be rotated with Q/E keys to align with terrain features.
	The span endpoints are calculated and shown to help placement.
	"""
	if not _current_building_data:
		return

	var footprint := _current_building_data.footprint_size
	var half_length: float = footprint.y * 0.5

	# Calculate span direction based on rotation
	var cos_r: float = cos(_bridge_rotation_y)
	var sin_r: float = sin(_bridge_rotation_y)
	var span_dir := Vector3(sin_r, 0.0, cos_r)

	# Calculate span endpoints
	_bridge_span_start = _cursor_world_pos - span_dir * half_length
	_bridge_span_end = _cursor_world_pos + span_dir * half_length

	# Snap endpoints to terrain height
	if _terrain and _terrain.has_method("get_height_at"):
		_bridge_span_start.y = _terrain.get_height_at(_bridge_span_start)
		_bridge_span_end.y = _terrain.get_height_at(_bridge_span_end)

	# Update ghost rotation
	if is_instance_valid(_ghost):
		_ghost.rotation.y = _bridge_rotation_y

		# If ghost supports span preview, update it
		if _ghost.has_method("set_bridge_span"):
			_ghost.set_bridge_span(_bridge_span_start, _bridge_span_end)


func rotate_bridge(clockwise: bool) -> void:
	"""Rotate bridge placement by 15 degrees.
	Called by input handler when Q/E pressed during bridge placement."""
	if not _is_bridge_placement():
		return

	var rotation_step: float = deg_to_rad(15.0)
	if clockwise:
		_bridge_rotation_y += rotation_step
	else:
		_bridge_rotation_y -= rotation_step

	# Normalize rotation to 0-360
	_bridge_rotation_y = fmod(_bridge_rotation_y, TAU)
	if _bridge_rotation_y < 0:
		_bridge_rotation_y += TAU

	# Trigger validation update with new rotation
	_validate_current_position()


func get_bridge_rotation() -> float:
	"""Get current bridge rotation in radians"""
	return _bridge_rotation_y


func get_bridge_span() -> Dictionary:
	"""Get current bridge span endpoints for preview rendering"""
	return {
		"start": _bridge_span_start,
		"end": _bridge_span_end,
		"rotation": _bridge_rotation_y
	}


func _queue_bridge_road_segment(job: Node, span_start: Vector3, span_end: Vector3) -> void:
	"""Queue road network integration for when bridge construction completes.

	When the bridge is built, we need to add it as a road segment so convoys
	can pathfind across it. This stores the span info in job metadata and
	connects to the job completion signal.
	"""
	if not is_instance_valid(job):
		return

	# Store span endpoints in job metadata for later use
	job.metadata["bridge_span_start"] = span_start
	job.metadata["bridge_span_end"] = span_end
	job.metadata["is_bridge"] = true

	# Connect to job completion to create road segment
	if job.has_signal("job_completed"):
		job.job_completed.connect(_on_bridge_job_completed.bind(job))


func _on_bridge_job_completed(job: Node) -> void:
	"""Create road segment when bridge construction completes"""
	if not is_instance_valid(job):
		return

	if not job.metadata.get("is_bridge", false):
		return

	var span_start: Vector3 = job.metadata.get("bridge_span_start", Vector3.ZERO)
	var span_end: Vector3 = job.metadata.get("bridge_span_end", Vector3.ZERO)

	if span_start == Vector3.ZERO or span_end == Vector3.ZERO:
		push_warning("[PlacementController] Bridge job completed but missing span data")
		return

	# Find RoadNetwork and create bridge segment
	var road_network: Node = get_node_or_null("/root/RoadNetwork")
	if road_network and road_network.has_method("create_bridge_segment"):
		var segment_id: int = road_network.create_bridge_segment(span_start, span_end)
		if segment_id >= 0:
			print("[PlacementController] Bridge road segment #%d created from %v to %v" % [
				segment_id, span_start, span_end
			])
		else:
			push_warning("[PlacementController] Failed to create bridge road segment")
	else:
		push_warning("[PlacementController] RoadNetwork not available for bridge registration")


## =============================================================================
## GHOST MANAGEMENT
## =============================================================================

func _create_ghost_for_building() -> void:
	"""Create appropriate ghost for current building type"""
	_destroy_ghost()

	# Reset arc state for new placement
	_arc_facing = 0.0
	_arc_anchored = false
	_arc_anchor_pos = Vector3.ZERO

	if _current_building_data.is_linear_placement:
		# For linear placement, start with RECTANGLE ghost at cursor
		# Will switch to LINE type when dragging starts
		var size := Vector3(
			_current_building_data.footprint_size.x,
			_current_building_data.height,
			_current_building_data.footprint_size.y
		)
		_ghost = BlueprintGhost.create_rectangle(size)
	elif _is_arc_building():
		# Directional weapon emplacement - show fire arc cone
		_ghost = BlueprintGhost.create_arc_sector(
			_current_building_data.weapon_range,
			_current_building_data.fire_arc,
			_arc_facing
		)
		# Also set base_size for building footprint display
		_ghost.base_size = Vector3(
			_current_building_data.footprint_size.x,
			_current_building_data.height,
			_current_building_data.footprint_size.y
		)
	else:
		# Standard building - rectangle ghost
		var size := Vector3(
			_current_building_data.footprint_size.x,
			_current_building_data.height,
			_current_building_data.footprint_size.y
		)
		_ghost = BlueprintGhost.create_rectangle(size)

	_ghost.name = "PlacementGhost"
	add_child(_ghost)

	# Set influence radius for HQ buildings (TOC, Command Post)
	# Shows the 150m firebase zone where other buildings can be placed
	if _current_building_data.is_hq_building and _current_building_data.influence_radius > 0:
		_ghost.set_influence_radius(_current_building_data.influence_radius)

	_ghost.show_ghost()


func _destroy_ghost() -> void:
	"""Remove and clean up ghost synchronously"""
	if is_instance_valid(_ghost):
		# Use synchronous destruction to prevent race conditions
		_ghost.visible = false
		if _ghost.get_parent():
			_ghost.get_parent().remove_child(_ghost)
		_ghost.free()  # Synchronous, not queue_free
		_ghost = null


## =============================================================================
## STATE MANAGEMENT
## =============================================================================

func _reset_state() -> void:
	"""Reset all state to idle"""
	state = State.IDLE
	_current_building_type = -1
	_current_building_data = null
	_linear_start_pos = Vector3.INF
	_linear_segment_positions.clear()
	_linear_valid_segments.clear()
	_linear_rotation_y = 0.0
	_bridge_rotation_y = 0.0
	_bridge_span_start = Vector3.ZERO
	_bridge_span_end = Vector3.ZERO
	_arc_facing = 0.0
	_arc_anchored = false
	_arc_anchor_pos = Vector3.ZERO
	_last_validation_result = {"valid": true, "error": 0, "message": ""}


## =============================================================================
## DEBUG / INFO
## =============================================================================

func get_current_building_name() -> String:
	"""Get display name of currently selected building"""
	if _current_building_data:
		return _current_building_data.display_name
	return ""


func get_validation_message() -> String:
	"""Get current validation error message"""
	return _last_validation_result.get("message", "")


func get_segment_count() -> int:
	"""Get number of segments in linear placement"""
	return _linear_segment_positions.size()


func get_valid_segment_count() -> int:
	"""Get number of valid segments in linear placement"""
	var count := 0
	for valid in _linear_valid_segments:
		if valid:
			count += 1
	return count
