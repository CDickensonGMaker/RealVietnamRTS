extends Node3D

## Helicopter Shuttle Test Scene
## Demonstrates player-driven helicopter troop transport with:
## - 1 Huey helicopter
## - Loading Zone (pickup point)
## - Destination LZ (drop-off point)
## - 2 infantry squads (12 soldiers each) starting at loading zone
##
## Uses BattleHUD autoload for unified selection/command UI.
## Uses SelectionManager autoload for drag-box selection.
##
## Controls:
## - Left-click drag: Select squad (via SelectionManager)
## - Right-click: Move selected squad (via MoveOrderHandler)
## - L: Load selected squad into helicopter
## - Ctrl+1-9: Save group / 1-9: Recall
## - Space: Focus camera on selection

const TestSceneBase = preload("res://test_scenes/common/test_scene_base.gd")

## Scene references
@onready var helicopter: Node3D = $Helicopter
@onready var loading_zone: Node3D = $Zones/LoadingZone
@onready var destination_lz: Node3D = $Zones/DestinationLZ
@onready var squads_container: Node3D = $Units/Squads

## Camera reference (set by TestSceneBase)
var camera: Camera3D

## HUD label for scene-specific info
var hud_label: Label


func _ready() -> void:
	# Use TestSceneBase for consistent environment - but we already have env in scene
	# Just create the camera and HUD
	var setup: Dictionary = TestSceneBase.setup_environment(self, {
		"seed": 11111,
		"size": 150.0,
		"name": "Helicopter Shuttle Test",
		"camera_position": Vector3(0.0, 50.0, 50.0),
		"add_camera": false,  # We use the camera from the scene
	})

	# Use existing camera from scene
	camera = $Camera3D
	if camera:
		camera.add_to_group("battle_camera")

	# Create test-specific HUD label (top-left)
	hud_label = TestSceneBase.make_hud(self)

	# Configure helicopter zone references
	helicopter.loading_zone = loading_zone
	helicopter.destination_lz = destination_lz

	# Connect helicopter signals
	helicopter.state_changed.connect(_on_helicopter_state_changed)
	helicopter.loading_complete.connect(_on_loading_complete)
	helicopter.unloading_complete.connect(_on_unloading_complete)

	# Spawn squads
	_spawn_squads()

	print("=== Helicopter Shuttle Test ===")
	print("Select squad with left-click drag")
	print("L: Load selected squad into helicopter")
	print("Right-click: Move selected squad")


func _spawn_squads() -> void:
	"""Create infantry squads at loading zone"""
	# Squad Alpha - 12-man rifle squad
	var squad_alpha := CharacterBody3D.new()
	squad_alpha.set_script(preload("res://battle_system/nodes/infantry_squad.gd"))
	squad_alpha.name = "SquadAlpha"
	squad_alpha.squad_name = "Alpha"
	squad_alpha.squad_type = InfantrySquad.SquadType.RIFLE  # 12 soldiers
	squad_alpha.soldier_color = Color(0.2, 0.5, 0.2)  # OD Green
	squad_alpha.position = loading_zone.position + Vector3(-10, 0, -8)
	squads_container.add_child(squad_alpha)

	# Squad Bravo - 12-man rifle squad
	var squad_bravo := CharacterBody3D.new()
	squad_bravo.set_script(preload("res://battle_system/nodes/infantry_squad.gd"))
	squad_bravo.name = "SquadBravo"
	squad_bravo.squad_name = "Bravo"
	squad_bravo.squad_type = InfantrySquad.SquadType.RIFLE  # 12 soldiers
	squad_bravo.soldier_color = Color(0.25, 0.45, 0.25)  # Slightly different green
	squad_bravo.position = loading_zone.position + Vector3(-10, 0, 8)
	squads_container.add_child(squad_bravo)


func _input(event: InputEvent) -> void:
	# Handle scene-specific hotkeys
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_L:
				_load_selected_squad()


func _load_selected_squad() -> void:
	"""Load the selected squad into the helicopter"""
	var sel_mgr: Node = get_node_or_null("/root/SelectionManager")
	if not sel_mgr:
		print("[HeliShuttleTest] SelectionManager not found")
		return

	var selected: Array[Node3D] = sel_mgr.get_selected_units()
	if selected.is_empty():
		print("[HeliShuttleTest] No squad selected")
		return

	if not helicopter.is_waiting_for_troops():
		print("[HeliShuttleTest] Helicopter not ready for loading")
		return

	# Get the first selected squad
	var squad: Node3D = null
	for unit in selected:
		if unit.is_in_group("squads"):
			squad = unit
			break

	if not squad:
		print("[HeliShuttleTest] No squad in selection")
		return

	# Load the squad
	if helicopter.load_squad(squad):
		# Deselect the loaded squad
		if squad.has_method("deselect"):
			squad.deselect()
		sel_mgr.clear_selection()
		print("[HeliShuttleTest] Loaded squad: %s" % squad.squad_name)


func _on_helicopter_state_changed(_heli: Node3D, _new_state: int) -> void:
	"""Update when helicopter state changes"""
	pass  # HUD updates in _process


func _on_loading_complete(_heli: Node3D, squad: Node3D) -> void:
	"""Handle loading completion"""
	var squad_name: String = squad.squad_name if "squad_name" in squad else "Squad"
	print("[HeliShuttleTest] Loaded %s" % squad_name)


func _on_unloading_complete(_heli: Node3D, squad: Node3D) -> void:
	"""Handle unloading completion"""
	var squad_name: String = squad.squad_name if "squad_name" in squad else "Squad"
	print("[HeliShuttleTest] Unloaded %s at LZ" % squad_name)


func _process(_delta: float) -> void:
	_update_hud()


func _update_hud() -> void:
	"""Update HUD with helicopter status"""
	if not hud_label:
		return

	var sel_mgr: Node = get_node_or_null("/root/SelectionManager")
	var selected_count: int = 0
	if sel_mgr and sel_mgr.has_method("get_selected_units"):
		selected_count = sel_mgr.get_selected_units().size()

	var cargo_text: String = "Empty"
	if helicopter.has_cargo():
		var squad: Node3D = helicopter.get_cargo_squad()
		if squad and "squad_name" in squad:
			cargo_text = squad.squad_name
		else:
			cargo_text = "Squad loaded"

	var lines: PackedStringArray = [
		"HELICOPTER SHUTTLE TEST",
		"",
		"Helicopter: %s" % helicopter.get_state_name(),
		"Cargo: %s" % cargo_text,
		"",
		"Selected: %d squad(s)" % selected_count,
		"",
		"L: Load selected squad",
	]

	hud_label.text = "\n".join(lines)
