class_name VehicleComponent extends RefCounted
## Vehicle Component - Men of War style component damage system.
## Vehicles have multiple components (engine, turret, tracks, etc.) with
## independent HP pools. Damage to specific components affects vehicle capability.
##
## This serves Pillar 4 (Doctrine Over Spam) - losing a tank component is a
## meaningful event requiring repair, not just HP depletion.

signal component_damaged(component_type: int, current_hp: float, max_hp: float)
signal component_destroyed(component_type: int)
signal component_repaired(component_type: int, current_hp: float)
signal crew_member_killed(position: int)

enum ComponentType {
	ENGINE,       # Affects mobility - destroyed = immobile
	TURRET,       # Affects rotation/firing - destroyed = can't rotate
	TRACKS_LEFT,  # Affects mobility - destroyed = pivot only
	TRACKS_RIGHT, # Affects mobility - destroyed = pivot only
	MAIN_GUN,     # Affects primary weapon - destroyed = can't fire main gun
	HULL,         # Main HP pool - destroyed = vehicle destroyed
	OPTICS,       # Affects accuracy - damaged = reduced aim speed
	RADIO,        # Affects command - destroyed = no reinforcement calls
	FUEL_TANK,    # Fire hazard - destroyed = fire/explosion
	AMMO_RACK,    # Explosion hazard - destroyed = catastrophic kill
}

enum AmmoType {
	AP,           # Armor Piercing - good vs armor, low suppression
	HE,           # High Explosive - good vs infantry/buildings, high suppression
	HEAT,         # High Explosive Anti-Tank - shaped charge
	CANISTER,     # Anti-infantry shotgun round
	SMOKE,        # Obscurant, no damage
	WP,           # White Phosphorus - incendiary/smoke
}

enum CrewPosition {
	DRIVER,       # Required for movement
	GUNNER,       # Required for turret operation
	LOADER,       # Affects reload speed
	COMMANDER,    # Affects detection and accuracy
	RADIO_OP,     # Required for radio calls
	BOW_GUNNER,   # Optional MG gunner
}

## Component data structure
class ComponentData:
	var type: int = ComponentType.HULL
	var max_hp: float = 100.0
	var current_hp: float = 100.0
	var armor_front: float = 0.0
	var armor_side: float = 0.0
	var armor_rear: float = 0.0
	var is_critical: bool = false  # Destroyed = vehicle destroyed
	var is_destroyed: bool = false

	func _init(comp_type: int, hp: float, front: float = 0.0, side: float = 0.0, rear: float = 0.0, critical: bool = false) -> void:
		type = comp_type
		max_hp = hp
		current_hp = hp
		armor_front = front
		armor_side = side
		armor_rear = rear
		is_critical = critical
		is_destroyed = false

	func take_damage(amount: float) -> float:
		var actual: float = minf(amount, current_hp)
		current_hp = maxf(0.0, current_hp - amount)
		if current_hp <= 0.0:
			is_destroyed = true
		return actual

	func repair(amount: float) -> void:
		current_hp = minf(max_hp, current_hp + amount)
		if current_hp > 0.0:
			is_destroyed = false

	func get_efficiency() -> float:
		if is_destroyed:
			return 0.0
		return current_hp / max_hp

## Crew member data
class CrewMember:
	var position: int = CrewPosition.DRIVER
	var is_alive: bool = true
	var is_wounded: bool = false
	var skill_level: float = 1.0  # 0.5 = conscript, 1.0 = regular, 1.5 = veteran

	func _init(pos: int, skill: float = 1.0) -> void:
		position = pos
		skill_level = skill
		is_alive = true
		is_wounded = false

## All components indexed by type
var components: Dictionary = {}

## Crew members indexed by position
var crew: Dictionary = {}

## Ammo storage - type -> count
var ammo: Dictionary = {}

## Currently selected ammo type for main gun
var selected_ammo: int = AmmoType.AP


func _init() -> void:
	pass


