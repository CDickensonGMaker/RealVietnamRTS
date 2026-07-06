class_name AnimatedSoldier extends Soldier
## AnimatedSoldier - Soldier with procedural skeletal animation
##
## Extends the base Soldier class to add Spring 1944-style code-driven animation.
## Automatically triggers animations based on SoldierState changes.

const ProceduralAnimatorScript = preload("res://battle_system/animation/procedural_animator.gd")
const SkeletonMapperScript = preload("res://battle_system/animation/skeleton_mapper.gd")
const InfantryPosesScript = preload("res://battle_system/animation/infantry_poses.gd")

signal animation_state_changed(anim_state: String)

## Animation system components
var _animator = null  # ProceduralAnimator instance
var _mapper = null    # SkeletonMapper instance
var _skeleton: Skeleton3D = null

## Animation state tracking
var _current_anim_state: String = "stand_idle"
var _last_velocity: Vector3 = Vector3.ZERO
var _is_aiming: bool = false

## Speed thresholds for animation selection
const WALK_SPEED_THRESHOLD := 2.0
const RUN_SPEED_THRESHOLD := 4.5

## Model path to load
var model_path: String = ""


func _ready() -> void:
	super._ready()
	_setup_procedural_animation()


## Override to load rigged model and setup animation
func load_model(path: String) -> void:
	model_path = path

	# Load the model
	var scene: PackedScene = load(path)
	if not scene:
		push_error("AnimatedSoldier: Failed to load model: %s" % path)
		return

	if _model:
		_model.queue_free()
		_model = null

	_model = scene.instantiate()
	add_child(_model)

	# Hide placeholder visuals
	if _body_mesh:
		_body_mesh.visible = false
	if _head_mesh:
		_head_mesh.visible = false

	# Find and setup skeleton
	_find_skeleton(_model)
	if _skeleton:
		_setup_animator()


## Setup procedural animation system
func _setup_procedural_animation() -> void:
	_animator = ProceduralAnimatorScript.new()
	_mapper = SkeletonMapperScript.new()


## Find skeleton in model hierarchy
func _find_skeleton(node: Node) -> void:
	if node is Skeleton3D:
		_skeleton = node as Skeleton3D
		print("[AnimatedSoldier] Found skeleton with %d bones" % _skeleton.get_bone_count())
		return

	for child in node.get_children():
		_find_skeleton(child)
		if _skeleton:
			return


## Setup animator after skeleton is found
func _setup_animator() -> void:
	if not _skeleton:
		push_warning("AnimatedSoldier: No skeleton found for animation")
		return

	# Scan skeleton and create bone mapping
	_mapper.scan_skeleton(_skeleton)
	_mapper.print_mapping()

	# Setup animator
	if not _animator.setup(_skeleton, _mapper):
		push_error("AnimatedSoldier: Failed to setup animator")
		return

	# Load pose and cycle data
	_animator.load_poses(InfantryPosesScript.POSES)
	_animator.load_cycles(InfantryPosesScript.CYCLES)

	# Start with idle pose
	_animator.set_pose_immediate("stand_idle")
	_current_anim_state = "stand_idle"

	print("[AnimatedSoldier] Animation system ready")


func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	# Update animation based on state
	if _animator and _skeleton:
		_update_animation_state()
		_animator.update(delta)


## Determine correct animation based on soldier state and movement
func _update_animation_state() -> void:
	var new_state: String = _current_anim_state

	match state:
		SoldierState.DEAD:
			if _current_anim_state != "dead_front" and _current_anim_state != "dead_back":
				# Randomly pick death pose
				new_state = "dead_front" if randf() > 0.5 else "dead_back"
				_set_animation_state(new_state)
			return

		SoldierState.PRONE:
			if _is_aiming:
				new_state = "prone_aim"
			else:
				# Check if crawling
				var speed: float = velocity.length()
				if speed > 0.5:
					_play_cycle_if_not_playing("crawl")
					return
				else:
					new_state = "prone_idle"

		SoldierState.MOVING:
			var speed: float = velocity.length()
			if speed > RUN_SPEED_THRESHOLD:
				_play_cycle_if_not_playing("run")
				return
			elif speed > WALK_SPEED_THRESHOLD:
				_play_cycle_if_not_playing("walk")
				return
			else:
				# Very slow movement - use idle
				new_state = "stand_idle" if not _is_aiming else "stand_aim"

		SoldierState.COMBAT:
			new_state = "stand_aim" if not _is_crouching() else "crouch_aim"

		SoldierState.IDLE:
			if _is_aiming:
				new_state = "stand_aim" if not _is_crouching() else "crouch_aim"
			else:
				new_state = "stand_idle" if not _is_crouching() else "crouch_idle"

	_set_animation_state(new_state)


## Helper to check if soldier is crouching
func _is_crouching() -> bool:
	# Could be extended to track crouch state
	return false


## Play a cycle if not already playing it
func _play_cycle_if_not_playing(cycle_name: String) -> void:
	if _animator.get_active_cycle() != cycle_name:
		_animator.play_cycle(cycle_name)
		_current_anim_state = cycle_name
		animation_state_changed.emit(cycle_name)


## Set a static pose animation state
func _set_animation_state(new_state: String) -> void:
	if new_state == _current_anim_state:
		return

	# Stop any playing cycle
	if _animator.is_cycle_playing():
		_animator.stop_cycle()

	# Set the pose
	if _animator.set_pose(new_state):
		_current_anim_state = new_state
		animation_state_changed.emit(new_state)


## Public API for controlling animations

## Set aiming state (affects pose selection)
func set_aiming(aiming: bool) -> void:
	_is_aiming = aiming
	_update_animation_state()


## Force a specific pose
func force_pose(pose_name: String) -> void:
	if _animator:
		_animator.set_pose(pose_name)
		_current_anim_state = pose_name


## Force a specific animation cycle
func force_cycle(cycle_name: String) -> void:
	if _animator:
		_animator.play_cycle(cycle_name)
		_current_anim_state = cycle_name


## Stop current animation cycle
func stop_animation_cycle() -> void:
	if _animator:
		_animator.stop_cycle()


## Get current animation state name
func get_animation_state() -> String:
	return _current_anim_state


## Check if animator is properly set up
func has_animator() -> bool:
	return _animator != null and _skeleton != null


## Get the skeleton for external manipulation
func get_skeleton() -> Skeleton3D:
	return _skeleton


## Get the mapper for debugging
func get_mapper():  # Returns SkeletonMapper
	return _mapper


## Get the animator for advanced control
func get_animator():  # Returns ProceduralAnimator
	return _animator
