# Control Manifest

> **Engine**: Godot 4.6
> **Last Updated**: 2026-05-21
> **Manifest Version**: 2026-05-21
> **ADRs Covered**: ADR-0001, ADR-0002, ADR-0003, ADR-0004, ADR-0005
> **Status**: Active — regenerate with `/create-control-manifest` when ADRs change

`Manifest Version` is the date this manifest was generated. Story files embed
this date when created. `/story-readiness` compares a story's embedded version
to this field to detect stories written against stale rules. Always matches
`Last Updated` — they are the same date, serving different consumers.

This manifest is a programmer's quick-reference extracted from all Accepted ADRs,
technical preferences, and engine reference docs. For the reasoning behind each
rule, see the referenced ADR.

---

## Foundation Layer Rules

*Applies to: scene management, event architecture, save/load, spatial partitioning, engine initialisation*

### Required Patterns

- **Use SpatialHashGrid for all spatial queries** — All target acquisition, area queries, and proximity checks must use the SpatialHashGrid autoload. Never iterate all units manually. — source: ADR-0003
- **Register units with SpatialHashGrid on spawn** — Connect to `BattleSignals.unit_spawned` and call `SpatialHashGrid.register_unit(unit, faction)` immediately. — source: ADR-0003
- **Unregister units on death** — Connect to `BattleSignals.unit_died` and call `SpatialHashGrid.unregister_unit(unit)`. — source: ADR-0003
- **Use distance_squared for spatial checks** — Avoid `sqrt()` in hot paths. Use `distance_squared_to()` and compare against `radius * radius`. — source: ADR-0003
- **Emit all cross-system events via BattleSignals** — Never call methods on other systems directly. Emit signals through the BattleSignals autoload. — source: ADR-0004
- **Connect to signals in _ready()** — All listeners must connect to BattleSignals in their `_ready()` lifecycle method. — source: ADR-0004
- **Use past tense for event signals** — Events that happened use past tense: `unit_died`, `firebase_captured`, `squad_routing`. — source: ADR-0004
- **Use present tense for request signals** — Requests use present tense: `request_reinforcements`, `call_airstrike`, `request_resupply`. — source: ADR-0004

### Forbidden Approaches

- **Never iterate all units for spatial queries** — O(n) iteration of all units is forbidden. Use SpatialHashGrid queries instead. Iterating wastes CPU and doesn't scale. — source: ADR-0003
- **Never call methods directly across systems** — Direct method calls create tight coupling. Use BattleSignals instead. — source: ADR-0004
- **Never use QuadTree or Octree for spatial partitioning** — SpatialHashGrid is the chosen architecture. Alternative spatial structures were rejected for unnecessary complexity at 300-500 unit scale. — source: ADR-0003

### Performance Guardrails

- **SpatialHashGrid queries**: O(cells * units_per_cell) — Typical query with 300 units across map, radius 50m = ~18 checks. — source: ADR-0003
- **Signal emission overhead**: Minimal — Godot's native signal system has negligible cost. — source: ADR-0004
- **Cell size tuning**: 20m cells — Optimal for typical weapon ranges (300m = 15 cells radius). — source: ADR-0003

---

## Core Layer Rules

*Applies to: core gameplay loop, terrain, vegetation, construction, physics, collision*

### Required Patterns

