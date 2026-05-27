# ADR-0015: Doctrine System

## Status
Proposed

## Context

RealVietnamRTS uses "Doctrine Over Spam" (Pillar 4) as a core design pillar. Before each mission, players select a doctrine that commits their playstyle, determines available units, and unlocks specific buildings. This prevents mid-game pivots and rewards planning.

### Requirements to Address
| TR-ID | Requirement |
|-------|-------------|
| TR-SYS-060 | Pre-mission doctrine choice commits playstyle, unit availability, and building unlocks |
| TR-SYS-061 | Air Cavalry: infantry + helis, limited ground vehicles, faster heli reinforcement (20%) |
| TR-SYS-062 | Mechanized Infantry: more armor, fewer helis, faster convoy reinforcement (25%) |
| TR-SYS-063 | VC Local Force: tunnels, night bonus (+25%), attrition tactics |
| TR-SYS-064 | MVP: 1 doctrine per side fully fleshed out (Air Cavalry for US, Local Force for VC) |

## Decision

### Doctrine Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                       DoctrineManager                               │
│                      (Autoload Singleton)                           │
├─────────────────────────────────────────────────────────────────────┤
│  + select_doctrine(doctrine: DoctrineData, faction) -> void         │
│  + get_active_doctrine(faction) -> DoctrineData                     │
│  + get_reinforcement_modifier(faction, delivery_mode) -> float      │
│  + get_combat_modifier(faction, context: ModifierContext) -> float  │
│  + get_available_buildings(faction) -> Array[BuildingData]          │
├─────────────────────────────────────────────────────────────────────┤
│  Signals: doctrine_selected, doctrine_ability_activated             │
└─────────────────────────────────────────────────────────────────────┘
          ▲
          │ references
          │
┌─────────────────────────────────────────────────────────────────────┐
│                       DoctrineData (Resource)                       │
├─────────────────────────────────────────────────────────────────────┤
│  + doctrine_id: String                                              │
│  + doctrine_name: String                                            │
│  + faction: GameEnums.Faction                                       │
│  + base_units: Array[UnitCardData]                                  │
│  + optional_units: Array[UnitCardData]                              │
│  + base_buildings: Array[BuildingData]                              │
│  + flexible_buildings: Array[BuildingData]                          │
│  + reinforcement_modifiers: Dictionary                              │
│  + combat_modifiers: Array[DoctrineModifier]                        │
│  + special_abilities: Array[DoctrineAbility]                        │
└─────────────────────────────────────────────────────────────────────┘
```

### DoctrineData Resource

```gdscript
## DoctrineData.gd - Resource defining a complete doctrine

class_name DoctrineData extends Resource

@export var doctrine_id: String
@export var doctrine_name: String
@export var doctrine_description: String
@export var faction: GameEnums.Faction

## Visual
@export var doctrine_icon: Texture2D
@export var doctrine_color: Color

## Unit availability (TR-SYS-060)
@export var base_units: Array[UnitCardData] = []       # Always available
@export var optional_units: Array[UnitCardData] = []   # Can pick during deck building
@export var max_optional_picks: int = 4                 # How many optional cards allowed

## Building availability (TR-SYS-060)
@export var base_buildings: Array[BuildingData] = []   # Always can build
@export var flexible_buildings: Array[BuildingData] = []  # Pool for flexible slots

## Reinforcement timing modifiers
@export var helicopter_time_modifier: float = 1.0      # Multiplier (0.8 = 20% faster)
@export var convoy_time_modifier: float = 1.0          # Multiplier (0.75 = 25% faster)

## Combat modifiers (contextual bonuses)
@export var combat_modifiers: Array[DoctrineModifier] = []

## Special abilities unique to this doctrine
@export var special_abilities: Array[DoctrineAbility] = []

## Restrictions
@export var restricted_units: Array[String] = []       # Unit IDs this doctrine cannot use
@export var restricted_buildings: Array[String] = []   # Building IDs this doctrine cannot build
```

### Doctrine Modifiers

```gdscript
## DoctrineModifier.gd - Contextual bonuses from doctrine

class_name DoctrineModifier extends Resource

enum ModifierType {
    DAMAGE_DEALT,
    DAMAGE_RECEIVED,
    ACCURACY,
    SUPPRESSION_RESISTANCE,
    MOVEMENT_SPEED,
    SIGHT_RANGE,
    MORALE_RECOVERY,
    SUPPLY_CONSUMPTION,
}

