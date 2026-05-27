# ADR-0007: Navigation Mesh Architecture

## Status

Accepted

## Date

2026-05-22

## Last Verified

2026-05-22

## Decision Makers

Technical Director, Systems Designer

## Summary

Unit pathfinding in RealVietnamRTS requires a navigation mesh system that respects terrain clearing states, integrates with the chunk streaming architecture, and provides separate routing for convoy road networks and routing (fleeing) units. This ADR establishes Godot's NavigationServer3D as the foundation, with per-chunk NavigationRegion3D nodes that update dynamically as terrain is cleared.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Navigation |
| **Knowledge Risk** | LOW - NavigationServer3D is stable in Godot 4.x |
| **References Consulted** | Godot 4.6 navigation documentation, ADR-0001 (Terrain Chunk Streaming) |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | NavigationRegion3D edge linking across chunk boundaries |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Terrain Chunk Streaming) - must be Accepted; navigation regions follow chunk boundaries |
| **Enables** | Convoy pathfinding, morale routing, squad movement |
| **Blocks** | Supply Logistics implementation (convoy routing), Morale System implementation (flee pathfinding) |
| **Ordering Note** | Navigation mesh must be generated after terrain heightmap and vegetation; updates after clearing operations |

## Context

### Problem Statement

Units in RealVietnamRTS must navigate a dynamic battlefield where:
- Terrain clearing changes passability (JUNGLE -> PARTIALLY_CLEARED -> CLEARED)
- Roads provide preferential paths for convoys
- Routing (fleeing) units must pathfind toward friendly firebases
- The 3km x 3km map requires efficient chunked navigation

Without a unified navigation architecture, movement systems will be inconsistent, convoys will not follow roads, and routing units will path incorrectly.

### Current State

ADR-0001 establishes per-chunk terrain management including navigation mesh regions. This ADR defines the specific navigation mesh behavior, cost modifiers, and integration points.

### Constraints

- Navigation regions must match 32x32m chunk boundaries from ADR-0001
- Navigation mesh rebuilds must not cause frame stalls
- Convoy routing must overlay road network onto base navigation
- Must support both infantry and vehicle navigation

### Requirements

- Navigation mesh per terrain chunk, linked at boundaries
- Terrain clearing state affects navigation costs
- Road network provides cost=0 paths for convoys
- Routing units pathfind to nearest firebase using standard navigation
- Navigation queries complete within 1ms for 500 concurrent units
- Chunk load/unload updates navigation without stalls

## Decision

Use **Godot NavigationServer3D** with per-chunk NavigationRegion3D nodes. Each terrain chunk owns its navigation region and updates it when terrain state changes. Road networks are implemented as overlaid navigation regions with zero cost.

### Architecture

```
+-------------------+     +----------------------+
|  NavigationServer |<--->|   NavigationAgent3D  |
|      (Singleton)  |     |   (per Squad/Vehicle)|
+-------------------+     +----------------------+
         ^
         |
+--------+--------+--------+--------+
|        |        |        |        |
v        v        v        v        v
+------+ +------+ +------+ +------+ +------+
|NavReg| |NavReg| |NavReg| |NavReg| |NavReg|  <- Per Chunk
|Chunk | |Chunk | |Chunk | |Chunk | |Chunk |
|(0,0) | |(1,0) | |(2,0) | |(0,1) | | ...  |
+------+ +------+ +------+ +------+ +------+
         |
         v
+-------------------+
|   RoadNetwork     |  <- Overlay NavRegion with cost=0
|   (Road Segments) |
+-------------------+
```

### Navigation Layers

| Layer | Bit | Purpose | Used By |
|-------|-----|---------|---------|
| 0 | 1 | Base terrain | All units |
| 1 | 2 | Road network | Convoys (preferred) |
| 2 | 4 | Infantry-only | Infantry, routing units |
| 3 | 8 | Vehicle-only | Vehicles, armor |

### Travel Cost Modifiers

