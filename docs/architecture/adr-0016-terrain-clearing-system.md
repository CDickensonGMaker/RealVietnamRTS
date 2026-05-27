# ADR-0016: Terrain Clearing System

## Status
Proposed

## Context

RealVietnamRTS uses "Carve the Map" (Pillar 1) as a core design pillar. Terrain is opaque jungle until cleared by bulldozers or engineer det-cord. This creates meaningful terrain manipulation - players must physically carve their battlespace from the jungle.

### Requirements to Address
| TR-ID | Requirement |
|-------|-------------|
| TR-SYS-001 | Terrain clearing progression: JUNGLE -> PARTIALLY_CLEARED -> CLEARED -> FORTIFIED |
| TR-SYS-002 | Bulldozers: fast, large-area, road-grade clearing (required for roads and large buildings) |
| TR-SYS-003 | Engineer det-cord: slower, smaller, tactical clearing (jungle pockets, LZs, fire lanes) |
| TR-SYS-004 | Bulldozers cannot easily push up steep hills; engineers more flexible on terrain |
| TR-SYS-005 | Both clearing tools are vulnerable while working |
| TR-SYS-006 | Terrain types respond differently to each clearing tool |
| TR-SYS-007 | Craters from explosives persist (DamageSystem terrain deformation) |
| TR-SYS-008 | Clear jungle (small) with engineer det-cord: 60 sec |
| TR-SYS-009 | Clear jungle (large) with bulldozer: 30 sec |
| TR-SYS-010 | Cut road through jungle with bulldozer: 2-3 min per 100m |
| TR-SYS-011 | Prepare LZ with engineer or bulldozer: 90 sec |

## Decision

### Terrain Clearing Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    TerrainClearingSystem                            │
│                      (Autoload Singleton)                           │
├─────────────────────────────────────────────────────────────────────┤
│  + request_clearing(area, tool_type) -> ClearingJob                 │
│  + get_clearing_state(position) -> ClearingState                    │
│  + can_clear_at(position, tool_type) -> bool                        │
│  + get_clearing_progress(job_id) -> float                           │
├─────────────────────────────────────────────────────────────────────┤
│  Signals: clearing_started, clearing_progress, clearing_completed,  │
│           clearing_interrupted, terrain_deformed                    │
└─────────────────────────────────────────────────────────────────────┘
          ▲
          │ manages
          │
┌─────────────────────────────────────────────────────────────────────┐
│                        ClearingJob                                  │
├─────────────────────────────────────────────────────────────────────┤
│  + job_id: int                                                      │
│  + area: Rect2                                                      │
│  + tool_type: ClearingTool (BULLDOZER, DET_CORD)                   │
│  + target_state: ClearingState                                      │
│  + progress: float (0.0 - 1.0)                                      │
│  + worker: Node3D (bulldozer or engineer squad)                     │
│  + state: JobState (PENDING, ACTIVE, PAUSED, COMPLETE, CANCELLED)  │
└─────────────────────────────────────────────────────────────────────┘
```

### Clearing States (TR-SYS-001)

```gdscript
## clearing_state.gd - Terrain clearing progression

enum ClearingState {
    JUNGLE,             # Dense vegetation, blocks movement and LOS
    PARTIALLY_CLEARED,  # Thinned, slower movement, reduced LOS block
    CLEARED,            # Open ground, normal movement, no LOS block
    FORTIFIED,          # Reinforced, can place heavy structures
    ROAD,               # Paved/graded, fast movement, vehicle-rated
}

