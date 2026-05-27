# RTS Architecture Toolbox Research

**Date:** 2026-05-26
**Session Type:** Technical Research & Pattern Mining
**Sources:** OpenSAGE, OpenRTS, Godot Plugins, Industry Case Studies

---

## Executive Summary

Deep investigation into RTS codebases yielded a comprehensive toolbox of patterns ready for deployment. Key findings organized by problem domain.

---

## PART 1: PATHFINDING DECISION MATRIX

### When to Use What

| Scenario | Solution | Compute Time | Notes |
|----------|----------|--------------|-------|
| Single unit, unique destination | A* with smoothing | ~0.1ms | Use Godot's NavigationServer |
| 5-20 units, same destination | Shared A* + formation offsets | ~0.5ms | Leader pathfinds, others follow |
| 20-100 units, same destination | **Flow Field** | ~10-30ms initial | Cache by destination |
| 100+ units | Flow Field + sector caching | ~50ms+ | Regenerate rarely |
| Long-distance across map | **HPA*** (Hierarchical) | ~1ms | Chunk-based abstraction |

### Flow Field Architecture (Supreme Commander 2 Style)

Three layers computed from destination outward:

```
┌─────────────────────────────────────────────┐
│ COST FIELD - Static terrain costs (1-254)  │
│ 255 = impassable (water, cliffs, buildings)│
├─────────────────────────────────────────────┤
│ INTEGRATION FIELD - Dijkstra distances     │
│ BFS flood from goal, propagate costs       │
├─────────────────────────────────────────────┤
│ FLOW FIELD - Direction vectors per cell    │
│ Each cell points toward lowest-cost neighbor│
└─────────────────────────────────────────────┘
```

**Key Insight (OpenRTS):** Cache flow fields by `(destination, cost_field_version)`. Most RTS games have only a handful of unique destinations at any time.

### GDScript Flow Field Implementation

```gdscript
# flow_field.gd
class_name FlowField extends RefCounted

const IMPASSABLE := 255
const MAX_COST := 65535

var grid_size: Vector2i
var cost_field: PackedByteArray      # Terrain costs
var integration_field: PackedInt32Array  # Distance from goal
var flow_field: PackedByteArray      # Direction indices (0-7)

const DIRECTIONS := [
    Vector2i(0, -1),   # 0: North
    Vector2i(1, -1),   # 1: Northeast
    Vector2i(1, 0),    # 2: East
    Vector2i(1, 1),    # 3: Southeast
    Vector2i(0, 1),    # 4: South
    Vector2i(-1, 1),   # 5: Southwest
    Vector2i(-1, 0),   # 6: West
    Vector2i(-1, -1),  # 7: Northwest
]

func generate(goal: Vector2i) -> void:
    _generate_integration_field(goal)
    _generate_flow_field()

func _generate_integration_field(goal: Vector2i) -> void:
    integration_field.fill(MAX_COST)

    var open_list: Array[Vector2i] = [goal]
    integration_field[_index(goal)] = 0

    while not open_list.is_empty():
        var current: Vector2i = open_list.pop_front()
        var current_cost: int = integration_field[_index(current)]

        for dir in DIRECTIONS:
            var neighbor := current + dir
            if not _is_valid(neighbor):
                continue

            var neighbor_idx := _index(neighbor)
            var terrain_cost: int = cost_field[neighbor_idx]

            if terrain_cost == IMPASSABLE:
                continue

            var new_cost := current_cost + terrain_cost
            if new_cost < integration_field[neighbor_idx]:
                integration_field[neighbor_idx] = new_cost
                open_list.append(neighbor)

func get_direction(world_pos: Vector3) -> Vector3:
    var grid_pos := _world_to_grid(world_pos)
    var dir_idx := flow_field[_index(grid_pos)]
    if dir_idx == 255:
        return Vector3.ZERO
    return Vector3(DIRECTIONS[dir_idx].x, 0, DIRECTIONS[dir_idx].y)

func _index(pos: Vector2i) -> int:
    return pos.y * grid_size.x + pos.x

func _is_valid(pos: Vector2i) -> bool:
    return pos.x >= 0 and pos.x < grid_size.x and pos.y >= 0 and pos.y < grid_size.y
```

