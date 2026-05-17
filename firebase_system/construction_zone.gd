extends Node3D
class_name ConstructionZone

## Construction Zone - A single construction slot within a firebase
## Handles the construction process for one building

signal construction_started(zone: ConstructionZone)
signal construction_progress(zone: ConstructionZone, progress: float)
signal stage_complete(zone: ConstructionZone, stage: int)
signal construction_complete(zone: ConstructionZone, building: Node3D)
signal construction_cancelled(zone: ConstructionZone)

enum ZoneState { EMPTY, CLEARING, BUILDING, COMPLETE }
enum ConstructionStage { NONE, FOUNDATION, STRUCTURE, FINISHING, COMPLETE }

const BuildingData = preload("res://firebase_system/building_data.gd")

## Building model paths - organized by category
## Models are loaded from res://assets/models/structures/ with subdirectories per category
const BUILDING_MODELS: Dictionary = {
	# =========================================================================
	# FIREBASE PERIMETER
	# =========================================================================
	BuildingData.BuildingType.SANDBAG_LIGHT: "res://assets/models/structures/firebase/sandbag_light.glb",
	BuildingData.BuildingType.SANDBAG_HEAVY: "res://assets/models/structures/firebase/sandbag_heavy.glb",
	BuildingData.BuildingType.BUNKER: "res://assets/models/structures/bunker.glb",
	BuildingData.BuildingType.SANDBAG_BUNKER: "res://assets/models/structures/firebase/sandbag_bunker.glb",
	BuildingData.BuildingType.CONEX_BUNKER: "res://assets/models/structures/firebase/conex_bunker.glb",
	BuildingData.BuildingType.MACHINE_GUN_NEST: "res://assets/models/structures/mg_nest.glb",
	BuildingData.BuildingType.MORTAR_PIT: "res://assets/models/structures/converted/mortar_pit.glb",
	BuildingData.BuildingType.WIRE_OBSTACLE: "res://assets/models/structures/converted/wire_obstacle.glb",
	BuildingData.BuildingType.TRIPLE_CONCERTINA: "res://assets/models/structures/firebase/triple_concertina.glb",
	BuildingData.BuildingType.CLAYMORE_LINE: "res://assets/models/structures/converted/claymore_line.glb",
	BuildingData.BuildingType.WATCHTOWER: "res://assets/models/structures/converted/watchtower.glb",

	# =========================================================================
	# FIREBASE SUPPORT
	# =========================================================================
	BuildingData.BuildingType.HELIPAD: "res://assets/models/structures/converted/helipad.glb",
	BuildingData.BuildingType.PSP_HELIPAD: "res://assets/models/structures/firebase/psp_helipad.glb",
	BuildingData.BuildingType.VIP_HELIPAD: "res://assets/models/structures/firebase/vip_helipad.glb",
	BuildingData.BuildingType.HELICOPTER_REVETMENT: "res://assets/models/structures/firebase/helo_revetment.glb",
	BuildingData.BuildingType.AMMO_BUNKER: "res://assets/models/structures/barracks.glb",
	BuildingData.BuildingType.FUEL_DEPOT: "res://assets/models/structures/converted/fuel_depot.glb",
	BuildingData.BuildingType.FUEL_POINT: "res://assets/models/structures/firebase/fuel_point.glb",
	BuildingData.BuildingType.MEDICAL_STATION: "res://assets/models/structures/converted/tent.glb",
	BuildingData.BuildingType.TOC: "res://assets/models/structures/hq_building.glb",
	BuildingData.BuildingType.COMMO_BUNKER: "res://assets/models/structures/barracks_bunker.glb",

	# =========================================================================
	# FIREBASE LIVING
	# =========================================================================
	BuildingData.BuildingType.HOOTCH: "res://assets/models/structures/firebase/hootch.glb",
	BuildingData.BuildingType.MESS_HALL: "res://assets/models/structures/firebase/mess_hall.glb",
	BuildingData.BuildingType.LATRINE: "res://assets/models/structures/firebase/latrine.glb",
	BuildingData.BuildingType.SHOWER_POINT: "res://assets/models/structures/firebase/shower_point.glb",
	BuildingData.BuildingType.OBSERVATION_TOWER: "res://assets/models/structures/firebase/observation_tower.glb",
	BuildingData.BuildingType.GUARD_TOWER: "res://assets/models/structures/firebase/guard_tower.glb",
	BuildingData.BuildingType.POWDER_BUNKER: "res://assets/models/structures/firebase/powder_bunker.glb",

	# =========================================================================
	# FIREBASE HEAVY
	# =========================================================================
	BuildingData.BuildingType.ARTILLERY_PIT: "res://assets/models/structures/converted/artillery_pit.glb",
	BuildingData.BuildingType.HOWITZER_PIT_105MM: "res://assets/models/structures/firebase/howitzer_pit_105.glb",
	BuildingData.BuildingType.HOWITZER_PIT_155MM: "res://assets/models/structures/firebase/howitzer_pit_155.glb",
	BuildingData.BuildingType.FIRE_DIRECTION_CENTER: "res://assets/models/structures/firebase/fdc.glb",
	BuildingData.BuildingType.TANK_REVETMENT: "res://assets/models/structures/converted/tank_revetment.glb",
	BuildingData.BuildingType.OPEN_REVETMENT: "res://assets/models/structures/firebase/open_revetment.glb",

	# =========================================================================
	# VIETNAMESE VILLAGE
	# =========================================================================
	BuildingData.BuildingType.THATCHED_HUT: "res://assets/models/structures/village/thatched_hut.glb",
	BuildingData.BuildingType.CLAY_WALL_COTTAGE: "res://assets/models/structures/village/clay_cottage.glb",
	BuildingData.BuildingType.STILT_HOUSE: "res://assets/models/structures/village/stilt_house.glb",
	BuildingData.BuildingType.THREE_ROOM_HOUSE: "res://assets/models/structures/village/three_room_house.glb",
	BuildingData.BuildingType.COMMUNAL_HOUSE: "res://assets/models/structures/village/communal_house.glb",
	BuildingData.BuildingType.VILLAGE_WELL: "res://assets/models/structures/village/well.glb",
	BuildingData.BuildingType.RICE_STORAGE_SHED: "res://assets/models/structures/village/rice_storage.glb",
	BuildingData.BuildingType.WATER_BUFFALO_SHED: "res://assets/models/structures/village/buffalo_shed.glb",
	BuildingData.BuildingType.BAMBOO_FENCE: "res://assets/models/structures/village/bamboo_fence.glb",
	BuildingData.BuildingType.VILLAGE_GATE: "res://assets/models/structures/village/village_gate.glb",
	BuildingData.BuildingType.VILLAGE_PAGODA: "res://assets/models/structures/village/pagoda.glb",
	BuildingData.BuildingType.TAM_QUAN_GATE: "res://assets/models/structures/village/tam_quan_gate.glb",
	BuildingData.BuildingType.BELL_TOWER: "res://assets/models/structures/village/bell_tower.glb",
	BuildingData.BuildingType.MONK_QUARTERS: "res://assets/models/structures/village/monk_quarters.glb",
	BuildingData.BuildingType.STONE_BUDDHA: "res://assets/models/structures/village/stone_buddha.glb",

	# =========================================================================
	# AIRFIELD STRUCTURES
	# =========================================================================
	BuildingData.BuildingType.RUNWAY_CONCRETE: "res://assets/models/structures/airfield/runway_concrete.glb",
	BuildingData.BuildingType.RUNWAY_PSP: "res://assets/models/structures/airfield/runway_psp.glb",
	BuildingData.BuildingType.RUNWAY_AM2: "res://assets/models/structures/airfield/runway_am2.glb",
	BuildingData.BuildingType.TAXIWAY_SECTION: "res://assets/models/structures/airfield/taxiway.glb",
	BuildingData.BuildingType.RUNWAY_CRATER: "res://assets/models/structures/airfield/runway_crater.glb",
	BuildingData.BuildingType.WONDERARCH_SHELTER: "res://assets/models/structures/airfield/wonderarch.glb",
	BuildingData.BuildingType.PSP_REVETMENT: "res://assets/models/structures/airfield/psp_revetment.glb",
	BuildingData.BuildingType.AIRCRAFT_HANGAR: "res://assets/models/structures/airfield/hangar.glb",
	BuildingData.BuildingType.MAINTENANCE_SHOP: "res://assets/models/structures/airfield/maintenance_shop.glb",
	BuildingData.BuildingType.CONTROL_TOWER: "res://assets/models/structures/airfield/control_tower.glb",
	BuildingData.BuildingType.RADAR_DOME: "res://assets/models/structures/airfield/radar_dome.glb",
	BuildingData.BuildingType.OPERATIONS_BUILDING: "res://assets/models/structures/airfield/ops_building.glb",
	BuildingData.BuildingType.POL_STORAGE: "res://assets/models/structures/airfield/pol_storage.glb",
	BuildingData.BuildingType.FIRE_STATION: "res://assets/models/structures/airfield/fire_station.glb",
	BuildingData.BuildingType.AMMO_STORAGE_AIRFIELD: "res://assets/models/structures/airfield/ammo_storage.glb",
	BuildingData.BuildingType.QUONSET_HUT: "res://assets/models/structures/airfield/quonset_hut.glb",
	BuildingData.BuildingType.SUPPLY_WAREHOUSE: "res://assets/models/structures/airfield/warehouse.glb",
	BuildingData.BuildingType.AMMO_DUMP_BUNKER: "res://assets/models/structures/airfield/ammo_dump.glb",
	BuildingData.BuildingType.POL_TANK_FARM: "res://assets/models/structures/airfield/tank_farm.glb",

	# =========================================================================
	# FRENCH COLONIAL
	# =========================================================================
	BuildingData.BuildingType.COLONIAL_VILLA: "res://assets/models/structures/colonial/villa.glb",
	BuildingData.BuildingType.PLANTATION_HOUSE: "res://assets/models/structures/colonial/plantation_house.glb",
	BuildingData.BuildingType.GOVERNMENT_BUILDING: "res://assets/models/structures/colonial/government.glb",
	BuildingData.BuildingType.FRENCH_BARRACKS: "res://assets/models/structures/colonial/barracks.glb",
	BuildingData.BuildingType.COLONIAL_PRISON: "res://assets/models/structures/colonial/prison.glb",
	BuildingData.BuildingType.RUBBER_PLANT: "res://assets/models/structures/colonial/rubber_plant.glb",
	BuildingData.BuildingType.COLONIAL_WAREHOUSE: "res://assets/models/structures/colonial/warehouse.glb",
	BuildingData.BuildingType.RAILWAY_STATION: "res://assets/models/structures/colonial/railway_station.glb",
	BuildingData.BuildingType.CUSTOMS_BUILDING: "res://assets/models/structures/colonial/customs.glb",

	# =========================================================================
	# INFRASTRUCTURE
	# =========================================================================
	BuildingData.BuildingType.STEEL_TRUSS_BRIDGE: "res://assets/models/structures/infrastructure/steel_bridge.glb",
	BuildingData.BuildingType.WOODEN_BRIDGE: "res://assets/models/structures/infrastructure/wooden_bridge.glb",
	BuildingData.BuildingType.PONTOON_BRIDGE: "res://assets/models/structures/infrastructure/pontoon_bridge.glb",
	BuildingData.BuildingType.STONE_ARCH_BRIDGE: "res://assets/models/structures/infrastructure/stone_bridge.glb",
	BuildingData.BuildingType.DOCK_PIER: "res://assets/models/structures/infrastructure/dock.glb",
	BuildingData.BuildingType.CARGO_CRANE: "res://assets/models/structures/infrastructure/crane.glb",
	BuildingData.BuildingType.CONTAINER_YARD: "res://assets/models/structures/infrastructure/container_yard.glb",
	BuildingData.BuildingType.DIRT_ROAD_SECTION: "res://assets/models/structures/infrastructure/dirt_road.glb",
	BuildingData.BuildingType.LATERITE_ROAD: "res://assets/models/structures/infrastructure/laterite_road.glb",
	BuildingData.BuildingType.PAVED_ROAD_SECTION: "res://assets/models/structures/infrastructure/paved_road.glb",
	BuildingData.BuildingType.TRAIL_PATH: "res://assets/models/structures/infrastructure/trail.glb",

	# =========================================================================
	# VC/NVA SPECIAL
	# =========================================================================
	BuildingData.BuildingType.TUNNEL_ENTRANCE_HIDDEN: "res://assets/models/structures/vc_nva/tunnel_hidden.glb",
	BuildingData.BuildingType.TUNNEL_ENTRANCE_EXPOSED: "res://assets/models/structures/vc_nva/tunnel_exposed.glb",
	BuildingData.BuildingType.SPIDER_HOLE: "res://assets/models/structures/vc_nva/spider_hole.glb",
	BuildingData.BuildingType.PUNJI_PIT: "res://assets/models/structures/vc_nva/punji_pit.glb",
	BuildingData.BuildingType.UNDERGROUND_HOSPITAL: "res://assets/models/structures/vc_nva/underground_hospital.glb",
	BuildingData.BuildingType.WEAPONS_CACHE: "res://assets/models/structures/vc_nva/weapons_cache.glb",
	BuildingData.BuildingType.STOCKADE_COMPOUND: "res://assets/models/structures/vc_nva/stockade.glb",
	BuildingData.BuildingType.PRISONER_TENT: "res://assets/models/structures/vc_nva/prisoner_tent.glb",

	# =========================================================================
	# RUINS & DESTRUCTION
	# =========================================================================
	BuildingData.BuildingType.CRATER_FIELD: "res://assets/models/structures/ruins/crater_field.glb",
	BuildingData.BuildingType.COLLAPSED_BUILDING: "res://assets/models/structures/ruins/collapsed_building.glb",
	BuildingData.BuildingType.BURNED_STRUCTURE: "res://assets/models/structures/ruins/burned_structure.glb",
	BuildingData.BuildingType.PARTIAL_RUINS: "res://assets/models/structures/ruins/partial_ruins.glb",
	BuildingData.BuildingType.FOUNDATION_ONLY: "res://assets/models/structures/ruins/foundation.glb",
	BuildingData.BuildingType.DESTROYED_VILLAGE: "res://assets/models/structures/ruins/destroyed_village.glb",
	BuildingData.BuildingType.BOMBED_PAGODA: "res://assets/models/structures/ruins/bombed_pagoda.glb",
	BuildingData.BuildingType.CRATERED_RUNWAY: "res://assets/models/structures/ruins/cratered_runway.glb",
	BuildingData.BuildingType.BURNED_BUNKER: "res://assets/models/structures/ruins/burned_bunker.glb",
	BuildingData.BuildingType.DESTROYED_BRIDGE: "res://assets/models/structures/ruins/destroyed_bridge.glb",
	BuildingData.BuildingType.RUBBLE_PILE: "res://assets/models/structures/ruins/rubble_pile.glb",
	BuildingData.BuildingType.CONEX_CELL: "res://assets/models/structures/vc_nva/conex_cell.glb",

	# =========================================================================
	# CHAM RUINS
	# =========================================================================
	BuildingData.BuildingType.CHAM_TEMPLE_TOWER: "res://assets/models/structures/cham/temple_tower.glb",
	BuildingData.BuildingType.CHAM_TEMPLE_BASE: "res://assets/models/structures/cham/temple_base.glb",
	BuildingData.BuildingType.CHAM_BROKEN_COLUMN: "res://assets/models/structures/cham/broken_column.glb",

	# =========================================================================
	# COMMERCIAL / MARKETPLACE
	# =========================================================================
	BuildingData.BuildingType.MARKET_HALL: "res://assets/models/structures/commercial/market_hall.glb",
	BuildingData.BuildingType.SHOP_HOUSE: "res://assets/models/structures/commercial/shop_house.glb",
	BuildingData.BuildingType.MARKET_STALL: "res://assets/models/structures/commercial/market_stall.glb",
	BuildingData.BuildingType.FOOD_VENDOR_CART: "res://assets/models/structures/commercial/vendor_cart.glb",
}

