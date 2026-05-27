# RealVietnamRTS — Master Architecture

## Document Status
- **Version**: 1.0
- **Last Updated**: 2026-05-21
- **Engine**: Godot 4.6
- **GDDs Covered**: 17 (game-concept + systems-index + 15 system GDDs)
- **ADRs Referenced**: ADR-0001, ADR-0002, ADR-0003, ADR-0004, ADR-0005
- **Technical Director Sign-Off**: CONCERNS (2026-05-21) — Foundation layer ADRs exist conceptually but need formal documentation
- **Lead Programmer Feasibility**: CONCERNS (2026-05-21) — Implementable, but 5 interface definitions should be documented before coding starts

## Engine Knowledge Gap Summary

**Engine**: Godot 4.6 (3 versions post-cutoff from LLM training)
**LLM Cutoff**: May 2025 (~Godot 4.3)
**Post-Cutoff Versions**: 4.4 (Mid 2025), 4.5 (Late 2025), 4.6 (Jan 2026)

### HIGH RISK Domains

**Physics (Godot 4.6)**
- Jolt is now the DEFAULT 3D physics engine (was GodotPhysics)
- HingeJoint3D `.damp` property only works with GodotPhysics, not Jolt
- Affects: Combat System (projectiles, suppression), Helicopter System (flight physics)

**Rendering (Godot 4.6)**
- Glow now processes BEFORE tonemapping (was after) — visual appearance changed
- D3D12 is default backend on Windows (was Vulkan)
- Affects: Terrain Clearing (glow on cleared areas), Firebase System (helipad lighting)

**GDScript (Godot 4.5)**
- Variadic arguments (`...`) and `@abstract` decorator added
- Script backtracing available in Release builds

**Animation (Godot 4.6)**
- IK system fully restored (CCDIK, FABRIK, Jacobian IK, Spline IK, TwoBoneIK)

### MEDIUM RISK Domains

**Core (Godot 4.4)**
- `FileAccess.store_*` methods now return `bool` (was `void`)
- Affects: Save System

**UI (Godot 4.6)**
- Dual-focus system (mouse/touch separate from keyboard/gamepad focus)
- Affects: Unit Resources (floating UI indicators)

**Navigation (Godot 4.5)**
- Dedicated 2D navigation server (no longer proxy to 3D)

**All HIGH RISK recommendations in this document should be verified against `docs/engine-reference/godot/` before implementation.**

---

## System Layer Map

RealVietnamRTS follows a 5-layer architecture model:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  PRESENTATION LAYER                                                         │
│  ← UI, HUD, menus, VFX, audio, visual feedback                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  • Selection System                                                         │
│  • Build Menu                                                               │
│  • HUD (supply indicators, unit health, firebase status)                    │
│  • Minimap                                                                  │
│  • Camera System (RTS strategic zoom)                                       │
│  • Visual Effects (napalm, artillery impacts, glow on cleared areas)        │
│  • Audio (combat sounds, radio chatter, Huey rotor wash)                    │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  FEATURE LAYER                                                              │
│  ← Gameplay systems, AI, secondary mechanics                               │
├─────────────────────────────────────────────────────────────────────────────┤
│  • AI Director (dynamic difficulty, wave spawning)                          │
│  • VC Controller (guerrilla tactics AI)                                     │
│  • NVA Controller (conventional military AI)                                │
│  • Doctrine System (pre-mission force composition)                          │
│  • Reinforcement System (off-map requests, convoy/heli delivery)            │
│  • Helicopter System (auto-missions, LZ network)                            │
│  • Unit Resources (ammo, water, fatigue)                                    │
│  • Morale & Routing (unit psychology, fleeing to firebases)                 │
│  • Day/Night Cycle (time of day) — PARKED                                   │
│  • Weather System (rain, fog, monsoon) — PARKED                             │
│  • Campaign Structure (mission progression, persistent map) — PARTIAL       │
│  • Save System (serialization, checkpoints) — PLANNED                       │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  CORE LAYER                                                                 │
│  ← Core gameplay loops, physics, combat, movement                           │
├─────────────────────────────────────────────────────────────────────────────┤
│  • Combat System (suppression, cover, lethality, hitbox detection)          │
│    ⚠️  HIGH RISK: Uses Jolt physics (default in 4.6)                       │
│  • Firebase System (firebase levels, influence zones, HQ buildings)         │
│  • Supply & Logistics (physical trucks, helicopters, spatial chains)        │
│  • Construction System (work points, engineer assignment, building stages)  │
│  • Terrain Clearing (JUNGLE→CLEARED→FORTIFIED, det-cord, bulldozers)       │
│    ⚠️  HIGH RISK: Glow effects changed in 4.6 (before tonemapping now)     │
│  • Terrain Generation (procedural heightmap, jungle density)                │
│  • Cell Streaming (LOD-based terrain chunk loading)                         │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  FOUNDATION LAYER                                                           │
│  ← Engine integration, save/load, scene management, event bus               │
├─────────────────────────────────────────────────────────────────────────────┤
│  • Signal Bus (BattleSignals autoload - cross-system events)                │
│  • Spatial Hash Grid (O(1) unit queries for combat/AI)                      │
│  • Scene Management (firebase loading, unit spawning)                       │
│  • Input System (mouse/keyboard handling, selection box)                    │
│  • Save/Load Architecture (state serialization) — PLANNED                   │
│    ⚠️  MEDIUM RISK: FileAccess.store_* returns bool in 4.4+                │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  PLATFORM LAYER                                                             │
│  ← OS, hardware, Godot 4.6 API surface                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│  • Godot 4.6 Engine                                                         │
│    ⚠️  HIGH RISK: Jolt physics default, D3D12 default on Windows           │
│  • Windows Platform (primary target)                                        │
│  • Steam Integration (future)                                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Layer Ownership Summary