## Setup components for a specific vehicle type
func setup_tank_components(armor_front: float, armor_side: float, armor_rear: float) -> void:
	components.clear()

	# Hull is the primary HP pool
	components[ComponentType.HULL] = ComponentData.new(
		ComponentType.HULL, 300.0, armor_front, armor_side, armor_rear, true
	)

	# Engine - rear mounted typically
	components[ComponentType.ENGINE] = ComponentData.new(
		ComponentType.ENGINE, 100.0, armor_rear * 0.5, armor_rear * 0.5, armor_rear * 0.3, false
	)

	# Turret - heavily armored
	components[ComponentType.TURRET] = ComponentData.new(
		ComponentType.TURRET, 150.0, armor_front * 0.9, armor_side * 0.8, armor_rear * 0.6, false
	)

	# Tracks
	components[ComponentType.TRACKS_LEFT] = ComponentData.new(
		ComponentType.TRACKS_LEFT, 50.0, 5.0, 5.0, 5.0, false
	)
	components[ComponentType.TRACKS_RIGHT] = ComponentData.new(
		ComponentType.TRACKS_RIGHT, 50.0, 5.0, 5.0, 5.0, false
	)

	# Main gun
	components[ComponentType.MAIN_GUN] = ComponentData.new(
		ComponentType.MAIN_GUN, 80.0, armor_front * 0.3, armor_side * 0.2, armor_rear * 0.1, false
	)

	# Optics
	components[ComponentType.OPTICS] = ComponentData.new(
		ComponentType.OPTICS, 30.0, armor_front * 0.1, armor_side * 0.05, armor_rear * 0.05, false
	)

	# Ammo rack - low HP, critical hit = explosion
	components[ComponentType.AMMO_RACK] = ComponentData.new(
		ComponentType.AMMO_RACK, 20.0, armor_side * 0.5, armor_side * 0.5, armor_rear * 0.5, true
	)

	# Fuel tank
	components[ComponentType.FUEL_TANK] = ComponentData.new(
		ComponentType.FUEL_TANK, 40.0, armor_rear * 0.3, armor_side * 0.3, armor_rear * 0.3, false
	)


## Setup components for APC (lighter armor, troop compartment)
func setup_apc_components(armor_front: float, armor_side: float, armor_rear: float) -> void:
	components.clear()

	components[ComponentType.HULL] = ComponentData.new(
		ComponentType.HULL, 200.0, armor_front, armor_side, armor_rear, true
	)

	components[ComponentType.ENGINE] = ComponentData.new(
		ComponentType.ENGINE, 80.0, armor_front * 0.3, armor_side * 0.3, armor_rear * 0.2, false
	)

	# APCs typically have a small turret or cupola
	components[ComponentType.TURRET] = ComponentData.new(
		ComponentType.TURRET, 50.0, armor_front * 0.5, armor_side * 0.4, armor_rear * 0.3, false
	)

	components[ComponentType.TRACKS_LEFT] = ComponentData.new(
		ComponentType.TRACKS_LEFT, 40.0, 3.0, 3.0, 3.0, false
	)
	components[ComponentType.TRACKS_RIGHT] = ComponentData.new(
		ComponentType.TRACKS_RIGHT, 40.0, 3.0, 3.0, 3.0, false
	)

	components[ComponentType.FUEL_TANK] = ComponentData.new(
		ComponentType.FUEL_TANK, 30.0, armor_rear * 0.2, armor_side * 0.2, armor_rear * 0.2, false
	)


## Setup components for a truck (minimal armor)
func setup_truck_components() -> void:
	components.clear()

	components[ComponentType.HULL] = ComponentData.new(
		ComponentType.HULL, 100.0, 0.0, 0.0, 0.0, true
	)

	components[ComponentType.ENGINE] = ComponentData.new(
		ComponentType.ENGINE, 60.0, 0.0, 0.0, 0.0, false
	)

	# Trucks have wheels, but we use tracks enum for simplicity
	components[ComponentType.TRACKS_LEFT] = ComponentData.new(
		ComponentType.TRACKS_LEFT, 20.0, 0.0, 0.0, 0.0, false
	)
	components[ComponentType.TRACKS_RIGHT] = ComponentData.new(
		ComponentType.TRACKS_RIGHT, 20.0, 0.0, 0.0, 0.0, false
	)

	components[ComponentType.FUEL_TANK] = ComponentData.new(
		ComponentType.FUEL_TANK, 25.0, 0.0, 0.0, 0.0, false
	)


## Setup crew for different vehicle types
func setup_tank_crew(skill: float = 1.0) -> void:
	crew.clear()
	crew[CrewPosition.DRIVER] = CrewMember.new(CrewPosition.DRIVER, skill)
	crew[CrewPosition.GUNNER] = CrewMember.new(CrewPosition.GUNNER, skill)
	crew[CrewPosition.LOADER] = CrewMember.new(CrewPosition.LOADER, skill)
	crew[CrewPosition.COMMANDER] = CrewMember.new(CrewPosition.COMMANDER, skill)


