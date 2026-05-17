extends RefCounted
class_name SquadBehaviors
## SquadBehaviors - Behavior tree factory for squad AI

# =============================================================================
# BEHAVIOR TREE TEMPLATES
# =============================================================================

## Create a complete combat-ready behavior tree for a squad
static func create_combat_tree(squad: Squad) -> BTNode:
	var blackboard := {
		"target": null,
		"cover_position": Vector3.ZERO,
		"rally_point": Vector3.ZERO,
		"last_known_enemy_pos": Vector3.ZERO,
		"is_under_fire": false,
		"should_retreat": false,
	}

	# Root selector - try behaviors in priority order
	var root := BTNode.Selector.new("CombatRoot")

	# 1. Handle routing (highest priority)
	root.add_child(_create_rout_behavior(squad, blackboard))

	# 2. Handle suppression
	root.add_child(_create_suppressed_behavior(squad, blackboard))

	# 3. Engage enemies if visible
	root.add_child(_create_engage_behavior(squad, blackboard))

	# 4. Seek cover when under fire
	root.add_child(_create_seek_cover_behavior(squad, blackboard))

	# 5. Follow standing orders
	root.add_child(_create_standing_orders_behavior(squad, blackboard))

	# 6. Idle
	root.add_child(BTNode.Action.new(func(): return BTNode.Status.SUCCESS, "Idle"))

	root.setup(squad, blackboard)
	return root


## Create patrol-focused behavior tree
static func create_patrol_tree(squad: Squad, waypoints: Array[Vector3]) -> BTNode:
	var blackboard := {
		"waypoints": waypoints,
		"current_waypoint": 0,
		"target": null,
		"alert_level": 0.0,
	}

	var root := BTNode.Selector.new("PatrolRoot")

	# 1. React to contact
	root.add_child(_create_contact_reaction_behavior(squad, blackboard))

	# 2. Patrol waypoints
	root.add_child(_create_patrol_behavior(squad, blackboard))

	root.setup(squad, blackboard)
	return root


## Create defensive behavior tree for garrisoned units
static func create_defensive_tree(squad: Squad) -> BTNode:
	var blackboard := {
		"target": null,
		"defense_position": squad.global_position,
		"max_engagement_range": 60.0,
	}

	var root := BTNode.Selector.new("DefensiveRoot")

	# 1. Engage enemies in range
	root.add_child(_create_defensive_engage_behavior(squad, blackboard))

	# 2. Hold position
	root.add_child(BTNode.Action.new(func():
		squad.velocity = Vector3.ZERO
		return BTNode.Status.SUCCESS
	, "HoldPosition"))

	root.setup(squad, blackboard)
	return root


# =============================================================================
# BEHAVIOR SUBTREES
# =============================================================================

static func _create_rout_behavior(squad: Squad, blackboard: Dictionary) -> BTNode:
	var sequence := BTNode.Sequence.new("RoutBehavior")

	# Check if routing
	sequence.add_child(BTNode.CheckCondition.new(func():
		return squad.current_state == Squad.SquadState.ROUTING
	, "IsRouting"))

	# Find rally point (nearest friendly unit or firebase)
	sequence.add_child(BTNode.Action.new(func():
		var nearest_friendly := SpatialHashGrid.get_nearest_enemy(
			squad.global_position, squad.faction, 200.0
		)
		if nearest_friendly:
			# Run away from nearest enemy
			var flee_dir := (squad.global_position - nearest_friendly.global_position).normalized()
			blackboard.rally_point = squad.global_position + flee_dir * 50.0
		return BTNode.Status.SUCCESS
	, "FindRallyPoint"))

	# Move to rally point
	sequence.add_child(_create_move_to_action(squad, blackboard, "rally_point"))

	return sequence


