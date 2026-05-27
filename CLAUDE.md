# RealVietnamRTS - Project Guidelines

<!-- Claude Code Game Studios Integration -->
<!-- 49 coordinated agents, 73 workflow skills, structured game development -->

## Agent Architecture

@.claude/docs/coordination-rules.md

## Technical Stack

- **Engine**: Godot 4.6
- **Language**: GDScript
- **Version Control**: Git with trunk-based development

@.claude/docs/technical-preferences.md

> **First session?** Run `/start` to begin guided onboarding, or `/project-stage-detect` to assess current state.

---

## Godot-First Development Philosophy

**PREFER GODOT EDITOR OVER SCRIPTS.** Use the engine's visual tools rather than writing GDScript for everything.

### Scene Files Over Code Instantiation
```gdscript
# BAD - Creating nodes in code
var bunker := StaticBody3D.new()
bunker.add_child(model)
bunker.add_child(collision)
get_tree().current_scene.add_child(bunker)

# GOOD - Use pre-made scene files
var bunker := preload("res://game/scenes/buildings/bunker.tscn").instantiate()
get_tree().current_scene.add_child(bunker)
```

### @export Variables Over Hardcoded Values
```gdscript
# BAD - Magic numbers in code
const INFLUENCE_RADIUS := 168.0
const SUPPLY_COST := 50

# GOOD - Configurable in Inspector
@export var influence_radius: float = 168.0
@export var supply_cost: int = 50
```

### Node Composition Over Script Inheritance
```gdscript
# BAD - Deep inheritance chains
class_name AdvancedBunker extends ReinforcedBunker extends Bunker extends BaseStructure

# GOOD - Compose with child nodes
# Bunker.tscn contains:
#   - StaticBody3D (root with bunker.gd)
#   - Model (Node3D)
#   - CollisionShape3D
#   - GarrisonSlot (Marker3D)
#   - WeaponMount (Node3D with weapon_mount.gd)
```

### Resources (.tres) Over Script Configuration
```gdscript
# BAD - Huge match statements for building data
match building_type:
    BuildingType.TOC: return {"cost": 80, "radius": 168}
    BuildingType.BUNKER: return {"cost": 40, "radius": 0}

# GOOD - Resource files per building type
# res://data/buildings/toc.tres
# res://data/buildings/bunker.tres
var data: BuildingData = load("res://data/buildings/%s.tres" % building_name)
```

### When to Use Scripts
- **State machines** - Combat states, AI behavior
- **Complex calculations** - Pathfinding, damage formulas
- **System coordination** - Signals, autoloads
- **Runtime generation** - Procedural terrain, spawning waves

### When to Use Godot Editor
- **Placing objects** - Buildings, units, props in levels
- **Configuring values** - Stats, costs, radii via @export
- **Defining data** - Resources (.tres) for items, units, buildings
- **UI layout** - Control nodes, themes, anchors
- **Animation** - AnimationPlayer, tweens, state machines

### Building Scene Locations
All placeable buildings live in `game/scenes/buildings/`:
- `toc.tscn` - Tactical Operations Center (HQ)
- `bunker.tscn`, `sandbag_bunker.tscn`, `conex_bunker.tscn`
- `mg_nest.tscn`, `mortar_pit.tscn`, `observation_tower.tscn`
- etc.

Use `PlacedBuilding` script for scene-placed buildings that auto-register with Firebase system.

---

> **CRITICAL: Read GAME_BIBLE.md before ANY work.** This file is a quick reference; the Bible is authoritative.

## Game Bible

**The single source of truth is `GAME_BIBLE.md` in this directory.**

Before implementing ANY feature, check:
1. Does it serve one of the Five Pillars?
2. Is it in the MVP roster?
3. Is there a `[LOCKED]` decision about it?
4. Is it in the Explicit Exclusions list?

## Vision
**Logistics-first Vietnam War RTS** - Carve a battlespace out of jungle, build interlocking firebase networks, run physical supply chains under constant threat. References: RUSE, Supreme Commander, Company of Heroes, Warno, Broken Arrow.

## Project Location
`C:\Users\caleb\RealVietnamRTS`

## The Five Pillars