func setup_apc_crew(skill: float = 1.0) -> void:
	crew.clear()
	crew[CrewPosition.DRIVER] = CrewMember.new(CrewPosition.DRIVER, skill)
	crew[CrewPosition.COMMANDER] = CrewMember.new(CrewPosition.COMMANDER, skill)
	crew[CrewPosition.BOW_GUNNER] = CrewMember.new(CrewPosition.BOW_GUNNER, skill)


func setup_truck_crew(skill: float = 1.0) -> void:
	crew.clear()
	crew[CrewPosition.DRIVER] = CrewMember.new(CrewPosition.DRIVER, skill)


## Setup ammo loadout
func setup_tank_ammo(ap: int = 30, he: int = 15, smoke: int = 5) -> void:
	ammo.clear()
	ammo[AmmoType.AP] = ap
	ammo[AmmoType.HE] = he
	ammo[AmmoType.SMOKE] = smoke
	selected_ammo = AmmoType.AP


func setup_apc_ammo(he: int = 100) -> void:
	ammo.clear()
	ammo[AmmoType.HE] = he
	selected_ammo = AmmoType.HE


## Apply damage to a specific component
func damage_component(component_type: int, damage: float, hit_angle: float = 0.0) -> float:
	if not components.has(component_type):
		return 0.0

	var comp: ComponentData = components[component_type]
	if comp.is_destroyed:
		return 0.0

	# Calculate armor based on hit angle
	var armor: float = _get_armor_for_angle(comp, hit_angle)

	# Apply armor reduction
	var penetrating_damage: float = maxf(0.0, damage - armor)
	if penetrating_damage <= 0.0:
		return 0.0  # Bounced/absorbed

	var actual_damage: float = comp.take_damage(penetrating_damage)

	component_damaged.emit(component_type, comp.current_hp, comp.max_hp)

	if comp.is_destroyed:
		component_destroyed.emit(component_type)
		_handle_component_destruction(component_type)

	# Chance to wound/kill crew near damaged component
	_check_crew_casualties(component_type, penetrating_damage)

	return actual_damage


## Damage vehicle from a direction (auto-selects components based on hit location)
func take_directional_damage(damage: float, hit_angle: float, ammo_type: int = AmmoType.AP) -> float:
	var total_damage: float = 0.0

	# Modify damage based on ammo type
	var modified_damage: float = _modify_damage_by_ammo(damage, ammo_type)

	# Determine which component gets hit based on angle and RNG
	var hit_component: int = _select_hit_component(hit_angle)

	total_damage = damage_component(hit_component, modified_damage, hit_angle)

	# AP rounds can over-penetrate and hit internal components
	if ammo_type == AmmoType.AP and total_damage > 0.0:
		if randf() < 0.3:  # 30% chance to hit secondary component
			var secondary: int = _select_secondary_component(hit_component)
			if secondary != hit_component:
				total_damage += damage_component(secondary, modified_damage * 0.5, hit_angle)

	return total_damage


## Get armor value based on hit angle
func _get_armor_for_angle(comp: ComponentData, angle: float) -> float:
	# Angle: 0 = front, PI/2 = side, PI = rear
	var normalized_angle: float = absf(angle)

	if normalized_angle < PI / 4.0:
		return comp.armor_front
	elif normalized_angle < 3.0 * PI / 4.0:
		return comp.armor_side
	else:
		return comp.armor_rear


## Modify damage based on ammo type
func _modify_damage_by_ammo(base_damage: float, ammo_type: int) -> float:
	match ammo_type:
		AmmoType.AP:
			return base_damage * 1.2  # Better penetration
		AmmoType.HE:
			return base_damage * 0.8  # Less penetration, more splash
		AmmoType.HEAT:
			return base_damage * 1.5  # Shaped charge, excellent penetration
		AmmoType.CANISTER:
			return base_damage * 0.3  # Not designed for armor
		_:
			return base_damage


