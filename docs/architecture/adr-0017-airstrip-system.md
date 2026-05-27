# ADR-0017: Airstrip System

## Status
Proposed

## Context

Airstrips in RealVietnamRTS are pre-placed map features that provide fixed-wing air support and high-capacity supply delivery. Unlike firebases which players build, airstrips exist on the map and must be captured or defended. This creates strategic control points that affect supply lines and air support availability.

### Requirements to Address
| TR-ID | Requirement |
|-------|-------------|
| TR-SYS-080 | Airstrips are map features, not buildings - captured or start controlled |
| TR-SYS-081 | Lost airstrip = no fixed-wing supply or air strikes from that base |
| TR-SYS-082 | VC sappers can crater runways, grounding aircraft until engineer repair |
| TR-SYS-083 | Runway crater repair is an engineer task with specific build time |

## Decision

### Airstrip Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                      AirstripManager                                │
│                      (Autoload Singleton)                           │
├─────────────────────────────────────────────────────────────────────┤
│  + register_airstrip(airstrip: Airstrip) -> void                    │
│  + get_airstrip_for_faction(faction) -> Airstrip                    │
│  + is_runway_operational(airstrip_id) -> bool                       │
│  + request_air_support(type, target, faction) -> AirMission         │
│  + request_supply_flight(destination, faction) -> SupplyFlight      │
├─────────────────────────────────────────────────────────────────────┤
│  Signals: airstrip_captured, airstrip_lost, runway_cratered,        │
│           runway_repaired, air_support_available                    │
└─────────────────────────────────────────────────────────────────────┘
          ▲
          │ manages
          │
┌─────────────────────────────────────────────────────────────────────┐
│                         Airstrip (Node3D)                           │
├─────────────────────────────────────────────────────────────────────┤
│  + airstrip_id: String                                              │
│  + controlling_faction: GameEnums.Faction                           │
│  + runway_state: RunwayState (OPERATIONAL, CRATERED, UNDER_REPAIR)  │
│  + aircraft_capacity: int                                           │
│  + available_aircraft: Dictionary                                   │
│  + capture_progress: float                                          │
├─────────────────────────────────────────────────────────────────────┤
│  + capture_zone: Area3D                                             │
│  + runway_collision: StaticBody3D                                   │
│  + crater_positions: Array[Vector3]                                 │
└─────────────────────────────────────────────────────────────────────┘
```

### Airstrip as Map Feature (TR-SYS-080)

```gdscript
## airstrip.gd - Map feature, not player-built

class_name Airstrip extends Node3D

enum RunwayState {
    OPERATIONAL,     # Aircraft can land/takeoff
    CRATERED,        # Damaged, unusable
    UNDER_REPAIR,    # Being repaired by engineers
}

@export var airstrip_id: String
@export var starting_faction: GameEnums.Faction = GameEnums.Faction.US_ARMY
@export var aircraft_capacity: int = 4
@export var runway_length: float = 300.0  # meters
@export var runway_width: float = 30.0

## Current state
var controlling_faction: GameEnums.Faction
var runway_state: RunwayState = RunwayState.OPERATIONAL
var capture_progress: float = 0.0

## Crater tracking
var crater_positions: Array[Vector3] = []
const CRATERS_TO_DISABLE := 3  # 3 craters = runway unusable

## Aircraft on station
var available_aircraft: Dictionary = {
    "c130_hercules": 2,    # Supply transport
    "skyraider": 2,        # Close air support
    "phantom": 0,          # Fast mover (doctrine-dependent)
}

@onready var capture_zone: Area3D = $CaptureZone
@onready var runway_mesh: MeshInstance3D = $RunwayMesh
@onready var control_tower: Node3D = $ControlTower

func _ready() -> void:
    controlling_faction = starting_faction
    AirstripManager.register_airstrip(self)

    capture_zone.body_entered.connect(_on_body_entered_capture_zone)
    capture_zone.body_exited.connect(_on_body_exited_capture_zone)

    BattleSignals.explosion_occurred.connect(_on_explosion)
```

### Capture Mechanics (TR-SYS-080)

```gdscript
## Airstrip capture - control via presence

var _units_in_zone: Dictionary = {}  # faction -> count

func _on_body_entered_capture_zone(body: Node3D) -> void:
    if not body.has_method("get_faction"):
        return

    var faction: GameEnums.Faction = body.get_faction()
    _units_in_zone[faction] = _units_in_zone.get(faction, 0) + 1

func _on_body_exited_capture_zone(body: Node3D) -> void:
    if not body.has_method("get_faction"):
        return

    var faction: GameEnums.Faction = body.get_faction()
    _units_in_zone[faction] = maxi(0, _units_in_zone.get(faction, 0) - 1)

func _process(delta: float) -> void:
    _process_capture(delta)