1. **Carve the Map** - Terrain opaque until cleared. Bulldozers cut roads, engineers use det-cord.
2. **Network of Firebases** - Build interlocking positions with LZs and road links.
3. **Physical Supply Chains** - Trucks on roads, helicopters to LZs. Supply is spatial and attackable.
4. **Doctrine Over Spam** - Pre-mission deck commits force composition. Reinforcements arrive over minutes.
5. **The War Continues** - Patrols run on standing orders. Defenses auto-fire. You command operations.

## Key Directories

```
RealVietnamRTS/
├── battle_system/           # Core combat, signals, AI, data
│   ├── ai/                  # VCController, NVAController, SpatialHashGrid
│   ├── camera/              # RTS camera
│   ├── data/                # GameEnums, VietnamUnitData, WeaponData
│   ├── nodes/               # Squad, Vehicle base classes
│   ├── signals/             # BattleSignals central signal bus
│   └── systems/             # CombatManager, AirSupportManager, WeatherSystem
├── firebase_system/         # Base building
│   ├── firebase.gd          # Firebase class with levels and zones
│   ├── construction_manager.gd
│   ├── construction_zone.gd
│   └── terrain_clearing.gd
├── helicopter_system/       # Air mobility
│   ├── insertion_manager.gd
│   ├── heli_mission.gd
│   └── landing_zone.gd
├── reinforcement_system/    # Off-map reinforcements
│   ├── reinforcement_manager.gd
│   └── convoy_manager.gd
├── sog_system/              # Special operations
│   └── sog_team.gd
├── village_system/          # Hearts and minds
│   └── village.gd
├── tunnel_system/           # VC tunnels
│   └── tunnel_network.gd
├── map_maker/               # Procedural terrain
│   ├── vietnam_terrain.gd   # Heightmap generation
│   ├── vietnam_cell.gd      # Cell generation
│   ├── vietnam_world_grid.gd
│   ├── cell_streamer.gd     # LOD streaming
│   ├── trail_network.gd
│   ├── river_generator.gd
│   └── village_placer.gd
├── campaign/                # Historical campaigns
│   └── campaign.gd          # Campaign, Mission, Objective classes
├── game/                    # Game scenes and scripts
│   ├── scenes/              # Unit and structure scenes
│   └── scripts/             # Game logic
├── scenes/                  # Main scenes
│   └── main.tscn
└── assets/                  # Models, textures, audio
    └── models/structures/   # Building models organized by category
        ├── firebase/        # Firebase perimeter, support, living
        ├── village/         # Vietnamese village buildings
        ├── airfield/        # Airport and runway structures
        ├── colonial/        # French colonial buildings
        ├── infrastructure/  # Bridges, roads, ports
        ├── vc_nva/          # VC/NVA special structures
        ├── ruins/           # Destroyed/damaged variants
        ├── cham/            # Ancient Cham temple ruins
        ├── commercial/      # Marketplace buildings
        └── converted/       # Spring 1944 converted models
```

## Architecture

### Autoloads (Global Singletons)
| Autoload | Path | Purpose |
|----------|------|---------|
| `BattleSignals` | `battle_system/signals/battle_signals.gd` | Central signal bus |
| `GameEnums` | `battle_system/data/game_enums.gd` | All game enumerations |
| `SpatialHashGrid` | `battle_system/ai/spatial_hash_grid.gd` | Efficient spatial queries |
| `CombatManager` | `battle_system/systems/combat_manager.gd` | Combat resolution |
| `AirSupportManager` | `battle_system/systems/air_support_manager.gd` | Air strikes |
| `WeatherSystem` | `battle_system/systems/weather_system.gd` | Weather effects |
| `ReinforcementManager` | `reinforcement_system/reinforcement_manager.gd` | Off-map reinforcements |
| `InsertionManager` | `helicopter_system/insertion_manager.gd` | Helicopter insertions |
| `TerrainClearingSystem` | `firebase_system/terrain_clearing.gd` | Jungle clearing |
| `ConstructionManager` | `firebase_system/construction_manager.gd` | Building system |

### Factions
| Enum | Description |
|------|-------------|
| `US_ARMY` | American forces with air superiority |
| `ARVN` | South Vietnamese allies |
| `VC` | Viet Cong guerrillas (tunnels, ambushes) |
| `NVA` | North Vietnamese Army regulars (conventional tactics) |

### Key Systems