**Foundation Layer** owns:
- Cross-system communication (BattleSignals signal bus)
- Spatial query infrastructure (SpatialHashGrid)
- Scene lifecycle management
- Input event routing
- Serialization contracts (planned)

**Core Layer** owns:
- Game state (unit positions, firebase data, terrain state)
- Primary gameplay loops (clear→build→supply→defend)
- Physics simulation (projectiles, suppression areas, vehicle movement)
- Terrain procedural generation and streaming

**Feature Layer** owns:
- AI behavior trees and decision-making
- Meta-game systems (doctrine, reinforcements, campaign progression)
- Secondary resource systems (ammo, water, morale)

**Presentation Layer** owns:
- All visual representation (no game logic)
- User input interpretation (clicks → commands)
- Audio playback and mixing

---

## Module Ownership

### Foundation Layer Modules

| Module | Owns | Exposes | Consumes | Engine APIs Used | Risk |
|--------|------|---------|----------|------------------|------|
| **BattleSignals** | All cross-system signal definitions | Signal emission methods (`unit_died.emit()`, `request_reinforcements.emit()`) | Nothing (pure emitter) | `Signal` (native Godot) | LOW |
| **SpatialHashGrid** | Cell-based unit spatial indexing (20m cells) | `get_units_in_radius()`, `get_nearest_enemy()`, `register_unit()`, `unregister_unit()` | Unit positions (via registration) | `Dictionary`, `Vector3`, `AABB` | LOW |
| **SceneManagement** | Unit/firebase spawning, scene lifecycle | `spawn_unit()`, `load_firebase()`, `despawn_unit()` | BattleSignals (lifecycle events) | `PackedScene.instantiate()`, `Node.add_child()` | LOW |
| **InputRouter** | Raw input → game commands | `get_mouse_world_pos()`, `is_selecting()`, `get_selection_box()` | Camera (raycast target) | `Input`, `InputEvent`, `Camera3D.project_position()` | LOW |
| **SaveLoadSystem** *(planned)* | Serialization contracts, save file I/O | `save_game()`, `load_game()`, `get_serializable_state()` | All Core/Feature systems (state queries) | `FileAccess.open()`, `.store_*()` methods | MEDIUM ⚠️ |

**Foundation Layer Engine Risk Notes:**
- **SaveLoadSystem**: `FileAccess.store_*` methods now return `bool` in Godot 4.4+. Must check return values for write failures.
  - Verified: `docs/engine-reference/godot/breaking-changes.md` line 52

### Core Layer Modules

| Module | Owns | Exposes | Consumes | Engine APIs Used | Risk |
|--------|------|---------|----------|------------------|------|
| **CombatManager** | Combat resolution, damage calc, suppression state | `resolve_attack()`, `apply_suppression()`, `check_line_of_sight()` | SpatialHashGrid (target queries), BattleSignals (combat events) | `PhysicsRayQueryParameters3D`, `PhysicsDirectSpaceState3D` (Jolt) | HIGH ⚠️ |
| **FirebaseSystem** | Firebase levels, influence zones, HQ position | `create_firebase()`, `get_influence_radius()`, `upgrade_firebase()` | ConstructionManager (building placement), SupplyLogistics (depot linkage) | `Area3D`, `CollisionShape3D` | LOW |
| **SupplyLogistics** | Truck/heli routes, supply quantities, convoy state | `create_convoy()`, `request_resupply()`, `get_supply_at_firebase()` | Firebase (depot positions), SpatialHashGrid (convoy pathfinding) | `NavigationAgent3D`, `PathFollow3D` | MEDIUM ⚠️ |
| **ConstructionManager** | Work points, construction stages, engineer assignment | `create_build_job()`, `assign_worker()`, `get_construction_progress()` | TerrainClearing (cleared area check), BattleSignals (job events) | `Timer`, `Node3D` | LOW |
| **TerrainClearing** | Clearing stages (JUNGLE→CLEARED), cleared cell tracking | `mark_area_cleared()`, `get_clearing_stage()`, `create_clearing_job()` | TerrainGeneration (heightmap), BattleSignals (clearing events) | `MeshInstance3D`, `StandardMaterial3D.emission` (glow) | HIGH ⚠️ |
| **TerrainGeneration** | Procedural heightmap, jungle density, river placement | `generate_chunk()`, `sample_height()`, `get_jungle_density()` | Nothing (generates data) | `Image`, `ImageTexture`, `FastNoiseLite` | LOW |
| **CellStreamer** | Chunk LOD, async loading, unloading beyond view | `load_chunk_async()`, `unload_chunk()`, `get_active_chunks()` | TerrainGeneration (chunk data), Camera (view frustum) | `WorkerThreadPool.add_task()`, `RenderingServer` | LOW |

**Core Layer Engine Risk Notes:**
- **CombatManager**: Uses Jolt physics (Godot 4.6 default). Projectile physics and raycast queries tested with Jolt. HingeJoint3D `.damp` property NOT available if using Jolt.
  - Verified: `docs/engine-reference/godot/breaking-changes.md` line 11
- **TerrainClearing**: Glow on cleared areas uses `StandardMaterial3D.emission`. Glow now processes BEFORE tonemapping in 4.6 — visual intensity may differ from pre-4.6 expectations. Adjust `emission_energy` for correct brightness.
  - Verified: `docs/engine-reference/godot/breaking-changes.md` line 12
