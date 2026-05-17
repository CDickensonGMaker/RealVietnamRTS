extends Node
class_name VillageManager

## Village Manager - Manages all villages and VC village integration
## Handles VC supply network, recruitment, and fake civilian attacks

signal vc_supplies_collected(total: float)
signal vc_recruits_ready(village: Node3D, count: int)
signal civilian_ambush_triggered(village: Node3D, attackers: Array)
signal hearts_and_minds_update(pro_us: int, pro_vc: int, neutral: int)

const Village = preload("res://village_system/village.gd")

## All villages
var villages: Array[Village] = []

## VC resources from villages
var vc_supply_pool: float = 0.0
var vc_recruit_pool: int = 0

## Timers
var _supply_collection_timer: float = 0.0
var _status_update_timer: float = 0.0
const SUPPLY_COLLECTION_INTERVAL := 30.0
const STATUS_UPDATE_INTERVAL := 10.0


func _ready() -> void:
	_collect_villages()
	print("[VillageManager] Initialized with %d villages" % villages.size())


func _collect_villages() -> void:
	"""Find all villages in scene"""
	villages.clear()
	var nodes: Array[Node] = get_tree().get_nodes_in_group("villages")
	for node in nodes:
		if node is Village:
			_register_village(node)


func _register_village(village: Village) -> void:
	"""Register a village with the manager"""
	if village in villages:
		return

	villages.append(village)

	# Connect signals
	village.vc_tax_collected.connect(_on_vc_tax_collected)
	village.civilian_killed.connect(_on_civilian_killed)
	village.allegiance_changed.connect(_on_allegiance_changed)


func _process(delta: float) -> void:
	_supply_collection_timer += delta
	_status_update_timer += delta

	# Periodic VC supply collection
	if _supply_collection_timer >= SUPPLY_COLLECTION_INTERVAL:
		_supply_collection_timer = 0.0
		_collect_vc_supplies()

	# Status update
	if _status_update_timer >= STATUS_UPDATE_INTERVAL:
		_status_update_timer = 0.0
		_update_status()


func _collect_vc_supplies() -> void:
	"""Collect supplies from VC-aligned villages"""
	var total_supplies: float = 0.0

	for village in villages:
		if not is_instance_valid(village):
			continue

		var supplies: float = village.get_supply_for_vc()
		total_supplies += supplies

	vc_supply_pool += total_supplies

	if total_supplies > 0:
		vc_supplies_collected.emit(total_supplies)


func _update_status() -> void:
	"""Update overall village status"""
	var pro_us: int = 0
	var pro_vc: int = 0
	var neutral: int = 0

	for village in villages:
		if not is_instance_valid(village):
			continue

		match village.allegiance:
			Village.Allegiance.PRO_US:
				pro_us += 1
			Village.Allegiance.PRO_VC:
				pro_vc += 1
			Village.Allegiance.NEUTRAL, Village.Allegiance.CONTESTED:
				neutral += 1

	hearts_and_minds_update.emit(pro_us, pro_vc, neutral)


func _on_vc_tax_collected(village: Village, amount: float) -> void:
	"""Handle VC tax collection"""
	vc_supply_pool += amount


func _on_civilian_killed(village: Village, killer: Node3D) -> void:
	"""Handle civilian casualty"""
	# This is tracked for war crimes / hearts and minds impact
	pass


func _on_allegiance_changed(village: Village, new_allegiance: int) -> void:
	"""Handle village allegiance change"""
	_update_status()


## Public API - VC Operations

func get_vc_supplies() -> float:
	"""Get available VC supplies from villages"""
	return vc_supply_pool


func consume_vc_supplies(amount: float) -> float:
	"""Consume VC supplies"""
	var consumed: float = minf(amount, vc_supply_pool)
	vc_supply_pool -= consumed
	return consumed


func recruit_vc_fighters(count: int) -> int:
	"""Recruit VC fighters from villages"""
	var recruited: int = 0

	for village in villages:
		if not is_instance_valid(village):
			continue

		if village.allegiance == Village.Allegiance.PRO_VC or village.vc_presence > 0.5:
			var from_village: int = village.recruit_for_vc()
			recruited += from_village
			vc_recruit_pool += from_village

			if recruited >= count:
				break

	return recruited


