# Systems Designer Analysis: Depot Resource System

## Core Architecture Proposal

### Two Depot Types, Parallel Systems

| Depot | Building | Resource | Consumers |
|-------|----------|----------|-----------|
| **Water Tank** | Renamed from FUEL_DEPOT (type 16) | Water | Infantry (Squad) |
| **Fuel Depot** | New building needed | Fuel | Vehicles |

### Depot Data Model

```gdscript
# On PlacedBuilding or new DepotBuilding class
@export var depot_type: GameEnums.DepotType  # WATER, FUEL
@export var max_reservoir: float = 10000.0
@export var current_reservoir: float = 10000.0
@export var resupply_radius: float = 50.0  # Smaller than firebase 168m
@export var refill_rate: float = 5.0  # Units per second to consumers
@export var regen_rate: float = 2.0  # Reservoir regen per second
@export var maintenance_cost: int = 100  # Global supply
@export var maintenance_interval: float = 120.0  # Every 2 minutes
```

### Resource Flow Diagram

```
┌─────────────────┐
│  Global Supply  │
│   (SupplyMgr)   │
└────────┬────────┘
         │ -100 supply every 2 min
         ▼
┌─────────────────┐     +2/sec regen
│   Depot         │◄────────────────┐
│  Reservoir      │                 │
│  (10,000 max)   │                 │
└────────┬────────┘                 │
         │ -5/sec to each unit      │
         │ (only if unit < 100%)    │
         ▼                          │
┌─────────────────┐                 │
│  Unit Resource  │   Stops at 100% │
│  (water/fuel)   │─────────────────┘
└─────────────────┘
```

### Key Rules

1. **Depot → Unit**: Only flows when unit is below 100%
2. **Supply → Depot**: Maintenance tick deducts from global supply
3. **Depot Regen**: Only active when global supply available
4. **Depot Offline**: If depot can't pay maintenance, it stops providing resources

## Integration Points

### Existing Systems to Modify

1. **Squad.gd** - Change `_auto_resupply()` to query nearby Water Tanks
2. **Vehicle.gd** - Add fuel system parallel to Squad's water
3. **Firebase.gd** - Register child depots, maybe track depot list
4. **SupplyManager** - Add maintenance tick system

### New Components

1. **DepotManager** (autoload?) - Track all depots, run maintenance ticks
2. **Depot signals** in BattleSignals:
   - `depot_reservoir_changed(depot, old_level, new_level)`
   - `depot_maintenance_failed(depot)`
   - `depot_empty(depot)`

## Recommended Implementation Order

1. Rename FUEL_DEPOT → WATER_TANK in enum
2. Add reservoir properties to PlacedBuilding
3. Modify Squad._auto_resupply() to consume from depots
4. Add maintenance tick to SupplyManager
5. Add vehicle fuel system (parallel to water)
6. Add new FUEL_DEPOT building type