func _process_capture(delta: float) -> void:
    var us_count: int = _units_in_zone.get(GameEnums.Faction.US_ARMY, 0)
    var vc_count: int = _units_in_zone.get(GameEnums.Faction.VC, 0)

    # Contested - no capture progress
    if us_count > 0 and vc_count > 0:
        return

    var dominant_faction: GameEnums.Faction = GameEnums.Faction.NEUTRAL
    if us_count > vc_count:
        dominant_faction = GameEnums.Faction.US_ARMY
    elif vc_count > us_count:
        dominant_faction = GameEnums.Faction.VC

    if dominant_faction == GameEnums.Faction.NEUTRAL:
        return

    # Same faction as controller - no change
    if dominant_faction == controlling_faction:
        capture_progress = 0.0
        return

    # Enemy capturing
    var capture_rate := 0.1 * (us_count + vc_count)  # Faster with more units
    capture_progress += capture_rate * delta

    if capture_progress >= 1.0:
        _change_control(dominant_faction)

func _change_control(new_faction: GameEnums.Faction) -> void:
    var old_faction := controlling_faction
    controlling_faction = new_faction
    capture_progress = 0.0

    # Emit signals
    if old_faction != GameEnums.Faction.NEUTRAL:
        BattleSignals.airstrip_lost.emit(self, old_faction)
    BattleSignals.airstrip_captured.emit(self, new_faction)

    # Update visual control indicators
    _update_control_visuals()
```

### Air Support Availability (TR-SYS-081)

```gdscript
## AirstripManager.gd - Air support availability

class_name AirstripManager extends Node

var _airstrips: Dictionary = {}  # airstrip_id -> Airstrip

func register_airstrip(airstrip: Airstrip) -> void:
    _airstrips[airstrip.airstrip_id] = airstrip

## Get operational airstrip for faction
func get_airstrip_for_faction(faction: GameEnums.Faction) -> Airstrip:
    for airstrip in _airstrips.values():
        if airstrip.controlling_faction == faction:
            if airstrip.runway_state == RunwayState.OPERATIONAL:
                return airstrip
    return null

## Check if faction has air support available (TR-SYS-081)
func has_air_support(faction: GameEnums.Faction) -> bool:
    var airstrip := get_airstrip_for_faction(faction)
    if not airstrip:
        return false

    # Check runway is operational
    if airstrip.runway_state != RunwayState.OPERATIONAL:
        return false

    # Check aircraft available
    for aircraft_type in airstrip.available_aircraft.keys():
        if airstrip.available_aircraft[aircraft_type] > 0:
            return true

    return false

## Request air support mission (TR-SYS-081)
func request_air_support(
    support_type: AirSupportType,
    target_position: Vector3,
    faction: GameEnums.Faction
) -> AirMission:

    var airstrip := get_airstrip_for_faction(faction)
    if not airstrip:
        BattleSignals.air_support_unavailable.emit(faction, "No airstrip controlled")
        return null

    if airstrip.runway_state != RunwayState.OPERATIONAL:
        BattleSignals.air_support_unavailable.emit(faction, "Runway cratered")
        return null

    # Check aircraft availability
    var required_aircraft := _get_aircraft_for_support(support_type)
    if airstrip.available_aircraft.get(required_aircraft, 0) <= 0:
        BattleSignals.air_support_unavailable.emit(faction, "No aircraft available")
        return null

    # Reserve aircraft
    airstrip.available_aircraft[required_aircraft] -= 1

    # Create mission
    var mission := AirMission.new()
    mission.mission_type = support_type
    mission.origin_airstrip = airstrip
    mission.target_position = target_position
    mission.aircraft_type = required_aircraft
    mission.state = MissionState.LAUNCHING

    # Calculate ETA based on distance
    mission.eta = _calculate_air_eta(airstrip.global_position, target_position)

    _active_missions.append(mission)
    BattleSignals.air_support_launching.emit(mission)

    return mission

func _get_aircraft_for_support(support_type: AirSupportType) -> String:
    match support_type:
        AirSupportType.SUPPLY_DROP:
            return "c130_hercules"
        AirSupportType.NAPALM:
            return "skyraider"
        AirSupportType.FAST_MOVER:
            return "phantom"
        _:
            return "skyraider"

## Supply flights depend on airstrip control (TR-SYS-081)
func request_supply_flight(
    destination: Node3D,
    faction: GameEnums.Faction
) -> SupplyFlight:

    var airstrip := get_airstrip_for_faction(faction)
    if not airstrip:
        BattleSignals.supply_flight_unavailable.emit(faction, "No airstrip")
        return null

    if airstrip.runway_state != RunwayState.OPERATIONAL:
        BattleSignals.supply_flight_unavailable.emit(faction, "Runway cratered")
        return null

    if airstrip.available_aircraft.get("c130_hercules", 0) <= 0:
        BattleSignals.supply_flight_unavailable.emit(faction, "No C-130 available")
        return null

    # Reserve aircraft
    airstrip.available_aircraft["c130_hercules"] -= 1

    var flight := SupplyFlight.new()
    flight.origin = airstrip
    flight.destination = destination
    flight.cargo_capacity = 500  # Supply units
    flight.state = FlightState.LOADING

    _active_supply_flights.append(flight)
    return flight
