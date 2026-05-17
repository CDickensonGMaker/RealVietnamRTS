extends Node
## SquadBehaviors - Tactical AI behaviors for squads
## NOTE: No class_name needed - registered as autoload in project.godot
## Uses behavior trees for decision making

const BehaviorTree = preload("res://battle_system/ai/behavior_tree/behavior_tree.gd")
const BTNode = preload("res://battle_system/ai/behavior_tree/bt_node.gd")
const BTLeaf = preload("res://battle_system/ai/behavior_tree/bt_leaf.gd")
const BTComposite = preload("res://battle_system/ai/behavior_tree/bt_composite.gd")
const BTDecorator = preload("res://battle_system/ai/behavior_tree/bt_decorator.gd")

## Behavior presets
enum BehaviorPreset {
	AGGRESSIVE,      # Push forward, engage immediately
	DEFENSIVE,       # Hold position, seek cover
	GUERRILLA,       # Hit and run, ambush
	SUPPORT,         # Stay back, provide fire support
	SCOUT,           # Recon, avoid direct combat
}

## Tracked squads with behaviors
var _squad_trees: Dictionary = {}  # Squad -> BehaviorTree


func _ready() -> void:
	print("[SquadBehaviors] Initialized")


func _process(delta: float) -> void:
	# Update all behavior trees
	for squad in _squad_trees.keys():
		if not is_instance_valid(squad):
			_squad_trees.erase(squad)
			continue

		var tree: BehaviorTree = _squad_trees[squad]
		tree.update(delta)


## Assign a behavior preset to a squad
func assign_behavior(squad: Node3D, preset: BehaviorPreset) -> BehaviorTree:
	"""Assign a behavior tree to a squad"""
	var tree: BehaviorTree

	match preset:
		BehaviorPreset.AGGRESSIVE:
			tree = _create_aggressive_tree(squad)
		BehaviorPreset.DEFENSIVE:
			tree = _create_defensive_tree(squad)
		BehaviorPreset.GUERRILLA:
			tree = _create_guerrilla_tree(squad)
		BehaviorPreset.SUPPORT:
			tree = _create_support_tree(squad)
		BehaviorPreset.SCOUT:
			tree = _create_scout_tree(squad)
		_:
			tree = _create_defensive_tree(squad)

	_squad_trees[squad] = tree
	tree.start()

	return tree


func remove_behavior(squad: Node3D) -> void:
	"""Remove behavior from a squad"""
	if squad in _squad_trees:
		_squad_trees[squad].stop()
		_squad_trees.erase(squad)


## Create a behavior tree for a squad without registering it.
## Used when Squad manages its own BT as a child node.
## Returns the behavior tree (caller is responsible for start/stop).
func create_behavior_for_squad(squad: Node3D, preset: int) -> BehaviorTree:
	var tree: BehaviorTree

	match preset:
		BehaviorPreset.AGGRESSIVE:
			tree = _create_aggressive_tree(squad)
		BehaviorPreset.DEFENSIVE:
			tree = _create_defensive_tree(squad)
		BehaviorPreset.GUERRILLA:
			tree = _create_guerrilla_tree(squad)
		BehaviorPreset.SUPPORT:
			tree = _create_support_tree(squad)
		BehaviorPreset.SCOUT:
			tree = _create_scout_tree(squad)
		_:
			tree = _create_defensive_tree(squad)

	return tree


# =============================================================================
# BEHAVIOR TREE FACTORIES
# =============================================================================

func _create_aggressive_tree(squad: Node3D) -> BehaviorTree:
	"""Aggressive behavior - push forward, engage enemies"""
	var root := BTComposite.Selector.new("AggressiveRoot")

	# Priority 1: Attack if enemy in range
	var attack_sequence := BTComposite.Sequence.new("AttackSequence")
	attack_sequence.add_child(_condition_enemy_in_range(40.0))
	attack_sequence.add_child(BTLeaf.FindNearestEnemy.new("target", 40.0))
	attack_sequence.add_child(BTLeaf.AttackTarget.new("target"))

	# Priority 2: Move toward enemies if none in range
	var advance_sequence := BTComposite.Sequence.new("AdvanceSequence")
	advance_sequence.add_child(BTLeaf.FindNearestEnemy.new("target", 100.0))
	advance_sequence.add_child(_action_move_toward_target())

	# Priority 3: Idle patrol
	var patrol := _action_patrol()

	root.add_child(attack_sequence)
	root.add_child(advance_sequence)
	root.add_child(patrol)

	return BehaviorTree.new(root).setup(squad)


