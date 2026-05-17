class_name DeployableFOB extends Node3D
## DeployableFOB - WARNO-style deployable Forward Operating Base
##
## Attach this to supply trucks or command vehicles to enable:
## - Vehicle deploys/packs up to become mobile supply point
## - Units within supply_radius can resupply ammunition
## - Provides limited construction capability when deployed
##
## LESSONS FROM WARNO:
## - FOB vehicles deploy in place (can't move while deployed)
## - Creates a supply zone that affects nearby units
## - Critical infrastructure - losing FOB cuts off supply
## - Can pack up and relocate if needed
##
## USAGE:
##   var fob = DeployableFOB.new()
##   supply_truck.add_child(fob)
##   # Later: fob.deploy() / fob.pack_up()

signal deployed(position: Vector3)
signal packed_up
signal supply_distributed(unit: Node3D, amount: float)
signal supply_depleted

enum FOBState {
	MOBILE,      # Can move, no supply function
	DEPLOYING,   # Transition state
	DEPLOYED,    # Stationary, providing supply
	PACKING,     # Transition state back to mobile
}

## Configuration
@export var supply_radius: float = 30.0  # Units within this radius can resupply
@export var supply_capacity: float = 500.0  # Total supply available
@export var resupply_rate: float = 10.0  # Supply per second to nearby units
@export var deploy_time: float = 5.0  # Seconds to deploy
@export var pack_time: float = 8.0  # Seconds to pack up

## State
var state: FOBState = FOBState.MOBILE
var current_supply: float = 500.0
var deploy_progress: float = 0.0
var units_in_range: Array[Node3D] = []

## Visuals
var supply_zone_visual: MeshInstance3D
var deployment_indicator: Node3D

## Timing
var _resupply_timer: float = 0.0
const RESUPPLY_INTERVAL: float = 1.0  # Check every second


func _ready() -> void:
	current_supply = supply_capacity
	_create_supply_zone_visual()
	add_to_group("deployable_fobs")


func _process(delta: float) -> void:
	match state:
		FOBState.DEPLOYING:
			_process_deploy(delta)
		FOBState.PACKING:
			_process_pack(delta)
		FOBState.DEPLOYED:
			_process_supply(delta)


func _process_deploy(delta: float) -> void:
	deploy_progress += delta / deploy_time
	if deploy_progress >= 1.0:
		deploy_progress = 1.0
		state = FOBState.DEPLOYED
		_on_deployed()


func _process_pack(delta: float) -> void:
	deploy_progress -= delta / pack_time
	if deploy_progress <= 0.0:
		deploy_progress = 0.0
		state = FOBState.MOBILE
		_on_packed()


func _process_supply(delta: float) -> void:
	if current_supply <= 0.0:
		return

	_resupply_timer += delta
	if _resupply_timer < RESUPPLY_INTERVAL:
		return

	_resupply_timer = 0.0
	_update_units_in_range()
	_distribute_supply()


# =============================================================================
# DEPLOYMENT CONTROL
# =============================================================================

## Start deploying the FOB (vehicle must stop)
func deploy() -> bool:
	if state != FOBState.MOBILE:
		return false

	# Ensure parent vehicle stops
	var parent: Node3D = get_parent()
	if parent and parent.has_method("stop"):
		parent.stop()
	elif parent and "velocity" in parent:
		parent.velocity = Vector3.ZERO

	state = FOBState.DEPLOYING
	deploy_progress = 0.0

	# Show deployment progress
	if supply_zone_visual:
		supply_zone_visual.visible = true
		_update_zone_visual()

	print("[DeployableFOB] Deploying...")
	return true


## Start packing up the FOB to become mobile again
func pack_up() -> bool:
	if state != FOBState.DEPLOYED:
		return false

	state = FOBState.PACKING
	print("[DeployableFOB] Packing up...")
	return true


## Force immediate pack (emergency)
func emergency_pack() -> void:
	state = FOBState.MOBILE
	deploy_progress = 0.0
	_on_packed()


func _on_deployed() -> void:
	"""Called when deployment completes"""
	if supply_zone_visual:
		supply_zone_visual.visible = true
		_update_zone_visual()

	deployed.emit(global_position)
	print("[DeployableFOB] Deployed at %s (supply: %.0f)" % [global_position, current_supply])


func _on_packed() -> void:
	"""Called when packing completes"""
	if supply_zone_visual:
		supply_zone_visual.visible = false

	units_in_range.clear()
	packed_up.emit()
	print("[DeployableFOB] Packed up and ready to move")


# =============================================================================
# SUPPLY DISTRIBUTION
# =============================================================================

func _update_units_in_range() -> void:
	"""Update list of units in supply range"""
	units_in_range.clear()

	# Query spatial hash or use group-based search
	var all_units: Array = get_tree().get_nodes_in_group("all_units")

	for unit_node in all_units:
		var unit: Node3D = unit_node as Node3D
		if not unit or unit == get_parent():
			continue

		var dist: float = global_position.distance_to(unit.global_position)
		if dist <= supply_radius:
			# Only resupply friendly units
			if _is_friendly(unit):
				units_in_range.append(unit)


