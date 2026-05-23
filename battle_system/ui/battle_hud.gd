extends Node
## Main HUD controller that owns and coordinates all HUD elements.
## Manages cursor mode, targeting overlay, minimap, and HUD panels.

const MilitaryTheme = preload("res://battle_system/ui/military_theme.gd")
const CursorModeScript = preload("res://battle_system/ui/cursor_mode.gd")
const SelectionCardScript = preload("res://battle_system/ui/selection_card.gd")
const CommandPanelScript = preload("res://battle_system/ui/command_panel.gd")
const TargetingOverlayScript = preload("res://battle_system/ui/targeting_overlay.gd")
const TacticalMinimapScript = preload("res://battle_system/ui/tactical_minimap.gd")
const BuildMenuPopupScript = preload("res://battle_system/ui/build_menu_popup.gd")
const PlacementControllerScript = preload("res://firebase_system/placement_controller.gd")

# =============================================================================
# STATE
# =============================================================================

var _hud_layer: CanvasLayer
var _placement_controller: Node3D  # PlacementController for building ghost preview
var _selection_card: Control
var _command_panel: Control
var _targeting_overlay: Node3D
var _objective_label: Label
var _tactical_minimap: SubViewportContainer
var _job_queue_label: Label
var _supply_label: Label
var _build_menu_popup: Control

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

## Timer for job queue updates
var _job_queue_update_timer: float = 0.0
const JOB_QUEUE_UPDATE_INTERVAL: float = 1.0  # Update every second

func _ready() -> void:
	# Cache autoload reference
	_selection_manager = get_node_or_null("/root/SelectionManager")

	_build_hud()
	_connect_signals()

	# Initial supply display update
	call_deferred("_update_supply_display")

	print("[BattleHUD] Initialized")


func _process(delta: float) -> void:
	# Update cursor position continuously when placement is active
	# This ensures smooth ghost tracking even between input events
	if _placement_controller and _placement_controller.is_active() and _targeting_overlay:
		var world_pos: Vector3 = _targeting_overlay.get_cursor_position(true)
		_placement_controller.update_cursor_position(world_pos)

	# Periodically update job queue and supply display
	_job_queue_update_timer -= delta
	if _job_queue_update_timer <= 0.0:
		_job_queue_update_timer = JOB_QUEUE_UPDATE_INTERVAL
		_update_job_queue_display()
		_update_supply_display()


func _update_job_queue_display() -> void:
	## Update the job queue label with current job counts
	if not _job_queue_label:
		return

	var job_mgr: Node = get_node_or_null("/root/JobSystem")
	if not job_mgr:
		_job_queue_label.text = ""
		return

	var pending: int = 0
	var in_progress: int = 0

	if job_mgr.has_method("get_pending_job_count"):
		pending = job_mgr.get_pending_job_count()
	if job_mgr.has_method("get_in_progress_job_count"):
		in_progress = job_mgr.get_in_progress_job_count()

	if pending > 0 or in_progress > 0:
		_job_queue_label.text = "Jobs: %d pending, %d active" % [pending, in_progress]
	else:
		_job_queue_label.text = ""


func _update_supply_display() -> void:
	## Update the supply label with current supply levels
	if not _supply_label:
		return

	# Get supply from SupplyManager (global) and/or nearest firebase
	var supply_mgr: Node = get_node_or_null("/root/SupplyManager")
	var total_supply: float = 0.0
	var max_supply: float = 0.0

	if supply_mgr:
		total_supply = supply_mgr.get_global_supply() if supply_mgr.has_method("get_global_supply") else 0.0
		max_supply = supply_mgr.max_global_supply if "max_global_supply" in supply_mgr else 5000.0
	else:
		# Fallback: sum up firebase supply levels
		var firebases: Array[Node] = get_tree().get_nodes_in_group("firebases")
		for fb in firebases:
			if fb.has_method("get") and fb.get("supply_level") != null:
				total_supply += fb.supply_level
			if fb.has_method("get") and fb.get("max_supply") != null:
				max_supply += fb.max_supply

	if max_supply > 0:
		var supply_percent: float = (total_supply / max_supply) * 100.0
		_supply_label.text = "Supply: %.0f / %.0f (%.0f%%)" % [total_supply, max_supply, supply_percent]

		# Color based on supply level
		if supply_percent > 50.0:
			_supply_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_PRIMARY)
		elif supply_percent > 20.0:
			_supply_label.add_theme_color_override("font_color", MilitaryTheme.COL_AMMO_LOW)
		else:
			_supply_label.add_theme_color_override("font_color", MilitaryTheme.COL_HEALTH_LOW)
	else:
		_supply_label.text = ""


