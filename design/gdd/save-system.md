# Save System GDD

> **Status**: `[LIVING]`
> **Last Updated**: 2026-05-21
> **Source Documents**: GAME_BIBLE.md D-106, PRD.md Section 15
> **Pillar**: 6 (Persistent Expanding Map)
> **MVP Status**: Architecture only - full implementation post-MVP

---

## 1. Overview

The save system handles serialization and deserialization of all game state for campaign persistence and checkpoint loading. It enables the persistent expanding map campaign by preserving terrain modifications, constructions, unit state, and supply levels between missions. For MVP, systems are architected with serialization in mind but full save/load implementation is deferred to post-MVP.

---

## 2. Player Fantasy

You can step away from a 90-minute mission confident your progress is safe. When you return, everything is exactly as you left it - the firebase you built, the road you cut, the battle you were fighting. When a mission goes badly, you reload from the checkpoint where you expanded the map, not from the very beginning. The game respects your time and your investment.

---

## 3. Detailed Rules

### 3.1 Save Points

| Trigger | Save Type | When |
|---------|-----------|------|
| Mission start | Automatic | Before first frame |
| Map expansion | Automatic | When new area revealed |
| Every 10 minutes | Autosave | Periodic checkpoint |
| Player-initiated | Manual | On demand |

### 3.2 Save Slots

| Slot Type | Count | Purpose |
|-----------|-------|---------|
| Campaign slot | 3 | Full campaign progress |
| Mission autosave | 3 | Rolling 10-minute checkpoints |
| Quicksave | 1 | Player-triggered manual save |

### 3.3 What Gets Saved

**Terrain State:**
- Clearing state per chunk cell (JUNGLE/PARTIAL/CLEARED/FORTIFIED)
- Road network graph
- Crater positions and sizes
- Vegetation removal state

**Building State:**
- Building type, position, rotation
- Construction progress (if incomplete)
- Health and damage state
- Garrison contents

**Unit State:**
- Unit type, position, facing
- Current orders and patrol routes
- Health, soldier count
- Resource levels (ammo, water)
- Morale state
- Veterancy level

**Supply State:**
- Depot contents
- Convoy positions and cargo
- Helicopter positions and state

**Mission State:**
- Mission timer
- Objective progress
- Revealed map areas
- AI Director state
- Weather/time state

### 3.4 What Does NOT Get Saved (Recomputed)

- Pathfinding navmesh (rebuilt from terrain)
- Spatial hash grid (rebuilt from unit positions)
- LOD states (recalculated from camera)
- Particle effects (restart clean)
- Audio state (restart clean)

### 3.5 On Mission Failure

Player can reload from:
1. **Mission start** - Retry with pre-mission state
2. **Last map expansion** - Return to when new area opened
3. **Last autosave** - Most recent 10-minute checkpoint
4. **Quicksave** - Player's chosen point

### 3.6 Serialization Requirements

All systems must follow serialization-friendly patterns:

**Required:**
- State held in data structures, not scene graph
- Use IDs or paths instead of raw Node references
- Deterministic state machines with serializable state
- No state stored in @onready lookups that can't be recomputed

**Forbidden:**
- Raw `Node` references stored across frames
- State dependent on scene tree order
- Non-deterministic initialization
- Closures or lambdas as stored state

---

## 4. Formulas

### 4.1 Save Data Structure

```gdscript
class_name SaveData
extends Resource

# Header
var save_version: int = 1
var timestamp: int  # Unix timestamp
var mission_id: String
var play_time_seconds: float

# Terrain
var terrain_cells: Dictionary  # Vector2i -> TerrainCellData
var roads: Array[RoadSegmentData]
var craters: Array[CraterData]

# Buildings
var buildings: Array[BuildingData]

# Units
var player_units: Array[UnitData]
var enemy_units: Array[UnitData]

# Supply
var depots: Dictionary  # depot_id -> supply_amount
var convoys: Array[ConvoyData]
var helicopters: Array[HelicopterData]

# Mission
var mission_timer: float
var objectives: Dictionary  # objective_id -> progress
var revealed_areas: Array[Rect2]
var ai_director_state: AIDirectorData
```

### 4.2 Serialization

```gdscript
func save_game(slot: int) -> Error:
    var save_data := SaveData.new()

    # Collect state from all systems
    save_data.terrain_cells = TerrainManager.serialize()
    save_data.buildings = ConstructionManager.serialize()
    save_data.player_units = serialize_units(get_tree().get_nodes_in_group("player_units"))
    save_data.depots = SupplyManager.serialize_depots()
    save_data.mission_timer = MissionManager.get_elapsed_time()
    save_data.objectives = MissionManager.get_objective_state()

    # Write to file
    var path := "user://saves/slot_%d.tres" % slot
    return ResourceSaver.save(save_data, path)
```