const CLEARING_STATE_DATA := {
    ClearingState.JUNGLE: {
        "movement_modifier": 0.3,      # 30% speed
        "los_block": true,             # Blocks line of sight
        "can_build": [],               # Nothing
        "visual_density": 1.0,         # Full vegetation
    },
    ClearingState.PARTIALLY_CLEARED: {
        "movement_modifier": 0.6,      # 60% speed
        "los_block": false,            # Doesn't block LOS
        "can_build": ["sandbag", "wire", "foxhole"],
        "visual_density": 0.4,         # Sparse vegetation
    },
    ClearingState.CLEARED: {
        "movement_modifier": 1.0,      # Full speed
        "los_block": false,
        "can_build": ["sandbag", "wire", "foxhole", "bunker", "mg_nest"],
        "visual_density": 0.0,         # No vegetation
    },
    ClearingState.FORTIFIED: {
        "movement_modifier": 1.0,
        "los_block": false,
        "can_build": ["all"],          # Everything including heavy
        "visual_density": 0.0,
    },
    ClearingState.ROAD: {
        "movement_modifier": 1.5,      # 150% speed (road bonus)
        "los_block": false,
        "can_build": [],               # No building on roads
        "visual_density": 0.0,
    },
}
```

### Clearing Tools (TR-SYS-002, TR-SYS-003)

```gdscript
## clearing_tool.gd - Different clearing methods

enum ClearingTool {
    BULLDOZER,   # Fast, large area, requires flat ground
    DET_CORD,    # Slower, precise, works on slopes
}

const TOOL_DATA := {
    ClearingTool.BULLDOZER: {
        "name": "D7 Bulldozer",
        "clear_radius": 8.0,           # Meters
        "clear_speed": 2.0,            # State transitions per minute
        "max_slope": 15.0,             # Degrees (TR-SYS-004)
        "can_make_road": true,
        "can_fortify": false,
        "noise_radius": 200.0,         # Enemy detection range
        "vulnerability": 1.5,          # Damage multiplier when working
    },
    ClearingTool.DET_CORD: {
        "name": "Det-Cord Charge",
        "clear_radius": 4.0,           # Meters (smaller)
        "clear_speed": 1.0,            # Slower (TR-SYS-003)
        "max_slope": 45.0,             # Works on steep terrain
        "can_make_road": false,
        "can_fortify": true,
        "noise_radius": 500.0,         # Explosions are loud
        "vulnerability": 1.2,
    },
}
```

### TerrainClearingSystem Implementation

```gdscript
## terrain_clearing_system.gd - Autoload singleton

class_name TerrainClearingSystem extends Node

## Grid of clearing states per cell
var _clearing_grid: Dictionary = {}  # Vector2i -> ClearingState
const CELL_SIZE := 4.0  # 4m cells match terrain chunks

## Active clearing jobs
var _active_jobs: Dictionary = {}  # job_id -> ClearingJob
var _next_job_id: int = 1

func _ready() -> void:
    BattleSignals.unit_died.connect(_on_unit_died)
    BattleSignals.explosion_occurred.connect(_on_explosion)

## Get clearing state at world position
func get_clearing_state(position: Vector3) -> ClearingState:
    var cell := _world_to_cell(position)
    return _clearing_grid.get(cell, ClearingState.JUNGLE)

func _world_to_cell(position: Vector3) -> Vector2i:
    return Vector2i(
        int(position.x / CELL_SIZE),
        int(position.z / CELL_SIZE)
    )

## Check if position can be cleared with given tool
func can_clear_at(position: Vector3, tool: ClearingTool) -> bool:
    var current_state := get_clearing_state(position)

    # Already cleared/fortified
    if current_state in [ClearingState.CLEARED, ClearingState.FORTIFIED, ClearingState.ROAD]:
        return false

    # Check slope for bulldozers (TR-SYS-004)
    if tool == ClearingTool.BULLDOZER:
        var slope := TerrainEngine.get_slope_at(position)
        if slope > TOOL_DATA[tool].max_slope:
            return false

    return true

## Request clearing of an area
func request_clearing(
    center: Vector3,
    tool: ClearingTool,
    target_state: ClearingState,
    worker: Node3D
) -> ClearingJob:

    var job := ClearingJob.new()
    job.job_id = _next_job_id
    _next_job_id += 1
    job.center = center
    job.radius = TOOL_DATA[tool].clear_radius
    job.tool_type = tool
    job.target_state = target_state
    job.worker = worker
    job.state = JobState.PENDING

    # Calculate clearing time based on tool and area
    job.total_time = _calculate_clearing_time(tool, target_state)

    _active_jobs[job.job_id] = job
    BattleSignals.clearing_started.emit(job)

    return job

