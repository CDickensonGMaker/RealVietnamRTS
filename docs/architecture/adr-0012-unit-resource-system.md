# ADR-0012: Unit Resource System

## Status
Proposed

## Context

RealVietnamRTS uses physical supply chains as a core pillar (Pillar 3). Squads carry internal reserves that deplete during combat and must be replenished via the supply system. Running out of ammo or water has severe consequences, creating meaningful logistics gameplay.

### Requirements to Address
| TR-ID | Requirement |
|-------|-------------|
| TR-COR-020 | Squads carry internal reserves: Ammo, Water, Morale |
| TR-COR-021 | Low Ammo triggers LOW AMMO icon; Empty Ammo triggers auto-retreat + voice callout |
| TR-COR-022 | Low Water causes accelerated morale drain; Empty Water causes severe morale drain |
| TR-COR-023 | Squads within firebase influence radius automatically resupply |
| TR-COR-024 | Squads outside influence must return to firebase or receive helicopter/truck delivery |
| TR-COR-025 | Audio callout when squad retreats: "SQUAD OUT OF SUPPLIES FALLING BACK" |

## Decision

### Resource Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                      UnitResourceManager                             │
│                      (Component on Squad)                            │
├─────────────────────────────────────────────────────────────────────┤
│  + ammo: float (0.0 - max_ammo)                                     │
│  + water: float (0.0 - max_water)                                   │
│  + consume_ammo(amount: float) -> bool                              │
│  + consume_water(delta: float) -> void                              │
│  + resupply(resource: ResourceType, amount: float) -> void          │
│  + get_resource_state(resource: ResourceType) -> ResourceState      │
├─────────────────────────────────────────────────────────────────────┤
│  Signals: resource_depleted, resource_low, resource_resupplied      │
└─────────────────────────────────────────────────────────────────────┘
```

### Resource Types and Thresholds

```gdscript
enum ResourceType {
    AMMO,
    WATER,
}

enum ResourceState {
    FULL,       # 75-100%
    ADEQUATE,   # 50-75%
    LOW,        # 25-50% - triggers warning icon
    CRITICAL,   # 10-25% - triggers urgent warning
    EMPTY,      # 0-10% - triggers auto-retreat
}

const RESOURCE_THRESHOLDS := {
    ResourceState.FULL: 0.75,
    ResourceState.ADEQUATE: 0.50,
    ResourceState.LOW: 0.25,
    ResourceState.CRITICAL: 0.10,
    ResourceState.EMPTY: 0.0,
}
```

### Ammo System (TR-COR-020, TR-COR-021)

```gdscript
class_name UnitResourceManager extends Node

## Ammo configuration
@export var max_ammo: float = 100.0
@export var ammo_per_shot: float = 1.0
@export var ammo_per_burst: float = 5.0

var ammo: float = 100.0
var _low_ammo_warned: bool = false
var _empty_ammo_retreating: bool = false

func consume_ammo(amount: float) -> bool:
    """Consume ammo for firing. Returns false if insufficient ammo."""
    if ammo < amount:
        return false

    ammo -= amount
    var state := get_resource_state(ResourceType.AMMO)

    # TR-COR-021: Low ammo triggers icon
    if state == ResourceState.LOW and not _low_ammo_warned:
        _low_ammo_warned = true
        BattleSignals.unit_low_ammo.emit(_owner)
        _show_low_ammo_icon()

    # TR-COR-021: Empty ammo triggers auto-retreat
    if state == ResourceState.EMPTY and not _empty_ammo_retreating:
        _empty_ammo_retreating = true
        _trigger_ammo_retreat()

    return true

func _trigger_ammo_retreat() -> void:
    """Auto-retreat when ammo depleted (TR-COR-021)"""
    # Play voice callout (TR-COR-025)
    AudioManager.play_voice(_owner, "squad_out_of_ammo")

    # Find nearest resupply point
    var resupply_point := _find_nearest_resupply()
    if resupply_point:
        _owner.set_waypoint(resupply_point.global_position)
        _owner.set_behavior_override(BehaviorOverride.RESUPPLY_RETREAT)
        BattleSignals.squad_retreating_resupply.emit(_owner, "ammo")

