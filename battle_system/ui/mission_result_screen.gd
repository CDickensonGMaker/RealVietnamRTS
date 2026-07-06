extends Control
class_name MissionResultScreen
## MissionResultScreen - Victory/Defeat screen with stats
## Shows after mission ends, allows restart or return to menu

signal continue_pressed
signal restart_pressed
signal quit_pressed

## UI Components
var _panel: PanelContainer
var _title_label: Label
var _subtitle_label: Label
var _stats_container: VBoxContainer
var _button_container: HBoxContainer

## Is this a victory or defeat screen
var is_victory: bool = true


func _ready() -> void:
	_create_ui()
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS  # Work while paused


func _create_ui() -> void:
	# Full screen overlay
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Dark background
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Center panel
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -250
	_panel.offset_right = 250
	_panel.offset_top = -200
	_panel.offset_bottom = 200
	add_child(_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.95)
	style.border_color = Color(0.4, 0.4, 0.4)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	_panel.add_child(vbox)

	# Title
	_title_label = Label.new()
	_title_label.text = "VICTORY"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 36)
	_title_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
	vbox.add_child(_title_label)

	# Subtitle
	_subtitle_label = Label.new()
	_subtitle_label.text = "Mission Complete"
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 18)
	_subtitle_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(_subtitle_label)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Stats
	_stats_container = VBoxContainer.new()
	_stats_container.add_theme_constant_override("separation", 8)
	vbox.add_child(_stats_container)

	# Separator
	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# Buttons
	_button_container = HBoxContainer.new()
	_button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_button_container.add_theme_constant_override("separation", 20)
	vbox.add_child(_button_container)

	var continue_btn := Button.new()
	continue_btn.text = "Continue"
	continue_btn.custom_minimum_size = Vector2(120, 40)
	continue_btn.pressed.connect(_on_continue_pressed)
	_button_container.add_child(continue_btn)

	var restart_btn := Button.new()
	restart_btn.text = "Restart"
	restart_btn.custom_minimum_size = Vector2(120, 40)
	restart_btn.pressed.connect(_on_restart_pressed)
	_button_container.add_child(restart_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.custom_minimum_size = Vector2(120, 40)
	quit_btn.pressed.connect(_on_quit_pressed)
	_button_container.add_child(quit_btn)


## Show with victory state
func show_victory(stats: Dictionary = {}) -> void:
	is_victory = true
	_title_label.text = "VICTORY"
	_title_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
	_subtitle_label.text = "Mission Complete"
	_show_stats(stats)
	visible = true


## Show with defeat state
func show_defeat(stats: Dictionary = {}) -> void:
	is_victory = false
	_title_label.text = "DEFEAT"
	_title_label.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3))
	_subtitle_label.text = "Mission Failed"
	_show_stats(stats)
	visible = true


## Generic show_stats method (called by MissionManager)
func show_stats(stats: Dictionary) -> void:
	_show_stats(stats)


func _show_stats(stats: Dictionary) -> void:
	# Clear old stats
	for child in _stats_container.get_children():
		child.queue_free()

	# Add stat lines
	_add_stat_line("Time", _format_time(stats.get("elapsed_time", 0.0)))
	_add_stat_line("Units Lost", str(stats.get("units_lost", 0)))
	_add_stat_line("Enemies Killed", str(stats.get("enemies_killed", 0)))
	_add_stat_line("Buildings Built", str(stats.get("buildings_constructed", 0)))

	var primary_complete: int = stats.get("primary_complete", 0)
	var primary_total: int = stats.get("primary_total", 0)
	_add_stat_line("Primary Objectives", "%d / %d" % [primary_complete, primary_total])

	var secondary_complete: int = stats.get("secondary_complete", 0)
	var secondary_total: int = stats.get("secondary_total", 0)
	if secondary_total > 0:
		_add_stat_line("Secondary Objectives", "%d / %d" % [secondary_complete, secondary_total])


func _add_stat_line(label_text: String, value_text: String) -> void:
	var hbox := HBoxContainer.new()

	var label := Label.new()
	label.text = label_text + ":"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hbox.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 16)
	value.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	hbox.add_child(value)

	_stats_container.add_child(hbox)


func _format_time(seconds: float) -> String:
	var mins: int = int(seconds / 60.0)
	var secs: int = int(seconds) % 60
	return "%d:%02d" % [mins, secs]


func _on_continue_pressed() -> void:
	visible = false
	get_tree().paused = false
	continue_pressed.emit()


func _on_restart_pressed() -> void:
	visible = false
	get_tree().paused = false
	restart_pressed.emit()
	# Reload current scene
	get_tree().reload_current_scene()


func _on_quit_pressed() -> void:
	visible = false
	get_tree().paused = false
	quit_pressed.emit()
	# Return to main menu or quit
	get_tree().quit()
