class_name SquadMorale extends RefCounted
## Squad-level morale component for RealVietnamRTS
## Tracks morale state, handles events, continuous modifiers, and routing behavior

signal morale_changed(current: float, maximum: float)
signal state_changed(old_state: String, new_state: String)
signal unit_broken  ## Emitted when unit breaks and starts routing
signal unit_rallied ## Emitted when unit recovers from broken state
signal unit_shattered ## Emitted when unit becomes completely uncontrollable

# =============================================================================
# STATE
# =============================================================================

var current_morale: float = 100.0
var max_morale: float = 100.0

## Training level affects morale resistance (0=CONSCRIPT, 1=REGULAR, 2=VETERAN, 3=ELITE)
var training_level: int = 1

## Current morale state
var current_state: String = "STEADY"

## Active continuous modifiers: { "modifier_name": value }
var _continuous_modifiers: Dictionary = {}

## Rally tracking
var _time_in_safety: float = 0.0
var _is_rallying: bool = false
var _is_routing: bool = false

## Route tracking
var _route_timer: float = 0.0
var _ignore_orders_timer: float = 0.0

## Reference to owning squad (set on init)
var _squad: Node = null

## Suppression-morale integration (Phase 4.3)
var _suppression_duration: float = 0.0          # How long unit has been suppressed
var _last_suppression_level: float = 0.0        # Track for relief detection
var _suppression_rout_check_timer: float = 0.0  # Timer for rout chance checks
var _prolonged_pinned_timer: float = 0.0        # Timer for prolonged pinned penalty

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(squad: Node = null, training: int = 1) -> void:
	_squad = squad
	training_level = training
	current_morale = max_morale
	current_state = MoraleConstants.get_state_name(current_morale)


## Initialize from SquadData
func init_from_data(squad: Node, data: SquadData) -> void:
	_squad = squad
	training_level = data.training_level
	max_morale = 100.0
	current_morale = max_morale
	current_state = MoraleConstants.get_state_name(current_morale)

# =============================================================================
# UPDATE LOOP
# =============================================================================

## Call every frame with delta time
func tick(delta: float) -> void:
	# Process suppression-morale integration (Phase 4.3)
	_process_suppression_morale(delta)

	# Process continuous modifiers
	_process_continuous_modifiers(delta)

	# Check for rally
	_process_rally(delta)

	# Process routing behavior
	_process_routing(delta)

	# Update state
	_update_state()


## Process suppression-morale integration (Phase 4.3)
## Links suppression system to morale with sustained fire penalties and rout checks
func _process_suppression_morale(delta: float) -> void:
	var current_suppression: float = _get_squad_suppression()
	var is_suppressed: bool = _continuous_modifiers.has("suppressed")
	var is_pinned: bool = _continuous_modifiers.has("pinned")
	var is_under_fire: bool = _continuous_modifiers.has("under_fire")

	# Track suppression duration for escalation
	if is_suppressed or is_pinned:
		_suppression_duration += delta

		# Apply sustained suppression penalty after threshold
		if _suppression_duration >= MoraleConstants.SUPPRESSION_ESCALATION_TIME:
			var escalation_mult: float = minf(_suppression_duration / MoraleConstants.SUPPRESSION_ESCALATION_TIME, 3.0)
			set_modifier("sustained_suppression", MoraleConstants.MOD_SUSTAINED_SUPPRESSION * escalation_mult)

		# Track prolonged pinned for event penalty
		if is_pinned:
			_prolonged_pinned_timer += delta
			if _prolonged_pinned_timer >= MoraleConstants.PROLONGED_PINNED_THRESHOLD:
				apply_event(MoraleConstants.EVENT_PROLONGED_PINNED)
				_prolonged_pinned_timer = 0.0  # Reset after applying penalty
		else:
			_prolonged_pinned_timer = 0.0

		# Check for suppression-induced rout when pinned with low morale
		if is_pinned and current_morale < MoraleConstants.STATE_SHAKEN_MIN:
			_suppression_rout_check_timer += delta
			if _suppression_rout_check_timer >= MoraleConstants.SUPPRESSION_ROUT_CHECK_INTERVAL:
				_suppression_rout_check_timer = 0.0
				_check_suppression_rout()
	else:
		# Not suppressed - check for relief and reset timers
		if _suppression_duration > 0.0:
			# Check for suppression relief (morale boost when pressure lifts)
			var suppression_drop: float = _last_suppression_level - current_suppression
			if suppression_drop >= MoraleConstants.SUPPRESSION_RELIEF_THRESHOLD:
				apply_event(MoraleConstants.EVENT_SUPPRESSION_RELIEF)

		_suppression_duration = 0.0
		_prolonged_pinned_timer = 0.0
		_suppression_rout_check_timer = 0.0
		clear_modifier("sustained_suppression")

	# Gradual morale recovery when not under fire
	if not is_under_fire and not is_suppressed and not is_pinned:
		# Small passive recovery when safe from fire (complements rally system)
		if current_morale < max_morale and current_morale >= MoraleConstants.STATE_SHAKEN_MIN:
			var recovery: float = 0.1 * delta  # Very slow passive recovery
			_apply_morale_change(recovery)

	_last_suppression_level = current_suppression


