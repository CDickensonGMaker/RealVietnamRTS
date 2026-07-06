extends Node3D
## Procedural Animation Test Scene
##
## Tests the Spring 1944-style procedural animation system using piece-based
## animation (not skeletal). Uses converted S3O models with named pieces.
##
## Controls:
##   - UI buttons to trigger poses
##   - UI buttons to play animation cycles
##   - Displays found pieces for debugging
##   - Arrow keys: Rotate camera
##   - Mouse wheel: Zoom

const PieceAnimatorScript = preload("res://battle_system/animation/piece_animator.gd")
const Spring1944PosesScript = preload("res://battle_system/animation/spring1944_poses.gd")

## References
var _model: Node3D = null
var _animator = null  # PieceAnimator instance
var _camera: Camera3D = null
var _info_label: Label = null
var _piece_list: Label = null

## S3O-converted model paths (not Mixamo-rigged!)
const MODEL_PATHS: Array = [
	"res://assets/models/us/infantry/us_rifle_infantry.glb",
	"res://assets/models/vc/infantry/vc_rifle_infantry.glb",
	"res://assets/models/us/infantry/us_engineer.glb",
	"res://assets/models/vc/infantry/vc_sapper.glb",
	"res://assets/models/us/infantry/us_mortar.glb",
	"res://assets/models/vc/infantry/vc_mortar.glb",
]
var _current_model_index: int = 0

var _current_state: String = "stand_idle"


func _ready() -> void:
	_setup_simple_environment()
	_create_ui()
	_spawn_model()

	print("=== Spring 1944 Procedural Animation Test ===")
	print("Uses piece-based animation (not skeletal)")
	print("Press M to cycle through models")
	print("Press 1-5 for quick pose changes")


func _setup_simple_environment() -> void:
	# Simple ground plane
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1

	var ground_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	ground_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.25)
	ground_mesh.material_override = mat
	ground.add_child(ground_mesh)

	var coll := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 0.2, 20)
	coll.shape = box
	coll.position.y = -0.1
	ground.add_child(coll)

	add_child(ground)

	# Lighting
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

	# Environment
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.4, 0.6, 0.85)
	sky_mat.sky_horizon_color = Color(0.7, 0.8, 0.9)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	world_env.environment = env
	add_child(world_env)

	# Camera focused on soldier position
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.position = Vector3(3, 2, 4)
	_camera.look_at(Vector3(0, 1, 0))
	_camera.current = true
	add_child(_camera)


func _spawn_model() -> void:
	if _model:
		_model.queue_free()
		_model = null
	_animator = null

	var model_path: String = MODEL_PATHS[_current_model_index]
	if not ResourceLoader.exists(model_path):
		push_warning("Model not found: %s" % model_path)
		_info_label.text = "Model not found: %s" % model_path.get_file()
		return

	var scene: PackedScene = load(model_path)
	if not scene:
		push_error("Failed to load model: %s" % model_path)
		return

	_model = scene.instantiate()
	_model.name = "TestModel"
	add_child(_model)
	_model.position = Vector3.ZERO

	# Scale up if model is very small (S3O models may need scaling)
	var aabb: AABB = _get_model_aabb(_model)
	var max_dim: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if max_dim < 0.5:
		_model.scale = Vector3.ONE * (2.0 / max_dim)
		print("[Test] Scaled model by %.2f" % (2.0 / max_dim))

	# Setup piece animator
	_animator = PieceAnimatorScript.new()
	if _animator.setup(_model):
		# Load Spring 1944 poses and cycles
		var poses: Dictionary = {}
		for pose_name: String in Spring1944PosesScript.POSES.keys():
			poses[pose_name] = Spring1944PosesScript.get_pose(pose_name)

		var cycles: Dictionary = {}
		for cycle_name: String in Spring1944PosesScript.CYCLES.keys():
			cycles[cycle_name] = Spring1944PosesScript.get_cycle(cycle_name)

		_animator.load_poses(poses)
		_animator.load_cycles(cycles)

		# Start with idle pose
		_animator.set_pose_immediate("stand_idle")
		_current_state = "stand_idle"

		print("[Test] Animation system ready with %d pieces" % _animator.get_found_pieces().size())
	else:
		print("[Test] Failed to setup animator - model may not have named pieces")

	_update_piece_list()
	print("[Test] Loaded model: %s" % model_path)


