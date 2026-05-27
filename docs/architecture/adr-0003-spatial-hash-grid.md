# ADR-0003: Spatial Hash Grid

## Status
Accepted

## Context
- Need efficient spatial queries for 300-500 units
- Combat requires finding nearby enemies quickly
- AI needs area awareness without O(n^2) checks
- Must support dynamic unit movement

The RealVietnamRTS game requires real-time spatial queries for:
1. **Target acquisition** - Units must find enemies within weapon range
2. **Area threat assessment** - AI directors evaluate force concentrations
3. **Faction filtering** - Distinguish friendlies from hostiles efficiently
4. **Formation queries** - Find nearby friendly units for cohesion

Traditional approaches (iterating all units, quad-trees) either scale poorly or add complexity unnecessary for this unit count range.

## Decision
- **SpatialHashGrid autoload singleton** registered at `battle_system/ai/spatial_hash_grid.gd`
- **Cell-based hashing** with configurable cell size (20m cells via `GridCoords.SPATIAL_CELL_SIZE`)
- **O(1) average lookup** for units in area using `Dictionary[Vector2i, Array[Node3D]]`
- **Automatic position updates** via `_process()` - units don't manually notify on movement
- **Signal-driven registration** - connects to `BattleSignals.unit_spawned` and `unit_died`

### Core Data Structures
```gdscript
var _cells: Dictionary = {}        # Vector2i -> Array[Node3D]
var _unit_cells: Dictionary = {}   # Node3D -> Vector2i
var _unit_factions: Dictionary = {} # Node3D -> faction
```

### Query Methods
| Method | Purpose | Complexity |
|--------|---------|------------|
| `get_units_in_radius(pos, radius, faction_filter)` | All units in radius | O(cells * units_per_cell) |
| `get_enemies_in_radius(pos, radius, my_faction)` | Enemy units only | O(cells * units_per_cell) |
| `get_nearest_enemy(pos, my_faction, max_range)` | Closest hostile | O(cells * units_per_cell) |
| `get_friendlies_in_radius(pos, radius, my_faction)` | Allied units | O(cells * units_per_cell) |
| `get_unit_count_in_area(min_pos, max_pos, faction)` | Count in rectangle | O(cells * units_per_cell) |
| `register_unit(unit, faction)` | Add to grid | O(1) |
| `unregister_unit(unit)` | Remove from grid | O(1) |

### Position to Cell Conversion
```gdscript
func _get_cell(position: Vector3) -> Vector2i:
    return Vector2i(
        int(floor(position.x / CELL_SIZE)),
        int(floor(position.z / CELL_SIZE))
    )
```

## Consequences

### Positive
- **Constant-time spatial queries** - Only check cells that could contain results
- **Scales well with unit count** - Performance independent of total units, depends on local density
- **Supports faction filtering** - Built-in faction tracking eliminates separate lookups
- **Automatic cell migration** - Units automatically move between cells as they traverse the map
- **Distance-squared optimization** - Avoids sqrt in hot paths
- **Dead unit cleanup** - Handles invalid references gracefully in `_update_unit_positions()`

### Negative
- **Must keep hash updated on unit movement** - `_process()` runs every frame to check migrations
- **Cell size tuning affects performance** - Too small = many cells checked; too large = many units per cell
- **Memory overhead for sparse areas** - Empty cells still exist if units passed through
- **No spatial sorting within cells** - Nearest queries still iterate all units in checked cells

### Cell Size Trade-offs
| Cell Size | Pros | Cons |
|-----------|------|------|
| 10m | Fewer units per cell | More cells to check for large radii |
| 20m (current) | Balanced for typical weapon ranges | Standard choice |
| 40m | Fewer cells for artillery queries | More units to filter per cell |

The 20m cell size aligns with typical infantry weapon engagement ranges (300m = 15 cells radius) and provides a good balance for the expected unit density.

## ADR Dependencies
None (foundational)

This is a foundational system with no dependencies on other architectural decisions. Other systems depend on it:
- Combat targeting uses `get_nearest_enemy()` and `get_enemies_in_radius()`
- AI threat assessment uses `get_unit_count_in_area()`
- Formation systems use `get_friendlies_in_radius()`

## Engine Compatibility
**Godot 4.6** - Pure GDScript, no engine dependencies

The implementation uses only standard GDScript features:
- `Dictionary` with `Vector2i` keys
- `Array[Node3D]` typed arrays
- `is_instance_valid()` for reference checking
- Standard `Node._process()` lifecycle

No GDExtension, no C# interop, no engine-specific spatial partitioning (like Godot's octree) required.

## GDD Requirements Addressed

### combat-system.md: Target Acquisition
- `get_nearest_enemy()` provides fast target selection
- `get_enemies_in_radius()` supports area weapons and suppression effects
- Faction filtering ensures units only target valid enemies

### ai-director.md: Area Threat Assessment
- `get_unit_count_in_area()` enables force concentration analysis
- `get_enemies_in_radius()` from strategic points measures threat levels
- Faction-aware queries support multi-faction scenarios (US vs VC vs NVA)

## Implementation Notes

### Registration Flow
```
BattleSignals.unit_spawned(unit, faction)
    -> SpatialHashGrid._on_unit_spawned(unit, faction)
        -> register_unit(unit, faction)
            -> _get_cell(unit.global_position)
            -> Add to _cells, _unit_cells, _unit_factions
```

### Query Flow
```
get_enemies_in_radius(position, radius, my_faction)
    -> Calculate cells_to_check from radius/CELL_SIZE
    -> For each cell in range:
        -> Skip if cell not in _cells
        -> For each unit in cell:
            -> Skip if invalid or same faction
            -> Check distance_squared <= radius_squared
            -> Add to result array
```

### Performance Characteristics
- **Best case**: Query in empty area = O(1)
- **Typical case**: 300 units across map, query radius 50m = ~6 cells * ~3 units = 18 checks
- **Worst case**: All units clustered in query area = O(n) but still faster than global iteration

## Related Files
- `battle_system/ai/spatial_hash_grid.gd` - Implementation
- `battle_system/signals/battle_signals.gd` - Registration signals
- `terrain/core/grid_coords.gd` - `SPATIAL_CELL_SIZE` constant