## Check if unit routs due to high suppression and low morale
func _check_suppression_rout() -> void:
	if _is_routing:
		return  # Already routing

	# Calculate rout chance
	var base_chance: float = MoraleConstants.SUPPRESSION_ROUT_CHANCE_BASE

	# Increase chance based on how far below SHAKEN threshold we are
	var morale_deficit: float = MoraleConstants.STATE_SHAKEN_MIN - current_morale
	var deficit_mult: float = morale_deficit / 10.0  # Per 10 morale
	base_chance += MoraleConstants.SUPPRESSION_ROUT_CHANCE_PER_10_MORALE * deficit_mult

	# Training reduces rout chance
	var training_mult: float = MoraleConstants.get_training_multiplier(training_level)
	var final_chance: float = base_chance / training_mult

	# Roll for rout
	if randf() < final_chance:
		# Force rout - drop morale to BROKEN threshold
		current_morale = minf(current_morale, MoraleConstants.STATE_SHATTERED_MAX + 1.0)
		_is_routing = true
		unit_broken.emit()
		morale_changed.emit(current_morale, max_morale)


## Get current suppression level from squad
func _get_squad_suppression() -> float:
	if _squad and _squad.has_method("get"):
		var level: Variant = _squad.get("suppression_level")
		if level is float:
			return level
	return 0.0


## Process all active continuous modifiers
func _process_continuous_modifiers(delta: float) -> void:
	var total_modifier: float = 0.0

	for modifier_name: String in _continuous_modifiers:
		var value: Variant = _continuous_modifiers[modifier_name]
		if value is float:
			total_modifier += value

	# Apply training resistance (better trained = less affected by negative)
	var training_mult: float = MoraleConstants.get_training_multiplier(training_level)
	if total_modifier < 0:
		total_modifier /= training_mult  # Reduced negative impact
	else:
		total_modifier *= training_mult  # Increased positive impact

	# Apply modifier
	if total_modifier != 0.0:
		_apply_morale_change(total_modifier * delta)


## Process rally mechanics
func _process_rally(delta: float) -> void:
	if _is_routing:
		_time_in_safety = 0.0
		_is_rallying = false
		return

	# Check if in safety
	var is_safe: bool = _check_safety()

	if is_safe:
		_time_in_safety += delta
	else:
		_time_in_safety = 0.0
		_is_rallying = false
		return

	# Start rally after safety threshold
	if _time_in_safety >= MoraleConstants.RALLY_SAFETY_TIME:
		if current_morale >= MoraleConstants.RALLY_MIN_THRESHOLD and current_morale < MoraleConstants.RALLY_TARGET:
			_is_rallying = true

	# Apply rally recovery
	if _is_rallying:
		var rally_rate: float = MoraleConstants.RALLY_RECOVERY_RATE
		rally_rate *= MoraleConstants.get_rally_multiplier(training_level)

		# Bonus for being at firebase
		if _continuous_modifiers.has("near_firebase"):
			rally_rate += MoraleConstants.RALLY_FIREBASE_BONUS

		_apply_morale_change(rally_rate * delta)

		# Stop rallying at target
		if current_morale >= MoraleConstants.RALLY_TARGET:
			_is_rallying = false
			unit_rallied.emit()


## Process routing behavior
func _process_routing(delta: float) -> void:
	if not _is_routing:
		_ignore_orders_timer = 0.0
		return

	_route_timer += delta
	_ignore_orders_timer += delta

	# Check if can stop routing (reached safety or rallied)
	if current_morale >= MoraleConstants.STATE_SHAKEN_MIN:
		_is_routing = false
		_route_timer = 0.0