func _get_model_aabb(node: Node) -> AABB:
	var aabb := AABB()
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			aabb = aabb.merge(mi.mesh.get_aabb())

	for child in node.get_children():
		aabb = aabb.merge(_get_model_aabb(child))

	return aabb


func _create_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	canvas.layer = 10
	add_child(canvas)

	# Main container
	var main_vbox := VBoxContainer.new()
	main_vbox.position = Vector2(20, 20)
	main_vbox.add_theme_constant_override("separation", 10)
	canvas.add_child(main_vbox)

	# Title
	var title := Label.new()
	title.text = "Spring 1944 Animation Test"
	title.add_theme_font_size_override("font_size", 20)
	main_vbox.add_child(title)

	# Info label for current state
	_info_label = Label.new()
	_info_label.text = "State: stand_idle"
	_info_label.add_theme_font_size_override("font_size", 14)
	main_vbox.add_child(_info_label)

	# Pose buttons section
	var pose_label := Label.new()
	pose_label.text = "--- Static Poses ---"
	main_vbox.add_child(pose_label)

	var pose_grid := GridContainer.new()
	pose_grid.columns = 3
	pose_grid.add_theme_constant_override("h_separation", 5)
	pose_grid.add_theme_constant_override("v_separation", 5)
	main_vbox.add_child(pose_grid)

	# Create pose buttons
	var poses: PackedStringArray = Spring1944PosesScript.get_pose_names()
	for pose_name: String in poses:
		var btn := Button.new()
		btn.text = pose_name.replace("_", " ").capitalize()
		btn.custom_minimum_size = Vector2(100, 30)
		btn.pressed.connect(_on_pose_button_pressed.bind(pose_name))
		pose_grid.add_child(btn)

	# Cycle buttons section
	var cycle_label := Label.new()
	cycle_label.text = "--- Animation Cycles ---"
	main_vbox.add_child(cycle_label)

	var cycle_hbox := HBoxContainer.new()
	cycle_hbox.add_theme_constant_override("separation", 5)
	main_vbox.add_child(cycle_hbox)

	var cycles: PackedStringArray = Spring1944PosesScript.get_cycle_names()
	for cycle_name: String in cycles:
		var btn := Button.new()
		btn.text = cycle_name.capitalize()
		btn.custom_minimum_size = Vector2(80, 30)
		btn.pressed.connect(_on_cycle_button_pressed.bind(cycle_name))
		cycle_hbox.add_child(btn)

	var stop_btn := Button.new()
	stop_btn.text = "Stop"
	stop_btn.custom_minimum_size = Vector2(60, 30)
	stop_btn.pressed.connect(_on_stop_button_pressed)
	cycle_hbox.add_child(stop_btn)

	# Model selector
	var model_label := Label.new()
	model_label.text = "--- Model (Press M) ---"
	main_vbox.add_child(model_label)

	var model_hbox := HBoxContainer.new()
	model_hbox.add_theme_constant_override("separation", 5)
	main_vbox.add_child(model_hbox)

	for i in MODEL_PATHS.size():
		var btn := Button.new()
		var path: String = MODEL_PATHS[i]
		btn.text = path.get_file().replace(".glb", "").replace("_", " ")
		btn.custom_minimum_size = Vector2(100, 30)
		btn.pressed.connect(_on_model_button_pressed.bind(i))
		model_hbox.add_child(btn)

	# Piece list (right side)
	var piece_panel := PanelContainer.new()
	piece_panel.position = Vector2(800, 20)
	piece_panel.custom_minimum_size = Vector2(300, 400)
	canvas.add_child(piece_panel)

	var piece_scroll := ScrollContainer.new()
	piece_scroll.custom_minimum_size = Vector2(290, 390)
	piece_panel.add_child(piece_scroll)

	_piece_list = Label.new()
	_piece_list.text = "Pieces:\n(Loading...)"
	_piece_list.add_theme_font_size_override("font_size", 12)
	piece_scroll.add_child(_piece_list)


