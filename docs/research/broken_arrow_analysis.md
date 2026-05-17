# Broken Arrow System Analysis

## Sources
- [Broken Arrow Steam Page](https://store.steampowered.com/app/1604270/Broken_Arrow/)
- [Broken Arrow Review - Reality Remake](https://www.realityremake.com/articles/broken-arrow-review-a-modern-rts-powerhouse-with-muscle-and-grit)
- [Broken Arrow - The Gamer](https://www.thegamer.com/broken-arrow-bridge-to-modern-military-rts/)
- [Broken Arrow - WebGameWeekly](https://webgameweekly.com/articles/broken-arrow-the-new-standard-for-real-time-tactics-and-combined-arms-warfare)

## Game Overview
Broken Arrow (released June 2025) is a modern warfare RTT game by Steel Balalaika, published by Slitherine. It emphasizes combined arms warfare with deep customization.

## No Traditional Base Building
Unlike classic RTS games, Broken Arrow does **not** use base construction:
- No harvesting resources
- No building factories
- No in-game construction

Instead, it uses a **deck-building** system where armies are assembled before battle.

## Deck Building System

### Pre-Battle Customization
- 300+ unit types
- 1,500+ possible combinations
- Units customizable with different weapons, armor kits, roles
- Example: APC → missile carrier, Fighter jet → precision bomber

### Deck Constraints
- 10,000 points to spend (outside campaign)
- Caps prevent overstacking single unit types
- Forces balanced, specialized, or creative compositions

### Deployment
- Units deployed via Command Points
- Points earned over time or by achieving objectives
- Focus on timing and positioning, not economy management

## Supply System

### Logistics Matter
- Units run out of ammo over time
- Supply trucks or airdrops replenish
- Losing supply chain = operational paralysis

### Supply Elements
- Forward Operating Bases (FOBs) - spawn/supply points
- Supply Trucks - mobile resupply
- Airdrops - emergency resupply
- Medevac Systems - casualty recovery

### Operational Impact
- Ammunition tracked per unit
- Fuel consumption (vehicles)
- Repair required for damaged units
- Reinforcement lines must be protected

## Terrain & Environment

### Destructible Terrain
- Buildings can be destroyed
- Terrain deforms from explosions
- Cover degrades over time

### Terrain Tactics
- Urban: Ambush + infantry garrison advantage
- Open Fields: Death zones without smoke/suppression
- Hills/Ridges: Line of sight advantages

### Line of Sight
- Critical for positioning
- Smoke breaks LOS
- Terrain occludes vision

## Combat Dynamics

### Combined Arms Essential
- Tanks vulnerable to ambush without infantry support
- Airpower devastating but vulnerable
- Infantry strong in urban/forest
- Artillery suppresses but needs spotters

### Reinforcement Flow
- Units deploy from off-map
- Timing of reinforcements critical
- FOBs as forward spawn points

## Applicability to RealVietnamRTS

### Deck Building Parallel
RealVietnamRTS uses a similar "Doctrine" system:
- Pre-mission unit selection
- No in-game production
- Reinforcements from off-map

### Supply Implementation
```gdscript
class_name SupplyUnit extends Node3D

var supply_capacity: float = 500.0
var current_supply: float = 500.0

# Supply types
enum SupplyType { AMMO, FUEL, MEDICAL }

var supply_inventory = {
    SupplyType.AMMO: 200.0,
    SupplyType.FUEL: 150.0,
    SupplyType.MEDICAL: 150.0,
}

func resupply_unit(unit: Node3D) -> void:
    if unit.has_method("request_resupply"):
        var needed = unit.request_resupply()
        for type in needed:
            var available = minf(supply_inventory[type], needed[type])
            unit.receive_supply(type, available)
            supply_inventory[type] -= available
```

### FOB System
```gdscript
class_name FOB extends Node3D

# Spawn and supply hub
var spawn_radius: float = 50.0
var supply_radius: float = 100.0
var reinforcement_queue: Array = []

# Units in radius auto-resupply
func _process(delta: float) -> void:
    var units = _get_units_in_radius(supply_radius)
    for unit in units:
        if unit.needs_resupply():
            _resupply_unit(unit, delta)

# Reinforcements spawn here
func spawn_reinforcement(unit_type: int) -> Node3D:
    var spawn_pos = _get_random_spawn_position()
    var unit = _create_unit(unit_type, spawn_pos)
    return unit
```

### Key Lessons
1. **No base building can work** - Focus on deployment timing
2. **Supply must be physical** - Trucks, not abstract resources
3. **FOBs as spawn points** - Forward deployment matters
4. **Terrain is tactical** - LOS and cover critical
5. **Combined arms required** - No single unit type dominates

## Vietnam Adaptation

### Firebase as FOB
- Firebases serve as spawn/resupply points
- Must be established via gameplay (clearing + construction)
- Vulnerable to attack (unlike infinite spawn points)

### Supply Convoys
- Ground convoys on roads (ambushable)
- Helicopter resupply to LZs
- Supply consumption per engagement

### Reinforcement Limits
- Pool of available units (like deck points)
- Heavy losses = delayed replacements
- Elite units limited availability
