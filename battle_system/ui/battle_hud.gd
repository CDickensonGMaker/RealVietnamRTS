extends Node
## Main HUD controller that owns and coordinates all HUD elements.
## Manages cursor mode, targeting overlay, minimap, and HUD panels.

const MilitaryTheme = preload("res://battle_system/ui/military_theme.gd")
const CursorModeScript = preload("res://battle_system/ui/cursor_mode.gd")
const SelectionCardScript = preload("res://battle_system/ui/selection_card.gd")
const CommandPanelScript = preload("res://battle_system/ui/command_panel.gd")
const TargetingOverlayScript = preload("res://battle_system/ui/targeting_overlay.gd")
const TacticalMinimapScript = preload("res://battle_system/ui/tactical_minimap.gd")

# =============================================================================
# STATE
# =============================================================================

var _hud_layer: CanvasLayer
var _selection_card: Control
var _command_panel: Control
var _targeting_overlay: Node3D
var _objective_label: Label
var _tactical_minimap: SubViewportContainer

var _cursor_mode: int = CursorModeScript.Mode.NORMAL
var _player_faction: int = 0  # GameEnums.Faction.US_ARMY

## Context data for current cursor mode
var _mode_context: Dictionary = {}

## Active objective timer (for memory leak prevention)
var _objective_timer: SceneTreeTimer = null

## Cached autoload reference (performance optimization)
var _selection_manager: Node = null

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Cache autoload reference
	_selection_manager = get_node_or_null("/root/SelectionManager")

	_build_hud()
	_connect_signals()
	print("[BattleHUD] Initialized")


func _input(event: InputEvent) -> void:
	# Handle mode cancellation with Escape
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if CursorModeScript.canceled_by_escape(_cursor_mode):
				set_cursor_mode(CursorModeScript.Mode.NORMAL)
				get_viewport().set_input_as_handled()
				return

	# Handle right-click commit in special modes
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if CursorModeScript.right_click_commits(_cursor_mode):
				_commit_current_mode()
				get_viewport().set_input_as_handled()
				return

		# Left-click cancels special modes
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _cursor_mode != CursorModeScript.Mode.NORMAL:
				set_cursor_mode(CursorModeScript.Mode.NORMAL)
				# Don't consume - let selection happen


func _build_hud() -> void:
	# Create HUD layer (above game, below menus)
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 10
	_hud_layer.name = "HUDLayer"
	add_child(_hud_layer)

	# Create base control for anchoring
	var base := Control.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(base)

	# Selection card (bottom-left)
	_selection_card = SelectionCardScript.new()
	_selection_card.anchor_left = 0.0
	_selection_card.anchor_right = 0.0
	_selection_card.anchor_top = 1.0
	_selection_card.anchor_bottom = 1.0
	_selection_card.offset_left = 10
	_selection_card.offset_top = -190
	_selection_card.offset_right = 330
	_selection_card.offset_bottom = -10
	base.add_child(_selection_card)

	# Command panel (bottom-right)
	_command_panel = CommandPanelScript.new()
	_command_panel.anchor_left = 1.0
	_command_panel.anchor_right = 1.0
	_command_panel.anchor_top = 1.0
	_command_panel.anchor_bottom = 1.0
	_command_panel.offset_left = -290
	_command_panel.offset_top = -150
	_command_panel.offset_right = -10
	_command_panel.offset_bottom = -10
	base.add_child(_command_panel)

	# Objective label (top-center, for mission objectives)
	_objective_label = Label.new()
	_objective_label.anchor_left = 0.5
	_objective_label.anchor_right = 0.5
	_objective_label.anchor_top = 0.0
	_objective_label.anchor_bottom = 0.0
	_objective_label.offset_left = -200
	_objective_label.offset_top = 50
	_objective_label.offset_right = 200
	_objective_label.offset_bottom = 80
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.add_theme_font_size_override("font_size", 18)
	_objective_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_HIGHLIGHT)
	_objective_label.visible = false
	base.add_child(_objective_label)

	# Tactical minimap (top-right corner)
	_tactical_minimap = TacticalMinimapScript.new()
	_tactical_minimap.anchor_left = 1.0
	_tactical_minimap.anchor_right = 1.0
	_tactical_minimap.anchor_top = 0.0
	_tactical_minimap.anchor_bottom = 0.0
	_tactical_minimap.offset_left = -210
	_tactical_minimap.offset_top = 10
	_tactical_minimap.offset_right = -10
	_tactical_minimap.offset_bottom = 210
	_tactical_minimap.custom_minimum_size = Vector2(200, 200)
	_tactical_minimap.stretch = true
	base.add_child(_tactical_minimap)

	# Add panel background behind minimap for military theme styling
	var minimap_panel := PanelContainer.new()
	minimap_panel.anchor_left = 1.0
	minimap_panel.anchor_right = 1.0
	minimap_panel.anchor_top = 0.0
	minimap_panel.anchor_bottom = 0.0
	minimap_panel.offset_left = -214
	minimap_panel.offset_top = 6
	minimap_panel.offset_right = -6
	minimap_panel.offset_bottom = 214
	minimap_panel.add_theme_stylebox_override("panel", MilitaryTheme.create_panel_stylebox())
	minimap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.add_child(minimap_panel)
	base.move_child(minimap_panel, base.get_child_count() - 2)  # Behind minimap

	# Targeting overlay (3D, not in canvas layer)
	_targeting_overlay = TargetingOverlayScript.new()
	add_child(_targeting_overlay)