static func _create_suppressed_behavior(squad: Squad, blackboard: Dictionary) -> BTNode:
	var sequence := BTNode.Sequence.new("SuppressedBehavior")

	# Check if heavily suppressed
	sequence.add_child(BTNode.CheckCondition.new(func():
		return squad.suppression > 70.0
	, "IsHeavilySuppressed"))

	# Find nearest cover
	sequence.add_child(BTNode.Action.new(func():
		var cover := _find_nearest_cover(squad)
		if cover != Vector3.ZERO:
			blackboard.cover_position = cover
			return BTNode.Status.SUCCESS
		return BTNode.Status.FAILURE
	, "FindCover"))

	# Move to cover
	sequence.add_child(_create_move_to_action(squad, blackboard, "cover_position"))

	# Wait for suppression to drop
	sequence.add_child(BTNode.CheckCondition.new(func():
		return squad.suppression < 40.0
	, "WaitForSuppressionDrop"))

	return sequence


static func _create_engage_behavior(squad: Squad, blackboard: Dictionary) -> BTNode:
	var sequence := BTNode.Sequence.new("EngageBehavior")

	# Check for enemies in sight
	sequence.add_child(BTNode.CheckCondition.new(func():
		return not squad.enemies_in_sight.is_empty()
	, "HasEnemiesInSight"))

	# Select best target
	sequence.add_child(BTNode.Action.new(func():
		blackboard.target = _select_best_target(squad)
		return BTNode.Status.SUCCESS if blackboard.target else BTNode.Status.FAILURE
	, "SelectTarget"))

	# Check if in range
	var in_range_check := BTNode.CheckCondition.new(func():
		if not blackboard.target:
			return false
		var dist := squad.global_position.distance_to(blackboard.target.global_position)
		return dist <= squad.attack_range
	, "InRange")

	# If in range, attack. If not, move closer
	var engage_selector := BTNode.Selector.new("EngageOrApproach")

	# Attack if in range
	var attack_seq := BTNode.Sequence.new("AttackSequence")
	attack_seq.add_child(in_range_check)
	attack_seq.add_child(BTNode.Action.new(func():
		if blackboard.target and is_instance_valid(blackboard.target):
			squad.attack(blackboard.target)
			return BTNode.Status.RUNNING
		return BTNode.Status.FAILURE
	, "Attack"))
	engage_selector.add_child(attack_seq)

	# Move closer
	engage_selector.add_child(BTNode.Action.new(func():
		if blackboard.target and is_instance_valid(blackboard.target):
			squad.move_to(blackboard.target.global_position)
			return BTNode.Status.RUNNING
		return BTNode.Status.FAILURE
	, "ApproachTarget"))

	sequence.add_child(engage_selector)

	return sequence


static func _create_seek_cover_behavior(squad: Squad, blackboard: Dictionary) -> BTNode:
	var sequence := BTNode.Sequence.new("SeekCoverBehavior")

	# Check if under fire but not in cover
	sequence.add_child(BTNode.CheckCondition.new(func():
		return blackboard.is_under_fire and squad.current_cover == "none"
	, "UnderFireNoCover"))

	# Find cover
	sequence.add_child(BTNode.Action.new(func():
		var cover := _find_nearest_cover(squad)
		if cover != Vector3.ZERO:
			blackboard.cover_position = cover
			return BTNode.Status.SUCCESS
		return BTNode.Status.FAILURE
	, "FindCover"))

	# Move to cover
	sequence.add_child(_create_move_to_action(squad, blackboard, "cover_position"))

	return sequence


