# ADR-0005: Job System Architecture

## Status
Accepted

## Context
- Construction requires work points accumulated over time by workers
- Engineers and bulldozers must be assigned to construction tasks
- Multiple jobs can run concurrently across the map
- Need to track progress, support pause/resume, and handle interruptions
- Prior implementation split job logic between ConstructionManager, BuilderAI, and JobNodes
- Dual authority between top-down assignment and worker autonomy caused conflicts
- Workers need efficient job discovery without O(n^2) scanning

## Decision
- **Single Authority JobSystem**: Centralized autoload that creates, tracks, and manages all jobs
- **UnifiedJob Resource**: Immutable job data structure with work_required, work_done, state, and metadata
- **Bottom-Up Worker Finding**: WorkerController on each unit finds jobs via heuristic scoring (no manager assignment)
- **Job States**: PENDING -> READY -> IN_PROGRESS -> COMPLETE (or CANCELLED/FAILED)
- **Priority System**: CRITICAL (0), HIGH (1), NORMAL (2), LOW (3) - lower value = more urgent
- **Grid-Aligned Jobs**: All jobs aligned to GridCoords.GAMEPLAY_CELL_SIZE (4m) cells
- **Node-Based Visuals**: Each job type creates a corresponding scene node for visual representation
- **Prerequisite Chains**: Jobs can depend on other jobs (e.g., BUILD depends on FLATTEN depends on CLEAR)

### Job Types
| Type | Description | Worker Class | Creates Node |
|------|-------------|--------------|--------------|
| CLEAR_TERRAIN | Remove vegetation | Engineer, Bulldozer | ClearingZoneNode |
| FLATTEN_AREA | Level terrain | Engineer (slow), Bulldozer (fast) | None (terrain system) |
| BUILD_STRUCTURE | Construct building | Engineer only | ConstructionSiteNode |
| BUILD_ROAD | Create road segment | Bulldozer only | RoadSegmentNode |
| FILL_CRATER | Repair terrain damage | Engineer, Bulldozer | Targets existing CraterNode |
| DIG_TRENCH | Create defensive position | Engineer only | TrenchNode |
| LAY_WIRE | Place wire obstacles | Engineer only | WireObstacleNode |

### Worker Assignment Algorithm
Workers score available jobs using:
```
score = priority_weight + capacity_bonus - distance_penalty - crowding_penalty + random_noise
```

Where:
- `priority_weight`: (4 - priority) * 50 (CRITICAL=200, HIGH=150, NORMAL=100, LOW=50)
- `capacity_bonus`: open_slots * 5 + 20 if unclaimed
- `distance_penalty`: distance_meters * 2.0
- `crowding_penalty`: assigned_workers * 40 + extra for 3+ workers

This ensures workers spread across jobs rather than pile onto one.

### Work Rate Multipliers
| Job Type | Engineer | Bulldozer |
|----------|----------|-----------|
| CLEAR_TERRAIN | 1.0 (via tree felling) | 3.0 base * 25x multiplier |
| FLATTEN_AREA | 0.5 | 2.0 |
| BUILD_STRUCTURE | 1.0 | N/A |
| BUILD_ROAD | 0.3 | 1.0 |
| FILL_CRATER | 0.7 | 1.5 |
| DIG_TRENCH | 1.0 | N/A |
| LAY_WIRE | 1.0 | N/A |

### Max Workers Per Job
Calculated from job cell area: `clamp(cell_count / 2, 2, 16)`

## Consequences

### Positive
- **Clear progress tracking**: UnifiedJob tracks work_done/work_required with 0-1 progress
- **Supports multiple concurrent jobs**: Dictionary-based tracking with spatial indexing
- **Workers auto-assign to nearest suitable job**: Bottom-up finding with priority/distance scoring
- **Pausable/resumable work**: State machine preserves progress through interruptions
- **Prerequisite chains**: CLEAR -> FLATTEN -> BUILD handled automatically
- **Scalable spatial queries**: _job_grid spatial hash for O(1) regional lookups
- **Decoupled visual state**: Job nodes handle visuals, UnifiedJob handles logic