func _connect_signals() -> void:
	# Connect to selection changes
	if BattleSignals:
		BattleSignals.selection_changed.connect(_on_selection_changed)

	# Connect to command panel
	if _command_panel.has_signal("command_pressed"):
		_command_panel.command_pressed.connect(_on_command_pressed)

	# Connect to attack-move mode from MoveOrderHandler
	var move_handler: Node = get_node_or_null("/root/MoveOrderHandler")
	if move_handler and move_handler.has_signal("attack_move_mode_changed"):
		move_handler.attack_move_mode_changed.connect(_on_attack_move_mode_changed)


func _on_selection_changed(_selected: Array = []) -> void:
	# Update targeting overlay with current selection
	var sel_mgr: Node = _selection_manager
	if sel_mgr and sel_mgr.has_method("get_selected_units"):
		var units: Array[Node3D] = sel_mgr.get_selected_units()
		_targeting_overlay.set_selected_units(units)


func _on_attack_move_mode_changed(enabled: bool) -> void:
	if enabled:
		set_cursor_mode(CursorModeScript.Mode.ATTACK_MOVE)
	else:
		if _cursor_mode == CursorModeScript.Mode.ATTACK_MOVE:
			set_cursor_mode(CursorModeScript.Mode.NORMAL)


func _on_command_pressed(command_name: String) -> void:
	match command_name:
		"move":
			set_cursor_mode(CursorModeScript.Mode.MOVE_PREVIEW)
		"attack_move":
			set_cursor_mode(CursorModeScript.Mode.ATTACK_MOVE)
		"stop":
			_issue_stop_orders()
			set_cursor_mode(CursorModeScript.Mode.NORMAL)
		"hold":
			_issue_hold_orders()
			set_cursor_mode(CursorModeScript.Mode.NORMAL)
		"fire_mission":
			_start_fire_mission_mode()
		"garrison":
			set_cursor_mode(CursorModeScript.Mode.GARRISON)
		"unload":
			_start_unload_mode()
		"bomb":
			set_cursor_mode(CursorModeScript.Mode.BOMB_RUN)
		"napalm":
			set_cursor_mode(CursorModeScript.Mode.NAPALM_RUN)
		"rockets":
			set_cursor_mode(CursorModeScript.Mode.ROCKET_RUN)
		"cannon":
			set_cursor_mode(CursorModeScript.Mode.STRAFE_RUN)
		"build":
			set_cursor_mode(CursorModeScript.Mode.BUILDING_PLACE)
		"clear":
			set_cursor_mode(CursorModeScript.Mode.PAINT_CLEAR)
		"dozer_clear":
			set_cursor_mode(CursorModeScript.Mode.PAINT_DOZER_LINE)
		"flatten":
			set_cursor_mode(CursorModeScript.Mode.PAINT_FLATTEN)
		_:
			# Generic command - emit and let other systems handle
			print("[BattleHUD] Unhandled command: %s" % command_name)


