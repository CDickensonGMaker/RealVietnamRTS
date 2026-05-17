extends PanelContainer
## HelpOverlay - Shows controls and hotkeys
## Toggle with F1 or H key

var is_visible_state: bool = false

const HELP_TEXT := """FIREBASE COMMAND - CONTROLS

CAMERA:
  WASD / Arrow Keys - Pan camera
  Q / E - Rotate camera
  Mouse Wheel - Zoom in/out
  Middle Mouse Drag - Rotate

SELECTION:
  Left Click - Select unit
  Left Drag - Box select
  Shift+Click - Add to selection

COMMANDS:
  Right Click - Move / Attack
  Shift+Right Click - Queue waypoint
  P - Set patrol route (click waypoints, right-click to confirm)

HOTKEYS:
  B - Open build menu
  Escape - Cancel / Deselect

DEBUG (Development):
  F1 - Spawn test enemies
  F2 - Add 100 supplies
  F3 - Spawn rifle squad
  F4 - Trigger enemy wave
  F9 - Print debug info
  H - Toggle this help

OBJECTIVE:
  Defend your firebase!
  Build defenses, send patrols, destroy enemy positions.
  Don't let your Command Post be destroyed!
"""


func _ready() -> void:
	_setup_ui()
	visible = false


func _setup_ui() -> void:
	custom_minimum_size = Vector2(400, 500)

	# Center on screen
	anchors_preset = Control.PRESET_CENTER
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "HELP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(370, 400)
	vbox.add_child(scroll)

	var help_label := Label.new()
	help_label.text = HELP_TEXT
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	scroll.add_child(help_label)

	var close_btn := Button.new()
	close_btn.text = "Close (H)"
	close_btn.pressed.connect(toggle_help)
	vbox.add_child(close_btn)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_H:
			toggle_help()


func toggle_help() -> void:
	is_visible_state = not is_visible_state
	visible = is_visible_state


func show_help() -> void:
	is_visible_state = true
	visible = true


func hide_help() -> void:
	is_visible_state = false
	visible = false