enum ModifierContext {
    ALWAYS,              # Always active
    AT_NIGHT,            # Between 1800-0600
    IN_JUNGLE,           # In jungle terrain
    DEFENDING_FIREBASE,  # Within firebase influence radius
    ATTACKING,           # Moving toward enemy
    FLANKING,            # Attack angle > 90 degrees from front
    LOW_SUPPLY,          # Below 25% supply
    OUTNUMBERED,         # Fewer units in engagement
}

@export var modifier_type: ModifierType
@export var context: ModifierContext
@export var value: float  # Additive (+0.25 = +25%) or multiplicative depending on type
@export var description: String
```

### Air Cavalry Doctrine (TR-SYS-061)

```gdscript
## air_cavalry_doctrine.tres - US Air Cavalry doctrine

extends DoctrineData

func _init() -> void:
    doctrine_id = "us_air_cavalry"
    doctrine_name = "Air Cavalry"
    doctrine_description = "Fast helicopter insertion, mobile infantry. Limited armor."
    faction = GameEnums.Faction.US_ARMY

    # Reinforcement timing (TR-SYS-061: 20% faster heli)
    helicopter_time_modifier = 0.80  # 20% faster
    convoy_time_modifier = 1.20      # 20% slower (doctrine doesn't favor ground)

    # Base units - always available
    base_units = [
        preload("res://data/units/us_rifle_squad.tres"),
        preload("res://data/units/us_engineer_squad.tres"),
        preload("res://data/units/us_recon_team.tres"),
        preload("res://data/units/us_huey_transport.tres"),
    ]

    # Optional units - pick during deck building
    optional_units = [
        preload("res://data/units/us_weapons_squad.tres"),
        preload("res://data/units/us_huey_gunship.tres"),
        preload("res://data/units/us_medevac.tres"),
    ]
    max_optional_picks = 3

    # Restricted units - Air Cav cannot use heavy armor
    restricted_units = ["us_m48_patton"]

    # Buildings
    base_buildings = [
        preload("res://data/buildings/command_post.tres"),
        preload("res://data/buildings/helipad.tres"),
        preload("res://data/buildings/sandbag_wall.tres"),
        preload("res://data/buildings/bunker.tres"),
    ]

    flexible_buildings = [
        preload("res://data/buildings/mg_nest.tres"),
        preload("res://data/buildings/mortar_pit.tres"),
        preload("res://data/buildings/observation_tower.tres"),
        preload("res://data/buildings/supply_depot.tres"),
        preload("res://data/buildings/medical_station.tres"),
    ]

    # Combat modifiers - Air Cav bonuses
    combat_modifiers = [
        _create_modifier(
            ModifierType.MOVEMENT_SPEED,
            ModifierContext.ALWAYS,
            0.10,  # +10% movement
            "Air Cav: +10% infantry movement"
        ),
        _create_modifier(
            ModifierType.SIGHT_RANGE,
            ModifierContext.ALWAYS,
            0.15,  # +15% sight range
            "Air Cav: +15% recon sight range"
        ),
    ]

func _create_modifier(
    type: DoctrineModifier.ModifierType,
    context: DoctrineModifier.ModifierContext,
    value: float,
    desc: String
) -> DoctrineModifier:
    var mod := DoctrineModifier.new()
    mod.modifier_type = type
    mod.context = context
    mod.value = value
    mod.description = desc
    return mod
```

### Mechanized Infantry Doctrine (TR-SYS-062)

```gdscript
## mechanized_infantry_doctrine.tres - US Mechanized Infantry doctrine

extends DoctrineData