func _on_supply_consumed(_firebase: Node3D, _amount: float, _reason: String) -> void:
	## Handle supply consumed event - update display
	_update_supply_display()


func _on_supply_delivered(_destination: Node3D, _amount: float) -> void:
	## Handle supply delivered event - update display
	_update_supply_display()


## Track if we're currently in a paint drag operation
var _paint_dragging: bool = false

func _input(event: InputEvent) -> void:
	# Route input to PlacementController when active (for building ghost preview)
	if _placement_controller and _placement_controller.is_active():
		# Don't consume UI clicks - check if mouse is over any Control
		if event is InputEventMouseButton and event.pressed:
			var mouse_pos: Vector2 = get_viewport().get_mouse_position()
			# Check if any UI element would handle this click
			var hud_base: Control = _hud_layer.get_child(0) if _hud_layer.get_child_count() > 0 else null
			if hud_base and _is_mouse_over_ui(hud_base, mouse_pos):
				return  # Let UI handle the click

		# Force cursor position update - TargetingOverlay only auto-updates when in a special mode
		var world_pos: Vector3 = _targeting_overlay.get_cursor_position(true) if _targeting_overlay else Vector3.ZERO
		_placement_controller.update_cursor_position(world_pos)
		if _placement_controller.handle_input(event, world_pos):
			get_viewport().set_input_as_handled()
			return

	# Handle mode cancellation with Escape
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if CursorModeScript.canceled_by_escape(_cursor_mode):
				# Cancel any active paint drag
				if _paint_dragging:
					_targeting_overlay.end_paint_drag()
					_paint_dragging = false
				set_cursor_mode(CursorModeScript.Mode.NORMAL)
				get_viewport().set_input_as_handled()
				return

	# Handle paint mode input (drag to select area)
	if CursorModeScript.is_paint_mode(_cursor_mode):
		if event is InputEventMouseButton:
			var mouse_event := event as InputEventMouseButton
			if mouse_event.button_index == MOUSE_BUTTON_LEFT:
				if mouse_event.pressed:
					# Start drag - force update for accurate click position
					var cursor_pos: Vector3 = _targeting_overlay.get_cursor_position(true)
					_targeting_overlay.start_paint_drag(cursor_pos)
					_paint_dragging = true
					get_viewport().set_input_as_handled()
					return
				else:
					# End drag and commit
					if _paint_dragging:
						var bounds: Rect2 = _targeting_overlay.get_paint_bounds()
						if bounds.size.x > 1.0 and bounds.size.y > 1.0:
							_commit_paint_area(bounds)
						_targeting_overlay.end_paint_drag()
						_paint_dragging = false
						set_cursor_mode(CursorModeScript.Mode.NORMAL)
						get_viewport().set_input_as_handled()
						return

			# Right-click cancels paint mode
			if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
				if _paint_dragging:
					_targeting_overlay.end_paint_drag()
					_paint_dragging = false
				set_cursor_mode(CursorModeScript.Mode.NORMAL)
				get_viewport().set_input_as_handled()
				return
		# Consume all input while in paint mode to prevent propagation
		get_viewport().set_input_as_handled()
		return

	# Handle right-click commit in special modes
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if CursorModeScript.right_click_commits(_cursor_mode):
				_commit_current_mode()
				get_viewport().set_input_as_handled()
				return

		# Left-click: either commit (for building placement) or cancel special modes
		if event.button_index == MOUSE_BUTTON_LEFT:
			if CursorModeScript.left_click_commits(_cursor_mode):
				_commit_current_mode()
				get_viewport().set_input_as_handled()
				return
			elif _cursor_mode != CursorModeScript.Mode.NORMAL:
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
	# Rect must fit all 3 button rows (~185px tall, ~285px wide) or the bottom
	# row overflows below the screen edge.
	_command_panel.offset_left = -300
	_command_panel.offset_top = -200
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

	# Job queue label (below minimap, top-right)
	_job_queue_label = Label.new()
	_job_queue_label.anchor_left = 1.0
	_job_queue_label.anchor_right = 1.0
	_job_queue_label.anchor_top = 0.0
	_job_queue_label.anchor_bottom = 0.0
	_job_queue_label.offset_left = -210
	_job_queue_label.offset_top = 215
	_job_queue_label.offset_right = -10
	_job_queue_label.offset_bottom = 235
	_job_queue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_job_queue_label.add_theme_font_size_override("font_size", 12)
	_job_queue_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_PRIMARY)
	_job_queue_label.text = ""
	base.add_child(_job_queue_label)

	# Supply indicator (below job queue, top-right)
	_supply_label = Label.new()
	_supply_label.anchor_left = 1.0
	_supply_label.anchor_right = 1.0
	_supply_label.anchor_top = 0.0
	_supply_label.anchor_bottom = 0.0
	_supply_label.offset_left = -210
	_supply_label.offset_top = 237
	_supply_label.offset_right = -10
	_supply_label.offset_bottom = 257
	_supply_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_supply_label.add_theme_font_size_override("font_size", 12)
	_supply_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_PRIMARY)
	_supply_label.text = ""
	base.add_child(_supply_label)

	# Targeting overlay (3D, not in canvas layer)
	_targeting_overlay = TargetingOverlayScript.new()
	add_child(_targeting_overlay)

	# Placement controller (3D ghost preview for building placement)
	_placement_controller = PlacementControllerScript.new()
	_placement_controller.name = "PlacementController"
	add_child(_placement_controller)

	# Build menu popup (initially hidden)
	_build_menu_popup = BuildMenuPopupScript.new()
	_build_menu_popup.visible = false
	base.add_child(_build_menu_popup)


