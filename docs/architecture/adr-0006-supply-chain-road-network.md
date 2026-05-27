# ADR-0006: Supply Chain & Road Network Architecture

## Status
Accepted

## Context
- Pillar 3 (Physical Supply Chains) requires spatial, attackable logistics
- Supply trucks must travel on physical roads between depots
- Roads can be damaged, cratered, or blocked by enemy action
- Convoys need pathfinding that respects road conditions
- Auto-road construction should trigger when Supply Depots are built
- Need efficient pathfinding for convoys without expensive navmesh recalculation
- Bridges must be special road segments that span water/ravines

## Decision

### RoadNetwork (terrain/systems/road_network.gd)

**Waypoint-based graph instead of navmesh**: Roads use a node-segment graph where RoadNodes are intersections/endpoints and RoadSegments connect them. This avoids navmesh regeneration when road state changes.

**Road Segment Structure**:
```gdscript
class RoadSegment:
    var id: int
    var start: Vector3
    var end: Vector3
    var road_type: int      # DIRT_TRAIL, LATERITE, GRAVEL, PAVED, PSP_MATTING
    var state: int          # INTACT, DAMAGED, CRATERED, BLOCKED
    var repair_progress: float
    var length: float
    var connected_segments: Array[int]
    var is_bridge: bool
```

**Road Types with Speed Multipliers**:
| Type | Speed Mult | Description |
|------|------------|-------------|
| DIRT_TRAIL | 1.0x | Basic jungle path |
| LATERITE | 1.15x | Red clay road |
| GRAVEL | 1.2x | Improved surface |
| PAVED | 1.25x | Asphalt/concrete |
| PSP_MATTING | 1.3x | Pierced steel planking (airfield/firebase) |

**Road Damage States**:
| State | Speed Mult | Repair Work | Description |
|-------|------------|-------------|-------------|
| INTACT | 1.0 | N/A | Full speed |
| DAMAGED | 0.75 | 20 units | Reduced speed |
| CRATERED | 0.4 | 50 units | Severe damage, slow |
| BLOCKED | 0.0 | 100 units | Impassable |

**A* Pathfinding**: Travel cost = `segment.length / segment.get_speed_multiplier()`. This makes damaged roads costlier and blocked roads impassable.

**Spatial Grid for Queries**: Segments indexed in 50m grid cells using Bresenham-style line rasterization. Enables O(1) lookup for `get_segment_at(position)`.

**Path Cache**: Paths cached by quantized position keys. Cache invalidated on any road state change (`_invalidate_cache()`).

### SupplyChainManager (logistics_system/supply_chain_manager.gd)

**Auto-Road Building**: When a Supply Depot completes construction:
1. Register depot in `_supply_depots` array
2. Find nearest existing depot
3. Plan route with waypoints every 20m
4. Create BUILD_ROAD jobs for each segment via JobSystem

**Depot Registration Flow**:
```
BattleSignals.construction_complete
    -> _on_construction_complete(building)
    -> if SUPPLY_DEPOT: _register_depot(depot)
    -> if >1 depot: _auto_build_road_to_depot(position)
```

**Main Base Promotion**: First depot becomes main base. If destroyed, next oldest depot is promoted.

**Road Completion Tracking**: Pending roads tracked in dictionary keyed by position string. When all segment jobs complete, road is registered with RoadNetwork.

### Bridge Segments

**Special Road Type**: Bridges use `is_bridge: bool` flag and default to PSP_MATTING type (military steel planking).

**Creation**: `create_bridge_segment(start, end)` creates a road segment that:
- Spans water/ravines that regular roads cannot cross
- Uses military-grade surface (1.3x speed)
- Emits `bridge_created` signal for visual/audio feedback

### SupplyTruck Integration

SupplyTruck queries RoadNetwork for routes:
```gdscript
var waypoints: Array[Vector3] = RoadNetwork.find_path(from, to)
```

Speed adjusted based on current segment:
```gdscript
var speed_mult: float = RoadNetwork.get_speed_multiplier_at(global_position)
var effective_speed: float = base_speed * speed_mult
```

## Consequences

### Positive
- **Spatial supply chains**: Trucks visible on roads, can be ambushed (Pillar 3)
- **Attackable logistics**: Crater roads to slow/block convoys
- **Auto-network growth**: Depots auto-connect with roads
- **Efficient pathfinding**: Graph-based A* avoids navmesh regeneration
- **Road repair gameplay**: Engineers repair damaged roads (repair_progress accumulates)
- **Cache invalidation**: Path cache cleared on road damage for correctness