static func _create_standing_orders_behavior(squad: Squad, blackboard: Dictionary) -> BTNode:
	var selector := BTNode.Selector.new("StandingOrders")

	# Patrol behavior
	var patrol_seq := BTNode.Sequence.new("PatrolOrder")
	patrol_seq.add_child(BTNode.CheckCondition.new(func():
		return squad.standing_order == Squad.StandingOrder.PATROL
	, "IsPatrolOrder"))
	patrol_seq.add_child(BTNode.Action.new(func():
		if squad.patrol_waypoints.is_empty():
			return BTNode.Status.FAILURE
		if squad.current_state != Squad.SquadState.MOVING:
			squad.move_to(squad.patrol_waypoints[squad.current_patrol_index])
		return BTNode.Status.RUNNING
	, "DoPatrol"))
	selector.add_child(patrol_seq)

	# Guard behavior
	var guard_seq := BTNode.Sequence.new("GuardOrder")
	guard_seq.add_child(BTNode.CheckCondition.new(func():
		return squad.standing_order == Squad.StandingOrder.GUARD
	, "IsGuardOrder"))
	guard_seq.add_child(BTNode.Action.new(func():
		# Just hold position and watch
		squad.velocity = Vector3.ZERO
		return BTNode.Status.SUCCESS
	, "DoGuard"))
	selector.add_child(guard_seq)

	# Aggressive - hunt enemies
	var aggressive_seq := BTNode.Sequence.new("AggressiveOrder")
	aggressive_seq.add_child(BTNode.CheckCondition.new(func():
		return squad.standing_order == Squad.StandingOrder.AGGRESSIVE
	, "IsAggressiveOrder"))
	aggressive_seq.add_child(BTNode.Action.new(func():
		var enemy := SpatialHashGrid.get_nearest_enemy(
			squad.global_position, squad.faction, squad.sight_range * 2
		)
		if enemy:
			blackboard.target = enemy
			squad.move_to(enemy.global_position)
			return BTNode.Status.RUNNING
		return BTNode.Status.SUCCESS
	, "HuntEnemies"))
	selector.add_child(aggressive_seq)

	return selector


static func _create_contact_reaction_behavior(squad: Squad, blackboard: Dictionary) -> BTNode:
	var sequence := BTNode.Sequence.new("ContactReaction")

	# Check for contact
	sequence.add_child(BTNode.CheckCondition.new(func():
		return not squad.enemies_in_sight.is_empty()
	, "HasContact"))

	# Report contact
	sequence.add_child(BTNode.Action.new(func():
		var enemy: Node3D = squad.enemies_in_sight[0]
		blackboard.last_known_enemy_pos = enemy.global_position
		squad.contact_spotted.emit(enemy.global_position, "enemy")
		return BTNode.Status.SUCCESS
	, "ReportContact"))

	# Engage based on standing orders
	var engage_check := BTNode.CheckCondition.new(func():
		return squad.standing_order in [
			Squad.StandingOrder.GUARD,
			Squad.StandingOrder.AGGRESSIVE
		]
	, "ShouldEngage")

	var engage_action := BTNode.Action.new(func():
		blackboard.target = _select_best_target(squad)
		if blackboard.target:
			squad.attack(blackboard.target)
			return BTNode.Status.RUNNING
		return BTNode.Status.FAILURE
	, "EngageContact")

	var engage_seq := BTNode.Sequence.new("EngageIfAllowed")
	engage_seq.add_child(engage_check)
	engage_seq.add_child(engage_action)

	sequence.add_child(engage_seq)

	return sequence


static func _create_patrol_behavior(squad: Squad, blackboard: Dictionary) -> BTNode:
	var sequence := BTNode.Sequence.new("PatrolBehavior")

	# Check if has waypoints
	sequence.add_child(BTNode.CheckCondition.new(func():
		return blackboard.waypoints.size() > 0
	, "HasWaypoints"))

	# Move to current waypoint
	sequence.add_child(BTNode.Action.new(func():
		var wp_index: int = blackboard.current_waypoint
		var waypoints: Array = blackboard.waypoints
		if wp_index >= waypoints.size():
			wp_index = 0
			blackboard.current_waypoint = 0

		var target_pos: Vector3 = waypoints[wp_index]
		var dist := squad.global_position.distance_to(target_pos)

		if dist < 3.0:
			# Reached waypoint, go to next
			blackboard.current_waypoint = (wp_index + 1) % waypoints.size()
			return BTNode.Status.SUCCESS
		else:
			squad.move_to(target_pos)
			return BTNode.Status.RUNNING
	, "PatrolToWaypoint"))

	# Small wait at waypoint
	sequence.add_child(BTNode.Wait.new(2.0, "WaitAtWaypoint"))

	# Repeat
	return BTNode.Repeater.new(sequence, -1, "RepeatPatrol")


