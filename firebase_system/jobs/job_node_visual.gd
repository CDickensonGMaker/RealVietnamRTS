class_name JobNodeVisual
extends Node3D
## JobNodeVisual - Handles the on-world appearance of a JobNode
##
## Shows the job's bounds as a colored outline while pending (green),
## gold while in progress, and fades when complete.
## Includes a floating progress bar and status label.

const JobTypes = preload("res://firebase_system/jobs/job_types.gd")
const JobNode = preload("res://firebase_system/jobs/job_node.gd")

## Colors for different states
const COLOR_PENDING := Color(0.2, 0.8, 0.2, 0.6)  # Green
const COLOR_IN_PROGRESS := Color(0.9, 0.7, 0.1, 0.8)  # Gold
const COLOR_COMPLETE := Color(0.5, 0.5, 0.5, 0.3)  # Gray, faded
const COLOR_BLOCKED := Color(0.8, 0.4, 0.1, 0.5)  # Orange - waiting for prereqs
const COLOR_CANCELLED := Color(0.8, 0.2, 0.2, 0.3)  # Red, faded

## Visual components
var outline_mesh: MeshInstance3D
var progress_bar_bg: MeshInstance3D
var progress_bar_fill: MeshInstance3D
var status_label: Label3D

## Reference to the job we're visualizing
var job: JobNode = null

## Materials
var outline_material: StandardMaterial3D
var progress_bg_material: StandardMaterial3D
var progress_fill_material: StandardMaterial3D

## Update rate limiting
const UPDATE_INTERVAL := 0.1  # 10Hz updates
var _update_timer := 0.0

## Fade tracking (Node3D doesn't have modulate)
var _alpha := 1.0

## ETA tracking
var _last_progress: float = 0.0
var _work_rate_samples: Array[float] = []  # Rolling average of work rate
const WORK_RATE_SAMPLE_COUNT := 10
var _eta_seconds: float = -1.0  # -1 means no ETA available


func _ready() -> void:
	_create_materials()
	_create_outline_mesh()
	_create_progress_bar()
	_create_status_label()


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_update_visuals()
		_update_eta()


## Initialize with a JobNode reference
func setup(p_job: JobNode) -> void:
	job = p_job

	# Connect to job signals
	if job:
		job.job_progress_updated.connect(_on_progress_updated)
		job.job_completed.connect(_on_job_completed)
		job.job_cancelled.connect(_on_job_cancelled)
		job.job_started.connect(_on_job_started)

	_update_visuals()
	_rebuild_outline()


func _create_materials() -> void:
	# Outline material
	outline_material = StandardMaterial3D.new()
	outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	outline_material.albedo_color = COLOR_PENDING

	# Progress bar background
	progress_bg_material = StandardMaterial3D.new()
	progress_bg_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	progress_bg_material.albedo_color = Color(0.2, 0.2, 0.2, 0.8)

	# Progress bar fill
	progress_fill_material = StandardMaterial3D.new()
	progress_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	progress_fill_material.albedo_color = Color(0.2, 0.8, 0.2)


func _create_outline_mesh() -> void:
	outline_mesh = MeshInstance3D.new()
	outline_mesh.name = "OutlineMesh"
	outline_mesh.material_override = outline_material
	add_child(outline_mesh)


func _create_progress_bar() -> void:
	# Background bar
	progress_bar_bg = MeshInstance3D.new()
	progress_bar_bg.name = "ProgressBarBG"
	progress_bar_bg.material_override = progress_bg_material

	var bg_box := BoxMesh.new()
	bg_box.size = Vector3(2.0, 0.15, 0.05)
	progress_bar_bg.mesh = bg_box

	add_child(progress_bar_bg)

	# Fill bar
	progress_bar_fill = MeshInstance3D.new()
	progress_bar_fill.name = "ProgressBarFill"
	progress_bar_fill.material_override = progress_fill_material

	var fill_box := BoxMesh.new()
	fill_box.size = Vector3(0.0, 0.15, 0.06)
	progress_bar_fill.mesh = fill_box

	add_child(progress_bar_fill)


func _create_status_label() -> void:
	status_label = Label3D.new()
	status_label.name = "StatusLabel"
	status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	status_label.no_depth_test = true
	status_label.font_size = 32
	status_label.outline_size = 4
	status_label.modulate = Color(1, 1, 1, 0.9)
	status_label.text = "Pending"

	add_child(status_label)


## Rebuild the outline mesh based on job bounds
func _rebuild_outline() -> void:
	if not job or not outline_mesh:
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	match job.job_type:
		JobTypes.JobType.CLEAR_TERRAIN, JobTypes.JobType.FLATTEN_AREA:
			_build_rect_outline(st)

		JobTypes.JobType.BUILD_ROAD:
			_build_road_outline(st)

		JobTypes.JobType.BUILD_STRUCTURE, JobTypes.JobType.FILL_CRATER:
			_build_point_outline(st)

	outline_mesh.mesh = st.commit()

	# Position the progress bar and label above the job
	var centroid: Vector3 = job.get_centroid() - global_position
	var bar_height: float = 3.0

	progress_bar_bg.position = Vector3(centroid.x, bar_height, centroid.z)
	progress_bar_fill.position = Vector3(centroid.x - 1.0, bar_height, centroid.z + 0.01)
	status_label.position = Vector3(centroid.x, bar_height + 0.5, centroid.z)


