extends Node
## Autoload that manages all in-battle XP awarding and level-up notifications.
## Tracks veterancy state for each unit and applies stat modifiers.

# =============================================================================
# XP SOURCE ENUM
# =============================================================================

enum XPSource {
	KILL,       ## XP from killing enemy units
	DAMAGE,     ## XP from dealing damage
	SURVIVAL,   ## XP from surviving under fire
	OBJECTIVE,  ## XP from completing objectives
	SPOTTING,   ## XP from spotting enemies (recon)
}

# =============================================================================
# XP AMOUNTS (base values, modified by tactic weights)
# =============================================================================

const XP_PER_KILL: int = 25
const XP_PER_DAMAGE_POINT: float = 0.1  # XP per point of damage dealt
const XP_PER_SURVIVAL_TICK: int = 1
const XP_PER_OBJECTIVE: int = 50
const XP_PER_SPOT: int = 5

# =============================================================================
# SIGNALS
# =============================================================================

## Emitted when a unit levels up
signal unit_leveled_up(unit: Node3D, new_level: int)

## Emitted when XP is awarded (for floating text feedback)
signal xp_awarded(unit: Node3D, amount: int, source: int)

# =============================================================================
# STATE
# =============================================================================

## Maps unit instance_id -> VeterancyState
var _unit_states: Dictionary = {}

## Maps unit instance_id -> cloned unit data (to avoid mutating shared resources)
var _unit_data_clones: Dictionary = {}

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	print("[VeterancyTracker] Initialized")


# =============================================================================
# UNIT REGISTRATION
# =============================================================================

## Registers a unit with the tracker, optionally with an existing state
func register_unit(unit: Node3D, initial_state: VeterancyState = null) -> void:
	if not is_instance_valid(unit):
		return

	var uid: int = unit.get_instance_id()

	# Create or use provided state
	var state: VeterancyState
	if initial_state != null:
		state = initial_state.duplicate_state()
	else:
		state = VeterancyState.new()

	# Check if RosterManager has an active tactic with starting veterancy floor
	var roster_mgr: Node = get_node_or_null("/root/RosterManager")
	if roster_mgr and roster_mgr.active_tactic != null:
		var floor_level: int = roster_mgr.active_tactic.starting_veterancy_floor
		if state.level < floor_level:
			state = VeterancyState.create_at_level(floor_level)

	_unit_states[uid] = state

	# Clone unit data to avoid mutating shared resource
	_clone_unit_data(unit)

	# Apply initial stat modifiers
	apply_stat_modifiers(unit)

	# Store reference to state on the unit for easy access
	if "veterancy" in unit:
		unit.veterancy = state


## Unregisters a unit (called on death/removal)
func unregister_unit(unit: Node3D) -> void:
	if not is_instance_valid(unit):
		return

	var uid: int = unit.get_instance_id()
	_unit_states.erase(uid)
	_unit_data_clones.erase(uid)


## Returns the veterancy state for a unit, or null if not registered
func get_state(unit: Node3D) -> VeterancyState:
	if not is_instance_valid(unit):
		return null

	var uid: int = unit.get_instance_id()
	var state: Variant = _unit_states.get(uid, null)
	return state as VeterancyState


## Checks if a unit is registered
func is_registered(unit: Node3D) -> bool:
	if not is_instance_valid(unit):
		return false
	return unit.get_instance_id() in _unit_states


# =============================================================================
# XP AWARDING
# =============================================================================