## Calculate clearing time (TR-SYS-008, 009, 010, 011)
func _calculate_clearing_time(tool: ClearingTool, target: ClearingState) -> float:
    var base_time: float

    match target:
        ClearingState.PARTIALLY_CLEARED:
            # Quick pass
            match tool:
                ClearingTool.BULLDOZER:
                    base_time = 15.0   # Quick initial clear
                ClearingTool.DET_CORD:
                    base_time = 30.0   # Slower det-cord

        ClearingState.CLEARED:
            # Full clearing (TR-SYS-008, 009)
            match tool:
                ClearingTool.BULLDOZER:
                    base_time = 30.0   # TR-SYS-009: 30 sec
                ClearingTool.DET_CORD:
                    base_time = 60.0   # TR-SYS-008: 60 sec

        ClearingState.FORTIFIED:
            # Reinforcement phase
            base_time = 45.0

        ClearingState.ROAD:
            # Road grading (TR-SYS-010: 2-3 min per 100m)
            # Per-cell time scaled for 4m cells
            base_time = 6.0  # ~2.5 min per 100m with 4m cells

    return base_time

## Process active clearing jobs
func _process(delta: float) -> void:
    for job in _active_jobs.values():
        if job.state != JobState.ACTIVE:
            continue

        # Check worker is still alive and working
        if not is_instance_valid(job.worker):
            _cancel_job(job, "Worker destroyed")
            continue

        if job.worker.is_in_combat():
            job.state = JobState.PAUSED
            BattleSignals.clearing_paused.emit(job)
            continue

        # Progress clearing
        job.elapsed_time += delta
        job.progress = job.elapsed_time / job.total_time

        BattleSignals.clearing_progress.emit(job)

        # Check completion
        if job.progress >= 1.0:
            _complete_job(job)

## Complete a clearing job
func _complete_job(job: ClearingJob) -> void:
    job.state = JobState.COMPLETE
    job.progress = 1.0

    # Update terrain cells
    var cells := _get_cells_in_radius(job.center, job.radius)
    for cell in cells:
        _clearing_grid[cell] = job.target_state

    # Update terrain visuals
    _update_terrain_visuals(cells, job.target_state)

    # Update navigation mesh
    NavigationServer3D.region_bake_navigation_mesh(
        _get_nav_region_for(job.center)
    )

    BattleSignals.clearing_completed.emit(job)
    _active_jobs.erase(job.job_id)
```

### Bulldozer Behavior (TR-SYS-002, TR-SYS-004, TR-SYS-005)

```gdscript
## bulldozer.gd - D7 Bulldozer unit

class_name Bulldozer extends Vehicle

enum BulldozerState {
    IDLE,
    MOVING,
    CLEARING,
    ROAD_GRADING,
}

@export var clearing_speed: float = 2.0       # m/s when clearing
@export var road_grade_speed: float = 1.0     # m/s when grading roads
@export var vulnerability_when_working: float = 1.5  # TR-SYS-005

var _current_state: BulldozerState = BulldozerState.IDLE
var _current_job: ClearingJob = null
var _road_path: Array[Vector3] = []

func _ready() -> void:
    super._ready()
    # Bulldozers are louder than other units
    detection_radius = 200.0

## Order bulldozer to clear an area
func order_clear_area(center: Vector3) -> bool:
    # Check slope constraint (TR-SYS-004)
    var slope := TerrainEngine.get_slope_at(center)
    if slope > 15.0:
        BattleSignals.order_failed.emit(self, "Slope too steep for bulldozer")
        return false

    var job := TerrainClearingSystem.request_clearing(
        center,
        ClearingTool.BULLDOZER,
        ClearingState.CLEARED,
        self
    )

    if job:
        _current_job = job
        _current_state = BulldozerState.CLEARING
        return true

    return false

