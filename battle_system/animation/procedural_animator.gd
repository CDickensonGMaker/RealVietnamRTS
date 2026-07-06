class_name ProceduralAnimator extends RefCounted
## ProceduralAnimator - Code-driven skeletal animation system
##
## Inspired by Spring 1944's procedural animation approach.
## Takes a Skeleton3D reference and interpolates between poses defined as
## dictionaries of bone_name -> Vector3 (euler angles in degrees).
##
## Usage:
##   var animator := ProceduralAnimator.new()
##   animator.setup(skeleton, SkeletonMapper.new())
##   animator.set_pose("stand_idle")
##   animator.play_cycle("walk")

signal pose_changed(pose_name: String)
signal cycle_started(cycle_name: String)
signal cycle_stopped(cycle_name: String)

## Configuration
const DEFAULT_BLEND_TIME := 0.25  # Seconds to blend between poses
const DEFAULT_CYCLE_SPEED := 1.0

## References
var _skeleton: Skeleton3D = null
var _mapper = null  # SkeletonMapper instance

## Pose data - set from InfantryPoses or custom
var _poses: Dictionary = {}      # pose_name -> Dictionary[bone_name -> Vector3]
var _cycles: Dictionary = {}     # cycle_name -> Array[Dictionary] (frames)

## Current animation state
var _current_pose: Dictionary = {}   # Current applied bone rotations
var _target_pose: Dictionary = {}    # Target pose we're blending toward
var _blend_progress: float = 1.0     # 0.0 = at current, 1.0 = at target
var _blend_time: float = DEFAULT_BLEND_TIME

## Cycle state
var _active_cycle: String = ""
var _cycle_frames: Array = []
var _cycle_frame_index: int = 0
var _cycle_frame_time: float = 0.0
var _cycle_speed: float = DEFAULT_CYCLE_SPEED
var _is_cycle_playing: bool = false

## Bone index cache for performance
var _bone_indices: Dictionary = {}  # generic_name -> skeleton_bone_index


## Setup the animator with a skeleton and mapper
func setup(skeleton: Skeleton3D, mapper) -> bool:  # mapper: SkeletonMapper
	if not skeleton:
		push_error("ProceduralAnimator: skeleton is null")
		return false
	if not mapper:
		push_error("ProceduralAnimator: mapper is null")
		return false

	_skeleton = skeleton
	_mapper = mapper

	# Build bone index cache
	_bone_indices.clear()
	for generic_name: String in _mapper.get_all_generic_names():
		var actual_name: String = _mapper.get_actual_bone_name(generic_name)
		if actual_name.is_empty():
			continue
		var idx: int = _skeleton.find_bone(actual_name)
		if idx >= 0:
			_bone_indices[generic_name] = idx

	# Initialize current pose to rest pose
	_current_pose.clear()
	for generic_name: String in _bone_indices.keys():
		_current_pose[generic_name] = Vector3.ZERO

	return true


## Load pose definitions from InfantryPoses or custom dictionary
func load_poses(poses: Dictionary) -> void:
	_poses = poses.duplicate(true)


## Load cycle definitions
func load_cycles(cycles: Dictionary) -> void:
	_cycles = cycles.duplicate(true)


## Set blend time for pose transitions
func set_blend_time(time: float) -> void:
	_blend_time = maxf(0.01, time)


## Set cycle playback speed multiplier
func set_cycle_speed(speed: float) -> void:
	_cycle_speed = maxf(0.1, speed)


## Immediately set to a pose (no blending)
func set_pose_immediate(pose_name: String) -> bool:
	if not _poses.has(pose_name):
		push_warning("ProceduralAnimator: pose '%s' not found" % pose_name)
		return false

	_stop_cycle_internal()

	var pose: Dictionary = _poses[pose_name]
	_current_pose = pose.duplicate()
	_target_pose = pose.duplicate()
	_blend_progress = 1.0

	_apply_pose(_current_pose)
	pose_changed.emit(pose_name)
	return true