func _create_defensive_tree(squad: Node3D) -> BehaviorTree:
	"""Defensive behavior - hold position, engage only nearby enemies"""
	var root := BTComposite.Selector.new("DefensiveRoot")

	# Priority 1: Seek cover if under fire
	var cover_sequence := BTComposite.Sequence.new("SeekCover")
	cover_sequence.add_child(_condition_under_fire())
	cover_sequence.add_child(BTLeaf.FindCover.new("cover_pos", 15.0))
	cover_sequence.add_child(BTLeaf.MoveToPosition.new("cover_pos", 2.0))

	# Priority 2: Attack enemies in defensive range
	var defend_sequence := BTComposite.Sequence.new("DefendSequence")
	defend_sequence.add_child(_condition_enemy_in_range(25.0))
	defend_sequence.add_child(BTLeaf.FindNearestEnemy.new("target", 25.0))
	defend_sequence.add_child(BTLeaf.AttackTarget.new("target"))

	# Priority 3: Hold position
	var hold := _action_hold_position()

	root.add_child(cover_sequence)
	root.add_child(defend_sequence)
	root.add_child(hold)

	return BehaviorTree.new(root).setup(squad)


func _create_guerrilla_tree(squad: Node3D) -> BehaviorTree:
	"""Guerrilla behavior - hit and run, ambush tactics"""
	var root := BTComposite.Selector.new("GuerrillaRoot")

	# Priority 1: Retreat if health low
	var retreat_sequence := BTComposite.Sequence.new("RetreatSequence")
	retreat_sequence.add_child(_condition_health_below(0.4))
	retreat_sequence.add_child(BTLeaf.StopAttack.new())
	retreat_sequence.add_child(BTLeaf.Retreat.new(30.0))
	retreat_sequence.add_child(BTLeaf.MoveToPosition.new("retreat_position", 3.0))

	# Priority 2: Ambush - wait for enemy to get close then attack
	var ambush_sequence := BTComposite.Sequence.new("AmbushSequence")
	ambush_sequence.add_child(_condition_enemy_in_range(15.0))
	ambush_sequence.add_child(BTLeaf.FindNearestEnemy.new("target", 15.0))
	ambush_sequence.add_child(BTLeaf.AttackTarget.new("target"))

	# Priority 3: Stay hidden
	var hide := _action_stay_concealed()

	root.add_child(retreat_sequence)
	root.add_child(ambush_sequence)
	root.add_child(hide)

	return BehaviorTree.new(root).setup(squad)


func _create_support_tree(squad: Node3D) -> BehaviorTree:
	"""Support behavior - stay back, provide covering fire"""
	var root := BTComposite.Selector.new("SupportRoot")

	# Priority 1: Retreat if enemies too close
	var retreat_sequence := BTComposite.Sequence.new("RetreatFromClose")
	retreat_sequence.add_child(_condition_enemy_in_range(10.0))
	retreat_sequence.add_child(BTLeaf.Retreat.new(20.0))
	retreat_sequence.add_child(BTLeaf.MoveToPosition.new("retreat_position", 2.0))

	# Priority 2: Provide fire support at range
	var support_sequence := BTComposite.Sequence.new("FireSupport")
	support_sequence.add_child(_condition_enemy_in_range(50.0))
	support_sequence.add_child(BTLeaf.FindNearestEnemy.new("target", 50.0))
	support_sequence.add_child(BTLeaf.AttackTarget.new("target"))

	# Priority 3: Follow friendlies
	var follow := _action_follow_friendlies()

	root.add_child(retreat_sequence)
	root.add_child(support_sequence)
	root.add_child(follow)

	return BehaviorTree.new(root).setup(squad)


func _create_scout_tree(squad: Node3D) -> BehaviorTree:
	"""Scout behavior - recon, avoid combat"""
	var root := BTComposite.Selector.new("ScoutRoot")

	# Priority 1: Flee from enemies
	var flee_sequence := BTComposite.Sequence.new("FleeSequence")
	flee_sequence.add_child(_condition_enemy_in_range(30.0))
	flee_sequence.add_child(BTLeaf.Retreat.new(40.0))
	flee_sequence.add_child(BTLeaf.MoveToPosition.new("retreat_position", 3.0))

	# Priority 2: Report enemy positions
	var report_sequence := BTComposite.Sequence.new("ReportSequence")
	report_sequence.add_child(_condition_enemy_in_range(60.0))
	report_sequence.add_child(_action_report_contacts())

	# Priority 3: Patrol/scout
	var patrol := _action_patrol()

	root.add_child(flee_sequence)
	root.add_child(report_sequence)
	root.add_child(patrol)

	return BehaviorTree.new(root).setup(squad)


# =============================================================================
# CONDITION NODES
# =============================================================================

func _condition_enemy_in_range(range_val: float) -> BTNode:
	"""Condition: Is there an enemy within range?"""
	return BTLeaf.Condition.new("EnemyInRange", func(actor, bb):
		if not SpatialHashGrid:
			return false
		var my_faction: int = _get_faction(actor)
		var enemies: Array[Node3D] = SpatialHashGrid.get_enemies_in_radius(
			actor.global_position, range_val, my_faction
		)
		return not enemies.is_empty()
	)


func _condition_health_below(threshold: float) -> BTNode:
	"""Condition: Is health below threshold?"""
	return BTLeaf.Condition.new("HealthLow", func(actor, bb):
		if actor.has_method("get") and actor.get("current_health") != null:
			var ratio: float = actor.current_health / actor.max_health
			return ratio < threshold
		return false
	)


