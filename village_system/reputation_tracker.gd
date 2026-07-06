class_name ReputationTracker extends Node
## Reputation Tracker - Hearts and Minds system.
## Tracks player reputation across all villages and with MACV (command).
## Actions have consequences - civilian casualties cost dearly.
##
## Serves Pillar 2 indirectly - reputation affects village cooperation,
## intelligence quality, and VC recruitment from the population.

signal reputation_changed(total: float, delta: float, reason: String)
signal village_flipped(village: Node3D, to_allegiance: int)
signal war_crime_committed(incident_type: int, position: Vector3)
signal commendation_earned(commendation: String)
signal medal_awarded(medal: String)
signal court_martial_warning()
signal game_over_war_crimes()

enum IncidentType {
	CIVILIAN_KILLED,
	VILLAGE_DESTROYED,
	HOSPITAL_ATTACKED,
	MEDEVAC_DESTROYED,
	SURRENDERED_KILLED,
	FRIENDLY_FIRE,
	EXCESSIVE_FORCE,  # Using heavy weapons in villages
}

enum CommendationType {
	VILLAGE_SECURED,
	MEDICAL_AID,
	FOOD_DISTRIBUTION,
	INFRASTRUCTURE_BUILT,
	ENEMY_DEFEATED,
	FIREBASE_ESTABLISHED,
}

## Reputation scale: -100 (war criminal) to +100 (beloved liberator)
## 0 = neutral
var total_reputation: float = 0.0
var macv_standing: float = 50.0  # Command's opinion, affects reinforcements

## Tracking
var civilian_casualties: int = 0
var villages_destroyed: int = 0
var villages_secured: int = 0
var aid_delivered: float = 0.0
var enemies_killed: int = 0

## Thresholds
const REPUTATION_MIN: float = -100.0
const REPUTATION_MAX: float = 100.0
const WAR_CRIME_THRESHOLD: float = -50.0  # Below this triggers consequences
const COURT_MARTIAL_THRESHOLD: float = -75.0  # Game over territory

## Incident costs
const INCIDENT_COSTS: Dictionary = {
	IncidentType.CIVILIAN_KILLED: -15.0,
	IncidentType.VILLAGE_DESTROYED: -30.0,
	IncidentType.HOSPITAL_ATTACKED: -25.0,
	IncidentType.MEDEVAC_DESTROYED: -20.0,
	IncidentType.SURRENDERED_KILLED: -20.0,
	IncidentType.FRIENDLY_FIRE: -10.0,
	IncidentType.EXCESSIVE_FORCE: -5.0,
}

## Commendation values
const COMMENDATION_VALUES: Dictionary = {
	CommendationType.VILLAGE_SECURED: 10.0,
	CommendationType.MEDICAL_AID: 3.0,
	CommendationType.FOOD_DISTRIBUTION: 2.0,
	CommendationType.INFRASTRUCTURE_BUILT: 5.0,
	CommendationType.ENEMY_DEFEATED: 1.0,
	CommendationType.FIREBASE_ESTABLISHED: 8.0,
}

## Medal thresholds
var _medals_earned: Array[String] = []
const MEDAL_THRESHOLDS: Dictionary = {
	"Bronze Star": 25.0,
	"Silver Star": 50.0,
	"Distinguished Service Cross": 75.0,
	"Medal of Honor": 95.0,
}


func _ready() -> void:
	# Connect to battle signals
	if BattleSignals:
		BattleSignals.civilian_casualty.connect(_on_civilian_casualty)
		BattleSignals.village_allegiance_changed.connect(_on_village_allegiance_changed)
		BattleSignals.unit_died.connect(_on_unit_died)


func _on_civilian_casualty(village: Node3D, killer: Node3D) -> void:
	if not killer:
		return

	# Only penalize player for their kills
	if killer.is_in_group("player_units"):
		report_incident(IncidentType.CIVILIAN_KILLED, killer.global_position)
		civilian_casualties += 1

		# Additional penalty if in village
		if village:
			_apply_village_penalty(village, 0.15)


func _on_village_allegiance_changed(village: Node3D, new_allegiance: int) -> void:
	village_flipped.emit(village, new_allegiance)

	# Track secured villages
	if new_allegiance == 1:  # PRO_US
		villages_secured += 1
		award_commendation(CommendationType.VILLAGE_SECURED)


func _on_unit_died(unit: Node3D, killer: Node3D) -> void:
	if not is_instance_valid(killer):
		return

	# Track enemy kills for reputation
	if unit.is_in_group("enemy_units") and killer.is_in_group("player_units"):
		enemies_killed += 1
		# Small reputation gain for combat success
		if enemies_killed % 10 == 0:
			award_commendation(CommendationType.ENEMY_DEFEATED)

	# Check for friendly fire
	if unit.is_in_group("player_units") and killer.is_in_group("player_units"):
		report_incident(IncidentType.FRIENDLY_FIRE, unit.global_position)


# =============================================================================
# PUBLIC API
# =============================================================================

func report_incident(incident_type: int, position: Vector3) -> void:
	var cost: float = INCIDENT_COSTS.get(incident_type, -5.0)
	_change_reputation(cost, "Incident: %s" % IncidentType.keys()[incident_type])

	# MACV standing also drops
	macv_standing = maxf(macv_standing + cost * 0.5, 0.0)

	war_crime_committed.emit(incident_type, position)

	# Emit to central signal bus
	if BattleSignals:
		BattleSignals.war_crime_committed.emit(incident_type, position)

	# Check thresholds
	_check_war_crime_status()