## Check if unit is in a safe location for rally
func _check_safety() -> bool:
	if _squad == null:
		return true

	# Check if under fire (has under_fire modifier)
	if _continuous_modifiers.has("under_fire"):
		return false

	# Check if suppressed
	if _continuous_modifiers.has("suppressed") or _continuous_modifiers.has("pinned"):
		return false

	# Check distance from enemies via SpatialHashGrid
	if Engine.has_singleton("SpatialHashGrid") or is_instance_valid(SpatialHashGrid):
		var enemies: Array = SpatialHashGrid.get_enemies_in_radius(
			_squad.global_position,
			MoraleConstants.RALLY_SAFE_DISTANCE,
			_get_faction()
		)
		if enemies.size() > 0:
			return false

	return true


func _get_faction() -> int:
	if _squad and _squad.has_method("get_faction"):
		return _squad.get_faction()
	return 0

# =============================================================================
# MORALE EVENTS (one-time changes)
# =============================================================================

## Apply a morale event
func apply_event(event_value: float) -> void:
	# Training affects event impact
	var training_mult: float = MoraleConstants.get_training_multiplier(training_level)

	if event_value < 0:
		event_value /= training_mult  # Reduced negative impact for trained units
	else:
		event_value *= training_mult  # Increased positive impact

	_apply_morale_change(event_value)


## Convenience methods for common events
func on_casualty(count: int = 1) -> void:
	if count == 1:
		apply_event(MoraleConstants.EVENT_CASUALTY_LIGHT)
	else:
		apply_event(MoraleConstants.EVENT_CASUALTY_HEAVY)


func on_enemy_killed() -> void:
	apply_event(MoraleConstants.EVENT_KILL_ENEMY)


func on_vehicle_destroyed() -> void:
	apply_event(MoraleConstants.EVENT_DESTROY_VEHICLE)


func on_ambushed() -> void:
	apply_event(MoraleConstants.EVENT_AMBUSHED)


func on_flanked() -> void:
	apply_event(MoraleConstants.EVENT_FLANKED)


func on_officer_killed() -> void:
	apply_event(MoraleConstants.EVENT_OFFICER_KILLED)


func on_hq_destroyed() -> void:
	apply_event(MoraleConstants.EVENT_HQ_DESTROYED)


func on_reinforcements() -> void:
	apply_event(MoraleConstants.EVENT_REINFORCEMENTS_ARRIVE)


func on_air_support() -> void:
	apply_event(MoraleConstants.EVENT_AIR_SUPPORT_CALLED)


func on_tunnel_breach() -> void:
	apply_event(MoraleConstants.EVENT_TUNNEL_BREACH)


func on_booby_trap() -> void:
	apply_event(MoraleConstants.EVENT_BOOBY_TRAP)

# =============================================================================
# CONTINUOUS MODIFIERS
# =============================================================================

## Set a continuous modifier (active while condition true)
func set_modifier(name: String, value: float) -> void:
	_continuous_modifiers[name] = value


## Remove a continuous modifier
func clear_modifier(name: String) -> void:
	_continuous_modifiers.erase(name)


## Check if modifier is active
func has_modifier(name: String) -> bool:
	return _continuous_modifiers.has(name)


## Clear all modifiers
func clear_all_modifiers() -> void:
	_continuous_modifiers.clear()


## Convenience methods for common modifiers
func set_under_fire(active: bool) -> void:
	if active:
		set_modifier("under_fire", MoraleConstants.MOD_UNDER_FIRE)
	else:
		clear_modifier("under_fire")


func set_suppressed(level: int) -> void:
	# level: 0=none, 1=suppressed, 2=pinned
	clear_modifier("suppressed")
	clear_modifier("pinned")

	match level:
		1:
			set_modifier("suppressed", MoraleConstants.MOD_SUPPRESSED)
		2:
			set_modifier("pinned", MoraleConstants.MOD_PINNED)


func set_in_cover(has_cover: bool) -> void:
	if has_cover:
		set_modifier("in_cover", MoraleConstants.MOD_IN_COVER)
	else:
		clear_modifier("in_cover")


func set_in_bunker(in_bunker: bool) -> void:
	if in_bunker:
		set_modifier("in_bunker", MoraleConstants.MOD_IN_BUNKER)
	else:
		clear_modifier("in_bunker")


func set_near_firebase(near: bool) -> void:
	if near:
		set_modifier("near_firebase", MoraleConstants.MOD_NEAR_FIREBASE)
	else:
		clear_modifier("near_firebase")


