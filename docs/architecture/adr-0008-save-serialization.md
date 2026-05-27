# ADR-0008: Save/Serialization System

## Status
Proposed

> **Note:** Full implementation deferred to Phase 7 (Post-MVP). This ADR establishes the architecture and contracts that all systems must follow now to enable serialization later.

## Context

RealVietnamRTS requires comprehensive save/load functionality to support:

- **Campaign Persistence (D-305)**: The persistent expanding map campaign requires all terrain modifications, buildings, and unit state to carry forward across 10 missions
- **Terrain Modifications**: Roads cut, jungle cleared, craters formed - all must persist
- **Firebase Networks**: Building positions, upgrade levels, and influence zones
- **Supply Chain State**: Depot inventories, road network graphs, scheduled convoys
- **Unit State**: Veterancy, casualties, loadouts, current orders

Per D-106, mid-mission save/load is deferred to post-MVP, but all systems must be written with serialization-friendly patterns from day one. This ADR documents those patterns and the contracts systems must implement.

### Constraints

1. **No Direct Node References**: Nodes cannot be serialized directly; must use paths or IDs
2. **Deterministic State Machines**: State must be reconstructable from serialized data
3. **Campaign Continuity**: Mission N's starting state = Mission N-1's ending state + fog reset
4. **Memory Efficiency**: Serialization must not require full map in memory (chunk-based)
5. **Corruption Resistance**: Partial save failure must not corrupt entire campaign

## Decision

### Serialization Contract

All systems requiring persistence MUST implement the `Serializable` interface:

```gdscript
## Interface contract for all serializable systems
## Systems must implement both methods

## Returns all state required to reconstruct this object
func serialize() -> Dictionary:
    push_error("serialize() not implemented")
    return {}

## Reconstructs object state from serialized data
## Returns true on success, false on validation failure
func deserialize(data: Dictionary) -> bool:
    push_error("deserialize() not implemented")
    return false
```

### Version Headers

All serialized data includes a version header for migration support:

```gdscript
const SAVE_VERSION := 1

func serialize() -> Dictionary:
    return {
        "_version": SAVE_VERSION,
        "_system": "TerrainEngine",
        "_timestamp": Time.get_unix_time_from_system(),
        # ... system-specific data
    }
```

### Systems Requiring Serialization

| System | Priority | Data Persisted | Estimated Size |
|--------|----------|----------------|----------------|
| TerrainEngine | Critical | Heightmap mods, clearing states, crater positions | ~2-8 MB per chunk set |
| FirebaseSystem | Critical | Buildings, positions, upgrade levels, influence radii | ~50 KB per firebase |
| SupplyChainManager | Critical | Depots, inventories, road network graph, scheduled convoys | ~100 KB |
| Squad | High | Veterancy, casualties, loadout, current orders, position | ~1 KB per squad |
| JobSystem | High | Queued jobs, progress percentages, assigned workers | ~2 KB per active job |
| DeckSystem | Medium | Unlocked cards, available reinforcements, cooldowns | ~5 KB |
| VCController | Medium | Active tunnels, spawn timers, cached supplies | ~20 KB |
| MissionState | Critical | Objectives, timers, win/loss flags, revealed fog | ~10 KB |

### Serialization Patterns by System

#### TerrainEngine Serialization

```gdscript
# Per-chunk terrain state serialization
func serialize_chunk(chunk: TerrainChunk) -> Dictionary:
    return {
        "coords": [chunk.coords.x, chunk.coords.y],
        "states": _pack_terrain_states(chunk),      # PackedByteArray
        "clearing_progress": _pack_clearing(chunk),  # PackedFloat32Array
        "craters": _serialize_craters(chunk),
        "modified_heights": _serialize_height_deltas(chunk),
    }

# Only serialize modified chunks (not pristine jungle)
func serialize() -> Dictionary:
    var modified_chunks: Array[Dictionary] = []
    for chunk in _get_modified_chunks():
        modified_chunks.append(serialize_chunk(chunk))
    return {
        "_version": SAVE_VERSION,
        "_system": "TerrainEngine",
        "modified_chunks": modified_chunks,
        "road_network": _road_network.serialize(),
    }
```

#### Firebase Serialization

```gdscript
func serialize() -> Dictionary:
    return {
        "_version": SAVE_VERSION,
        "_system": "Firebase",
        "id": firebase_id,
        "position": [global_position.x, global_position.y, global_position.z],
        "level": current_level,  # PATROL_BASE, FIRE_SUPPORT_BASE, MAJOR_FIREBASE
        "influence_radius": influence_radius,
        "buildings": _serialize_buildings(),
        "supply_inventory": supply_inventory,
        "is_player_controlled": is_player_controlled,
    }

func _serialize_buildings() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for building in buildings:
        result.append({
            "type": building.building_type,
            "position": [building.position.x, building.position.y, building.position.z],
            "rotation": building.rotation.y,
            "health": building.current_health,
            "construction_progress": building.construction_progress,
        })
    return result
```

