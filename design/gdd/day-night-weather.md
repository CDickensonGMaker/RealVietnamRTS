# Day/Night Cycle and Weather System GDD

> **Status**: `[PARKED]` - Post-MVP Feature
> **Last Updated**: 2026-05-21
> **Source Documents**: PRD.md Section 17, GAME_BIBLE.md
> **Pillar**: None (Environmental Enhancement)
> **MVP Status**: Missions use fixed Clear/Overcast weather. Full system parked for post-MVP.

---

## 1. Overview

The Day/Night Cycle and Weather System provides dynamic environmental conditions that affect gameplay through visibility, movement, air operations, morale, and AI behavior. The system models the Central Highlands (Pleiku Province) climate with distinct dry and monsoon seasons.

**Key Design Goals:**
- Create meaningful tactical choices based on time of day and weather
- Provide asymmetric advantage to VC/NVA forces during adverse conditions
- Ground US air superiority during severe weather, creating vulnerability windows
- Enhance atmosphere without overwhelming core gameplay

**Compression Ratio:** 1 real minute = 10-15 game minutes (configurable). A 60-minute mission spans approximately 1-1.5 in-game days.

**Historical Authenticity:** Weather patterns based on actual Pleiku Province climate data. VC/NVA forces historically timed major operations during monsoon storms when US air support was grounded (e.g., Tet Offensive).

---

## 2. Player Fantasy

The sun sets over your firebase as the last convoy arrives. You check supply levels - enough for the night. The weatherman says rain is coming. You know what that means.

In the jungle below, you cannot see them, but they see the lights of your firebase. They have been watching. Waiting for the rain to mask their approach. When the monsoon hits and your Hueys are grounded, they will come.

You reinforce the eastern bunkers. You double the guard. You wait.

The rain begins. Visibility drops to nothing. Radio chatter confirms contacts on the wire. Your mortars fire blind into the darkness. The M60s open up. For the next hour, you fight with what you have on the ground - no air support, no reinforcements, just sandbags and steel against an enemy who chose this moment.

When dawn breaks and the clouds lift, you survey the damage. The perimeter held. Barely. You understand now why firebase defense is about preparation, not reaction. You cannot control the weather, but you can build for it.

---

## 3. Detailed Rules

### 3.1 Time of Day Phases

The day is divided into four phases with distinct gameplay effects:

| Phase | Game Time | Duration (real) | Visibility Modifier | Notes |
|-------|-----------|-----------------|---------------------|-------|
| **Day** | 0600-1800 | ~80 min | 100% | Full operations, US air superiority |
| **Dusk** | 1800-1930 | ~10 min | 75% (-25%) | Transitional, atmospheric |
| **Night** | 1930-0500 | ~64 min | 40% (-60%) | VC/NVA +25% effectiveness |
| **Dawn** | 0500-0600 | ~6 min | 75% (-25%) | Fog chance increased to 50% |

*Note: Real-time durations assume 1:12 compression ratio (1 real minute = 12 game minutes).*

### 3.2 Night Combat Rules

During **Night** phase (1930-0500):

**Visibility Effects:**
- All unit sight ranges reduced by 60%
- Engagement range reduced by 40%
- Accuracy reduced by 20%
- Muzzle flash reveals shooter position for 5 seconds

**VC/NVA Night Bonus (+25% effectiveness):**
- Detection range increased by 25%
- Movement speed penalty from darkness reduced by 50%
- Suppression resistance increased by 25%
- Accuracy penalty reduced by 50%

**US Night Operations:**
- Observation towers provide 40% sight range (vs. 40% base)
- Mortar pits use illumination rounds (area visibility for 30 seconds, 60-second cooldown)
- Flares from 81mm mortars: 150m radius illumination
- Firebase lights provide 50m visibility bubble (but also attract attacks)

### 3.3 Weather Types

Six weather types based on Central Highlands climate:

| Weather | Movement | Visibility | Air Ops | Morale Effect | Special |
|---------|----------|------------|---------|---------------|---------|
| **Clear** | 100% | 100% | Full | Neutral | Baseline conditions |
| **Overcast** | 100% | 90% | 90% effectiveness | Neutral | CAS accuracy -10% |
| **Light Rain** | 90% | 75% | 75% effectiveness | -0.1/sec | Extinguishes fires |
| **Heavy Rain** | 70% | 50% | 50% effectiveness | -0.2/sec | Roads become mud |
| **Monsoon Storm** | 50% | 25% | **Grounded** | -0.5/sec | No helicopter ops, flash floods |
| **Fog** | 80% | 30% | **Grounded** | Neutral | Burns off by 0800 |

### 3.4 Seasonal Weather Distribution

