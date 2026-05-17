extends Node
class_name ResourceFlowSystem
## ResourceFlowSystem - Supreme Commander-style continuous resource economy
##
## Resources flow continuously per second rather than discrete transactions:
## - Supply flows from base camps to firebases
## - Construction consumes supply over time
## - Units consume ammo/fuel in combat
## - Deficit causes efficiency reduction
##
## LESSONS FROM SUPREME COMMANDER:
## - Resources are generated/consumed per second
## - Storage acts as buffer
## - Deficit reduces production speed (doesn't halt it)
## - Economic indicators show flow rates
##
## USAGE:
##   ResourceFlowSystem.add_producer("supply", firebase, 10.0)  # +10/sec
##   ResourceFlowSystem.add_consumer("supply", construction, 5.0)  # -5/sec

signal resource_updated(resource_type: String, current: float, flow_rate: float)
signal deficit_started(resource_type: String)
signal deficit_ended(resource_type: String)
signal storage_full(resource_type: String)

## Resource types for Vietnam RTS
enum ResourceType {
	SUPPLY,      # General construction/maintenance
	AMMO,        # Ammunition for combat
	FUEL,        # Vehicle/helicopter fuel
	MANPOWER,    # Reinforcement points
}

## Resource state
var _resources: Dictionary = {}  # {type: {current, max, flow_rate, producers, consumers}}

## Default storage capacities
const DEFAULT_STORAGE: Dictionary = {
	"supply": 1000.0,
	"ammo": 500.0,
	"fuel": 500.0,
	"manpower": 100.0,
}

## Default starting values
const DEFAULT_STARTING: Dictionary = {
	"supply": 500.0,
	"ammo": 250.0,
	"fuel": 250.0,
	"manpower": 50.0,
}


func _ready() -> void:
	# Initialize resource pools
	for resource_name in DEFAULT_STORAGE:
		_init_resource(resource_name, DEFAULT_STORAGE[resource_name], DEFAULT_STARTING.get(resource_name, 0.0))

	print("[ResourceFlowSystem] Initialized with %d resource types" % _resources.size())


func _init_resource(resource_name: String, max_value: float, starting: float) -> void:
	"""Initialize a resource pool"""
	_resources[resource_name] = {
		"current": starting,
		"max": max_value,
		"flow_rate": 0.0,  # Net flow rate (production - consumption)
		"producers": {},   # {node_id: rate}
		"consumers": {},   # {node_id: rate}
		"in_deficit": false,
		"efficiency": 1.0,  # 1.0 = full efficiency, <1.0 = deficit
	}


func _process(delta: float) -> void:
	_update_all_resources(delta)


func _update_all_resources(delta: float) -> void:
	"""Update all resource pools based on flow rates"""
	for resource_name in _resources:
		var res: Dictionary = _resources[resource_name]

		# Calculate net flow rate
		var production: float = _sum_rates(res.producers)
		var consumption: float = _sum_rates(res.consumers)
		var net_flow: float = production - consumption

		res.flow_rate = net_flow

		# Apply flow over delta time
		var change: float = net_flow * delta

		# Apply change
		var old_current: float = res.current
		res.current = clampf(res.current + change, 0.0, res.max)

		# Check for state changes
		var was_deficit: bool = res.in_deficit
		res.in_deficit = net_flow < 0.0 and res.current <= 0.0

		# Calculate efficiency (how much of demand is met)
		if consumption > 0.0:
			if res.current > 0.0 or production >= consumption:
				res.efficiency = 1.0
			else:
				# Partial efficiency based on how much we can provide
				res.efficiency = clampf(production / consumption, 0.1, 1.0)
		else:
			res.efficiency = 1.0

		# Emit signals for state changes
		if res.in_deficit and not was_deficit:
			deficit_started.emit(resource_name)
		elif not res.in_deficit and was_deficit:
			deficit_ended.emit(resource_name)

		if res.current >= res.max and old_current < res.max:
			storage_full.emit(resource_name)

		# Always emit update for UI
		resource_updated.emit(resource_name, res.current, res.flow_rate)


func _sum_rates(rates_dict: Dictionary) -> float:
	"""Sum all rates in a producer/consumer dictionary"""
	var total: float = 0.0
	for node_id in rates_dict:
		total += rates_dict[node_id]
	return total


# =============================================================================
# PRODUCER/CONSUMER MANAGEMENT
# =============================================================================

## Add a resource producer (base camp, depot, helicopter delivery)
func add_producer(resource_name: String, producer: Node, rate_per_second: float) -> void:
	if resource_name not in _resources:
		push_warning("[ResourceFlowSystem] Unknown resource: %s" % resource_name)
		return

	var node_id: int = producer.get_instance_id()
	_resources[resource_name].producers[node_id] = rate_per_second

	print("[ResourceFlowSystem] Added producer: %s +%.1f %s/sec" % [producer.name, rate_per_second, resource_name])


## Remove a resource producer
func remove_producer(resource_name: String, producer: Node) -> void:
	if resource_name not in _resources:
		return

	var node_id: int = producer.get_instance_id()
	_resources[resource_name].producers.erase(node_id)


