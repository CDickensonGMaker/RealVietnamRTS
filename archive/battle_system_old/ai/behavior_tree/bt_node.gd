extends RefCounted
class_name BTNode
## BTNode - Base class for behavior tree nodes

enum Status {
	SUCCESS,
	FAILURE,
	RUNNING,
}

var name: String = "BTNode"
var blackboard: Dictionary = {}
var agent: Node3D = null

func _init(node_name: String = "BTNode") -> void:
	name = node_name


func setup(agent_node: Node3D, shared_blackboard: Dictionary) -> void:
	agent = agent_node
	blackboard = shared_blackboard


func tick(delta: float) -> Status:
	# Override in subclasses
	return Status.SUCCESS


func reset() -> void:
	# Override to reset state
	pass


# =============================================================================
# COMPOSITE NODES
# =============================================================================

class Sequence extends BTNode:
	## Executes children in order until one fails
	var children: Array[BTNode] = []
	var current_child: int = 0

	func _init(node_name: String = "Sequence") -> void:
		name = node_name

	func add_child(child: BTNode) -> void:
		children.append(child)

	func setup(agent_node: Node3D, shared_blackboard: Dictionary) -> void:
		super.setup(agent_node, shared_blackboard)
		for child in children:
			child.setup(agent_node, shared_blackboard)

	func tick(delta: float) -> Status:
		while current_child < children.size():
			var status := children[current_child].tick(delta)

			match status:
				Status.SUCCESS:
					current_child += 1
				Status.FAILURE:
					current_child = 0
					return Status.FAILURE
				Status.RUNNING:
					return Status.RUNNING

		current_child = 0
		return Status.SUCCESS

	func reset() -> void:
		current_child = 0
		for child in children:
			child.reset()


class Selector extends BTNode:
	## Executes children in order until one succeeds
	var children: Array[BTNode] = []
	var current_child: int = 0

	func _init(node_name: String = "Selector") -> void:
		name = node_name

	func add_child(child: BTNode) -> void:
		children.append(child)

	func setup(agent_node: Node3D, shared_blackboard: Dictionary) -> void:
		super.setup(agent_node, shared_blackboard)
		for child in children:
			child.setup(agent_node, shared_blackboard)

	func tick(delta: float) -> Status:
		while current_child < children.size():
			var status := children[current_child].tick(delta)

			match status:
				Status.SUCCESS:
					current_child = 0
					return Status.SUCCESS
				Status.FAILURE:
					current_child += 1
				Status.RUNNING:
					return Status.RUNNING

		current_child = 0
		return Status.FAILURE

	func reset() -> void:
		current_child = 0
		for child in children:
			child.reset()


class Parallel extends BTNode:
	## Executes all children simultaneously
	enum Policy { REQUIRE_ALL, REQUIRE_ONE }

	var children: Array[BTNode] = []
	var success_policy: Policy = Policy.REQUIRE_ONE
	var failure_policy: Policy = Policy.REQUIRE_ONE

	func _init(node_name: String = "Parallel") -> void:
		name = node_name

	func add_child(child: BTNode) -> void:
		children.append(child)

	func setup(agent_node: Node3D, shared_blackboard: Dictionary) -> void:
		super.setup(agent_node, shared_blackboard)
		for child in children:
			child.setup(agent_node, shared_blackboard)

	func tick(delta: float) -> Status:
		var success_count := 0
		var failure_count := 0

		for child in children:
			var status := child.tick(delta)
			match status:
				Status.SUCCESS:
					success_count += 1
				Status.FAILURE:
					failure_count += 1

		# Check failure first
		if failure_policy == Policy.REQUIRE_ONE and failure_count > 0:
			return Status.FAILURE
		if failure_policy == Policy.REQUIRE_ALL and failure_count == children.size():
			return Status.FAILURE

		# Check success
		if success_policy == Policy.REQUIRE_ONE and success_count > 0:
			return Status.SUCCESS
		if success_policy == Policy.REQUIRE_ALL and success_count == children.size():
			return Status.SUCCESS

		return Status.RUNNING


# =============================================================================
# DECORATOR NODES
# =============================================================================