#### Firebase System
- Terrain must be cleared before building: `JUNGLE` -> `PARTIALLY_CLEARED` -> `CLEARED` -> `FORTIFIED`
- Progressive construction stages: `FOUNDATION` -> `STRUCTURE` -> `FINISHING` -> `COMPLETE`
- Building slots expand with firebase level:
  - `PATROL_BASE`: 4 slots
  - `FIRE_SUPPORT_BASE`: 8 slots
  - `MAJOR_FIREBASE`: 12 slots

#### Helicopter System
- Auto-mission loops: supply, medevac, rotation, recon
- LZ network with hot/cold status
- Flight paths with Cobra escort coordination

#### Reinforcement System
- No barracks - request from off-map base camp
- Helicopter insertion or convoy delivery
- Vulnerable to ambush/interception

#### SOG System
- 6-man special ops teams with stealth rating
- Mission types: RECON, PRISONER_SNATCH, WIRE_TAP, BDA, TRAIL_WATCH, DIRECT_ACTION
- Emergency extraction when compromised

#### Enemy AI
- `VCController` - Guerrilla tactics, tunnels, sappers, village sympathizers
- `NVAController` - Conventional military with artillery, armor, AAA umbrella

## Coding Standards

### GDScript Style
```gdscript
class_name ClassName extends ParentClass

# Constants first
const MAX_SQUAD_SIZE := 12

# Enums
enum State { IDLE, MOVING, COMBAT }

# Exported variables
@export var unit_data: VietnamUnitData

# Public variables
var current_state: State = State.IDLE

# Private variables (underscore prefix)
var _internal_timer: float = 0.0

# @onready variables
@onready var _sprite: Sprite3D = $Sprite3D

# Lifecycle methods
func _ready() -> void:
    pass

func _process(delta: float) -> void:
    pass

# Public methods
func take_damage(amount: float, source: Node) -> void:
    pass

# Private methods (underscore prefix)
func _update_state() -> void:
    pass
```

### Signal Naming
- Past tense for events that happened: `unit_died`, `firebase_captured`
- Present tense for requests: `request_reinforcements`, `call_airstrike`

### Type Safety
Always use explicit type annotations when dealing with:
- `get_node_or_null()`, `get_nodes_in_group()`
- Dictionary access
- `max()`, `min()`, `abs()` - use `maxf()`, `minf()`, `absf()` for floats
- Array `pop_front()`, `pop_back()`
- Autoload property/method access

## Asset Pipeline

### S3O to Godot Workflow
1. Import S3O in Blender using s3o-Blender-plugins-2022
2. Clean up S3O attribute nodes
3. Export as GLTF 2.0
4. Import to Godot `assets/models/`

### Source Repos
- Spring 1944 Models: `C:\Users\caleb\spring1944-models`
- Spring 1944 Game: `C:\Users\caleb\spring1944-game`

### Available Models (from Spring 1944)
| Asset Type | S3O Path | Use For |
|------------|----------|---------|
| US Infantry (stand-in) | `FRAInfantry/s3o/FRARifle.s3o` | US Rifle Platoon |
| US Engineers | `FRAInfantry/s3o/FRAEngineer.s3o` | Combat Engineers |
| VC Infantry (stand-in) | `FINInfantry/s3o/FINRifle.s3o` | VC Infantry |
| Bunkers | `FRABunkers/s3o/*.s3o` | Firebase structures |
| US Jeep | `USJeep/s3o/USJeep.s3o` | Light transport |
| US Halftrack | `USM3A1Halftrack/s3o/*.s3o` | APC, troop transport |

## Historical Campaigns

| Campaign | Year | Mission Types | Key Features |
|----------|------|---------------|--------------|
| **Ia Drang** | 1965 | Air Assault, Defense | First Air Cav battle, "Broken Arrow" |
| **Junction City** | 1967 | Search & Destroy | Largest airborne op, find COSVN |
| **Khe Sanh** | 1968 | 77-day Siege | Firebase defense, B-52 Arc Light |
| **Tet - Hue** | 1968 | Urban Combat | House-to-house, citadel assault |
| **Hamburger Hill** | 1969 | Assault | Uphill assault, high casualties |
| **Lam Son 719** | 1971 | Cross-border | Into Laos, heavy NVA resistance |

## Testing Scenarios