**Campaign Setting: 1969, Central Highlands (Pleiku Province)**

| Season | Months | Clear | Overcast | Light Rain | Heavy Rain | Storm | Fog |
|--------|--------|-------|----------|------------|------------|-------|-----|
| **Dry** | Nov-Apr | 70% | 20% | 10% | 0% | 0% | Dawn only |
| **Monsoon** | May-Oct | 20% | 30% | 30% | 15% | 5% | Rare |

**Fog Rules:**
- Dry season: 30% chance at dawn, burns off by 0800
- Monsoon: 10% chance at dawn
- Valley terrain: +20% fog chance

### 3.5 Weather State Machine

Weather transitions follow a state machine to prevent jarring changes:

```
CLEAR <-> OVERCAST <-> LIGHT_RAIN <-> HEAVY_RAIN <-> MONSOON_STORM
              |
            FOG (dawn only, transitions to CLEAR or OVERCAST)
```

**Transition Rules:**
- Weather changes every 2-4 in-game hours (randomized)
- Cannot skip states (must go Clear -> Overcast -> Light Rain, not Clear -> Heavy Rain)
- Monsoon storms last minimum 1 in-game hour, maximum 3 hours
- Fog always burns off by 0800 game time

### 3.6 Air Operations Weather Restrictions

| Weather | Transport Helicopters | Gunship Support | Fixed-Wing CAS | Medevac |
|---------|----------------------|-----------------|----------------|---------|
| Clear | Full | Full | Full | Full |
| Overcast | Full | Full | -10% accuracy | Full |
| Light Rain | 90% capacity | 75% effectiveness | -25% accuracy | Full |
| Heavy Rain | 50% capacity | 50% effectiveness | **Unavailable** | Emergency only |
| Monsoon Storm | **Grounded** | **Grounded** | **Grounded** | **Grounded** |
| Fog | **Grounded** | **Grounded** | **Grounded** | **Grounded** |

**Grounded:** All air missions auto-abort. Helicopters in flight must land at nearest LZ immediately.

### 3.7 Terrain Weather Interactions

**Mud (Heavy Rain, Monsoon Storm):**
- Unpaved roads: Vehicle speed reduced to 50%
- Off-road: Vehicle speed reduced to 30%
- Wheeled vehicles may become stuck (5% chance per minute off-road)
- Tracked vehicles (M48, M113) unaffected

**Flash Floods (Monsoon Storm):**
- River fords become impassable
- Low-lying areas may flood (defined per map)
- Infantry in flooded areas take continuous morale damage (-1.0/sec)

**Fire Suppression (Light Rain+):**
- Existing fires extinguished over 30 seconds
- New fires cannot start (napalm ineffective in Heavy Rain+)
- Smoke screens disperse 50% faster

---

## 4. Formulas

### 4.1 Time Progression

```gdscript
class_name TimeManager
extends Node

## Time compression ratio (game minutes per real minute)
const TIME_COMPRESSION_RATIO := 12.0  # 1 real min = 12 game min
const MINUTES_PER_DAY := 1440.0  # 24 * 60

## Current game time in minutes since midnight
var game_time_minutes: float = 360.0  # Start at 0600

## Current time phase
var current_phase: TimePhase = TimePhase.DAY

enum TimePhase { DAWN, DAY, DUSK, NIGHT }

func _process(delta: float) -> void:
    var real_minutes: float = delta / 60.0
    var game_minutes_passed: float = real_minutes * TIME_COMPRESSION_RATIO

    game_time_minutes += game_minutes_passed
    if game_time_minutes >= MINUTES_PER_DAY:
        game_time_minutes -= MINUTES_PER_DAY
        _on_new_day()

    _update_time_phase()


func _update_time_phase() -> void:
    var old_phase: TimePhase = current_phase
    var hour: float = game_time_minutes / 60.0

    if hour >= 5.0 and hour < 6.0:
        current_phase = TimePhase.DAWN
    elif hour >= 6.0 and hour < 18.0:
        current_phase = TimePhase.DAY
    elif hour >= 18.0 and hour < 19.5:
        current_phase = TimePhase.DUSK
    else:
        current_phase = TimePhase.NIGHT

    if current_phase != old_phase:
        BattleSignals.time_phase_changed.emit(current_phase)


func get_hour() -> int:
    return int(game_time_minutes / 60.0)


func get_minute() -> int:
    return int(game_time_minutes) % 60


func get_time_string() -> String:
    return "%02d:%02d" % [get_hour(), get_minute()]
```

### 4.2 Visibility Calculation

