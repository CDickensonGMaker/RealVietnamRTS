# ADR-0009: Build Menu & Firebase Placement System

## Status
Accepted

## Context
- Players need an intuitive way to construct firebase defenses and support structures
- Buildings have different placement requirements based on their category
- Some buildings can be placed anywhere (field defenses), while others require being within a TOC influence zone (firebase defenses)
- Linear structures like sandbags and wire require drag-to-paint placement rather than point-click
- Bridge placement requires spanning terrain features (water/ravines) with rotation controls
- Reference games (Company of Heroes, Men of War) provide drag-to-paint tools for perimeter defenses
- Need visual feedback (blueprint ghost) showing valid/invalid placement in real-time

## Decision

### Build Menu System (BuildMenuPopup)
- **Tab-based organization** with 4 categories reflecting placement requirements:
  - `FIELD_DEFENSE` - Placeable anywhere without TOC (sandbags, wire, foxholes, claymores)
  - `FIREBASE_DEFENSE` - Requires TOC influence zone (bunkers, MG nests, mortar pits, trenches)
  - `OPERATIONS` - Firebase operational buildings (TOC, helipad, medical, ammo, commo)
  - `SUPPLY_CHAIN` - Logistics structures (supply depot, fuel depot, bridges)

- **TOC creates firebase zone**: TOC can be placed anywhere (`can_place_anywhere = true`) and creates 150m influence radius. Firebase Defense buildings require being within a TOC zone.

### Placement Modes (PlacementController)
Four distinct placement modes based on building type:

| Mode | Description | Use Cases |
|------|-------------|-----------|
| `SINGLE` | Point-click placement | Bunker, helipad, TOC, bridges |
| `PAINTABLE` | Continuous drag, seamless segments | Sandbags, trenches |
| `PAINTABLE_SPACED` | Drag with spacing between segments | Wire obstacles (2.0m), tank traps (2.5m) |
| `PAINTABLE_LINE_JITTERED` | Drag with jittered spacing | Foxholes (4.0m base spacing) |

### Placement State Machine
```
State Machine:
IDLE -> SINGLE_PLACING (on start_placement for non-linear)
IDLE -> LINEAR_START (on start_placement for linear)
LINEAR_START -> LINEAR_DRAGGING (on first click)
LINEAR_DRAGGING -> IDLE (on second click - commits)
Any State -> IDLE (on cancel/ESC/right-click)
```

### Bridge Placement Validation
- Bridges use SINGLE mode with additional validation
- Q/E keys rotate bridge by 15 degrees for alignment
- Must span water or ravine (terrain feature detection)
- Creates road segment on construction completion for convoy pathfinding

### Validation Pipeline (via JobSystem)
```
PlacementController.handle_input()
  -> JobSystem.validate_placement_real_time()  [cached per-frame]
     -> _check_map_bounds()
     -> _check_terrain_slope()
     -> _check_building_overlap()
     -> _check_terrain_clearance()
     -> _check_water()
     -> _check_firebase_zone()  [Firebase Defense only]
     -> _validate_bridge_span()  [bridges only]
```

### BuildingData Flags for Placement
- `can_place_anywhere: bool` - True for field defenses and TOC
- `is_linear_placement: bool` - True for paintable buildings (sandbags, wire)
- `is_hq_building: bool` - True for TOC (creates firebase zone)
- `influence_radius: float` - Zone radius for HQ buildings (150m for TOC)
- `requires_cleared_terrain: bool` - Some firebase buildings need cleared terrain

### Blueprint Ghost Visual Feedback
- Green outline = valid placement
- Red outline = invalid placement
- Yellow outline = partial validity (some linear segments valid)
- Ghost updates position every frame via cursor tracking
- Line preview for linear placement shows all segment positions

## Consequences

### Positive
- **Clear category organization**: Players understand which buildings need TOC zone
- **Intuitive painting**: Linear defenses placed rapidly with drag gestures (Company of Heroes style)
- **Real-time feedback**: Blueprint ghost immediately shows placement validity
- **Cached validation**: Per-frame cache prevents redundant terrain/overlap checks during cursor movement
- **Flexible rotation**: Bridge placement supports Q/E rotation for terrain alignment
- **Road network integration**: Bridges automatically register as road segments when complete