### Local Avoidance Layer (ORCA)

Strategic pathfinding tells WHERE to go. ORCA tells HOW without collisions.

```
Unit Movement Pipeline:
1. Flow Field/A* → preferred_velocity
2. ORCA constraints → collision-free velocity
3. CharacterBody3D.move_and_slide() → actual movement
```

### Recommended Godot Plugins

| Plugin | Use Case | URL |
|--------|----------|-----|
| **Godot-4-VectorFieldNavigation** | Flow fields | github.com/D2klaas/Godot-4-VectorFieldNavigation |
| **godot-tilemap-flowfields** | 2D tilemap flow | github.com/arnemileswinter/godot-tilemap-flowfields |
| **steering-behaviors-godot-4** | Flocking/ORCA | github.com/konbel/steering-behaviors-godot-4 |

---

## PART 2: SPATIAL PARTITIONING

### Grid vs Quadtree Decision

**Use Uniform Grid (RECOMMENDED):**
- Constant-time cell lookup O(1)
- Predictable memory access patterns
- Better for uniform unit distribution
- Simpler implementation

**Use Quadtree only if:**
- Highly clustered units
- Variable density across map
- Need recursive subdivision

### Optimal Cell Size

```
cell_size = max(weapon_range, detection_range, unit_spacing)
```

For RealVietnamRTS with ~10-15m weapon ranges: **cell_size = 16.0 meters**

### GDScript Spatial Hash Grid

```gdscript
# spatial_hash_grid.gd
class_name SpatialHashGrid extends RefCounted

var _cell_size: float
var _cells: Dictionary = {}  # Vector2i -> Array[Unit]
var _unit_cells: Dictionary = {}  # Unit -> Vector2i

func _init(cell_size: float = 16.0) -> void:
    _cell_size = cell_size

func _get_cell(world_pos: Vector3) -> Vector2i:
    return Vector2i(
        int(floor(world_pos.x / _cell_size)),
        int(floor(world_pos.z / _cell_size))
    )

func insert(unit: Unit) -> void:
    var cell := _get_cell(unit.global_position)
    if not _cells.has(cell):
        _cells[cell] = []
    _cells[cell].append(unit)
    _unit_cells[unit] = cell

func remove(unit: Unit) -> void:
    if _unit_cells.has(unit):
        var cell: Vector2i = _unit_cells[unit]
        if _cells.has(cell):
            _cells[cell].erase(unit)
        _unit_cells.erase(unit)

func update_position(unit: Unit) -> void:
    var old_cell: Vector2i = _unit_cells.get(unit, Vector2i(-99999, -99999))
    var new_cell := _get_cell(unit.global_position)
    if old_cell != new_cell:
        remove(unit)
        insert(unit)

func query_radius(center: Vector3, radius: float) -> Array[Unit]:
    var results: Array[Unit] = []
    var center_cell := _get_cell(center)
    var cell_radius := int(ceil(radius / _cell_size))
    var radius_sq := radius * radius

    for x in range(center_cell.x - cell_radius, center_cell.x + cell_radius + 1):
        for y in range(center_cell.y - cell_radius, center_cell.y + cell_radius + 1):
            var cell := Vector2i(x, y)
            if _cells.has(cell):
                for unit in _cells[cell]:
                    if center.distance_squared_to(unit.global_position) <= radius_sq:
                        results.append(unit)
    return results
```

### 5x5 Neighborhood Pattern (OpenRTS)

Most combat queries only need immediate neighbors. Hardcode the pattern:

