extends Node
## GameManager - Central game state and coordination
## Handles game flow, victory/defeat conditions, and global references

signal game_started
signal game_paused(is_paused: bool)
signal game_ended(victory: bool)
signal supplies_changed(new_amount: int)

enum GameState { MENU, PLAYING, PAUSED, VICTORY, DEFEAT }

var current_state: GameState = GameState.MENU

# Resources
var supplies: int = 100:
	set(value):
		supplies = max(0, value)
		supplies_changed.emit(supplies)

var max_supply_storage: int = 200

# References (set by scenes)
var command_post: Node3D = null
var player_squads: Array[Node3D] = []
var enemy_positions: Array[Node3D] = []
var structures: Array[Node3D] = []

# Game time tracking
var game_time: float = 0.0
var game_speed: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if current_state == GameState.PLAYING:
		game_time += delta * game_speed


func start_game() -> void:
	current_state = GameState.PLAYING
	game_time = 0.0
	game_started.emit()


func pause_game() -> void:
	if current_state == GameState.PLAYING:
		current_state = GameState.PAUSED
		get_tree().paused = true
		game_paused.emit(true)
	elif current_state == GameState.PAUSED:
		current_state = GameState.PLAYING
		get_tree().paused = false
		game_paused.emit(false)


func end_game(victory: bool) -> void:
	if victory:
		current_state = GameState.VICTORY
	else:
		current_state = GameState.DEFEAT
	game_ended.emit(victory)


func spend_supplies(amount: int) -> bool:
	if supplies >= amount:
		supplies -= amount
		return true
	return false


func add_supplies(amount: int) -> void:
	supplies = min(supplies + amount, max_supply_storage)


func register_squad(squad: Node3D) -> void:
	if squad not in player_squads:
		player_squads.append(squad)


func unregister_squad(squad: Node3D) -> void:
	player_squads.erase(squad)


func register_structure(structure: Node3D) -> void:
	if structure not in structures:
		structures.append(structure)


func unregister_structure(structure: Node3D) -> void:
	structures.erase(structure)


func get_formatted_time() -> String:
	var minutes := int(game_time) / 60
	var seconds := int(game_time) % 60
	return "%02d:%02d" % [minutes, seconds]
