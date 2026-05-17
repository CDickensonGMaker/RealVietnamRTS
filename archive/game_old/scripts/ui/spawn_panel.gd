extends PanelContainer
## SpawnPanel - UI for spawning units from Command Post
## Shows available units with costs and spawn queue

signal unit_queued(unit_type: String)

const UNIT_INFO := {
	"rifle_squad": {"name": "Rifle", "cost": 20, "icon": "R"},
	"engineer_squad": {"name": "Engineer", "cost": 25, "icon": "E"},
	"recon_team": {"name": "Recon", "cost": 15, "icon": "S"},
	"weapons_squad": {"name": "Weapons", "cost": 35, "icon": "W"},
	"medic_team": {"name": "Medic", "cost": 15, "icon": "M"},
}

var command_post: Node3D = null
var spawn_buttons: Dictionary = {}
var queue_labels: Array[Label] = []


func _ready() -> void:
	_setup_ui()

	await get_tree().process_frame
	_find_command_post()


func _process(_delta: float) -> void:
	_update_button_states()
	_update_queue_display()
	_update_progress_display()


func _setup_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	add_child(vbox)

	# Header
	var header := Label.new()
	header.text = "TRAIN UNITS"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Spawn buttons grid
	var grid := GridContainer.new()
	grid.columns = 2
	grid.name = "SpawnGrid"
	vbox.add_child(grid)

	for unit_type in UNIT_INFO:
		var info: Dictionary = UNIT_INFO[unit_type]
		var btn := Button.new()
		btn.name = unit_type + "_btn"
		btn.text = "%s ($%d)" % [info.name, info.cost]
		btn.custom_minimum_size = Vector2(80, 30)
		btn.pressed.connect(_on_spawn_button_pressed.bind(unit_type))
		grid.add_child(btn)
		spawn_buttons[unit_type] = btn

	# Separator
	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# Queue display
	var queue_label := Label.new()
	queue_label.name = "QueueLabel"
	queue_label.text = "Queue:"
	vbox.add_child(queue_label)

	var queue_container := HBoxContainer.new()
	queue_container.name = "QueueContainer"
	vbox.add_child(queue_container)

	# Create queue slot labels
	for i in range(5):
		var slot := Label.new()
		slot.text = "[ ]"
		slot.custom_minimum_size = Vector2(25, 20)
		queue_container.add_child(slot)
		queue_labels.append(slot)

	# Progress bar
	var progress := ProgressBar.new()
	progress.name = "SpawnProgress"
	progress.custom_minimum_size = Vector2(0, 15)
	progress.max_value = 100
	progress.value = 0
	vbox.add_child(progress)


func _find_command_post() -> void:
	command_post = GameManager.command_post


func _on_spawn_button_pressed(unit_type: String) -> void:
	if not command_post:
		_find_command_post()

	if command_post and command_post.has_method("queue_spawn"):
		if command_post.queue_spawn(unit_type):
			unit_queued.emit(unit_type)


func _update_button_states() -> void:
	for unit_type in spawn_buttons:
		var btn: Button = spawn_buttons[unit_type]
		var info: Dictionary = UNIT_INFO[unit_type]

		# Check if can afford
		var cost: int = info.cost
		var can_afford: bool = GameManager.supplies >= cost
		btn.disabled = not can_afford

		if can_afford:
			btn.modulate = Color.WHITE
		else:
			btn.modulate = Color(0.5, 0.5, 0.5)


func _update_queue_display() -> void:
	if not command_post:
		return

	var queue: Array = []
	if command_post.has_method("get_spawn_queue"):
		queue = command_post.get_spawn_queue()

	for i in range(queue_labels.size()):
		var label: Label = queue_labels[i]
		if i < queue.size():
			var unit_type: String = queue[i]
			var info: Dictionary = UNIT_INFO.get(unit_type, {"icon": "?"})
			label.text = "[%s]" % info.icon
		else:
			label.text = "[ ]"


func _update_progress_display() -> void:
	var progress_bar_node: Node = get_node_or_null("VBox/SpawnProgress")
	var progress_bar := progress_bar_node as ProgressBar
	if not progress_bar or not command_post:
		return

	if command_post.has_method("get_spawn_progress"):
		progress_bar.value = command_post.get_spawn_progress() * 100
	else:
		progress_bar.value = 0