| Terrain State | Base Cost | Infantry Cost | Vehicle Cost |
|---------------|-----------|---------------|--------------|
| JUNGLE | 4.0 | 2.0 (can push through) | INF (impassable) |
| PARTIALLY_CLEARED | 2.0 | 1.5 | 3.0 (slow) |
| CLEARED | 1.0 | 1.0 | 1.0 |
| FORTIFIED | 1.0 | 1.0 | 1.0 |
| ROAD | 0.5 | 0.8 | 0.3 (preferred) |
| WATER | INF | INF | INF |

### Key Interfaces

```gdscript
# TerrainChunk - navigation region management
class_name TerrainChunk extends Node3D

var _nav_region: NavigationRegion3D
var _nav_mesh: NavigationMesh

func _ready() -> void:
    _nav_region = NavigationRegion3D.new()
    _nav_region.navigation_layers = 0b0001  # Base terrain layer
    add_child(_nav_region)
    _generate_navigation_mesh()

func _generate_navigation_mesh() -> void:
    _nav_mesh = NavigationMesh.new()
    _nav_mesh.cell_size = 0.5
    _nav_mesh.cell_height = 0.2
    _nav_mesh.agent_radius = 0.5
    _nav_mesh.agent_height = 1.8
    _nav_mesh.agent_max_climb = 0.5
    _nav_mesh.agent_max_slope = 45.0
    # Bake from chunk geometry
    NavigationServer3D.bake_from_source_geometry_data(_nav_mesh, _get_source_geometry())
    _nav_region.navigation_mesh = _nav_mesh

func update_navigation_for_clearing(cell_coords: Vector2i, new_state: int) -> void:
    # Mark region as needing rebake
    _pending_nav_update = true

func _process(_delta: float) -> void:
    if _pending_nav_update:
        _rebake_navigation_async()
        _pending_nav_update = false

func _rebake_navigation_async() -> void:
    # Defer to thread to avoid frame stalls
    var callable := Callable(self, "_generate_navigation_mesh")
    WorkerThreadPool.add_task(callable)
```

```gdscript
# RoadNetwork - overlay navigation for convoys
class_name RoadNetwork extends Node3D

var _road_nav_region: NavigationRegion3D
var _road_segments: Array[RoadSegment] = []

func add_road_segment(start: Vector3, end: Vector3, width: float) -> void:
    var segment := RoadSegment.new(start, end, width)
    _road_segments.append(segment)
    _rebuild_road_navigation()

func _rebuild_road_navigation() -> void:
    var nav_mesh := NavigationMesh.new()
    nav_mesh.cell_size = 0.25  # Higher resolution for roads
    nav_mesh.agent_radius = 1.5  # Vehicle width
    # Generate mesh from road segments
    _road_nav_region.navigation_mesh = nav_mesh
    _road_nav_region.navigation_layers = 0b0010  # Road layer
```

```gdscript
# NavigationAgent3D usage on Squad
class_name Squad extends CharacterBody3D

@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D

func _ready() -> void:
    _nav_agent.path_desired_distance = 0.5
    _nav_agent.target_desired_distance = 1.0
    _nav_agent.navigation_layers = 0b0101  # Base + Infantry
    _nav_agent.path_postprocessing = NavigationPathQueryParameters3D.PATH_POSTPROCESSING_EDGECENTERED

func move_to(target: Vector3) -> void:
    _nav_agent.target_position = target

func flee_to_firebase(firebase_position: Vector3) -> void:
    # Routing uses same navigation but ignores combat
    _nav_agent.target_position = firebase_position
    _is_routing = true

func _physics_process(delta: float) -> void:
    if _nav_agent.is_navigation_finished():
        return

    var next_pos := _nav_agent.get_next_path_position()
    var direction := global_position.direction_to(next_pos)
    velocity = direction * _get_movement_speed()
    move_and_slide()
```