## Configuration
@export var zone_size: Vector2 = Vector2(5, 5)

## State
var state: ZoneState = ZoneState.EMPTY
var construction_stage: ConstructionStage = ConstructionStage.NONE
var building_data: BuildingData = null
var current_progress: float = 0.0
var total_work_done: float = 0.0

## Building reference
var completed_building: Node3D = null
var _construction_mesh: MeshInstance3D = null

## Destruction state
var current_destruction_state: BuildingData.DestructionState = BuildingData.DestructionState.INTACT

## Workers
var assigned_engineers: Array[Node3D] = []


func _ready() -> void:
	_create_zone_marker()


func _create_zone_marker() -> void:
	"""Create visual marker for empty zone"""
	var marker := MeshInstance3D.new()
	marker.name = "ZoneMarker"

	var plane := PlaneMesh.new()
	plane.size = zone_size
	marker.mesh = plane
	marker.position.y = 0.05

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.5, 0.3, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = mat

	add_child(marker)


func start_construction(data: BuildingData) -> bool:
	"""Begin construction of a building"""
	if state != ZoneState.EMPTY:
		return false

	building_data = data
	state = ZoneState.BUILDING
	construction_stage = ConstructionStage.FOUNDATION
	current_progress = 0.0
	total_work_done = 0.0

	# NOTE: Vegetation clearing is now handled by the job system
	# When CLEAR_TERRAIN job completes, JobManager clears vegetation
	# This prevents instant clearing when ghost is placed

	_create_construction_visual()
	construction_started.emit(self)

	if BattleSignals:
		BattleSignals.construction_started.emit(self, data.building_type)

	return true