```gdscript
## Calculate effective visibility multiplier
func get_visibility_multiplier() -> float:
    var base_visibility: float = 1.0

    # Time of day modifier
    match TimeManager.current_phase:
        TimeManager.TimePhase.DAY:
            base_visibility = 1.0
        TimeManager.TimePhase.DUSK:
            base_visibility = 0.75
        TimeManager.TimePhase.NIGHT:
            base_visibility = 0.40
        TimeManager.TimePhase.DAWN:
            base_visibility = 0.75

    # Weather modifier (multiplicative)
    var weather_modifier: float = WeatherSystem.get_visibility_modifier()

    return base_visibility * weather_modifier


## WeatherSystem.get_visibility_modifier()
func get_visibility_modifier() -> float:
    match current_weather:
        WeatherType.CLEAR:
            return 1.0
        WeatherType.OVERCAST:
            return 0.90
        WeatherType.LIGHT_RAIN:
            return 0.75
        WeatherType.HEAVY_RAIN:
            return 0.50
        WeatherType.MONSOON_STORM:
            return 0.25
        WeatherType.FOG:
            return 0.30
    return 1.0


## Apply to unit sight range
func get_effective_sight_range(base_range: float, faction: int) -> float:
    var visibility_mult: float = get_visibility_multiplier()
    var night_bonus: float = 1.0

    # VC/NVA night bonus
    if TimeManager.current_phase == TimeManager.TimePhase.NIGHT:
        if faction == GameEnums.Faction.VC or faction == GameEnums.Faction.NVA:
            night_bonus = 1.25  # +25% detection at night

    return base_range * visibility_mult * night_bonus
```

### 4.3 Weather State Machine

```gdscript
class_name WeatherSystem
extends Node

enum WeatherType { CLEAR, OVERCAST, LIGHT_RAIN, HEAVY_RAIN, MONSOON_STORM, FOG }
enum Season { DRY, MONSOON }

var current_weather: WeatherType = WeatherType.CLEAR
var current_season: Season = Season.DRY
var weather_timer: float = 0.0
var weather_duration: float = 0.0

## Weather transition weights by season [Clear, Overcast, LightRain, HeavyRain, Storm]
const DRY_SEASON_WEIGHTS := [0.70, 0.20, 0.10, 0.0, 0.0]
const MONSOON_SEASON_WEIGHTS := [0.20, 0.30, 0.30, 0.15, 0.05]

## Valid transitions (can only move to adjacent states)
const TRANSITIONS := {
    WeatherType.CLEAR: [WeatherType.OVERCAST],
    WeatherType.OVERCAST: [WeatherType.CLEAR, WeatherType.LIGHT_RAIN, WeatherType.FOG],
    WeatherType.LIGHT_RAIN: [WeatherType.OVERCAST, WeatherType.HEAVY_RAIN],
    WeatherType.HEAVY_RAIN: [WeatherType.LIGHT_RAIN, WeatherType.MONSOON_STORM],
    WeatherType.MONSOON_STORM: [WeatherType.HEAVY_RAIN],
    WeatherType.FOG: [WeatherType.CLEAR, WeatherType.OVERCAST],
}

func _process(delta: float) -> void:
    weather_timer += delta

    # Convert delta to game minutes for duration check
    var game_minutes: float = (delta / 60.0) * TimeManager.TIME_COMPRESSION_RATIO
    weather_duration -= game_minutes

    if weather_duration <= 0.0:
        _transition_weather()

    # Special: Fog burns off at 0800
    if current_weather == WeatherType.FOG and TimeManager.get_hour() >= 8:
        _transition_from_fog()


func _transition_weather() -> void:
    var valid_next: Array = TRANSITIONS[current_weather]

    # Weighted selection based on season target distribution
    var target_weights: Array = DRY_SEASON_WEIGHTS if current_season == Season.DRY else MONSOON_SEASON_WEIGHTS

    var best_next: WeatherType = valid_next[0]
    var best_weight: float = 0.0

    for next_weather: WeatherType in valid_next:
        var weight: float = target_weights[next_weather] * randf()
        if weight > best_weight:
            best_weight = weight
            best_next = next_weather

    _set_weather(best_next)


func _set_weather(weather: WeatherType) -> void:
    var old_weather: WeatherType = current_weather
    current_weather = weather

    # Duration: 2-4 game hours (120-240 game minutes)
    weather_duration = randf_range(120.0, 240.0)

    # Monsoon storms: minimum 1 hour
    if weather == WeatherType.MONSOON_STORM:
        weather_duration = maxf(weather_duration, 60.0)

    BattleSignals.weather_changed.emit(old_weather, current_weather)


func set_season_from_month(month: int) -> void:
    # Dry: Nov (11) - Apr (4), Monsoon: May (5) - Oct (10)
    if month >= 5 and month <= 10:
        current_season = Season.MONSOON
    else:
        current_season = Season.DRY
```

