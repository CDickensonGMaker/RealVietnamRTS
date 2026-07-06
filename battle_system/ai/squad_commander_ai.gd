class_name SquadCommanderAI
extends RefCounted

## Squad Commander AI - Per-squad tactical decision making via behavior tree.
## Ported from BP RTS DARK SHADOWS CommanderAI and adapted for Vietnam RTS.
##
## Each squad gets one SquadCommanderAI that:
## - Maintains a blackboard with current state
## - Runs a behavior tree for tactical decisions
## - Responds to threats, suppression, and orders
## - Coordinates with AITickManager for staggered processing

const BTNode = preload("res://battle_system/ai/behavior_tree/bt_node.gd")
const BTComposite = preload("res://battle_system/ai/behavior_tree/bt_composite.gd")

## Stance affects engagement range and behavior
enum Stance { DEFENSIVE, AGGRESSIVE, WITHDRAWING }

## The squad we control
var squad: Node3D = null

## Blackboard - shared state for all behavior tree nodes
var blackboard: Dictionary = {}

## Current stance
var stance: Stance = Stance.DEFENSIVE

## Behavior tree root
var behavior_tree: RefCounted = null  # BTNode

## Current target (cached for quick access)
var current_target: Node = null

## Faction for threat assessment
var faction: int = 0


func _init(controlled_squad: Node3D) -> void:
	squad = controlled_squad
	_init_blackboard()
	_build_behavior_tree()


## Initialize the blackboard with default values.
func _init_blackboard() -> void:
	# Get faction from squad
	if squad and squad.data:
		faction = squad.data.faction

	blackboard = {
		"squad": squad,
		"target": null,
		"stance": stance,
		"is_suppressed": false,
		"suppression_level": 0.0,
		"is_routing": false,
		"is_engaged": false,
		"cover_position": Vector3.ZERO,
		"has_cover": false,
		"ammo_status": "full",  # full, low, empty
		"health_ratio": 1.0,
		"faction": faction,
		"last_damage_source": null,
		"threat_direction": Vector3.ZERO,
		"in_ambush": false,
		"ambush_triggered": false,
	}


## Build the behavior tree based on faction.
func _build_behavior_tree() -> void:
	# Determine faction type
	var is_player: bool = _is_player_faction()
	var is_vc: bool = faction == GameEnums.Faction.VC
	var is_nva: bool = faction == GameEnums.Faction.NVA

	if is_vc:
		behavior_tree = _build_vc_tree()
	elif is_nva:
		behavior_tree = _build_nva_tree()
	else:
		behavior_tree = _build_us_tree()

	# Setup tree with squad and blackboard
	if behavior_tree:
		behavior_tree.setup(squad, blackboard)


## Build US/ARVN behavior tree (conventional tactics).
## Priority: Routing > Suppressed > Engaged > Acquire > Idle
func _build_us_tree() -> RefCounted:
	var root := BTComposite.Selector.new("US_Root")

	# 1. Routing behavior - flee to safety
	var routing_seq := BTComposite.Sequence.new("Routing")
	routing_seq.add_child(BTCondition.new("IsRouting", func(): return blackboard.get("is_routing", false)))
	routing_seq.add_child(TaskRetreat.new())
	root.add_child(routing_seq)

	# 2. Suppressed behavior - seek cover, return fire
	var suppressed_seq := BTComposite.Sequence.new("Suppressed")
	suppressed_seq.add_child(BTCondition.new("IsSuppressed", func(): return blackboard.get("is_suppressed", false)))
	suppressed_seq.add_child(BTComposite.Selector.new("SuppressedActions")
		.add_child(BTComposite.Sequence.new("SeekCover")
			.add_child(BTCondition.new("NeedsCover", func(): return not blackboard.get("has_cover", false)))
			.add_child(TaskSeekCover.new()))
		.add_child(TaskFireAtTarget.new()))  # Return fire from cover
	root.add_child(suppressed_seq)

	# 3. Engaged behavior - fire at target
	var engaged_seq := BTComposite.Sequence.new("Engaged")
	engaged_seq.add_child(BTCondition.new("HasTarget", func(): return _has_valid_target()))
	engaged_seq.add_child(TaskFireAtTarget.new())
	root.add_child(engaged_seq)

	# 4. Acquire target
	var acquire_seq := BTComposite.Sequence.new("Acquire")
	acquire_seq.add_child(TaskAcquireTarget.new())
	acquire_seq.add_child(TaskFireAtTarget.new())
	root.add_child(acquire_seq)

	# 5. Idle - hold position
	root.add_child(TaskIdle.new())

	return root