#### Squad Serialization

```gdscript
func serialize() -> Dictionary:
    return {
        "_version": SAVE_VERSION,
        "_system": "Squad",
        "id": squad_id,
        "unit_type": unit_type,  # GameEnums.UnitType
        "faction": faction,      # GameEnums.Faction
        "position": [global_position.x, global_position.y, global_position.z],
        "rotation": rotation.y,
        "soldiers_alive": soldiers_alive,
        "soldiers_max": soldiers_max,
        "veterancy_level": veterancy_level,
        "veterancy_xp": veterancy_xp,
        "suppression": suppression,
        "current_ammo": current_ammo,
        "current_orders": _serialize_orders(),
        "control_group": control_group,
    }
```

#### JobSystem Serialization

```gdscript
func serialize() -> Dictionary:
    var active_jobs: Array[Dictionary] = []
    for job in _jobs.values():
        active_jobs.append({
            "id": job.job_id,
            "type": job.job_type,
            "state": job.state,
            "position": [job.position.x, job.position.y, job.position.z],
            "bounds": [job.bounds.position.x, job.bounds.position.y,
                       job.bounds.size.x, job.bounds.size.y],
            "work_done": job.work_done,
            "work_required": job.work_required,
            "priority": job.priority,
            "assigned_workers": _serialize_worker_ids(job),
            "prerequisites": job.prerequisite_job_ids,
        })
    return {
        "_version": SAVE_VERSION,
        "_system": "JobSystem",
        "jobs": active_jobs,
        "next_job_id": _next_job_id,
    }
```

### Save File Structure

```
saves/
  campaigns/
    campaign_001/
      meta.json           # Campaign metadata, current mission
      mission_01_end.sav  # State at end of mission 1
      mission_02_end.sav  # State at end of mission 2
      ...
      current.sav         # Auto-save of current mission (post-MVP)
  skirmish/
    autosave.sav          # Last skirmish state (post-MVP)
```

### Campaign Save Format

```gdscript
# Campaign save contains delta from mission start + accumulated state
{
    "campaign_id": "campaign_001",
    "mission_completed": 5,
    "total_play_time_seconds": 18450,
    "systems": {
        "terrain": { /* TerrainEngine.serialize() */ },
        "firebases": [ /* Firebase[].serialize() */ ],
        "supply_chain": { /* SupplyChainManager.serialize() */ },
        "squads": [ /* Squad[].serialize() */ ],
        "jobs": { /* JobSystem.serialize() */ },
        "deck": { /* DeckSystem.serialize() */ },
        "mission_state": { /* Current objectives, etc. */ },
    },
    "checksum": "sha256:...",
}
```

### Forbidden Patterns

These patterns MUST be avoided in any system requiring persistence:

| Pattern | Problem | Solution |
|---------|---------|----------|
| `@onready var target = get_node("../Unit")` | Node refs can't serialize | Store path or ID, resolve on deserialize |
| Anonymous lambdas in signals | Can't serialize closures | Use bound methods |
| State stored only in AnimationPlayer | Lost on reload | Mirror state in serializable variables |
| Random values without seed | Non-deterministic | Store seed, regenerate on load |
| Direct `Node` in Dictionary values | Reference lost | Use node path strings or numeric IDs |
| Timer progress stored in Timer node | Lost on scene change | Store elapsed time in variable |

### ID Management

All persistent entities use stable IDs:

```gdscript
## ID Registry - generates and tracks stable entity IDs
class_name IDRegistry

var _next_id: int = 1
var _entity_map: Dictionary = {}  # id -> WeakRef

func generate_id(entity: Node) -> int:
    var id := _next_id
    _next_id += 1
    _entity_map[id] = weakref(entity)
    return id

func get_entity(id: int) -> Node:
    if not _entity_map.has(id):
        return null
    var ref: WeakRef = _entity_map[id]
    return ref.get_ref()

func register_loaded_entity(id: int, entity: Node) -> void:
    _entity_map[id] = weakref(entity)
    _next_id = maxi(_next_id, id + 1)
```

### Deserialization Order

Systems must deserialize in dependency order:

1. **TerrainEngine** - Terrain must exist before anything placed on it
2. **FirebaseSystem** - Firebase zones must exist before buildings
3. **Buildings** - Buildings must exist before garrison assignments
4. **SupplyChainManager** - Depots and roads must exist before convoys
5. **JobSystem** - Jobs must exist before worker assignments
6. **Squads** - Units must exist before orders
7. **MissionState** - Objectives reference other entities