### 4.4 Movement Speed Modifiers

```gdscript
## Get movement speed modifier based on weather and terrain
func get_movement_modifier(unit: Node3D, terrain_type: int) -> float:
    var base_modifier: float = 1.0

    # Weather modifier
    match WeatherSystem.current_weather:
        WeatherSystem.WeatherType.CLEAR:
            base_modifier = 1.0
        WeatherSystem.WeatherType.OVERCAST:
            base_modifier = 1.0
        WeatherSystem.WeatherType.LIGHT_RAIN:
            base_modifier = 0.9
        WeatherSystem.WeatherType.HEAVY_RAIN:
            base_modifier = 0.7
        WeatherSystem.WeatherType.MONSOON_STORM:
            base_modifier = 0.5
        WeatherSystem.WeatherType.FOG:
            base_modifier = 0.8

    # Mud effects on vehicles (Heavy Rain+)
    if unit.is_vehicle and WeatherSystem.current_weather >= WeatherSystem.WeatherType.HEAVY_RAIN:
        if terrain_type == TerrainType.UNPAVED_ROAD:
            base_modifier *= 0.5
        elif terrain_type == TerrainType.OFF_ROAD:
            base_modifier *= 0.3
            # Tracked vehicles less affected
            if unit.is_tracked:
                base_modifier *= 1.5  # Partial recovery

    return base_modifier
```

### 4.5 Air Operations Availability

```gdscript
enum AirMissionType { TRANSPORT, GUNSHIP, CAS, MEDEVAC }

## Check if air mission type is available in current weather
func is_air_mission_available(mission_type: AirMissionType) -> bool:
    var weather: WeatherSystem.WeatherType = WeatherSystem.current_weather

    # Grounded conditions
    if weather == WeatherSystem.WeatherType.MONSOON_STORM:
        return false
    if weather == WeatherSystem.WeatherType.FOG:
        return false

    # CAS unavailable in heavy rain
    if mission_type == AirMissionType.CAS and weather == WeatherSystem.WeatherType.HEAVY_RAIN:
        return false

    return true


## Get effectiveness modifier for air operations
func get_air_effectiveness(mission_type: AirMissionType) -> float:
    var weather: WeatherSystem.WeatherType = WeatherSystem.current_weather

    if not is_air_mission_available(mission_type):
        return 0.0

    match weather:
        WeatherSystem.WeatherType.CLEAR:
            return 1.0
        WeatherSystem.WeatherType.OVERCAST:
            if mission_type == AirMissionType.CAS:
                return 0.9  # -10% accuracy
            return 1.0
        WeatherSystem.WeatherType.LIGHT_RAIN:
            match mission_type:
                AirMissionType.TRANSPORT:
                    return 0.9
                AirMissionType.GUNSHIP:
                    return 0.75
                AirMissionType.CAS:
                    return 0.75
                AirMissionType.MEDEVAC:
                    return 1.0
        WeatherSystem.WeatherType.HEAVY_RAIN:
            match mission_type:
                AirMissionType.TRANSPORT:
                    return 0.5
                AirMissionType.GUNSHIP:
                    return 0.5
                AirMissionType.MEDEVAC:
                    return 0.75  # Emergency only

    return 1.0
```

### 4.6 AI Director Weather Integration

```gdscript
## AI Director weather-based attack timing
func get_attack_probability_modifier() -> float:
    var modifier: float = 1.0

    # Time of day - VC prefer night
    if TimeManager.current_phase == TimeManager.TimePhase.NIGHT:
        modifier *= 1.5  # 50% more likely at night

    # Weather - VC attack more in bad weather
    match WeatherSystem.current_weather:
        WeatherSystem.WeatherType.HEAVY_RAIN:
            modifier *= 1.25  # US air support degraded
        WeatherSystem.WeatherType.MONSOON_STORM:
            modifier *= 2.0   # US air support grounded - prime attack window
        WeatherSystem.WeatherType.FOG:
            modifier *= 1.5   # Infiltration opportunity

    # Combined: Night + Storm = 3x base probability
    return modifier


## Check if conditions favor major assault
func should_launch_major_attack() -> bool:
    var base_threshold: float = 0.15  # 15% base chance per check
    var modified_chance: float = base_threshold * get_attack_probability_modifier()

    # Monsoon storm at night = ideal conditions for VC assault
    if TimeManager.current_phase == TimeManager.TimePhase.NIGHT:
        if WeatherSystem.current_weather == WeatherSystem.WeatherType.MONSOON_STORM:
            modified_chance += 0.3  # +30% absolute bonus

    return randf() < modified_chance
```

