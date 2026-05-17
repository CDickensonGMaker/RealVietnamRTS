extends Node
## IntelDirector - Manages fog of war and intelligence
## Tracks what the player knows and how knowledge degrades over time

signal contact_spotted(position: Vector3, contact_type: String)
signal contact_lost(contact_id: int)
signal intel_degraded(contact_id: int)

# Intel entry structure
class IntelContact:
	var id: int
	var position: Vector3
	var contact_type: String  # "infantry", "camp", "mortar", "aa", "tunnel"
	var spotted_time: float
	var last_confirmed: float
	var is_confirmed: bool  # Currently visible
	var threat_level: int  # 1-5

	func _init(p_id: int, p_pos: Vector3, p_type: String, p_time: float):
		id = p_id
		position = p_pos
		contact_type = p_type
		spotted_time = p_time
		last_confirmed = p_time
		is_confirmed = true
		threat_level = _calculate_threat(p_type)

	func _calculate_threat(type: String) -> int:
		match type:
			"camp": return 5
			"mortar": return 4
			"aa": return 4
			"tunnel": return 3
			"infantry": return 2
			_: return 1

# All known contacts
var contacts: Dictionary = {}  # id -> IntelContact
var next_contact_id: int = 0

# Intel degradation settings
var intel_stale_time: float = 120.0  # 2 minutes until intel becomes stale
var intel_expire_time: float = 300.0  # 5 minutes until intel is removed

# Fog of war grid
var fog_resolution: float = 2.0  # Meters per fog cell
var explored_cells: Dictionary = {}  # Vector2i -> bool
var visible_cells: Dictionary = {}  # Vector2i -> bool (currently visible)


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	_update_intel_degradation()


func _update_intel_degradation() -> void:
	var current_time: float = GameManager.game_time
	var to_remove: Array[int] = []

	for contact_id in contacts:
		var contact: IntelContact = contacts[contact_id]

		if not contact.is_confirmed:
			var time_since_confirmed: float = current_time - contact.last_confirmed

			# Check if intel has expired
			if time_since_confirmed >= intel_expire_time:
				to_remove.append(contact_id)
			# Check if intel is stale
			elif time_since_confirmed >= intel_stale_time:
				intel_degraded.emit(contact_id)

	# Remove expired contacts
	for contact_id in to_remove:
		contacts.erase(contact_id)
		contact_lost.emit(contact_id)


func report_contact(position: Vector3, contact_type: String) -> int:
	## Called when a unit spots something. Returns contact ID.
	var contact := IntelContact.new(next_contact_id, position, contact_type, GameManager.game_time)
	contacts[next_contact_id] = contact
	contact_spotted.emit(position, contact_type)
	next_contact_id += 1
	return contact.id


func confirm_contact(contact_id: int, new_position: Vector3 = Vector3.ZERO) -> void:
	## Called when a contact is re-sighted
	if contact_id in contacts:
		var contact: IntelContact = contacts[contact_id]
		contact.is_confirmed = true
		contact.last_confirmed = GameManager.game_time
		if new_position != Vector3.ZERO:
			contact.position = new_position


func lose_sight(contact_id: int) -> void:
	## Called when a contact leaves line of sight
	if contact_id in contacts:
		contacts[contact_id].is_confirmed = false


func get_contact(contact_id: int) -> IntelContact:
	return contacts.get(contact_id)


func get_all_contacts() -> Array:
	return contacts.values()


func get_contacts_by_type(contact_type: String) -> Array:
	var result: Array = []
	var all_contacts: Array = contacts.values()
	for i: int in range(all_contacts.size()):
		var contact: IntelContact = all_contacts[i]
		if contact.contact_type == contact_type:
			result.append(contact)
	return result


func is_intel_stale(contact_id: int) -> bool:
	if contact_id in contacts:
		var contact: IntelContact = contacts[contact_id]
		if not contact.is_confirmed:
			var time_since: float = GameManager.game_time - contact.last_confirmed
			return time_since >= intel_stale_time
	return false


# Fog of war helpers
func reveal_area(center: Vector3, radius: float) -> void:
	## Mark an area as explored and currently visible
	var cell_radius := int(radius / fog_resolution)
	var center_cell := _world_to_cell(center)

	for x in range(-cell_radius, cell_radius + 1):
		for z in range(-cell_radius, cell_radius + 1):
			var cell := Vector2i(center_cell.x + x, center_cell.y + z)
			if Vector2(x, z).length() <= cell_radius:
				explored_cells[cell] = true
				visible_cells[cell] = true


func clear_visibility() -> void:
	## Called each frame before units re-reveal their vision
	visible_cells.clear()


func is_cell_visible(world_pos: Vector3) -> bool:
	var cell := _world_to_cell(world_pos)
	return visible_cells.get(cell, false)


func is_cell_explored(world_pos: Vector3) -> bool:
	var cell := _world_to_cell(world_pos)
	return explored_cells.get(cell, false)


func _world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(int(pos.x / fog_resolution), int(pos.z / fog_resolution))


func report_enemy_contact(position: Vector3, source: String, confidence: float = 1.0) -> int:
	## Report enemy contact from a specific source (unit, structure, etc.)
	## Confidence affects how long intel remains valid
	return report_contact(position, "infantry")
