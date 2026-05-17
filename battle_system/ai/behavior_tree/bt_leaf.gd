extends "res://battle_system/ai/behavior_tree/bt_node.gd"
class_name BTLeaf

## Leaf Nodes - Actions and Conditions
## These are the actual behaviors that do things


## Action - Executes a callable
class Action extends BTLeaf:
	var action_func: Callable  # func(actor, blackboard, delta) -> Status

	func _init(node_name: String, action: Callable) -> void:
		name = node_name
		action_func = action

	func tick(delta: float) -> Status:
		if not action_func.is_valid():
			return Status.FAILURE
		return action_func.call(actor, blackboard, delta)


## Condition - Checks a condition
class Condition extends BTLeaf:
	var condition_func: Callable  # func(actor, blackboard) -> bool

	func _init(node_name: String, condition: Callable) -> void:
		name = node_name
		condition_func = condition

	func tick(_delta: float) -> Status:
		if not condition_func.is_valid():
			return Status.FAILURE
		if condition_func.call(actor, blackboard):
			return Status.SUCCESS
		return Status.FAILURE


## Wait - Waits for a duration
class Wait extends BTLeaf:
	var wait_time: float = 1.0
	var elapsed: float = 0.0

	func _init(duration: float = 1.0) -> void:
		name = "Wait"
		wait_time = duration

	func tick(delta: float) -> Status:
		elapsed += delta
		if elapsed >= wait_time:
			reset()
			return Status.SUCCESS
		return Status.RUNNING

	func reset() -> void:
		elapsed = 0.0


## SetBlackboard - Sets a value in the blackboard
class SetBlackboard extends BTLeaf:
	var key: String
	var value_func: Callable  # func(actor, blackboard) -> Variant

	func _init(bb_key: String, value: Callable) -> void:
		name = "SetBlackboard"
		key = bb_key
		value_func = value

	func tick(_delta: float) -> Status:
		if value_func.is_valid():
			blackboard[key] = value_func.call(actor, blackboard)
		return Status.SUCCESS


## Log - Prints debug message
class Log extends BTLeaf:
	var message: String

	func _init(msg: String) -> void:
		name = "Log"
		message = msg

	func tick(_delta: float) -> Status:
		print("[BT] %s: %s" % [actor.name if actor else "Unknown", message])
		return Status.SUCCESS


# =============================================================================
# COMMON COMBAT ACTIONS
# =============================================================================

## MoveToPosition - Move actor to a position
class MoveToPosition extends BTLeaf:
	var target_key: String = "move_target"  # Blackboard key for position
	var arrival_distance: float = 2.0

	func _init(pos_key: String = "move_target", arrive_dist: float = 2.0) -> void:
		name = "MoveToPosition"
		target_key = pos_key
		arrival_distance = arrive_dist

	func tick(_delta: float) -> Status:
		if target_key not in blackboard:
			return Status.FAILURE

		var target_pos: Vector3 = blackboard[target_key]
		var distance: float = actor.global_position.distance_to(target_pos)

		if distance <= arrival_distance:
			return Status.SUCCESS

		if actor.has_method("move_to"):
			actor.move_to(target_pos)
			return Status.RUNNING

		return Status.FAILURE


## AttackTarget - Attack a target
class AttackTarget extends BTLeaf:
	var target_key: String = "attack_target"

	func _init(tgt_key: String = "attack_target") -> void:
		name = "AttackTarget"
		target_key = tgt_key

	func tick(_delta: float) -> Status:
		if target_key not in blackboard:
			return Status.FAILURE

		var target: Node3D = blackboard[target_key]
		if not is_instance_valid(target):
			return Status.FAILURE

		if actor.has_method("attack"):
			actor.attack(target)
			return Status.SUCCESS

		return Status.FAILURE


## StopAttack - Stop current attack
class StopAttack extends BTLeaf:
	func _init() -> void:
		name = "StopAttack"

	func tick(_delta: float) -> Status:
		if actor.has_method("stop_attack"):
			actor.stop_attack()
		return Status.SUCCESS


## FindNearestEnemy - Find and store nearest enemy
class FindNearestEnemy extends BTLeaf:
	var output_key: String = "nearest_enemy"
	var max_range: float = 50.0

	func _init(out_key: String = "nearest_enemy", range_limit: float = 50.0) -> void:
		name = "FindNearestEnemy"
		output_key = out_key
		max_range = range_limit

	func tick(_delta: float) -> Status:
		if not SpatialHashGrid:
			return Status.FAILURE

		var my_faction: int = GameEnums.Faction.US_ARMY
		if actor.has_method("get") and actor.get("faction") != null:
			my_faction = actor.faction

		var enemy: Node3D = SpatialHashGrid.get_nearest_enemy(
			actor.global_position, my_faction, max_range
		)

		if enemy:
			blackboard[output_key] = enemy
			return Status.SUCCESS

		return Status.FAILURE


## FindCover - Find nearby cover position
class FindCover extends BTLeaf:
	var output_key: String = "cover_position"
	var search_radius: float = 15.0

	func _init(out_key: String = "cover_position", radius: float = 15.0) -> void:
		name = "FindCover"
		output_key = out_key
		search_radius = radius

	func tick(_delta: float) -> Status:
		# Simple cover finding - move away from threat
		var threat: Node3D = blackboard.get("current_threat", null)
		if not is_instance_valid(threat):
			return Status.FAILURE

		var away_dir: Vector3 = (actor.global_position - threat.global_position).normalized()
		var cover_pos: Vector3 = actor.global_position + away_dir * search_radius

		blackboard[output_key] = cover_pos
		return Status.SUCCESS


## Retreat - Move away from combat
class Retreat extends BTLeaf:
	var retreat_distance: float = 20.0
	var output_key: String = "retreat_position"

	func _init(distance: float = 20.0) -> void:
		name = "Retreat"
		retreat_distance = distance

	func tick(_delta: float) -> Status:
		# Find direction away from enemies
		var enemies: Array[Node] = actor.get_tree().get_nodes_in_group("player_units")
		if enemies.is_empty():
			return Status.FAILURE

		var avg_enemy_pos: Vector3 = Vector3.ZERO
		var count: int = 0
		for enemy in enemies:
			if is_instance_valid(enemy):
				avg_enemy_pos += enemy.global_position
				count += 1

		if count == 0:
			return Status.FAILURE

		avg_enemy_pos /= float(count)

		var retreat_dir: Vector3 = (actor.global_position - avg_enemy_pos).normalized()
		var retreat_pos: Vector3 = actor.global_position + retreat_dir * retreat_distance

		blackboard[output_key] = retreat_pos

		if actor.has_method("move_to"):
			actor.move_to(retreat_pos)
			return Status.SUCCESS

		return Status.FAILURE