func _commit_current_mode() -> void:
	var target_pos: Vector3 = _targeting_overlay.get_cursor_position()

	match _cursor_mode:
		CursorModeScript.Mode.FIRE_MISSION:
			if _targeting_overlay.is_cursor_valid():
				_issue_fire_mission(target_pos)
		CursorModeScript.Mode.UNLOAD:
			_issue_unload(target_pos)
		CursorModeScript.Mode.BOMB_RUN, CursorModeScript.Mode.NAPALM_RUN, \
		CursorModeScript.Mode.ROCKET_RUN, CursorModeScript.Mode.STRAFE_RUN:
			_issue_attack_run(target_pos)
		CursorModeScript.Mode.BUILDING_PLACE:
			if _targeting_overlay.is_cursor_valid():
				_issue_build(target_pos)
		CursorModeScript.Mode.PAINT_CLEAR:
			if _targeting_overlay.is_cursor_valid():
				_issue_clear(target_pos)
		CursorModeScript.Mode.PAINT_DOZER_LINE:
			if _targeting_overlay.is_cursor_valid():
				_issue_dozer_line(target_pos)
		CursorModeScript.Mode.PAINT_FLATTEN:
			if _targeting_overlay.is_cursor_valid():
				_issue_flatten(target_pos)

	set_cursor_mode(CursorModeScript.Mode.NORMAL)


# =============================================================================
# MODE-SPECIFIC SETUP
# =============================================================================

func _start_fire_mission_mode() -> void:
	var context: Dictionary = {
		"min_range": 100.0,
		"max_range": 11000.0,
		"impact_radius": 30.0,
	}

	# Get actual range from selected artillery
	var sel_mgr: Node = _selection_manager
	if sel_mgr and sel_mgr.has_method("get_selected_units"):
		var units: Array[Node3D] = sel_mgr.get_selected_units()
		for unit in units:
			if unit.is_in_group("artillery"):
				if unit.has_method("get"):
					var min_r: Variant = unit.get("min_indirect_range")
					if min_r != null:
						context["min_range"] = float(min_r)
				break

	set_cursor_mode(CursorModeScript.Mode.FIRE_MISSION, context)


func _start_unload_mode() -> void:
	var context: Dictionary = {"unit_count": 4}

	# Get cargo count from selected transport
	var sel_mgr: Node = _selection_manager
	if sel_mgr and sel_mgr.has_method("get_selected_units"):
		var units: Array[Node3D] = sel_mgr.get_selected_units()
		for unit in units:
			if unit.has_method("get"):
				var cargo: Variant = unit.get("cargo")
				if cargo != null and cargo is Array:
					context["unit_count"] = (cargo as Array).size()
					break

	set_cursor_mode(CursorModeScript.Mode.UNLOAD, context)


# =============================================================================
# ORDER ISSUANCE
# =============================================================================

func _issue_stop_orders() -> void:
	var sel_mgr: Node = _selection_manager
	if not sel_mgr:
		return

	var units: Array[Node3D] = sel_mgr.get_selected_units()
	for unit in units:
		if unit.has_method("stop_attack"):
			unit.stop_attack()
		if unit.has_method("get") and unit.get("has_move_order") != null:
			unit.has_move_order = false
	print("[BattleHUD] Stop orders issued to %d units" % units.size())


func _issue_hold_orders() -> void:
	var sel_mgr: Node = _selection_manager
	if not sel_mgr:
		return

	var units: Array[Node3D] = sel_mgr.get_selected_units()
	for unit in units:
		if unit.has_method("stop_attack"):
			unit.stop_attack()
		if unit.has_method("get") and unit.get("has_move_order") != null:
			unit.has_move_order = false
		# TODO: Set hold position flag
	print("[BattleHUD] Hold orders issued to %d units" % units.size())