## Build VC behavior tree (guerrilla tactics).
## Priority: Routing > Ambush > HitAndRun > Engaged > Conceal
func _build_vc_tree() -> RefCounted:
	var root := BTComposite.Selector.new("VC_Root")

	# 1. Routing behavior - flee to tunnel/jungle
	var routing_seq := BTComposite.Sequence.new("Routing")
	routing_seq.add_child(BTCondition.new("IsRouting", func(): return blackboard.get("is_routing", false)))
	routing_seq.add_child(TaskRetreat.new())
	root.add_child(routing_seq)

	# 2. Ambush behavior - wait concealed, spring on trigger
	var ambush_seq := BTComposite.Sequence.new("Ambush")
	ambush_seq.add_child(BTCondition.new("InAmbush", func(): return blackboard.get("in_ambush", false)))
	ambush_seq.add_child(BTComposite.Selector.new("AmbushActions")
		.add_child(BTComposite.Sequence.new("SpringAmbush")
			.add_child(BTCondition.new("AmbushTriggered", func(): return blackboard.get("ambush_triggered", false)))
			.add_child(TaskFireAtTarget.new()))
		.add_child(TaskAmbush.new()))  # Wait concealed
	root.add_child(ambush_seq)

	# 3. Hit-and-run behavior - disengage when wounded
	var hitrun_seq := BTComposite.Sequence.new("HitAndRun")
	hitrun_seq.add_child(BTCondition.new("Wounded", func(): return blackboard.get("health_ratio", 1.0) < 0.5))
	hitrun_seq.add_child(BTCondition.new("HasTarget", func(): return _has_valid_target()))
	hitrun_seq.add_child(TaskHitAndRun.new())
	root.add_child(hitrun_seq)

	# 4. Engaged behavior - fire and move
	var engaged_seq := BTComposite.Sequence.new("Engaged")
	engaged_seq.add_child(BTCondition.new("HasTarget", func(): return _has_valid_target()))
	engaged_seq.add_child(TaskFireAtTarget.new())
	root.add_child(engaged_seq)

	# 5. Acquire target
	var acquire_seq := BTComposite.Sequence.new("Acquire")
	acquire_seq.add_child(TaskAcquireTarget.new())
	acquire_seq.add_child(TaskFireAtTarget.new())
	root.add_child(acquire_seq)

	# 6. Concealment - find hiding spot
	root.add_child(TaskConceal.new())

	return root


## Build NVA behavior tree (conventional assault tactics).
## Priority: Routing > Assault > Engaged > Acquire > Hold
func _build_nva_tree() -> RefCounted:
	var root := BTComposite.Selector.new("NVA_Root")

	# 1. Routing behavior - orderly withdrawal
	var routing_seq := BTComposite.Sequence.new("Routing")
	routing_seq.add_child(BTCondition.new("IsRouting", func(): return blackboard.get("is_routing", false)))
	routing_seq.add_child(TaskRetreat.new())
	root.add_child(routing_seq)

	# 2. Human wave assault (when ordered and have numbers)
	var assault_seq := BTComposite.Sequence.new("HumanWave")
	assault_seq.add_child(BTCondition.new("AssaultOrdered", func(): return stance == Stance.AGGRESSIVE))
	assault_seq.add_child(BTCondition.new("HasTarget", func(): return _has_valid_target()))
	assault_seq.add_child(TaskHumanWave.new())
	root.add_child(assault_seq)

	# 3. Suppressed behavior - return fire, advance
	var suppressed_seq := BTComposite.Sequence.new("Suppressed")
	suppressed_seq.add_child(BTCondition.new("IsSuppressed", func(): return blackboard.get("is_suppressed", false)))
	suppressed_seq.add_child(TaskFireAtTarget.new())  # NVA keeps firing under suppression
	root.add_child(suppressed_seq)

	# 4. Engaged behavior - fire at target
	var engaged_seq := BTComposite.Sequence.new("Engaged")
	engaged_seq.add_child(BTCondition.new("HasTarget", func(): return _has_valid_target()))
	engaged_seq.add_child(TaskFireAtTarget.new())
	root.add_child(engaged_seq)

	# 5. Acquire target
	var acquire_seq := BTComposite.Sequence.new("Acquire")
	acquire_seq.add_child(TaskAcquireTarget.new())
	acquire_seq.add_child(TaskFireAtTarget.new())
	root.add_child(acquire_seq)

	# 6. Hold position
	root.add_child(TaskIdle.new())

	return root