### Negative
- **Job assignment logic complexity**: Scoring heuristic requires tuning to prevent bunching
- **Must handle worker death mid-job**: Workers unassigned on death, job continues with remaining workers
- **Priority conflicts need resolution**: Multiple CRITICAL jobs may compete for workers
- **Path-clearing can cascade**: Workers stuck en route spawn FLATTEN jobs, which can spawn more
- **Signal lifecycle management**: Job signals must be disconnected when jobs complete/cancel

### Mitigations
- Crowding penalty (40 per assigned worker) discourages bunching
- Random noise (+-10) breaks ties to spread workers
- Path-clear attempts capped at 3 before abandoning job
- JobSystem.reset() clears all state on scene reload
- Supply refunded proportionally on cancel (100% - progress%)

## ADR Dependencies
- ADR-0004 (Signal Bus Pattern): Jobs emit signals via BattleSignals for UI/AI/sound
  - `job_created`, `job_completed`, `job_cancelled`, `job_ready`, `worker_needed`
  - Jobs also emit local signals: `state_changed`, `progress_updated`, `stage_completed`

## Engine Compatibility
Godot 4.6 - Implementation uses:
- Timer-based updates via `_process(delta)` with configurable interval (0.1s default)
- RefCounted for UnifiedJob (lightweight, auto-freed)
- Node3D for job visual nodes (ConstructionSiteNode, TrenchNode, etc.)
- AABB for world-space spatial queries
- Rect2i for grid-space cell tracking
- PackedVector3Array for work positions along job perimeter

## GDD Requirements Addressed

### construction-system.md
- **Work points system**: `work_per_second = engineer_count * WORK_RATE_PER_ENGINEER * delta`
- **Engineer assignment**: Auto-assign inside firebase radius, manual outside
- **Construction stages**: FOUNDATION (0-25%), STRUCTURE (25-50%), FINISHING (50-75%), COMPLETE (75-100%)
- **Engineer death handling**: Progress preserved, new engineers can resume
- **Supply deduction**: Consumed at job creation, partial refund on cancel

### firebase-system.md
- **Building progression**: Jobs support staged construction with visual updates
- **Terrain clearing prerequisite**: BUILD_STRUCTURE jobs auto-create CLEAR_TERRAIN prereqs
- **Multiple workers per site**: `max_workers` scales with job area (2-16)
- **Firebase influence radius**: ConstructionManager routes to JobSystem for auto-build

## Implementation Files

| File | Purpose |
|------|---------|
| `firebase_system/job_system/job_system.gd` | JobSystem autoload - creates, tracks, manages all jobs |
| `firebase_system/job_system/unified_job.gd` | UnifiedJob class - job data structure and state machine |
| `firebase_system/job_system/worker_controller.gd` | WorkerController - per-unit AI for autonomous job finding |
| `firebase_system/construction_manager.gd` | ConstructionManager - bridges ConstructionZone and JobSystem |
| `battle_system/ui/work_progress_bar.gd` | Visual progress bar floating above jobs |

## Key Signals

### JobSystem Signals
```gdscript
signal job_created(job: UnifiedJob)
signal job_completed(job: UnifiedJob)
signal job_cancelled(job: UnifiedJob)
signal job_ready(job: UnifiedJob)  # Prerequisites complete
signal worker_needed(job: UnifiedJob)  # Job has room for more workers
```

### UnifiedJob Signals
```gdscript
signal state_changed(job: UnifiedJob, old_state: State, new_state: State)
signal progress_updated(job: UnifiedJob, progress: float)
signal stage_completed(job: UnifiedJob, stage_index: int)
signal job_completed(job: UnifiedJob)
signal job_cancelled(job: UnifiedJob)
signal worker_assigned(job: UnifiedJob, worker: Node3D)
signal worker_unassigned(job: UnifiedJob, worker: Node3D)
signal prerequisite_completed(job: UnifiedJob, prereq: UnifiedJob)
```

### WorkerController Signals
```gdscript
signal started_work(job: UnifiedJob)
signal completed_work(job: UnifiedJob)
signal job_abandoned(job: UnifiedJob, reason: String)
signal state_changed(old_state: State, new_state: State)
```