func _clear_vegetation_for_building() -> void:
	"""DEPRECATED: Vegetation clearing now handled by JobManager when CLEAR_TERRAIN completes.
	This function is kept for reference but no longer called."""
	push_warning("_clear_vegetation_for_building is deprecated - use JobManager")
	var terrain_integration: Node = get_node_or_null("/root/TerrainIntegration")
	if not terrain_integration:
		return

	# Calculate clearing radius based on building footprint + 5m buffer
	var clear_radius: float = 5.0
	if building_data:
		# Use half the larger footprint dimension + 5m buffer
		var footprint_radius: float = maxf(building_data.footprint_size.x, building_data.footprint_size.y) * 0.5
		clear_radius = footprint_radius + 5.0

	# Clear vegetation around the building position
	if terrain_integration.has_method("clear_vegetation_around_building"):
		terrain_integration.clear_vegetation_around_building(global_position, clear_radius)


func add_work(amount: float) -> void:
	"""Add construction work (from engineers)"""
	if state != ZoneState.BUILDING:
		return

	current_progress += amount
	total_work_done += amount

	var stage_requirement: float = _get_stage_requirement()

	# Check for stage completion
	if current_progress >= stage_requirement:
		current_progress -= stage_requirement
		_advance_stage()

	# Emit progress
	var total_required: float = _get_total_work_required()
	var overall_progress: float = total_work_done / total_required if total_required > 0 else 0.0
	construction_progress.emit(self, overall_progress)

	# Update visual
	_update_construction_visual()


