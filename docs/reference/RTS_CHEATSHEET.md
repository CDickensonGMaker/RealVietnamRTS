# RTS Architecture Cheatsheet

> Quick reference for RealVietnamRTS. Full details: `rts_architecture_patterns.md`

---

## Pathfinding Decision Matrix

| Units | Use This |
|-------|----------|
| 1-20 | A* + smoothing |
| 20-100 | **Flow Field** |
| 100+ | Flow Field + cache |
| Long distance | HPA* (chunks) |

---

## Spatial Grid

```
cell_size = 16.0  # meters (matches weapon range)
```

```gdscript
# Query pattern
func get_enemies_in_range(pos: Vector3, range: float) -> Array[Unit]:
    return spatial_grid.query_radius(pos, range)
```

---

## Update Budget

| Priority | Interval | When |
|----------|----------|------|
| CRITICAL | 1 frame | In combat |
| HIGH | 2 frames | Near camera |
| NORMAL | 4 frames | Default |
| LOW | 8 frames | Far away |
| DORMANT | 30 frames | Off-screen |

**Frame budget:** 2-3ms for unit updates

---

## MultiMesh Rendering

- One MultiMesh per unit type
- Thousands of instances in single draw call

| Distance | Animation LOD |
|----------|---------------|
| 0-30m | Full |
| 30-80m | Every 3 frames |
| 80-150m | Key poses |
| 150m+ | Frozen |

---

## Formation Types

| Type | Use Case |
|------|----------|
| Line | Defense |
| Column | March/roads |
| Wedge | Assault |
| Square | All-around |

---

## State Machine Pattern

```gdscript
# Flyweight: shared logic, per-unit state reference
var current_state: StringName = &"idle"

# Stack-based for interrupts
var state_stack: Array[StringName] = [&"move"]
# Attack interrupts → push(&"attack_back")
# Done → pop() back to move
```

---

## Key Plugins

| Plugin | Purpose |
|--------|---------|
| Godot-4-VectorFieldNavigation | Flow fields |
| godot-open-rts | Fog of war reference |
| AnimatedMultimeshInstance3D | GPU animations |
| Terrain3D | C++ terrain |

---

## Sources

- OpenSAGE (C&C Generals): Sleepy updates, spatial grid
- OpenRTS (Java): Flow fields, steering, formations
- Supreme Commander 2: Flow field architecture
- Full research: `rts_architecture_patterns.md`