func _connect_signals() -> void:
	# Connect to selection changes
	if BattleSignals:
		BattleSignals.selection_changed.connect(_on_selection_changed)
		BattleSignals.supply_consumed.connect(_on_supply_consumed)
		BattleSignals.supply_delivered.connect(_on_supply_delivered)

	# Connect to command panel
	if _command_panel.has_signal("command_pressed"):
		_command_panel.command_pressed.connect(_on_command_pressed)

	# Connect to build menu popup
	if _build_menu_popup.has_signal("building_selected"):
		_build_menu_popup.building_selected.connect(_on_building_selected)

	# Connect to attack-move mode from MoveOrderHandler
	var move_handler: Node = get_node_or_null("/root/MoveOrderHandler")
	if move_handler and move_handler.has_signal("attack_move_mode_changed"):
		move_handler.attack_move_mode_changed.connect(_on_attack_move_mode_changed)

	# Connect to PlacementController for building ghost preview
	if _placement_controller:
		_placement_controller.placement_committed.connect(_on_placement_committed)
		_placement_controller.placement_cancelled.connect(_on_placement_cancelled)
		_placement_controller.validation_changed.connect(_on_placement_validation_changed)


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


func _on_placement_committed(building_type: int, position: Vector3) -> void:
	## Handle successful building placement from PlacementController
	print("[BattleHUD] Placement committed: type=%d at %v" % [building_type, position])
	# Job is already created by PlacementController, just clear context
	_mode_context.clear()
	# Reset cursor mode to normal after placement
	set_cursor_mode(CursorModeScript.Mode.NORMAL)