## Awards XP to a unit from a specific source
func award_xp(unit: Node3D, source: int, amount: int) -> void:
	if not is_instance_valid(unit) or amount <= 0:
		return

	var state: VeterancyState = get_state(unit)
	if state == null:
		# Auto-register if not registered
		register_unit(unit)
		state = get_state(unit)
		if state == null:
			return

	# Apply tactic weight if available
	var final_amount: int = _apply_tactic_weight(source, amount)

	# Add XP and check for level up
	var leveled_up: bool = state.add_xp(final_amount)

	# Emit signals
	xp_awarded.emit(unit, final_amount, source)

	# Spawn floating XP text (only for significant amounts)
	if final_amount >= 10:
		_spawn_floating_xp_text(unit, final_amount)

	if leveled_up:
		apply_stat_modifiers(unit)
		unit_leveled_up.emit(unit, state.level)
		_show_level_up_feedback(unit, state.level)
		print("[VeterancyTracker] %s leveled up to %s!" % [
			_get_unit_name(unit),
			state.get_level_name()
		])


## Awards kill XP (convenience method)
func award_kill_xp(unit: Node3D) -> void:
	var state: VeterancyState = get_state(unit)
	if state != null:
		state.record_kill()
	award_xp(unit, XPSource.KILL, XP_PER_KILL)


## Awards damage XP (convenience method)
func award_damage_xp(unit: Node3D, damage: float) -> void:
	var state: VeterancyState = get_state(unit)
	if state != null:
		state.record_damage(damage)
	var xp_amount: int = int(damage * XP_PER_DAMAGE_POINT)
	if xp_amount > 0:
		award_xp(unit, XPSource.DAMAGE, xp_amount)


## Awards survival XP (called periodically while under fire)
func award_survival_xp(unit: Node3D) -> void:
	var state: VeterancyState = get_state(unit)
	if state != null:
		state.record_survival_tick()
	award_xp(unit, XPSource.SURVIVAL, XP_PER_SURVIVAL_TICK)


## Awards objective XP (called by objectives system)
func award_objective_xp(unit: Node3D, kind: String) -> void:
	var state: VeterancyState = get_state(unit)
	if state != null:
		state.record_objective()

	# Different objectives might give different XP
	var amount: int = XP_PER_OBJECTIVE
	match kind:
		"capture_zone":
			amount = 75
		"evac_success":
			amount = 50
		"complete_order":
			amount = 25
		"destroy_target":
			amount = 100

	award_xp(unit, XPSource.OBJECTIVE, amount)


## Awards spotting XP (for recon units)
func award_spotting_xp(unit: Node3D) -> void:
	award_xp(unit, XPSource.SPOTTING, XP_PER_SPOT)


# =============================================================================
# STAT MODIFIER APPLICATION
# =============================================================================

## Applies veterancy stat modifiers to a unit's data
func apply_stat_modifiers(unit: Node3D) -> void:
	if not is_instance_valid(unit):
		return

	var state: VeterancyState = get_state(unit)
	if state == null:
		return

	# Ensure we have a cloned data
	_clone_unit_data(unit)

	var uid: int = unit.get_instance_id()
	var cloned_data: Variant = _unit_data_clones.get(uid)
	if cloned_data == null:
		return

	var mods: Dictionary = state.get_stat_modifiers()

	# Apply accuracy bonus
	if "accuracy" in cloned_data:
		var base: Variant = cloned_data.accuracy
		if base is float:
			cloned_data.accuracy = base * (1.0 + mods.get("accuracy_bonus", 0.0))

	# Apply HP bonus
	if "health_per_soldier" in cloned_data:
		var base: Variant = cloned_data.health_per_soldier
		if base is float:
			cloned_data.health_per_soldier = base * (1.0 + mods.get("hp_bonus", 0.0))

	# Apply reload bonus (reduces fire delay)
	if "fire_delay" in cloned_data:
		var base: Variant = cloned_data.fire_delay
		if base is float:
			cloned_data.fire_delay = base * (1.0 - mods.get("reload_bonus", 0.0))

	# Apply sight bonus
	if "sight_range" in cloned_data:
		var base: Variant = cloned_data.sight_range
		if base is float:
			cloned_data.sight_range = base * (1.0 + mods.get("sight_bonus", 0.0))

	# Store suppression resist on unit directly (checked in combat)
	if "suppression_resistance" in unit:
		unit.suppression_resistance = mods.get("suppression_resist", 0.0)