func _condition_under_fire() -> BTNode:
	"""Condition: Is the squad currently taking fire?"""
	return BTLeaf.Condition.new("UnderFire", func(actor, bb):
		if actor.has_method("get") and actor.get("suppression_level") != null:
			return actor.suppression_level > 0.2
		return false
	)


func _condition_has_ammo() -> BTNode:
	"""Condition: Does the squad have ammunition?"""
	return BTLeaf.Condition.new("HasAmmo", func(actor, bb):
		if actor.has_method("get") and actor.get("current_ammo") != null:
			return actor.current_ammo > 0
		return true  # Assume has ammo if property doesn't exist
	)


# =============================================================================
# ACTION NODES
# =============================================================================

func _action_move_toward_target() -> BTNode:
	"""Action: Move toward the target in blackboard"""
	return BTLeaf.Action.new("MoveTowardTarget", func(actor, bb, delta):
		var target: Node3D = bb.get("target", null)
		if not is_instance_valid(target):
			return BTNode.Status.FAILURE

		var distance: float = actor.global_position.distance_to(target.global_position)
		if distance < 20.0:
			return BTNode.Status.SUCCESS

		if actor.has_method("move_to"):
			var move_pos: Vector3 = target.global_position
			actor.move_to(move_pos)
			return BTNode.Status.RUNNING

		return BTNode.Status.FAILURE
	)


func _action_patrol() -> BTNode:
	"""Action: Patrol around current position"""
	return BTLeaf.Action.new("Patrol", func(actor, bb, delta):
		# Generate patrol point if needed
		if not bb.has("patrol_point") or bb.get("patrol_timer", 0.0) > 10.0:
			var angle: float = randf() * TAU
			var distance: float = randf_range(5.0, 15.0)
			var origin: Vector3 = bb.get("patrol_origin", actor.global_position)
			bb["patrol_point"] = origin + Vector3(cos(angle), 0, sin(angle)) * distance
			bb["patrol_timer"] = 0.0
			bb["patrol_origin"] = origin

		bb["patrol_timer"] = bb.get("patrol_timer", 0.0) + delta

		var patrol_pos: Vector3 = bb["patrol_point"]
		if actor.global_position.distance_to(patrol_pos) < 2.0:
			return BTNode.Status.SUCCESS

		if actor.has_method("move_to"):
			actor.move_to(patrol_pos)

		return BTNode.Status.RUNNING
	)


func _action_hold_position() -> BTNode:
	"""Action: Hold current position"""
	return BTLeaf.Action.new("HoldPosition", func(actor, bb, delta):
		# Just stay put
		return BTNode.Status.RUNNING
	)


func _action_stay_concealed() -> BTNode:
	"""Action: Stay hidden/concealed"""
	return BTLeaf.Action.new("StayConcealed", func(actor, bb, delta):
		# For now, just stay in place
		# In future, could seek dense vegetation
		return BTNode.Status.RUNNING
	)


func _action_follow_friendlies() -> BTNode:
	"""Action: Follow nearby friendly units"""
	return BTLeaf.Action.new("FollowFriendlies", func(actor, bb, delta):
		if not SpatialHashGrid:
			return BTNode.Status.FAILURE

		var my_faction: int = _get_faction(actor)
		var friendlies: Array[Node3D] = SpatialHashGrid.get_friendlies_in_radius(
			actor.global_position, 30.0, my_faction
		)

		if friendlies.is_empty():
			return BTNode.Status.FAILURE

		# Find average position of friendlies
		var avg_pos: Vector3 = Vector3.ZERO
		for friendly in friendlies:
			if friendly != actor:
				avg_pos += friendly.global_position

		if friendlies.size() > 1:
			avg_pos /= float(friendlies.size() - 1)

			if actor.global_position.distance_to(avg_pos) > 10.0:
				if actor.has_method("move_to"):
					actor.move_to(avg_pos)

		return BTNode.Status.RUNNING
	)


func _action_report_contacts() -> BTNode:
	"""Action: Report enemy contacts to command"""
	return BTLeaf.Action.new("ReportContacts", func(actor, bb, delta):
		var target: Node3D = bb.get("target", null)
		if is_instance_valid(target):
			# Emit signal for enemy spotted
			if BattleSignals:
				BattleSignals.unit_spotted.emit(target, actor) if BattleSignals.has_signal("unit_spotted") else null
		return BTNode.Status.SUCCESS
	)


# =============================================================================
# HELPERS
# =============================================================================

func _get_faction(actor: Node3D) -> int:
	"""Get faction of an actor"""
	if actor.has_method("get") and actor.get("faction") != null:
		return actor.faction
	if actor.is_in_group("player_units"):
		return GameEnums.Faction.US_ARMY
	if actor.is_in_group("enemy_units"):
		return GameEnums.Faction.VC
	return -1