## Order bulldozer to grade a road (TR-SYS-010)
func order_grade_road(path: Array[Vector3]) -> bool:
    # Validate path doesn't have steep slopes
    for point in path:
        var slope := TerrainEngine.get_slope_at(point)
        if slope > 15.0:
            BattleSignals.order_failed.emit(self, "Road path too steep")
            return false

    _road_path = path
    _current_state = BulldozerState.ROAD_GRADING
    return true

func _process(delta: float) -> void:
    super._process(delta)

    match _current_state:
        BulldozerState.CLEARING:
            _process_clearing(delta)
        BulldozerState.ROAD_GRADING:
            _process_road_grading(delta)

func _process_clearing(delta: float) -> void:
    if not _current_job:
        _current_state = BulldozerState.IDLE
        return

    # Move toward clearing center if not there
    var dist := global_position.distance_to(_current_job.center)
    if dist > 2.0:
        _move_toward(_current_job.center, clearing_speed)
    else:
        # Start job if pending
        if _current_job.state == JobState.PENDING:
            _current_job.state = JobState.ACTIVE

## Vulnerability when working (TR-SYS-005)
func get_damage_multiplier() -> float:
    if _current_state in [BulldozerState.CLEARING, BulldozerState.ROAD_GRADING]:
        return vulnerability_when_working
    return 1.0

func take_damage(amount: float, damage_type: DamageType, source: Node3D) -> void:
    # Apply vulnerability multiplier
    var actual_damage := amount * get_damage_multiplier()
    super.take_damage(actual_damage, damage_type, source)

    # Interrupt work if taking fire
    if _current_job and _current_job.state == JobState.ACTIVE:
        _current_job.state = JobState.PAUSED
        BattleSignals.clearing_interrupted.emit(_current_job)
```

### Engineer Det-Cord Behavior (TR-SYS-003)

```gdscript
## engineer_squad.gd - Engineer clearing capability

extends Squad
class_name EngineerSquad

enum EngineerTask {
    NONE,
    CLEARING,
    FORTIFYING,
    PREPARING_LZ,
}

@export var det_cord_charges: int = 10
@export var charges_per_clear: int = 2
@export var vulnerability_when_working: float = 1.2  # TR-SYS-005

var _current_task: EngineerTask = EngineerTask.NONE
var _current_job: ClearingJob = null

## Order engineers to clear an area with det-cord
func order_clear_area(center: Vector3) -> bool:
    if det_cord_charges < charges_per_clear:
        BattleSignals.order_failed.emit(self, "No det-cord charges remaining")
        return false

    var job := TerrainClearingSystem.request_clearing(
        center,
        ClearingTool.DET_CORD,
        ClearingState.CLEARED,
        self
    )

    if job:
        _current_job = job
        _current_task = EngineerTask.CLEARING
        det_cord_charges -= charges_per_clear
        return true

    return false

## Order engineers to prepare LZ (TR-SYS-011)
func order_prepare_lz(center: Vector3) -> bool:
    if det_cord_charges < 4:  # LZ needs more charges
        BattleSignals.order_failed.emit(self, "Insufficient charges for LZ prep")
        return false

    var job := TerrainClearingSystem.request_clearing(
        center,
        ClearingTool.DET_CORD,
        ClearingState.CLEARED,
        self
    )

    if job:
        # LZ prep takes 90 seconds (TR-SYS-011)
        job.total_time = 90.0
        job.radius = 15.0  # Larger area for LZ
        _current_job = job
        _current_task = EngineerTask.PREPARING_LZ
        det_cord_charges -= 4
        return true

    return false

## Order engineers to fortify cleared area
func order_fortify_area(center: Vector3) -> bool:
    var current_state := TerrainClearingSystem.get_clearing_state(center)
    if current_state != ClearingState.CLEARED:
        BattleSignals.order_failed.emit(self, "Area must be cleared first")
        return false

    var job := TerrainClearingSystem.request_clearing(
        center,
        ClearingTool.DET_CORD,
        ClearingState.FORTIFIED,
        self
    )

    if job:
        _current_job = job
        _current_task = EngineerTask.FORTIFYING
        return true

    return false

