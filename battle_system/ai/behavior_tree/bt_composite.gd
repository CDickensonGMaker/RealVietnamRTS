extends "res://battle_system/ai/behavior_tree/bt_node.gd"
class_name BTComposite

## Composite Nodes - Contain multiple children
## Selector: OR logic - succeeds if any child succeeds
## Sequence: AND logic - succeeds if all children succeed

var children: Array = []  # BTNode
var current_child_index: int = 0


func add_child(child: RefCounted) -> BTComposite:  # BTNode
	"""Add a child node (returns self for chaining)"""
	children.append(child)
	return self


func setup(unit: Node3D, shared_blackboard: Dictionary) -> void:
	super.setup(unit, shared_blackboard)
	for child in children:
		child.setup(unit, shared_blackboard)


func reset() -> void:
	current_child_index = 0
	for child in children:
		child.reset()


## Selector - Tries children until one succeeds (OR)
class Selector extends BTComposite:
	func _init(node_name: String = "Selector") -> void:
		name = node_name

	func tick(delta: float) -> Status:
		while current_child_index < children.size():
			var status: Status = children[current_child_index].tick(delta)

			match status:
				Status.SUCCESS:
					reset()
					return Status.SUCCESS
				Status.RUNNING:
					return Status.RUNNING
				Status.FAILURE:
					current_child_index += 1

		reset()
		return Status.FAILURE


## Sequence - Runs children in order until one fails (AND)
class Sequence extends BTComposite:
	func _init(node_name: String = "Sequence") -> void:
		name = node_name

	func tick(delta: float) -> Status:
		while current_child_index < children.size():
			var status: Status = children[current_child_index].tick(delta)

			match status:
				Status.FAILURE:
					reset()
					return Status.FAILURE
				Status.RUNNING:
					return Status.RUNNING
				Status.SUCCESS:
					current_child_index += 1

		reset()
		return Status.SUCCESS


## Parallel - Runs all children simultaneously
class Parallel extends BTComposite:
	var success_threshold: int = 1  # How many need to succeed

	func _init(node_name: String = "Parallel", threshold: int = 1) -> void:
		name = node_name
		success_threshold = threshold

	func tick(delta: float) -> Status:
		var successes: int = 0
		var failures: int = 0
		var running: int = 0

		for child in children:
			var status: Status = child.tick(delta)
			match status:
				Status.SUCCESS:
					successes += 1
				Status.FAILURE:
					failures += 1
				Status.RUNNING:
					running += 1

		if successes >= success_threshold:
			return Status.SUCCESS
		if failures > children.size() - success_threshold:
			return Status.FAILURE
		return Status.RUNNING


## RandomSelector - Tries children in random order
class RandomSelector extends BTComposite:
	var _shuffled_indices: Array[int] = []

	func _init(node_name: String = "RandomSelector") -> void:
		name = node_name

	func tick(delta: float) -> Status:
		# Shuffle on first tick
		if _shuffled_indices.is_empty():
			for i in children.size():
				_shuffled_indices.append(i)
			_shuffled_indices.shuffle()

		while current_child_index < _shuffled_indices.size():
			var idx: int = _shuffled_indices[current_child_index]
			var status: Status = children[idx].tick(delta)

			match status:
				Status.SUCCESS:
					reset()
					return Status.SUCCESS
				Status.RUNNING:
					return Status.RUNNING
				Status.FAILURE:
					current_child_index += 1

		reset()
		return Status.FAILURE

	func reset() -> void:
		super.reset()
		_shuffled_indices.clear()