### Negative
- **Graph maintenance**: Must keep node/segment connections bidirectionally updated
- **Cache thrashing**: Heavy combat with frequent road damage clears cache repeatedly
- **Spatial grid overhead**: Memory cost for segment grid (acceptable for road counts)
- **Direct route fallback**: If no road found, convoys use direct path (may cross jungle)

### Mitigations
- Grid cell size of 50m balances lookup speed vs memory
- Cache limited to 100 entries with LRU-style eviction
- `create_segment_from_positions()` auto-merges nodes within 5m radius
- Road jobs integrated with JobSystem for worker assignment

## ADR Dependencies
- ADR-0004 (Signal Bus Pattern): Uses BattleSignals for `construction_complete`, `road_damaged`
- ADR-0005 (Job System): Road building uses BUILD_ROAD job type through JobSystem

## Engine Compatibility
Godot 4.6 - Implementation uses:
- Node for autoload singletons (RoadNetwork, SupplyChainManager)
- Dictionary for segment/node storage and spatial grid
- Array[Vector3] for waypoint paths
- Vector2i for grid cell coordinates
- Inner classes (RoadSegment, RoadNode) for data structures
- Timer-based cleanup via `_process()` with frame-count gating

## GDD Requirements Addressed

### supply-logistics.md
- **Convoy pathfinding on roads**: `RoadNetwork.find_path()` returns waypoints along road graph
- **Road speed**: Type-based multipliers (1.0x-1.3x based on road quality)
- **Road damage affects supply flow**: DAMAGED/CRATERED states reduce speed, BLOCKED stops convoys
- **Road vulnerability**: `damage_road_at(position)` escalates damage states
- **Road repair**: `repair_segment(id, work_amount)` accumulates repair progress
- **Convoy routing**: A* pathfinding with cost = distance / speed_multiplier

### terrain-clearing.md
- **Roads create cleared paths**: Road construction jobs clear underlying terrain
- **Road cutting**: BUILD_ROAD jobs integrate with terrain clearing system
- **Craters block road passage**: CRATERED/BLOCKED states from explosion damage

## Implementation Files

| File | Purpose |
|------|---------|
| `terrain/systems/road_network.gd` | RoadNetwork autoload - graph-based road system with A* pathfinding |
| `logistics_system/supply_chain_manager.gd` | SupplyChainManager - auto-road building between depots |

## Key Signals

### RoadNetwork Signals
```gdscript
signal road_damaged(segment_id: int, position: Vector3)
signal road_repaired(segment_id: int)
signal road_blocked(segment_id: int)
signal path_found(from: Vector3, to: Vector3, waypoints: Array[Vector3])
signal bridge_created(segment_id: int, start: Vector3, end: Vector3)
```

### SupplyChainManager Signals
```gdscript
signal road_construction_started(from_pos: Vector3, to_pos: Vector3)
signal road_construction_completed(from_pos: Vector3, to_pos: Vector3)
signal depot_registered(depot: Node3D, is_main_base: bool)
signal depot_unregistered(depot: Node3D)
```

## API Summary

### RoadNetwork Public API
| Method | Returns | Description |
|--------|---------|-------------|
| `find_path(from, to)` | Array[Vector3] | A* path along road network |
| `get_speed_multiplier_at(pos)` | float | Speed multiplier at position |
| `is_on_road(pos)` | bool | Check if position is on a road |
| `damage_road_at(pos, damage_type)` | void | Damage road segment at position |
| `repair_segment(id, work_amount)` | bool | Apply repair work, returns true if fully repaired |
| `create_segment_from_positions(start, end, type)` | int | Create road segment, returns segment_id |
| `create_bridge_segment(start, end)` | int | Create bridge segment |
| `is_route_passable(from, to)` | bool | Check if route has no BLOCKED segments |
| `get_travel_time(from, to, base_speed)` | float | Estimated travel time in seconds |

### SupplyChainManager Public API
| Method | Returns | Description |
|--------|---------|-------------|
| `get_depot_count()` | int | Number of registered depots |
| `get_main_base()` | Node3D | Main base depot (first established) |
| `get_all_depots()` | Array[Node3D] | All registered supply depots |
| `find_nearest_depot_to(position)` | Node3D | Nearest depot to position |
| `manually_register_depot(depot)` | void | Register existing depot (map start) |
| `force_build_road(from, to)` | void | Manual road construction trigger |