- **Use 32x32m terrain chunks** — All terrain generation and modification must respect chunk boundaries. — source: ADR-0001
- **Load chunks asynchronously** — Chunk loading must use WorkerThreadPool to prevent main thread stalls. Target < 50ms per chunk. — source: ADR-0001
- **Stream chunks based on camera distance** — Load distance is configurable per LOD tier. Unload beyond threshold + hysteresis buffer. — source: ADR-0001
- **Each chunk owns its vegetation** — Terrain mesh, vegetation, collision, navmesh all belong to the chunk. — source: ADR-0001
- **Overlap heightmap edges by 1 vertex** — Prevents seams at chunk boundaries. Blend normals at boundaries. — source: ADR-0001
- **Seed vegetation RNG by world position** — Not chunk index. Ensures vegetation continuity across chunk boundaries. — source: ADR-0001, ADR-0002
- **Use hysteresis for LOD transitions** — 3D trees: show < 70m, hide > 90m (20m buffer). Billboards: show > 60m, hide < 50m. Prevents flickering. — source: ADR-0002
- **VegetationLODManager is authoritative for 3D tree visibility** — BillboardVegetation manages itself but respects overlapping ranges. — source: ADR-0002
- **TreeNodeManager must register trees with VegetationLODManager** — On spawn, call `VegetationLODManager.register_tree(tree)`. — source: ADR-0002
- **ClearingSystem affects both 3D trees and billboards** — Clearing state checks required in both systems. — source: ADR-0002
- **JobSystem is the single authority for all jobs** — Never create jobs outside JobSystem. All job management centralized. — source: ADR-0005
- **Workers find jobs via bottom-up scoring** — No top-down assignment. WorkerController on each unit scores available jobs using priority + distance + crowding. — source: ADR-0005

### Forbidden Approaches

- **Never use monolithic terrain** — A single large terrain exceeds memory constraints and fails performance targets. Rejected in favor of chunk streaming. — source: ADR-0001
- **Never use continuous alpha fade for LOD** — Transparent sorting with thousands of trees is prohibitively expensive. Hard swap with hysteresis chosen instead. — source: ADR-0002
- **Never use single LOD system with impostors** — Requires pre-baked impostor textures, less flexibility for clearing. Rejected for dual-tier approach. — source: ADR-0002
- **Never use Godot's built-in visibility_range** — No hysteresis, causes popping. Explicit VegetationLODManager required. — source: ADR-0002
- **Never split job logic between multiple managers** — Prior implementation with ConstructionManager + BuilderAI + JobNodes caused dual authority conflicts. JobSystem is sole authority. — source: ADR-0005

### Performance Guardrails

- **Terrain memory budget**: ~117 MB for 400 active chunks (640m x 640m visible area) — source: ADR-0001
- **Chunk load time**: < 50ms per chunk — source: ADR-0001
- **Vegetation LOD update rate**: 10Hz — Balances responsiveness with CPU overhead. — source: ADR-0002
- **Overlap zone draw calls**: Acceptable trade-off — 60-90m zone renders both 3D and billboards. — source: ADR-0002

---

## Feature Layer Rules

*Applies to: secondary mechanics, AI systems, job assignment, worker behavior*

### Required Patterns

- **Use priority scoring for job assignment** — `score = priority_weight + capacity_bonus - distance_penalty - crowding_penalty + random_noise`. — source: ADR-0005
- **Apply crowding penalty** — 40 points per assigned worker, prevents worker bunching on single job. — source: ADR-0005
- **Cap path-clear attempts at 3** — Workers stuck en route to job abandon after 3 FLATTEN job spawns. — source: ADR-0005
- **Refund supply proportionally on job cancel** — `refund = supply_cost * (1.0 - progress)`. — source: ADR-0005

### Forbidden Approaches

- **Never use top-down worker assignment** — Manager-assigned workers caused conflicts. Bottom-up finding required. — source: ADR-0005
- **Never allow workers to pile onto one job** — Crowding penalty mandatory to spread workers across jobs. — source: ADR-0005

### Performance Guardrails

- **Job update interval**: 0.1s default (10Hz) — Configurable via Timer. — source: ADR-0005

---

## Presentation Layer Rules

*Applies to: rendering, audio, UI, VFX, vegetation visuals*

### Required Patterns

- **Use MultiMesh for billboard vegetation** — 5-plane cross quads, ~4,500 per 256m chunk. — source: ADR-0002
- **Match billboard scale to 3D tree silhouettes** — Billboards must visually resemble the 3D trees they represent in the overlap zone. — source: ADR-0002
- **Use same placement RNG seeds for consistency** — Billboard placement uses same RNG as would-be 3D trees. — source: ADR-0002