```gdscript
# Convoy pathfinding - prefers roads
class_name Convoy extends Node3D

var _lead_vehicle: Vehicle

func calculate_route(start: Vector3, end: Vector3) -> PackedVector3Array:
    var query := NavigationPathQueryParameters3D.new()
    query.start_position = start
    query.target_position = end
    query.navigation_layers = 0b0011  # Base + Road (road preferred)
    query.pathfinding_algorithm = NavigationPathQueryParameters3D.PATHFINDING_ALGORITHM_ASTAR

    var result := NavigationPathQueryResult3D.new()
    NavigationServer3D.query_path(query, result)
    return result.path
```

### Implementation Guidelines

1. **Chunk Navigation Region Setup**
   - Each TerrainChunk creates a NavigationRegion3D in `_ready()`
   - Navigation mesh baked from heightmap + vegetation collision
   - Use `NavigationMesh.add_source_geometry_data()` for per-cell cost modification

2. **Terrain Clearing Updates**
   - When `TerrainClearingSystem` changes cell state, notify owning chunk
   - Chunk marks navigation as dirty, rebakes on next frame
   - Use `WorkerThreadPool` for async rebaking to prevent stalls

3. **Cross-Chunk Linking**
   - NavigationServer3D automatically links adjacent NavigationRegion3D nodes
   - Ensure chunk navigation meshes extend slightly beyond boundaries (0.5m overlap)
   - Edge vertices must align for seamless pathfinding

4. **Road Network Overlay**
   - RoadNetwork maintains separate NavigationRegion3D on layer 1
   - Road segments have travel_cost = 0.3 (lower than any terrain)
   - Convoys query with layers 0b0011 to prefer roads but fall back to terrain

5. **Routing (Fleeing) Units**
   - Use standard NavigationAgent3D targeting nearest firebase
   - Movement speed reduced (see morale-routing.md)
   - Pathfinding ignores enemies (no avoidance of hostiles during flee)

6. **Performance Optimization**
   - Cache navigation queries for static destinations (firebases)
   - Limit path recalculation to every 0.5s per unit
   - Use NavigationAgent3D.avoidance_enabled = false for mass routing

## Alternatives Considered

### Alternative 1: Custom A* Implementation

- **Description**: Build custom pathfinding grid separate from Godot navigation
- **Pros**: Full control over cost functions, no engine API changes risk
- **Cons**: Significant implementation effort, loses engine optimizations
- **Estimated Effort**: 3x compared to NavigationServer3D approach
- **Rejection Reason**: Godot's NavigationServer3D is production-ready and handles chunk linking automatically

### Alternative 2: Single Global Navigation Mesh

- **Description**: One NavigationMesh for entire 3km map
- **Pros**: No chunk boundary handling, simpler implementation
- **Cons**: Cannot stream, memory explosion (8836 cells at once), rebuild time prohibitive
- **Estimated Effort**: 0.5x initial, but unscalable
- **Rejection Reason**: Violates ADR-0001 streaming architecture, fails memory budget

### Alternative 3: Navigation Mesh Per Road Segment

- **Description**: Each road segment gets its own NavigationRegion3D
- **Pros**: Highly granular road updates
- **Cons**: Hundreds of navigation regions, linking complexity, performance overhead
- **Estimated Effort**: 1.5x with ongoing maintenance burden
- **Rejection Reason**: Single RoadNetwork NavigationRegion3D is simpler and sufficient

## Consequences

### Positive

- **Unified pathfinding**: All unit types use NavigationServer3D API consistently
- **Dynamic terrain**: Navigation costs update as terrain is cleared
- **Road preference**: Convoys naturally prefer roads via layer costs
- **Chunk streaming compatible**: Navigation regions load/unload with terrain chunks
- **Flee pathfinding**: Routing units use same system with different target

### Negative

- **Rebake overhead**: Terrain clearing requires async navigation mesh rebuilds
- **Cross-chunk seams**: Edge cases at chunk boundaries require careful handling
- **Two-layer complexity**: Road overlay adds navigation query complexity
- **Memory per chunk**: ~48KB navigation data per loaded chunk (from ADR-0001)

### Neutral