## Main tick function - called by AITickManager every ~2s (staggered).
func tick(delta: float) -> void:
	if not is_instance_valid(squad):
		return
	if squad.state == Squad.State.DEAD:
		return

	# Update blackboard from squad state
	_update_blackboard()

	# Run behavior tree
	if behavior_tree:
		behavior_tree.tick(delta)


## Update blackboard from current squad state.
func _update_blackboard() -> void:
	if not is_instance_valid(squad):
		return

	# Suppression state
	var suppression: float = squad.suppression_level if "suppression_level" in squad else 0.0
	blackboard["suppression_level"] = suppression
	blackboard["is_suppressed"] = suppression > 0.3  # CAUTIOUS threshold

	# Routing state
	blackboard["is_routing"] = squad.state == Squad.State.ROUTING

	# Combat state
	blackboard["is_engaged"] = squad.state == Squad.State.COMBAT

	# Health
	var health_ratio: float = 1.0
	if squad.max_health > 0:
		health_ratio = squad.current_health / squad.max_health
	blackboard["health_ratio"] = health_ratio

	# Ammo
	if "current_ammo" in squad and "max_ammo" in squad:
		var ammo_ratio: float = float(squad.current_ammo) / float(maxi(squad.max_ammo, 1))
		if ammo_ratio <= 0.0:
			blackboard["ammo_status"] = "empty"
		elif ammo_ratio < 0.2:
			blackboard["ammo_status"] = "low"
		else:
			blackboard["ammo_status"] = "full"

	# Cover
	blackboard["has_cover"] = squad.is_in_cover if "is_in_cover" in squad else false

	# Target validation
	if current_target and not is_instance_valid(current_target):
		current_target = null
	blackboard["target"] = current_target

	# Last damage source for threat direction
	if "_last_damage_source" in squad and squad._last_damage_source:
		blackboard["last_damage_source"] = squad._last_damage_source
		if is_instance_valid(squad._last_damage_source):
			var dir: Vector3 = (squad._last_damage_source.global_position - squad.global_position).normalized()
			blackboard["threat_direction"] = dir


## Check if we have a valid target.
func _has_valid_target() -> bool:
	if not current_target:
		return false
	if not is_instance_valid(current_target):
		current_target = null
		return false
	if current_target.has_method("is_dead") and current_target.is_dead():
		current_target = null
		return false
	return true


## Check if faction is player-controlled.
func _is_player_faction() -> bool:
	return faction == GameEnums.Faction.US_ARMY or faction == GameEnums.Faction.ARVN


## Set stance.
func set_stance(new_stance: Stance) -> void:
	stance = new_stance
	blackboard["stance"] = stance


## Set target.
func set_target(target: Node) -> void:
	current_target = target
	blackboard["target"] = target


## Clear target.
func clear_target() -> void:
	current_target = null
	blackboard["target"] = null


## Get the controlled squad.
func get_squad() -> Node3D:
	return squad


## Set ambush mode.
func set_ambush_mode(enabled: bool) -> void:
	blackboard["in_ambush"] = enabled
	blackboard["ambush_triggered"] = false


## Trigger ambush (enemy entered kill zone).
func trigger_ambush() -> void:
	blackboard["ambush_triggered"] = true


# =============================================================================
# CONDITION NODE
# =============================================================================

## BTCondition - Leaf node that evaluates a condition
class BTCondition extends BTNode:
	var condition: Callable

	func _init(node_name: String, cond: Callable) -> void:
		super._init(node_name)
		condition = cond

	func tick(_delta: float) -> Status:
		if condition.call():
			return Status.SUCCESS
		return Status.FAILURE


# =============================================================================
# TASK NODES (Leaf behaviors)
# =============================================================================

## TaskIdle - Hold position, do nothing
class TaskIdle extends BTNode:
	func _init() -> void:
		super._init("Idle")

	func tick(_delta: float) -> Status:
		# Just idle - no action needed
		return Status.SUCCESS


