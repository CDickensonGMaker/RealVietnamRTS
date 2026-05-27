# Eugen Systems Design Reference

**Purpose:** War-room reference document for RealVietnamRTS agents. Covers Steel Division, Wargame series, WARNO, and Broken Arrow mechanics relevant to our Five Pillars.

**Last Updated:** 2026-05-25

**Status:** `[REFERENCE MATERIAL - Check GAME_BIBLE.md for final design]`

---

## Table of Contents

1. [Strategic-to-Tactical Zoom System](#1-strategic-to-tactical-zoom-system)
2. [Unit Card Information Display](#2-unit-card-information-display)
3. [Autonomous Unit Behavior](#3-autonomous-unit-behavior-place-and-they-work)
4. [Recon and Fog of War System](#4-recon-and-fog-of-war-system)
5. [Morale and Stress System](#5-morale-and-stress-system)
6. [Deck Building and Unit Availability](#6-deck-building-and-unit-availability)
7. [Supply and Logistics](#7-supply-and-logistics)
8. [RealVietnamRTS Integration Guide](#8-realvietnamrts-integration-guide)

---

## Reference Game Overview

| Game | Developer | Setting | Key Innovation |
|------|-----------|---------|----------------|
| **Wargame: European Escalation** (2012) | Eugen | Cold War | Deck building, massive scale |
| **Wargame: AirLand Battle** (2013) | Eugen | Cold War | Air combat, dynamic campaigns |
| **Wargame: Red Dragon** (2014) | Eugen | Cold War Asia | Naval, amphibious ops |
| **Steel Division: Normandy 44** (2017) | Eugen | WW2 Normandy | Phase system, historical divisions |
| **Steel Division 2** (2019) | Eugen | WW2 Eastern Front | Army General mode |
| **WARNO** (2022-2024) | Eugen | Cold War 1989 | Refined Wargame formula |
| **Broken Arrow** (2025) | Steel Balalaika | Modern | Deep customization, supply focus |

**Core Philosophy Shared by All:**
- "Realism through abstraction" - complex systems simplified to playable mechanics
- Unit preservation over expenditure - losing units hurts
- Combined arms mandatory - no single unit type dominates
- Positioning and sightlines matter as much as firepower

---

## 1. Strategic-to-Tactical Zoom System

### 1.1 How Eugen Handles Scale

Eugen games operate on maps typically **4km x 4km to 10km x 10km** with hundreds of units active simultaneously. The zoom system is their solution to commanding at multiple scales.

**Zoom Levels in WARNO/Wargame:**

| Zoom Level | Height (approx) | What You See | Use Case |
|------------|-----------------|--------------|----------|
| **Strategic** | 2000m+ | NATO symbols only | Theater-wide positioning |
| **Operational** | 500-2000m | NATO symbols, terrain detail | Sector management |
| **Tactical** | 100-500m | 3D unit models visible | Combat direction |
| **Close** | <100m | Full detail, individual soldiers | Micro, screenshots |

### 1.2 NATO Symbology at Distance

At strategic zoom, units render as **NATO military map symbols**:

```
Infantry:       [X]     (crossed rectangle)
Armor:          [O-O]   (oval/track marks)
Artillery:      [.]     (dot/circle)
Recon:          [/]     (diagonal slash)
Helicopter:     [Y]     (rotorcraft symbol)
Supply:         [S]     (logistics marker)
```

**Implementation Notes:**
- Symbols are 2D billboards or screen-space UI elements
- Color-coded by faction (Blue = player, Red = enemy, Green = allied)
- Size indicates unit type (platoon/company/battalion)
- Icons show unit state (moving, engaged, suppressed)

### 1.3 Level-of-Detail Transitions

**WARNO LOD System:**

| Distance from Camera | Infantry | Vehicles | Buildings |
|---------------------|----------|----------|-----------|
| 0-50m | Full 3D, animations | Full detail | Full detail |
| 50-150m | Simplified mesh | Medium LOD | Medium LOD |
| 150-300m | Billboard sprites | Low LOD | Low LOD |
| 300-500m | NATO symbol overlay | Silhouette + symbol | Footprint only |
| 500m+ | NATO symbol only | NATO symbol only | Map feature |

**Transition Behavior:**
- Smooth crossfade between LOD levels (no popping)
- Hysteresis zone prevents rapid switching at boundary
- Selected units always render at higher detail
- Units under cursor get detail boost

### 1.4 Camera Controls

**Standard Eugen Camera:**

| Input | Action |
|-------|--------|
| WASD / Arrow Keys | Pan camera |
| Mouse at screen edge | Edge scroll pan |
| Scroll wheel | Zoom in/out |
| Middle mouse drag | Rotate camera |
| Right mouse drag | Pan camera (alt) |
| Double-click unit | Focus and follow |
| Space / Home | Jump to last event |
| Backspace | Return to HQ/spawn |
| F1-F4 | Jump to control groups |

**Zoom Behavior:**
- Zoom toward cursor position (not screen center)
- Zoom speed accelerates with distance
- Minimum zoom clamped to prevent terrain clipping
- Maximum zoom shows entire map

### 1.5 Implementation Guidance for RealVietnamRTS

**Bible Reference:** D-001 requires strategic zoom for multi-firebase management.

```gdscript
# camera_zoom_controller.gd
class_name StrategicZoomCamera extends Camera3D

# Zoom configuration
const ZOOM_MIN := 20.0        # Closest (tactical)
const ZOOM_MAX := 800.0       # Farthest (strategic)
const ZOOM_SPEED := 0.1       # Scroll sensitivity
const ZOOM_SMOOTH := 8.0      # Interpolation speed

# LOD thresholds (match rendering system)
const LOD_TACTICAL := 100.0   # Full 3D models
const LOD_OPERATIONAL := 300.0 # Simplified models
const LOD_STRATEGIC := 500.0  # NATO symbols only

var _target_zoom: float = 200.0
var _current_zoom: float = 200.0

func _process(delta: float) -> void:
    _current_zoom = lerpf(_current_zoom, _target_zoom, ZOOM_SMOOTH * delta)
    position.y = _current_zoom
    _update_unit_lod()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _zoom_toward_cursor(-1.0)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _zoom_toward_cursor(1.0)

func _zoom_toward_cursor(direction: float) -> void:
    var cursor_world := _get_cursor_world_position()
    var zoom_delta := direction * _current_zoom * ZOOM_SPEED

    _target_zoom = clampf(_target_zoom + zoom_delta, ZOOM_MIN, ZOOM_MAX)

    # Pan toward cursor while zooming in
    if direction < 0:
        var pan_factor := 0.1 * absf(direction)
        var to_cursor := cursor_world - global_position
        to_cursor.y = 0
        global_position += to_cursor * pan_factor

func get_zoom_level() -> int:
    if _current_zoom < LOD_TACTICAL:
        return ZoomLevel.TACTICAL
    elif _current_zoom < LOD_OPERATIONAL:
        return ZoomLevel.OPERATIONAL
    elif _current_zoom < LOD_STRATEGIC:
        return ZoomLevel.STRATEGIC
    else:
        return ZoomLevel.THEATER

func _update_unit_lod() -> void:
    var zoom_level := get_zoom_level()
    BattleSignals.zoom_level_changed.emit(zoom_level)
```

**NATO Symbol Rendering:**

```gdscript
# unit_marker.gd
class_name NATOMarker extends Node3D

@export var unit_type: GameEnums.UnitType
@export var faction: GameEnums.Faction

var _symbol_sprite: Sprite3D
var _state_indicator: Sprite3D

const SYMBOL_TEXTURES := {
    GameEnums.UnitType.RIFLE_SQUAD: preload("res://assets/ui/nato/infantry.png"),
    GameEnums.UnitType.WEAPONS_SQUAD: preload("res://assets/ui/nato/infantry_heavy.png"),
    GameEnums.UnitType.RECON_TEAM: preload("res://assets/ui/nato/recon.png"),
    GameEnums.UnitType.M48_PATTON: preload("res://assets/ui/nato/armor.png"),
    GameEnums.UnitType.HUEY_TRANSPORT: preload("res://assets/ui/nato/helicopter.png"),
}

const FACTION_COLORS := {
    GameEnums.Faction.US_ARMY: Color(0.2, 0.4, 0.8),  # Blue
    GameEnums.Faction.ARVN: Color(0.3, 0.6, 0.3),     # Green
    GameEnums.Faction.VC: Color(0.8, 0.2, 0.2),       # Red
    GameEnums.Faction.NVA: Color(0.9, 0.3, 0.1),      # Orange-red
}

func _ready() -> void:
    _symbol_sprite = $SymbolSprite
    _state_indicator = $StateIndicator
    _update_symbol()

    BattleSignals.zoom_level_changed.connect(_on_zoom_changed)

func _on_zoom_changed(level: int) -> void:
    visible = level >= ZoomLevel.OPERATIONAL

    # Scale symbol based on zoom for consistent screen size
    var scale_factor := 1.0 + (level - ZoomLevel.OPERATIONAL) * 0.5
    _symbol_sprite.scale = Vector3.ONE * scale_factor

func _update_symbol() -> void:
    if SYMBOL_TEXTURES.has(unit_type):
        _symbol_sprite.texture = SYMBOL_TEXTURES[unit_type]
    _symbol_sprite.modulate = FACTION_COLORS.get(faction, Color.WHITE)
```

---

## 2. Unit Card Information Display

### 2.1 The Eugen Unit Card

Eugen games are famous for their **dense, information-rich unit cards**. A single card tells you everything about a unit's capabilities at a glance.

**WARNO/Wargame Unit Card Layout:**

```
+------------------------------------------+
|  [UNIT ICON]     M1A1 ABRAMS             |
|                  1st Armored Division     |
+------------------------------------------+
|  WEAPONS                                  |
|  M256 120mm     AP: 23  HE: 4  ACC: 60%  |
|                 RNG: 2275m  ROF: 8/min   |
|  M240C 7.62mm   HE: 1  SUPP: 200         |
|                 RNG: 1050m  ROF: 800/min |
+------------------------------------------+
|  ARMOR          Front  Side  Rear  Top   |
|                 22     12    6     3     |
+------------------------------------------+
|  STATS                                   |
|  Speed: 65 km/h    Fuel: 3500L          |
|  Optics: Good      Stealth: Bad          |
|  Size: Large       Autonomy: 100km       |
+------------------------------------------+
|  AVAILABILITY    [====] 4/4              |
|  COST: 160 pts                           |
+------------------------------------------+
```

### 2.2 Stat Categories Explained

**Weapons Section:**

| Stat | Meaning |
|------|---------|
| **AP** (Armor Piercing) | Penetration value vs. armored targets |
| **HE** (High Explosive) | Damage vs. soft targets and buildings |
| **ACC** | Base accuracy percentage |
| **RNG** | Maximum engagement range in meters |
| **ROF** | Rounds per minute |
| **SUPP** | Suppression value per hit |
| **STAB** | Stabilizer - can fire while moving |

**Armor Section (vehicles only):**

| Facing | Coverage |
|--------|----------|
| **Front** | 0-30 degrees from forward |
| **Side** | 30-150 degrees |
| **Rear** | 150-180 degrees |
| **Top** | Aerial attacks, artillery |

Armor values are compared to AP values:
- AP > Armor = Penetration likely
- AP = Armor = 50% penetration chance
- AP < Armor = Bounce/ricochet

**Detection Stats:**

| Stat | Rating Scale | Effect |
|------|--------------|--------|
| **Optics** | Bad/Poor/Medium/Good/Very Good/Exceptional | Detection range |
| **Stealth** | Bad/Poor/Medium/Good/Very Good/Exceptional | How hard to spot |
| **Size** | Small/Medium/Large/Very Large | Affects detection distance |

### 2.3 Visual Design Principles

**Quick-Read Design:**
1. **Color coding** - Green=good, Yellow=average, Red=bad
2. **Icons over text** - Weapon type icons, armor diagrams
3. **Consistent layout** - Same position for same info across all cards
4. **Numerical emphasis** - Big numbers for key stats (damage, armor)

**At-a-Glance vs. Detailed:**

| At-a-Glance (Selection UI) | Detailed (Armory/Inspect) |
|---------------------------|--------------------------|
| Unit icon and name | Full unit card |
| Health bar | Complete weapon stats |
| Ammo indicator | Armor diagram |
| Current order icon | Veterancy details |
| Suppression state | Movement characteristics |

### 2.4 Implementation Guidance for RealVietnamRTS

**Selection Panel (Minimal):**

```gdscript
# selection_panel.gd
class_name SelectionPanel extends Control

@onready var _unit_icon: TextureRect = $UnitIcon
@onready var _unit_name: Label = $UnitName
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _ammo_bar: ProgressBar = $AmmoBar
@onready var _suppression_indicator: TextureRect = $SuppressionIndicator
@onready var _order_icon: TextureRect = $OrderIcon

func display_unit(unit: Node3D) -> void:
    if not unit:
        hide()
        return

    show()
    var data: SquadData = unit.squad_data

    _unit_icon.texture = data.icon
    _unit_name.text = data.display_name

    _health_bar.max_value = data.max_health
    _health_bar.value = unit.current_health
    _health_bar.modulate = _get_health_color(unit.health_percent)

    _ammo_bar.max_value = data.max_ammo
    _ammo_bar.value = unit.current_ammo

    _update_suppression(unit.suppression_state)
    _update_order(unit.current_order)

func _get_health_color(percent: float) -> Color:
    if percent > 0.66:
        return Color.GREEN
    elif percent > 0.33:
        return Color.YELLOW
    else:
        return Color.RED
```

**Detailed Unit Card (Inspection/Armory):**

```gdscript
# unit_card_detailed.gd
class_name UnitCardDetailed extends Control

signal card_closed

func populate_from_data(data: SquadData) -> void:
    # Header
    $Header/UnitIcon.texture = data.icon
    $Header/UnitName.text = data.display_name
    $Header/UnitType.text = _get_type_string(data.unit_type)

    # Weapons
    _populate_weapons(data.weapons)

    # Stats grid
    $Stats/Optics.text = _rating_to_string(data.optics_rating)
    $Stats/Stealth.text = _rating_to_string(data.stealth_rating)
    $Stats/Speed.text = "%d m/s" % data.move_speed
    $Stats/Size.text = _size_to_string(data.unit_size)

    # Availability (deck building)
    if data.has("deck_availability"):
        $Availability/Count.text = "%d/%d" % [
            data.deck_current, data.deck_max
        ]
        $Availability/Cost.text = "%d pts" % data.point_cost

func _populate_weapons(weapons: Array[WeaponData]) -> void:
    var container := $WeaponsContainer

    for child in container.get_children():
        child.queue_free()

    for weapon in weapons:
        var row := _create_weapon_row(weapon)
        container.add_child(row)

func _create_weapon_row(weapon: WeaponData) -> Control:
    var row := preload("res://ui/components/weapon_row.tscn").instantiate()

    row.get_node("Name").text = weapon.display_name
    row.get_node("Damage").text = str(weapon.damage)
    row.get_node("Range").text = "%dm" % weapon.range_meters
    row.get_node("ROF").text = "%d/min" % weapon.rate_of_fire
    row.get_node("Suppression").text = str(weapon.suppression_value)

    # Color code based on weapon role
    if weapon.is_anti_armor:
        row.get_node("Damage").add_theme_color_override("font_color", Color.ORANGE)

    return row

func _rating_to_string(rating: int) -> String:
    const RATINGS := ["Bad", "Poor", "Medium", "Good", "Very Good", "Exceptional"]
    return RATINGS[clampi(rating, 0, 5)]
```

**Key Constants for Unit Display:**

```gdscript
# unit_display_constants.gd
class_name UnitDisplayConstants

# Optics ratings (detection range multiplier)
const OPTICS_MULTIPLIERS := {
    0: 0.5,   # Bad
    1: 0.7,   # Poor
    2: 1.0,   # Medium
    3: 1.3,   # Good
    4: 1.6,   # Very Good
    5: 2.0,   # Exceptional
}

# Stealth ratings (detection difficulty multiplier)
const STEALTH_MULTIPLIERS := {
    0: 1.5,   # Bad (easier to spot)
    1: 1.2,   # Poor
    2: 1.0,   # Medium
    3: 0.8,   # Good
    4: 0.6,   # Very Good
    5: 0.4,   # Exceptional (hardest to spot)
}

# Size affects base detection range
const SIZE_DETECTION_BASE := {
    GameEnums.UnitSize.SMALL: 150.0,
    GameEnums.UnitSize.MEDIUM: 250.0,
    GameEnums.UnitSize.LARGE: 400.0,
    GameEnums.UnitSize.VERY_LARGE: 600.0,
}
```

---

## 3. Autonomous Unit Behavior ("Place and They Work")

### 3.1 Core Philosophy

**Bible Reference:** Pillar 5 - "The War Continues"

Eugen games embody the principle that **well-placed units should fight effectively without constant attention**. The player is a commander, not a puppeteer.

**Key Autonomous Behaviors:**

| Behavior | Trigger | Unit Action |
|----------|---------|-------------|
| **Auto-engage** | Enemy in range + LOS | Open fire |
| **Self-preservation** | Taking heavy fire | Seek cover, reverse |
| **Ammo conservation** | Low ammo | Reduce fire rate |
| **Retreat** | Critically damaged/routed | Fall back to safety |
| **Regroup** | Scattered after combat | Reform formation |

### 3.2 Attack Orders vs. Movement Orders

**Movement Order (Right-click on ground):**
- Unit moves to destination
- Will not stop to engage enemies
- Will return fire if attacked (defensive)
- Priority: Reach destination

**Attack Order (Right-click on enemy):**
- Unit engages target
- Will pursue if target retreats
- Will find optimal firing position
- Priority: Destroy target

**Attack-Move (A + click):**
- Unit moves toward destination
- Engages any enemy encountered
- Stops to fight, then continues
- Priority: Clear path to destination

**Reverse Move (Ctrl + right-click):**
- Vehicle reverses (keeps front armor toward threat)
- Infantry crawl backward
- Maintains defensive facing

### 3.3 Rules of Engagement (ROE)

**WARNO ROE Settings:**

| ROE | Behavior | Use Case |
|-----|----------|----------|
| **Fire at Will** | Engage any valid target | Default offensive |
| **Return Fire** | Only fire if fired upon | Ambush, stealth |
| **Hold Fire** | Never fire automatically | Recon, infiltration |
| **Fire Position** | Attack-move to position, then hold | Defensive setup |

**ROE Implementation:**

```gdscript
# unit_roe.gd
enum ROE { FIRE_AT_WILL, RETURN_FIRE, HOLD_FIRE, FIRE_POSITION }

var current_roe: ROE = ROE.FIRE_AT_WILL
var _has_been_fired_upon: bool = false
var _position_reached: bool = false

func can_engage_target(target: Node3D) -> bool:
    match current_roe:
        ROE.FIRE_AT_WILL:
            return _is_valid_target(target)
        ROE.RETURN_FIRE:
            return _has_been_fired_upon and _is_valid_target(target)
        ROE.HOLD_FIRE:
            return false
        ROE.FIRE_POSITION:
            return _position_reached and _is_valid_target(target)
    return false

func _on_unit_took_damage(attacker: Node3D) -> void:
    _has_been_fired_upon = true

    if current_roe == ROE.RETURN_FIRE:
        # Immediately engage the attacker
        if can_engage_target(attacker):
            _set_attack_target(attacker)

func _on_reached_destination() -> void:
    _position_reached = true
```

### 3.4 Auto-Target Priority System

**WARNO Target Priority (Infantry):**

| Priority | Target Type | Reason |
|----------|-------------|--------|
| 1 | Immediate threat (firing at us) | Survival |
| 2 | Soft targets in range | Maximize damage |
| 3 | Exposed infantry | Easy kills |
| 4 | Vehicles (if AT weapons) | Role fulfillment |
| 5 | Buildings/structures | Opportunity |

**WARNO Target Priority (Vehicles):**

| Priority | Target Type | Reason |
|----------|-------------|--------|
| 1 | Immediate threat (AT weapons) | Survival |
| 2 | Enemy armor (if can penetrate) | Counter-armor |
| 3 | High-value targets (command, supply) | Strategic |
| 4 | Infantry concentrations | HE effectiveness |
| 5 | Buildings | Opportunity |

**Implementation:**

```gdscript
# target_prioritization.gd
class_name TargetPrioritizer

static func get_priority(attacker: Node3D, target: Node3D) -> float:
    var priority: float = 0.0

    # Factor 1: Is target threatening us?
    if _is_target_engaging_us(target, attacker):
        priority += 100.0

    # Factor 2: Can we effectively damage them?
    var effectiveness := _get_weapon_effectiveness(attacker, target)
    priority += effectiveness * 50.0

    # Factor 3: Target value
    priority += _get_target_value(target) * 20.0

    # Factor 4: Distance (closer = higher priority)
    var distance := attacker.global_position.distance_to(target.global_position)
    var max_range := attacker.get_max_weapon_range()
    priority += (1.0 - distance / max_range) * 30.0

    # Factor 5: Target vulnerability
    if _is_target_suppressed(target):
        priority += 15.0
    if _is_target_flanked(target, attacker):
        priority += 25.0

    return priority

static func _get_weapon_effectiveness(attacker: Node3D, target: Node3D) -> float:
    if target.is_in_group("infantry"):
        return attacker.get_anti_infantry_rating()
    elif target.is_in_group("vehicles"):
        return attacker.get_anti_armor_rating()
    elif target.is_in_group("buildings"):
        return attacker.get_anti_structure_rating()
    return 0.5

static func _get_target_value(target: Node3D) -> float:
    # High-value targets
    if target.is_in_group("command"):
        return 1.0
    if target.is_in_group("supply"):
        return 0.8
    if target.is_in_group("artillery"):
        return 0.9
    if target.is_in_group("air_defense"):
        return 0.7
    return 0.5
```

### 3.5 Retreat When Outmatched

**WARNO Retreat Triggers:**

| Condition | Response |
|-----------|----------|
| Health < 25% | Auto-retreat to nearest safe zone |
| Morale = Routed | Uncontrollable retreat |
| All weapons destroyed | Retreat (combat ineffective) |
| Ammunition exhausted | Retreat to resupply |
| Commander orders retreat | Manual override |

**Retreat Behavior:**

```gdscript
# retreat_behavior.gd
func _check_retreat_conditions() -> void:
    if _should_auto_retreat():
        _initiate_retreat()

func _should_auto_retreat() -> bool:
    # Health critical
    if health_percent < 0.25:
        return true

    # Morale broken
    if morale_state == MoraleState.ROUTED:
        return true

    # Combat ineffective
    if not _has_functional_weapons():
        return true

    # Outmatched (taking damage, can't respond)
    if _damage_taken_recently > _damage_dealt_recently * 3.0:
        return true

    return false

func _initiate_retreat() -> void:
    var retreat_target := _find_retreat_position()

    if retreat_target:
        set_roe(ROE.RETURN_FIRE)  # Defensive during retreat
        move_to(retreat_target, MoveType.RETREAT)
        BattleSignals.unit_retreating.emit(self, retreat_target)
    else:
        # No safe position - fight to the death
        set_roe(ROE.FIRE_AT_WILL)

func _find_retreat_position() -> Vector3:
    # Priority 1: Nearby firebase
    var nearest_firebase := _find_nearest_friendly_firebase()
    if nearest_firebase and _is_path_safe(nearest_firebase.position):
        return nearest_firebase.position

    # Priority 2: Friendly unit concentration
    var friendly_cluster := _find_friendly_concentration()
    if friendly_cluster:
        return friendly_cluster

    # Priority 3: Cover position away from enemy
    var cover_position := _find_cover_away_from_enemy()
    if cover_position:
        return cover_position

    return Vector3.ZERO  # No retreat possible
```

### 3.6 Standing Orders System

**Bible Reference:** Pillar 5 - "Patrols run on standing orders"

```gdscript
# standing_orders.gd
class_name StandingOrders extends Node

enum OrderType {
    GUARD,      # Hold position, engage threats
    PATROL,     # Move between waypoints, engage threats
    AGGRESSIVE, # Seek and destroy in area
    DEFEND,     # Hold position, don't pursue
    AMBUSH,     # Hold fire until triggered, then engage
}

@export var order_type: OrderType = OrderType.GUARD
@export var patrol_waypoints: Array[Vector3] = []
@export var patrol_radius: float = 50.0
@export var ambush_trigger_distance: float = 30.0

var _current_waypoint_index: int = 0
var _ambush_triggered: bool = false

func execute_order(unit: Node3D) -> void:
    match order_type:
        OrderType.GUARD:
            _execute_guard(unit)
        OrderType.PATROL:
            _execute_patrol(unit)
        OrderType.AGGRESSIVE:
            _execute_aggressive(unit)
        OrderType.DEFEND:
            _execute_defend(unit)
        OrderType.AMBUSH:
            _execute_ambush(unit)

func _execute_patrol(unit: Node3D) -> void:
    if patrol_waypoints.is_empty():
        return

    var current_waypoint := patrol_waypoints[_current_waypoint_index]

    # Check for enemies while patrolling
    var nearby_enemies := SpatialHashGrid.get_enemies_in_radius(
        unit.global_position, patrol_radius, unit.faction
    )

    if not nearby_enemies.is_empty() and unit.can_engage_target(nearby_enemies[0]):
        # Engage, then resume patrol
        unit.set_attack_target(nearby_enemies[0])
    elif unit.global_position.distance_to(current_waypoint) < 5.0:
        # Reached waypoint, move to next
        _current_waypoint_index = (_current_waypoint_index + 1) % patrol_waypoints.size()
        unit.move_to(patrol_waypoints[_current_waypoint_index])
    elif not unit.is_moving():
        # Continue to current waypoint
        unit.move_to(current_waypoint)

func _execute_ambush(unit: Node3D) -> void:
    unit.set_roe(ROE.HOLD_FIRE)

    if _ambush_triggered:
        unit.set_roe(ROE.FIRE_AT_WILL)
        return

    # Check for ambush trigger
    var nearby_enemies := SpatialHashGrid.get_enemies_in_radius(
        unit.global_position, ambush_trigger_distance, unit.faction
    )

    if not nearby_enemies.is_empty():
        _ambush_triggered = true
        unit.set_roe(ROE.FIRE_AT_WILL)
        BattleSignals.ambush_triggered.emit(unit, nearby_enemies)
```

---

## 4. Recon and Fog of War System

### 4.1 Eugen Detection Model

**Core Principle:** You can only shoot what you can see. Recon units are force multipliers.

**Detection Formula (simplified from WARNO):**

```
Detection Range = BASE_RANGE * Optics_Multiplier * (1 / Stealth_Multiplier) * Terrain_Modifier

Where:
- BASE_RANGE = Size-based detection distance
- Optics_Multiplier = Observer's optics rating (0.5 to 2.0)
- Stealth_Multiplier = Target's stealth rating (0.4 to 1.5)
- Terrain_Modifier = Cover/concealment effect (0.2 to 1.0)
```

### 4.2 Optics Ratings

| Rating | Name | Detection Multiplier | Typical Units |
|--------|------|---------------------|---------------|
| 0 | Bad | 0.5x | Supply trucks, artillery |
| 1 | Poor | 0.7x | Most infantry |
| 2 | Medium | 1.0x | Tanks, IFVs |
| 3 | Good | 1.3x | Scout vehicles |
| 4 | Very Good | 1.6x | Recon infantry |
| 5 | Exceptional | 2.0x | Special forces, forward observers |

### 4.3 Stealth Ratings

| Rating | Name | Detection Difficulty | Typical Units |
|--------|------|---------------------|---------------|
| 0 | Bad | 1.5x easier | Large vehicles, helicopters |
| 1 | Poor | 1.2x easier | Medium vehicles, weapon teams |
| 2 | Medium | Normal | Standard infantry |
| 3 | Good | 0.8x harder | Trained infantry in cover |
| 4 | Very Good | 0.6x harder | Recon teams |
| 5 | Exceptional | 0.4x harder | Snipers, special forces |

### 4.4 Exceptional Optics as Force Multiplier

**The Recon Value Proposition:**
- An Exceptional optics recon team (2.0x range) can spot enemies that teammates can't
- Spotted enemies become valid targets for **all** friendly units with LOS
- This means recon enables long-range artillery, air strikes, and ambushes

**Example:**
```
Scenario: Enemy tank in forest
- Tank stealth in forest: Good (0.8x detection)
- Normal infantry optics: Poor (0.7x)
- Recon team optics: Exceptional (2.0x)

Detection range for infantry: 250m * 0.7 * (1/0.8) * 0.3 (forest) = 66m
Detection range for recon: 250m * 2.0 * (1/0.8) * 0.3 (forest) = 188m

Recon spots tank at 150m, shares contact.
Artillery fires on spotted target from 3km away.
```

### 4.5 Fog of War States

| State | Visual | Unit Data Visible | Targeting |
|-------|--------|-------------------|-----------|
| **Unknown** | Full fog | None | Cannot target |
| **Suspected** | Blurred icon | Type only | Area fire only |
| **Spotted** | Clear icon | Full stats | Direct fire |
| **Tracked** | Icon + trail | Full stats + movement | Full targeting |

**Spotted Mechanic:**
- Once spotted, unit remains visible for ~5-10 seconds after losing LOS
- Moving while spotted extends tracking duration
- Firing weapons extends spotted duration significantly
- Stationary + silent = faster return to unspotted

### 4.6 Implementation Guidance for RealVietnamRTS

```gdscript
# detection_system.gd
class_name DetectionSystem extends Node

const BASE_DETECTION_RANGES := {
    GameEnums.UnitSize.SMALL: 150.0,
    GameEnums.UnitSize.MEDIUM: 250.0,
    GameEnums.UnitSize.LARGE: 400.0,
    GameEnums.UnitSize.VERY_LARGE: 600.0,
}

const OPTICS_MULTIPLIERS := [0.5, 0.7, 1.0, 1.3, 1.6, 2.0]
const STEALTH_MULTIPLIERS := [1.5, 1.2, 1.0, 0.8, 0.6, 0.4]

const TERRAIN_DETECTION_MODIFIERS := {
    GameEnums.TerrainType.OPEN: 1.0,
    GameEnums.TerrainType.LIGHT_COVER: 0.7,
    GameEnums.TerrainType.FOREST: 0.3,
    GameEnums.TerrainType.DENSE_JUNGLE: 0.15,
    GameEnums.TerrainType.BUILDING: 0.0,  # Cannot detect inside buildings
}

const SPOTTED_DURATION_BASE := 5.0
const SPOTTED_DURATION_MOVING := 3.0  # Additional when moving
const SPOTTED_DURATION_FIRING := 8.0  # Additional when firing

func can_detect(observer: Node3D, target: Node3D) -> bool:
    var detection_range := calculate_detection_range(observer, target)
    var distance := observer.global_position.distance_to(target.global_position)

    return distance <= detection_range and _has_line_of_sight(observer, target)

func calculate_detection_range(observer: Node3D, target: Node3D) -> float:
    var base_range: float = BASE_DETECTION_RANGES.get(
        target.unit_size, 250.0
    )

    var optics_mult: float = OPTICS_MULTIPLIERS[
        clampi(observer.optics_rating, 0, 5)
    ]

    var stealth_mult: float = STEALTH_MULTIPLIERS[
        clampi(target.stealth_rating, 0, 5)
    ]

    var terrain_mult: float = _get_terrain_modifier(target.global_position)

    # Activity modifiers
    var activity_mult: float = 1.0
    if target.is_firing:
        activity_mult = 2.0  # Much easier to spot when shooting
    elif target.is_moving:
        activity_mult = 1.3  # Movement draws attention

    return base_range * optics_mult * (1.0 / stealth_mult) * terrain_mult * activity_mult

func _get_terrain_modifier(position: Vector3) -> float:
    var terrain_type := TerrainEngine.get_terrain_type_at(position)
    return TERRAIN_DETECTION_MODIFIERS.get(terrain_type, 1.0)
```

**Fog of War Rendering:**

```gdscript
# fog_of_war.gd
class_name FogOfWar extends Node

enum VisibilityState { UNKNOWN, SUSPECTED, SPOTTED, TRACKED }

var _unit_visibility: Dictionary = {}  # unit_id -> VisibilityState
var _spotted_timers: Dictionary = {}   # unit_id -> time_remaining

func update_visibility(observer_faction: int) -> void:
    var observers := _get_all_observers(observer_faction)
    var potential_targets := _get_all_enemy_units(observer_faction)

    for target in potential_targets:
        var target_id := target.get_instance_id()
        var was_spotted := _unit_visibility.get(target_id, VisibilityState.UNKNOWN) >= VisibilityState.SPOTTED
        var is_spotted := false

        for observer in observers:
            if DetectionSystem.can_detect(observer, target):
                is_spotted = true
                break

        if is_spotted:
            _unit_visibility[target_id] = VisibilityState.SPOTTED
            _spotted_timers[target_id] = _calculate_spotted_duration(target)
        elif was_spotted and _spotted_timers.get(target_id, 0.0) > 0:
            # Fade from spotted to suspected
            _unit_visibility[target_id] = VisibilityState.SPOTTED
        else:
            _unit_visibility[target_id] = VisibilityState.UNKNOWN

func _calculate_spotted_duration(unit: Node3D) -> float:
    var duration := SPOTTED_DURATION_BASE

    if unit.is_moving:
        duration += SPOTTED_DURATION_MOVING
    if unit.is_firing:
        duration += SPOTTED_DURATION_FIRING

    return duration
```

---

## 5. Morale and Stress System

### 5.1 WARNO Morale States

**Bible Reference:** See `docs/design/morale_system_design.md` for full implementation.

WARNO uses a **5-state morale system**:

| State | Visual | Unit Behavior |
|-------|--------|---------------|
| **Calm** | Green | Full effectiveness, will advance |
| **Worried** | Yellow | Slightly reduced accuracy, cautious |
| **Shaken** | Orange | Reduced accuracy, won't advance, seeks cover |
| **Panicked** | Red | Severely reduced effectiveness, retreat behavior |
| **Routed** | Flashing red | Uncontrollable retreat, ignores orders |

### 5.2 Morale Damage Sources

| Source | Morale Damage | Notes |
|--------|---------------|-------|
| Near-miss (small arms) | 1-3 | Cumulative |
| Near-miss (MG) | 5-10 | Primary suppression |
| Near-miss (artillery) | 15-25 | Area effect |
| Hit (wounded) | 10-20 | Per casualty |
| Hit (killed) | 25-35 | Per death |
| Friendly unit destroyed nearby | 20-30 | Morale shock |
| Leader killed | 40-50 | Command loss |
| Flanked | 15-20 | Tactical penalty |
| Ambushed | 30-40 | Surprise penalty |
| Outnumbered | 5-15 | Continuous drain |

### 5.3 Training Level and Morale Resistance

| Training | Morale Damage Mult | Recovery Rate | Break Threshold |
|----------|-------------------|---------------|-----------------|
| Conscript | 1.5x | 0.5x | 60% |
| Regular | 1.0x | 1.0x | 80% |
| Veteran | 0.8x | 1.3x | 90% |
| Elite | 0.5x | 2.0x | Never (only pins) |

### 5.4 Morale Recovery

**Recovery Triggers:**

| Condition | Recovery Rate |
|-----------|---------------|
| In cover, no contact | Fast (10%/sec) |
| In cover, under fire | Slow (2%/sec) |
| In open, no contact | Medium (5%/sec) |
| Near NCO/officer | +50% recovery |
| Recently killed enemy | +20 instant |
| Reinforcements arrived | +10 instant |

### 5.5 Integration with Suppression

Our existing suppression system (from `morale_system_design.md`) should integrate with morale:

```gdscript
# Morale and suppression interaction
func update_combat_state(delta: float) -> void:
    # Suppression affects immediate behavior (can't move/fire)
    _update_suppression(delta)

    # Morale affects willingness to fight (will retreat?)
    _update_morale(delta)

    # Combined effect determines unit state
    var suppression_state := _get_suppression_state()
    var morale_state := _get_morale_state()

    # Morale break + high suppression = rout
    if morale_state == MoraleState.BROKEN and suppression_level > 0.5:
        _trigger_rout()
    # High morale can resist suppression effects
    elif morale_state == MoraleState.HIGH:
        suppression_level = maxf(suppression_level - 0.1 * delta, 0.0)
```

---

## 6. Deck Building and Unit Availability

### 6.1 Pre-Battle Army Composition

**Bible Reference:** D-105 covers our doctrine/deck system.

**How Steel Division Does It:**

1. **Division Selection** - Pick a historical division (e.g., 3rd Armored)
2. **Deck Building** - Fill slots with units from division roster
3. **Phase Assignment** - Assign units to Phase A, B, or C availability
4. **Point Limit** - Total deck value must stay under cap

### 6.2 Point Costs and Activation

**WARNO Point System:**

| Unit Category | Typical Cost | Notes |
|---------------|--------------|-------|
| Recon infantry | 15-30 pts | Cheap scouts |
| Line infantry | 20-40 pts | Backbone units |
| Elite infantry | 40-70 pts | Specialized |
| Light vehicles | 30-60 pts | Transports, scouts |
| IFVs | 60-100 pts | Infantry support |
| Tanks | 80-180 pts | Main battle tanks |
| Artillery | 70-150 pts | Fire support |
| Helicopters | 80-200 pts | Air mobility |
| Aircraft | 100-250 pts | Air superiority |

**Activation Points:**
- Earn points over time and through objectives
- Spend points to call in units from deck
- Higher-cost units require more time to deploy

### 6.3 Steel Division Phase System

**Phase Availability:**

| Phase | Time | Available Units | Character |
|-------|------|-----------------|-----------|
| **Phase A** | 0-10 min | Recon, light forces | Scouting, probing |
| **Phase B** | 10-20 min | Main battle units | Primary engagement |
| **Phase C** | 20+ min | Heavy/reserve units | Decisive action |

**Phase Assignment Rules:**
- Each unit card assigned to ONE phase
- Earlier phases = limited selection
- Later phases = heavier units available
- Phase progression is time-based, not trigger-based

### 6.4 Unit Card Limits

**Preventing Spam:**

| Limit Type | Example | Effect |
|------------|---------|--------|
| **Per-card limit** | M1 Abrams: 4 max | Can't field more than 4 |
| **Category limit** | Tanks: 8 max | Total tanks capped |
| **Deck slots** | 25 cards total | Must diversify |
| **Veterancy cost** | Elite +50% cost | Quality vs. quantity |

### 6.5 How This Prevents Blob Tactics

1. **Limited availability** - Can't spam infinite of one unit
2. **High costs** - Losing expensive units hurts
3. **Phase gates** - Can't rush heavy units early
4. **Cooldowns** - Reinforcing takes time
5. **Map control** - Must hold spawn zones

### 6.6 RealVietnamRTS Approach

**We use reinforcement timing instead of phases (per D-101):**

| Our System | Eugen System | Difference |
|------------|--------------|------------|
| Reinforcement delay | Activation points | Time-based only |
| Doctrine selection | Division selection | Similar concept |
| Building auto-include | Manual slot filling | Simplified |
| Supply dependency | Point cost | Physical logistics |

**Our Reinforcement Timing (from Game Bible):**

```gdscript
# reinforcement_constants.gd
const REINFORCEMENT_TIMES := {
    GameEnums.UnitType.RIFLE_SQUAD: 180.0,      # 3 min
    GameEnums.UnitType.ENGINEER_SQUAD: 240.0,   # 4 min
    GameEnums.UnitType.WEAPONS_SQUAD: 300.0,    # 5 min
    GameEnums.UnitType.RECON_TEAM: 180.0,       # 3 min
    GameEnums.UnitType.M48_PATTON: 720.0,       # 12 min
    GameEnums.UnitType.HUEY_TRANSPORT: 360.0,   # 6 min
}

# Doctrine modifiers
const DOCTRINE_REINFORCEMENT_MODIFIERS := {
    "air_cavalry": {
        GameEnums.UnitType.HUEY_TRANSPORT: 0.75,  # Faster helis
        GameEnums.UnitType.M48_PATTON: 1.25,      # Slower armor
    },
    "mechanized": {
        GameEnums.UnitType.M48_PATTON: 0.85,      # Faster armor
        GameEnums.UnitType.HUEY_TRANSPORT: 1.15,  # Slower helis
    },
}
```

---

## 7. Supply and Logistics

### 7.1 Ammunition Tracking

**Bible Reference:** Pillar 3 - "Physical Supply Chains"

**WARNO/Wargame Ammo System:**

| Weapon Type | Typical Ammo | Consumption Rate |
|-------------|--------------|------------------|
| Rifle | 500 rounds | 20/minute (sustained) |
| MG | 1500 rounds | 100/minute (sustained) |
| AT weapon | 6-12 rounds | 2/minute (when engaging) |
| Tank gun | 40-60 rounds | 6/minute (combat) |
| Artillery | 20-40 rounds | 4/minute (fire mission) |
| Helicopter | 2-4 rocket pods, 500 MG | Per attack run |

**Ammo States:**

| State | Indicator | Effect |
|-------|-----------|--------|
| **Full** | Green | Normal operation |
| **Low** | Yellow | Reduced rate of fire |
| **Critical** | Red | One magazine remaining |
| **Empty** | Flashing | Cannot fire |

### 7.2 Supply Vehicles and FOBs

**Broken Arrow Supply System:**

| Element | Capacity | Range | Speed |
|---------|----------|-------|-------|
| FOB | 5000 supplies | Unlimited | Static |
| Supply Truck | 500 supplies | N/A | 60 km/h |
| Supply Helicopter | 300 supplies | N/A | 200 km/h |
| Airdrop | 200 supplies | N/A | Instant |

**FOB Mechanics:**
- FOB provides passive resupply to units within radius
- FOB itself must be resupplied by rear-area logistics
- Losing FOB = forward units cut off

### 7.3 Resupply Mechanics

**WARNO Resupply Process:**

1. Unit enters supply zone (near FOB or supply vehicle)
2. Resupply begins automatically
3. Rate based on priority (ammo > fuel > repairs)
4. Interrupted by combat
5. Supply source depletes proportionally

**Resupply Priorities:**

| Priority | Type | Reason |
|----------|------|--------|
| 1 | Ammunition | Combat effectiveness |
| 2 | Fuel | Mobility |
| 3 | Repairs | Survival |
| 4 | Medical | Crew recovery |

### 7.4 Running Dry

**Effect of Zero Ammo:**

| Weapon Type | Behavior |
|-------------|----------|
| Infantry small arms | Melee only (ineffective) |
| MG | Cannot fire |
| AT weapons | Cannot engage armor |
| Tank | Main gun disabled, MG may function |
| Artillery | Fire mission unavailable |

**Tactical Implications:**
- Units at zero ammo should retreat for resupply
- Enemy can force ammo expenditure through harassment
- Smoke missions consume artillery ammo rapidly
- Extended firefights drain both sides

### 7.5 Broken Arrow Medevac and Repair

**Medevac System:**
- Wounded crew can be evacuated
- Medevac helicopters retrieve casualties
- Crew returned to replacement pool
- Veterancy preserved through medevac

**Repair System:**
- Damaged vehicles can be field-repaired
- Repair vehicles required
- Partial repairs restore combat effectiveness
- Full repairs require rear-area facilities

### 7.6 Implementation Guidance for RealVietnamRTS

```gdscript
# supply_system.gd
class_name SupplySystem extends Node

enum SupplyType { AMMO, FUEL, MEDICAL, CONSTRUCTION }

const RESUPPLY_RATES := {
    SupplyType.AMMO: 10.0,        # Units per second
    SupplyType.FUEL: 5.0,
    SupplyType.MEDICAL: 2.0,
    SupplyType.CONSTRUCTION: 8.0,
}

const RESUPPLY_PRIORITY := [
    SupplyType.AMMO,
    SupplyType.FUEL,
    SupplyType.MEDICAL,
    SupplyType.CONSTRUCTION,
]

func process_resupply(unit: Node3D, supply_source: Node3D, delta: float) -> void:
    if not _can_resupply(unit, supply_source):
        return

    # Process in priority order
    for supply_type in RESUPPLY_PRIORITY:
        var needed := unit.get_supply_needed(supply_type)
        if needed <= 0:
            continue

        var available := supply_source.get_supply_available(supply_type)
        if available <= 0:
            continue

        var transfer_rate := RESUPPLY_RATES[supply_type] * delta
        var transfer_amount := minf(minf(needed, available), transfer_rate)

        unit.receive_supply(supply_type, transfer_amount)
        supply_source.consume_supply(supply_type, transfer_amount)

        # Only resupply one type per frame for visual clarity
        break

func _can_resupply(unit: Node3D, source: Node3D) -> bool:
    # Must be in range
    var distance := unit.global_position.distance_to(source.global_position)
    if distance > source.supply_radius:
        return false

    # Must be same faction
    if unit.faction != source.faction:
        return false

    # Must not be in combat
    if unit.is_in_combat():
        return false

    return true
```

**Ammo Consumption Tracking:**

```gdscript
# weapon_ammo.gd
class_name WeaponAmmo extends Resource

@export var max_ammo: int = 500
@export var current_ammo: int = 500
@export var burst_size: int = 3
@export var reload_time: float = 2.0

var _is_reloading: bool = false

func can_fire() -> bool:
    return current_ammo >= burst_size and not _is_reloading

func consume_burst() -> void:
    current_ammo -= burst_size
    current_ammo = maxi(current_ammo, 0)

    if current_ammo <= 0:
        BattleSignals.unit_ammo_depleted.emit(get_parent())

func get_ammo_state() -> int:
    var percent := float(current_ammo) / float(max_ammo)

    if percent > 0.5:
        return AmmoState.FULL
    elif percent > 0.2:
        return AmmoState.LOW
    elif percent > 0:
        return AmmoState.CRITICAL
    else:
        return AmmoState.EMPTY

func resupply(amount: int) -> int:
    var needed := max_ammo - current_ammo
    var received := mini(needed, amount)
    current_ammo += received
    return received
```

**Supply Convoy System:**

```gdscript
# convoy_manager.gd
class_name ConvoyManager extends Node

signal convoy_departed(convoy: Node3D, destination: Node3D)
signal convoy_arrived(convoy: Node3D, destination: Node3D)
signal convoy_destroyed(convoy: Node3D, attacker: Node3D)

const CONVOY_INTERVAL := 300.0  # 5 minutes between convoys
const TRUCK_SPEED := 8.0        # m/s on roads
const TRUCK_CAPACITY := 500.0

var _active_convoys: Array[Node3D] = []
var _convoy_timer: float = 0.0

func _process(delta: float) -> void:
    _convoy_timer += delta

    if _convoy_timer >= CONVOY_INTERVAL:
        _convoy_timer = 0.0
        _dispatch_scheduled_convoy()

    _update_active_convoys(delta)

func _dispatch_scheduled_convoy() -> void:
    var firebases := get_tree().get_nodes_in_group("firebases")

    for firebase in firebases:
        if firebase.faction != GameEnums.Faction.US_ARMY:
            continue
        if firebase.supply_level > 0.7:  # Well supplied
            continue

        var route := _find_road_route_to(firebase)
        if route.is_empty():
            continue  # No road access

        var convoy := _spawn_convoy(route)
        convoy.destination = firebase
        convoy.cargo = TRUCK_CAPACITY
        _active_convoys.append(convoy)
        convoy_departed.emit(convoy, firebase)

func _on_convoy_arrived(convoy: Node3D) -> void:
    var firebase: Node3D = convoy.destination
    firebase.receive_supply(SupplyType.AMMO, convoy.cargo * 0.4)
    firebase.receive_supply(SupplyType.FUEL, convoy.cargo * 0.3)
    firebase.receive_supply(SupplyType.MEDICAL, convoy.cargo * 0.2)
    firebase.receive_supply(SupplyType.CONSTRUCTION, convoy.cargo * 0.1)

    convoy_arrived.emit(convoy, firebase)
    _return_convoy_to_depot(convoy)
```

---

## 8. RealVietnamRTS Integration Guide

### 8.1 Priority Implementation Order

Based on Game Bible pillars and MVP scope:

| Priority | System | Pillar Served | Eugen Reference |
|----------|--------|---------------|-----------------|
| **1** | Strategic Zoom + LOD | D-001 (multi-firebase scale) | WARNO zoom system |
| **2** | Fog of War + Detection | Pillar 1 (Carve the Map) | Wargame optics/stealth |
| **3** | Autonomous Unit Behavior | Pillar 5 (War Continues) | WARNO ROE + targeting |
| **4** | Supply Consumption | Pillar 3 (Physical Supply) | Broken Arrow logistics |
| **5** | Morale Integration | Combat depth | WARNO morale states |
| **6** | Unit Card UI | Player information | Wargame card design |

### 8.2 What to Borrow vs. Skip

**Borrow:**

| Mechanic | Source | Why |
|----------|--------|-----|
| NATO symbol rendering at distance | All Eugen | Essential for scale |
| Optics/stealth detection model | Wargame/WARNO | Makes recon valuable |
| ROE system | WARNO | Pillar 5 compliance |
| Auto-retreat behavior | All Eugen | Unit preservation |
| Ammo tracking per weapon | Broken Arrow | Pillar 3 compliance |
| 5-state morale | WARNO | Combat depth |
| Target prioritization | All Eugen | Reduces micro burden |

**Skip:**

| Mechanic | Source | Why |
|----------|--------|-----|
| Activation points | Wargame | We use time-based reinforcement |
| Phase system | Steel Division | We use continuous availability |
| Deck slot limits | All Eugen | We use doctrine auto-include |
| Fuel consumption | Broken Arrow | Simplify for MVP (post-MVP) |
| Full repair system | Broken Arrow | Simplify for MVP (post-MVP) |
| Naval units | Wargame: RD | Not in scope |
| Air-to-air combat | All Eugen | Fixed-wing parked for MVP |

### 8.3 Code Structure Suggestions

**Suggested File Organization:**

```
battle_system/
    detection/
        detection_system.gd      # Core detection logic
        fog_of_war.gd            # FoW rendering
        optics_calculator.gd     # Range calculations
    behavior/
        unit_ai.gd               # Base autonomous behavior
        standing_orders.gd       # Patrol, guard, ambush
        target_prioritizer.gd    # Target selection
        retreat_handler.gd       # Auto-retreat logic
    morale/
        morale_system.gd         # 5-state morale
        suppression_system.gd    # Existing suppression
        morale_integration.gd    # Combined effects
    supply/
        ammo_tracker.gd          # Per-weapon ammo
        supply_consumer.gd       # Unit supply needs
        resupply_system.gd       # Depot/truck logic
ui/
    unit_display/
        selection_panel.gd       # Minimal selection UI
        unit_card.gd             # Detailed inspection
        nato_marker.gd           # Strategic zoom symbols
    hud/
        ammo_indicator.gd        # Ammo state display
        morale_indicator.gd      # Morale state icon
```

### 8.4 Constants to Define

**Master Constants File:**

```gdscript
# eugen_constants.gd
class_name EugenConstants

# Detection System (Section 4)
const OPTICS_MULTIPLIERS := [0.5, 0.7, 1.0, 1.3, 1.6, 2.0]
const STEALTH_MULTIPLIERS := [1.5, 1.2, 1.0, 0.8, 0.6, 0.4]
const SIZE_DETECTION_BASE := {
    GameEnums.UnitSize.SMALL: 150.0,
    GameEnums.UnitSize.MEDIUM: 250.0,
    GameEnums.UnitSize.LARGE: 400.0,
    GameEnums.UnitSize.VERY_LARGE: 600.0,
}
const SPOTTED_DURATION_BASE := 5.0
const SPOTTED_DURATION_MOVING := 3.0
const SPOTTED_DURATION_FIRING := 8.0

# Morale System (Section 5)
const MORALE_THRESHOLDS := {
    "calm": 0.8,
    "worried": 0.6,
    "shaken": 0.4,
    "panicked": 0.2,
    "routed": 0.0,
}
const TRAINING_MORALE_RESISTANCE := {
    GameEnums.TrainingLevel.CONSCRIPT: 1.5,
    GameEnums.TrainingLevel.REGULAR: 1.0,
    GameEnums.TrainingLevel.VETERAN: 0.8,
    GameEnums.TrainingLevel.ELITE: 0.5,
}
const MORALE_RECOVERY_IN_COVER := 0.1      # Per second
const MORALE_RECOVERY_IN_OPEN := 0.05
const MORALE_RECOVERY_NCO_BONUS := 0.5     # 50% faster

# Supply System (Section 7)
const RESUPPLY_RATES := {
    SupplyType.AMMO: 10.0,
    SupplyType.FUEL: 5.0,
    SupplyType.MEDICAL: 2.0,
    SupplyType.CONSTRUCTION: 8.0,
}
const AMMO_STATE_THRESHOLDS := {
    "full": 0.5,
    "low": 0.2,
    "critical": 0.0,
}

# Camera/Zoom System (Section 1)
const ZOOM_MIN := 20.0
const ZOOM_MAX := 800.0
const LOD_TACTICAL := 100.0
const LOD_OPERATIONAL := 300.0
const LOD_STRATEGIC := 500.0

# Target Priority Weights (Section 3)
const PRIORITY_THREAT_BONUS := 100.0
const PRIORITY_EFFECTIVENESS_WEIGHT := 50.0
const PRIORITY_VALUE_WEIGHT := 20.0
const PRIORITY_DISTANCE_WEIGHT := 30.0
const PRIORITY_SUPPRESSED_BONUS := 15.0
const PRIORITY_FLANKED_BONUS := 25.0
```

### 8.5 Signal Definitions

```gdscript
# Add to battle_signals.gd

# Detection Events
signal unit_spotted(unit: Node3D, spotter: Node3D)
signal unit_lost_contact(unit: Node3D)
signal contact_shared(unit: Node3D, faction: int)

# Morale Events
signal morale_state_changed(unit: Node3D, old_state: int, new_state: int)
signal unit_routed(unit: Node3D)
signal unit_rallied(unit: Node3D)

# Supply Events
signal ammo_state_changed(unit: Node3D, weapon_index: int, state: int)
signal unit_ammo_depleted(unit: Node3D)
signal resupply_started(unit: Node3D, source: Node3D)
signal resupply_completed(unit: Node3D, source: Node3D)

# Autonomous Behavior Events
signal unit_auto_engaging(unit: Node3D, target: Node3D)
signal unit_retreating(unit: Node3D, destination: Vector3)
signal standing_order_changed(unit: Node3D, order_type: int)
signal ambush_triggered(unit: Node3D, targets: Array[Node3D])

# Zoom Events
signal zoom_level_changed(level: int)
```

---

## Summary: Eugen Philosophy Applied to Vietnam

### The Core Lessons

1. **Scale Through Abstraction** - NATO symbols and LOD let you command hundreds of units across kilometers without losing tactical awareness.

2. **Units That Think** - Well-placed units fight effectively without babysitting. The player commands operations, not individual soldiers.

3. **Recon Wins Wars** - The detection model makes scouts valuable force multipliers. You can't shoot what you can't see.

4. **Morale Matters** - Units are not automatons. They get scared, they run, they need leadership. This creates combined-arms necessity.

5. **Supply is Vulnerability** - Ammunition runs out. Convoys can be ambushed. Logistics is a targetable system, not an abstract number.

6. **Preservation Over Production** - High unit costs and long reinforcement times make every loss hurt. This is the opposite of AoE-style spam.

### How This Serves Our Pillars

| Pillar | Eugen Mechanic | Application |
|--------|----------------|-------------|
| **Carve the Map** | Detection/FoW | Cleared terrain = visibility |
| **Network of Firebases** | Strategic zoom | Manage multiple positions |
| **Physical Supply Chains** | Ammo tracking, convoys | Supply is attackable |
| **Doctrine Over Spam** | High unit costs, reinforcement timing | Force preservation |
| **The War Continues** | Autonomous behavior, ROE | Units fight without micro |

---

## Related Documents

- **Game Bible:** `GAME_BIBLE.md` - Authoritative design decisions
- **Company of Heroes Reference:** `docs/gdd/company_of_heroes_reference.md` - Cover, suppression, garrison
- **Morale System Design:** `docs/design/morale_system_design.md` - Detailed suppression implementation
- **Warno/Wargame Terrain:** `docs/research/warno_wargame_terrain.md` - Cover and LOS research
- **Broken Arrow Analysis:** `docs/research/broken_arrow_analysis.md` - Supply system research

---

*End of document. For Company of Heroes mechanics, see `company_of_heroes_reference.md`.*
