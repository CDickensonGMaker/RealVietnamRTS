# Programmer Analysis: Depot Resource System

## Technical Implementation Plan

### Phase 1: Rename and Extend BuildingData

**File**: `battle_system/data/building_data.gd`

```gdscript
# Add to BuildingType enum
enum BuildingType {
    # ... existing ...
    WATER_TANK = 16,  # Renamed from FUEL_DEPOT
    FUEL_POINT = 33,  # New
}

# Add depot-specific properties
@export var is_depot: bool = false
@export var depot_resource_type: GameEnums.ResourceType = GameEnums.ResourceType.NONE
@export var max_reservoir: float = 0.0
@export var resupply_radius: float = 0.0
```

### Phase 2: Create DepotBuilding Script

**File**: `firebase_system/depot_building.gd` (extends PlacedBuilding)

```gdscript
class_name DepotBuilding extends PlacedBuilding

signal reservoir_changed(old_value: float, new_value: float)
signal reservoir_empty()
signal maintenance_failed()

@export var max_reservoir: float = 10000.0
@export var resupply_radius: float = 50.0
@export var refill_rate: float = 5.0
@export var regen_rate: float = 2.0

var current_reservoir: float = 10000.0
var _maintenance_timer: float = 0.0

func _process(delta: float) -> void:
    _handle_unit_resupply(delta)
    _handle_regeneration(delta)
    _handle_maintenance(delta)

func request_resource(amount: float) -> float:
    var provided := minf(amount, current_reservoir)
    current_reservoir -= provided
    reservoir_changed.emit(current_reservoir + provided, current_reservoir)
    if current_reservoir <= 0:
        reservoir_empty.emit()
    return provided
```

### Phase 3: Modify Squad.gd Water System

**Current code** (to modify):
```gdscript
func _auto_resupply() -> void:
    var firebase := _get_nearest_firebase()
    if firebase and global_position.distance_to(firebase.global_position) <= firebase.influence_radius:
        current_water = minf(current_water + 1.0, max_water)
```

**New code**:
```gdscript
func _auto_resupply(delta: float) -> void:
    if current_water >= max_water:
        return  # Don't consume depot resources at 100%

    var depot := _find_nearest_water_depot()
    if depot and global_position.distance_to(depot.global_position) <= depot.resupply_radius:
        var needed := minf(max_water - current_water, depot.refill_rate * delta)
        var received := depot.request_resource(needed)
        current_water = minf(current_water + received, max_water)
```

### Phase 4: Add Vehicle Fuel System

**File**: `battle_system/nodes/vehicle.gd`

```gdscript
@export var max_fuel: float = 100.0
@export var fuel_depletion_idle: float = 0.1
@export var fuel_depletion_moving: float = 0.3

var current_fuel: float = 100.0

func _process(delta: float) -> void:
    # Fuel depletion
    var rate := fuel_depletion_moving if _is_moving else fuel_depletion_idle
    current_fuel = maxf(0.0, current_fuel - rate * delta)

    # Auto-resupply from fuel depot
    if current_fuel < max_fuel:
        _try_resupply_fuel(delta)

    # Immobilize if empty
    if current_fuel <= 0.0:
        _immobilize()
```

### Phase 5: Maintenance System in SupplyManager

**File**: `battle_system/systems/supply_manager.gd`

```gdscript
const DEPOT_MAINTENANCE_INTERVAL := 120.0  # 2 minutes
const DEPOT_MAINTENANCE_COST := 100

var _depot_maintenance_timer: float = 0.0
var _registered_depots: Array[DepotBuilding] = []

func _process(delta: float) -> void:
    _depot_maintenance_timer += delta
    if _depot_maintenance_timer >= DEPOT_MAINTENANCE_INTERVAL:
        _depot_maintenance_timer = 0.0
        _run_depot_maintenance()

func _run_depot_maintenance() -> void:
    for depot in _registered_depots:
        if global_supply >= DEPOT_MAINTENANCE_COST:
            global_supply -= DEPOT_MAINTENANCE_COST
            depot.maintenance_paid()
        else:
            depot.maintenance_failed()
```

### Signal Additions to BattleSignals

```gdscript
signal depot_reservoir_changed(depot: Node, resource_type: int, old_level: float, new_level: float)
signal depot_maintenance_failed(depot: Node)
signal depot_empty(depot: Node, resource_type: int)
signal unit_resupply_started(unit: Node, depot: Node)
signal unit_resupply_completed(unit: Node, depot: Node)
```

## File Changes Summary

| File | Change Type |
|------|-------------|
| `building_data.gd` | Modify enum, add depot properties |
| `depot_building.gd` | **New file** |
| `squad.gd` | Modify `_auto_resupply()` |
| `vehicle.gd` | Add fuel system |
| `supply_manager.gd` | Add maintenance ticks |
| `battle_signals.gd` | Add depot signals |
| `water_tank.tscn` | Rename from fuel_depot.tscn |
| `fuel_point.tscn` | **New scene** |