## TaskAcquireTarget - Find a target to engage
class TaskAcquireTarget extends BTNode:
	const ACQUISITION_RANGE_DEFENSIVE: float = 50.0
	const ACQUISITION_RANGE_AGGRESSIVE: float = 120.0

	func _init() -> void:
		super._init("AcquireTarget")

	func tick(_delta: float) -> Status:
		if not is_instance_valid(actor):
			return Status.FAILURE

		# Determine range based on stance
		var stance_val = blackboard.get("stance", SquadCommanderAI.Stance.DEFENSIVE)
		var max_range: float = ACQUISITION_RANGE_DEFENSIVE
		if stance_val == SquadCommanderAI.Stance.AGGRESSIVE:
			max_range = ACQUISITION_RANGE_AGGRESSIVE

		# Find nearest enemy
		var target = _find_nearest_enemy(max_range)
		if target:
			blackboard["target"] = target
			return Status.SUCCESS

		return Status.FAILURE

	func _find_nearest_enemy(max_range: float) -> Node:
		if not is_instance_valid(actor):
			return null

		var my_faction: int = blackboard.get("faction", 0)

		# Use SpatialHashGrid for efficient enemy lookup
		if not SpatialHashGrid:
			return null

		var nearest: Node3D = SpatialHashGrid.get_nearest_enemy(
			actor.global_position, my_faction, max_range
		)

		# Validate target is alive
		if nearest and nearest.has_method("is_dead") and nearest.is_dead():
			return null

		return nearest


## TaskFireAtTarget - Fire at current target
class TaskFireAtTarget extends BTNode:
	func _init() -> void:
		super._init("FireAtTarget")

	func tick(_delta: float) -> Status:
		var target = blackboard.get("target")
		if not target or not is_instance_valid(target):
			return Status.FAILURE

		if not is_instance_valid(actor):
			return Status.FAILURE

		# Check ammo
		if blackboard.get("ammo_status", "full") == "empty":
			return Status.FAILURE

		# Face target (must be in tree to call look_at)
		var dir: Vector3 = (target.global_position - actor.global_position).normalized()
		if dir.length() > 0.1 and actor.is_inside_tree():
			actor.look_at(target.global_position)

		# Fire at target using squad's attack method
		if actor.has_method("attack"):
			actor.attack(target)
		elif actor.has_method("_fire_at_target"):
			actor._fire_at_target(target)

		return Status.RUNNING  # Keep firing


## TaskSeekCover - Move to nearby cover
class TaskSeekCover extends BTNode:
	const COVER_SEEK_RADIUS: float = 15.0

	func _init() -> void:
		super._init("SeekCover")

	func tick(_delta: float) -> Status:
		if not is_instance_valid(actor):
			return Status.FAILURE

		# Already in cover?
		if blackboard.get("has_cover", false):
			return Status.SUCCESS

		# Find cover position
		var cover_pos: Vector3 = blackboard.get("cover_position", Vector3.ZERO)
		if cover_pos == Vector3.ZERO:
			cover_pos = _find_cover_position()
			blackboard["cover_position"] = cover_pos

		if cover_pos == Vector3.ZERO:
			return Status.FAILURE  # No cover found

		# Move to cover
		if actor.has_method("move_to"):
			actor.move_to(cover_pos)
		elif actor.has_method("set_destination"):
			actor.set_destination(cover_pos)

		# Check if arrived
		var dist: float = actor.global_position.distance_to(cover_pos)
		if dist < 2.0:
			blackboard["has_cover"] = true
			blackboard["cover_position"] = Vector3.ZERO
			return Status.SUCCESS

		return Status.RUNNING

	func _find_cover_position() -> Vector3:
		# Look for cover in opposite direction of threat
		var threat_dir: Vector3 = blackboard.get("threat_direction", Vector3.ZERO)
		if threat_dir == Vector3.ZERO:
			threat_dir = Vector3.FORWARD

		# Search for cover objects nearby
		# This would query terrain/structures for cover positions
		# For now, just move away from threat
		var cover_dir: Vector3 = -threat_dir
		cover_dir = cover_dir.rotated(Vector3.UP, randf_range(-0.5, 0.5))
		return actor.global_position + cover_dir * randf_range(5.0, COVER_SEEK_RADIUS)