```

### Runway Cratering (TR-SYS-082)

```gdscript
## airstrip.gd - Crater damage from explosions

func _on_explosion(position: Vector3, radius: float, damage_type: DamageType) -> void:
    # Only explosives can crater runways
    if damage_type != DamageType.EXPLOSIVE:
        return

    # Check if explosion is on runway
    var local_pos := to_local(position)
    if not _is_on_runway(local_pos):
        return

    # Large explosions (sapper charges, bombs) crater the runway
    if radius < 5.0:
        return

    # Add crater
    _add_crater(position)

func _is_on_runway(local_pos: Vector3) -> bool:
    # Runway is along local Z axis
    return (absf(local_pos.x) < runway_width / 2.0 and
            absf(local_pos.z) < runway_length / 2.0)

func _add_crater(position: Vector3) -> void:
    crater_positions.append(position)

    # Spawn crater visual
    var crater_visual := preload("res://effects/runway_crater.tscn").instantiate()
    crater_visual.global_position = position
    add_child(crater_visual)

    # Check if runway disabled (TR-SYS-082)
    if crater_positions.size() >= CRATERS_TO_DISABLE:
        if runway_state == RunwayState.OPERATIONAL:
            runway_state = RunwayState.CRATERED
            BattleSignals.runway_cratered.emit(self)

            # Cancel any in-flight missions to this airstrip
            AirstripManager.cancel_missions_to(self)

            # Audio/visual feedback
            AudioManager.play_voice(controlling_faction, "runway_cratered")
```

### Runway Repair (TR-SYS-083)

```gdscript
## airstrip.gd - Engineer repair capability

const REPAIR_TIME_PER_CRATER := 60.0  # 1 minute per crater
var _repair_progress: float = 0.0
var _repairing_engineers: Array[Node3D] = []

func start_repair(engineer: Node3D) -> bool:
    if runway_state != RunwayState.CRATERED:
        return false

    if engineer in _repairing_engineers:
        return false

    _repairing_engineers.append(engineer)

    if runway_state == RunwayState.CRATERED:
        runway_state = RunwayState.UNDER_REPAIR
        BattleSignals.runway_repair_started.emit(self)

    return true

func stop_repair(engineer: Node3D) -> void:
    _repairing_engineers.erase(engineer)

    # If no engineers, pause repair
    if _repairing_engineers.is_empty() and runway_state == RunwayState.UNDER_REPAIR:
        # Don't reset progress, just pause
        pass

func _process(delta: float) -> void:
    _process_capture(delta)
    _process_repair(delta)

func _process_repair(delta: float) -> void:
    if runway_state != RunwayState.UNDER_REPAIR:
        return

    if _repairing_engineers.is_empty():
        return

    # More engineers = faster repair (diminishing returns)
    var repair_speed := 1.0 + 0.25 * (_repairing_engineers.size() - 1)
    var total_repair_time := crater_positions.size() * REPAIR_TIME_PER_CRATER

    _repair_progress += (delta / total_repair_time) * repair_speed

    BattleSignals.runway_repair_progress.emit(self, _repair_progress)

    if _repair_progress >= 1.0:
        _complete_repair()

func _complete_repair() -> void:
    runway_state = RunwayState.OPERATIONAL
    _repair_progress = 0.0

    # Remove crater visuals
    for child in get_children():
        if child.name.begins_with("RunwayCrater"):
            child.queue_free()

    crater_positions.clear()
    _repairing_engineers.clear()

    BattleSignals.runway_repaired.emit(self)
    AudioManager.play_voice(controlling_faction, "runway_operational")
```

### Engineer Repair Task

```gdscript
## engineer_squad.gd - Runway repair capability

func order_repair_runway(airstrip: Airstrip) -> bool:
    if not airstrip:
        return false

    if airstrip.runway_state == RunwayState.OPERATIONAL:
        BattleSignals.order_failed.emit(self, "Runway already operational")
        return false

    # Move to airstrip
    var repair_position := airstrip.get_repair_position()
    _current_order = OrderType.REPAIR_RUNWAY
    _repair_target = airstrip

    set_waypoint(repair_position)
    return true

