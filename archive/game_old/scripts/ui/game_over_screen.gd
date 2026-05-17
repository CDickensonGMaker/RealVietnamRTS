extends ColorRect
## GameOverScreen - Victory/Defeat display
## Shows when game ends with stats

signal restart_requested
signal quit_requested

var is_victory: bool = false


func _ready() -> void:
	visible = false
	color = Color(0, 0, 0, 0.8)

	# Connect to game manager
	GameManager.game_ended.connect(_on_game_ended)

	_setup_ui()


func _setup_ui() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.anchors_preset = Control.PRESET_FULL_RECT
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 300)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Stats
	var stats := Label.new()
	stats.name = "StatsLabel"
	stats.text = "Time: 00:00\nWaves Survived: 0\nEnemies Killed: 0"
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stats)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# Buttons
	var btn_container := HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_container)

	var restart_btn := Button.new()
	restart_btn.text = "Restart"
	restart_btn.custom_minimum_size = Vector2(100, 40)
	restart_btn.pressed.connect(_on_restart_pressed)
	btn_container.add_child(restart_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.custom_minimum_size = Vector2(100, 40)
	quit_btn.pressed.connect(_on_quit_pressed)
	btn_container.add_child(quit_btn)


func _on_game_ended(victory: bool) -> void:
	is_victory = victory
	visible = true

	# Update title
	var title_node: Node = get_node_or_null("CenterContainer/PanelContainer/VBoxContainer/TitleLabel")
	var title := title_node as Label
	if title:
		if victory:
			title.text = "VICTORY!"
			title.add_theme_color_override("font_color", Color.GREEN)
		else:
			title.text = "DEFEAT"
			title.add_theme_color_override("font_color", Color.RED)

	# Update stats
	var stats_node: Node = get_node_or_null("CenterContainer/PanelContainer/VBoxContainer/StatsLabel")
	var stats := stats_node as Label
	if stats:
		var time: String = GameManager.get_formatted_time()
		var waves := 0
		var ai_director: Node = get_node_or_null("/root/Main/Directors/AIDirector")
		if ai_director:
			waves = ai_director.get_current_wave()

		stats.text = "Time Survived: %s\nWaves Survived: %d\nUnits Remaining: %d" % [
			time, waves, GameManager.player_squads.size()
		]


func _on_restart_pressed() -> void:
	visible = false
	restart_requested.emit()
	get_tree().reload_current_scene()


func _on_quit_pressed() -> void:
	quit_requested.emit()
	get_tree().quit()
