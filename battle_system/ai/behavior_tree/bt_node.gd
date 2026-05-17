extends RefCounted
class_name BTNode

## Behavior Tree Node - Base class for all BT nodes
## Provides common interface for tick/execute pattern

enum Status { SUCCESS, FAILURE, RUNNING }

var name: String = "BTNode"
var blackboard: Dictionary = {}  # Shared data between nodes
var actor: Node3D = null  # The unit being controlled


func _init(node_name: String = "BTNode") -> void:
	name = node_name


func setup(unit: Node3D, shared_blackboard: Dictionary) -> void:
	"""Initialize node with actor and blackboard"""
	actor = unit
	blackboard = shared_blackboard


func tick(delta: float) -> Status:
	"""Execute this node - override in subclasses"""
	return Status.SUCCESS


func reset() -> void:
	"""Reset node state - override if needed"""
	pass


func get_debug_info() -> String:
	"""Get debug information about this node"""
	return name