### 4.7 Morale Weather Effects

```gdscript
## Get weather-based morale modifier (per second)
func get_weather_morale_modifier() -> float:
    match WeatherSystem.current_weather:
        WeatherSystem.WeatherType.CLEAR:
            return 0.0
        WeatherSystem.WeatherType.OVERCAST:
            return 0.0
        WeatherSystem.WeatherType.LIGHT_RAIN:
            return -0.1
        WeatherSystem.WeatherType.HEAVY_RAIN:
            return -0.2
        WeatherSystem.WeatherType.MONSOON_STORM:
            return -0.5
        WeatherSystem.WeatherType.FOG:
            return 0.0  # Fog is eerie but not demoralizing
    return 0.0
```

---

## 5. Edge Cases

### 5.1 Helicopter In-Flight When Weather Turns

**Scenario:** A Huey is mid-flight when weather changes to Monsoon Storm (grounded conditions).

**Resolution:**
- Helicopter receives immediate "RTB" (return to base) order
- Helicopter attempts to land at nearest available LZ
- If no LZ within range, helicopter enters "emergency landing" mode
- Emergency landing: Land at current position, creates temporary LZ marker
- Cargo/passengers disembark at emergency LZ
- Helicopter cannot take off until weather clears

### 5.2 Fog During Active Combat

**Scenario:** Combat is ongoing when fog rolls in at dawn.

**Resolution:**
- Engaged units maintain contact (they know where enemies are)
- New units entering combat area have fog visibility penalties
- Mortars and artillery continue firing at last known positions
- Auto-defense structures fire at muzzle flashes only
- Fog burns off at 0800, restoring normal visibility gradually over 15 game minutes

### 5.3 Weather Change Mid-Airstrike

**Scenario:** Player calls CAS, but weather degrades to Heavy Rain before aircraft arrives.

**Resolution:**
- If weather is HEAVY_RAIN: CAS is cancelled, cooldown refunded 50%
- If weather is MONSOON_STORM: CAS is cancelled, cooldown refunded 100%
- UI notification: "Air support aborted due to weather"
- Aircraft never enters map (aborts en route)

### 5.4 Monsoon Storm Flooding

**Scenario:** Infantry squad is in a low-lying area when flash flood occurs.

**Resolution:**
- Low-lying areas defined per map with flood zones
- When MONSOON_STORM active for 30+ game minutes, flood zones activate
- Infantry in flood zones: -1.0 morale/sec, movement -70%
- Vehicles in flood zones: Movement -90%, wheeled vehicles stuck until storm ends
- Units receive "MOVE TO HIGH GROUND" auto-suggestion
- Squads do NOT auto-retreat (player must order withdrawal)

### 5.5 Night Attack During Weather Transition

**Scenario:** VC attack begins at night in Heavy Rain, but dawn arrives mid-battle.

**Resolution:**
- Phase transitions apply immediately to visibility
- VC lose night bonus at 0600 (dawn)
- Weather continues independently of time
- Combat effectiveness shifts gradually as visibility improves
- AI Director may signal retreat if conditions become unfavorable

### 5.6 Firebase Lights at Night

**Scenario:** Firebase has lights active, creating visibility bubble.

**Resolution:**
- Firebase lights: 50m visibility radius around each light source
- Lights attract VC attacks: +25% attack probability on lit firebases
- Player can toggle lights off (no visibility bonus, but harder to spot)
- Trade-off: See attackers approaching vs. be seen from distance
- MG nests and towers benefit from lights (can engage within light radius)

### 5.7 Time Pause and Weather

**Scenario:** Player pauses game; how does weather timer behave?

**Resolution:**
- Weather timer pauses with game
- Weather state preserved exactly
- On unpause, weather continues from paused state
- No "catch-up" weather transitions during pause

### 5.8 Mission Start Weather

**Scenario:** Mission starts at specific time with random weather.

**Resolution:**
- Mission defines: start time, season, optional fixed weather
- If no fixed weather: Roll weather based on season weights
- If fixed weather: Use specified weather, duration starts fresh
- MVP: All missions use Clear or Overcast (fixed)

---

## 6. Dependencies

### 6.1 Systems This System Depends On

| System | Dependency Type | Dependency Details |
|--------|-----------------|-------------------|
| **BattleSignals** | Required | `time_phase_changed`, `weather_changed` signals |
| **Combat System** | Required | Visibility affects engagement range, accuracy |
| **Helicopter System** | Required | Weather restricts air operations |
| **Morale System** | Required | Weather affects morale drain rates |
| **AI Director** | Required | Weather influences attack timing decisions |
| **Terrain System** | Required | Flood zones, mud effects on roads |
| **Unit Resources** | Optional | Could affect water consumption (post-MVP) |