static func _create_defensive_engage_behavior(squad: Squad, blackboard: Dictionary) -> BTNode:
	var sequence := BTNode.Sequence.new("DefensiveEngage")

	# Check for enemies
	sequence.add_child(BTNode.CheckCondition.new(func():
		return not squad.enemies_in_sight.is_empty()
	, "HasTargets"))

	# Select target in range
	sequence.add_child(BTNode.Action.new(func():
		var best_target: Node3D = null
		var best_dist := INF

		for enemy in squad.enemies_in_sight:
			if not is_instance_valid(enemy):
				continue
			var dist := squad.global_position.distance_to(enemy.global_position)
			if dist < blackboard.max_engagement_range and dist < best_dist:
				best_dist = dist
				best_target = enemy

		if best_target:
			blackboard.target = best_target
			return BTNode.Status.SUCCESS
		return BTNode.Status.FAILURE
	, "SelectDefensiveTarget"))

	# Engage without moving
	sequence.add_child(BTNode.Action.new(func():
		if blackboard.target and is_instance_valid(blackboard.target):
			squad.current_target = blackboard.target
			squad.current_state = Squad.SquadState.ATTACKING
			return BTNode.Status.RUNNING
		return BTNode.Status.FAILURE
	, "EngageFromPosition"))

	return sequence


# =============================================================================
# HELPER ACTIONS
# =============================================================================

static func _create_move_to_action(squad: Squad, blackboard: Dictionary, target_key: String) -> BTNode:
	return BTNode.Action.new(func():
		var target_pos: Vector3 = blackboard.get(target_key, Vector3.ZERO)
		if target_pos == Vector3.ZERO:
			return BTNode.Status.FAILURE

		var dist := squad.global_position.distance_to(target_pos)
		if dist < 2.0:
			return BTNode.Status.SUCCESS

		squad.move_to(target_pos)
		return BTNode.Status.RUNNING
	, "MoveTo_" + target_key)


# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

static func _select_best_target(squad: Squad) -> Node3D:
	var best_target: Node3D = null
	var best_score := -INF

	for enemy in squad.enemies_in_sight:
		if not is_instance_valid(enemy):
			continue

		var score := _calculate_target_priority(squad, enemy)
		if score > best_score:
			best_score = score
			best_target = enemy

	return best_target


static func _calculate_target_priority(squad: Squad, target: Node3D) -> float:
	var score := 0.0
	var distance := squad.global_position.distance_to(target.global_position)

	# Closer targets are better
	score += 100.0 - clampf(distance, 0.0, 100.0)

	# Prefer targets in range
	if distance <= squad.attack_range:
		score += 50.0

	# Prefer damaged targets
	if target.has_method("get_squad_size"):
		var size: int = target.get_squad_size()
		if size < 5:
			score += 30.0

	# Prefer suppressed targets
	if target.has_method("get_suppression"):
		var suppression: float = target.get_suppression()
		score += suppression * 0.3

	return score


static func _find_nearest_cover(squad: Squad) -> Vector3:
	# Query for cover positions near squad
	# In a real implementation, this would check for:
	# - Buildings/bunkers in range
	# - Terrain features (craters, tree lines)
	# - Existing friendly positions

	var cover_positions: Array[Vector3] = []

	# Check for structures that provide cover
	var structures := squad.get_tree().get_nodes_in_group("structures")
	for structure in structures:
		if structure.has_method("provides_cover") and structure.provides_cover():
			var dist := squad.global_position.distance_to(structure.global_position)
			if dist < 30.0:
				cover_positions.append(structure.global_position)

	# Find nearest
	if cover_positions.is_empty():
		# No cover found, return position behind current direction
		var flee_dir := -squad.basis.z
		return squad.global_position + flee_dir * 10.0

	var nearest_pos := cover_positions[0]
	var nearest_dist := squad.global_position.distance_to(nearest_pos)

	for pos in cover_positions:
		var dist := squad.global_position.distance_to(pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_pos = pos

	return nearest_pos