func _get_stage_requirement() -> float:
	"""Get work required for current stage"""
	if not building_data:
		return 0.0

	var stage_index: int = int(construction_stage) - 1
	if stage_index >= 0 and stage_index < building_data.stage_work.size():
		return building_data.stage_work[stage_index]
	return 0.0


func _get_total_work_required() -> float:
	"""Get total work for all stages"""
	if not building_data:
		return 0.0

	var total: float = 0.0
	for work in building_data.stage_work:
		total += work
	return total


func _advance_stage() -> void:
	"""Move to next construction stage"""
	match construction_stage:
		ConstructionStage.FOUNDATION:
			construction_stage = ConstructionStage.STRUCTURE
			stage_complete.emit(self, 1)
		ConstructionStage.STRUCTURE:
			construction_stage = ConstructionStage.FINISHING
			stage_complete.emit(self, 2)
		ConstructionStage.FINISHING:
			construction_stage = ConstructionStage.COMPLETE
			_complete_construction()
			stage_complete.emit(self, 3)


func _complete_construction() -> void:
	"""Finish construction and spawn building"""
	state = ZoneState.COMPLETE

	# Remove construction visual
	if _construction_mesh:
		_construction_mesh.queue_free()
		_construction_mesh = null

	# Create final building
	completed_building = _create_building()
	construction_complete.emit(self, completed_building)

	if BattleSignals:
		BattleSignals.construction_complete.emit(completed_building)


