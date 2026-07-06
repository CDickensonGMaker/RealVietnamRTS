class_name MoraleConstants extends RefCounted
## Morale System Constants for RealVietnamRTS
## Total War-style morale with Vietnam-specific modifiers

# =============================================================================
# MORALE STATE THRESHOLDS (0-100 scale)
# =============================================================================

## STEADY: Unit fights normally, follows orders without hesitation
const STATE_STEADY_MIN: float = 70.0

## WAVERING: Unit shows signs of stress, reduced combat effectiveness
const STATE_WAVERING_MIN: float = 40.0

## SHAKEN: Unit is close to breaking, may refuse some orders
const STATE_SHAKEN_MIN: float = 20.0

## Below SHAKEN_MIN = BROKEN: Unit routes toward nearest firebase
## Below 10 = SHATTERED: Unit ignores orders completely, rogue behavior

const STATE_SHATTERED_MAX: float = 10.0

# =============================================================================
# EVENT MAGNITUDES (one-time morale changes)
# =============================================================================

## Casualty events - per soldier lost
const EVENT_CASUALTY_LIGHT: float = -3.0      # Single casualty
const EVENT_CASUALTY_HEAVY: float = -8.0      # Multiple casualties at once
const EVENT_SQUAD_WIPED_NEARBY: float = -15.0 # Friendly squad destroyed within 50m

## Combat events
const EVENT_KILL_ENEMY: float = 2.0           # Squad kills enemy soldier
const EVENT_DESTROY_VEHICLE: float = 5.0      # Squad destroys enemy vehicle
const EVENT_AMBUSHED: float = -12.0           # Caught in ambush (first contact)
const EVENT_FLANKED: float = -8.0             # Taking fire from multiple directions

## Command events
const EVENT_OFFICER_KILLED: float = -10.0     # Squad leader killed
const EVENT_HQ_DESTROYED: float = -20.0       # Firebase HQ destroyed

## Positive events
const EVENT_REINFORCEMENTS_ARRIVE: float = 8.0  # Friendly reinforcements nearby
const EVENT_AIR_SUPPORT_CALLED: float = 6.0     # Air strike inbound
const EVENT_MEDEVAC_ARRIVES: float = 4.0        # Helicopter evacuating wounded
const EVENT_FIREBASE_CAPTURED: float = 10.0     # Objective completed

## Vietnam-specific events
const EVENT_TUNNEL_BREACH: float = -10.0      # VC emerge from tunnel nearby
const EVENT_BOOBY_TRAP: float = -6.0          # Triggered booby trap
const EVENT_NAPALM_FRIENDLY: float = -8.0     # Friendly napalm too close

# =============================================================================
# CONTINUOUS MODIFIERS (per second while condition active)
# =============================================================================

## Combat stress
const MOD_UNDER_FIRE: float = -0.3            # Taking fire
const MOD_SUPPRESSED: float = -0.5            # Currently suppressed
const MOD_PINNED: float = -0.8                # Heavily suppressed, can't move
const MOD_TAKING_CASUALTIES: float = -1.0     # Lost soldier in last 10 seconds

## Position modifiers
const MOD_IN_COVER: float = 0.1               # Behind hard cover
const MOD_IN_BUNKER: float = 0.3              # Inside fortification
const MOD_EXPOSED: float = -0.2               # No cover in combat
const MOD_FLANKED: float = -0.4               # Enemies on multiple sides

## Support modifiers
const MOD_NEAR_FIREBASE: float = 1.0          # Within firebase influence radius
const MOD_NEAR_HQ: float = 0.5                # Within 30m of HQ building
const MOD_NEARBY_ALLIES: float = 0.3          # Per friendly squad within 30m (max 3)
const MOD_OUTNUMBERED: float = -0.3           # Enemies outnumber friendlies 2:1+

## Resource modifiers (from Phase 2)
const MOD_LOW_AMMO: float = -0.3              # Ammo below 20%
const MOD_LOW_WATER: float = -0.5             # Water below 20%
const MOD_NO_AMMO: float = -1.0               # Completely out of ammo
const MOD_NO_WATER: float = -1.5              # Completely dehydrated

## Vietnam-specific continuous
const MOD_JUNGLE_DENSE: float = -0.1          # In dense jungle (limited visibility)
const MOD_NIGHT_COMBAT: float = -0.2          # Fighting at night without illumination
const MOD_MONSOON: float = -0.1               # Heavy rain reduces morale recovery

# =============================================================================
# SUPPRESSION-MORALE INTEGRATION (Phase 4.3)
# =============================================================================

## Sustained suppression escalation
## After this many seconds of continuous suppression, morale drain increases
const SUPPRESSION_ESCALATION_TIME: float = 5.0

## Additional morale drain per second when suppression has been sustained
const MOD_SUSTAINED_SUPPRESSION: float = -0.3

## Rout chance under high suppression
## When suppression >= PINNED and morale < SHAKEN, roll for forced rout each second
const SUPPRESSION_ROUT_CHECK_INTERVAL: float = 1.0

