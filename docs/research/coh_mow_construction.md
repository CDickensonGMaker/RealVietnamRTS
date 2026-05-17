# Company of Heroes / Men of War Construction Analysis

## Sources
- [Company of Heroes Wiki - Bunker](https://companyofheroes.fandom.com/wiki/Bunker)
- [Company of Heroes Wiki - Defensive Structure](https://companyofheroes.fandom.com/wiki/Defensive_Structure)
- [CoH3 Wehrmacht Guide](https://gamerant.com/company-of-heroes-3-wehrmacht-units-and-buildings-guide/)
- [Men of War 2 Fortifications Guide](https://www.pcinvasion.com/how-to-dig-trenches-and-build-fortifications-in-men-of-war-2/)

---

## Company of Heroes 3

### Base Structure System

**Base Sector Constraint:**
- Base structures only buildable in HQ sector
- Limited space = strategic building choices
- Production chain: HQ → intermediate buildings → advanced units

**Starting Structures:**
- Each faction starts with Headquarters
- HQ produces basic units and enables first-tier buildings

### Defensive Structure Categories

| Type | Examples | Purpose |
|------|----------|---------|
| Light | Sandbags, Wire | Cover, infantry blocking |
| Medium | MG Nest, Bunker | Suppression, garrison |
| Heavy | Mortar Pit, AT Gun | Area denial, vehicle defense |
| Obstacle | Tank Traps, Mines | Movement blocking, damage |

### Engineer Construction Abilities

**US Engineers:**
- Sandbags (free) - Heavy cover
- Barbed Wire (free) - Infantry blocking
- Tank Traps (free) - Vehicle blocking
- Mines (30 Munitions) - Hidden damage
- Fighting Position (150 MP) - Garrisonable
  - +30 cal MG upgrade (75 MU)
  - +Mortar upgrade (75 MU)
- Resource Cache (200 MP)

**Wehrmacht Pioneers:**
- Fighting Nest (150 MP) - 1 squad garrison
- Concrete Bunker (200 MP) - 2 squad garrison
  - MG42 Bunker upgrade (60 MU) - Loses garrison, gains suppression
  - Repair Bunker upgrade (85 MU) - Auto-repairs vehicles
  - Medical Bunker upgrade - Heals infantry

**British Engineers:**
- Same basic obstacles as US
- Focus on defensive line construction

### Bunker Mechanics

**Garrison System:**
- Infantry can enter bunker
- Fire from 4 openings (cardinal directions)
- MG squads set up inside automatically
- Heavy cover protection

**Upgrade Paths:**
- Base bunker → specialized function
- Upgrades remove garrison ability
- Each upgrade serves specific role

### Construction Time
- Light structures: Fast (~5-10 seconds)
- Medium structures: Moderate (~15-30 seconds)
- Heavy structures: Slow (~30-60 seconds)
- Can be interrupted by combat

---

## Men of War 2

### Any Infantry Can Build
Unlike CoH, Men of War allows regular soldiers to construct:
- SMG Infantry can dig trenches
- Riflemen can build sandbags/breastworks
- Engineers build faster + better fortifications

### Trench Digging System

**Interactive Placement:**
1. Select unit, press Q (or Dig Trenches button)
2. Click starting point
3. Move mouse to set length
4. Mouse wheel to adjust depth (troop capacity)
5. Click endpoint to start digging

**Trench Properties:**
- Protects from incoming fire
- Reduces accuracy (trade-off)
- Takes significant time
- Vulnerable during construction

### Sandbag Construction

**Quick Build:**
- Select riflemen
- Shift+Z shortcut
- Same click-drag placement as trenches
- Faster than trenches

### Construction Balance
- Protection vs. Accuracy trade-off
- Time investment (vulnerable)
- Engineers faster but weaker in combat
- Must construct outside combat

---

## Applicability to RealVietnamRTS

### Construction System Design

```gdscript
class_name ConstructionAbility extends Resource

@export var structure_type: int
@export var cost_supply: int = 0
@export var cost_ammo: int = 0
@export var build_time: float = 10.0
@export var requires_engineer: bool = false
@export var can_interrupt: bool = true

# Who can build this
enum BuilderType { ENGINEER_ONLY, ANY_INFANTRY, VEHICLE }
@export var builder_type: BuilderType = BuilderType.ENGINEER_ONLY
```

### Interactive Placement (Men of War Style)

```gdscript
# For trenches, wire, walls
class_name LinearPlacement extends Node

enum State { IDLE, PLACING_START, PLACING_END }
var state: State = State.IDLE
var start_pos: Vector3
var end_pos: Vector3
var preview_mesh: MeshInstance3D

func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed:
        match state:
            State.PLACING_START:
                start_pos = _get_world_position(event.position)
                state = State.PLACING_END
            State.PLACING_END:
                end_pos = _get_world_position(event.position)
                _begin_construction()
                state = State.IDLE

func _process(_delta: float) -> void:
    if state == State.PLACING_END:
        end_pos = _get_cursor_world_position()
        _update_preview()
```

### Bunker Garrison System

```gdscript
class_name GarrisonableStructure extends Node3D

@export var max_squads: int = 2
@export var firing_positions: Array[Node3D] = []

var garrisoned_units: Array[Node3D] = []

func can_garrison(unit: Node3D) -> bool:
    if garrisoned_units.size() >= max_squads:
        return false
    if not unit.is_in_group("infantry"):
        return false
    return true

func garrison_unit(unit: Node3D) -> void:
    if not can_garrison(unit):
        return

    garrisoned_units.append(unit)
    unit.enter_garrison(self)
    _assign_firing_position(unit)

func _assign_firing_position(unit: Node3D) -> void:
    for pos in firing_positions:
        if not pos.has_meta("occupied"):
            pos.set_meta("occupied", true)
            unit.position = pos.global_position
            return
```

### Vietnamese Fortification Types

| Structure | Builder | Time | Cost | Notes |
|-----------|---------|------|------|-------|
| Foxhole | Any Infantry | 30s | 0 | Single soldier cover |
| Fighting Hole | Any Infantry | 45s | 0 | 2-man position |
| Sandbag Wall | Engineers | 20s | 5 | Linear cover |
| Bunker | Engineers | 120s | 40 | Garrison 4-8 |
| MG Nest | Engineers | 90s | 30 | Fixed MG position |
| Mortar Pit | Engineers | 60s | 35 | Indirect fire |
| Observation Tower | Engineers | 75s | 25 | +60m sight |
| Wire Obstacle | Engineers | 30s | 10 | Slows infantry |
| Punji Pit (VC) | VC Sappers | 45s | 5 | Hidden damage |
| Tunnel (VC) | VC Engineers | 300s | 100 | Spawn/hide point |

### Key Design Lessons

1. **Multiple Builder Types** - Engineers faster, infantry can help
2. **Interactive Placement** - Click-drag for linear structures
3. **Upgrade Paths** - Base structure → specialized function
4. **Garrison Mechanics** - Units enter, fire from positions
5. **Trade-offs** - Protection vs accuracy, time vs safety
6. **Interruption** - Construction can be stopped by combat