- **SupplyLogistics**: `NavigationAgent3D` uses dedicated NavigationServer3D (unchanged in 4.5+). Path-finding behavior stable.

### Feature Layer Modules

| Module | Owns | Exposes | Consumes | Engine APIs Used | Risk |
|--------|------|---------|----------|------------------|------|
| **AIDirector** | Wave spawning schedule, difficulty scaling, threat assessment | `spawn_wave()`, `get_threat_level()`, `adjust_difficulty()` | CombatManager (combat state), Firebase (positions), SpatialHashGrid (area queries) | `Timer`, `RandomNumberGenerator` | LOW |
| **VCController** | VC unit AI (guerrilla tactics, sapper behavior) | `update_ai()`, `get_attack_target()` | SpatialHashGrid (player unit queries), BattleSignals (attack orders) | `NavigationAgent3D` | LOW |
| **NVAController** | NVA unit AI (conventional assault, artillery coordination) | `update_ai()`, `coordinate_assault()` | SpatialHashGrid, BattleSignals | `NavigationAgent3D` | LOW |
| **DoctrineSystem** | Pre-mission force composition, doctrine bonuses | `apply_doctrine()`, `get_reinforcement_roster()` | ReinforcementSystem (unit availability) | `Resource` (doctrine data files) | LOW |
| **ReinforcementManager** | Off-map request queue, arrival timing, convoy/heli spawning | `request_reinforcements()`, `spawn_convoy()`, `spawn_heli_insertion()` | SupplyLogistics (convoy routes), HelicopterSystem (LZ availability), Doctrine (roster) | `Timer`, `PackedScene.instantiate()` | LOW |
| **HelicopterSystem** | Auto-mission loops, LZ network, Cobra escort | `create_lz()`, `schedule_resupply_mission()`, `request_medevac()` | Firebase (LZ positions), SupplyLogistics (resupply demand), BattleSignals (mission events) | `Path3D`, `PathFollow3D`, `AudioStreamPlayer3D` | MEDIUM ⚠️ |
| **UnitResources** | Ammo, water, fatigue tracking per unit | `consume_ammo()`, `request_resupply()`, `get_resource_level()` | SupplyLogistics (depot proximity), BattleSignals (resource events) | N/A (pure data) | LOW |
| **MoraleSystem** | Morale state, routing behavior, rally logic | `update_morale()`, `trigger_rout()`, `rally_unit()` | CombatManager (casualties, suppression), SpatialHashGrid (nearby ally/enemy counts) | N/A (pure logic) | LOW |
| **SaveSystem** *(planned)* | Save file versioning, checkpoint creation, campaign progress | `create_checkpoint()`, `save_campaign()` | All Core/Feature systems (state serialization) | `FileAccess`, `JSON` | MEDIUM ⚠️ |

**Feature Layer Engine Risk Notes:**
- **HelicopterSystem**: Flight paths use `Path3D` + `PathFollow3D`. No post-cutoff changes to these APIs. Rotor wash audio uses `AudioStreamPlayer3D` (unchanged).
- **SaveSystem**: See Foundation Layer SaveLoadSystem notes — `FileAccess.store_*` return values must be checked.

### Presentation Layer Modules

| Module | Owns | Exposes | Consumes | Engine APIs Used | Risk |
|--------|------|---------|----------|------------------|------|
| **SelectionManager** | Selected units, selection box rendering | `add_to_selection()`, `clear_selection()`, `get_selected_units()` | InputRouter (mouse events), SpatialHashGrid (box selection queries) | `ImmediateMesh`, `Camera3D.project_position()` | LOW |
| **BuildMenu** | Building type UI, placement ghost, cost display | `show_menu()`, `get_selected_building()` | Firebase (placement validation), SupplyManager (cost check) | `Control`, `Button`, `Label` | LOW |
| **HUD** | Supply bars, unit health, firebase status widgets | `update_supply_display()`, `show_unit_info()` | All Core/Feature systems (state queries) | `Control`, `ProgressBar`, `Label` | MEDIUM ⚠️ |
| **Minimap** | Top-down tactical view, fog of war | `update_minimap()`, `get_minimap_texture()` | Camera (viewport rect), Firebase (positions), Units (positions) | `SubViewport`, `ViewportTexture`, `TextureRect` | LOW |
| **RTSCamera** | Strategic zoom, WASD pan, middle-drag rotate | `set_zoom()`, `pan_to()`, `rotate_camera()` | InputRouter (keyboard/mouse) | `Camera3D`, `SpringArm3D` | LOW |
| **VFXManager** | Particle effects, explosions, napalm, tracers | `spawn_explosion()`, `play_napalm_effect()` | CombatManager (impact events), BattleSignals (effect triggers) | `GPUParticles3D`, `Mesh`, `StandardMaterial3D.emission` (glow) | HIGH ⚠️ |
| **AudioManager** | Combat sounds, radio chatter, ambient audio | `play_sound()`, `play_radio()`, `adjust_combat_music()` | BattleSignals (audio cues), CombatManager (combat intensity) | `AudioStreamPlayer3D`, `AudioBus` | LOW |

**Presentation Layer Engine Risk Notes:**
- **HUD**: Dual-focus system in Godot 4.6 means mouse/touch focus is separate from keyboard/gamepad focus. HUD widgets may receive focus differently depending on input method. Test focus behavior with both mouse and keyboard navigation.
  - Verified: `docs/engine-reference/godot/breaking-changes.md` line 16