## Blend to a pose over time
func set_pose(pose_name: String, blend_time: float = -1.0) -> bool:
	if not _poses.has(pose_name):
		push_warning("ProceduralAnimator: pose '%s' not found" % pose_name)
		return false

	_stop_cycle_internal()

	var pose: Dictionary = _poses[pose_name]
	_target_pose = pose.duplicate()
	_blend_progress = 0.0
	_blend_time = blend_time if blend_time > 0.0 else DEFAULT_BLEND_TIME

	pose_changed.emit(pose_name)
	return true


## Start playing an animation cycle
func play_cycle(cycle_name: String, blend_in_time: float = -1.0) -> bool:
	if not _cycles.has(cycle_name):
		push_warning("ProceduralAnimator: cycle '%s' not found" % cycle_name)
		return false

	var cycle: Array = _cycles[cycle_name]
	if cycle.is_empty():
		push_warning("ProceduralAnimator: cycle '%s' is empty" % cycle_name)
		return false

	_active_cycle = cycle_name
	_cycle_frames = cycle
	_cycle_frame_index = 0
	_cycle_frame_time = 0.0
	_is_cycle_playing = true

	# Set first frame as target
	var first_frame: Dictionary = _cycle_frames[0]
	var frame_pose: Dictionary = first_frame.get("pose", {})
	_target_pose = frame_pose.duplicate()
	_blend_progress = 0.0
	_blend_time = blend_in_time if blend_in_time > 0.0 else DEFAULT_BLEND_TIME

	cycle_started.emit(cycle_name)
	return true


## Stop the current cycle, optionally blending to a pose
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
	if not _skeleton:
		return

	# Update cycle if playing
	if _is_cycle_playing:
		_update_cycle(delta)

	# Update blend
	if _blend_progress < 1.0:
		_blend_progress += delta / _blend_time
		_blend_progress = minf(_blend_progress, 1.0)
		_interpolate_pose()

	# Apply current pose to skeleton
	_apply_pose(_current_pose)


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

		# Set new target pose from next frame
		var next_frame: Dictionary = _cycle_frames[_cycle_frame_index]
		var frame_pose: Dictionary = next_frame.get("pose", {})
		_target_pose = frame_pose.duplicate()

		# Quick blend between cycle frames
		_blend_progress = 0.0
		_blend_time = minf(frame_duration * 0.8, 0.15)


## Internal: interpolate between current and target pose
func _interpolate_pose() -> void:
	var t: float = _ease_in_out(_blend_progress)

	for bone_name: String in _target_pose.keys():
		var current_rot: Vector3 = _current_pose.get(bone_name, Vector3.ZERO)
		var target_rot: Vector3 = _target_pose[bone_name]
		_current_pose[bone_name] = current_rot.lerp(target_rot, t)


## Internal: apply pose to skeleton
func _apply_pose(pose: Dictionary) -> void:
	for generic_name: String in pose.keys():
		if not _bone_indices.has(generic_name):
			continue

		var bone_idx: int = _bone_indices[generic_name]
		var euler_deg: Vector3 = pose[generic_name]
		var euler_rad := Vector3(
			deg_to_rad(euler_deg.x),
			deg_to_rad(euler_deg.y),
			deg_to_rad(euler_deg.z)
		)

		# Create rotation from euler angles
		var rotation := Basis.from_euler(euler_rad)

		# Apply as pose override (relative to rest pose)
		_skeleton.set_bone_pose_rotation(bone_idx, Quaternion(rotation))


## Internal: smooth easing function
func _ease_in_out(t: float) -> float:
	# Smoothstep for nice blending
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


## Get the current pose dictionary (for debugging)
func get_current_pose() -> Dictionary:
	return _current_pose.duplicate()


## Check if a specific bone is mapped and available
func has_bone(generic_name: String) -> bool:
	return _bone_indices.has(generic_name)