func _create_building() -> Node3D:
	"""Create the completed building node"""
	var building := Node3D.new()
	building.name = building_data.display_name.replace(" ", "_")

	# Try to load GLB model first
	var model_loaded: bool = false
	if building_data.building_type in BUILDING_MODELS:
		var model_path: String = BUILDING_MODELS[building_data.building_type]
		if ResourceLoader.exists(model_path):
			var model_scene: PackedScene = load(model_path)
			if model_scene:
				var model_instance: Node3D = model_scene.instantiate()
				building.add_child(model_instance)
				model_loaded = true
				print("[ConstructionZone] Loaded building model: ", model_path)

	# Fall back to placeholder box if no model
	if not model_loaded:
		var mesh := MeshInstance3D.new()
		mesh.name = "BuildingMesh"

		var box := BoxMesh.new()
		var height: float = building_data.height if building_data.height > 0 else 2.0
		box.size = Vector3(building_data.footprint_size.x, height, building_data.footprint_size.y)
		mesh.mesh = box
		mesh.position.y = height * 0.5

		# Color based on building category
		var mat := StandardMaterial3D.new()
		match building_data.category:
			BuildingData.BuildingCategory.FIREBASE_PERIMETER:
				mat.albedo_color = Color(0.45, 0.4, 0.35)  # Tan/sandbag
			BuildingData.BuildingCategory.FIREBASE_SUPPORT:
				mat.albedo_color = Color(0.35, 0.4, 0.25)  # Olive drab
			BuildingData.BuildingCategory.FIREBASE_LIVING:
				mat.albedo_color = Color(0.5, 0.45, 0.35)  # Light brown canvas
			BuildingData.BuildingCategory.FIREBASE_HEAVY:
				mat.albedo_color = Color(0.4, 0.35, 0.3)  # Gray-brown
			BuildingData.BuildingCategory.VIETNAMESE_VILLAGE:
				mat.albedo_color = Color(0.6, 0.5, 0.35)  # Bamboo/straw
			BuildingData.BuildingCategory.AIRFIELD:
				mat.albedo_color = Color(0.3, 0.3, 0.3)  # Dark gray concrete
			BuildingData.BuildingCategory.FRENCH_COLONIAL:
				mat.albedo_color = Color(0.85, 0.8, 0.7)  # Colonial white/cream
			BuildingData.BuildingCategory.INFRASTRUCTURE:
				mat.albedo_color = Color(0.4, 0.4, 0.4)  # Gray
			BuildingData.BuildingCategory.VC_NVA_SPECIAL:
				mat.albedo_color = Color(0.35, 0.3, 0.25)  # Dark earth
			BuildingData.BuildingCategory.RUINS:
				mat.albedo_color = Color(0.3, 0.25, 0.2)  # Charred/dark
			BuildingData.BuildingCategory.CHAM_RUINS:
				mat.albedo_color = Color(0.55, 0.35, 0.25)  # Ancient brick
			BuildingData.BuildingCategory.COMMERCIAL:
				mat.albedo_color = Color(0.65, 0.55, 0.4)  # Wood/market
			_:
				mat.albedo_color = Color(0.45, 0.4, 0.35)  # Default tan

		mesh.material_override = mat
		building.add_child(mesh)

	add_child(building)
	building.position = Vector3.ZERO

	return building