func _issue_fire_mission(target: Vector3) -> void:
	var sel_mgr: Node = _selection_manager
	if not sel_mgr:
		return

	var units: Array[Node3D] = sel_mgr.get_selected_units()
	for unit in units:
		if unit.is_in_group("artillery") and unit.has_method("fire_mission"):
			unit.fire_mission(target)
	print("[BattleHUD] Fire mission issued at %s" % target)


func _issue_unload(target: Vector3) -> void:
	var sel_mgr: Node = _selection_manager
	if not sel_mgr:
		return

	var units: Array[Node3D] = sel_mgr.get_selected_units()
	for unit in units:
		if unit.has_method("unload_troops"):
			unit.unload_troops(target)
		elif unit.has_method("unload_all"):
			unit.unload_all()
	print("[BattleHUD] Unload issued at %s" % target)


func _issue_attack_run(target: Vector3) -> void:
	var sel_mgr: Node = _selection_manager
	if not sel_mgr:
		return

	var ordnance: int = 0  # Default to bombs
	match _cursor_mode:
		CursorModeScript.Mode.NAPALM_RUN:
			ordnance = 1
		CursorModeScript.Mode.ROCKET_RUN:
			ordnance = 2
		CursorModeScript.Mode.STRAFE_RUN:
			ordnance = 3

	var units: Array[Node3D] = sel_mgr.get_selected_units()
	for unit in units:
		if unit.is_in_group("airplanes") and unit.has_method("start_attack_run"):
			unit.start_attack_run(target, ordnance)
	print("[BattleHUD] Attack run issued at %s with ordnance %d" % [target, ordnance])


func _issue_build(target: Vector3) -> void:
	## Issue build order at target location
	## Creates job chain: CLEAR_TERRAIN -> FLATTEN_AREA -> BUILD_STRUCTURE
	## Vegetation is cleared when CLEAR job completes (not immediately)

	# Get ConstructionManager for building placement
	var construction_mgr: Node = get_node_or_null("/root/ConstructionManager")
	if not construction_mgr:
		print("[BattleHUD] ConstructionManager not found")
		return

	# Check if we have a building type selected in mode context
	var building_type: int = _mode_context.get("building_type", -1)
	if building_type >= 0:
		# Create a build job with prerequisites (clear -> flatten -> build)
		var job: Node = construction_mgr.enqueue_build_with_prerequisites(
			target,
			building_type,
			0.0,  # rotation
			Vector2(4.0, 4.0)  # default footprint
		)
		if job:
			print("[BattleHUD] Build job created at %s for building type %d" % [target, building_type])
		else:
			print("[BattleHUD] Failed to create build job at %s" % target)
	else:
		# No building type selected - just prepare the site
		print("[BattleHUD] Build site prepared at %s (no building type selected)" % target)