func _init() -> void:
    doctrine_id = "us_mechanized"
    doctrine_name = "Mechanized Infantry"
    doctrine_description = "Armored support, ground-based logistics. Fewer helicopters."
    faction = GameEnums.Faction.US_ARMY

    # Reinforcement timing (TR-SYS-062: 25% faster convoy)
    helicopter_time_modifier = 1.30  # 30% slower (fewer helis)
    convoy_time_modifier = 0.75      # 25% faster

    # Base units - more ground vehicles
    base_units = [
        preload("res://data/units/us_rifle_squad.tres"),
        preload("res://data/units/us_engineer_squad.tres"),
        preload("res://data/units/us_weapons_squad.tres"),
        preload("res://data/units/us_m35_truck.tres"),
        preload("res://data/units/us_m113_apc.tres"),
    ]

    # Optional units - armor available
    optional_units = [
        preload("res://data/units/us_m48_patton.tres"),
        preload("res://data/units/us_huey_transport.tres"),
        preload("res://data/units/us_bulldozer.tres"),
    ]
    max_optional_picks = 3

    # Restricted units - Mech doesn't get gunships
    restricted_units = ["us_huey_gunship"]

    # Buildings - includes tank revetment
    base_buildings = [
        preload("res://data/buildings/command_post.tres"),
        preload("res://data/buildings/sandbag_wall.tres"),
        preload("res://data/buildings/bunker.tres"),
        preload("res://data/buildings/tank_revetment.tres"),
    ]

    flexible_buildings = [
        preload("res://data/buildings/helipad.tres"),
        preload("res://data/buildings/mg_nest.tres"),
        preload("res://data/buildings/mortar_pit.tres"),
        preload("res://data/buildings/supply_depot.tres"),
        preload("res://data/buildings/fuel_depot.tres"),
    ]

    # Combat modifiers - Mechanized bonuses
    combat_modifiers = [
        _create_modifier(
            ModifierType.DAMAGE_RECEIVED,
            ModifierContext.DEFENDING_FIREBASE,
            -0.15,  # -15% damage when defending
            "Mech Infantry: -15% damage in firebase"
        ),
        _create_modifier(
            ModifierType.SUPPRESSION_RESISTANCE,
            ModifierContext.ALWAYS,
            0.20,  # +20% suppression resistance
            "Mech Infantry: +20% suppression resistance"
        ),
    ]
```

### VC Local Force Doctrine (TR-SYS-063)

```gdscript
## vc_local_force_doctrine.tres - VC Local Force doctrine

extends DoctrineData

func _init() -> void:
    doctrine_id = "vc_local_force"
    doctrine_name = "Local Force"
    doctrine_description = "Tunnel networks, night operations, attrition tactics."
    faction = GameEnums.Faction.VC

    # VC doesn't use helicopters/convoys - spawns from tunnels
    helicopter_time_modifier = 0.0   # N/A
    convoy_time_modifier = 0.0       # N/A

    # Base units
    base_units = [
        preload("res://data/units/vc_infantry.tres"),
        preload("res://data/units/vc_sapper.tres"),
        preload("res://data/units/vc_mortar_team.tres"),
    ]

    optional_units = [
        preload("res://data/units/vc_porter.tres"),
        preload("res://data/units/vc_rpg_team.tres"),
        preload("res://data/units/vc_sniper.tres"),
    ]
    max_optional_picks = 2

    # VC structures
    base_buildings = [
        preload("res://data/buildings/vc_tunnel_entrance.tres"),
        preload("res://data/buildings/vc_spider_hole.tres"),
        preload("res://data/buildings/vc_weapon_cache.tres"),
    ]

    flexible_buildings = [
        preload("res://data/buildings/vc_punji_trap.tres"),
        preload("res://data/buildings/vc_booby_trap.tres"),
        preload("res://data/buildings/vc_mortar_position.tres"),
    ]

    # Combat modifiers - VC bonuses (TR-SYS-063)
    combat_modifiers = [
        # Night bonus +25%
        _create_modifier(
            ModifierType.DAMAGE_DEALT,
            ModifierContext.AT_NIGHT,
            0.25,
            "Local Force: +25% damage at night"
        ),
        _create_modifier(
            ModifierType.ACCURACY,
            ModifierContext.AT_NIGHT,
            0.20,
            "Local Force: +20% accuracy at night"
        ),
        # Jungle bonus
        _create_modifier(
            ModifierType.MOVEMENT_SPEED,
            ModifierContext.IN_JUNGLE,
            0.30,
            "Local Force: +30% movement in jungle"
        ),
        _create_modifier(
            ModifierType.SIGHT_RANGE,
            ModifierContext.IN_JUNGLE,
            0.25,
            "Local Force: +25% sight in jungle"
        ),
        # Attrition tactics - better when outnumbered
        _create_modifier(
            ModifierType.MORALE_RECOVERY,
            ModifierContext.OUTNUMBERED,
            0.50,
            "Local Force: +50% morale recovery when outnumbered"
        ),
    ]

    # Special abilities
    special_abilities = [
        _create_tunnel_spawn_ability(),
        _create_fade_ability(),
    ]