class Inverter extends BTNode:
	## Inverts the result of child
	var child: BTNode

	func _init(child_node: BTNode, node_name: String = "Inverter") -> void:
		name = node_name
		child = child_node

	func setup(agent_node: Node3D, shared_blackboard: Dictionary) -> void:
		super.setup(agent_node, shared_blackboard)
		child.setup(agent_node, shared_blackboard)

	func tick(delta: float) -> Status:
		var status := child.tick(delta)
		match status:
			Status.SUCCESS:
				return Status.FAILURE
			Status.FAILURE:
				return Status.SUCCESS
			_:
				return Status.RUNNING


class Repeater extends BTNode:
	## Repeats child N times or until failure
	var child: BTNode
	var repeat_count: int = -1  # -1 = infinite
	var current_count: int = 0

	func _init(child_node: BTNode, count: int = -1, node_name: String = "Repeater") -> void:
		name = node_name
		child = child_node
		repeat_count = count

	func setup(agent_node: Node3D, shared_blackboard: Dictionary) -> void:
		super.setup(agent_node, shared_blackboard)
		child.setup(agent_node, shared_blackboard)

	func tick(delta: float) -> Status:
		var status := child.tick(delta)

		if status == Status.FAILURE:
			current_count = 0
			return Status.FAILURE

		if status == Status.SUCCESS:
			current_count += 1
			child.reset()

			if repeat_count > 0 and current_count >= repeat_count:
				current_count = 0
				return Status.SUCCESS

		return Status.RUNNING

	func reset() -> void:
		current_count = 0
		child.reset()


class Cooldown extends BTNode:
	## Prevents child from running until cooldown expires
	var child: BTNode
	var cooldown_time: float
	var current_cooldown: float = 0.0

	func _init(child_node: BTNode, cd_time: float, node_name: String = "Cooldown") -> void:
		name = node_name
		child = child_node
		cooldown_time = cd_time

	func setup(agent_node: Node3D, shared_blackboard: Dictionary) -> void:
		super.setup(agent_node, shared_blackboard)
		child.setup(agent_node, shared_blackboard)

	func tick(delta: float) -> Status:
		if current_cooldown > 0:
			current_cooldown -= delta
			return Status.FAILURE

		var status := child.tick(delta)

		if status == Status.SUCCESS or status == Status.FAILURE:
			current_cooldown = cooldown_time

		return status

	func reset() -> void:
		current_cooldown = 0.0
		child.reset()


class Condition extends BTNode:
	## Checks a condition before allowing child to run
	var child: BTNode
	var condition: Callable

	func _init(condition_func: Callable, child_node: BTNode, node_name: String = "Condition") -> void:
		name = node_name
		condition = condition_func
		child = child_node

	func setup(agent_node: Node3D, shared_blackboard: Dictionary) -> void:
		super.setup(agent_node, shared_blackboard)
		child.setup(agent_node, shared_blackboard)

	func tick(delta: float) -> Status:
		if condition.call():
			return child.tick(delta)
		return Status.FAILURE


# =============================================================================
# LEAF NODES
# =============================================================================

class Wait extends BTNode:
	## Waits for specified time
	var wait_time: float
	var elapsed: float = 0.0

	func _init(time: float, node_name: String = "Wait") -> void:
		name = node_name
		wait_time = time

	func tick(delta: float) -> Status:
		elapsed += delta
		if elapsed >= wait_time:
			elapsed = 0.0
			return Status.SUCCESS
		return Status.RUNNING

	func reset() -> void:
		elapsed = 0.0


class Action extends BTNode:
	## Executes a callable action
	var action: Callable

	func _init(action_func: Callable, node_name: String = "Action") -> void:
		name = node_name
		action = action_func

	func tick(_delta: float) -> Status:
		if action.is_valid():
			var result = action.call()
			if result is Status:
				return result
			elif result is bool:
				return Status.SUCCESS if result else Status.FAILURE
		return Status.SUCCESS


class CheckCondition extends BTNode:
	## Pure condition check (no child)
	var condition: Callable

	func _init(condition_func: Callable, node_name: String = "CheckCondition") -> void:
		name = node_name
		condition = condition_func

	func tick(_delta: float) -> Status:
		if condition.is_valid() and condition.call():
			return Status.SUCCESS
		return Status.FAILURE