## Select which component gets hit based on hit angle
func _select_hit_component(hit_angle: float) -> int:
	var roll: float = randf()

	# Front hit
	if absf(hit_angle) < PI / 4.0:
		if roll < 0.4:
			return ComponentType.HULL
		elif roll < 0.6:
			return ComponentType.TURRET
		elif roll < 0.75:
			return ComponentType.MAIN_GUN
		elif roll < 0.9:
			return ComponentType.OPTICS
		else:
			return ComponentType.TRACKS_LEFT if randf() < 0.5 else ComponentType.TRACKS_RIGHT

	# Side hit
	elif absf(hit_angle) < 3.0 * PI / 4.0:
		var is_left: bool = hit_angle > 0.0
		if roll < 0.35:
			return ComponentType.HULL
		elif roll < 0.5:
			return ComponentType.TURRET
		elif roll < 0.7:
			return ComponentType.TRACKS_LEFT if is_left else ComponentType.TRACKS_RIGHT
		elif roll < 0.85:
			return ComponentType.ENGINE
		else:
			return ComponentType.AMMO_RACK

	# Rear hit
	else:
		if roll < 0.5:
			return ComponentType.ENGINE
		elif roll < 0.7:
			return ComponentType.HULL
		elif roll < 0.85:
			return ComponentType.FUEL_TANK
		else:
			return ComponentType.TRACKS_LEFT if randf() < 0.5 else ComponentType.TRACKS_RIGHT


## Select secondary component for over-penetration
func _select_secondary_component(primary: int) -> int:
	match primary:
		ComponentType.HULL:
			return [ComponentType.AMMO_RACK, ComponentType.FUEL_TANK, ComponentType.ENGINE].pick_random()
		ComponentType.TURRET:
			return [ComponentType.MAIN_GUN, ComponentType.OPTICS, ComponentType.AMMO_RACK].pick_random()
		ComponentType.ENGINE:
			return [ComponentType.FUEL_TANK, ComponentType.HULL].pick_random()
		_:
			return ComponentType.HULL


## Handle special effects when components are destroyed
func _handle_component_destruction(component_type: int) -> void:
	match component_type:
		ComponentType.AMMO_RACK:
			# Catastrophic explosion - all components take massive damage
			for comp_type in components.keys():
				if comp_type != ComponentType.AMMO_RACK:
					damage_component(comp_type, 500.0, 0.0)

		ComponentType.FUEL_TANK:
			# Fire - gradual damage to other components
			# This would be handled by the vehicle over time
			pass


## Check for crew casualties when component is damaged
func _check_crew_casualties(component_type: int, damage: float) -> void:
	var casualty_chance: float = damage / 100.0 * 0.2  # 20% chance per 100 damage

	# Different components affect different crew
	var at_risk: Array[int] = []
	match component_type:
		ComponentType.HULL:
			at_risk = [CrewPosition.DRIVER, CrewPosition.BOW_GUNNER]
		ComponentType.TURRET:
			at_risk = [CrewPosition.GUNNER, CrewPosition.COMMANDER, CrewPosition.LOADER]
		ComponentType.ENGINE:
			at_risk = [CrewPosition.DRIVER]

	for pos in at_risk:
		if crew.has(pos) and crew[pos].is_alive:
			if randf() < casualty_chance:
				if randf() < 0.5:
					crew[pos].is_wounded = true
				else:
					crew[pos].is_alive = false
					crew_member_killed.emit(pos)


## Repair a component
func repair_component(component_type: int, amount: float) -> void:
	if not components.has(component_type):
		return

	var comp: ComponentData = components[component_type]
	comp.repair(amount)
	component_repaired.emit(component_type, comp.current_hp)


## Get movement efficiency (0.0 = immobile, 1.0 = full speed)
func get_movement_efficiency() -> float:
	if not components.has(ComponentType.ENGINE):
		return 1.0

	var engine: ComponentData = components[ComponentType.ENGINE]
	if engine.is_destroyed:
		return 0.0

	# Check tracks
	var left_track: float = 1.0
	var right_track: float = 1.0

	if components.has(ComponentType.TRACKS_LEFT):
		left_track = components[ComponentType.TRACKS_LEFT].get_efficiency()
	if components.has(ComponentType.TRACKS_RIGHT):
		right_track = components[ComponentType.TRACKS_RIGHT].get_efficiency()

	var track_eff: float = (left_track + right_track) / 2.0

	# Check driver
	var driver_mult: float = 1.0
	if crew.has(CrewPosition.DRIVER):
		if not crew[CrewPosition.DRIVER].is_alive:
			driver_mult = 0.0
		elif crew[CrewPosition.DRIVER].is_wounded:
			driver_mult = 0.5

	return engine.get_efficiency() * track_eff * driver_mult