func _create_tunnel_spawn_ability() -> DoctrineAbility:
    var ability := DoctrineAbility.new()
    ability.ability_id = "tunnel_spawn"
    ability.ability_name = "Tunnel Network"
    ability.description = "Units spawn from tunnel entrances instead of map edge"
    ability.is_passive = true
    return ability

func _create_fade_ability() -> DoctrineAbility:
    var ability := DoctrineAbility.new()
    ability.ability_id = "fade_into_jungle"
    ability.ability_name = "Fade into Jungle"
    ability.description = "Units in jungle that break contact become hidden after 5 seconds"
    ability.cooldown = 0.0  # Passive
    ability.is_passive = true
    return ability
```

### DoctrineManager Implementation

```gdscript
## DoctrineManager.gd - Autoload singleton for doctrine management

class_name DoctrineManager extends Node

## Active doctrines per faction
var _active_doctrines: Dictionary = {}  # faction -> DoctrineData

## Cached modifier lookups
var _modifier_cache: Dictionary = {}

func _ready() -> void:
    BattleSignals.mission_started.connect(_on_mission_started)

## Select doctrine for faction (TR-SYS-060)
func select_doctrine(doctrine: DoctrineData, faction: GameEnums.Faction) -> void:
    if doctrine.faction != faction:
        push_error("Doctrine faction mismatch")
        return

    _active_doctrines[faction] = doctrine
    _rebuild_modifier_cache(faction)

    BattleSignals.doctrine_selected.emit(faction, doctrine)

func get_active_doctrine(faction: GameEnums.Faction) -> DoctrineData:
    return _active_doctrines.get(faction)

## Get reinforcement time modifier for delivery mode
func get_reinforcement_modifier(
    faction: GameEnums.Faction,
    delivery_mode: ReinforcementManager.DeliveryMode
) -> float:
    var doctrine := get_active_doctrine(faction)
    if not doctrine:
        return 1.0

    match delivery_mode:
        ReinforcementManager.DeliveryMode.HELICOPTER:
            return doctrine.helicopter_time_modifier
        ReinforcementManager.DeliveryMode.CONVOY:
            return doctrine.convoy_time_modifier

    return 1.0

## Get combat modifier for specific context
func get_combat_modifier(
    faction: GameEnums.Faction,
    modifier_type: DoctrineModifier.ModifierType,
    context: DoctrineModifier.ModifierContext
) -> float:
    var doctrine := get_active_doctrine(faction)
    if not doctrine:
        return 0.0

    var total_modifier := 0.0
    for mod in doctrine.combat_modifiers:
        if mod.modifier_type == modifier_type:
            if mod.context == DoctrineModifier.ModifierContext.ALWAYS or mod.context == context:
                total_modifier += mod.value

    return total_modifier

## Check if context is currently active for a unit
func evaluate_context(
    unit: Node3D,
    context: DoctrineModifier.ModifierContext
) -> bool:
    match context:
        DoctrineModifier.ModifierContext.ALWAYS:
            return true
        DoctrineModifier.ModifierContext.AT_NIGHT:
            return TimeManager.is_night()
        DoctrineModifier.ModifierContext.IN_JUNGLE:
            return TerrainSystem.get_terrain_type(unit.global_position) == TerrainType.JUNGLE
        DoctrineModifier.ModifierContext.DEFENDING_FIREBASE:
            return FirebaseSystem.is_in_influence_radius(unit.global_position, unit.faction)
        DoctrineModifier.ModifierContext.ATTACKING:
            return unit.is_advancing_toward_enemy()
        DoctrineModifier.ModifierContext.FLANKING:
            return unit.is_flanking_target()
        DoctrineModifier.ModifierContext.LOW_SUPPLY:
            return unit.get_supply_percentage() < 0.25
        DoctrineModifier.ModifierContext.OUTNUMBERED:
            return _is_outnumbered(unit)

    return false

func _is_outnumbered(unit: Node3D) -> bool:
    var allies := SpatialHashGrid.get_allies_in_radius(
        unit.global_position, 100.0, unit.faction
    )
    var enemies := SpatialHashGrid.get_enemies_in_radius(
        unit.global_position, 100.0, unit.faction
    )
    return enemies.size() > allies.size()