# =============================================================================
# PRIVATE HELPERS
# =============================================================================

## Clones unit data to avoid mutating shared resource
func _clone_unit_data(unit: Node3D) -> void:
	if not is_instance_valid(unit):
		return
	if not "data" in unit or unit.data == null:
		return

	var uid: int = unit.get_instance_id()

	# Only clone once
	if uid in _unit_data_clones:
		return

	# Clone the data resource
	var cloned: Resource = unit.data.duplicate()
	_unit_data_clones[uid] = cloned

	# Point unit to cloned data
	unit.data = cloned


## Applies tactic XP weight to an amount
func _apply_tactic_weight(source: int, amount: int) -> int:
	var roster_mgr: Node = get_node_or_null("/root/RosterManager")
	if roster_mgr == null or roster_mgr.active_tactic == null:
		return amount

	var source_name: String
	match source:
		XPSource.KILL:
			source_name = "kills"
		XPSource.DAMAGE:
			source_name = "damage"
		XPSource.SURVIVAL:
			source_name = "survival"
		XPSource.OBJECTIVE:
			source_name = "objectives"
		XPSource.SPOTTING:
			source_name = "spotting"
		_:
			return amount

	var weight: float = roster_mgr.active_tactic.get_xp_weight(source_name)
	return int(float(amount) * weight)


## Gets unit display name for logging
func _get_unit_name(unit: Node3D) -> String:
	if "data" in unit and unit.data != null and "display_name" in unit.data:
		return unit.data.display_name
	return unit.name


## Spawn floating XP text above unit
func _spawn_floating_xp_text(unit: Node3D, amount: int) -> void:
	if not is_instance_valid(unit):
		return

	# Create a simple 3D label that floats up and fades
	var label_3d := Label3D.new()
	label_3d.text = "+%d XP" % amount
	label_3d.font_size = 32
	label_3d.modulate = Color(0.9, 0.8, 0.2, 1.0)  # Gold color
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.no_depth_test = true
	label_3d.render_priority = 100

	# Position above unit
	label_3d.global_position = unit.global_position + Vector3(0, 3.0, 0)

	get_tree().current_scene.add_child(label_3d)

	# Animate float up and fade
	var tween := get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(label_3d, "global_position:y", label_3d.global_position.y + 2.0, 1.5)
	tween.tween_property(label_3d, "modulate:a", 0.0, 1.5)
	tween.set_parallel(false)
	tween.tween_callback(label_3d.queue_free)


## Show level-up visual and audio feedback
func _show_level_up_feedback(unit: Node3D, new_level: int) -> void:
	if not is_instance_valid(unit):
		return

	# Create level-up label
	var label_3d := Label3D.new()
	label_3d.text = "LEVEL UP!\n%s" % VeterancyState.LEVEL_NAMES[new_level]
	label_3d.font_size = 48
	label_3d.modulate = Color(1.0, 0.9, 0.3, 1.0)  # Bright gold
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.no_depth_test = true
	label_3d.render_priority = 101
	label_3d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Position above unit
	label_3d.global_position = unit.global_position + Vector3(0, 4.0, 0)

	get_tree().current_scene.add_child(label_3d)

	# Scale bounce + fade animation
	var tween := get_tree().create_tween()
	label_3d.scale = Vector3(0.5, 0.5, 0.5)
	tween.tween_property(label_3d, "scale", Vector3(1.2, 1.2, 1.2), 0.2)
	tween.tween_property(label_3d, "scale", Vector3(1.0, 1.0, 1.0), 0.1)
	tween.tween_interval(1.0)
	tween.tween_property(label_3d, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label_3d.queue_free)

	# Play audio if AudioManager exists
	var audio_mgr: Node = get_node_or_null("/root/AudioManager")
	if audio_mgr and audio_mgr.has_method("play_ui_sound"):
		audio_mgr.play_ui_sound("level_up")