```gdscript
func get_nearby_enemies(pos: Vector3, range: float) -> Array[Unit]:
    var cell := _get_cell(pos)
    var results: Array[Unit] = []

    for dx in range(-2, 3):  # 5x5 grid
        for dy in range(-2, 3):
            var check := Vector2i(cell.x + dx, cell.y + dy)
            if _cells.has(check):
                for unit in _cells[check]:
                    if _is_enemy(unit) and pos.distance_to(unit.global_position) <= range:
                        results.append(unit)
    return results
```

---

## PART 3: UPDATE BUDGETING

### The Sleepy Update Pattern (OpenSAGE)

Not all units need updates every frame. Each module schedules its next update.

```gdscript
# priority_update_scheduler.gd
class_name PriorityUpdateScheduler extends Node

enum Priority { CRITICAL, HIGH, NORMAL, LOW, DORMANT }

const INTERVALS := {
    Priority.CRITICAL: 1,   # Every frame (in combat)
    Priority.HIGH: 2,       # Every 2 frames (near camera)
    Priority.NORMAL: 4,     # Every 4 frames (standard)
    Priority.LOW: 8,        # Every 8 frames (far)
    Priority.DORMANT: 30,   # Every 30 frames (off-screen)
}

var _buckets: Dictionary = {}  # Priority -> Array[Unit]
var _frame: int = 0

func _physics_process(_delta: float) -> void:
    _frame += 1
    for priority in Priority.values():
        var interval: int = INTERVALS[priority]
        if _frame % interval == 0:
            for unit in _buckets.get(priority, []):
                unit.tick_update()

func calculate_priority(unit: Unit, camera_pos: Vector3, hotspots: Array[Vector3]) -> Priority:
    var dist := unit.global_position.distance_to(camera_pos)

    if unit.is_in_combat():
        return Priority.CRITICAL
    elif dist < 50.0 or _near_hotspot(unit.global_position, hotspots):
        return Priority.HIGH
    elif dist < 150.0:
        return Priority.NORMAL
    elif dist < 300.0:
        return Priority.LOW
    else:
        return Priority.DORMANT

func _near_hotspot(pos: Vector3, hotspots: Array[Vector3]) -> bool:
    for hs in hotspots:
        if pos.distance_squared_to(hs) < 10000.0:  # 100m
            return true
    return false
```

### Time-Slicing Budget

```
Frame Budget (60 FPS): 16.67ms total
├── Rendering: ~8ms
├── Physics: ~4ms
├── Unit Updates: 2-3ms  ← Your budget
└── Pathfinding: 1-2ms
```

Process units until budget exhausted, resume next frame:

```gdscript
const BUDGET_MS := 2.0
var _current_index: int = 0

func _physics_process(_delta: float) -> void:
    var start := Time.get_ticks_usec()
    var budget_usec := int(BUDGET_MS * 1000.0)

    while _current_index < units.size():
        units[_current_index].update()
        _current_index += 1

        if Time.get_ticks_usec() - start >= budget_usec:
            break  # Resume next frame

    if _current_index >= units.size():
        _current_index = 0
```

---

## PART 4: PRODUCTION & BUILD QUEUES

### OpenSAGE Production Pattern

```gdscript
# production_job.gd
class_name ProductionJob extends RefCounted

var template_name: StringName
var progress_frames: int = 0
var build_time_frames: int
var quantity: int = 1
var produced: int = 0

func tick() -> int:  # Returns: 0=in_progress, 1=unit_complete, 2=batch_complete
    progress_frames += 1
    if progress_frames >= build_time_frames:
        produced += 1
        progress_frames = 0
        if produced >= quantity:
            return 2  # BATCH_COMPLETE
        return 1  # UNIT_COMPLETE
    return 0  # IN_PROGRESS
```

### Building Placement Validation (OpenSAGE)

1. Create **ghost preview** (transparent, no collision)
2. Query spatial grid for overlapping structures
3. Check terrain flatness/slope
4. Check shroud/fog visibility
5. Verify path accessibility to build site