### 6.2 Systems That Depend On This System

| System | Dependency Type | Integration Point |
|--------|-----------------|-------------------|
| **Combat System** | Consumer | Calls `get_visibility_multiplier()`, `get_night_effectiveness_bonus()` |
| **Morale System** | Consumer | Calls `get_weather_morale_modifier()` |
| **Helicopter System** | Consumer | Calls `is_air_mission_available()`, `get_air_effectiveness()` |
| **AI Director** | Consumer | Calls `get_attack_probability_modifier()` |
| **Pathfinding** | Consumer | Calls `get_movement_modifier()` for weather/mud effects |
| **Rendering** | Consumer | Time of day affects lighting, weather affects particles |
| **UI/HUD** | Consumer | Displays current time and weather status |

### 6.3 Signal Definitions

```gdscript
# In BattleSignals autoload
signal time_phase_changed(new_phase: int)
signal weather_changed(old_weather: int, new_weather: int)
signal air_operations_grounded()
signal air_operations_resumed()
signal flood_zone_activated(zone_id: int)
signal flood_zone_deactivated(zone_id: int)
```

### 6.4 Autoload Requirements

| Autoload | Required Methods/Properties |
|----------|----------------------------|
| `TimeManager` | `current_phase`, `game_time_minutes`, `get_hour()`, `get_minute()` |
| `WeatherSystem` | `current_weather`, `current_season`, `get_visibility_modifier()` |
| `BattleSignals` | Signal definitions above |

---

## 7. Tuning Knobs

### 7.1 Time Progression

| Parameter | Default | Range | Gameplay Effect |
|-----------|---------|-------|-----------------|
| `TIME_COMPRESSION_RATIO` | 12.0 | 8.0-20.0 | Higher = faster day/night cycle. 12.0 means 60 real min = 12 game hours |
| `DAWN_START_HOUR` | 5.0 | 4.5-5.5 | When dawn phase begins |
| `DAY_START_HOUR` | 6.0 | 5.5-7.0 | When full daylight begins |
| `DUSK_START_HOUR` | 18.0 | 17.0-19.0 | When dusk begins |
| `NIGHT_START_HOUR` | 19.5 | 19.0-20.5 | When full night begins |

### 7.2 Visibility

| Parameter | Default | Range | Gameplay Effect |
|-----------|---------|-------|-----------------|
| `DUSK_VISIBILITY` | 0.75 | 0.6-0.85 | Dusk phase sight range multiplier |
| `NIGHT_VISIBILITY` | 0.40 | 0.25-0.5 | Night phase sight range multiplier |
| `DAWN_VISIBILITY` | 0.75 | 0.6-0.85 | Dawn phase sight range multiplier |
| `FOG_VISIBILITY` | 0.30 | 0.2-0.4 | Fog weather visibility multiplier |
| `STORM_VISIBILITY` | 0.25 | 0.15-0.35 | Monsoon storm visibility multiplier |

### 7.3 VC/NVA Night Bonuses

| Parameter | Default | Range | Gameplay Effect |
|-----------|---------|-------|-----------------|
| `VC_NIGHT_DETECTION_BONUS` | 1.25 | 1.1-1.5 | VC/NVA sight range multiplier at night |
| `VC_NIGHT_ACCURACY_BONUS` | 1.5 | 1.2-2.0 | Reduces VC/NVA night accuracy penalty |
| `VC_NIGHT_SUPPRESSION_RESIST` | 1.25 | 1.1-1.5 | VC/NVA suppression resistance at night |
| `VC_NIGHT_SPEED_PENALTY_REDUCTION` | 0.5 | 0.3-0.7 | How much darkness speed penalty is reduced |

### 7.4 Weather Duration

| Parameter | Default | Range | Gameplay Effect |
|-----------|---------|-------|-----------------|
| `WEATHER_MIN_DURATION_MINUTES` | 120.0 | 60.0-180.0 | Minimum game minutes per weather state |
| `WEATHER_MAX_DURATION_MINUTES` | 240.0 | 180.0-360.0 | Maximum game minutes per weather state |
| `STORM_MIN_DURATION_MINUTES` | 60.0 | 30.0-120.0 | Minimum storm duration |
| `FOG_BURN_OFF_HOUR` | 8 | 7-10 | When fog automatically clears |
| `FOG_BURN_OFF_DURATION_MINUTES` | 15.0 | 5.0-30.0 | How long fog takes to clear |

### 7.5 Movement Effects