func _create_construction_visual() -> void:
	"""Create in-progress construction visual"""
	_construction_mesh = MeshInstance3D.new()
	_construction_mesh.name = "ConstructionMesh"

	var box := BoxMesh.new()
	box.size = Vector3(building_data.footprint_size.x, 0.5, building_data.footprint_size.y)
	_construction_mesh.mesh = box
	_construction_mesh.position.y = 0.25

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.5, 0.3, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_construction_mesh.material_override = mat

	add_child(_construction_mesh)


func _update_construction_visual() -> void:
	"""Update construction visual based on progress - simplified staged approach"""
	if not _construction_mesh:
		return

	var total_required: float = _get_total_work_required()
	var progress: float = total_work_done / total_required if total_required > 0 else 0.0

	# Get building dimensions
	var footprint_x: float = 4.0
	var footprint_z: float = 4.0
	var target_height: float = 2.5

	if building_data:
		footprint_x = building_data.footprint_size.x
		footprint_z = building_data.footprint_size.y
		target_height = building_data.height if building_data.height > 0 else 2.5

	# Get or create material
	var mat: StandardMaterial3D = _construction_mesh.material_override as StandardMaterial3D
	if not mat:
		mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_construction_mesh.material_override = mat

	# Simple staged visuals using BoxMesh
	match construction_stage:
		ConstructionStage.FOUNDATION:
			# Stage 1: Flat foundation pad
			var box := BoxMesh.new()
			box.size = Vector3(footprint_x, 0.3, footprint_z)
			_construction_mesh.mesh = box
			_construction_mesh.position.y = 0.15
			mat.albedo_color = Color(0.5, 0.5, 0.5, 0.9)  # Gray concrete

		ConstructionStage.STRUCTURE:
			# Stage 2: Building rising (height based on progress within stage)
			var stage_progress: float = current_progress / _get_stage_requirement() if _get_stage_requirement() > 0 else 0.0
			var current_height: float = target_height * (0.3 + stage_progress * 0.7)

			var box := BoxMesh.new()
			box.size = Vector3(footprint_x, current_height, footprint_z)
			_construction_mesh.mesh = box
			_construction_mesh.position.y = current_height * 0.5
			mat.albedo_color = Color(0.6, 0.5, 0.35, 0.7)  # Wood/framework color

		ConstructionStage.FINISHING:
			# Stage 3: Full building at reduced opacity
			var stage_progress: float = current_progress / _get_stage_requirement() if _get_stage_requirement() > 0 else 0.0
			var opacity: float = 0.5 + stage_progress * 0.4

			var box := BoxMesh.new()
			box.size = Vector3(footprint_x, target_height, footprint_z)
			_construction_mesh.mesh = box
			_construction_mesh.position.y = target_height * 0.5
			mat.albedo_color = Color(0.7, 0.6, 0.5, opacity)  # Near-final color

		_:
			# Default box
			var box := BoxMesh.new()
			box.size = Vector3(footprint_x, 0.5, footprint_z)
			_construction_mesh.mesh = box
			_construction_mesh.position.y = 0.25
			mat.albedo_color = Color(0.5, 0.4, 0.3, 0.6)