func set_nearby_allies(count: int) -> void:
	var clamped: int = mini(count, 3)  # Max 3 stacks
	if clamped > 0:
		set_modifier("nearby_allies", MoraleConstants.MOD_NEARBY_ALLIES * clamped)
	else:
		clear_modifier("nearby_allies")


func set_low_ammo(is_low: bool) -> void:
	if is_low:
		set_modifier("low_ammo", MoraleConstants.MOD_LOW_AMMO)
	else:
		clear_modifier("low_ammo")


func set_low_water(is_low: bool) -> void:
	if is_low:
		set_modifier("low_water", MoraleConstants.MOD_LOW_WATER)
	else:
		clear_modifier("low_water")


func set_no_ammo(is_empty: bool) -> void:
	if is_empty:
		set_modifier("no_ammo", MoraleConstants.MOD_NO_AMMO)
	else:
		clear_modifier("no_ammo")


func set_no_water(is_empty: bool) -> void:
	if is_empty:
		set_modifier("no_water", MoraleConstants.MOD_NO_WATER)
	else:
		clear_modifier("no_water")


## Update suppression level from external source (for suppression relief detection)
## Called by squad when suppression changes significantly
func notify_suppression_change(old_level: float, new_level: float) -> void:
	# Check for immediate relief (large drop in suppression)
	var drop: float = old_level - new_level
	if drop >= MoraleConstants.SUPPRESSION_RELIEF_THRESHOLD and new_level < 0.3:
		# Only give relief if we were significantly suppressed before
		if old_level >= 0.5:
			apply_event(MoraleConstants.EVENT_SUPPRESSION_RELIEF)


## Get how long unit has been under sustained suppression
func get_suppression_duration() -> float:
	return _suppression_duration


## Check if unit is experiencing sustained suppression (escalated morale drain)
func is_under_sustained_suppression() -> bool:
	return _suppression_duration >= MoraleConstants.SUPPRESSION_ESCALATION_TIME

# =============================================================================
# INTERNAL
# =============================================================================

func _apply_morale_change(amount: float) -> void:
	var old_morale: float = current_morale
	current_morale = clampf(current_morale + amount, 0.0, max_morale)

	if current_morale != old_morale:
		morale_changed.emit(current_morale, max_morale)


func _update_state() -> void:
	var new_state: String = MoraleConstants.get_state_name(current_morale)

	if new_state != current_state:
		var old_state: String = current_state
		current_state = new_state
		state_changed.emit(old_state, new_state)

		# Check for broken/shattered transitions
		if new_state == "BROKEN" and old_state != "SHATTERED":
			_is_routing = true
			unit_broken.emit()
		elif new_state == "SHATTERED":
			_is_routing = true
			unit_shattered.emit()

# =============================================================================
# PUBLIC GETTERS
# =============================================================================

func get_morale() -> float:
	return current_morale


func get_morale_percent() -> float:
	return current_morale / max_morale if max_morale > 0 else 0.0


func get_state() -> String:
	return current_state


func is_broken() -> bool:
	return current_state == "BROKEN" or current_state == "SHATTERED"


func is_shattered() -> bool:
	return current_state == "SHATTERED"


func is_routing() -> bool:
	return _is_routing


func is_rallying() -> bool:
	return _is_rallying


func can_receive_orders() -> bool:
	if is_shattered():
		return false
	if _is_routing and _ignore_orders_timer < MoraleConstants.ROUTE_IGNORE_ORDERS_TIME:
		return false
	return true


func get_accuracy_multiplier() -> float:
	return MoraleConstants.get_accuracy_multiplier(current_morale)


func get_rof_multiplier() -> float:
	return MoraleConstants.get_rof_multiplier(current_morale)


func get_speed_multiplier() -> float:
	if _is_routing:
		return MoraleConstants.ROUTE_SPEED_MULTIPLIER
	return 1.0


## Get current suppression-induced stress level (0.0 to 1.0)
## Higher values mean unit is closer to breaking from suppression
func get_suppression_stress() -> float:
	if _suppression_duration <= 0.0:
		return 0.0

	# Calculate stress based on suppression duration and morale
	var duration_factor: float = minf(_suppression_duration / MoraleConstants.SUPPRESSION_ESCALATION_TIME, 1.0)
	var morale_factor: float = 1.0 - (current_morale / max_morale)

	return clampf(duration_factor * 0.5 + morale_factor * 0.5, 0.0, 1.0)
