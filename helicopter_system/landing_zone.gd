extends Node3D
class_name LandingZone

## Landing Zone (LZ) - Helicopter landing point
## Can be hot (under fire), warm (nearby enemies), or cold (safe)

signal lz_status_changed(lz: LandingZone, is_hot: bool)
signal helicopter_arrived(lz: LandingZone, helicopter: Node3D)
signal helicopter_departed(lz: LandingZone, helicopter: Node3D)

enum LZStatus { COLD, WARM, HOT }

## Configuration
@export var lz_name: String = "LZ Alpha"
@export var lz_radius: float = 15.0
@export var capacity: int = 2  # Max helicopters at once

## State
var status: LZStatus = LZStatus.COLD
var threat_level: float = 0.0  # 0.0 = safe, 1.0 = heavy fire
var helicopters_present: Array[Node3D] = []
var is_active: bool = true

## Threat assessment
var _threat_check_timer: float = 0.0
const THREAT_CHECK_INTERVAL := 2.0
const THREAT_DECAY_RATE := 0.1


func _ready() -> void:
	add_to_group("landing_zones")
	_create_visual()


func _create_visual() -> void:
	"""Create visual marker for LZ"""
	# Ground marker (flat disc)
	var marker := MeshInstance3D.new()
	marker.name = "LZMarker"

	var disc := CylinderMesh.new()
	disc.top_radius = lz_radius
	disc.bottom_radius = lz_radius
	disc.height = 0.1
	marker.mesh = disc
	marker.position.y = 0.05

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 0.2, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = mat

	add_child(marker)

	# Helipad cross
	var cross_h := MeshInstance3D.new()
	cross_h.name = "CrossH"
	var box_h := BoxMesh.new()
	box_h.size = Vector3(lz_radius * 1.5, 0.15, lz_radius * 0.2)
	cross_h.mesh = box_h
	cross_h.position.y = 0.1

	var cross_mat := StandardMaterial3D.new()
	cross_mat.albedo_color = Color(1.0, 1.0, 0.2, 0.8)
	cross_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cross_h.material_override = cross_mat
	add_child(cross_h)

	var cross_v := MeshInstance3D.new()
	cross_v.name = "CrossV"
	var box_v := BoxMesh.new()
	box_v.size = Vector3(lz_radius * 0.2, 0.15, lz_radius * 1.5)
	cross_v.mesh = box_v
	cross_v.position.y = 0.1
	cross_v.material_override = cross_mat
	add_child(cross_v)


func _process(delta: float) -> void:
	_threat_check_timer += delta
	if _threat_check_timer >= THREAT_CHECK_INTERVAL:
		_threat_check_timer = 0.0
		_assess_threat()
	else:
		# Decay threat over time
		threat_level = maxf(threat_level - THREAT_DECAY_RATE * delta, 0.0)
		_update_status()


func _assess_threat() -> void:
	"""Check for nearby enemy units"""
	var enemy_groups: Array[String] = ["enemy_units"]
	var threat_count: int = 0
	var threat_distance: float = 0.0

	for group in enemy_groups:
		var enemies: Array[Node] = get_tree().get_nodes_in_group(group)
		for enemy in enemies:
			if not is_instance_valid(enemy):
				continue
			var dist: float = global_position.distance_to(enemy.global_position)
			if dist < 100.0:  # Threat range
				threat_count += 1
				threat_distance += dist

	# Calculate threat level
	if threat_count > 0:
		var avg_dist: float = threat_distance / float(threat_count)
		var distance_factor: float = 1.0 - (avg_dist / 100.0)
		threat_level = minf(threat_level + distance_factor * 0.2, 1.0)

		# Increase threat if enemies are very close
		if avg_dist < 30.0:
			threat_level = minf(threat_level + 0.3, 1.0)

	_update_status()


func _update_status() -> void:
	"""Update LZ status based on threat level"""
	var old_status: LZStatus = status

	if threat_level >= 0.7:
		status = LZStatus.HOT
	elif threat_level >= 0.3:
		status = LZStatus.WARM
	else:
		status = LZStatus.COLD

	if status != old_status:
		lz_status_changed.emit(self, status == LZStatus.HOT)
		_update_visual()


func _update_visual() -> void:
	"""Update visual to reflect status"""
	var marker: MeshInstance3D = get_node_or_null("LZMarker")
	if not marker:
		return

	var mat: StandardMaterial3D = marker.material_override as StandardMaterial3D
	if not mat:
		return

	match status:
		LZStatus.COLD:
			mat.albedo_color = Color(0.2, 0.6, 0.2, 0.3)
		LZStatus.WARM:
			mat.albedo_color = Color(0.8, 0.6, 0.1, 0.4)
		LZStatus.HOT:
			mat.albedo_color = Color(0.8, 0.2, 0.1, 0.5)


## Public API

func can_land() -> bool:
	"""Check if a helicopter can land here"""
	return is_active and helicopters_present.size() < capacity


func register_helicopter(heli: Node3D) -> void:
	"""Register helicopter as present at LZ"""
	if heli not in helicopters_present:
		helicopters_present.append(heli)
		helicopter_arrived.emit(self, heli)


func unregister_helicopter(heli: Node3D) -> void:
	"""Remove helicopter from LZ"""
	helicopters_present.erase(heli)
	helicopter_departed.emit(self, heli)


func get_landing_position() -> Vector3:
	"""Get a position to land at within the LZ"""
	var offset_angle: float = randf() * TAU
	var offset_dist: float = randf() * (lz_radius * 0.5)
	var offset := Vector3(cos(offset_angle), 0, sin(offset_angle)) * offset_dist
	return global_position + offset


func is_hot() -> bool:
	return status == LZStatus.HOT


func is_safe() -> bool:
	return status == LZStatus.COLD


func add_threat(amount: float) -> void:
	"""Manually add threat (e.g., when taking fire)"""
	threat_level = minf(threat_level + amount, 1.0)
	_update_status()