1. **Firebase Construction** - Clear jungle, build from scratch
2. **Air Assault** - Helicopter insertion under fire
3. **Tunnel Attack** - VC breach firebase perimeter
4. **NVA Offensive** - Conventional assault with armor
5. **SOG Recon** - Insert, observe, emergency extraction
6. **Napalm Strike** - Air support, jungle clearing
7. **Supply Convoy** - Survive ambush between firebases

## Performance Targets

- 60 FPS with 300-500 units
- Efficient spatial hashing for unit queries
- LOD system for large battles
- Cell streaming for large maps

## Reference Documents

| Document | Path | Contents |
|----------|------|----------|
| **RTS Architecture Patterns** | `docs/reference/rts_architecture_patterns.md` | Flow fields, spatial partitioning, update budgeting, MultiMesh rendering, formation movement, state machines |
| **War Room Sessions** | `production/war_room/` | Architectural decisions and research synthesis |

### Quick Reference: RTS Patterns

**Pathfinding Decision:**
- 1-20 units → A* with smoothing
- 20-100 units → Flow Field (cache by destination)
- 100+ units → Flow Field + aggressive caching

**Spatial Grid:** 16m cell size, uniform grid beats quadtree for RTS

**Update Budget:** 2-3ms per frame, priority tiers (CRITICAL→DORMANT)

**Rendering:** One MultiMesh per unit type, Animation LOD at 30m/80m/150m

## Weapon Balance

| Weapon | Damage | Range (m) | ROF | Suppression |
|--------|--------|-----------|-----|-------------|
| M16 | 15 | 300 | 700 | 5 |
| M60 | 25 | 500 | 550 | 30 |
| M79 | 80 | 350 | 6 | 40 |
| M72 LAW | 200 | 200 | 0.5 | 50 |
| AK47 | 18 | 300 | 600 | 6 |
| RPG7 | 250 | 150 | 4 | 60 |
| M102 Howitzer | 500 | 11000 | 3 | 100 |
| Napalm | 150 | Area | N/A | 100 |

## Building System

### Building Categories (114 total building types)
| Category | Count | Description |
|----------|-------|-------------|
| Firebase Perimeter | 10 | Defensive positions (bunkers, wire, towers) |
| Firebase Support | 10 | Logistics (helipads, ammo, fuel, medical, comms) |
| Firebase Living | 7 | Living quarters (hootch, mess hall, latrines) |
| Firebase Heavy | 6 | Artillery and vehicle positions |
| Vietnamese Village | 15 | Traditional structures (huts, pagodas, wells) |
| Airfield | 19 | Runways, hangars, control towers |
| French Colonial | 9 | Villas, barracks, government buildings |
| Infrastructure | 11 | Bridges, roads, ports |
| VC/NVA Special | 8 | Tunnels, spider holes, caches |
| Ruins | 12 | Destroyed/bombed variants |
| Cham Ruins | 3 | Ancient temple structures |
| Commercial | 4 | Markets and shops |

### Building Costs (Player-Constructible)
| Building | Supply | Work Stages | Notes |
|----------|--------|-------------|-------|
| Sandbag Wall | 5 | [20, 20, 10] | Basic cover |
| Bunker | 40 | [40, 60, 40] | Garrison 8 |
| Sandbag Bunker | 25 | [25, 35, 25] | Garrison 4, PSP cover |
| CONEX Bunker | 45 | [30, 50, 30] | Garrison 6, armored |
| MG Nest | 30 | [30, 40, 30] | Auto-fire 500m range |
| Mortar Pit | 35 | [30, 50, 30] | Indirect fire 3.5km |
| Wire Obstacle | 10 | [15, 15, 10] | Slows 70%, 2 DPS |
| Triple Concertina | 15 | [20, 20, 15] | Slows 80%, 4 DPS |
| Watchtower | 25 | [30, 40, 30] | +60m sight, Garrison 2 |
| Observation Tower | 30 | [35, 45, 30] | +80m sight, 8m tall |
| Helipad | 50 | [40, 50, 40] | Landing zone |
| PSP Helipad | 60 | [45, 55, 45] | Steel matting, 15x15m |
| Ammo Bunker | 45 | [40, 60, 40] | Explosive hazard |
| Fuel Depot | 40 | [35, 50, 35] | Flammable |
| Medical Station | 35 | [30, 50, 30] | Heals wounded |
| TOC | 80 | [60, 80, 60] | +100m sight, HQ |
| Commo Bunker | 50 | [40, 60, 40] | Calls air support |
| Hootch | 20 | [20, 30, 20] | Living quarters |
| Mess Hall | 45 | [40, 60, 40] | Flammable |
| Artillery Pit | 100 | [60, 100, 60] | 105mm howitzer 11km |
| 155mm Howitzer Pit | 120 | [70, 120, 70] | 155mm howitzer 14.6km |
| Tank Revetment | 60 | [50, 70, 50] | Vehicle protection |

