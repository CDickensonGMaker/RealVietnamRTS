class_name BuildingComponentFactory
extends RefCounted
## BuildingComponentFactory - Single source for attaching combat components to
## completed buildings.
##
## Called by BOTH ConstructionZone (legacy firebase-slot path) and
## ConstructionManager.spawn_building_at (JobSystem placement path) so a player-
## built fortification is a real combat object no matter which pipeline built it.
##
## Serves Pillar 2 (Network of Firebases) and Pillar 5 (The War Continues):
## a built bunker can be garrisoned, an MG nest auto-fires.

const BuildingData = preload("res://firebase_system/building_data.gd")
const GarrisonableStructureScript = preload("res://fortification_system/garrisonable_structure.gd")
const DefensiveStructureScript = preload("res://firebase_system/nodes/defensive_structure.gd")


static func attach_building_components(building: Node3D, data: BuildingData) -> void:
	"""Attach garrison and/or auto-defense components based on BuildingData flags.
	Garrison is attached first so the DefensiveStructure finds it as a sibling in _ready()."""
	if not is_instance_valid(building) or data == null:
		return

	if data.garrison_capacity > 0:
		_attach_garrison(building, data)

	if data.auto_attacks and not data.defense_weapon.is_empty():
		_attach_defense(building, data)

	_assign_cover_group(building, data)


static func _assign_cover_group(building: Node3D, data: BuildingData) -> void:
	"""Join the CoverSystem scan group matching this building's cover tier, so
	sandbags/foxholes/bunkers grant cover through the same canonical path as
	trenches (which join cover_fortified on completion). Data-driven from
	BuildingData.cover_value; buildings that provide no cover join nothing."""
	if not data.provides_cover or data.cover_value <= 0.0:
		return
	if data.cover_value >= 0.7:
		building.add_to_group("cover_fortified")
	elif data.cover_value >= 0.5:
		building.add_to_group("cover_heavy")
	else:
		building.add_to_group("cover_light")


static func _attach_garrison(building: Node3D, data: BuildingData) -> void:
	"""Attach a GarrisonableStructure sized from BuildingData.garrison_capacity."""
	if building.has_node("GarrisonableStructure"):
		return

	var garrison := GarrisonableStructureScript.new()
	garrison.name = "GarrisonableStructure"
	garrison.max_infantry = data.garrison_capacity

	# Hardened perimeter buildings get bunker-grade cover
	if data.category == BuildingData.BuildingCategory.FIREBASE_PERIMETER:
		garrison.structure_type = GarrisonableStructureScript.StructureType.BUNKER

	building.add_child(garrison)


static func _attach_defense(building: Node3D, data: BuildingData) -> void:
	"""Attach a DefensiveStructure configured from BuildingData weapon/arc fields."""
	if building.has_node("DefensiveStructure"):
		return

	var defense := DefensiveStructureScript.new()
	defense.name = "DefensiveStructure"
	# The building already carries its own GLB/placeholder model - suppress the
	# component's procedural mesh so it does not double up geometry.
	defense.create_own_visuals = false
	defense.weapon_id = data.defense_weapon

	# Prefer explicit attack_range, fall back to weapon_range (arc-display value)
	var effective_range: float = data.attack_range
	if effective_range <= 0.0:
		effective_range = data.weapon_range
	defense.range_override = effective_range

	defense.fire_arc = data.fire_arc
	defense.facing_direction = data.initial_facing
	defense.can_rotate_post_placement = data.rotatable_post_placement
	defense.requires_garrison = data.requires_garrison_to_fire

	# BuildingData.defense_type indexes DefenseType {MG,BUNKER,MORTAR,WATCHTOWER,ARTILLERY}.
	# The kept DefensiveStructure.StructureType shares indices 0-3; index 4 (artillery)
	# maps to MORTAR_PIT so indirect fire skips the line-of-sight check.
	var structure_type: int = data.defense_type
	if structure_type == 4:
		structure_type = DefensiveStructureScript.StructureType.MORTAR_PIT
	defense.structure_type = structure_type

	# Owner faction: player-built firebase defenses are US_ARMY (GameEnums.Faction.US_ARMY=0).
	# Set it EXPLICITLY (not by relying on the component default). Read an override from the
	# owning building if one is present, so a future enemy emplacement wires up correctly.
	# BuildingData intentionally carries no faction field (out of scope).
	var faction: int = 0  # GameEnums.Faction.US_ARMY
	if building.has_method("get") and building.get("faction") != null:
		faction = int(building.get("faction"))
	defense.set_faction(faction)

	defense.building_data = data
	building.add_child(defense)