func _show_low_ammo_icon() -> void:
    """Display LOW AMMO warning icon above unit"""
    var icon := preload("res://battle_system/ui/icons/low_ammo_icon.tscn").instantiate()
    _owner.add_child(icon)
```

### Water System (TR-COR-020, TR-COR-022)

```gdscript
## Water configuration
@export var max_water: float = 100.0
@export var water_drain_rate: float = 0.5  # Per minute in normal conditions
@export var water_drain_combat: float = 1.5  # Per minute in combat

var water: float = 100.0

## Morale penalties from dehydration (TR-COR-022)
const MORALE_DRAIN_LOW_WATER := -0.3      # Accelerated drain
const MORALE_DRAIN_EMPTY_WATER := -1.0    # Severe drain

func _process(delta: float) -> void:
    _update_water(delta)

func _update_water(delta: float) -> void:
    # Water drains over time
    var drain_rate := water_drain_rate
    if _owner.is_in_combat():
        drain_rate = water_drain_combat

    # Convert per-minute to per-second
    water -= (drain_rate / 60.0) * delta
    water = maxf(water, 0.0)

    var state := get_resource_state(ResourceType.WATER)

    # TR-COR-022: Apply morale penalties
    match state:
        ResourceState.LOW, ResourceState.CRITICAL:
            MoraleSystem.apply_continuous_modifier(
                _owner,
                "dehydration",
                MORALE_DRAIN_LOW_WATER * delta
            )
        ResourceState.EMPTY:
            MoraleSystem.apply_continuous_modifier(
                _owner,
                "severe_dehydration",
                MORALE_DRAIN_EMPTY_WATER * delta
            )

func is_dehydrated() -> bool:
    """Check if unit is suffering from dehydration"""
    var state := get_resource_state(ResourceType.WATER)
    return state in [ResourceState.LOW, ResourceState.CRITICAL, ResourceState.EMPTY]
```

### Auto-Resupply System (TR-COR-023)

```gdscript
## Auto-resupply within firebase influence radius
const RESUPPLY_CHECK_INTERVAL := 2.0  # Seconds
const RESUPPLY_RATE_AMMO := 10.0      # Per second when in supply zone
const RESUPPLY_RATE_WATER := 5.0      # Per second when in supply zone

var _resupply_timer: float = 0.0

func _process(delta: float) -> void:
    _update_water(delta)
    _check_auto_resupply(delta)

func _check_auto_resupply(delta: float) -> void:
    _resupply_timer += delta
    if _resupply_timer < RESUPPLY_CHECK_INTERVAL:
        return
    _resupply_timer = 0.0

    # TR-COR-023: Check if within firebase influence
    if FirebaseSystem.is_in_supply_zone(_owner.global_position, _owner.faction):
        _perform_auto_resupply(RESUPPLY_CHECK_INTERVAL)

func _perform_auto_resupply(time_in_zone: float) -> void:
    """Resupply while in firebase influence radius"""
    var ammo_gained := RESUPPLY_RATE_AMMO * time_in_zone
    var water_gained := RESUPPLY_RATE_WATER * time_in_zone

    var ammo_before := ammo
    var water_before := water

    ammo = minf(ammo + ammo_gained, max_ammo)
    water = minf(water + water_gained, max_water)

    # Reset warning states if resupplied
    if ammo > max_ammo * RESOURCE_THRESHOLDS[ResourceState.LOW]:
        _low_ammo_warned = false
        _empty_ammo_retreating = false
        _hide_low_ammo_icon()

    # Signal resupply for UI feedback
    if ammo > ammo_before or water > water_before:
        BattleSignals.unit_resupplied.emit(_owner)
