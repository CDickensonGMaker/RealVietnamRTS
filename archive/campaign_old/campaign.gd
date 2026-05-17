extends Resource
class_name Campaign
## Campaign - Historical campaign containing multiple missions

@export var campaign_name: String = "Ia Drang Valley"
@export var campaign_description: String = ""
@export var historical_year: int = 1965
@export var campaign_icon: Texture2D

@export var missions: Array[Mission] = []
@export var narrative_events: Array[NarrativeEvent] = []

var current_mission_index: int = 0
var is_complete: bool = false

# =============================================================================
# CAMPAIGN PROGRESSION
# =============================================================================

func get_current_mission() -> Mission:
	if current_mission_index < missions.size():
		return missions[current_mission_index]
	return null

func advance_to_next_mission() -> Mission:
	current_mission_index += 1
	if current_mission_index >= missions.size():
		is_complete = true
		return null
	return get_current_mission()

func get_progress() -> float:
	if missions.is_empty():
		return 0.0
	return float(current_mission_index) / float(missions.size())

# =============================================================================
# CAMPAIGN CREATION
# =============================================================================

static func create_ia_drang() -> Campaign:
	var campaign := Campaign.new()
	campaign.campaign_name = "Ia Drang Valley"
	campaign.campaign_description = "November 1965. The first major battle between US and NVA forces. The 1st Cavalry Division (Airmobile) faces three NVA regiments in the Central Highlands."
	campaign.historical_year = 1965

	# Mission 1: LZ X-Ray
	var xray := Mission.new()
	xray.mission_name = "LZ X-Ray"
	xray.mission_type = Mission.MissionType.FIREBASE_DEFENSE
	xray.briefing = "Establish and hold Landing Zone X-Ray against determined NVA assault. Air Cavalry tactics will be tested to the limit."
	xray.objectives = [
		Mission.Objective.new("establish_lz", "Establish LZ X-Ray", false),
		Mission.Objective.new("hold_24h", "Hold LZ for 24 hours", false),
		Mission.Objective.new("survive", "Maintain combat effectiveness", false),
	]
	xray.optional_objectives = [
		Mission.Objective.new("no_broken_arrow", "Avoid calling Broken Arrow", true),
	]
	campaign.missions.append(xray)

	# Mission 2: Broken Arrow
	var broken_arrow := Mission.new()
	broken_arrow.mission_name = "Broken Arrow"
	broken_arrow.mission_type = Mission.MissionType.LAST_STAND
	broken_arrow.briefing = "NVA forces have surrounded LZ X-Ray. Call in danger close air support and hold until reinforcements arrive. Broken Arrow - all available aircraft."
	broken_arrow.objectives = [
		Mission.Objective.new("survive_assault", "Survive the NVA assault", false),
		Mission.Objective.new("hold_perimeter", "Maintain perimeter integrity", false),
	]
	campaign.missions.append(broken_arrow)

	# Mission 3: LZ Albany
	var albany := Mission.new()
	albany.mission_name = "LZ Albany"
	albany.mission_type = Mission.MissionType.FIGHTING_WITHDRAWAL
	albany.briefing = "March from X-Ray to LZ Albany for extraction. Intelligence suggests NVA forces in the area."
	albany.objectives = [
		Mission.Objective.new("reach_albany", "Reach LZ Albany", false),
		Mission.Objective.new("extract_wounded", "Evacuate all wounded", false),
		Mission.Objective.new("survive_ambush", "Survive NVA ambush", false),
	]
	campaign.missions.append(albany)

	return campaign

static func create_khe_sanh() -> Campaign:
	var campaign := Campaign.new()
	campaign.campaign_name = "Siege of Khe Sanh"
	campaign.campaign_description = "January-April 1968. The 77-day siege of Khe Sanh Combat Base. Hold the firebase against overwhelming NVA forces with air support as your lifeline."
	campaign.historical_year = 1968

	# Mission 1: Establish Defenses
	var establish := Mission.new()
	establish.mission_name = "Prepare for Siege"
	establish.mission_type = Mission.MissionType.BASE_BUILDING
	establish.briefing = "Intelligence indicates a major NVA buildup. Strengthen firebase defenses before the assault begins."
	establish.objectives = [
		Mission.Objective.new("build_bunkers", "Construct 4 reinforced bunkers", false),
		Mission.Objective.new("establish_wire", "Complete perimeter wire", false),
		Mission.Objective.new("stockpile", "Stockpile 500 supplies", false),
	]
	campaign.missions.append(establish)

	# Mission 2: First Assault
	var first_assault := Mission.new()
	first_assault.mission_name = "Opening Barrage"
	first_assault.mission_type = Mission.MissionType.FIREBASE_DEFENSE
	first_assault.briefing = "NVA artillery has opened fire. The siege has begun. Survive the bombardment and repel probing attacks."
	first_assault.objectives = [
		Mission.Objective.new("survive_barrage", "Survive artillery barrage", false),
		Mission.Objective.new("repel_probes", "Repel NVA probing attacks", false),
		Mission.Objective.new("maintain_lz", "Keep at least one LZ operational", false),
	]
	campaign.missions.append(first_assault)

	# Mission 3: Arc Light
	var arc_light := Mission.new()
	arc_light.mission_name = "Arc Light"
	arc_light.mission_type = Mission.MissionType.FIREBASE_DEFENSE
	arc_light.briefing = "B-52 strikes are approved. Coordinate Arc Light missions while defending against ground assaults."
	arc_light.objectives = [
		Mission.Objective.new("direct_arc_light", "Direct 3 successful Arc Light strikes", false),
		Mission.Objective.new("hold_firebase", "Maintain control of firebase", false),
	]
	campaign.missions.append(arc_light)

	# Mission 4: Relief
	var relief := Mission.new()
	relief.mission_name = "Operation Pegasus"
	relief.mission_type = Mission.MissionType.BREAKTHROUGH
	relief.briefing = "Relief forces are approaching. Hold until the 1st Cavalry Division breaks through."
	relief.objectives = [
		Mission.Objective.new("survive_until_relief", "Survive until relief arrives", false),
		Mission.Objective.new("link_up", "Link up with relief forces", false),
	]
	campaign.missions.append(relief)

	return campaign