## Add a resource consumer (construction site, firebase, combat unit)
func add_consumer(resource_name: String, consumer: Node, rate_per_second: float) -> void:
	if resource_name not in _resources:
		push_warning("[ResourceFlowSystem] Unknown resource: %s" % resource_name)
		return

	var node_id: int = consumer.get_instance_id()
	_resources[resource_name].consumers[node_id] = rate_per_second

	print("[ResourceFlowSystem] Added consumer: %s -%.1f %s/sec" % [consumer.name, rate_per_second, resource_name])


## Remove a resource consumer
func remove_consumer(resource_name: String, consumer: Node) -> void:
	if resource_name not in _resources:
		return

	var node_id: int = consumer.get_instance_id()
	_resources[resource_name].consumers.erase(node_id)


## Update consumer rate (e.g., construction acceleration)
func set_consumer_rate(resource_name: String, consumer: Node, new_rate: float) -> void:
	if resource_name not in _resources:
		return

	var node_id: int = consumer.get_instance_id()
	if node_id in _resources[resource_name].consumers:
		_resources[resource_name].consumers[node_id] = new_rate


## Update producer rate
func set_producer_rate(resource_name: String, producer: Node, new_rate: float) -> void:
	if resource_name not in _resources:
		return

	var node_id: int = producer.get_instance_id()
	if node_id in _resources[resource_name].producers:
		_resources[resource_name].producers[node_id] = new_rate


# =============================================================================
# RESOURCE QUERIES
# =============================================================================

## Get current amount of a resource
func get_current(resource_name: String) -> float:
	if resource_name not in _resources:
		return 0.0
	return _resources[resource_name].current


## Get max storage of a resource
func get_max(resource_name: String) -> float:
	if resource_name not in _resources:
		return 0.0
	return _resources[resource_name].max


## Get net flow rate
func get_flow_rate(resource_name: String) -> float:
	if resource_name not in _resources:
		return 0.0
	return _resources[resource_name].flow_rate


## Get current efficiency (0.1 to 1.0)
func get_efficiency(resource_name: String) -> float:
	if resource_name not in _resources:
		return 1.0
	return _resources[resource_name].efficiency


## Check if resource is in deficit
func is_in_deficit(resource_name: String) -> bool:
	if resource_name not in _resources:
		return false
	return _resources[resource_name].in_deficit


## Get production rate only
func get_production_rate(resource_name: String) -> float:
	if resource_name not in _resources:
		return 0.0
	return _sum_rates(_resources[resource_name].producers)


## Get consumption rate only
func get_consumption_rate(resource_name: String) -> float:
	if resource_name not in _resources:
		return 0.0
	return _sum_rates(_resources[resource_name].consumers)


# =============================================================================
# DIRECT RESOURCE MANIPULATION
# =============================================================================

## Add a discrete amount of resource (supply delivery)
func add_resource(resource_name: String, amount: float) -> void:
	if resource_name not in _resources:
		return
	_resources[resource_name].current = minf(
		_resources[resource_name].current + amount,
		_resources[resource_name].max
	)


## Remove a discrete amount of resource (instant cost)
func remove_resource(resource_name: String, amount: float) -> bool:
	if resource_name not in _resources:
		return false

	if _resources[resource_name].current < amount:
		return false

	_resources[resource_name].current -= amount
	return true


## Check if we can afford an instant cost
func can_afford(resource_name: String, amount: float) -> bool:
	if resource_name not in _resources:
		return false
	return _resources[resource_name].current >= amount


## Increase storage capacity (building a depot)
func increase_storage(resource_name: String, amount: float) -> void:
	if resource_name not in _resources:
		return
	_resources[resource_name].max += amount


## Set storage capacity
func set_storage(resource_name: String, max_value: float) -> void:
	if resource_name not in _resources:
		return
	_resources[resource_name].max = max_value
	# Clamp current to new max
	_resources[resource_name].current = minf(_resources[resource_name].current, max_value)


# =============================================================================
# STATUS / DEBUG
# =============================================================================

## Get full status of all resources
func get_all_status() -> Dictionary:
	var status: Dictionary = {}
	for resource_name in _resources:
		var res: Dictionary = _resources[resource_name]
		status[resource_name] = {
			"current": res.current,
			"max": res.max,
			"flow_rate": res.flow_rate,
			"efficiency": res.efficiency,
			"in_deficit": res.in_deficit,
			"production": _sum_rates(res.producers),
			"consumption": _sum_rates(res.consumers),
		}
	return status


## Print debug status
func print_status() -> void:
	print("\n[ResourceFlowSystem] Status:")
	for resource_name in _resources:
		var res: Dictionary = _resources[resource_name]
		var flow_str: String = "+%.1f" % res.flow_rate if res.flow_rate >= 0 else "%.1f" % res.flow_rate
		var deficit_str: String = " [DEFICIT]" if res.in_deficit else ""
		print("  %s: %.0f/%.0f (%s/sec) [%.0f%% eff]%s" % [
			resource_name.to_upper(),
			res.current,
			res.max,
			flow_str,
			res.efficiency * 100,
			deficit_str
		])