## Get all buildings this faction can build
func get_available_buildings(faction: GameEnums.Faction) -> Array[BuildingData]:
    var doctrine := get_active_doctrine(faction)
    if not doctrine:
        return []

    var available: Array[BuildingData] = []

    # Base buildings always available
    available.append_array(doctrine.base_buildings)

    # Buildings unlocked by unit cards in deck
    var deck_buildings := DeckManager.get_unlocked_buildings()
    for building in deck_buildings:
        if building not in available:
            available.append(building)

    return available

func get_flexible_building_pool(faction: GameEnums.Faction) -> Array[BuildingData]:
    var doctrine := get_active_doctrine(faction)
    if not doctrine:
        return []
    return doctrine.flexible_buildings

## Check if unit type is allowed by doctrine
func is_unit_allowed(unit_id: String, faction: GameEnums.Faction) -> bool:
    var doctrine := get_active_doctrine(faction)
    if not doctrine:
        return true  # No doctrine = allow all

    return unit_id not in doctrine.restricted_units

## Check if building type is allowed by doctrine
func is_building_allowed(building_id: String, faction: GameEnums.Faction) -> bool:
    var doctrine := get_active_doctrine(faction)
    if not doctrine:
        return true

    return building_id not in doctrine.restricted_buildings
```

### Doctrine Selection UI

```gdscript
## DoctrineSelectionScreen.gd - Pre-mission doctrine selection

class_name DoctrineSelectionScreen extends Control

signal doctrine_confirmed(doctrine: DoctrineData)

@onready var _doctrine_list: ItemList = $DoctrineList
@onready var _doctrine_name: Label = $DoctrineDetails/Name
@onready var _doctrine_desc: RichTextLabel = $DoctrineDetails/Description
@onready var _unit_list: VBoxContainer = $DoctrineDetails/Units
@onready var _building_list: VBoxContainer = $DoctrineDetails/Buildings
@onready var _modifier_list: VBoxContainer = $DoctrineDetails/Modifiers
@onready var _confirm_button: Button = $ConfirmButton

var _available_doctrines: Array[DoctrineData]
var _selected_doctrine: DoctrineData
var _faction: GameEnums.Faction

func setup(faction: GameEnums.Faction) -> void:
    _faction = faction
    _load_available_doctrines()
    _populate_list()

func _load_available_doctrines() -> void:
    _available_doctrines.clear()

    # Load all doctrines for this faction
    var doctrine_dir := "res://data/doctrines/"
    var dir := DirAccess.open(doctrine_dir)
    if dir:
        dir.list_dir_begin()
        var file_name := dir.get_next()
        while file_name != "":
            if file_name.ends_with(".tres"):
                var doctrine: DoctrineData = load(doctrine_dir + file_name)
                if doctrine and doctrine.faction == _faction:
                    _available_doctrines.append(doctrine)
            file_name = dir.get_next()

func _populate_list() -> void:
    _doctrine_list.clear()
    for doctrine in _available_doctrines:
        var idx := _doctrine_list.add_item(doctrine.doctrine_name, doctrine.doctrine_icon)
        _doctrine_list.set_item_metadata(idx, doctrine)

func _on_doctrine_selected(index: int) -> void:
    _selected_doctrine = _doctrine_list.get_item_metadata(index)
    _update_details_panel()

func _update_details_panel() -> void:
    if not _selected_doctrine:
        return

    _doctrine_name.text = _selected_doctrine.doctrine_name
    _doctrine_desc.text = _selected_doctrine.doctrine_description

    # Show base units
    for child in _unit_list.get_children():
        child.queue_free()

    for unit in _selected_doctrine.base_units:
        var label := Label.new()
        label.text = "- %s (Base)" % unit.unit_name
        _unit_list.add_child(label)

    for unit in _selected_doctrine.optional_units:
        var label := Label.new()
        label.text = "- %s (Optional)" % unit.unit_name
        _unit_list.add_child(label)

    # Show modifiers
    for child in _modifier_list.get_children():
        child.queue_free()

    for mod in _selected_doctrine.combat_modifiers:
        var label := Label.new()
        label.text = mod.description
        _modifier_list.add_child(label)

    _confirm_button.disabled = false

func _on_confirm_pressed() -> void:
    if _selected_doctrine:
        DoctrineManager.select_doctrine(_selected_doctrine, _faction)
        doctrine_confirmed.emit(_selected_doctrine)
