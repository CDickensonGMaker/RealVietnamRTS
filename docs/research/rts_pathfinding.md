# RTS Pathfinding Systems Research

## Sources
- [How to RTS: Basic Flow Fields](https://howtorts.github.io/2014/01/04/basic-flow-fields.html)
- [Game AI Pro - Flow Field Tiles](https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter23_Crowd_Pathfinding_and_Steering_Using_Flow_Field_Tiles.pdf)
- [Group Pathfinding in RTS Games](https://www.gamedeveloper.com/programming/group-pathfinding-movement-in-rts-style-games)
- [Flow Fields - jdxdev](https://www.jdxdev.com/blog/2020/05/03/flowfields/)

---

## Pathfinding Approaches Comparison

| Approach | Best For | Pros | Cons |
|----------|----------|------|------|
| A* | Single units | Precise, well-understood | Expensive per-unit |
| NavMesh | Modern 3D games | Efficient, handles large areas | Complex generation |
| Flow Field | Mass unit movement | Scales to thousands | Memory intensive |
| Hierarchical | Large maps | Fast long-distance | Less precise locally |

---

## Flow Fields (Supreme Commander 2, Planetary Annihilation)

### How Flow Fields Work

1. **Cost Field** - Grid where each cell has movement cost
2. **Integration Field** - Dijkstra from goal, stores distance-to-goal
3. **Flow Field** - Vector at each cell pointing toward goal
4. **Agent Movement** - Units read local cell vector, apply to velocity

### Algorithm Steps

```
1. Mark goal cell with cost 0
2. Wavefront expansion (Dijkstra):
   - For each neighbor of current cell
   - new_cost = current_cost + movement_cost
   - If new_cost < neighbor_cost: update
3. Generate vectors:
   - For each cell, find lowest-cost neighbor
   - Vector points toward that neighbor
4. Movement:
   - Unit reads vector at current cell
   - Applies vector to velocity
```

### Memory Optimization: Flow Field Tiling

**Problem:** Full-map flow field too large for memory

**Solution (Supreme Commander 2):**
- Divide map into sectors (10x10 grid squares)
- Only generate flow fields for sectors agents traverse
- Portals connect adjacent sectors
- Hierarchical A* determines which sectors to calculate

### Advantages
- Scales to hundreds/thousands of units
- Dynamic obstacle avoidance is trivial
- All units share single flow field per destination
- Natural crowd behavior

### Disadvantages
- High initial computation cost
- Memory usage for large maps
- Less precise than individual A* paths

---

## Navigation Meshes (StarCraft II)

### NavMesh Structure
- Convex polygons covering walkable space
- Edges connect adjacent polygons
- Units move freely inside polygons
- Path is sequence of polygon transitions

### Benefits
- Handles complex terrain efficiently
- Polygons can be large (saves computation)
- Path smoothing built-in (funnel algorithm)

### StarCraft II Specifics
- Uses hierarchical planning
- Local steering for collision avoidance
- Flocking behavior for group movement

---

## Hybrid Approach (Recommended)

### Architecture
```
Global Planning (A* or Hierarchical)
        ↓
    Path Waypoints
        ↓
Local Flow Fields (per sector)
        ↓
    Steering Behaviors
        ↓
    Final Movement
```

### Components

1. **Global Planner** - High-level path (A* on coarse grid)
2. **Sector Flow Fields** - Local direction for mass movement
3. **Steering Behaviors** - Collision avoidance, separation
4. **Formation Manager** - Group shape maintenance

---

## Steering Behaviors

### Core Behaviors
- **Seek** - Move toward target
- **Flee** - Move away from threat
- **Arrive** - Seek with deceleration
- **Separation** - Avoid crowding
- **Alignment** - Match neighbor heading
- **Cohesion** - Stay with group

### Combined Force
```gdscript
func calculate_steering() -> Vector3:
    var force := Vector3.ZERO

    force += seek(target) * SEEK_WEIGHT
    force += separation(neighbors) * SEPARATION_WEIGHT
    force += alignment(neighbors) * ALIGNMENT_WEIGHT

    return force.limit_length(MAX_FORCE)
```

---

## Applicability to RealVietnamRTS

### Current Implementation
Already have:
- `_calculate_separation()` in Squad
- `SpatialHashGrid` for neighbor queries
- Basic `move_to()` with direct movement

### Recommended Enhancements

#### 1. Simple Flow Field for Mass Movement
```gdscript
class_name FlowField extends Node

var grid_size: int = 128
var cell_size: float = 2.0
var vectors: Array[Vector3] = []

func generate(goal: Vector3) -> void:
    var goal_cell = _world_to_cell(goal)
    var costs = _dijkstra_from(goal_cell)
    _generate_vectors(costs)

func get_direction(world_pos: Vector3) -> Vector3:
    var cell = _world_to_cell(world_pos)
    return vectors[_cell_to_index(cell)]
```

#### 2. Path Caching
```gdscript
class_name PathCache extends Node

var cached_paths: Dictionary = {}  # {goal_cell: FlowField}
var cache_ttl: float = 5.0  # Seconds before invalidation

func get_or_create(goal: Vector3) -> FlowField:
    var cell = _world_to_cell(goal)
    if cell in cached_paths:
        return cached_paths[cell]

    var field = FlowField.new()
    field.generate(goal)
    cached_paths[cell] = field
    return field
```

#### 3. Hierarchical Planning for Large Maps
```gdscript
class_name HierarchicalPathfinder extends Node

# Coarse grid for long-distance planning
var sector_size: float = 50.0
var sector_connections: Dictionary = {}

func plan_route(start: Vector3, goal: Vector3) -> Array[Vector3]:
    var start_sector = _get_sector(start)
    var goal_sector = _get_sector(goal)

    # A* on sector level
    var sector_path = _astar_sectors(start_sector, goal_sector)

    # Convert to waypoints
    var waypoints: Array[Vector3] = []
    for sector in sector_path:
        waypoints.append(_sector_center(sector))

    return waypoints
```

### Vietnam-Specific Considerations

1. **Terrain Costs** - Jungle = high cost, roads = low cost
2. **Dynamic Obstacles** - Burning areas, artillery craters
3. **Ambush Detection** - AI uses flow field to predict player routes
4. **Trail Networks** - Pre-built paths through jungle (low cost)

### Performance Budget

| Unit Count | Recommended Approach |
|------------|---------------------|
| < 50 | Individual A* + steering |
| 50-200 | Cached A* + flow fields for mass moves |
| 200+ | Full flow field system |

For RealVietnamRTS target of 300-500 units, a hybrid flow field system is appropriate.