```

### Manual Resupply (TR-COR-024)

```gdscript
## Resupply from helicopter/truck delivery
func resupply_from_vehicle(vehicle: Node3D) -> void:
    """Receive supplies from helicopter or truck (TR-COR-024)"""
    var supply_amount := vehicle.get_supply_capacity()

    # Distribute supplies based on need
    var ammo_needed := max_ammo - ammo
    var water_needed := max_water - water
    var total_needed := ammo_needed + water_needed

    if total_needed <= 0:
        return

    # Proportional distribution
    var ammo_ratio := ammo_needed / total_needed
    var water_ratio := water_needed / total_needed

    resupply(ResourceType.AMMO, supply_amount * ammo_ratio)
    resupply(ResourceType.WATER, supply_amount * water_ratio)

    # Play resupply audio (TR-COR-025)
    AudioManager.play_voice(_owner, "squad_resupplied")
    BattleSignals.squad_resupplied.emit(_owner, vehicle)

func resupply(resource: ResourceType, amount: float) -> void:
    """Add resources to unit reserves"""
    match resource:
        ResourceType.AMMO:
            ammo = minf(ammo + amount, max_ammo)
            if ammo > max_ammo * RESOURCE_THRESHOLDS[ResourceState.LOW]:
                _low_ammo_warned = false
                _empty_ammo_retreating = false
        ResourceType.WATER:
            water = minf(water + amount, max_water)

    BattleSignals.resource_resupplied.emit(_owner, resource, amount)
```

### Resource State Queries

```gdscript
func get_resource_state(resource: ResourceType) -> ResourceState:
    """Get current state of a resource"""
    var current: float
    var maximum: float

    match resource:
        ResourceType.AMMO:
            current = ammo
            maximum = max_ammo
        ResourceType.WATER:
            current = water
            maximum = max_water

    var ratio := current / maximum if maximum > 0 else 0.0

    if ratio >= RESOURCE_THRESHOLDS[ResourceState.FULL]:
        return ResourceState.FULL
    elif ratio >= RESOURCE_THRESHOLDS[ResourceState.ADEQUATE]:
        return ResourceState.ADEQUATE
    elif ratio >= RESOURCE_THRESHOLDS[ResourceState.LOW]:
        return ResourceState.LOW
    elif ratio >= RESOURCE_THRESHOLDS[ResourceState.CRITICAL]:
        return ResourceState.CRITICAL
    else:
        return ResourceState.EMPTY

func get_ammo_percentage() -> float:
    return ammo / max_ammo if max_ammo > 0 else 0.0

func get_water_percentage() -> float:
    return water / max_water if max_water > 0 else 0.0

func is_low_ammo() -> bool:
    return get_resource_state(ResourceType.AMMO) in [
        ResourceState.LOW, ResourceState.CRITICAL, ResourceState.EMPTY
    ]

func has_good_supply() -> bool:
    """Check if unit has adequate supplies (for morale bonus)"""
    return (get_resource_state(ResourceType.AMMO) in [ResourceState.FULL, ResourceState.ADEQUATE]
        and get_resource_state(ResourceType.WATER) in [ResourceState.FULL, ResourceState.ADEQUATE])
```

### Integration with Combat System

```gdscript
## Called by combat system when unit fires
func on_weapon_fired(weapon_data: WeaponData) -> bool:
    """Consume ammo when firing. Returns false if cannot fire."""
    var ammo_cost := weapon_data.ammo_per_shot
    return consume_ammo(ammo_cost)

## Called by combat system for burst fire
func on_burst_fired(weapon_data: WeaponData, rounds: int) -> bool:
    """Consume ammo for burst fire."""
    var ammo_cost := weapon_data.ammo_per_shot * rounds
    return consume_ammo(ammo_cost)