```

### Serialization Support

```gdscript
## DoctrineManager serialization
func serialize() -> Dictionary:
    var doctrines_data: Dictionary = {}
    for faction in _active_doctrines.keys():
        doctrines_data[faction] = _active_doctrines[faction].doctrine_id

    return {
        "_version": 1,
        "_system": "DoctrineManager",
        "active_doctrines": doctrines_data,
    }

func deserialize(data: Dictionary) -> bool:
    if data.get("_version", 0) != 1:
        return false

    _active_doctrines.clear()
    var doctrines_data: Dictionary = data.get("active_doctrines", {})

    for faction_key in doctrines_data.keys():
        var faction: GameEnums.Faction = faction_key
        var doctrine_id: String = doctrines_data[faction_key]
        var doctrine := _load_doctrine_by_id(doctrine_id)
        if doctrine:
            _active_doctrines[faction] = doctrine

    return true

func _load_doctrine_by_id(doctrine_id: String) -> DoctrineData:
    var path := "res://data/doctrines/%s.tres" % doctrine_id
    if ResourceLoader.exists(path):
        return load(path)
    return null
```

## Consequences

### Positive
- **Strategic depth**: Pre-mission choices matter (TR-SYS-060)
- **Faction identity**: Each doctrine feels distinct
- **Asymmetry**: VC plays fundamentally different from US
- **No mid-game pivots**: Commitment creates consequences
- **Clear bonuses**: Modifiers are transparent to players

### Negative
- **Learning curve**: New players must understand doctrine differences
- **Balance challenge**: Multiple doctrines per faction multiply balance variables
- **Lock-in frustration**: Wrong doctrine choice can't be undone

### Mitigations
- Tutorial mission locks to one doctrine
- Clear UI showing doctrine effects
- MVP limits to one doctrine per side (TR-SYS-064)
- Doctrine comparison screen before selection

## ADR Dependencies

- **ADR-0008 (Serialization)**: Doctrine state persistence
- **ADR-0010 (Combat System)**: Combat modifiers integration
- **ADR-0011 (Morale)**: Morale recovery modifiers
- **ADR-0014 (Reinforcement)**: Reinforcement timing modifiers

## Engine Compatibility

**Godot 4.6** - Resource-based doctrine definitions, pure GDScript.

## GDD Requirements Addressed

| Requirement | How Addressed |
|-------------|---------------|
| TR-SYS-060 | `DoctrineManager.select_doctrine()` commits playstyle before mission |
| TR-SYS-061 | `air_cavalry_doctrine.tres` with helicopter_time_modifier = 0.80 |
| TR-SYS-062 | `mechanized_infantry_doctrine.tres` with convoy_time_modifier = 0.75 |
| TR-SYS-063 | `vc_local_force_doctrine.tres` with AT_NIGHT +25% damage, IN_JUNGLE +30% movement |
| TR-SYS-064 | MVP ships with air_cavalry + local_force doctrines fully implemented |

## Implementation Files

| File | Purpose |
|------|---------|
| `systems/doctrine_manager.gd` | Autoload singleton |
| `data/doctrine_data.gd` | DoctrineData resource class |
| `data/doctrine_modifier.gd` | DoctrineModifier resource class |
| `data/doctrine_ability.gd` | DoctrineAbility resource class |
| `data/doctrines/us_air_cavalry.tres` | US Air Cavalry doctrine |
| `data/doctrines/us_mechanized.tres` | US Mechanized Infantry |
| `data/doctrines/vc_local_force.tres` | VC Local Force doctrine |
| `ui/doctrine_selection_screen.tscn` | Pre-mission selection UI |

## Key Signals

```gdscript
## BattleSignals additions for doctrine
signal doctrine_selected(faction: int, doctrine: DoctrineData)
signal doctrine_ability_activated(faction: int, ability_id: String)
signal doctrine_modifier_applied(unit: Node3D, modifier: DoctrineModifier)
```

## Validation Criteria

- [ ] Air Cavalry helicopter reinforcement is 20% faster
- [ ] Mechanized Infantry convoy reinforcement is 25% faster
- [ ] VC Local Force gets +25% damage at night
- [ ] VC Local Force gets +30% movement in jungle
- [ ] Restricted units cannot be added to deck
- [ ] Doctrine selection cannot be changed after mission start
- [ ] MVP includes exactly 2 doctrines (Air Cav, Local Force)