func _on_placement_cancelled() -> void:
	## Handle placement cancellation
	print("[BattleHUD] Placement cancelled")
	_mode_context.clear()
	# Reset cursor mode to normal after cancellation
	set_cursor_mode(CursorModeScript.Mode.NORMAL)


func _on_placement_validation_changed(valid: bool, message: String) -> void:
	## Handle validation status change (for UI feedback if needed)
	if not valid and message != "":
		# Could show tooltip or status message here
		pass


func _on_command_pressed(command_name: String) -> void:
	print("[BattleHUD] >>> RECEIVED COMMAND: %s <<<" % command_name)
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
			_show_build_menu()
		"clear":
			set_cursor_mode(CursorModeScript.Mode.PAINT_CLEAR)
		"dozer_clear":
			set_cursor_mode(CursorModeScript.Mode.PAINT_DOZER_LINE)
		"flatten":
			set_cursor_mode(CursorModeScript.Mode.PAINT_FLATTEN)
		"patrol":
			set_cursor_mode(CursorModeScript.Mode.PATROL)
		"repair":
			set_cursor_mode(CursorModeScript.Mode.REPAIR)
		_:
			# Generic command - emit and let other systems handle
			print("[BattleHUD] Unhandled command: %s" % command_name)


func _commit_current_mode() -> void:
	# Force update cursor position for accurate commit location
	var target_pos: Vector3 = _targeting_overlay.get_cursor_position(true)

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
		CursorModeScript.Mode.PATROL:
			_issue_patrol_orders(target_pos)
		CursorModeScript.Mode.REPAIR:
			_issue_repair_orders(target_pos)

	set_cursor_mode(CursorModeScript.Mode.NORMAL)


# =============================================================================
# MODE-SPECIFIC SETUP
# =============================================================================

## Public: open the canonical build menu (e.g. from a test scene's hotkey).
func open_build_menu() -> void:
	_show_build_menu()


## Public: is a building placement currently active (ghost following the cursor)?
func is_placing() -> bool:
	return _placement_controller != null and _placement_controller.is_active()


func _show_build_menu() -> void:
	## Show the build menu popup for building selection
	if not _build_menu_popup:
		print("[BattleHUD] Build menu popup not available")
		return

	# Get current supply for affordability check
	var supply: int = 1000  # Default
	var supply_mgr: Node = get_node_or_null("/root/SupplyManager")
	if supply_mgr and supply_mgr.has_method("get_global_supply"):
		supply = int(supply_mgr.get_global_supply())
	else:
		# Fallback: check nearest firebase
		var firebases: Array[Node] = get_tree().get_nodes_in_group("firebases")
		if not firebases.is_empty() and firebases[0].has_method("get"):
			var fb_supply: Variant = firebases[0].get("supply_level")
			if fb_supply != null:
				supply = int(fb_supply)

	_build_menu_popup.open_menu(supply)
	print("[BattleHUD] Build menu opened with %d supply" % supply)