### 4.3 Deserialization

```gdscript
func load_game(slot: int) -> Error:
    var path := "user://saves/slot_%d.tres" % slot
    if not FileAccess.file_exists(path):
        return ERR_FILE_NOT_FOUND

    var save_data: SaveData = ResourceLoader.load(path)
    if save_data == null:
        return ERR_INVALID_DATA

    # Clear current state
    clear_game_state()

    # Restore state to all systems
    TerrainManager.deserialize(save_data.terrain_cells)
    ConstructionManager.deserialize(save_data.buildings)
    spawn_units_from_data(save_data.player_units)
    SupplyManager.deserialize_depots(save_data.depots)
    MissionManager.set_elapsed_time(save_data.mission_timer)
    MissionManager.set_objective_state(save_data.objectives)

    # Rebuild derived state
    rebuild_navmesh()
    rebuild_spatial_hash()

    return OK
```

### 4.4 Unit Serialization

```gdscript
class_name UnitData
extends Resource

var unit_type: String
var position: Vector3
var rotation: float
var soldier_count: int
var health: float
var ammo: int
var water: int
var morale: float
var current_order: Dictionary
var veterancy: int

static func from_unit(unit: Node3D) -> UnitData:
    var data := UnitData.new()
    data.unit_type = unit.unit_data.type_id
    data.position = unit.global_position
    data.rotation = unit.rotation.y
    data.soldier_count = unit.soldier_count
    data.health = unit.health
    data.ammo = unit.ammo
    data.water = unit.water
    data.morale = unit.morale
    data.current_order = unit.serialize_order()
    data.veterancy = unit.veterancy
    return data
```

---

## 5. Edge Cases

### 5.1 Save During Combat
- Save is allowed during combat
- All projectiles in flight are NOT saved (too transient)
- Combat state (who is engaged with whom) IS saved
- Suppression values are saved

### 5.2 Save During Construction
- Construction progress is saved as percentage
- Assigned engineers are saved
- Resume construction on load

### 5.3 Save During Convoy Transit
- Convoy position along route is saved
- Cargo contents saved
- Route waypoints saved

### 5.4 Corrupt Save Detection
- Checksum verification on load
- Version compatibility check
- Graceful error handling with user notification

### 5.5 Version Migration
- Save version number in header
- Migration functions for older saves
- Warn user if save is from incompatible version

### 5.6 Disk Full
- Check available space before save
- Atomic write (temp file then rename)
- Keep previous save until new save confirmed

---

## 6. Dependencies

| System | Dependency Type | Notes |
|--------|-----------------|-------|
| **All Gameplay Systems** | Required | Must implement serialize/deserialize |
| **Resource System** | Required | Godot Resource serialization |
| **File System** | Required | user:// save directory |

### Systems Requiring Serialization Interface

Every system listed in systems-index.md must implement:
```gdscript
func serialize() -> Dictionary
func deserialize(data: Dictionary) -> void
```

---

## 7. Tuning Knobs

| Parameter | Default | Range | Notes |
|-----------|---------|-------|-------|
| `autosave_interval` | 600 sec | 300-900 | Time between autosaves |
| `autosave_slot_count` | 3 | 2-5 | Rolling autosave slots |
| `save_compression` | true | bool | Compress save files |
| `max_save_size_mb` | 50 | 20-100 | Warn if save exceeds |

---

## 8. Acceptance Criteria

### Core Functionality
- [ ] Manual save creates save file
- [ ] Load restores complete game state
- [ ] Autosave triggers every 10 minutes
- [ ] Map expansion triggers autosave

### State Preservation
- [ ] Terrain clearing state persists
- [ ] Building positions and state persist
- [ ] Unit positions and stats persist
- [ ] Supply levels persist
- [ ] Mission progress persists

### Checkpoint System
- [ ] Can reload from mission start
- [ ] Can reload from map expansion
- [ ] Can reload from autosave
- [ ] Can reload from quicksave

### Error Handling
- [ ] Corrupt save detected and reported
- [ ] Disk full handled gracefully
- [ ] Version mismatch detected

### Performance
- [ ] Save completes in <2 seconds
- [ ] Load completes in <5 seconds
- [ ] Game does not freeze during save

---

## MVP Implementation Notes

**For MVP (Architecture Only):**
- All systems written with serialization-friendly patterns
- `serialize()` and `deserialize()` interface defined
- No actual save/load UI or file operations
- State held in data, not scene graph
- No raw Node references across frames

**Post-MVP (Full Implementation):**
- Save/load UI
- File operations
- Checkpoint system
- Save slot management
- Compression and versioning

**Code Review Checklist:**
- [ ] No raw `Node` references stored across frames
- [ ] State in data structures, not scene graph
- [ ] Deterministic state machines
- [ ] `@onready` lookups can be recomputed on load