- **VFXManager**: Glow on napalm/explosion effects uses `StandardMaterial3D.emission`. Glow processes BEFORE tonemapping in 4.6 — adjust `emission_energy` values downward from pre-4.6 expectations.
  - Verified: `docs/engine-reference/godot/breaking-changes.md` line 12

---

## Data Flow

### 1. Frame Update Path (Input → Core → State → Rendering)

```
Input Layer:
  Mouse/Keyboard → InputRouter.get_mouse_world_pos()
                      ↓
  Selection Events → SelectionManager.add_to_selection()
                      ↓
  Command Input (move, attack, build) → BattleSignals.emit(command_issued)

Core Update (_physics_process 60Hz):
  BattleSignals listeners → CombatManager.resolve_attacks()
                                ↓
                         SpatialHashGrid.get_units_in_radius()
                                ↓
                         Squad.take_damage() → update health
                                ↓
                         BattleSignals.unit_died.emit() if killed

Rendering (_process):
  HUD subscribes to BattleSignals → update health bars
  VFXManager subscribes → spawn death explosion
  AudioManager subscribes → play death sound
```

### 2. Event/Signal Path (Cross-System Communication)

**All cross-system communication flows through BattleSignals autoload.**

```
Example: Engineer completes clearing job

ConstructionManager (completes job):
  work_done >= work_required
    ↓
  BattleSignals.job_completed.emit(job_id, JobType.CLEAR_TERRAIN)

TerrainClearing (listens to job_completed):
  if job_type == CLEAR_TERRAIN:
    mark_area_cleared(job_id.cells)
      ↓
    BattleSignals.area_cleared.emit(cells, ClearingStage.CLEARED)

FirebaseSystem (listens to area_cleared):
  if cells overlap with pending firebase:
    allow_construction = true

VFXManager (listens to area_cleared):
  spawn_glow_effect(cells)  # Cleared area visual feedback
```

**Signal Naming Convention** (from BattleSignals autoload):
- Past tense for events: `unit_died`, `firebase_captured`, `job_completed`
- Present tense for requests: `request_reinforcements`, `call_airstrike`, `request_resupply`

### 3. Save/Load Path (Serialization Architecture)

**Planned — Not yet implemented. Architecture defined here for ADR-0006 reference.**

```
SaveLoadSystem.save_game():
  ↓
  Query all Core/Feature systems for serializable state:
    - FirebaseSystem.get_serializable_state() → JSON
    - CombatManager.get_serializable_state() → {active_combats, suppression_state}
    - SupplyLogistics.get_serializable_state() → {convoy_positions, depot_supply_levels}
    - TerrainClearing.get_serializable_state() → {cleared_cells_per_chunk}
    - etc.
  ↓
  Combine into master save file:
    {
      "version": "1.0",
      "timestamp": unix_timestamp,
      "terrain": {...},
      "firebases": [...],
      "units": [...],
      "supply": {...}
    }
  ↓
  FileAccess.open("user://saves/campaign_001.sav", WRITE)
  store_string(JSON.stringify(state))  ⚠️  Check return value (bool in 4.4+)
```

**Serialization Contracts:**
- Every Core/Feature system implements `get_serializable_state() -> Dictionary`
- SaveLoadSystem owns the master save file format versioning
- No system directly writes to disk — all go through SaveLoadSystem

### 4. Initialisation Order (Module Boot Sequence)

```
Foundation Layer Init (Autoloads, _ready() order):
  1. BattleSignals (pure signal definitions, no dependencies)
  2. SpatialHashGrid (depends on nothing, used by everyone)
  3. InputRouter (depends on nothing)
  4. SceneManagement (depends on BattleSignals for lifecycle events)

Core Layer Init (Scene load time):
  5. TerrainGeneration (depends on nothing, generates data)
  6. CellStreamer (depends on TerrainGeneration, Camera for view frustum)
  7. TerrainClearing (depends on TerrainGeneration for heightmap)
  8. ConstructionManager (depends on TerrainClearing for cleared area checks)
  9. FirebaseSystem (depends on ConstructionManager for building placement)
 10. SupplyLogistics (depends on Firebase for depot positions)
 11. CombatManager (depends on SpatialHashGrid, BattleSignals)

Feature Layer Init:
 12. DoctrineSystem (depends on nothing — reads data files)
 13. UnitResources (depends on SupplyLogistics for depot proximity checks)
 14. MoraleSystem (depends on CombatManager for casualty events)
 15. HelicopterSystem (depends on Firebase for LZ positions, SupplyLogistics for routes)
 16. ReinforcementManager (depends on Doctrine, SupplyLogistics, HelicopterSystem)
 17. AIDirector (depends on CombatManager, Firebase, SpatialHashGrid for threat assessment)
 18. VCController / NVAController (depends on SpatialHashGrid, BattleSignals)

Presentation Layer Init:
 19. RTSCamera (depends on InputRouter)
 20. SelectionManager (depends on InputRouter, Camera for raycasts)
 21. BuildMenu (depends on Firebase for placement validation)
 22. HUD (depends on all Core/Feature systems for state display)
 23. Minimap (depends on Camera, Firebase, Units)
 24. VFXManager (depends on BattleSignals for effect triggers)
 25. AudioManager (depends on BattleSignals for audio cues)
```

**Initialisation Rule:** Systems in lower layers init before systems in higher layers. Within a layer, init order is defined by explicit dependencies.

**Thread Boundaries:**
- Cell Streaming uses `WorkerThreadPool.add_task()` for async terrain loading
- All other systems run on main thread
- No data flows cross thread boundaries except TerrainGeneration → CellStreamer (thread-safe queue)