func trigger_civilian_ambush(near_position: Vector3) -> Array[Node3D]:
	"""Trigger fake civilian ambush near a position"""
	var attackers: Array[Node3D] = []

	# Find nearest VC-aligned village
	var nearest_village: Village = null
	var nearest_dist: float = INF

	for village in villages:
		if not is_instance_valid(village):
			continue

		if village.vc_presence < 0.4:
			continue  # Not enough VC presence

		if village.get_vc_sympathizers() < 1:
			continue  # No hidden fighters

		var dist: float = near_position.distance_to(village.global_position)
		if dist < nearest_dist and dist < 100.0:  # Within range
			nearest_dist = dist
			nearest_village = village

	if nearest_village:
		attackers = nearest_village.reveal_sympathizers()

		if not attackers.is_empty():
			civilian_ambush_triggered.emit(nearest_village, attackers)

			# Order attack on nearby player units
			_order_sympathizer_attack(attackers, near_position)

	return attackers


func _order_sympathizer_attack(attackers: Array[Node3D], target_pos: Vector3) -> void:
	"""Order revealed sympathizers to attack"""
	# Find nearby player units
	var player_units: Array[Node] = get_tree().get_nodes_in_group("player_units")
	var nearby_targets: Array[Node3D] = []

	for unit in player_units:
		if not is_instance_valid(unit):
			continue
		var dist: float = target_pos.distance_to(unit.global_position)
		if dist < 30.0:
			nearby_targets.append(unit as Node3D)

	if nearby_targets.is_empty():
		return

	# Assign targets
	for attacker in attackers:
		if not is_instance_valid(attacker):
			continue

		var target: Node3D = nearby_targets[randi() % nearby_targets.size()]

		if attacker.has_method("attack"):
			attacker.attack(target)


## Public API - US Operations

func deliver_aid_to_village(village: Village, amount: float) -> void:
	"""Deliver US aid to a village"""
	if is_instance_valid(village):
		village.deliver_aid(amount)


func perform_civic_action(village: Village, duration: float) -> void:
	"""Perform civic action at village"""
	if is_instance_valid(village):
		village.apply_civic_action(duration)


func find_village_for_aid() -> Village:
	"""Find best village for aid (highest potential gain)"""
	var best_village: Village = null
	var best_score: float = -INF

	for village in villages:
		if not is_instance_valid(village):
			continue

		# Score based on current state
		var score: float = 0.0

		# Prefer contested or neutral villages
		match village.allegiance:
			Village.Allegiance.NEUTRAL:
				score += 2.0
			Village.Allegiance.CONTESTED:
				score += 3.0
			Village.Allegiance.PRO_VC:
				score += 1.0
			Village.Allegiance.PRO_US:
				score += 0.0  # Already friendly

		# Prefer larger populations
		score += float(village.population) / 100.0

		# Prefer lower VC presence (easier to flip)
		score += (1.0 - village.vc_presence) * 2.0

		if score > best_score:
			best_score = score
			best_village = village

	return best_village


func get_village_near(position: Vector3, max_distance: float = 50.0) -> Village:
	"""Find village near a position"""
	for village in villages:
		if not is_instance_valid(village):
			continue

		var dist: float = position.distance_to(village.global_position)
		if dist <= max_distance:
			return village

	return null


## Statistics

func get_pro_us_count() -> int:
	var count: int = 0
	for v in villages:
		if is_instance_valid(v) and v.allegiance == Village.Allegiance.PRO_US:
			count += 1
	return count


func get_pro_vc_count() -> int:
	var count: int = 0
	for v in villages:
		if is_instance_valid(v) and v.allegiance == Village.Allegiance.PRO_VC:
			count += 1
	return count


func get_total_population() -> int:
	var total: int = 0
	for v in villages:
		if is_instance_valid(v):
			total += v.population
	return total


func get_total_vc_sympathizers() -> int:
	var total: int = 0
	for v in villages:
		if is_instance_valid(v):
			total += v.get_vc_sympathizers()
	return total
