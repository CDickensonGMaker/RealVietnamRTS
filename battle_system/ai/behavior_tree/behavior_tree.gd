extends RefCounted
class_name BehaviorTree

## Behavior Tree - Manages and executes a behavior tree for an actor

const BTNode = preload("res://battle_system/ai/behavior_tree/bt_node.gd")

var root: BTNode = null
var actor: Node3D = null
var blackboard: Dictionary = {}
var is_running: bool = false
var tick_rate: float = 0.1  # How often to tick (seconds)
var _tick_timer: float = 0.0


func _init(tree_root: BTNode = null) -> void:
	root = tree_root


func setup(unit: Node3D, initial_blackboard: Dictionary = {}) -> BehaviorTree:
	"""Initialize the tree with an actor"""
	actor = unit
	blackboard = initial_blackboard.duplicate()

	if root:
		root.setup(unit, blackboard)

	return self


func set_root(tree_root: BTNode) -> BehaviorTree:
	"""Set the root node"""
	root = tree_root
	if actor:
		root.setup(actor, blackboard)
	return self


func start() -> void:
	"""Start the behavior tree"""
	is_running = true
	_tick_timer = 0.0


func stop() -> void:
	"""Stop the behavior tree"""
	is_running = false
	if root:
		root.reset()


func update(delta: float) -> BTNode.Status:
	"""Update the behavior tree (call every frame)"""
	if not is_running or not root:
		return BTNode.Status.FAILURE

	_tick_timer += delta
	if _tick_timer < tick_rate:
		return BTNode.Status.RUNNING

	_tick_timer = 0.0
	return root.tick(delta)


func set_blackboard_value(key: String, value: Variant) -> void:
	"""Set a value in the blackboard"""
	blackboard[key] = value


func get_blackboard_value(key: String, default: Variant = null) -> Variant:
	"""Get a value from the blackboard"""
	return blackboard.get(key, default)


func has_blackboard_key(key: String) -> bool:
	"""Check if blackboard has a key"""
	return key in blackboard


func clear_blackboard() -> void:
	"""Clear all blackboard values"""
	blackboard.clear()


func reset() -> void:
	"""Reset the tree"""
	if root:
		root.reset()
	_tick_timer = 0.0


# =============================================================================
# BUILDER HELPERS
# =============================================================================

static func selector(node_name: String = "Selector") -> BTNode:
	"""Create a selector node"""
	var BTComposite = load("res://battle_system/ai/behavior_tree/bt_composite.gd")
	return BTComposite.Selector.new(node_name)


static func sequence(node_name: String = "Sequence") -> BTNode:
	"""Create a sequence node"""
	var BTComposite = load("res://battle_system/ai/behavior_tree/bt_composite.gd")
	return BTComposite.Sequence.new(node_name)


static func parallel(node_name: String = "Parallel", success_threshold: int = 1) -> BTNode:
	"""Create a parallel node"""
	var BTComposite = load("res://battle_system/ai/behavior_tree/bt_composite.gd")
	return BTComposite.Parallel.new(node_name, success_threshold)


static func action(node_name: String, action_func: Callable) -> BTNode:
	"""Create an action node"""
	var BTLeaf = load("res://battle_system/ai/behavior_tree/bt_leaf.gd")
	return BTLeaf.Action.new(node_name, action_func)


static func condition(node_name: String, condition_func: Callable) -> BTNode:
	"""Create a condition node"""
	var BTLeaf = load("res://battle_system/ai/behavior_tree/bt_leaf.gd")
	return BTLeaf.Condition.new(node_name, condition_func)


static func wait(duration: float) -> BTNode:
	"""Create a wait node"""
	var BTLeaf = load("res://battle_system/ai/behavior_tree/bt_leaf.gd")
	return BTLeaf.Wait.new(duration)


static func inverter() -> BTNode:
	"""Create an inverter decorator"""
	var BTDecorator = load("res://battle_system/ai/behavior_tree/bt_decorator.gd")
	return BTDecorator.Inverter.new()


static func repeater(max_repeats: int = -1) -> BTNode:
	"""Create a repeater decorator"""
	var BTDecorator = load("res://battle_system/ai/behavior_tree/bt_decorator.gd")
	return BTDecorator.Repeater.new(max_repeats)


static func cooldown(duration: float) -> BTNode:
	"""Create a cooldown decorator"""
	var BTDecorator = load("res://battle_system/ai/behavior_tree/bt_decorator.gd")
	return BTDecorator.Cooldown.new(duration)


static func time_limit(limit: float) -> BTNode:
	"""Create a time limit decorator"""
	var BTDecorator = load("res://battle_system/ai/behavior_tree/bt_decorator.gd")
	return BTDecorator.TimeLimit.new(limit)