---

## API Boundaries

Public contracts between modules. All interfaces use GDScript's type system for compile-time safety.

### Foundation Layer API Contracts

#### BattleSignals (Signal Bus)

```gdscript
# battle_system/signals/battle_signals.gd
extends Node
class_name BattleSignals

# Combat Events (past tense)
signal unit_died(unit: Node3D, killer: Node3D)
signal unit_damaged(unit: Node3D, damage: float, source: Node3D)
signal firebase_captured(firebase: Node3D, new_faction: GameEnums.Faction)
signal job_completed(job_id: int, job_type: int)
signal area_cleared(cells: PackedVector2Array, stage: int)

# Combat Requests (present tense)
signal request_reinforcements(firebase: Node3D, unit_type: int, count: int)
signal call_airstrike(target_pos: Vector3, strike_type: int)
signal request_resupply(firebase: Node3D, supply_type: int, amount: float)
```

**Contract:**
- Emitters call `.emit()` with typed parameters
- Listeners connect in `_ready()` using `signal_name.connect(callable)`
- No return values — signals are fire-and-forget
- All listeners must handle invalid/null parameters gracefully

#### SpatialHashGrid (Spatial Queries)

```gdscript
# battle_system/ai/spatial_hash_grid.gd
extends Node
class_name SpatialHashGrid

# Register unit for spatial queries
func register_unit(unit: Node3D, faction: GameEnums.Faction) -> void

# Unregister unit (on death or despawn)
func unregister_unit(unit: Node3D) -> void

# Get all units within radius of position
func get_units_in_radius(pos: Vector3, radius: float, faction_filter: int = -1) -> Array[Node3D]

# Get nearest enemy to position
func get_nearest_enemy(pos: Vector3, my_faction: GameEnums.Faction, max_range: float = 1000.0) -> Node3D

# Get nearest ally to position
func get_nearest_ally(pos: Vector3, my_faction: GameEnums.Faction, max_range: float = 1000.0) -> Node3D
```

**Contract:**
- `register_unit()` must be called BEFORE querying for that unit
- `unregister_unit()` must be called on unit death to avoid stale references
- Queries return empty array / null if no units found
- Radius queries use `distance_squared` internally — avoid `sqrt()` in hot paths
- Faction filter: `-1` = all factions, or specific `GameEnums.Faction` value

#### SaveLoadSystem (Serialization) — PLANNED

```gdscript
# foundation/save_load_system.gd
extends Node
class_name SaveLoadSystem

# Save current game state to file
func save_game(filepath: String) -> bool  # Returns true on success

# Load game state from file
func load_game(filepath: String) -> bool  # Returns true on success

# Get serializable state from all systems
func get_serializable_state() -> Dictionary

# Apply loaded state to all systems
func apply_loaded_state(state: Dictionary) -> void
```

**Contract:**
- All Core/Feature systems must implement `get_serializable_state() -> Dictionary`
- SaveLoadSystem owns file format versioning — other systems provide raw state only
- `save_game()` returns `false` if FileAccess write fails (Godot 4.4+) ⚠️  MEDIUM RISK
- Load order matches init order (Foundation → Core → Feature → Presentation)

### Core Layer API Contracts

#### CombatManager (Combat Resolution)

```gdscript
# battle_system/systems/combat_manager.gd
extends Node
class_name CombatManager

# Resolve attack from attacker to target
func resolve_attack(attacker: Node3D, target: Node3D, weapon_data: WeaponData) -> Dictionary

# Apply suppression to unit
func apply_suppression(unit: Node3D, amount: float, source_pos: Vector3) -> void

# Check line of sight between two points
func check_line_of_sight(from: Vector3, to: Vector3, ignore: Array[Node3D] = []) -> bool

# Get units in suppression area (cone or circle)
func get_suppressed_units_in_area(center: Vector3, radius: float) -> Array[Node3D]
```

**Contract:**
- `resolve_attack()` returns `{hit: bool, damage: float, crit: bool}`
- Combat resolution emits `unit_damaged` or `unit_died` signals via BattleSignals
- Line-of-sight uses Jolt physics raycasts (Godot 4.6 default) ⚠️  HIGH RISK
- Suppression is spatial — uses `SpatialHashGrid` for area queries

#### FirebaseSystem (Firebase Management)

```gdscript
# firebase_system/firebase_system.gd
extends Node
class_name FirebaseSystem

# Create new firebase at position
func create_firebase(pos: Vector3, faction: GameEnums.Faction, level: int = 0) -> Firebase

# Get influence radius for firebase level
func get_influence_radius(level: int) -> float

# Upgrade firebase to next level
func upgrade_firebase(firebase: Firebase) -> bool  # Returns false if can't upgrade

# Check if position is within firebase influence
func is_within_firebase_influence(pos: Vector3, faction: GameEnums.Faction) -> bool
```

**Contract:**
- Firebase levels: 0 (Patrol Base), 1 (Fire Support Base), 2 (Major Firebase)
- Influence radius scales with level: 100m, 150m, 200m
- Construction must be within influence radius (automated) or manually placed outside
- Firebase positions tracked in SpatialHashGrid for proximity queries

#### ConstructionManager (Job System)

