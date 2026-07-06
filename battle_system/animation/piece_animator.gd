class_name PieceAnimator extends RefCounted
## PieceAnimator - Spring 1944-style piece-based animation system
##
## Unlike skeletal animation, Spring 1944 uses named mesh "pieces" that are
## rotated and moved via code. This animator finds child nodes by name and
## applies transforms directly.
##
## Usage:
##   var animator := PieceAnimator.new()
##   animator.setup(model_root)
##   animator.set_pose("stand_idle")
##   animator.play_cycle("run")

signal pose_changed(pose_name: String)
signal cycle_started(cycle_name: String)
signal cycle_stopped(cycle_name: String)

## Configuration
const DEFAULT_BLEND_TIME := 0.25
const DEFAULT_CYCLE_SPEED := 1.0

## Axis remapping from Spring 1944 to GLB/Godot coordinates
## Spring 1944: Z-up, rotations around local axes
## GLB/Godot: Y-up, different conventions
## Format: Vector3(x_mult, y_mult, z_mult) and axis swap
## Try different values until animation looks correct
var axis_multipliers := Vector3(-1.0, -1.0, 1.0)  # Negate X and Y
var swap_yz := true  # Swap Y and Z axes (Z-up to Y-up conversion)

## Root node of the model
var _model_root: Node3D = null

## Piece node cache: piece_name -> Node3D
var _pieces: Dictionary = {}

## Rest transforms for each piece (to reset properly)
var _rest_transforms: Dictionary = {}

## Pose/cycle data
var _poses: Dictionary = {}
var _cycles: Dictionary = {}

## Current animation state
var _current_rotations: Dictionary = {}  # piece_name -> Vector3 (current rotation in radians)
var _start_rotations: Dictionary = {}    # piece_name -> Vector3 (start rotation for blend)
var _target_rotations: Dictionary = {}   # piece_name -> Vector3 (target rotation)
var _blend_progress: float = 1.0
var _blend_time: float = DEFAULT_BLEND_TIME

## Cycle state
var _active_cycle: String = ""
var _cycle_frames: Array = []
var _cycle_frame_index: int = 0
var _cycle_frame_time: float = 0.0
var _cycle_speed: float = DEFAULT_CYCLE_SPEED
var _is_cycle_playing: bool = false



## Setup the animator with a model root node
func setup(model_root: Node3D) -> bool:
	if not model_root:
		push_error("PieceAnimator: model_root is null")
		return false

	_model_root = model_root
	_find_pieces(model_root)

	if _pieces.is_empty():
		push_warning("PieceAnimator: No pieces found in model")
		return false

	# Store rest transforms
	for piece_name: String in _pieces.keys():
		var piece: Node3D = _pieces[piece_name]
		_rest_transforms[piece_name] = piece.transform
		_current_rotations[piece_name] = Vector3.ZERO

	# Debug: print("[PieceAnimator] Found %d pieces" % _pieces.size())
	return true


## Recursively find all named pieces in the model
func _find_pieces(node: Node, depth: int = 0) -> void:
	# Check if this node matches a Spring 1944 piece name
	var node_name: String = node.name.to_lower()

	# Spring 1944 piece names we look for
	var piece_names: Array = [
		"head", "torso", "pelvis", "gun", "ground", "flare",
		"luparm", "lloarm", "ruparm", "rloarm",
		"lthigh", "lleg", "lfoot", "rthigh", "rleg", "rfoot"
	]

	for piece_name: String in piece_names:
		if node_name == piece_name or node_name.ends_with("_" + piece_name) or node_name.begins_with(piece_name + "_"):
			if node is Node3D:
				_pieces[piece_name] = node as Node3D
				# Debug: print("  [PieceAnimator] Found piece: %s -> %s" % [piece_name, node.name])

	# Recurse into children
	for child in node.get_children():
		_find_pieces(child, depth + 1)