## Get turret efficiency (rotation speed modifier)
func get_turret_efficiency() -> float:
	if not components.has(ComponentType.TURRET):
		return 1.0

	var turret: ComponentData = components[ComponentType.TURRET]
	if turret.is_destroyed:
		return 0.0

	var gunner_mult: float = 1.0
	if crew.has(CrewPosition.GUNNER):
		if not crew[CrewPosition.GUNNER].is_alive:
			gunner_mult = 0.3  # Commander can barely operate turret
		elif crew[CrewPosition.GUNNER].is_wounded:
			gunner_mult = 0.6

	return turret.get_efficiency() * gunner_mult


## Get accuracy modifier from optics and crew
func get_accuracy_modifier() -> float:
	var base: float = 1.0

	if components.has(ComponentType.OPTICS):
		var optics: ComponentData = components[ComponentType.OPTICS]
		if optics.is_destroyed:
			base *= 0.5  # Major accuracy penalty
		else:
			base *= 0.5 + 0.5 * optics.get_efficiency()

	# Commander bonus
	if crew.has(CrewPosition.COMMANDER):
		if crew[CrewPosition.COMMANDER].is_alive and not crew[CrewPosition.COMMANDER].is_wounded:
			base *= 1.1 * crew[CrewPosition.COMMANDER].skill_level

	# Gunner required for any accuracy
	if crew.has(CrewPosition.GUNNER):
		if not crew[CrewPosition.GUNNER].is_alive:
			base *= 0.2
		elif crew[CrewPosition.GUNNER].is_wounded:
			base *= 0.6

	return base


## Get reload speed modifier
func get_reload_modifier() -> float:
	var mult: float = 1.0

	if crew.has(CrewPosition.LOADER):
		if not crew[CrewPosition.LOADER].is_alive:
			mult = 2.0  # Commander has to load - twice as slow
		elif crew[CrewPosition.LOADER].is_wounded:
			mult = 1.5
		else:
			mult = 1.0 / crew[CrewPosition.LOADER].skill_level

	return mult


## Check if main gun can fire
func can_fire_main_gun() -> bool:
	if components.has(ComponentType.MAIN_GUN):
		if components[ComponentType.MAIN_GUN].is_destroyed:
			return false

	if components.has(ComponentType.TURRET):
		if components[ComponentType.TURRET].is_destroyed:
			return false

	# Need at least commander or gunner alive
	var has_gunner: bool = crew.has(CrewPosition.GUNNER) and crew[CrewPosition.GUNNER].is_alive
	var has_commander: bool = crew.has(CrewPosition.COMMANDER) and crew[CrewPosition.COMMANDER].is_alive

	return has_gunner or has_commander


## Check if vehicle is destroyed (all critical components gone)
func is_vehicle_destroyed() -> bool:
	for comp in components.values():
		if comp.is_critical and comp.is_destroyed:
			return true
	return false


## Get alive crew count
func get_alive_crew_count() -> int:
	var count: int = 0
	for member in crew.values():
		if member.is_alive:
			count += 1
	return count


## Consume ammo of selected type
func consume_ammo(ammo_type: int = -1) -> bool:
	var type_to_use: int = ammo_type if ammo_type >= 0 else selected_ammo

	if not ammo.has(type_to_use) or ammo[type_to_use] <= 0:
		return false

	ammo[type_to_use] -= 1
	return true


## Get ammo count for a type
func get_ammo_count(ammo_type: int) -> int:
	return ammo.get(ammo_type, 0)


## Select ammo type
func select_ammo(ammo_type: int) -> void:
	if ammo.has(ammo_type) and ammo[ammo_type] > 0:
		selected_ammo = ammo_type


## Get total HP across all components
func get_total_hp() -> float:
	var total: float = 0.0
	for comp in components.values():
		total += comp.current_hp
	return total


## Get max HP across all components
func get_max_hp() -> float:
	var total: float = 0.0
	for comp in components.values():
		total += comp.max_hp
	return total


## Get component status string for UI
func get_component_status(component_type: int) -> String:
	if not components.has(component_type):
		return "N/A"

	var comp: ComponentData = components[component_type]
	if comp.is_destroyed:
		return "DESTROYED"
	elif comp.current_hp < comp.max_hp * 0.25:
		return "CRITICAL"
	elif comp.current_hp < comp.max_hp * 0.5:
		return "DAMAGED"
	elif comp.current_hp < comp.max_hp:
		return "LIGHT DMG"
	else:
		return "OK"