func _on_building_selected(building_key: String, placement_mode: int) -> void:
	## Handle building selection from build menu
	## Uses PlacementController for ghost preview with real-time red/green validation
	## Falls back to cursor mode system for non-building items (clear, flatten, etc.)
	print("[BattleHUD] Building selected: %s (mode: %d)" % [building_key, placement_mode])

	# Get building data to set up context
	var entry = _build_menu_popup.get_building(building_key)
	if not entry:
		print("[BattleHUD] Building entry not found for: %s" % building_key)
		return

	# Check if this is a real building (type >= 0) or a special command (type < 0)
	# Special commands like clear, flatten, trenches have building_type = -1
	if entry.building_type < 0:
		# Fall back to cursor mode system for special commands
		print("[BattleHUD] Special command (type=%d), using cursor mode" % entry.building_type)
		var context: Dictionary = {
			"building_key": building_key,
			"building_type": entry.building_type,
			"supply_cost": entry.supply_cost,
			"placement_mode": placement_mode,
			"spacing": entry.spacing,
		}
		# Map building_key to appropriate cursor mode
		match building_key:
			"clear", "clear_zone":
				set_cursor_mode(CursorModeScript.Mode.PAINT_CLEAR, context)
			"flatten", "flatten_zone":
				set_cursor_mode(CursorModeScript.Mode.PAINT_FLATTEN, context)
			"road", "road_segment":
				set_cursor_mode(CursorModeScript.Mode.PAINT_ROAD, context)
			"trench", "trench_line":
				set_cursor_mode(CursorModeScript.Mode.PAINT_TRENCH, context)
			"wire", "wire_obstacle", "concertina":
				set_cursor_mode(CursorModeScript.Mode.PAINT_WIRE, context)
			_:
				# Default to paint build for unknown special types
				set_cursor_mode(CursorModeScript.Mode.PAINT_BUILD, context)
		return

	# Use PlacementController for building preview (CoH-style ghost)
	if _placement_controller:
		# Get fresh cursor position to prevent ghost appearing at origin
		var fresh_cursor_pos: Vector3 = _targeting_overlay.get_cursor_position(true) if _targeting_overlay else Vector3.INF
		_placement_controller.start_placement(entry.building_type, fresh_cursor_pos)
		# Store context for use when placement completes
		_mode_context = {
			"building_key": building_key,
			"building_type": entry.building_type,
			"supply_cost": entry.supply_cost,
			"placement_mode": placement_mode,
			"spacing": entry.spacing,
		}
		return

	# Fallback: use old cursor mode system if PlacementController not available
	var context: Dictionary = {
		"building_key": building_key,
		"building_type": entry.building_type,
		"supply_cost": entry.supply_cost,
		"placement_mode": placement_mode,
		"spacing": entry.spacing,
	}

	# Set cursor mode based on placement mode
	match placement_mode:
		BuildMenuPopupScript.PlacementMode.SINGLE:
			set_cursor_mode(CursorModeScript.Mode.BUILDING_PLACE, context)
		BuildMenuPopupScript.PlacementMode.PAINTABLE:
			set_cursor_mode(CursorModeScript.Mode.PAINT_BUILD, context)
		BuildMenuPopupScript.PlacementMode.PAINTABLE_SPACED:
			set_cursor_mode(CursorModeScript.Mode.PAINT_BUILD, context)
		_:
			set_cursor_mode(CursorModeScript.Mode.BUILDING_PLACE, context)


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


func _issue_patrol_orders(target: Vector3) -> void:
	## Issue patrol orders - set waypoint for patrol route
	var sel_mgr: Node = _selection_manager
	if not sel_mgr:
		return

	var units: Array[Node3D] = sel_mgr.get_selected_units()
	var patrol_count: int = 0

	for unit in units:
		# Get current patrol waypoints from mode context or initialize new array
		var waypoints: Array[Vector3] = _mode_context.get("patrol_waypoints", [])

		# If this is first waypoint, include unit's current position
		if waypoints.is_empty():
			waypoints.append(unit.global_position)

		waypoints.append(target)

		# Check if unit has patrol route capability
		if unit.has_method("set_patrol_route"):
			unit.set_patrol_route(waypoints)
			patrol_count += 1
		elif unit.has_method("get") and unit.get("patrol_waypoints") != null:
			unit.patrol_waypoints = waypoints
			if unit.has_method("get") and unit.get("standing_order") != null:
				unit.standing_order = 1  # StandingOrder.PATROL
			patrol_count += 1
		elif unit.has_method("move_to"):
			# Fallback: just move to the target
			unit.move_to(target)
			patrol_count += 1

	if patrol_count > 0:
		print("[BattleHUD] Patrol route set for %d units to %s" % [patrol_count, target])
	else:
		print("[BattleHUD] No units can patrol")