func award_commendation(commendation_type: int) -> void:
	var value: float = COMMENDATION_VALUES.get(commendation_type, 1.0)
	_change_reputation(value, "Commendation: %s" % CommendationType.keys()[commendation_type])

	macv_standing = minf(macv_standing + value * 0.3, 100.0)

	commendation_earned.emit(CommendationType.keys()[commendation_type])

	# Check for medals
	_check_medals()


func deliver_aid(village: Node3D, amount: float) -> void:
	aid_delivered += amount

	# Reputation gain based on amount
	var rep_gain: float = clampf(amount / 100.0, 0.5, 5.0)
	_change_reputation(rep_gain, "Aid delivered to %s" % (village.name if village else "village"))

	# Direct village trust increase
	if village and village.has_method("deliver_aid"):
		village.deliver_aid(amount)


func establish_firebase(firebase: Node3D) -> void:
	award_commendation(CommendationType.FIREBASE_ESTABLISHED)

	# Nearby villages become slightly more pro-US
	var nearby_villages: Array[Node] = get_tree().get_nodes_in_group("villages")
	for village in nearby_villages:
		var dist: float = firebase.global_position.distance_to(village.global_position)
		if dist < 500.0:
			_apply_village_bonus(village, 0.1 * (1.0 - dist / 500.0))


func report_excessive_force(position: Vector3) -> void:
	# Called when using heavy weapons (artillery, napalm) near civilians
	report_incident(IncidentType.EXCESSIVE_FORCE, position)


func _change_reputation(delta: float, reason: String) -> void:
	var old_rep: float = total_reputation
	total_reputation = clampf(total_reputation + delta, REPUTATION_MIN, REPUTATION_MAX)

	if total_reputation != old_rep:
		reputation_changed.emit(total_reputation, delta, reason)
		print("[ReputationTracker] %s: %.1f (%+.1f)" % [reason, total_reputation, delta])

		# Emit to central signal bus
		if BattleSignals:
			BattleSignals.reputation_changed.emit(total_reputation, delta, reason)


func _apply_village_penalty(village: Node3D, amount: float) -> void:
	if village.has_method("get") and village.get("us_influence"):
		village.us_influence = maxf(village.us_influence - amount, 0.0)
	if village.has_method("get") and village.get("vc_presence"):
		village.vc_presence = minf(village.vc_presence + amount * 0.5, 1.0)


func _apply_village_bonus(village: Node3D, amount: float) -> void:
	if village.has_method("get") and village.get("us_influence"):
		village.us_influence = minf(village.us_influence + amount, 1.0)


func _check_war_crime_status() -> void:
	if total_reputation <= COURT_MARTIAL_THRESHOLD:
		game_over_war_crimes.emit()
		print("[ReputationTracker] GAME OVER: Court martial for war crimes")
	elif total_reputation <= WAR_CRIME_THRESHOLD:
		court_martial_warning.emit()
		print("[ReputationTracker] WARNING: War crime investigation pending")


func _check_medals() -> void:
	for medal_name in MEDAL_THRESHOLDS.keys():
		if medal_name in _medals_earned:
			continue
		var threshold: float = MEDAL_THRESHOLDS[medal_name]
		if total_reputation >= threshold:
			_medals_earned.append(medal_name)
			medal_awarded.emit(medal_name)
			print("[ReputationTracker] Medal awarded: %s" % medal_name)

			# Emit to central signal bus
			if BattleSignals:
				BattleSignals.medal_awarded.emit(medal_name)


## Get reputation effect on various game systems
func get_reinforcement_modifier() -> float:
	# Low MACV standing = slower reinforcements
	return clampf(macv_standing / 50.0, 0.5, 1.5)


func get_air_support_modifier() -> float:
	# Very low reputation = no air support
	if total_reputation < -30.0:
		return 0.0
	return clampf((total_reputation + 50.0) / 100.0, 0.3, 1.2)


func get_intel_quality() -> float:
	# Reputation affects intel from civilians
	return clampf((total_reputation + 50.0) / 100.0, 0.1, 1.0)


func get_vc_recruitment_modifier() -> float:
	# Low reputation = VC recruits more easily
	return clampf(1.0 - (total_reputation / 100.0), 0.5, 2.0)


func get_village_cooperation() -> float:
	# How willing villages are to cooperate
	return clampf((total_reputation + 50.0) / 100.0, 0.0, 1.0)


## Statistics
func get_statistics() -> Dictionary:
	return {
		"reputation": total_reputation,
		"macv_standing": macv_standing,
		"civilian_casualties": civilian_casualties,
		"villages_destroyed": villages_destroyed,
		"villages_secured": villages_secured,
		"aid_delivered": aid_delivered,
		"enemies_killed": enemies_killed,
		"medals": _medals_earned.duplicate(),
	}


func get_reputation_level() -> String:
	if total_reputation >= 75.0:
		return "Beloved Liberator"
	elif total_reputation >= 50.0:
		return "Respected Ally"
	elif total_reputation >= 25.0:
		return "Trusted"
	elif total_reputation >= 0.0:
		return "Neutral"
	elif total_reputation >= -25.0:
		return "Distrusted"
	elif total_reputation >= -50.0:
		return "Feared"
	elif total_reputation >= -75.0:
		return "Hated"
	else:
		return "War Criminal"


func is_war_criminal() -> bool:
	return total_reputation <= WAR_CRIME_THRESHOLD


func is_court_martial_pending() -> bool:
	return total_reputation <= COURT_MARTIAL_THRESHOLD
