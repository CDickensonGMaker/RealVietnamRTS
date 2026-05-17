extends "res://battle_system/ai/behavior_tree/bt_node.gd"
class_name BTDecorator

## Decorator Nodes - Wrap a single child and modify its behavior

var child: BTNode = null


func set_child(node: BTNode) -> BTDecorator:
	"""Set the child node (returns self for chaining)"""
	child = node
	return self


func setup(unit: Node3D, shared_blackboard: Dictionary) -> void:
	super.setup(unit, shared_blackboard)
	if child:
		child.setup(unit, shared_blackboard)


func reset() -> void:
	if child:
		child.reset()


## Inverter - Inverts child result
class Inverter extends BTDecorator:
	func _init() -> void:
		name = "Inverter"

	func tick(delta: float) -> Status:
		if not child:
			return Status.FAILURE

		var status: Status = child.tick(delta)
		match status:
			Status.SUCCESS:
				return Status.FAILURE
			Status.FAILURE:
				return Status.SUCCESS
			_:
				return status


## Succeeder - Always returns SUCCESS
class Succeeder extends BTDecorator:
	func _init() -> void:
		name = "Succeeder"

	func tick(delta: float) -> Status:
		if child:
			child.tick(delta)
		return Status.SUCCESS


## Repeater - Repeats child N times or until failure
class Repeater extends BTDecorator:
	var max_repeats: int = -1  # -1 = infinite
	var current_repeat: int = 0

	func _init(repeats: int = -1) -> void:
		name = "Repeater"
		max_repeats = repeats

	func tick(delta: float) -> Status:
		if not child:
			return Status.FAILURE

		var status: Status = child.tick(delta)

		if status == Status.RUNNING:
			return Status.RUNNING

		if status == Status.FAILURE:
			reset()
			return Status.FAILURE

		# Success - check if we should repeat
		current_repeat += 1
		child.reset()

		if max_repeats > 0 and current_repeat >= max_repeats:
			reset()
			return Status.SUCCESS

		return Status.RUNNING

	func reset() -> void:
		super.reset()
		current_repeat = 0


## RepeatUntilFail - Keeps running until child fails
class RepeatUntilFail extends BTDecorator:
	func _init() -> void:
		name = "RepeatUntilFail"

	func tick(delta: float) -> Status:
		if not child:
			return Status.SUCCESS

		var status: Status = child.tick(delta)

		if status == Status.FAILURE:
			return Status.SUCCESS

		if status == Status.SUCCESS:
			child.reset()

		return Status.RUNNING


## Cooldown - Prevents execution for duration after success
class Cooldown extends BTDecorator:
	var cooldown_time: float = 1.0
	var time_remaining: float = 0.0

	func _init(duration: float = 1.0) -> void:
		name = "Cooldown"
		cooldown_time = duration

	func tick(delta: float) -> Status:
		if time_remaining > 0:
			time_remaining -= delta
			return Status.FAILURE

		if not child:
			return Status.FAILURE

		var status: Status = child.tick(delta)

		if status == Status.SUCCESS:
			time_remaining = cooldown_time

		return status

	func reset() -> void:
		super.reset()
		time_remaining = 0.0


## TimeLimit - Fails if child takes too long
class TimeLimit extends BTDecorator:
	var time_limit: float = 5.0
	var elapsed_time: float = 0.0

	func _init(limit: float = 5.0) -> void:
		name = "TimeLimit"
		time_limit = limit

	func tick(delta: float) -> Status:
		if not child:
			return Status.FAILURE

		elapsed_time += delta

		if elapsed_time >= time_limit:
			reset()
			return Status.FAILURE

		var status: Status = child.tick(delta)

		if status != Status.RUNNING:
			reset()

		return status

	func reset() -> void:
		super.reset()
		elapsed_time = 0.0


## Condition - Runs child only if condition is true
class ConditionalDecorator extends BTDecorator:
	var condition: Callable  # func(actor, blackboard) -> bool

	func _init(cond: Callable) -> void:
		name = "Conditional"
		condition = cond

	func tick(delta: float) -> Status:
		if not condition.is_valid():
			return Status.FAILURE

		if not condition.call(actor, blackboard):
			return Status.FAILURE

		if not child:
			return Status.SUCCESS

		return child.tick(delta)