| Parameter | Default | Range | Gameplay Effect |
|-----------|---------|-------|-----------------|
| `LIGHT_RAIN_MOVE_MODIFIER` | 0.9 | 0.8-1.0 | Movement speed in light rain |
| `HEAVY_RAIN_MOVE_MODIFIER` | 0.7 | 0.5-0.8 | Movement speed in heavy rain |
| `STORM_MOVE_MODIFIER` | 0.5 | 0.3-0.6 | Movement speed in monsoon storm |
| `MUD_ROAD_VEHICLE_MODIFIER` | 0.5 | 0.3-0.7 | Vehicle speed on muddy roads |
| `MUD_OFFROAD_VEHICLE_MODIFIER` | 0.3 | 0.1-0.5 | Vehicle speed off-road in mud |
| `TRACKED_VEHICLE_MUD_BONUS` | 1.5 | 1.2-2.0 | Tracked vehicles recover this much of mud penalty |

### 7.6 Morale Effects

| Parameter | Default | Range | Gameplay Effect |
|-----------|---------|-------|-----------------|
| `LIGHT_RAIN_MORALE_DRAIN` | -0.1 | -0.05 to -0.2 | Morale/sec in light rain |
| `HEAVY_RAIN_MORALE_DRAIN` | -0.2 | -0.1 to -0.4 | Morale/sec in heavy rain |
| `STORM_MORALE_DRAIN` | -0.5 | -0.3 to -0.8 | Morale/sec in monsoon storm |
| `FLOOD_ZONE_MORALE_DRAIN` | -1.0 | -0.5 to -2.0 | Morale/sec when in flooded area |

### 7.7 AI Director Integration

| Parameter | Default | Range | Gameplay Effect |
|-----------|---------|-------|-----------------|
| `NIGHT_ATTACK_PROBABILITY_MULT` | 1.5 | 1.2-2.0 | VC attack probability multiplier at night |
| `HEAVY_RAIN_ATTACK_PROBABILITY_MULT` | 1.25 | 1.0-1.5 | Attack probability in heavy rain |
| `STORM_ATTACK_PROBABILITY_MULT` | 2.0 | 1.5-3.0 | Attack probability during storm |
| `FOG_ATTACK_PROBABILITY_MULT` | 1.5 | 1.2-2.0 | Attack probability in fog |
| `STORM_NIGHT_ASSAULT_BONUS` | 0.3 | 0.1-0.5 | Flat bonus to major assault chance |

### 7.8 Seasonal Distribution

| Parameter | Default | Range | Gameplay Effect |
|-----------|---------|-------|-----------------|
| `DRY_CLEAR_WEIGHT` | 0.70 | 0.5-0.85 | Clear weather probability in dry season |
| `DRY_OVERCAST_WEIGHT` | 0.20 | 0.1-0.3 | Overcast probability in dry season |
| `DRY_LIGHT_RAIN_WEIGHT` | 0.10 | 0.05-0.2 | Light rain probability in dry season |
| `MONSOON_CLEAR_WEIGHT` | 0.20 | 0.1-0.3 | Clear weather probability in monsoon |
| `MONSOON_STORM_WEIGHT` | 0.05 | 0.02-0.15 | Monsoon storm probability |
| `DAWN_FOG_CHANCE_DRY` | 0.30 | 0.1-0.5 | Fog probability at dawn in dry season |
| `DAWN_FOG_CHANCE_MONSOON` | 0.10 | 0.0-0.2 | Fog probability at dawn in monsoon |
| `VALLEY_FOG_BONUS` | 0.20 | 0.1-0.4 | Additional fog chance in valley terrain |

---

## 8. Acceptance Criteria

### 8.1 Core Time System

- [ ] Game time advances at configurable compression ratio (default 1:12)
- [ ] Time displays in 24-hour format (HH:MM) on HUD
- [ ] Day transitions through four phases: Dawn, Day, Dusk, Night
- [ ] `time_phase_changed` signal fires on each transition
- [ ] Time pauses when game is paused
- [ ] Mission start time is configurable per mission

### 8.2 Visibility System

- [ ] Unit sight range reduces by 25% during Dusk/Dawn
- [ ] Unit sight range reduces by 60% during Night
- [ ] VC/NVA units receive +25% sight range bonus at night
- [ ] Visibility modifiers stack multiplicatively with weather
- [ ] Engagement range scales with visibility

### 8.3 Weather State Machine

- [ ] Weather transitions only between adjacent states
- [ ] Weather changes every 2-4 game hours
- [ ] Season affects weather probability distribution
- [ ] Monsoon storms last minimum 1 game hour
- [ ] Fog burns off automatically at 0800
- [ ] `weather_changed` signal fires on each transition