## Consequences

### Positive

1. **Campaign Persistence**: Persistent expanding map fully supported (D-305)
2. **Clean Architecture**: Serialization contract forces clean state management
3. **Testable**: Serialize/deserialize round-trip makes state testable
4. **Migration Path**: Version headers enable save file format evolution
5. **Chunk Efficiency**: Only modified terrain chunks serialized
6. **Corruption Resistance**: Per-system serialization allows partial recovery

### Negative

1. **Boilerplate**: Every system needs serialize/deserialize methods
2. **ID Management**: Must track stable IDs across session boundaries
3. **Order Dependencies**: Deserialization order must be carefully managed
4. **Testing Burden**: Every system needs serialization round-trip tests
5. **Schema Evolution**: Adding fields requires migration logic

### Mitigations

| Risk | Mitigation |
|------|------------|
| Boilerplate | Provide base class with common serialization patterns |
| ID collisions | Centralized IDRegistry autoload; IDs never reused |
| Order errors | SaveManager enforces deserialization order |
| Schema drift | Version headers + explicit migration functions |
| Large saves | Compress with `FileAccess.COMPRESSION_ZSTD` |

## ADR Dependencies

- **ADR-0001 (Terrain Chunk Streaming)**: Chunk-based terrain enables incremental serialization
- **ADR-0004 (Signal Bus Pattern)**: Signals for save/load lifecycle events
- **ADR-0005 (Job System Architecture)**: Jobs require serialization for persistence

## Engine Compatibility

**Godot 4.6**

| Godot Feature | Usage |
|---------------|-------|
| `FileAccess` | Save file read/write with compression |
| `JSON` | Human-readable save format for debugging |
| `var_to_bytes` / `bytes_to_var` | Binary serialization for performance |
| `Resource` | Typed resources for complex data |
| `PackedByteArray` | Efficient terrain state storage |
| `Time.get_unix_time_from_system()` | Timestamps for save metadata |

## GDD Requirements Addressed

### From GAME_BIBLE.md

| Decision | Requirement | How Addressed |
|----------|-------------|---------------|
| D-106 | Save system parked but architect for it | Serialization contract defined; all systems must implement |
| D-106 | State held in data, not scene graph | ID-based references, no raw Node storage |
| D-106 | Signals over direct refs | Save/load lifecycle via BattleSignals |
| D-106 | Deterministic state machines | All state serializable; round-trip tested |
| D-305 | Persistent expanding map | TerrainEngine chunk serialization; clearing state persists |
| D-305 | All terrain modifications persist | Roads, craters, clearing in per-chunk save data |
| D-305 | All constructed bases persist | FirebaseSystem serialization with full building state |
| D-305 | Mission N starts with union of previous areas | Fog reset only; terrain state carries forward |

### From Campaign Requirements (D-305)

- Terrain clearing state serialization: clearing progress floats + 4-state enum per cell
- Crater positions: Array of Vector3 + radius + depth
- Road network: Graph serialization with edge list
- Firebase fortifications: Building type + position + health + progress
- Unit veterancy: XP value + derived level

## Implementation Files (Planned)

| File | Purpose |
|------|---------|
| `core/save_system/save_manager.gd` | SaveManager autoload - orchestrates save/load |
| `core/save_system/serializable.gd` | Interface contract (virtual class) |
| `core/save_system/id_registry.gd` | Stable entity ID management |
| `core/save_system/save_file.gd` | Save file format wrapper |
| `core/save_system/migration.gd` | Version migration logic |

## Key Signals (Planned)

### SaveManager Signals

```gdscript
signal save_started()
signal save_completed(filepath: String)
signal save_failed(error: String)
signal load_started(filepath: String)
signal load_progress(system: String, progress: float)
signal load_completed()
signal load_failed(error: String)
```

## Validation Checklist (Pre-Merge)

Before merging any system code, verify:

- [ ] `serialize()` method implemented
- [ ] `deserialize(data: Dictionary)` method implemented
- [ ] No raw `Node` references stored in class variables
- [ ] No anonymous lambdas connected to signals
- [ ] State variables not solely stored in nodes (@onready lookup required)
- [ ] Entity uses stable ID from IDRegistry
- [ ] Unit test for serialize/deserialize round-trip

## References

- GAME_BIBLE.md: Decision D-106 (Save system architecture)
- GAME_BIBLE.md: Decision D-305 (Persistent expanding map)
- GAME_BIBLE.md: Phase 8 (Campaign Mode) - save/load implementation
- ADR-0001: Terrain chunk serialization interface
- ADR-0005: Job system serialization requirements