func _issue_repair_orders(target: Vector3) -> void:
	## Issue repair orders - find nearest damaged structure and repair it
	var sel_mgr: Node = _selection_manager
	if not sel_mgr:
		return

	# Find damaged structures near target
	var structures: Array[Node] = get_tree().get_nodes_in_group("structures")
	var target_structure: Node3D = null
	var best_dist: float = 20.0  # Search radius

	for structure in structures:
		if not structure is Node3D:
			continue
		var dist: float = target.distance_to(structure.global_position)
		if dist > best_dist:
			continue

		# Check if structure is damaged (has health < max_health)
		if structure.has_method("get"):
			var current_health: Variant = structure.get("current_health")
			var max_health: Variant = structure.get("max_health")
			if current_health != null and max_health != null:
				if float(current_health) < float(max_health):
					best_dist = dist
					target_structure = structure as Node3D

	if not target_structure:
		print("[BattleHUD] No damaged structure found near %s" % target)
		return

	# Assign engineers to repair
	var units: Array[Node3D] = sel_mgr.get_selected_units()
	var repair_count: int = 0

	for unit in units:
		# Check if unit can repair (engineers)
		if unit.has_method("get"):
			var data: Resource = unit.get("data")
			if data and "can_build" in data and data.can_build:
				if not ("is_vehicle" in data and data.is_vehicle):
					# Issue repair command
					if unit.has_method("start_repair"):
						unit.start_repair(target_structure)
						repair_count += 1
					elif unit.has_method("move_to"):
						# Fallback: move to structure
						unit.move_to(target_structure.global_position)
						repair_count += 1

	if repair_count > 0:
		print("[BattleHUD] Repair orders issued to %d engineers for %s" % [repair_count, target_structure.name])
	else:
		print("[BattleHUD] No engineers selected for repair")


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
		var job: UnifiedJob = construction_mgr.enqueue_build_with_prerequisites(
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
	var job_mgr: Node = get_node_or_null("/root/JobSystem")
	if job_mgr and job_mgr.has_method("create_area_job"):
		# 3x3 grid = 9x9 meters centered on target
		var clear_size: float = 9.0
		var half_size: float = clear_size * 0.5
		var min_corner := Vector3(target.x - half_size, 0, target.z - half_size)
		var max_corner := Vector3(target.x + half_size, 0, target.z + half_size)

		var job: Node = job_mgr.create_area_job(0, min_corner, max_corner)  # 0 = CLEAR_TERRAIN
		if job:
			print("[BattleHUD] Clear job created at %s (9x9m)" % target)
			# WorkerController handles auto-assignment - workers find jobs bottom-up
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
	var job_mgr: Node = get_node_or_null("/root/JobSystem")
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
			# WorkerController handles auto-assignment - workers find jobs bottom-up
			return

	print("[BattleHUD] Could not create bulldozer line clear job")


func _issue_flatten(target: Vector3) -> void:
	## Issue terrain flattening order to selected bulldozers
	var sel_mgr: Node = _selection_manager
	if not sel_mgr:
		return

	# Create a FLATTEN_AREA job via JobManager
	var job_mgr: Node = get_node_or_null("/root/JobSystem")
	if job_mgr and job_mgr.has_method("create_area_job"):
		# Flatten a 15x15m area centered on target
		var flatten_size: float = 15.0
		var half_size: float = flatten_size * 0.5
		var min_corner := Vector3(target.x - half_size, 0, target.z - half_size)
		var max_corner := Vector3(target.x + half_size, 0, target.z + half_size)

		var job: Node = job_mgr.create_area_job(1, min_corner, max_corner)  # 1 = FLATTEN_AREA
		if job:
			print("[BattleHUD] Flatten job created at %s (15x15m)" % target)
			# WorkerController handles auto-assignment - workers find jobs bottom-up
			return

	print("[BattleHUD] Could not create flatten job")


func _commit_paint_area(bounds: Rect2) -> void:
	## Commit the painted area as a job based on current cursor mode
	var job_mgr: Node = get_node_or_null("/root/JobSystem")
	if not job_mgr:
		print("[BattleHUD] JobManager not found - cannot commit paint area")
		return

	# Convert Rect2 (x, y = world x, z) to Vector3 corners
	var min_corner := Vector3(bounds.position.x, 0, bounds.position.y)
	var max_corner := Vector3(bounds.position.x + bounds.size.x, 0, bounds.position.y + bounds.size.y)

	var job = null  # Can be Node (old API) or RefCounted (new JobSystem)
	match _cursor_mode:
		CursorModeScript.Mode.PAINT_CLEAR:
			if job_mgr.has_method("create_area_job"):
				job = job_mgr.create_area_job(0, min_corner, max_corner)  # 0 = CLEAR_TERRAIN
				if job:
					print("[BattleHUD] Clear zone created: %.0fx%.0fm at (%0.f, %.0f)" % [
						bounds.size.x, bounds.size.y, bounds.position.x, bounds.position.y
					])

		CursorModeScript.Mode.PAINT_FLATTEN:
			if job_mgr.has_method("create_area_job"):
				job = job_mgr.create_area_job(1, min_corner, max_corner)  # 1 = FLATTEN_AREA
				if job:
					print("[BattleHUD] Flatten zone created: %.0fx%.0fm" % [bounds.size.x, bounds.size.y])

		CursorModeScript.Mode.PAINT_BUILD:
			# Build requires a specific building type - use build preview flow instead
			var building_type: int = _mode_context.get("building_type", -1)
			if building_type >= 0 and job_mgr.has_method("create_area_job"):
				var center := Vector3(
					bounds.position.x + bounds.size.x * 0.5,
					0,
					bounds.position.y + bounds.size.y * 0.5
				)
				# Use construction manager for build with prerequisites
				var construction_mgr := get_node_or_null("/root/ConstructionManager")
				if construction_mgr and construction_mgr.has_method("enqueue_build_with_prerequisites"):
					job = construction_mgr.enqueue_build_with_prerequisites(
						center, building_type, 0.0, Vector2(bounds.size.x, bounds.size.y)
					)
					if job:
						print("[BattleHUD] Build zone created at %s" % center)

		CursorModeScript.Mode.PAINT_ROAD:
			# Roads are polyline, handled separately
			pass

		CursorModeScript.Mode.PAINT_FILL:
			if job_mgr.has_method("create_area_job"):
				job = job_mgr.create_area_job(4, min_corner, max_corner)  # 4 = FILL_CRATER
				if job:
					print("[BattleHUD] Fill crater zone created")

	# Auto-assign selected workers to the new job
	if job:
		_auto_assign_workers_to_job(job)


func _auto_assign_workers_to_job(_job) -> void:
	## Legacy function - WorkerController now handles job assignment automatically
	## Workers use bottom-up job finding (Rimworld-style) instead of top-down assignment
	## See WorkerController for the auto-assignment logic
	pass


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


## Check if mouse is over any visible, clickable UI control
func _is_mouse_over_ui(control: Control, mouse_pos: Vector2) -> bool:
	if not control.visible:
		return false

	# Check if this control would receive the click
	if control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		var rect := control.get_global_rect()
		if rect.has_point(mouse_pos):
			# Found a control that would receive this click
			# But check children first (they might be more specific)
			for child in control.get_children():
				if child is Control:
					if _is_mouse_over_ui(child as Control, mouse_pos):
						return true
			# No child caught it, this control catches it
			if control.mouse_filter == Control.MOUSE_FILTER_STOP:
				return true

	# Check children even if this control ignores mouse
	for child in control.get_children():
		if child is Control:
			if _is_mouse_over_ui(child as Control, mouse_pos):
				return true

	return false
