@tool
extends EditorPlugin
## Simple building model viewer - 400x400 popup window

var dock: Control
var window: Window
var toolbar_button: Button


func _enter_tree() -> void:
	# Load the dock scene
	dock = preload("res://addons/building_viewer/building_viewer.tscn").instantiate()

	# Create 400x400 popup window
	window = Window.new()
	window.title = "Building Viewer"
	window.size = Vector2i(400, 400)
	window.min_size = Vector2i(400, 400)
	window.max_size = Vector2i(400, 400)
	window.visible = false
	window.wrap_controls = true
	window.transient = true
	window.close_requested.connect(_on_close)

	window.add_child(dock)
	dock.set_anchors_preset(Control.PRESET_FULL_RECT)
	EditorInterface.get_base_control().add_child(window)

	# Toolbar button
	toolbar_button = Button.new()
	toolbar_button.text = "Buildings"
	toolbar_button.toggle_mode = true
	toolbar_button.toggled.connect(_on_toggle)
	add_control_to_container(CONTAINER_TOOLBAR, toolbar_button)


func _exit_tree() -> void:
	if toolbar_button:
		remove_control_from_container(CONTAINER_TOOLBAR, toolbar_button)
		toolbar_button.queue_free()

	if window:
		window.queue_free()


func _on_toggle(pressed: bool) -> void:
	window.visible = pressed
	if pressed:
		# Center on screen
		var screen := DisplayServer.screen_get_size()
		window.position = Vector2i((screen.x - 400) / 2, (screen.y - 400) / 2)


func _on_close() -> void:
	window.visible = false
	toolbar_button.button_pressed = false