func _build_rect_outline(st: SurfaceTool) -> void:
	var bounds: AABB = job.area_bounds
	var min_pos: Vector3 = bounds.position - global_position
	var max_pos: Vector3 = min_pos + bounds.size

	# Outline height above ground
	var y: float = 0.2

	# Bottom rectangle
	var corners: Array[Vector3] = [
		Vector3(min_pos.x, y, min_pos.z),
		Vector3(max_pos.x, y, min_pos.z),
		Vector3(max_pos.x, y, max_pos.z),
		Vector3(min_pos.x, y, max_pos.z),
	]

	# Draw rectangle
	for i in range(4):
		st.add_vertex(corners[i])
		st.add_vertex(corners[(i + 1) % 4])

	# Draw grid pattern inside (every 2m)
	var grid_spacing := 2.0
	var x_count := int(bounds.size.x / grid_spacing)
	var z_count := int(bounds.size.z / grid_spacing)

	# Vertical lines
	for i in range(1, x_count):
		var x: float = min_pos.x + i * grid_spacing
		st.add_vertex(Vector3(x, y, min_pos.z))
		st.add_vertex(Vector3(x, y, max_pos.z))

	# Horizontal lines
	for i in range(1, z_count):
		var z: float = min_pos.z + i * grid_spacing
		st.add_vertex(Vector3(min_pos.x, y, z))
		st.add_vertex(Vector3(max_pos.x, y, z))


func _build_road_outline(st: SurfaceTool) -> void:
	if job.path_points.size() < 2:
		return

	var road_width := 3.0
	var half_width := road_width * 0.5
	var y := 0.2

	for i in range(job.path_points.size() - 1):
		var p1: Vector3 = job.path_points[i] - global_position
		var p2: Vector3 = job.path_points[i + 1] - global_position

		# Calculate perpendicular direction
		var dir: Vector3 = (p2 - p1).normalized()
		var perp := Vector3(-dir.z, 0, dir.x) * half_width

		# Draw road segment outline
		var corners: Array[Vector3] = [
			Vector3(p1.x + perp.x, y, p1.z + perp.z),
			Vector3(p1.x - perp.x, y, p1.z - perp.z),
			Vector3(p2.x - perp.x, y, p2.z - perp.z),
			Vector3(p2.x + perp.x, y, p2.z + perp.z),
		]

		for j in range(4):
			st.add_vertex(corners[j])
			st.add_vertex(corners[(j + 1) % 4])

		# Center line (dashed effect via segments)
		st.add_vertex(Vector3(p1.x, y, p1.z))
		st.add_vertex(Vector3(p2.x, y, p2.z))

	# Draw waypoint markers
	for pt in job.path_points:
		var local_pt: Vector3 = pt - global_position
		_add_cross_marker(st, local_pt, 0.5)


func _build_point_outline(st: SurfaceTool) -> void:
	var center: Vector3 = job.center_position - global_position
	var radius: float = 2.0
	var y: float = 0.2

	# Draw circle
	var segments := 16
	for i in range(segments):
		var angle1: float = TAU * float(i) / float(segments)
		var angle2: float = TAU * float(i + 1) / float(segments)

		st.add_vertex(Vector3(center.x + cos(angle1) * radius, y, center.z + sin(angle1) * radius))
		st.add_vertex(Vector3(center.x + cos(angle2) * radius, y, center.z + sin(angle2) * radius))

	# Center cross
	_add_cross_marker(st, center, 1.0)


func _add_cross_marker(st: SurfaceTool, pos: Vector3, size: float) -> void:
	var y: float = 0.2
	var half := size * 0.5

	st.add_vertex(Vector3(pos.x - half, y, pos.z))
	st.add_vertex(Vector3(pos.x + half, y, pos.z))
	st.add_vertex(Vector3(pos.x, y, pos.z - half))
	st.add_vertex(Vector3(pos.x, y, pos.z + half))