```gdscript
# firebase_system/construction_manager.gd
extends Node
class_name ConstructionManager

# Create build job at position
func create_build_job(pos: Vector3, building_type: int, rotation: float = 0.0) -> int  # Returns job_id

# Create clearing job in area
func create_clearing_job(center: Vector3, radius: float) -> int

# Assign worker to job
func assign_worker(job_id: int, worker: Node3D) -> bool

# Get construction progress (0.0 to 1.0)
func get_construction_progress(job_id: int) -> float

# Cancel job and refund supply
func cancel_job(job_id: int) -> void
```

**Contract:**
- Jobs must be on cleared terrain (check `TerrainClearing.get_clearing_stage()` first)
- Workers auto-assign via bottom-up scoring (ADR-0005)
- Progress updates emitted via `BattleSignals.job_progress_updated`
- Completion emits `BattleSignals.job_completed` signal

#### TerrainClearing (Clearing System)

```gdscript
# terrain/systems/clearing_system.gd
extends Node
class_name TerrainClearing

# Mark area as cleared (from job completion)
func mark_area_cleared(cells: PackedVector2Array, stage: int) -> void

# Get clearing stage for cell
func get_clearing_stage(cell: Vector2i) -> int  # Returns ClearingStage enum

# Create clearing job
func create_clearing_job(center: Vector3, radius: float) -> int

# Check if position is cleared enough for building
func is_buildable(pos: Vector3) -> bool
```

**Contract:**
- Clearing stages: `JUNGLE` (0), `PARTIALLY_CLEARED` (1), `CLEARED` (2), `FORTIFIED` (3)
- Cleared areas show glow via `StandardMaterial3D.emission` ⚠️  HIGH RISK (glow changed in 4.6)
- Emits `area_cleared` signal for visual feedback via BattleSignals
- Building requires stage ≥ `CLEARED`

---

## ADR Audit + Traceability

### ADR Quality Check

The project references 5 ADRs in the TR registry, but **these ADR files do not yet exist in `docs/architecture/`**. They are conceptual decisions documented in the prior architecture review (2026-05-21) and referenced throughout the codebase, but not yet formalized as standalone ADR documents.

**Referenced ADRs and their coverage:**

| ADR | Title (inferred from TR registry) | Engine Compat | Version | GDD Linkage | Conflicts | Status |
|-----|-----------------------------------|--------------|---------|-------------|-----------|--------|
| ADR-0001 | Terrain Chunk Streaming | ❌ Not yet written | N/A | ✅ (terrain, firebase, supply GDDs) | None | **Missing** |
| ADR-0002 | Vegetation LOD System | ❌ Not yet written | N/A | ✅ (terrain-clearing GDD) | None | **Missing** |
| ADR-0003 | Spatial Hash Grid | ❌ Not yet written | N/A | ✅ (combat, morale, AI GDDs) | None | **Missing** |
| ADR-0004 | Signal Bus Architecture | ❌ Not yet written | N/A | ✅ (combat, firebase, supply, morale, doctrine, AI, heli, reinforcement, unit resources GDDs) | None | **Missing** |
| ADR-0005 | Job System (Bottom-Up Worker Assignment) | ❌ Not yet written | N/A | ✅ (firebase, construction GDDs) | None | **Missing** |

**Critical Finding:** All 5 ADRs are referenced in code, the TR registry, and this master architecture document, but none have been written as formal ADR documents with Engine Compatibility sections, GDD Requirements Addressed sections, or ADR Dependencies sections.

### Traceability Coverage

Based on the TR registry (`docs/architecture/tr-registry.yaml`):

| Metric | Value |
|--------|-------|
| **Total Requirements** | 58 |
| **✅ Covered** | 45 (77.6%) |
| **❌ Gaps** | 13 (22.4%) |

**Coverage by Domain:**

| Domain | Requirements | Covered | Gap |
|--------|-------------|---------|-----|
| Spatial Queries | 8 | 8 | 0 |
| Signal/Events | 12 | 12 | 0 |
| Terrain/Chunks | 10 | 10 | 0 |
| Vegetation LOD | 4 | 4 | 0 |
| Job/Construction | 9 | 9 | 0 |
| **Save/Serialization** | **6** | **0** | **6** ⚠️ |
| **Pathfinding/Nav** | **5** | **2** | **3** ⚠️ |
| **UI/HUD** | **4** | **0** | **4** ⚠️ |

**Foundation Layer Coverage:** 100% (all requirements covered by ADR-0003, ADR-0004)
**Core Layer Coverage:** 89% (terrain + construction covered; save system gap)
**Feature Layer Coverage:** 60% (AI gaps in nav, UI gaps in indicators)

### Gap Requirements (No ADR)

**HIGH PRIORITY — Foundation/Core Layer Gaps:**

| TR-ID | Requirement | GDD | Layer | Suggested ADR |
|-------|-------------|-----|-------|---------------|
| TR-SAVE-001 | Serialization architecture | save-system.md | Foundation | ADR-0006: Save/Serialization System |
| TR-SAVE-002 | State in data structures, not scene graph | save-system.md | Foundation | ADR-0006 |
| TR-SAVE-003 | All systems implement serialize/deserialize | save-system.md | Foundation | ADR-0006 |
| TR-SAVE-004 | Checkpoint system for mission reload | save-system.md | Feature | ADR-0006 |
| TR-SAVE-005 | Campaign persistence between missions | save-system.md | Feature | ADR-0006 |
| TR-SAVE-006 | Version migration for save compatibility | save-system.md | Foundation | ADR-0006 |

**MEDIUM PRIORITY — Feature Layer Gaps:**