func _distribute_supply() -> void:
	"""Distribute supply to units in range"""
	if units_in_range.is_empty() or current_supply <= 0.0:
		return

	var supply_per_unit: float = minf(
		resupply_rate / float(units_in_range.size()),
		current_supply / float(units_in_range.size())
	)

	for unit in units_in_range:
		if not is_instance_valid(unit):
			continue

		var amount_given: float = 0.0

		# Try to resupply ammo
		if unit.has_method("add_ammo"):
			var ammo_needed: float = _get_ammo_needed(unit)
			var ammo_to_give: float = minf(supply_per_unit, ammo_needed)
			if ammo_to_give > 0.0:
				unit.add_ammo(ammo_to_give)
				amount_given += ammo_to_give

		# Try to resupply vehicle fuel
		if unit.has_method("add_fuel"):
			var fuel_needed: float = _get_fuel_needed(unit)
			var fuel_to_give: float = minf(supply_per_unit - amount_given, fuel_needed)
			if fuel_to_give > 0.0:
				unit.add_fuel(fuel_to_give)
				amount_given += fuel_to_give

		if amount_given > 0.0:
			current_supply -= amount_given
			supply_distributed.emit(unit, amount_given)

	# Check for depletion
	if current_supply <= 0.0:
		current_supply = 0.0
		supply_depleted.emit()
		print("[DeployableFOB] Supply depleted!")


func _get_ammo_needed(unit: Node3D) -> float:
	"""Calculate how much ammo a unit needs"""
	if unit.has_method("get"):
		var current: float = unit.get("current_ammo") if "current_ammo" in unit else 0.0
		var max_ammo: float = unit.get("max_ammo") if "max_ammo" in unit else 100.0
		return maxf(0.0, max_ammo - current)
	return 0.0


func _get_fuel_needed(unit: Node3D) -> float:
	"""Calculate how much fuel a unit needs"""
	if unit.has_method("get"):
		var current: float = unit.get("current_fuel") if "current_fuel" in unit else 0.0
		var max_fuel: float = unit.get("max_fuel") if "max_fuel" in unit else 100.0
		return maxf(0.0, max_fuel - current)
	return 0.0


func _is_friendly(unit: Node3D) -> bool:
	"""Check if unit is friendly (same faction)"""
	var parent: Node3D = get_parent()
	if not parent:
		return false

	# Get factions
	var our_faction: int = parent.get("faction") if "faction" in parent else -1
	var their_faction: int = unit.get("faction") if "faction" in unit else -2

	if our_faction < 0 or their_faction < 0:
		return true  # Default to friendly if faction unknown

	# US and ARVN are allies (factions 0 and 1)
	# VC and NVA are allies (factions 2 and 3)
	if our_faction <= 1:
		return their_faction <= 1
	else:
		return their_faction >= 2


# =============================================================================
# SUPPLY MANAGEMENT
# =============================================================================

## Add supply to the FOB (from supply convoy, helicopter, etc.)
func add_supply(amount: float) -> void:
	current_supply = minf(current_supply + amount, supply_capacity)


## Get current supply percentage
func get_supply_percent() -> float:
	return current_supply / supply_capacity


## Check if FOB can provide supply
func can_provide_supply() -> bool:
	return state == FOBState.DEPLOYED and current_supply > 0.0


## Check if FOB is deployed
func is_deployed() -> bool:
	return state == FOBState.DEPLOYED


## Check if FOB is mobile
func is_mobile() -> bool:
	return state == FOBState.MOBILE


## Get deployment progress (0.0 to 1.0)
func get_deploy_progress() -> float:
	return deploy_progress


# =============================================================================
# VISUALS
# =============================================================================

func _create_supply_zone_visual() -> void:
	"""Create visual indicator for supply zone"""
	supply_zone_visual = MeshInstance3D.new()
	supply_zone_visual.name = "SupplyZone"

	var torus := TorusMesh.new()
	torus.inner_radius = supply_radius - 0.3
	torus.outer_radius = supply_radius
	torus.rings = 64
	torus.ring_segments = 8
	supply_zone_visual.mesh = torus
	supply_zone_visual.position.y = 0.2
	supply_zone_visual.rotation_degrees.x = 90

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 0.3, 0.4)  # Green tint for supply
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	supply_zone_visual.material_override = mat

	supply_zone_visual.visible = false  # Hidden until deployed
	add_child(supply_zone_visual)


func _update_zone_visual() -> void:
	"""Update supply zone visual based on state and supply level"""
	if not supply_zone_visual:
		return

	var mat: StandardMaterial3D = supply_zone_visual.material_override
	if not mat:
		return

	# Color based on supply level
	var supply_percent: float = get_supply_percent()
	if supply_percent > 0.5:
		mat.albedo_color = Color(0.2, 0.6, 0.3, 0.4)  # Green - healthy
	elif supply_percent > 0.2:
		mat.albedo_color = Color(0.6, 0.5, 0.2, 0.4)  # Yellow - warning
	else:
		mat.albedo_color = Color(0.6, 0.2, 0.2, 0.4)  # Red - critical

	# Pulse during deployment
	if state == FOBState.DEPLOYING or state == FOBState.PACKING:
		var pulse: float = 0.3 + 0.1 * sin(Time.get_ticks_msec() * 0.01)
		mat.albedo_color.a = pulse


## Get units currently in supply range
func get_units_in_range() -> Array[Node3D]:
	return units_in_range


## Get supply zone bounds for minimap
func get_supply_bounds() -> AABB:
	return AABB(
		global_position - Vector3(supply_radius, 0, supply_radius),
		Vector3(supply_radius * 2, 5, supply_radius * 2)
	)