### Negative
- **Tab navigation required**: Players must switch tabs to access different building categories
- **Ghost lifecycle management**: Must properly destroy ghost on cancel/commit to prevent orphaned nodes
- **Linear segment calculation**: Must handle edge cases (too short drag, all segments invalid)
- **Input consumption**: Placement mode must consume all input to prevent accidental selection/commands
- **Activation frame guard**: Must skip input on activation frame to prevent menu click from immediately committing

### Mitigations
- Activation frame tracking prevents immediate commit on menu click
- Ghost uses synchronous `free()` (not `queue_free()`) to prevent race conditions
- Linear placement shows segment count so players know how many will be placed
- Invalid position clicks (NaN, out of bounds) fall through to UI handlers
- Cancel cancels and cleans up properly rather than leaving partial state

## ADR Dependencies
- **ADR-0005 (Job System Architecture)**: Placement creates build jobs via JobSystem
- **ADR-0004 (Signal Bus Pattern)**: Placement signals (placement_committed, placement_cancelled) integrate with game systems

## Engine Compatibility
Godot 4.6 - Implementation uses:
- `Control` nodes for BuildMenuPopup UI (PanelContainer, GridContainer, ScrollContainer)
- `Node3D` for PlacementController and BlueprintGhost
- Input event handling via `_input()` and explicit `handle_input()` method
- StyleBoxFlat for military-themed panel styling
- Real-time cursor tracking via raycast results from BattleHUD

## GDD Requirements Addressed

### firebase-system.md
- **HQ building creates influence radius**: TOC placed anywhere creates 150m firebase zone
- **Firebase levels based on building count**: Building placement tracked for level calculation
- **Firebase perimeter construction**: Paint tools for sandbags, wire, foxholes

### construction-system.md
- **Paint/drag tools for perimeter structures**: PAINTABLE, PAINTABLE_SPACED, PAINTABLE_LINE_JITTERED modes
- **Terrain requirements for building**: Validation checks slope, water, clearance, zone membership
- **Interactive placement preview**: BlueprintGhost provides real-time valid/invalid feedback

## Implementation Files

| File | Purpose |
|------|---------|
| `battle_system/ui/build_menu_popup.gd` | Tab-based build menu UI with grid thumbnails |
| `firebase_system/placement_controller.gd` | Central placement coordinator with state machine |
| `battle_system/ui/blueprint_ghost.gd` | Visual preview with valid/invalid coloring |
| `firebase_system/building_data.gd` | Building definitions including placement flags |
| `firebase_system/job_system/job_system.gd` | Validation pipeline and build job creation |

## Key Signals

### BuildMenuPopup Signals
```gdscript
signal building_selected(building_key: String, placement_mode: PlacementMode)
signal menu_closed()
```

### PlacementController Signals
```gdscript
signal placement_started(building_type: int)
signal placement_committed(building_type: int, position: Vector3)
signal placement_cancelled()
signal linear_segment_committed(building_type: int, positions: Array)
signal validation_changed(valid: bool, message: String)
```

## Tab Category to Building Type Mapping

### FIELD_DEFENSE (can_place_anywhere = true)
- Sandbag Light
- Wire Obstacle
- Tank Trap
- Foxhole
- Claymore Line

### FIREBASE_DEFENSE (requires TOC zone)
- Bunker
- Machine Gun Nest
- Mortar Pit
- Sandbag Heavy
- Watchtower
- Trench

### OPERATIONS (mixed - TOC can_place_anywhere, others need zone)
- Helipad
- TOC (can_place_anywhere, creates firebase zone)
- Medical Station
- Ammo Bunker
- Commo Bunker
- Observation Tower

### SUPPLY_CHAIN (logistics)
- Supply Depot
- Fuel Depot
- Pontoon Bridge

## Placement Validation Errors

```gdscript
enum PlacementError {
    NONE,
    TERRAIN_OCCUPIED,       # Another building/job at this location
    TERRAIN_SLOPE,          # Ground too steep for building
    TERRAIN_CLEARED,        # Requires cleared terrain
    TERRAIN_WATER,          # Position is in water
    INSUFFICIENT_SUPPLY,    # Not enough supply
    OUT_OF_BOUNDS,          # Position outside playable map
    OUTSIDE_FIREBASE,       # Firebase Defense not within TOC zone
    INVALID_BRIDGE_SPAN     # Bridge not spanning water/ravine
}
```