static func create_tet_hue() -> Campaign:
	var campaign := Campaign.new()
	campaign.campaign_name = "Tet Offensive - Hue"
	campaign.campaign_description = "January-March 1968. The Battle of Hue. Retake the ancient imperial city from NVA and VC forces in brutal urban combat."
	campaign.historical_year = 1968

	# Mission 1: MACV Compound
	var macv := Mission.new()
	macv.mission_name = "MACV Compound"
	macv.mission_type = Mission.MissionType.FIREBASE_DEFENSE
	macv.briefing = "NVA forces have overrun most of Hue. Hold the MACV compound until reinforcements arrive."
	macv.objectives = [
		Mission.Objective.new("hold_compound", "Defend MACV compound", false),
		Mission.Objective.new("protect_advisors", "Protect US advisors", false),
	]
	campaign.missions.append(macv)

	# Mission 2: Street Fighting
	var street := Mission.new()
	street.mission_name = "Street by Street"
	street.mission_type = Mission.MissionType.SEARCH_AND_DESTROY
	street.briefing = "Clear the modern city south of the Perfume River. House-to-house fighting."
	street.objectives = [
		Mission.Objective.new("clear_blocks", "Clear 6 city blocks", false),
		Mission.Objective.new("secure_bridge", "Secure Nguyen Hoang Bridge", false),
	]
	campaign.missions.append(street)

	# Mission 3: The Citadel
	var citadel := Mission.new()
	citadel.mission_name = "The Citadel"
	citadel.mission_type = Mission.MissionType.ASSAULT
	citadel.briefing = "Assault the ancient Citadel. The NVA flag flies over the Imperial Palace. Take it down."
	citadel.objectives = [
		Mission.Objective.new("breach_walls", "Breach Citadel walls", false),
		Mission.Objective.new("clear_citadel", "Clear Citadel interior", false),
		Mission.Objective.new("capture_flag", "Capture enemy flag position", false),
	]
	campaign.missions.append(citadel)

	return campaign


# =============================================================================
# MISSION CLASS
# =============================================================================

class Mission:
	extends Resource

	enum MissionType {
		FIREBASE_DEFENSE,
		SEARCH_AND_DESTROY,
		ASSAULT,
		LAST_STAND,
		FIGHTING_WITHDRAWAL,
		BASE_BUILDING,
		BREAKTHROUGH,
		RECON,
	}

	class Objective:
		var id: String
		var description: String
		var is_optional: bool
		var is_complete: bool = false

		func _init(obj_id: String = "", desc: String = "", optional: bool = false) -> void:
			id = obj_id
			description = desc
			is_optional = optional

	@export var mission_name: String = ""
	@export var mission_type: MissionType = MissionType.FIREBASE_DEFENSE
	@export var briefing: String = ""
	@export var map_scene: String = ""

	var objectives: Array[Objective] = []
	var optional_objectives: Array[Objective] = []

	var is_started: bool = false
	var is_complete: bool = false
	var is_failed: bool = false

	func start() -> void:
		is_started = true
		BattleSignals.mission_started.emit(mission_name)

	func complete_objective(objective_id: String) -> bool:
		for obj in objectives:
			if obj.id == objective_id:
				obj.is_complete = true
				BattleSignals.mission_objective_complete.emit(objective_id)
				_check_completion()
				return true

		for obj in optional_objectives:
			if obj.id == objective_id:
				obj.is_complete = true
				BattleSignals.mission_objective_complete.emit(objective_id)
				return true

		return false

	func _check_completion() -> void:
		for obj in objectives:
			if not obj.is_complete:
				return

		is_complete = true
		BattleSignals.mission_complete.emit(mission_name, "success")

	func fail(reason: String) -> void:
		is_failed = true
		BattleSignals.mission_failed.emit(mission_name, reason)

	func get_mission_type_name() -> String:
		match mission_type:
			MissionType.FIREBASE_DEFENSE: return "Firebase Defense"
			MissionType.SEARCH_AND_DESTROY: return "Search & Destroy"
			MissionType.ASSAULT: return "Assault"
			MissionType.LAST_STAND: return "Last Stand"
			MissionType.FIGHTING_WITHDRAWAL: return "Fighting Withdrawal"
			MissionType.BASE_BUILDING: return "Base Building"
			MissionType.BREAKTHROUGH: return "Breakthrough"
			MissionType.RECON: return "Reconnaissance"
			_: return "Unknown"


# =============================================================================
# NARRATIVE EVENT CLASS
# =============================================================================

class NarrativeEvent:
	extends Resource

	var event_id: String
	var trigger_mission: int  # Mission index
	var trigger_condition: String  # "start", "end", "objective_X"
	var title: String
	var text: String
	var voice_over: AudioStream