```

### Serialization Support

```gdscript
func serialize() -> Dictionary:
    return {
        "_version": 1,
        "_system": "UnitResourceManager",
        "ammo": ammo,
        "water": water,
        "max_ammo": max_ammo,
        "max_water": max_water,
        "low_ammo_warned": _low_ammo_warned,
        "empty_ammo_retreating": _empty_ammo_retreating,
    }

func deserialize(data: Dictionary) -> bool:
    if data.get("_version", 0) != 1:
        return false

    ammo = data.get("ammo", max_ammo)
    water = data.get("water", max_water)
    max_ammo = data.get("max_ammo", 100.0)
    max_water = data.get("max_water", 100.0)
    _low_ammo_warned = data.get("low_ammo_warned", false)
    _empty_ammo_retreating = data.get("empty_ammo_retreating", false)

    return true
```

## Consequences

### Positive
- **Logistics matters**: Running out of ammo/water has real consequences
- **Firebase importance**: Units must stay near or return to firebase
- **Visual feedback**: Clear icons show resource state
- **Audio feedback**: Voice callouts communicate critical states
- **Supply chain integration**: Creates demand for helicopters/trucks

### Negative
- **Micromanagement potential**: Players must track unit supplies
- **Complexity**: Multiple resource types to balance
- **UI clutter**: Resource icons add visual noise

### Mitigations
- Auto-resupply in firebase zones reduces micro
- Group resource indicators for selected units
- Audio callouts reduce need to watch icons
- Clear thresholds make state predictable

## ADR Dependencies

- **ADR-0006 (Supply Chain)**: Helicopter/truck resupply integration
- **ADR-0008 (Serialization)**: Resource state persistence
- **ADR-0009 (Firebase Placement)**: Influence radius for auto-resupply
- **ADR-0011 (Morale)**: Dehydration affects morale

## Engine Compatibility

**Godot 4.6** - Pure GDScript, standard Node component pattern.

## GDD Requirements Addressed

| Requirement | How Addressed |
|-------------|---------------|
| TR-COR-020 | `UnitResourceManager` with ammo and water properties |
| TR-COR-021 | `_show_low_ammo_icon()` and `_trigger_ammo_retreat()` |
| TR-COR-022 | `MORALE_DRAIN_LOW_WATER` and `MORALE_DRAIN_EMPTY_WATER` applied via MoraleSystem |
| TR-COR-023 | `_check_auto_resupply()` with `FirebaseSystem.is_in_supply_zone()` |
| TR-COR-024 | `resupply_from_vehicle()` for helicopter/truck delivery |
| TR-COR-025 | `AudioManager.play_voice()` calls for retreat callout |

## Implementation Files

| File | Purpose |
|------|---------|
| `battle_system/components/unit_resource_manager.gd` | Resource tracking component |
| `battle_system/ui/icons/low_ammo_icon.tscn` | Warning icon prefab |
| `battle_system/ui/icons/low_water_icon.tscn` | Warning icon prefab |

## Key Signals

```gdscript
## BattleSignals additions for resources
signal unit_low_ammo(unit: Node3D)
signal unit_low_water(unit: Node3D)
signal unit_resupplied(unit: Node3D)
signal squad_retreating_resupply(unit: Node3D, resource_type: String)
signal squad_resupplied(unit: Node3D, source: Node3D)
signal resource_resupplied(unit: Node3D, resource: int, amount: float)
```

## Validation Criteria

- [ ] Firing weapons consumes ammo
- [ ] LOW AMMO icon appears at 25% ammo
- [ ] Unit auto-retreats when ammo reaches 0-10%
- [ ] Voice callout plays on retreat ("SQUAD OUT OF SUPPLIES FALLING BACK")
- [ ] Water drains over time (faster in combat)
- [ ] Low water causes morale drain (-0.3/sec)
- [ ] Empty water causes severe morale drain (-1.0/sec)
- [ ] Units in firebase radius auto-resupply
- [ ] Helicopter/truck delivery resupplies units outside radius