## Load pose definitions
func load_poses(poses: Dictionary) -> void:
	_poses = poses.duplicate(true)


## Load cycle definitions
func load_cycles(cycles: Dictionary) -> void:
	_cycles = cycles.duplicate(true)


## Set blend time for transitions
func set_blend_time(time: float) -> void:
	_blend_time = maxf(0.01, time)


## Set cycle playback speed
func set_cycle_speed(speed: float) -> void:
	_cycle_speed = maxf(0.1, speed)


## Immediately set to a pose (no blending)
func set_pose_immediate(pose_name: String) -> bool:
	if not _poses.has(pose_name):
		push_warning("PieceAnimator: pose '%s' not found" % pose_name)
		return false

	_stop_cycle_internal()

	var pose: Dictionary = _poses[pose_name]
	for piece_name: String in pose.keys():
		_current_rotations[piece_name] = pose[piece_name]
		_target_rotations[piece_name] = pose[piece_name]

	_blend_progress = 1.0
	_apply_rotations()
	pose_changed.emit(pose_name)
	return true


## Blend to a pose over time
func set_pose(pose_name: String, blend_time: float = -1.0) -> bool:
	if not _poses.has(pose_name):
		push_warning("PieceAnimator: pose '%s' not found" % pose_name)
		return false

	_stop_cycle_internal()

	# Store current rotations as start point for blend
	_start_rotations = _current_rotations.duplicate()

	var pose: Dictionary = _poses[pose_name]
	for piece_name: String in pose.keys():
		_target_rotations[piece_name] = pose[piece_name]
		# Ensure we have a start rotation for this piece
		if not _start_rotations.has(piece_name):
			_start_rotations[piece_name] = Vector3.ZERO

	_blend_progress = 0.0
	_blend_time = blend_time if blend_time > 0.0 else DEFAULT_BLEND_TIME

	# Debug: print("[PieceAnimator] Blending to pose: %s" % pose_name)
	pose_changed.emit(pose_name)
	return true


## Start playing an animation cycle
func play_cycle(cycle_name: String, blend_in_time: float = -1.0) -> bool:
	if not _cycles.has(cycle_name):
		push_warning("PieceAnimator: cycle '%s' not found" % cycle_name)
		return false

	var cycle: Array = _cycles[cycle_name]
	if cycle.is_empty():
		push_warning("PieceAnimator: cycle '%s' is empty" % cycle_name)
		return false

	_active_cycle = cycle_name
	_cycle_frames = cycle
	_cycle_frame_index = 0
	_cycle_frame_time = 0.0
	_is_cycle_playing = true

	# Store current rotations as start point for blend
	_start_rotations = _current_rotations.duplicate()

	# Set first frame as target
	var first_frame: Dictionary = _cycle_frames[0]
	var frame_pose: Dictionary = first_frame.get("pose", {})
	for piece_name: String in frame_pose.keys():
		_target_rotations[piece_name] = frame_pose[piece_name]
		if not _start_rotations.has(piece_name):
			_start_rotations[piece_name] = Vector3.ZERO

	_blend_progress = 0.0
	_blend_time = blend_in_time if blend_in_time > 0.0 else DEFAULT_BLEND_TIME

	# Debug: print("[PieceAnimator] Playing cycle: %s" % cycle_name)
	cycle_started.emit(cycle_name)
	return true


## Stop the current cycle
func stop_cycle(blend_to_pose: String = "") -> void:
	_stop_cycle_internal()

	if not blend_to_pose.is_empty() and _poses.has(blend_to_pose):
		set_pose(blend_to_pose)


## Check if a cycle is currently playing
func is_cycle_playing() -> bool:
	return _is_cycle_playing


## Get the name of the currently playing cycle
func get_active_cycle() -> String:
	return _active_cycle if _is_cycle_playing else ""