## Update visuals based on current job state
func _update_visuals() -> void:
	if not job:
		return

	# Update color based on state
	var color: Color
	match job.completion_state:
		JobTypes.CompletionState.PENDING:
			color = COLOR_BLOCKED if not job.can_be_worked() else COLOR_PENDING
		JobTypes.CompletionState.IN_PROGRESS:
			color = COLOR_IN_PROGRESS
		JobTypes.CompletionState.COMPLETE:
			color = COLOR_COMPLETE
		JobTypes.CompletionState.CANCELLED:
			color = COLOR_CANCELLED
		_:
			color = COLOR_PENDING

	outline_material.albedo_color = color

	# Update progress bar
	_update_progress_bar()

	# Update status label with ETA
	var base_text: String = job.get_status_text()
	var eta_text: String = _format_eta() if job.completion_state == JobTypes.CompletionState.IN_PROGRESS else ""
	status_label.text = base_text + eta_text

	# Show prerequisite chain info if applicable
	if job.prerequisites.size() > 0:
		var pending_prereqs := 0
		for prereq in job.prerequisites:
			if is_instance_valid(prereq) and prereq.completion_state != JobTypes.CompletionState.COMPLETE:
				pending_prereqs += 1

		if pending_prereqs > 0:
			var step := job.prerequisites.size() - pending_prereqs + 1
			var total_steps := job.prerequisites.size() + 1  # +1 for this job
			status_label.text = "Step %d/%d: %s%s" % [step, total_steps, job.get_status_text(), eta_text]

	# Fade out when complete
	if job.completion_state == JobTypes.CompletionState.COMPLETE:
		_alpha = maxf(0.0, _alpha - 0.02)  # Fade out
		_apply_alpha(_alpha)
		if _alpha <= 0.0:
			queue_free()


func _update_progress_bar() -> void:
	if not job:
		return

	var progress: float = job.get_progress_percent() / 100.0

	# Update fill bar size and position
	var fill_mesh: BoxMesh = progress_bar_fill.mesh as BoxMesh
	if fill_mesh:
		var full_width := 2.0
		var fill_width: float = full_width * progress
		fill_mesh.size = Vector3(fill_width, 0.15, 0.06)

		# Reposition to align left edge
		var centroid: Vector3 = job.get_centroid() - global_position
		progress_bar_fill.position.x = centroid.x - 1.0 + fill_width * 0.5

	# Update fill color based on progress
	if progress < 0.33:
		progress_fill_material.albedo_color = Color(0.8, 0.2, 0.2)  # Red
	elif progress < 0.66:
		progress_fill_material.albedo_color = Color(0.8, 0.7, 0.1)  # Yellow
	else:
		progress_fill_material.albedo_color = Color(0.2, 0.8, 0.2)  # Green


## Update ETA calculation based on work rate
func _update_eta() -> void:
	if not job:
		_eta_seconds = -1.0
		return

	# Only calculate ETA for in-progress jobs
	if job.completion_state != JobTypes.CompletionState.IN_PROGRESS:
		_eta_seconds = -1.0
		_last_progress = job.current_progress
		return

	# Calculate work done since last update
	var work_delta: float = job.current_progress - _last_progress
	_last_progress = job.current_progress

	# Only track positive work (in case of resets)
	if work_delta > 0:
		# Work rate per second (work_delta in UPDATE_INTERVAL seconds)
		var work_rate: float = work_delta / UPDATE_INTERVAL

		# Add to rolling average
		_work_rate_samples.append(work_rate)
		if _work_rate_samples.size() > WORK_RATE_SAMPLE_COUNT:
			_work_rate_samples.pop_front()

	# Calculate average work rate
	if _work_rate_samples.is_empty():
		_eta_seconds = -1.0
		return

	var avg_rate: float = 0.0
	for rate in _work_rate_samples:
		avg_rate += rate
	avg_rate /= float(_work_rate_samples.size())

	# Calculate ETA
	if avg_rate > 0.001:  # Avoid division by tiny numbers
		var remaining_work: float = job.total_work - job.current_progress
		_eta_seconds = remaining_work / avg_rate
	else:
		_eta_seconds = -1.0


## Format ETA for display
func _format_eta() -> String:
	if _eta_seconds < 0:
		return ""

	if _eta_seconds < 60:
		return " (~%ds)" % int(_eta_seconds)
	elif _eta_seconds < 3600:
		var mins: int = int(_eta_seconds / 60)
		var secs: int = int(_eta_seconds) % 60
		return " (~%dm %ds)" % [mins, secs]
	else:
		var hours: int = int(_eta_seconds / 3600)
		var mins: int = int(fmod(_eta_seconds, 3600) / 60)
		return " (~%dh %dm)" % [hours, mins]


## Signal handlers
func _on_progress_updated(_progress: float) -> void:
	_update_progress_bar()


func _on_job_started() -> void:
	_update_visuals()


func _on_job_completed(_job: JobNode) -> void:
	_update_visuals()


func _on_job_cancelled(_job: JobNode) -> void:
	_update_visuals()
	# Quick fade out for cancelled jobs
	var tween := create_tween()
	tween.tween_method(_apply_alpha, _alpha, 0.0, 0.5)
	tween.tween_callback(queue_free)


## Apply alpha to all materials (Node3D doesn't have modulate)
func _apply_alpha(alpha: float) -> void:
	_alpha = alpha
	if outline_material:
		var c := outline_material.albedo_color
		outline_material.albedo_color = Color(c.r, c.g, c.b, c.a * alpha)
	if progress_bg_material:
		var c := progress_bg_material.albedo_color
		progress_bg_material.albedo_color = Color(c.r, c.g, c.b, 0.8 * alpha)
	if progress_fill_material:
		var c := progress_fill_material.albedo_color
		progress_fill_material.albedo_color = Color(c.r, c.g, c.b, alpha)
	if status_label:
		status_label.modulate.a = alpha