func _issue_clear(target: Vector3) -> void:
	## Issue clearing orders to selected engineer units
	## Engineers use det-cord for 3x3 square clearing (9x9m)
	var sel_mgr: Node = _selection_manager
	if not sel_mgr:
		return

	# Create a CLEAR_TERRAIN job via JobManager
	var job_mgr: Node = get_node_or_null("/root/JobManager")
	if job_mgr and job_mgr.has_method("create_area_job"):
		# 3x3 grid = 9x9 meters centered on target
		var clear_size: float = 9.0
		var half_size: float = clear_size * 0.5
		var min_corner := Vector3(target.x - half_size, 0, target.z - half_size)
		var max_corner := Vector3(target.x + half_size, 0, target.z + half_size)

		var job: Node = job_mgr.create_area_job(0, min_corner, max_corner)  # 0 = CLEAR_TERRAIN
		if job:
			print("[BattleHUD] Clear job created at %s (9x9m)" % target)

			# Assign selected engineers to work on the job
			var units: Array[Node3D] = sel_mgr.get_selected_units()
			var builder_ai: Node = get_node_or_null("/root/BuilderAI")
			if builder_ai and builder_ai.has_method("assign_to_job"):
				for unit in units:
					# Check if unit is an engineer (can_build, not vehicle)
					if unit.has_method("get"):
						var data: Resource = unit.get("data")
						if data and "can_build" in data and data.can_build:
							if not ("is_vehicle" in data and data.is_vehicle):
								builder_ai.assign_to_job(unit, job)
			return

	# Fallback: direct unit command
	var units: Array[Node3D] = sel_mgr.get_selected_units()
	var cleared: int = 0

	for unit in units:
		if unit.has_method("can_clear") and unit.can_clear():
			if unit.has_method("start_clearing"):
				unit.start_clearing(target, 9.0)  # 9m clearing radius for 3x3
				cleared += 1

	if cleared > 0:
		print("[BattleHUD] Clear order issued to %d engineers at %s" % [cleared, target])
	else:
		print("[BattleHUD] No engineers available to clear")


func _issue_dozer_line(target: Vector3) -> void:
	## Issue bulldozer line clearing order
	## Bulldozers clear a 3-wide (6m) line from current position to target
	var sel_mgr: Node = _selection_manager
	if not sel_mgr:
		return

	var units: Array[Node3D] = sel_mgr.get_selected_units()

	# Find the first bulldozer
	var bulldozer: Node3D = null
	for unit in units:
		if unit.has_method("get"):
			var data: Resource = unit.get("data")
			if data and "is_vehicle" in data and data.is_vehicle:
				if "can_build" in data and data.can_build:
					bulldozer = unit
					break

	if not bulldozer:
		print("[BattleHUD] No bulldozer selected for line clearing")
		return

	var start_pos: Vector3 = bulldozer.global_position

	# Create a CLEAR_TERRAIN job along the line via JobManager
	var job_mgr: Node = get_node_or_null("/root/JobManager")
	if job_mgr and job_mgr.has_method("create_area_job"):
		# Line is 6m wide (3 units) and runs from bulldozer to target
		var line_dir: Vector3 = (target - start_pos)
		line_dir.y = 0
		var line_length: float = line_dir.length()
		line_dir = line_dir.normalized()

		# Calculate bounding box that contains the 6m-wide line
		var perp: Vector3 = Vector3(-line_dir.z, 0, line_dir.x) * 3.0  # 3m on each side
		var corners: Array[Vector3] = [
			start_pos + perp,
			start_pos - perp,
			target + perp,
			target - perp,
		]

		var min_x: float = corners[0].x
		var max_x: float = corners[0].x
		var min_z: float = corners[0].z
		var max_z: float = corners[0].z

		for corner in corners:
			min_x = minf(min_x, corner.x)
			max_x = maxf(max_x, corner.x)
			min_z = minf(min_z, corner.z)
			max_z = maxf(max_z, corner.z)

		var min_corner := Vector3(min_x, 0, min_z)
		var max_corner := Vector3(max_x, 0, max_z)

		var job: Node = job_mgr.create_area_job(0, min_corner, max_corner)  # 0 = CLEAR_TERRAIN
		if job:
			# Set metadata indicating this is a bulldozer line clear
			if job.has_method("set"):
				job.metadata["bulldozer_line"] = true
				job.metadata["line_start"] = start_pos
				job.metadata["line_end"] = target
			print("[BattleHUD] Bulldozer line clear job created: %s -> %s (%.0fm)" % [start_pos, target, line_length])

			# Assign bulldozer to work on the job via BuilderAI
			var builder_ai: Node = get_node_or_null("/root/BuilderAI")
			if builder_ai and builder_ai.has_method("assign_to_job"):
				builder_ai.assign_to_job(bulldozer, job)
			elif bulldozer.has_method("move_to"):
				# Fallback: just move bulldozer to start
				bulldozer.move_to(start_pos)
			return

	print("[BattleHUD] Could not create bulldozer line clear job")