func _process(delta: float) -> void:
    super._process(delta)

    if _current_task == EngineerTask.NONE:
        return

    if not _current_job:
        _current_task = EngineerTask.NONE
        return

    # Move to work site
    var dist := global_position.distance_to(_current_job.center)
    if dist > 3.0:
        _move_toward(_current_job.center)
    else:
        if _current_job.state == JobState.PENDING:
            _current_job.state = JobState.ACTIVE
            # Play det-cord placement animation
            _play_work_animation("placing_charges")

    # Check job completion
    if _current_job.state == JobState.COMPLETE:
        _current_task = EngineerTask.NONE
        _current_job = null
```

### Terrain Type Response (TR-SYS-006)

```gdscript
## terrain_clearing_modifiers.gd - How terrain types affect clearing

const TERRAIN_CLEARING_MODIFIERS := {
    TerrainType.DENSE_JUNGLE: {
        ClearingTool.BULLDOZER: 0.8,   # 20% slower in dense jungle
        ClearingTool.DET_CORD: 1.0,    # Normal
    },
    TerrainType.LIGHT_JUNGLE: {
        ClearingTool.BULLDOZER: 1.2,   # 20% faster
        ClearingTool.DET_CORD: 1.0,
    },
    TerrainType.BAMBOO: {
        ClearingTool.BULLDOZER: 1.5,   # Easy to push through
        ClearingTool.DET_CORD: 0.8,    # Doesn't blast well
    },
    TerrainType.ROCKY: {
        ClearingTool.BULLDOZER: 0.5,   # Very slow on rocks
        ClearingTool.DET_CORD: 1.2,    # Blasting works well
    },
    TerrainType.SWAMP: {
        ClearingTool.BULLDOZER: 0.0,   # Cannot operate
        ClearingTool.DET_CORD: 0.6,    # Difficult but possible
    },
}

func get_clearing_time_modifier(position: Vector3, tool: ClearingTool) -> float:
    var terrain_type := TerrainEngine.get_terrain_type_at(position)
    if terrain_type in TERRAIN_CLEARING_MODIFIERS:
        return TERRAIN_CLEARING_MODIFIERS[terrain_type].get(tool, 1.0)
    return 1.0
```

### Terrain Deformation (TR-SYS-007)

```gdscript
## terrain_deformation.gd - Crater persistence from explosions

func _on_explosion(position: Vector3, radius: float, damage_type: DamageType) -> void:
    if damage_type not in [DamageType.EXPLOSIVE, DamageType.ARMOR_PIERCING]:
        return

    # Only large explosions create craters
    if radius < 3.0:
        return

    # Create crater deformation (TR-SYS-007)
    var crater_depth := radius * 0.3  # Depth proportional to radius
    var crater := CraterData.new()
    crater.position = position
    crater.radius = radius
    crater.depth = crater_depth

    # Apply to heightmap
    TerrainEngine.deform_terrain(crater)

    # Clear vegetation in crater area
    var cells := _get_cells_in_radius(position, radius)
    for cell in cells:
        _clearing_grid[cell] = ClearingState.CLEARED

    # Craters persist in save data
    _persistent_craters.append(crater)

    BattleSignals.terrain_deformed.emit(crater)
```

### Serialization Support

```gdscript
func serialize() -> Dictionary:
    var grid_data: Array = []
    for cell in _clearing_grid.keys():
        grid_data.append({
            "x": cell.x,
            "y": cell.y,
            "state": _clearing_grid[cell],
        })

    var jobs_data: Array = []
    for job in _active_jobs.values():
        jobs_data.append(job.serialize())

    return {
        "_version": 1,
        "_system": "TerrainClearingSystem",
        "clearing_grid": grid_data,
        "active_jobs": jobs_data,
        "persistent_craters": _serialize_craters(),
        "next_job_id": _next_job_id,
    }