func _process_repair_runway() -> void:
    if not _repair_target or not is_instance_valid(_repair_target):
        _current_order = OrderType.NONE
        return

    # Check if at repair position
    var dist := global_position.distance_to(_repair_target.get_repair_position())
    if dist > 5.0:
        return  # Still moving

    # Start/continue repair
    if not _is_repairing:
        _repair_target.start_repair(self)
        _is_repairing = true
        _play_work_animation("repairing")

    # Check if repair complete
    if _repair_target.runway_state == RunwayState.OPERATIONAL:
        _repair_target.stop_repair(self)
        _is_repairing = false
        _current_order = OrderType.NONE
        _repair_target = null

func _on_combat_started() -> void:
    super._on_combat_started()

    # Interrupt repair if taking fire
    if _is_repairing and _repair_target:
        _repair_target.stop_repair(self)
        _is_repairing = false
```

### Serialization Support

```gdscript
## Airstrip serialization
func serialize() -> Dictionary:
    return {
        "_version": 1,
        "airstrip_id": airstrip_id,
        "controlling_faction": controlling_faction,
        "runway_state": runway_state,
        "crater_positions": _serialize_positions(crater_positions),
        "repair_progress": _repair_progress,
        "available_aircraft": available_aircraft.duplicate(),
        "capture_progress": capture_progress,
    }

func deserialize(data: Dictionary) -> bool:
    if data.get("_version", 0) != 1:
        return false

    controlling_faction = data.get("controlling_faction", starting_faction)
    runway_state = data.get("runway_state", RunwayState.OPERATIONAL)
    crater_positions = _deserialize_positions(data.get("crater_positions", []))
    _repair_progress = data.get("repair_progress", 0.0)
    available_aircraft = data.get("available_aircraft", available_aircraft)
    capture_progress = data.get("capture_progress", 0.0)

    # Restore crater visuals
    for pos in crater_positions:
        var crater := preload("res://effects/runway_crater.tscn").instantiate()
        crater.global_position = pos
        add_child(crater)

    return true
```

## Consequences

### Positive
- **Strategic control points**: Airstrips create contestable objectives
- **Air support contingency**: Losing airstrip disables air (TR-SYS-081)
- **Asymmetric sabotage**: VC sappers can neutralize US air advantage (TR-SYS-082)
- **Engineer value**: Runway repair is important task (TR-SYS-083)

### Negative
- **Binary availability**: Air support is on/off based on runway state
- **Map dependency**: Requires maps designed with airstrips
- **Balance complexity**: Airstrip control heavily affects US faction

### Mitigations
- Helicopter pads at firebases provide backup air mobility
- Multiple airstrips on larger maps
- Repair time scales with damage, not all-or-nothing
- VC gets own advantages (tunnels) to balance

## ADR Dependencies

- **ADR-0006 (Supply Chain)**: Supply flights from airstrips
- **ADR-0008 (Serialization)**: Airstrip state persistence
- **ADR-0014 (Reinforcement)**: Helicopter delivery alternative
- **ADR-0016 (Terrain Clearing)**: Crater mechanics shared

## Engine Compatibility

**Godot 4.6** - Area3D for capture zones, standard node hierarchy.

## GDD Requirements Addressed

| Requirement | How Addressed |
|-------------|---------------|
| TR-SYS-080 | `Airstrip extends Node3D` map feature with capture mechanics |
| TR-SYS-081 | `AirstripManager.has_air_support()` checks faction control + runway state |
| TR-SYS-082 | `_on_explosion()` adds craters, disables runway at threshold |
| TR-SYS-083 | `start_repair()`, `_process_repair()`, 60 sec per crater |

## Implementation Files

| File | Purpose |
|------|---------|
| `systems/airstrip_manager.gd` | Autoload singleton |
| `map_features/airstrip.gd` | Airstrip map feature |
| `map_features/runway.gd` | Runway collision and visuals |
| `missions/air_mission.gd` | Air support mission data |
| `missions/supply_flight.gd` | Supply flight data |
| `effects/runway_crater.tscn` | Crater visual effect |

## Key Signals

```gdscript
## BattleSignals additions for airstrips
signal airstrip_captured(airstrip: Airstrip, faction: int)
signal airstrip_lost(airstrip: Airstrip, faction: int)
signal runway_cratered(airstrip: Airstrip)
signal runway_repair_started(airstrip: Airstrip)
signal runway_repair_progress(airstrip: Airstrip, progress: float)
signal runway_repaired(airstrip: Airstrip)
signal air_support_launching(mission: AirMission)
signal air_support_unavailable(faction: int, reason: String)
signal supply_flight_unavailable(faction: int, reason: String)
```

## Validation Criteria

- [ ] Airstrips spawn on map, not player-built
- [ ] Capturing airstrip requires presence without contest
- [ ] Lost airstrip disables fixed-wing supply and air support
- [ ] 3+ craters disable runway
- [ ] Engineers can repair runway (60 sec per crater)
- [ ] Repaired runway re-enables air support
- [ ] Sapper explosions create runway craters
- [ ] Airstrip state persists in save/load