func cancel_construction() -> void:
	"""Cancel ongoing construction"""
	if state != ZoneState.BUILDING:
		return

	if _construction_mesh:
		_construction_mesh.queue_free()
		_construction_mesh = null

	state = ZoneState.EMPTY
	construction_stage = ConstructionStage.NONE
	building_data = null
	current_progress = 0.0
	total_work_done = 0.0

	construction_cancelled.emit(self)


func assign_engineer(engineer: Node3D) -> void:
	"""Assign an engineer to work on this zone"""
	if engineer not in assigned_engineers:
		assigned_engineers.append(engineer)


func unassign_engineer(engineer: Node3D) -> void:
	"""Remove engineer from this zone"""
	assigned_engineers.erase(engineer)


func get_progress_percent() -> float:
	"""Get overall construction progress as percentage"""
	var total_required: float = _get_total_work_required()
	if total_required <= 0:
		return 0.0
	return (total_work_done / total_required) * 100.0


func is_empty() -> bool:
	return state == ZoneState.EMPTY


func is_building() -> bool:
	return state == ZoneState.BUILDING


func is_complete() -> bool:
	return state == ZoneState.COMPLETE


## =============================================================================
## DESTRUCTION STATE MANAGEMENT
## =============================================================================

func set_destruction_state(new_state: BuildingData.DestructionState) -> void:
	"""Change the building's destruction state and update visual"""
	if not building_data:
		return

	# Check if the new state is valid for this building
	if new_state not in building_data.destruction_states:
		push_warning("Destruction state %s not valid for building %s" % [new_state, building_data.display_name])
		return

	current_destruction_state = new_state

	# Update the building visual
	if completed_building:
		_update_building_for_destruction_state()