func _update_piece_list() -> void:
	if not _animator:
		_piece_list.text = "Pieces:\n(No animator)"
		return

	var found: PackedStringArray = _animator.get_found_pieces()

	var text: String = "Found Pieces (%d):\n" % found.size()
	text += "-------------------\n"

	for piece: String in found:
		text += "  %s\n" % piece

	text += "\n-------------------\n"
	text += "Expected Spring 1944 pieces:\n"

	for piece: String in Spring1944PosesScript.PIECE_NAMES:
		var status: String = "[OK]" if _animator.has_piece(piece) else "[MISSING]"
		text += "  %s %s\n" % [status, piece]

	text += "\n-------------------\n"
	text += "Model hierarchy:\n"
	if _model:
		_append_hierarchy(text, _model, 0)

	_piece_list.text = text


func _append_hierarchy(text: String, node: Node, depth: int) -> String:
	var indent: String = "  ".repeat(depth)
	text += "%s%s\n" % [indent, node.name]
	for child in node.get_children():
		if depth < 5:  # Limit depth
			text = _append_hierarchy(text, child, depth + 1)
	return text


func _on_pose_button_pressed(pose_name: String) -> void:
	if _animator:
		_animator.set_pose(pose_name)
		_current_state = pose_name
		_info_label.text = "State: %s" % pose_name
		print("[Test] Set pose: %s" % pose_name)


func _on_cycle_button_pressed(cycle_name: String) -> void:
	if _animator:
		_animator.play_cycle(cycle_name)
		_current_state = cycle_name
		_info_label.text = "State: %s (cycling)" % cycle_name
		print("[Test] Playing cycle: %s" % cycle_name)


func _on_stop_button_pressed() -> void:
	if _animator:
		_animator.stop_cycle("stand_idle")
		_current_state = "stand_idle"
		_info_label.text = "State: stand_idle"
		print("[Test] Stopped animation cycle")


func _on_model_button_pressed(index: int) -> void:
	_current_model_index = index
	_spawn_model()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not event.pressed:
		return

	var key := event as InputEventKey

	# Quick pose hotkeys
	match key.keycode:
		KEY_1:
			_on_pose_button_pressed("stand_idle")
		KEY_2:
			_on_pose_button_pressed("stand_aim")
		KEY_3:
			_on_pose_button_pressed("prone_idle")
		KEY_4:
			_on_pose_button_pressed("pinned")
		KEY_5:
			_on_pose_button_pressed("dead")
		KEY_6:
			_on_cycle_button_pressed("walk")
		KEY_7:
			_on_cycle_button_pressed("run")
		KEY_8:
			_on_cycle_button_pressed("crawl")
		KEY_M:
			_current_model_index = (_current_model_index + 1) % MODEL_PATHS.size()
			_spawn_model()
			print("[Test] Switched to model: %s" % MODEL_PATHS[_current_model_index])

	# Camera controls
	if key.keycode == KEY_LEFT:
		_camera.position = _camera.position.rotated(Vector3.UP, 0.1)
		_camera.look_at(Vector3(0, 1, 0))
	elif key.keycode == KEY_RIGHT:
		_camera.position = _camera.position.rotated(Vector3.UP, -0.1)
		_camera.look_at(Vector3(0, 1, 0))
	elif key.keycode == KEY_UP:
		_camera.position.y += 0.5
		_camera.look_at(Vector3(0, 1, 0))
	elif key.keycode == KEY_DOWN:
		_camera.position.y = maxf(0.5, _camera.position.y - 0.5)
		_camera.look_at(Vector3(0, 1, 0))


func _physics_process(delta: float) -> void:
	if _animator:
		_animator.update(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			var dir: Vector3 = (_camera.position - Vector3(0, 1, 0)).normalized()
			_camera.position -= dir * 0.5
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var dir: Vector3 = (_camera.position - Vector3(0, 1, 0)).normalized()
			_camera.position += dir * 0.5