## Update the animation - call this every frame
func update(delta: float) -> void:
	if _pieces.is_empty():
		return

	# Update cycle if playing
	if _is_cycle_playing:
		_update_cycle(delta)

	# Update blend
	if _blend_progress < 1.0:
		_blend_progress += delta / _blend_time
		_blend_progress = minf(_blend_progress, 1.0)
		_interpolate_rotations()

	# Apply current rotations to pieces
	_apply_rotations()


## Internal: stop cycle without blending
func _stop_cycle_internal() -> void:
	if _is_cycle_playing:
		var old_cycle: String = _active_cycle
		_is_cycle_playing = false
		_active_cycle = ""
		_cycle_frames = []
		cycle_stopped.emit(old_cycle)


## Internal: update cycle animation
func _update_cycle(delta: float) -> void:
	if _cycle_frames.is_empty():
		return

	var current_frame: Dictionary = _cycle_frames[_cycle_frame_index]
	var frame_duration: float = current_frame.get("duration", 0.2) / _cycle_speed

	_cycle_frame_time += delta

	# Check if we should advance to next frame
	if _cycle_frame_time >= frame_duration:
		_cycle_frame_time -= frame_duration
		_cycle_frame_index = (_cycle_frame_index + 1) % _cycle_frames.size()

		# Store current as start for next blend
		_start_rotations = _current_rotations.duplicate()

		# Set new target from next frame
		var next_frame: Dictionary = _cycle_frames[_cycle_frame_index]
		var frame_pose: Dictionary = next_frame.get("pose", {})
		for piece_name: String in frame_pose.keys():
			_target_rotations[piece_name] = frame_pose[piece_name]
			if not _start_rotations.has(piece_name):
				_start_rotations[piece_name] = Vector3.ZERO

		# Quick blend between cycle frames
		_blend_progress = 0.0
		_blend_time = minf(frame_duration * 0.8, 0.15)


## Internal: interpolate between start and target rotations
func _interpolate_rotations() -> void:
	var t: float = _ease_in_out(_blend_progress)

	for piece_name: String in _target_rotations.keys():
		var start: Vector3 = _start_rotations.get(piece_name, Vector3.ZERO)
		var target: Vector3 = _target_rotations[piece_name]
		_current_rotations[piece_name] = start.lerp(target, t)


## Internal: apply current rotations to piece nodes
func _apply_rotations() -> void:
	for piece_name: String in _current_rotations.keys():
		if not _pieces.has(piece_name):
			continue

		var piece: Node3D = _pieces[piece_name]
		var rotation_rad: Vector3 = _current_rotations[piece_name]

		# Apply axis remapping from Spring 1944 to Godot coordinates
		var remapped: Vector3
		if swap_yz:
			# Swap Y and Z, then apply multipliers
			remapped = Vector3(
				rotation_rad.x * axis_multipliers.x,
				rotation_rad.z * axis_multipliers.y,  # Z -> Y
				rotation_rad.y * axis_multipliers.z   # Y -> Z
			)
		else:
			remapped = rotation_rad * axis_multipliers

		# Apply rotation directly
		piece.rotation = remapped


## Internal: smooth easing function
func _ease_in_out(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## Get all available pose names
func get_pose_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for key: String in _poses.keys():
		names.append(key)
	return names


## Get all available cycle names
func get_cycle_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for key: String in _cycles.keys():
		names.append(key)
	return names


## Check if a specific piece is found
func has_piece(piece_name: String) -> bool:
	return _pieces.has(piece_name)


## Get list of found pieces
func get_found_pieces() -> PackedStringArray:
	var names: PackedStringArray = []
	for key: String in _pieces.keys():
		names.append(key)
	return names


## Debug: print all found pieces
func print_pieces() -> void:
	print("[PieceAnimator] Found pieces:")
	for piece_name: String in _pieces.keys():
		var node: Node3D = _pieces[piece_name]
		print("  %s -> %s" % [piece_name, node.get_path()])