### 8.4 Weather Gameplay Effects

- [ ] Movement speed reduces based on weather type
- [ ] Mud affects vehicle movement on unpaved surfaces in Heavy Rain+
- [ ] Tracked vehicles are less affected by mud than wheeled
- [ ] Rain extinguishes fires within 30 seconds
- [ ] Flood zones activate during extended Monsoon Storms

### 8.5 Air Operations

- [ ] Helicopters are grounded during Monsoon Storm and Fog
- [ ] In-flight helicopters emergency land when weather grounds them
- [ ] CAS is unavailable during Heavy Rain
- [ ] Air effectiveness degrades proportionally to weather severity
- [ ] `air_operations_grounded` signal fires when conditions prevent flying
- [ ] Cancelled air missions refund appropriate cooldown

### 8.6 Morale Integration

- [ ] Weather applies morale modifier per second
- [ ] Light Rain: -0.1/sec, Heavy Rain: -0.2/sec, Storm: -0.5/sec
- [ ] Flood zone applies -1.0/sec additional morale drain
- [ ] Weather morale effects stack with other morale modifiers

### 8.7 AI Director Integration

- [ ] AI Director increases attack probability at night (+50%)
- [ ] AI Director increases attack probability in bad weather
- [ ] Night + Storm combination triggers assault consideration
- [ ] AI Director signals retreat when conditions become unfavorable

### 8.8 Visual Feedback (Post-MVP)

- [ ] Lighting changes to reflect time of day
- [ ] Rain particle effects visible during rain weather
- [ ] Fog volumetric effect during fog conditions
- [ ] Puddles/mud visual on terrain during Heavy Rain+
- [ ] UI weather indicator shows current weather and forecast

### 8.9 Performance

- [ ] Weather/time updates occur at fixed intervals (not every frame)
- [ ] Visibility calculations are cached and updated on phase/weather change
- [ ] No per-frame allocations in weather system
- [ ] System adds less than 0.1ms to frame time

### 8.10 Balance Verification

- [ ] US player can still win missions during monsoon season
- [ ] Night attacks are challenging but survivable with proper defenses
- [ ] Weather creates meaningful tactical decisions without feeling unfair
- [ ] Firebase lights provide useful trade-off decision
- [ ] AI Director does not spam attacks during every storm

---

## Historical Reference

### Central Highlands Climate (Pleiku Province, 1969)

**Annual Rainfall:** ~2,228mm (87.7 inches)
**Temperature Range:** 22-33C (72-91F)
**Altitude:** ~750 meters (2,450 feet)

**Monthly Breakdown:**
| Month | Rainfall (mm) | Avg Temp (C) | Conditions |
|-------|---------------|--------------|------------|
| January | 9 | 20-27 | Dry, clear, cool nights |
| February | 15 | 21-28 | Dry, warming |
| March | 40 | 22-32 | Hot, occasional showers |
| April | 80 | 23-33 | Hottest, humid |
| May | 180 | 23-31 | Monsoon begins |
| June | 220 | 22-29 | Heavy daily rain |
| July | 240 | 22-28 | Sustained rain |
| August | 280 | 22-28 | Heavy rain, flooding |
| September | 390 | 22-28 | Peak rainfall |
| October | 250 | 22-28 | Rains tapering |
| November | 100 | 21-27 | Transitional |
| December | 25 | 20-26 | Dry season begins |

### Historical Tactical Implications

**VC/NVA Weather Exploitation:**
- Tet Offensive (January 1968): Timed during poor weather period
- Major attacks frequently coincided with monsoon storms
- Night attacks were standard VC/NVA doctrine
- Fog and rain used for infiltration and tunnel operations

**US Weather Limitations:**
- Air superiority was the US primary advantage
- Grounded aircraft meant no CAS, no medevac, no air resupply
- Wet season operations were significantly more difficult
- Mud affected vehicle mobility, especially wheeled transport

---

## MVP Implementation Notes

**Current Status:** This system is **parked for post-MVP**.

**MVP Behavior:**
- All missions use fixed weather: Clear or Overcast
- Time of day is fixed at mission start (typically 0600)
- No weather transitions during mission
- No day/night cycle during mission
- AI Director ignores weather/time in attack calculations

**Post-MVP Integration Order:**
1. Implement TimeManager with day/night cycle
2. Add visibility effects (sight range reduction at night)
3. Implement WeatherSystem state machine
4. Add movement/morale weather effects
5. Integrate with Helicopter System (grounding)
6. Integrate with AI Director (attack timing)
7. Add visual effects (lighting, particles, fog volumes)
8. Historical weather data for specific 1969 dates (optional)

---

*End of Document*