```gdscript
func validate_placement(pos: Vector3, footprint: Rect2, rotation: float) -> Dictionary:
    var result := {
        "valid": true,
        "reason": "",
        "needs_clearing": false,
        "blocked_by": []
    }

    # Ask terrain (per synthesis.md architecture)
    var terrain_query := TerrainEngine.query_build_site(pos, footprint, rotation)

    if not terrain_query.flat_enough:
        result.valid = false
        result.reason = "Ground too steep"
        return result

    if terrain_query.has_vegetation:
        result.needs_clearing = true
        result.blocked_by = terrain_query.blocking_trees

    # Check for overlapping structures
    var overlaps := spatial_grid.query_rect(pos, footprint)
    for obj in overlaps:
        if obj.is_structure:
            result.valid = false
            result.reason = "Overlaps existing structure"
            result.blocked_by.append(obj)

    return result
```

---

## PART 5: LARGE BATTLE RENDERING

### MultiMesh Strategy

One MultiMesh per unit type. Each handles up to 2000+ instances.

```gdscript
# multimesh_unit_renderer.gd
class_name MultiMeshUnitRenderer extends MultiMeshInstance3D

var _unit_indices: Dictionary = {}  # Unit -> int
var _active_count: int = 0

func add_unit(unit: Unit) -> void:
    var idx := _active_count
    _unit_indices[unit] = idx
    _active_count += 1
    multimesh.visible_instance_count = _active_count
    update_transform(unit)

func update_transform(unit: Unit) -> void:
    var idx: int = _unit_indices.get(unit, -1)
    if idx >= 0:
        multimesh.set_instance_transform(idx, unit.global_transform)

func batch_update(units: Array[Unit]) -> void:
    for unit in units:
        update_transform(unit)
```

### Animation LOD Thresholds

| Distance | LOD | Update Rate |
|----------|-----|-------------|
| 0-30m | FULL | Every frame |
| 30-80m | REDUCED | Every 3 frames |
| 80-150m | MINIMAL | Key poses only |
| 150m+ | FROZEN | Static pose |

### Recommended Plugins

| Plugin | Purpose |
|--------|---------|
| **AnimatedMultimeshInstance3D** | GPU-baked animations, thousands of units |
| **Terrain3D** | High-performance C++ terrain |
| **godot-open-rts** | Reference fog of war implementation |

---

## PART 6: FORMATION MOVEMENT

### Architecture

```
Formation Anchor (invisible leader)
├── Has own pathfinding
├── Defines center + rotation
└── Slots[] (relative offsets)
    ├── Slot 0 → Unit A (assigned by distance)
    ├── Slot 1 → Unit B
    └── Slot N → Unit N

Units use Arrive steering toward their slot position.
```

### Formation Types

| Type | Use Case | Shape |
|------|----------|-------|
| Line | Defense, holding | ━━━━━ |
| Column | March, roads | ┃ |
| Wedge | Assault | ◁ |
| Square | All-around defense | ▢ |

### Slot Assignment

Hungarian algorithm simplified: Assign by distance.

```gdscript
func assign_units(units: Array[Unit], slots: Array[Vector3]) -> Dictionary:
    var assignments := {}
    var remaining_units := units.duplicate()
    var remaining_slots := slots.duplicate()

    while not remaining_units.is_empty():
        var best_unit: Unit
        var best_slot: Vector3
        var best_dist := INF

        for unit in remaining_units:
            for slot in remaining_slots:
                var dist := unit.global_position.distance_squared_to(slot)
                if dist < best_dist:
                    best_dist = dist
                    best_unit = unit
                    best_slot = slot

        assignments[best_unit] = best_slot
        remaining_units.erase(best_unit)
        remaining_slots.erase(best_slot)

    return assignments
```

---

## PART 7: STATE MACHINE PATTERNS

### Flyweight Pattern (OpenRTS)

State logic is **shared** (singleton), state data is **per-unit**.