| TR-ID | Requirement | GDD | Layer | Suggested ADR |
|-------|-------------|-----|-------|---------------|
| TR-MOR-003 | Routing pathfinding to nearest firebase | morale-routing.md | Feature | ADR-0007: Navigation Mesh Architecture |
| TR-REI-003 | Road network pathfinding for convoys | reinforcement-system.md | Feature | ADR-0007 |
| TR-TC-004 | Clearing affects pathfinding nav costs | terrain-clearing.md | Core | ADR-0007 |

**LOW PRIORITY — Presentation Layer Gaps:**

| TR-ID | Requirement | GDD | Layer | Suggested ADR |
|-------|-------------|-----|-------|---------------|
| TR-CMB-004 | Cover/suppression indicators | combat-system.md | Presentation | ADR-0008: HUD/Indicator System |
| TR-FB-004 | Influence radius visualization | firebase-system.md | Presentation | ADR-0008 |
| TR-MOR-004 | Morale state visual indicators | morale-routing.md | Presentation | ADR-0008 |
| TR-UNR-003 | Floating resource icons (ammo/water) | unit-resources.md | Presentation | ADR-0008 |

### Cross-ADR Conflicts

**No conflicts detected** between referenced ADRs (based on prior architecture review 2026-05-21):
- ADR-0001 and ADR-0002 coordinate correctly (terrain chunks own vegetation)
- ADR-0003 and ADR-0004 are independent foundational systems (no shared state)
- ADR-0005 depends on ADR-0004 (Signal Bus) for job event communication

### ADR Dependency Order

**Topologically sorted implementation order** (based on TR registry dependencies):

**Foundation Layer (no dependencies):**
1. **ADR-0001**: Terrain Chunk Streaming
2. **ADR-0003**: Spatial Hash Grid
3. **ADR-0004**: Signal Bus Pattern

**Core Layer (depends on Foundation):**
4. **ADR-0002**: Vegetation LOD System (requires ADR-0001 for chunk integration)
5. **ADR-0005**: Job System Architecture (requires ADR-0004 for event bus)

**Feature Layer (recommended new ADRs):**
6. **ADR-0006**: Save/Serialization System (requires all gameplay systems — write AFTER Core layer is implemented)
7. **ADR-0007**: Navigation Mesh Architecture (requires ADR-0001 for terrain integration)
8. **ADR-0008**: HUD/Indicator System (requires ADR-0004 for event subscriptions)

**No circular dependencies detected.**

### Engine Compatibility Audit

Based on the prior architecture review (2026-05-21), all 5 referenced ADRs are conceptually compatible with Godot 4.6:

| ADR | Engine Version Target | Compatibility | Issues |
|-----|----------------------|---------------|--------|
| ADR-0001 | Godot 4.6 | ✅ Full (conceptual) | None — chunk streaming uses standard `WorkerThreadPool` |
| ADR-0002 | Godot 4.6 | ✅ Full (conceptual) | None — billboard LOD uses `MultiMeshInstance3D` |
| ADR-0003 | Godot 4.6 | ✅ Full (conceptual) | None — pure GDScript, no engine-specific APIs |
| ADR-0004 | Godot 4.6 | ✅ Full (conceptual) | None — native `Signal` support unchanged |
| ADR-0005 | Godot 4.6 | ✅ Full (conceptual) | None — job assignment logic is pure code |

**Deprecated API References:** None (ADRs not yet written — no code to audit)
**Post-Cutoff API Conflicts:** None identified in conceptual design
**Stale Version References:** None

**HOWEVER:** The 5 referenced ADRs **lack formal Engine Compatibility sections** because they are not yet written as ADR documents. When these ADRs are authored using `/architecture-decision`, each must include:
- Engine version stamp (Godot 4.6)
- Post-Cutoff APIs Used section with verification references
- Knowledge Risk rating (HIGH/MEDIUM/LOW)
- Engine compatibility notes for any HIGH RISK domains touched

### Missing Engine Compatibility Coverage

The following systems touch **HIGH RISK engine domains** but have no formal ADR with engine compatibility documentation:

**Physics (HIGH RISK — Jolt default in 4.6):**
- CombatManager (uses `PhysicsRayQueryParameters3D` for line-of-sight)
- Suppression system (area queries via Jolt spatial queries)
- **Required:** ADR-0003 (Spatial Hash Grid) should document why it does NOT use Jolt spatial queries directly (uses custom grid instead)

**Rendering (HIGH RISK — Glow changed in 4.6):**
- TerrainClearing (glow on cleared areas via `StandardMaterial3D.emission`)
- VFXManager (napalm effects, explosion glow)
- **Required:** ADR-0002 (Vegetation LOD) should document glow usage on vegetation transitions

**Save System (MEDIUM RISK — FileAccess.store_* changed in 4.4):**
- SaveLoadSystem (not yet designed)
- **Required:** ADR-0006 (Save System) must document FileAccess return value checking

---

## Required New ADRs

### Priority 1: Foundation Layer (Write Before Pre-Production)

**All 5 conceptual ADRs must be formalized:**

1. **`/architecture-decision "Terrain Chunk Streaming and LOD System"`** → **ADR-0001**
   - **Covers:** TR-FB-001, TR-SUP-001, TR-TC-001, TR-TC-003 (10 requirements total)
   - **Engine Risk:** LOW
   - **Why first:** Foundation for all terrain-based systems; Core layer depends on this
   - **Must document:** `WorkerThreadPool` async loading, chunk size rationale, LOD distance formulas

