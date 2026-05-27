extends StaticBody3D
class_name PlacedBuilding

## Base class for scene-placed buildings (drag from Godot editor)
## Automatically registers with the firebase system when placed in a level

const BuildingData = preload("res://firebase_system/building_data.gd")
const Firebase = preload("res://firebase_system/firebase.gd")

signal building_destroyed(building: PlacedBuilding)

## Configuration (set in editor or derived scenes)
@export var building_type: BuildingData.BuildingType = BuildingData.BuildingType.BUNKER
@export var auto_create_firebase: bool = true  ## If true and this is HQ, create Firebase automatically
@export var firebase_influence_radius: float = 168.0  ## Override influence radius if creating firebase

## State
var building_data: BuildingData = null
var owning_firebase: Firebase = null
var _is_destroyed: bool = false

## Visual
@onready var _model: Node3D = $Model if has_node("Model") else null


func _ready() -> void:
	# Load building data
	building_data = BuildingData.get_building_data(building_type)
	if not building_data:
		push_error("[PlacedBuilding] Invalid building type: %d" % building_type)
		return

	# Add to groups
	add_to_group("buildings")
	add_to_group("all_units")

	if building_data.is_hq_building:
		add_to_group("hq_buildings")

	# Setup collision
	_setup_collision()

	# Register with firebase system on next frame (let tree settle)
	call_deferred("_register_with_firebase_system")

	print("[PlacedBuilding] %s placed at %s" % [building_data.display_name, global_position])


func _setup_collision() -> void:
	"""Setup collision shape based on building footprint"""
	if has_node("CollisionShape3D"):
		return  # Already has collision

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"

	var box := BoxShape3D.new()
	# Use footprint from building data or default
	var footprint: Vector2 = building_data.footprint_size if building_data else Vector2(4, 4)
	box.size = Vector3(footprint.x, 3.0, footprint.y)

	collision.shape = box
	collision.position.y = 1.5  # Center vertically
	add_child(collision)

	# Set collision layers (layer 7 = buildings)
	collision_layer = 64
	collision_mask = 1  # Collide with terrain


func _register_with_firebase_system() -> void:
	"""Register this building with the firebase system"""
	# Find or create owning firebase
	owning_firebase = _find_nearest_firebase()

	if building_data.is_hq_building:
		_handle_hq_placement()
	elif owning_firebase:
		_register_with_firebase(owning_firebase)


func _find_nearest_firebase() -> Firebase:
	"""Find the nearest firebase (active or not) within reasonable range"""
	var firebases: Array = get_tree().get_nodes_in_group("firebases")
	var nearest: Firebase = null
	var nearest_dist: float = INF

	for fb: Node in firebases:
		if fb is Firebase:
			var dist: float = global_position.distance_to(fb.global_position)
			# Only consider firebases within 500m (generous for scene placement)
			if dist < 500.0 and dist < nearest_dist:
				nearest = fb
				nearest_dist = dist

	if nearest:
		print("[PlacedBuilding] Found firebase %s at %.0fm" % [nearest.firebase_name, nearest_dist])

	return nearest


func _handle_hq_placement() -> void:
	"""Handle placement of HQ building (TOC, Command Post, etc.)"""
	if owning_firebase:
		# Found existing firebase - activate it with this HQ
		_activate_firebase(owning_firebase)
	elif auto_create_firebase:
		# No firebase found - create one centered on this HQ
		owning_firebase = _create_firebase_for_hq()
		_activate_firebase(owning_firebase)
	else:
		push_warning("[PlacedBuilding] HQ building %s has no firebase and auto_create_firebase is false" % building_data.display_name)


func _create_firebase_for_hq() -> Firebase:
	"""Create a new Firebase centered on this HQ building"""
	var firebase := Firebase.new()
	firebase.name = "Firebase_%s" % name
	firebase.firebase_name = "Firebase %s" % building_data.display_name
	firebase.influence_radius = firebase_influence_radius
	firebase.auto_activate = false  # We'll activate manually below

	# Position at this building's location
	firebase.position = global_position

	# Add to scene tree (parent is this building's parent, not this building)
	get_parent().add_child(firebase)

	print("[PlacedBuilding] Created Firebase at %s for %s" % [global_position, building_data.display_name])
	return firebase


func _activate_firebase(firebase: Firebase) -> void:
	"""Activate firebase with this HQ building"""
	# Always link this HQ to the firebase, even if already active
	if firebase._hq_building == null:
		firebase._hq_building = self
		print("[PlacedBuilding] Linked %s as HQ for %s" % [building_data.display_name if building_data else name, firebase.firebase_name])

	if firebase._is_active:
		# Already active - just make sure we're linked
		if firebase._hq_building != self:
			push_warning("[PlacedBuilding] Firebase %s already has different HQ!" % firebase.firebase_name)
		return

	# Set HQ reference and activate
	firebase._hq_building = self
	firebase._is_active = true
	firebase.influence_radius = building_data.influence_radius if building_data else firebase_influence_radius

	# Emit activation signals
	firebase.firebase_activated.emit(firebase)
	if BattleSignals:
		BattleSignals.firebase_activated.emit(firebase)

	print("[PlacedBuilding] Firebase %s ACTIVATED by %s (radius %.0fm)" % [
		firebase.firebase_name,
		building_data.display_name if building_data else name,
		firebase.influence_radius
	])


func _register_with_firebase(firebase: Firebase) -> void:
	"""Register non-HQ building with owning firebase"""
	if self not in firebase.buildings:
		firebase.buildings.append(self)
		firebase.building_constructed.emit(firebase, self)
		print("[PlacedBuilding] %s registered with %s" % [building_data.display_name, firebase.firebase_name])


## Public API

func get_building_data() -> BuildingData:
	return building_data


func take_damage(amount: float, source: Node3D = null) -> void:
	"""Apply damage to building"""
	# TODO: Implement damage states
	pass


func destroy() -> void:
	"""Destroy this building"""
	if _is_destroyed:
		return

	_is_destroyed = true

	# Remove from firebase
	if owning_firebase:
		owning_firebase.buildings.erase(self)

		# If this was the HQ, deactivate firebase
		if owning_firebase._hq_building == self:
			owning_firebase._deactivate()

	building_destroyed.emit(self)

	# TODO: Play destruction effects, swap to destroyed model
	queue_free()