### Forbidden Approaches

- **Never render all trees as 3D models** — Destroys framerate. LOD system mandatory. — source: ADR-0002
- **Never render all trees as billboards** — Loses close-up fidelity and clearing interactivity. Dual-tier required. — source: ADR-0002

### Performance Guardrails

- **Frame time budget for vegetation**: < 2ms — Down from 8ms+ without LOD. — source: ADR-0002
- **Draw calls (max visible vegetation)**: < 500 (3D) + batched MultiMesh — source: ADR-0002

---

## Global Rules (All Layers)

### Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| **Classes** | PascalCase with `class_name` declaration | `Squad`, `FirebaseZone`, `VietnamUnitData` |
| **Variables** | snake_case, private members prefixed with `_` | `current_state`, `_internal_timer` |
| **Signals/Events** | snake_case, **past tense** for events, **present tense** for requests | `unit_died`, `firebase_captured`, `request_reinforcements` |
| **Files** | snake_case matching class name | `squad.gd`, `firebase_zone.gd` |
| **Scenes/Prefabs** | snake_case matching script | `squad.tscn`, `firebase_zone.tscn` |
| **Constants** | SCREAMING_SNAKE_CASE with `:=` | `const MAX_SQUAD_SIZE := 12` |

### Performance Budgets

| Target | Value | Notes |
|--------|-------|-------|
| **Framerate** | 60 FPS | Non-negotiable target |
| **Frame Budget** | 16.67ms | All systems combined |
| **Draw Calls** | Minimize via MultiMesh, chunk batching | — |
| **Unit Count** | 300-500 active units | Design target |
| **Map Size** | 3km x 3km with chunk streaming | Campaign final size |
| **Memory Ceiling** | 4GB RAM | Recommended spec target |

### Approved Libraries / Addons

- **GDUnit4** — Approved for unit testing, integration tests
- **Custom terrain engine** — In-project at `terrain/`, no external dependency

### Forbidden Patterns (from technical-preferences.md)

- **Untyped function parameters/returns** — All functions must declare types
- **`get_node()` without null checks** — Use `get_node_or_null()` and check validity
- **Untyped math functions** — Use `clampf`, `maxf`, `mini`, `minf`, `absf` for type safety
- **Per-frame allocations in hot paths** — Avoid `new()`, `Array[]` creation in `_process()` or `_physics_process()`
- **Deep nesting** — Use early returns instead of nested if/else chains
- **Features not serving a Pillar** — See GAME_BIBLE.md Section 3 (The Six Pillars)
- **Items in Explicit Exclusions list** — See GAME_BIBLE.md Section 5 (Anti-Pillars)
- **Files over 500 LOC without refactoring** — Split large files into focused modules

### Deprecated APIs (Godot 4.6)

*No deprecated APIs detected in ADRs. Engine reference docs not found.*

### Cross-Cutting Constraints

- **All gameplay systems must be serialization-ready** — State in data structures, not scene graph. Prepare for ADR-0006 (Save System). — inferred from save-system.md GDD
- **NavMesh must update when terrain cleared** — Clearing affects pathfinding costs. Prepare for ADR-0007 (Navigation Mesh). — inferred from terrain-clearing.md GDD

---

## Notes

- **Missing ADRs**: Save/Serialization (ADR-0006), Navigation Mesh (ADR-0007), HUD System (ADR-0008) — referenced in requirements but not yet written
- **Engine Reference**: No `docs/engine-reference/godot/` found — deprecated APIs and post-cutoff verifications not available
- **Next update trigger**: When new ADRs are accepted or existing ADRs are revised

---

**Generated by**: `/create-control-manifest`
**Regenerate with**: `/create-control-manifest` after ADR changes