2. **`/architecture-decision "Spatial Hash Grid for Unit Queries"`** → **ADR-0003**
   - **Covers:** TR-CMB-001, TR-CMB-003, TR-MOR-002, TR-AI-001, TR-UNR-002 (8 requirements)
   - **Engine Risk:** LOW (pure GDScript)
   - **Why second:** Independent foundational system; many Core systems depend on this
   - **Must document:** Cell size (20m), why custom grid over Jolt spatial queries

3. **`/architecture-decision "Signal Bus Pattern for Cross-System Events"`** → **ADR-0004**
   - **Covers:** TR-CMB-002, TR-FB-002, TR-SUP-002, TR-MOR-001, TR-DOC-001, TR-AI-002, TR-HEL-001, TR-HEL-002, TR-REI-001, TR-REI-002, TR-UNR-001 (12 requirements)
   - **Engine Risk:** LOW
   - **Why third:** Independent foundational system; ADR-0005 depends on this
   - **Must document:** Signal naming conventions (past tense for events, present for requests), BattleSignals autoload structure

### Priority 2: Core Layer (Write Before Vertical Slice)

4. **`/architecture-decision "Vegetation LOD with 3D/Billboard Hysteresis"`** → **ADR-0002**
   - **Covers:** TR-TC-002, TR-VEG-001, TR-VEG-002 (4 requirements)
   - **Engine Risk:** HIGH ⚠️ (Glow rendering changed in 4.6)
   - **Depends On:** ADR-0001 (terrain chunks)
   - **Must document:** LOD distance thresholds, hysteresis buffer, glow emission intensity values for Godot 4.6 post-tonemapping behavior

5. **`/architecture-decision "Bottom-Up Worker Assignment for Jobs"`** → **ADR-0005**
   - **Covers:** TR-FB-002, TR-FB-003, TR-CON-001, TR-CON-002, TR-CON-003 (9 requirements)
   - **Engine Risk:** LOW
   - **Depends On:** ADR-0004 (signal bus for job events)
   - **Must document:** Scoring algorithm, worker idle state detection, job cancellation rules

### Priority 3: Feature Layer (Write Before Production Sprint Planning)

6. **`/architecture-decision "Save/Load Serialization Architecture"`** → **ADR-0006**
   - **Covers:** TR-SAVE-001 through TR-SAVE-006 (6 requirements)
   - **Engine Risk:** MEDIUM ⚠️ (`FileAccess.store_*` returns bool in 4.4+)
   - **Depends On:** All Core layer ADRs (serializes their state)
   - **Must document:** Save file format (JSON recommended), version migration strategy, FileAccess return value checking pattern

7. **`/architecture-decision "Navigation Mesh Integration with Dynamic Terrain"`** → **ADR-0007**
   - **Covers:** TR-MOR-003, TR-REI-003, TR-TC-004 (3 requirements)
   - **Engine Risk:** LOW (NavigationServer3D stable in 4.5+)
   - **Depends On:** ADR-0001 (terrain clearing updates nav mesh)
   - **Must document:** How cleared terrain updates nav costs, convoy pathfinding on roads vs offroad

### Priority 4: Presentation Layer (Defer Until UI Implementation)

8. **`/architecture-decision "HUD Indicator System for Real-Time Feedback"`** → **ADR-0008**
   - **Covers:** TR-CMB-004, TR-FB-004, TR-MOR-004, TR-UNR-003 (4 requirements)
   - **Engine Risk:** MEDIUM ⚠️ (Dual-focus system in 4.6)
   - **Depends On:** ADR-0004 (subscribes to signals for updates)
   - **Must document:** Floating UI world-space indicators, dual-focus handling (mouse vs keyboard navigation)

---

## Architecture Principles

Five core principles govern all technical decisions for RealVietnamRTS:

### 1. **Emergent Complexity from Simple Rules**
The Six Pillars should interact to create unexpected gameplay moments. No system should be designed in isolation — always consider cross-system effects. Example: Terrain clearing affects pathfinding costs, which affects convoy timing, which affects supply delivery, which affects firebase sustainability.

### 2. **Player Intent Over Micromanagement**
Systems should execute standing orders without constant player input (Pillar 5: The War Continues). Design for "set it and forget it" automation with strategic decision points, not tactical busywork. Example: Helicopter auto-missions run on schedules; player adjusts missions, not every flight.

### 3. **Spatial Relationships Are Gameplay**
Physical position matters. Supply chains are attackable. Firebase influence zones define safe areas. Cleared terrain enables movement. Use spatial queries (`SpatialHashGrid`) and visual feedback (glow, HUD indicators) to make spatial state obvious.

### 4. **Event-Driven Loose Coupling**
Systems communicate via `BattleSignals` signal bus, not direct references. This enables modular design, easier testing, and clean save/load (no circular dependencies in serialized state). Signals are named in past tense (events) or present tense (requests).

### 5. **Godot 4.6 Post-Cutoff Awareness**
The LLM's training data predates Godot 4.4/4.5/4.6. Always flag HIGH/MEDIUM RISK engine APIs with verification references to `docs/engine-reference/godot/`. Test assumptions about physics (Jolt), rendering (glow), and core APIs (`FileAccess` return values) before committing to implementation.

---

## Open Questions

**No open questions at this time.** All architectural decisions for Foundation and Core layers are defined (pending ADR formalization). Feature layer gaps (Save, Nav, HUD) are documented but deferred until their respective implementation phases.

When new questions arise, they will be added here in this format:

```
### QQ-001: [Question Title]
- **Domain**: [Architecture / Engine / Design]
- **Blocking**: [Yes/No] — Does this block current work?
- **Resolution Path**: [ADR / GDD revision / Prototype / User decision]
- **Context**: [What decision depends on this answer?]
```

---