### Destruction States
Buildings support multiple destruction states with visual variants:
- `INTACT` - Fully operational
- `DAMAGED` - Reduced effectiveness, visual damage
- `BURNED` - Fire damage, wooden structures
- `RUINS` - Major structural damage
- `DESTROYED` - Non-functional
- `EXPLODED` - Ammunition/fuel explosions
- `COLLAPSED` - Structural collapse
- `CRATERED` - Bomb/artillery damage

### Map Placement Buildings (Zero supply cost)
Used for map generation and scenario design:
- Vietnamese Village structures (huts, pagodas, wells)
- French Colonial buildings (villas, government buildings)
- Infrastructure (bridges, roads, ports)
- VC/NVA structures (tunnel entrances, spider holes, caches)
- Ruins and destroyed variants
- Commercial/marketplace buildings

## Unit Selection Setup (Standardized Workflow)

**Key File:** `battle_system/utils/selectable_unit_setup.gd`

When adding new player-controlled units, use `SelectableUnitSetup` to ensure click hitboxes match visuals.

### Quick Setup
```gdscript
# In your unit's _ready():
var collision := SelectableUnitSetup.auto_setup_from_model(
    self,           # CharacterBody3D unit
    $Model,         # Node3D model
    data.faction,   # GameEnums.Faction
    data.is_vehicle
)
```

### Manual Setup
```gdscript
# Create standard collision shapes
var infantry_collision := SelectableUnitSetup.create_infantry_collision()
var vehicle_collision := SelectableUnitSetup.create_vehicle_collision(Vector3(2, 1.5, 4))

# Setup with proper layers and groups
SelectableUnitSetup.setup_selectable(unit, collision, faction, is_vehicle)
```

### Center Y Offsets (Visual/Collision)
| Unit Type | Center Y | Notes |
|-----------|----------|-------|
| Infantry | 0.9m | Capsule collision |
| Vehicle | 0.75m | Box collision |
| Helicopter | 2.0m | Airborne offset |

### Collision Layers
| Layer | Bit Value | Purpose |
|-------|-----------|---------|
| 1 | 1 | Terrain |
| 2 | 2 | US/ARVN units |
| 3 | 4 | VC units |
| 4 | 8 | NVA units |
| 5 | 16 | Vehicles |
| 6 | 32 | Helicopters |
| 7 | 64 | Buildings |

SelectionManager raycasts with mask `0b1110` (layers 2,3,4) for unit selection.

### Troubleshooting Selection
1. **Click offset from visual** - Ensure collision shape y-position matches visual center
2. **Can't select units** - Check collision_layer is 2/4/8 based on faction
3. **Drag-select misses units** - Unit must be in "all_units" group
4. **Model loads offset** - Use `SelectableUnitSetup.sync_visual_to_collision()`


<!-- BEGIN BEADS INTEGRATION v:2 profile:minimal hash:auto -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Beads integration is **AUTOMATIC** - Claude MUST run session protocols without being asked.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
bd remember "context" # Persist knowledge across sessions
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Start (AUTOMATIC)

**At the START of every session**, Claude MUST automatically run:

```bash
bd ready              # Show open tasks awaiting work
```

This is NOT optional. Do this immediately when the session begins, before any other work. Show the user what tasks are available.

## Session End (AUTOMATIC)

**When the user says they are signing off, ending the session, or similar**, Claude MUST automatically:

1. **Create issues for incomplete work** - `bd create "title" -d "description" -l "labels"`
2. **Close completed issues** - `bd update <id> --status closed`
3. **Save context** - `bd remember "key decisions and state for next session"`
4. **Commit and push**:
   ```bash
   git add <relevant-files>
   git commit -m "description"
   git push
   ```
5. **Show summary** - List issues created/closed and what was pushed

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
- These session protocols are AUTOMATIC - do not wait for user to ask
<!-- END BEADS INTEGRATION -->