- Navigation mesh resolution (0.5m cell size) balances accuracy vs memory
- Road layer separation means convoy pathfinding is a separate query

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Cross-chunk path discontinuity | Medium | High | Overlap chunk nav meshes by 0.5m, test edge cases |
| Frame stalls on clearing | Medium | Medium | Async rebake via WorkerThreadPool, defer to next frame |
| Convoy ignores roads | Low | Medium | Verify layer costs, test with debug visualization |
| Mass routing performance | Medium | Medium | Disable avoidance for routing units, cap path recalc rate |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|----------------|--------|
| CPU (pathfinding per unit) | N/A | 0.1ms | 2ms total for 500 units |
| Memory (navigation per chunk) | N/A | 48KB | 19.2MB for 400 active chunks |
| Nav rebuild time | N/A | <100ms async | No frame stalls |
| Cross-chunk path query | N/A | <2ms | 5ms max |

## Migration Plan

This is a new system, no migration required. Implementation order:

1. Add NavigationRegion3D to TerrainChunk, bake from heightmap
2. Integrate with TerrainClearingSystem for dynamic updates
3. Implement RoadNetwork overlay navigation
4. Add NavigationAgent3D to Squad and Vehicle base classes
5. Implement convoy road-preferring pathfinding
6. Implement morale routing flee-to-firebase behavior

**Rollback plan**: Revert to placeholder movement (direct-line with collision avoidance) if navigation architecture proves unworkable

## Validation Criteria

- [ ] Units pathfind around JUNGLE terrain without direct movement through
- [ ] Clearing terrain from JUNGLE to CLEARED updates navigation within 1 frame (async)
- [ ] Convoys prefer road paths over direct terrain paths
- [ ] Routing units successfully pathfind to nearest firebase
- [ ] 500 units pathfinding simultaneously maintains 60 FPS
- [ ] Chunk load/unload does not break active paths
- [ ] Cross-chunk paths are seamless (no visible hitching at boundaries)

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|--------------|--------|-------------|---------------------------|
| `design/gdd/morale-routing.md` | Morale | "Units at BROKEN state attempt to flee toward nearest firebase" (Section 3.5) | NavigationAgent3D.target_position set to firebase position; standard pathfinding executes flee |
| `design/gdd/morale-routing.md` | Morale | "Routing units that encounter enemies during retreat attempt to path around" (Section 5.5) | NavigationServer3D handles obstacle avoidance; enemy units not marked as nav obstacles |
| `design/gdd/supply-logistics.md` | Supply | "Truck convoys follow road network from rear depot to firebase" (Section 3.6) | RoadNetwork overlay with layer 1; convoys query with road layer preference |
| `design/gdd/supply-logistics.md` | Supply | "Convoys only travel on cleared roads" (Section 8) | Road layer only exists where roads are built; terrain layer impassable for vehicles in JUNGLE |
| `design/gdd/terrain-clearing.md` | Terrain | "Cleared terrain changes pathfinding costs" (Section 6) | Navigation mesh rebaked on clearing; cost modifiers per terrain state |
| `design/gdd/terrain-clearing.md` | Terrain | "Roads improve vehicle movement speed" (Section 8) | Road layer travel_cost = 0.3, lowest of all terrain types |

## Related

- **ADR-0001** (Terrain Chunk Streaming): Navigation regions align with chunk boundaries
- **ADR-0003** (Spatial Hash Grid): Used for nearby enemy detection during routing, not for pathfinding
- **ADR-0005** (Job System): Road cutting jobs trigger RoadNetwork updates

## Implementation Files

| File | Purpose |
|------|---------|
| `map_maker/terrain_chunk.gd` | Per-chunk NavigationRegion3D management |
| `battle_system/nodes/squad.gd` | NavigationAgent3D for infantry |
| `battle_system/nodes/vehicle.gd` | NavigationAgent3D for vehicles |
| `reinforcement_system/convoy_manager.gd` | Convoy road-preferring pathfinding |
| `firebase_system/road_network.gd` | Road overlay navigation layer |
| `battle_system/systems/morale_system.gd` | Flee pathfinding to firebase |