```gdscript
# States are static classes (no instance data)
class IdleState:
    static func tick(unit: Unit) -> StringName:
        if unit.has_target():
            return &"pursuing"
        return &"idle"

class PursuingState:
    static func tick(unit: Unit) -> StringName:
        if not unit.has_target():
            return &"idle"
        if unit.is_in_attack_range():
            return &"attacking"
        unit.move_toward_target()
        return &"pursuing"

# Per-unit: just a state reference
var current_state: StringName = &"idle"
var states: Dictionary = {
    &"idle": IdleState,
    &"pursuing": PursuingState,
    &"attacking": AttackingState,
}

func tick() -> void:
    var next := states[current_state].tick(self)
    if next != current_state:
        current_state = next
        states[next].enter(self)
```

### Stack-Based FSM (OpenRTS)

Allows layered behaviors:

```gdscript
var state_stack: Array[StringName] = [&"idle"]

func push_state(state: StringName) -> void:
    state_stack.push_front(state)

func pop_state() -> void:
    state_stack.pop_front()

func current_state() -> StringName:
    return state_stack[0]

# Example: Attack interrupts movement, then returns
# Stack: [&"move_to"]
# Enemy appears → push(&"attack_back")
# Stack: [&"attack_back", &"move_to"]
# Enemy killed → pop()
# Stack: [&"move_to"]  # Resumes previous behavior
```

---

## PART 8: UTILITY AI FOR TARGET SELECTION

Better than rule cascades for complex prioritization:

```gdscript
# utility_target_selector.gd
class_name UtilityTargetSelector extends RefCounted

func select_target(attacker: Unit, targets: Array[Unit]) -> Unit:
    var best: Unit = null
    var best_score := 0.0

    for target in targets:
        var score := 1.0

        # Distance (closer = higher)
        var dist := attacker.global_position.distance_to(target.global_position)
        score *= clampf(1.0 - (dist / attacker.max_range * 2.0), 0.1, 1.0)

        # Health (wounded = higher priority for focus fire)
        score *= (1.0 - target.health_percent) * 0.5 + 0.5

        # Threat (dangerous enemies = higher)
        if target.is_threat_to(attacker):
            score *= 1.5

        # Counter bonus
        if target.unit_type in attacker.bonus_vs:
            score *= 1.4

        if score > best_score:
            best_score = score
            best = target

    return best
```

---

## ACTIONABLE ITEMS FOR REALVIETNAMRTS

### Immediate (This Sprint)

1. **Implement SpatialHashGrid** (Part 2)
   - Replace all "enemies in range" queries
   - 16m cell size

2. **Add Priority Update Scheduler** (Part 3)
   - 5 priority tiers
   - Camera distance + combat proximity

3. **Production Queue Refactor** (Part 4)
   - Frame-based progress
   - Batch production support

### Next Sprint

4. **Flow Field System** (Part 1)
   - For firebase resupply convoys (many units, same destination)
   - Cache per supply depot location

5. **MultiMesh Unit Rendering** (Part 5)
   - One per unit type
   - Animation LOD manager

### Future

6. **HPA* Integration** (Part 1)
   - For long-distance strategic movement
   - Chunk-based path caching

7. **ORCA Local Avoidance** (Part 1)
   - For dense unit formations
   - Convoy collision prevention

---

## SOURCE REFERENCES

### Open Source Projects
- OpenSAGE: github.com/OpenSAGE/OpenSAGE
- OpenRTS: github.com/methusalah/OpenRTS

### Godot Plugins
- Flow Fields: github.com/D2klaas/Godot-4-VectorFieldNavigation
- RTS Framework: github.com/rluders/rts-framework
- Open RTS: github.com/lampe-games/godot-open-rts
- MultiMesh Animation: github.com/shadecoredev/AnimatedMultimeshInstance3D
- Terrain3D: github.com/TokisanGames/Terrain3D

### Industry Case Studies
- Supreme Commander 2 Flow Fields (GDC)
- StarCraft 2 Pathfinding Discussion
- Total War Engine Analysis (AMD GPUOpen)
- Game AI Pro Chapter 23 (Flow Field Tiles)
- ORCA Algorithm (UNC)

---

*Research complete. Patterns ready for deployment at the Summoner's command.*