## Base chance to rout when PINNED with low morale (per check)
const SUPPRESSION_ROUT_CHANCE_BASE: float = 0.05  # 5% per second

## Rout chance increases as morale drops (multiplier per 10 morale below SHAKEN threshold)
const SUPPRESSION_ROUT_CHANCE_PER_10_MORALE: float = 0.03

## Morale recovery when suppression drops significantly
## Triggered when suppression drops by at least this amount
const SUPPRESSION_RELIEF_THRESHOLD: float = 0.3

## Morale boost when suppression drops significantly (relief)
const EVENT_SUPPRESSION_RELIEF: float = 3.0

## Morale penalty for being pinned for extended time (per 10 seconds)
const EVENT_PROLONGED_PINNED: float = -5.0

## Time threshold for prolonged pinned penalty
const PROLONGED_PINNED_THRESHOLD: float = 10.0

# =============================================================================
# TRAINING LEVEL MODIFIERS
# =============================================================================

## Morale resistance multiplier by training level
## Higher training = better morale resistance
const TRAINING_MULTIPLIER: Dictionary = {
	0: 0.7,   # CONSCRIPT - 30% worse morale
	1: 1.0,   # REGULAR - baseline
	2: 1.2,   # VETERAN - 20% better morale
	3: 1.5,   # ELITE - 50% better morale (SOG teams)
}

## Rally speed multiplier by training
const TRAINING_RALLY_MULTIPLIER: Dictionary = {
	0: 0.5,   # CONSCRIPT - rallies slowly
	1: 1.0,   # REGULAR - baseline
	2: 1.5,   # VETERAN - rallies faster
	3: 2.0,   # ELITE - rallies very quickly
}

# =============================================================================
# RALLY SYSTEM
# =============================================================================

## Time in safety before rally begins (seconds)
const RALLY_SAFETY_TIME: float = 5.0

## Morale recovery rate while rallying (per second)
const RALLY_RECOVERY_RATE: float = 3.0

## Minimum morale to begin rallying (can't rally from SHATTERED)
const RALLY_MIN_THRESHOLD: float = 10.0

## Morale target when rallying (stops at WAVERING)
const RALLY_TARGET: float = 50.0

## Distance from enemies considered "safe" for rally (meters)
const RALLY_SAFE_DISTANCE: float = 30.0

## Rally bonus when at firebase
const RALLY_FIREBASE_BONUS: float = 2.0

# =============================================================================
# ROUTING BEHAVIOR
# =============================================================================

## Speed multiplier when routing (fleeing is faster)
const ROUTE_SPEED_MULTIPLIER: float = 1.3

## How long unit ignores orders while BROKEN (seconds)
const ROUTE_IGNORE_ORDERS_TIME: float = 8.0

## Distance to flee before stopping (if no firebase)
const ROUTE_FLEE_DISTANCE: float = 50.0

## Chance to surrender when SHATTERED and surrounded (0-1)
const SURRENDER_CHANCE_BASE: float = 0.1

## Surrender chance increase per second while SHATTERED
const SURRENDER_CHANCE_RATE: float = 0.02

# =============================================================================
# COMBAT EFFECTIVENESS PENALTIES
# =============================================================================

## Accuracy multiplier by morale state
const ACCURACY_BY_STATE: Dictionary = {
	"STEADY": 1.0,
	"WAVERING": 0.85,
	"SHAKEN": 0.6,
	"BROKEN": 0.3,
	"SHATTERED": 0.1,
}

## Rate of fire multiplier by morale state
const ROF_BY_STATE: Dictionary = {
	"STEADY": 1.0,
	"WAVERING": 0.9,
	"SHAKEN": 0.7,
	"BROKEN": 0.4,
	"SHATTERED": 0.2,
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

## Get morale state name from value
static func get_state_name(morale: float) -> String:
	if morale >= STATE_STEADY_MIN:
		return "STEADY"
	elif morale >= STATE_WAVERING_MIN:
		return "WAVERING"
	elif morale >= STATE_SHAKEN_MIN:
		return "SHAKEN"
	elif morale >= STATE_SHATTERED_MAX:
		return "BROKEN"
	else:
		return "SHATTERED"


## Get training multiplier for morale resistance
static func get_training_multiplier(training_level: int) -> float:
	return TRAINING_MULTIPLIER.get(training_level, 1.0) as float


## Get training multiplier for rally speed
static func get_rally_multiplier(training_level: int) -> float:
	return TRAINING_RALLY_MULTIPLIER.get(training_level, 1.0) as float


## Get accuracy penalty for morale state
static func get_accuracy_multiplier(morale: float) -> float:
	var state: String = get_state_name(morale)
	return ACCURACY_BY_STATE.get(state, 1.0) as float


## Get rate of fire penalty for morale state
static func get_rof_multiplier(morale: float) -> float:
	var state: String = get_state_name(morale)
	return ROF_BY_STATE.get(state, 1.0) as float