func _issue_flatten(target: Vector3) -> void:
	## Issue terrain flattening order to selected bulldozers
	var sel_mgr: Node = _selection_manager
	if not sel_mgr:
		return

	# Create a FLATTEN_AREA job via JobManager
	var job_mgr: Node = get_node_or_null("/root/JobManager")
	if job_mgr and job_mgr.has_method("create_area_job"):
		# Flatten a 15x15m area centered on target
		var flatten_size: float = 15.0
		var half_size: float = flatten_size * 0.5
		var min_corner := Vector3(target.x - half_size, 0, target.z - half_size)
		var max_corner := Vector3(target.x + half_size, 0, target.z + half_size)

		var job: Node = job_mgr.create_area_job(1, min_corner, max_corner)  # 1 = FLATTEN_AREA
		if job:
			print("[BattleHUD] Flatten job created at %s (15x15m)" % target)

			# Assign selected bulldozers to work on the job
			var units: Array[Node3D] = sel_mgr.get_selected_units()
			var builder_ai: Node = get_node_or_null("/root/BuilderAI")
			if builder_ai and builder_ai.has_method("assign_to_job"):
				for unit in units:
					# Check if unit is a bulldozer
					if unit.has_method("get"):
						var data: Resource = unit.get("data")
						if data and "is_vehicle" in data and data.is_vehicle:
							if "can_build" in data and data.can_build:
								builder_ai.assign_to_job(unit, job)
								break  # One bulldozer is enough
			return

	print("[BattleHUD] Could not create flatten job")


# =============================================================================
# PUBLIC API
# =============================================================================

## Set the current cursor mode
func set_cursor_mode(mode: int, context: Dictionary = {}) -> void:
	_cursor_mode = mode
	_mode_context = context
	_targeting_overlay.set_mode(mode, context)

	# Update command panel highlighting
	if _command_panel.has_method("set_command_highlighted"):
		_command_panel.set_command_highlighted("attack_move", mode == CursorModeScript.Mode.ATTACK_MOVE)
		_command_panel.set_command_highlighted("fire_mission", mode == CursorModeScript.Mode.FIRE_MISSION)

	print("[BattleHUD] Cursor mode: %s" % CursorModeScript.get_mode_name(mode))


## Get the current cursor mode
func get_cursor_mode() -> int:
	return _cursor_mode


## Register the player's faction for UI coloring
func register_player_faction(faction: int) -> void:
	_player_faction = faction


## Show an objective notification (temporary)
func show_objective(text: String, duration: float = 5.0) -> void:
	_objective_label.text = text
	_objective_label.visible = true

	# Cancel previous timer to prevent memory leak from stacked lambdas
	if _objective_timer != null and _objective_timer.time_left > 0:
		# Disconnect any existing connections (timer cannot be cancelled, but we track state)
		pass

	# Create new timer
	_objective_timer = get_tree().create_timer(duration)

	# Capture current timer reference to check validity on callback
	var timer_ref: SceneTreeTimer = _objective_timer
	timer_ref.timeout.connect(func():
		# Only hide if this is still the active timer
		if _objective_timer == timer_ref:
			_objective_label.visible = false
			_objective_timer = null
	)


## Get the targeting overlay (for external queries)
func get_targeting_overlay() -> Node3D:
	return _targeting_overlay


## Get the selection card
func get_selection_card() -> Control:
	return _selection_card


## Get the command panel
func get_command_panel() -> Control:
	return _command_panel


## Get the tactical minimap
func get_tactical_minimap() -> SubViewportContainer:
	return _tactical_minimap


## Configure the minimap with map bounds
func configure_minimap(map_size: Vector2, fog_of_war: Node = null, main_camera: Camera3D = null) -> void:
	if _tactical_minimap:
		_tactical_minimap.set_map_size(map_size)
		if fog_of_war:
			_tactical_minimap.set_fog_of_war(fog_of_war)
		if main_camera:
			_tactical_minimap.set_main_camera(main_camera)
