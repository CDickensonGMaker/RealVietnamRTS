extends Node3D
class_name ConstructionZone
## ConstructionZone - A zone where buildings can be constructed after clearing

signal clearing_progress_changed(progress: float)
signal construction_progress_changed(progress: float)
signal state_changed(new_state: int)
signal construction_complete(building: Node3D)

# Zone properties
@export var zone_size: Vector2 = Vector2(10, 10)

# State
var clearing_state: int = GameEnums.ClearingState.JUNGLE
var clearing_progress: float = 0.0
var construction_stage: int = GameEnums.ConstructionStage.FOUNDATION
var construction_progress: float = 0.0

# Building being constructed
var current_building_type: int = -1
var building_instance: Node3D = null

# Assigned workers
var assigned_engineers: Array[Node3D] = []

func _ready() -> void:
	add_to_group("construction_zones")

# =============================================================================
# CLEARING
# =============================================================================

func get_state() -> int:
	return clearing_state

func set_state(new_state: int) -> void:
	clearing_state = new_state
	state_changed.emit(new_state)

func is_cleared() -> bool:
	return clearing_state >= GameEnums.ClearingState.CLEARED

func advance_clearing_state() -> void:
	match clearing_state:
		GameEnums.ClearingState.JUNGLE:
			set_state(GameEnums.ClearingState.PARTIALLY_CLEARED)
		GameEnums.ClearingState.PARTIALLY_CLEARED:
			set_state(GameEnums.ClearingState.CLEARED)

func add_clearing_progress(amount: float) -> void:
	clearing_progress += amount
	clearing_progress_changed.emit(clearing_progress)

	if clearing_progress >= 100.0:
		advance_clearing_state()
		clearing_progress = 0.0

# =============================================================================
# CONSTRUCTION
# =============================================================================

func can_build() -> bool:
	return is_cleared() and current_building_type == -1

func start_construction(building_type: int) -> bool:
	if not can_build():
		return false

	current_building_type = building_type
	construction_stage = GameEnums.ConstructionStage.FOUNDATION
	construction_progress = 0.0

	BattleSignals.construction_started.emit(self, building_type)
	return true

func add_construction_progress(amount: float) -> void:
	if current_building_type == -1:
		return

	construction_progress += amount
	construction_progress_changed.emit(construction_progress)

	BattleSignals.construction_progress.emit(self, construction_progress)

	if construction_progress >= 100.0:
		advance_construction_stage()

func advance_construction_stage() -> void:
	construction_progress = 0.0

	match construction_stage:
		GameEnums.ConstructionStage.FOUNDATION:
			construction_stage = GameEnums.ConstructionStage.STRUCTURE
			_spawn_foundation_visuals()
		GameEnums.ConstructionStage.STRUCTURE:
			construction_stage = GameEnums.ConstructionStage.FINISHING
			_spawn_structure_visuals()
		GameEnums.ConstructionStage.FINISHING:
			construction_stage = GameEnums.ConstructionStage.COMPLETE
			_complete_construction()

	BattleSignals.construction_stage_complete.emit(self, construction_stage)

func _spawn_foundation_visuals() -> void:
	# Spawn sandbag outlines, stakes, etc.
	pass

func _spawn_structure_visuals() -> void:
	# Spawn partial walls, framework
	pass

func _complete_construction() -> void:
	# Spawn final building
	var building := _create_building(current_building_type)
	if building:
		building_instance = building
		building.global_position = global_position
		get_parent().add_child(building)

		construction_complete.emit(building)
		BattleSignals.construction_complete.emit(building)

	# Clear state
	current_building_type = -1
	clearing_state = GameEnums.ClearingState.FORTIFIED

func _create_building(building_type: int) -> Node3D:
	# This would load the appropriate building scene
	var scenes := {
		GameEnums.BuildingType.SANDBAG_WALL: "res://firebase_system/buildings/sandbag_wall.tscn",
		GameEnums.BuildingType.BUNKER: "res://firebase_system/buildings/bunker.tscn",
		GameEnums.BuildingType.MACHINE_GUN_NEST: "res://firebase_system/buildings/mg_nest.tscn",
		GameEnums.BuildingType.MORTAR_PIT: "res://firebase_system/buildings/mortar_pit.tscn",
		GameEnums.BuildingType.WIRE_OBSTACLE: "res://firebase_system/buildings/wire.tscn",
		GameEnums.BuildingType.WATCHTOWER: "res://firebase_system/buildings/watchtower.tscn",
		GameEnums.BuildingType.HELIPAD: "res://firebase_system/buildings/helipad.tscn",
		GameEnums.BuildingType.AMMO_BUNKER: "res://firebase_system/buildings/ammo_bunker.tscn",
		GameEnums.BuildingType.MEDICAL_STATION: "res://firebase_system/buildings/medical_station.tscn",
		GameEnums.BuildingType.TOC: "res://firebase_system/buildings/toc.tscn",
		GameEnums.BuildingType.ARTILLERY_PIT: "res://firebase_system/buildings/artillery_pit.tscn",
	}

	var scene_path: String = scenes.get(building_type, "")
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		# Create placeholder
		var placeholder := CSGBox3D.new()
		placeholder.size = Vector3(4, 2, 4)
		return placeholder

	var scene := load(scene_path) as PackedScene
	return scene.instantiate()

# =============================================================================
# ENGINEER MANAGEMENT
# =============================================================================

func assign_engineer(engineer: Node3D) -> void:
	if engineer not in assigned_engineers:
		assigned_engineers.append(engineer)

func remove_engineer(engineer: Node3D) -> void:
	assigned_engineers.erase(engineer)

func get_engineer_count() -> int:
	var count := 0
	for eng in assigned_engineers:
		if is_instance_valid(eng):
			count += 1
	return count

# =============================================================================
# DEBUG
# =============================================================================

func get_debug_info() -> Dictionary:
	return {
		"clearing_state": clearing_state,
		"clearing_progress": clearing_progress,
		"construction_stage": construction_stage,
		"construction_progress": construction_progress,
		"building_type": current_building_type,
		"engineers": get_engineer_count(),
	}