func _update_building_for_destruction_state() -> void:
	"""Update the building model/visual for current destruction state"""
	if not completed_building or not building_data:
		return

	# Try to load destruction variant model
	var model_loaded: bool = false

	if building_data.building_type in BUILDING_MODELS:
		var base_path: String = BUILDING_MODELS[building_data.building_type]
		var variant_path: String = _get_destruction_variant_path(base_path)

		if ResourceLoader.exists(variant_path):
			# Remove existing visual children
			for child in completed_building.get_children():
				child.queue_free()

			# Load destruction variant
			var model_scene: PackedScene = load(variant_path)
			if model_scene:
				var model_instance: Node3D = model_scene.instantiate()
				completed_building.add_child(model_instance)
				model_loaded = true
				print("[ConstructionZone] Loaded destruction variant: ", variant_path)

	# If no variant model, apply visual effects to indicate destruction
	if not model_loaded:
		_apply_destruction_visual_effects()


func _get_destruction_variant_path(base_path: String) -> String:
	"""Get the model path for current destruction state"""
	if current_destruction_state == BuildingData.DestructionState.INTACT:
		return base_path

	var suffix: String = BuildingData.get_destruction_model_suffix(current_destruction_state)
	if suffix.is_empty():
		return base_path

	# Insert suffix before file extension
	var extension_idx: int = base_path.rfind(".")
	if extension_idx > 0:
		return base_path.substr(0, extension_idx) + suffix + base_path.substr(extension_idx)

	return base_path + suffix


func _apply_destruction_visual_effects() -> void:
	"""Apply visual effects to indicate destruction state when no variant model exists"""
	if not completed_building:
		return

	# Find mesh instances and modify their appearance
	var meshes: Array[Node] = completed_building.find_children("*", "MeshInstance3D", true, false)

	for node in meshes:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if not mesh_instance:
			continue

		var mat: StandardMaterial3D = mesh_instance.get_active_material(0) as StandardMaterial3D
		if not mat:
			mat = StandardMaterial3D.new()
			mesh_instance.material_override = mat

		match current_destruction_state:
			BuildingData.DestructionState.DAMAGED:
				# Darken slightly and add roughness
				mat.albedo_color = mat.albedo_color.darkened(0.2)
				mat.roughness = minf(mat.roughness + 0.2, 1.0)

			BuildingData.DestructionState.BURNED:
				# Blacken the material
				mat.albedo_color = Color(0.15, 0.1, 0.08)
				mat.roughness = 1.0

			BuildingData.DestructionState.RUINS, BuildingData.DestructionState.DESTROYED:
				# Gray/rubble coloring
				mat.albedo_color = Color(0.35, 0.3, 0.25)
				mat.roughness = 0.9

			BuildingData.DestructionState.EXPLODED:
				# Dark with hints of char
				mat.albedo_color = Color(0.2, 0.15, 0.1)
				mat.roughness = 1.0

			BuildingData.DestructionState.COLLAPSED:
				# Concrete dust gray
				mat.albedo_color = Color(0.5, 0.48, 0.45)
				mat.roughness = 0.95

			BuildingData.DestructionState.CRATERED:
				# Earth brown
				mat.albedo_color = Color(0.4, 0.3, 0.2)
				mat.roughness = 0.85


func get_destruction_state() -> BuildingData.DestructionState:
	"""Get current destruction state"""
	return current_destruction_state


func can_transition_to_destruction_state(target_state: BuildingData.DestructionState) -> bool:
	"""Check if building can transition to a destruction state"""
	if not building_data:
		return false
	return target_state in building_data.destruction_states