## TaskRetreat - Flee to safety using threat heatmap
class TaskRetreat extends BTNode:
	func _init() -> void:
		super._init("Retreat")

	func tick(_delta: float) -> Status:
		if not is_instance_valid(actor):
			return Status.FAILURE

		# Get retreat position from AITickManager
		var retreat_pos: Vector3 = _get_retreat_position()

		# Move to retreat position
		if actor.has_method("move_to"):
			actor.move_to(retreat_pos)
		elif actor.has_method("set_destination"):
			actor.set_destination(retreat_pos)

		# Check if we've reached relative safety
		var my_faction: int = blackboard.get("faction", 0)
		var threat: float = _get_threat_at_position(actor.global_position, my_faction)
		if threat < 10.0:  # Low threat = safe enough
			return Status.SUCCESS

		return Status.RUNNING

	func _get_retreat_position() -> Vector3:
		var my_faction: int = blackboard.get("faction", 0)

		# Try to use AITickManager if available
		var tick_mgr: Node = actor.get_node_or_null("/root/AITickManager") if actor else null
		if tick_mgr:
			return tick_mgr.get_safest_retreat_position(
				actor.global_position,
				my_faction,
				60.0
			)

		# Fallback: retreat away from threat direction
		var threat_dir: Vector3 = blackboard.get("threat_direction", Vector3.FORWARD)
		return actor.global_position - threat_dir * 60.0

	func _get_threat_at_position(pos: Vector3, faction: int) -> float:
		var tick_mgr: Node = actor.get_node_or_null("/root/AITickManager") if actor else null
		if tick_mgr:
			return tick_mgr.get_threat_at(pos, faction)
		return 0.0


## TaskAmbush - Wait in concealment for enemy
class TaskAmbush extends BTNode:
	func _init() -> void:
		super._init("Ambush")

	func tick(_delta: float) -> Status:
		# Just wait - ambush is triggered externally
		if blackboard.get("ambush_triggered", false):
			return Status.SUCCESS  # Proceed to engage
		return Status.RUNNING  # Keep waiting


## TaskHitAndRun - Fire then disengage
class TaskHitAndRun extends BTNode:
	var _fire_time: float = 0.0
	const FIRE_DURATION: float = 2.0  # Fire for 2 seconds then run

	func _init() -> void:
		super._init("HitAndRun")

	func tick(delta: float) -> Status:
		if not is_instance_valid(actor):
			return Status.FAILURE

		var target = blackboard.get("target")

		# Fire phase
		if _fire_time < FIRE_DURATION:
			_fire_time += delta
			if target and is_instance_valid(target):
				if actor.has_method("attack"):
					actor.attack(target)
			return Status.RUNNING

		# Run phase - disengage
		var threat_dir: Vector3 = blackboard.get("threat_direction", Vector3.FORWARD)
		var escape_pos: Vector3 = actor.global_position - threat_dir * 40.0

		if actor.has_method("move_to"):
			actor.move_to(escape_pos)

		# Reset for next cycle
		_fire_time = 0.0
		return Status.SUCCESS

	func reset() -> void:
		_fire_time = 0.0


## TaskConceal - Find hiding spot (VC specialty)
class TaskConceal extends BTNode:
	func _init() -> void:
		super._init("Conceal")

	func tick(_delta: float) -> Status:
		if not is_instance_valid(actor):
			return Status.FAILURE

		# Find concealment (jungle, tunnel entrance, village)
		var conceal_pos: Vector3 = _find_concealment()

		if conceal_pos == Vector3.ZERO:
			return Status.FAILURE

		# Move to concealment
		if actor.has_method("move_to"):
			actor.move_to(conceal_pos)

		var dist: float = actor.global_position.distance_to(conceal_pos)
		if dist < 3.0:
			return Status.SUCCESS

		return Status.RUNNING

	func _find_concealment() -> Vector3:
		# Would query terrain for jungle/tunnel/village
		# For now, just find a spot away from enemies
		var threat_dir: Vector3 = blackboard.get("threat_direction", Vector3.FORWARD)
		return actor.global_position - threat_dir * 30.0


## TaskHumanWave - NVA mass assault
class TaskHumanWave extends BTNode:
	func _init() -> void:
		super._init("HumanWave")

	func tick(_delta: float) -> Status:
		if not is_instance_valid(actor):
			return Status.FAILURE

		var target = blackboard.get("target")
		if not target or not is_instance_valid(target):
			return Status.FAILURE

		# Charge toward target
		if actor.has_method("move_to"):
			actor.move_to(target.global_position)

		# Fire while advancing
		if actor.has_method("attack"):
			actor.attack(target)

		# Check if we've reached melee range
		var dist: float = actor.global_position.distance_to(target.global_position)
		if dist < 5.0:
			return Status.SUCCESS  # In melee

		return Status.RUNNING