func deserialize(data: Dictionary) -> bool:
    if data.get("_version", 0) != 1:
        return false

    _clearing_grid.clear()
    for entry in data.get("clearing_grid", []):
        var cell := Vector2i(entry.x, entry.y)
        _clearing_grid[cell] = entry.state

    # Restore craters (TR-SYS-007)
    _deserialize_craters(data.get("persistent_craters", []))

    _next_job_id = data.get("next_job_id", 1)
    return true
```

## Consequences

### Positive
- **Terrain is gameplay**: Clearing creates meaningful strategic choices
- **Tool differentiation**: Bulldozers and det-cord serve distinct roles (TR-SYS-002, 003)
- **Persistent modification**: Craters and clearing last entire mission
- **Physical presence**: Workers vulnerable while clearing (TR-SYS-005)

### Negative
- **Gameplay pacing**: Clearing takes real time, can feel slow
- **Complexity**: Multiple terrain states to track
- **Performance**: Heightmap deformation can be expensive

### Mitigations
- Clear timing feedback in UI
- Batch heightmap updates
- Pre-cleared areas on some maps
- Quick-clear tutorial option

## ADR Dependencies

- **ADR-0001 (Terrain Chunks)**: Chunk-based clearing grid
- **ADR-0005 (Job System)**: ClearingJob extends job pattern
- **ADR-0007 (Navigation)**: Nav mesh updates after clearing
- **ADR-0008 (Serialization)**: Clearing state persistence

## Engine Compatibility

**Godot 4.6** - Uses NavigationServer3D for nav mesh updates, heightmap terrain deformation.

## GDD Requirements Addressed

| Requirement | How Addressed |
|-------------|---------------|
| TR-SYS-001 | `ClearingState` enum with JUNGLE → FORTIFIED progression |
| TR-SYS-002 | `TOOL_DATA[BULLDOZER]` with 8m radius, fast clearing |
| TR-SYS-003 | `TOOL_DATA[DET_CORD]` with 4m radius, precise clearing |
| TR-SYS-004 | `max_slope: 15.0` for bulldozer, 45.0 for det-cord |
| TR-SYS-005 | `vulnerability_when_working` multiplier on damage |
| TR-SYS-006 | `TERRAIN_CLEARING_MODIFIERS` per terrain type |
| TR-SYS-007 | `_on_explosion()` creates persistent craters |
| TR-SYS-008 | Det-cord clearing time: 60 sec |
| TR-SYS-009 | Bulldozer clearing time: 30 sec |
| TR-SYS-010 | Road grading: ~2.5 min per 100m (6 sec per 4m cell) |
| TR-SYS-011 | LZ prep: 90 sec via `order_prepare_lz()` |

## Implementation Files

| File | Purpose |
|------|---------|
| `terrain/systems/terrain_clearing_system.gd` | Main autoload singleton |
| `terrain/clearing_state.gd` | ClearingState enum and data |
| `terrain/clearing_job.gd` | ClearingJob data class |
| `battle_system/units/bulldozer.gd` | D7 Bulldozer unit |
| `battle_system/nodes/engineer_squad.gd` | Engineer clearing capability |

## Key Signals

```gdscript
## BattleSignals additions for terrain clearing
signal clearing_started(job: ClearingJob)
signal clearing_progress(job: ClearingJob)
signal clearing_completed(job: ClearingJob)
signal clearing_paused(job: ClearingJob)
signal clearing_interrupted(job: ClearingJob)
signal terrain_deformed(crater: CraterData)
```

## Validation Criteria

- [ ] Bulldozer clears jungle in 30 seconds
- [ ] Det-cord clears jungle in 60 seconds
- [ ] Bulldozer cannot operate on slopes > 15 degrees
- [ ] Engineers can clear on steep terrain
- [ ] Workers take extra damage while clearing
- [ ] Explosions create persistent craters
- [ ] Road grading takes 2-3 min per 100m
- [ ] LZ preparation takes 90 seconds
- [ ] Terrain types modify clearing speed
