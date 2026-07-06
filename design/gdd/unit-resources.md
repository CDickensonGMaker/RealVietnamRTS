# Unit Resource System GDD

> **Status**: `[LIVING]`
> **Last Updated**: 2026-05-21
> **Source Documents**: PRD.md Section 6, GAME_BIBLE.md Section 3 (Pillar 3)
> **Pillar**: 3 (Physical Supply Chains)
> **Existing Implementation**: `battle_system/nodes/squad.gd` (partial)

---

## 1. Overview

Squads carry **internal reserves** that deplete through action and time. This creates the tangible logistics pressure that defines the game. Units are not abstract tokens - they are soldiers who need ammunition to fight and water to survive. When a squad runs dry, they cannot simply wait for a cooldown; they must physically receive supplies from the logistics network or retreat to a firebase.

The Unit Resource System bridges the gap between individual unit needs and the macro-level Supply & Logistics System. Every bullet fired draws from a physical reserve. Every minute in the field drains water. When resources hit critical levels, units exhibit automated survival behaviors - retreating, calling for resupply, and warning the player through voice lines and visual indicators.

This system directly serves **Pillar 3: Physical Supply Chains** by making supply matter at the squad level. A firebase stocked with supplies but cut off by ambushed convoys is meaningless if units inside have full reserves. Conversely, a well-connected firebase with empty depots starves its defenders. The system creates pressure that flows both directions.

---

## 2. Player Fantasy

You are managing a firebase under sustained assault. Your defensive positions are holding, but you notice the warning icons appearing over your forward squads - yellow "LOW AMMO" indicators flickering above the bunker line. You check the supply depot: half full, but the road convoy was ambushed thirty minutes ago.

You scramble a Huey for emergency resupply while ordering your rear squads to rotate forward. The gunship strafes the treeline as the transport swoops in, and you watch the resupply animation play out - soldiers breaking from cover to grab ammunition crates. The LOW AMMO icons fade to green.

But you were too slow for 2nd Squad. Their indicator turned red, and over the radio you hear: "SQUAD OUT OF SUPPLIES, FALLING BACK!" They break cover and start running for the firebase - right through the enemy killzone. Three men down before they reach the wire.

Supply is not a number in a corner. Supply is soldiers dying because you did not watch the icons.

---

## 3. Detailed Rules

### 3.1 Resource Types

Squads track three internal resources that interact with each other:

| Resource | Depletion Trigger | Effect When Low (<20%) | Effect When Empty (0) |
|----------|-------------------|------------------------|----------------------|
| **Ammo** | Shooting (per shot) | "LOW AMMO" icon, reduced fire rate | Auto-retreat + voice callout "SQUAD OUT OF SUPPLIES, FALLING BACK" |
| **Water** | Time-based (passive) | "LOW WATER" icon, accelerated morale drain (-0.5/sec) | Severe morale drain (-1.5/sec), combat effectiveness -50% |
| **Morale** | Combat, casualties, dehydration | Reduced effectiveness (see Morale GDD) | Routing behavior (see Morale GDD) |

### 3.2 Resource Depletion Mechanics

#### Ammo Depletion

Ammo depletes when the squad fires:

- **Per-shot cost**: 1 ammo per shot (base)
- **Weapon modifiers**: Heavy weapons consume more ammo per burst
  - Rifle (M16, AK-47): 1 ammo/shot
  - LMG (M60, RPD): 2 ammo/burst
  - Heavy MG (M2, DShK): 3 ammo/burst
  - Mortar: 5 ammo/round
- **Suppression fire**: Continuous fire consumes at sustained rate
- **Ammo is NOT consumed** when:
  - Unit is suppressed (not firing back effectively)
  - Unit is routing (not fighting)
  - Unit is in HOLD_FIRE stance

#### Water Depletion

Water depletes passively over time:

- **Base rate**: 1 water per 30 seconds (2/minute)
- **Activity modifiers**:
  - Combat: +50% depletion (1 per 20 seconds)
  - Running/moving: +25% depletion
  - Resting in shade/cover: -25% depletion
  - Garrisoned in structure: -50% depletion
- **Environmental modifiers** (post-MVP):
  - Monsoon rain: No water depletion (rain collection)
  - Hot/clear day: +50% depletion

#### Morale Interaction

Morale is tracked in the Morale & Routing System but interacts with Unit Resources:

- **Low water** (<20%): Applies -0.5 morale/sec continuous penalty
- **Empty water** (0): Applies -1.5 morale/sec, combat effectiveness halved
- **Resupply received**: +3 morale one-time bonus (basic needs met)

### 3.3 Reserve Capacities by Unit Type

Reserve capacities vary by unit type and reflect their loadout and role:

| Unit Type | Ammo Reserve | Water Reserve | Ammo Notes | Water Notes |
|-----------|--------------|---------------|------------|-------------|
| **Rifle Squad** | 100 | 100 | Standard loadout | Standard canteens |
| **Weapons Squad** | 150 | 100 | Extra MG ammo | Same water needs |
| **Engineer Squad** | 40 | 100 | Limited combat role | Standard canteens |
| **Recon Team** | 60 | 80 | Light loadout | Reduced team size |
| **M48 Patton** | 80 | N/A | Main gun + MG rounds | Crew has internal supply |
| **Huey Transport** | 50 | N/A | Door gunner ammo | Crew rotation handles water |

**VC/NVA Units** (AI-controlled, still track resources for gameplay):

| Unit Type | Ammo Reserve | Water Reserve | Notes |
|-----------|--------------|---------------|-------|
| VC Infantry | 80 | 80 | Lighter loadout |
| VC Sappers | 30 | 60 | Explosives-focused |
| VC Mortar Team | 60 | 60 | Limited mortar rounds |
| VC Porter | 0 | 100 | Non-combat, carries supplies |

### 3.4 Resupply Mechanics

#### Auto-Resupply (Within Firebase Influence Radius)

Squads within a firebase's influence radius automatically resupply from the local Supply Depot:

1. **Trigger**: Resource below 90% AND depot has supply available
2. **Rate**: 5 ammo/sec, 3 water/sec (takes ~20 seconds for full refill)
3. **Priority**: Critical units (<20%) resupply before low units (<50%)
4. **Cost**: Draws from depot supply reserves (see Supply & Logistics GDD)
5. **Animation**: Soldiers move to depot, grab supplies, return to position

**Auto-resupply does NOT occur when**:
- Squad is in active combat (enemy within 30m)
- Squad is suppressed or pinned
- Supply depot is destroyed or empty
- Squad is routing

#### Manual Resupply (Outside Firebase Influence)

Squads outside firebase influence must receive supplies manually:

1. **Option A: Return to firebase**
   - Squad moves back to firebase radius
   - Auto-resupply triggers
   - Player manually orders squad back to position

2. **Option B: Helicopter resupply**
   - Player orders Huey to deliver supplies to squad position
   - Huey lands (requires clear LZ or hover drop)
   - Supplies transferred to all squads within 15m
   - 30 supply delivered per helicopter trip

3. **Option C: Truck convoy drop-off**
   - Only works on roads or cleared terrain
   - Convoy can be ordered to stop at specific location
   - Squads move to convoy to collect supplies

### 3.5 Empty Resource Behaviors

#### Empty Ammo Behavior

When ammo reaches 0:

1. **Immediate**: Squad stops firing
2. **3-second grace period**: Allow player to notice/react
3. **Auto-retreat trigger**: Squad receives automatic retreat order
4. **Voice callout**: "SQUAD OUT OF SUPPLIES, FALLING BACK!"
5. **Retreat behavior**:
   - Squad seeks nearest safe area (firebase, friendly cluster)
   - Will not engage enemies while retreating for ammo
   - Moves at run speed
   - Will defend if directly attacked (melee/bayonet, minimal damage)
6. **Player override**: Can order squad to hold position (they still cannot shoot)

#### Empty Water Behavior

When water reaches 0:

1. **Combat effectiveness -50%**: Accuracy and damage halved
2. **Severe morale drain**: -1.5 morale/sec continuously
3. **Movement penalty**: -30% move speed
4. **No auto-retreat**: Unlike ammo, water depletion does not trigger auto-retreat
5. **Warning**: "SQUAD DEHYDRATED, NEED WATER!" voice callout
6. **Death risk** (post-MVP): Extended dehydration causes casualties

#### Both Resources Empty

When both ammo AND water are empty:

1. **Resources depleted signal** emitted
2. **Automatic retreat** to nearest firebase
3. **Voice callout**: "WE'RE OUT OF EVERYTHING, FALLING BACK!"
4. **Maximum priority** for resupply when reaching firebase

### 3.6 Visual Indicators

Resource status is communicated through floating icons above units:

| Resource State | Icon | Color | Visibility |
|----------------|------|-------|------------|
| Full (>50%) | None | N/A | No indicator |
| Low (20-50%) | Resource icon | Yellow | Visible when selected |
| Critical (<20%) | Resource icon | Orange | Always visible |
| Empty (0) | Resource icon + X | Red | Always visible + pulsing |

**Icon Specifications**:
- **Ammo icon**: Bullet silhouette
- **Water icon**: Water drop
- **Icons float 2.5m above unit center**
- **Icons face camera (billboard behavior)**
- **Multiple icons stack horizontally**

**Audio Indicators**:
- Low ammo/water: Radio click + status report
- Empty ammo: Full voice callout + retreat order acknowledgment
- Resupply received: "Ammo up!" / "Got water!"

---

## 4. Formulas

### 4.1 Ammo Consumption Per Shot

```gdscript
## Calculate ammo cost for a single attack action
func get_ammo_cost_per_shot(weapon_class: int) -> int:
    match weapon_class:
        GameEnums.WeaponClass.M16, GameEnums.WeaponClass.AK47, GameEnums.WeaponClass.SKS:
            return 1
        GameEnums.WeaponClass.M60, GameEnums.WeaponClass.RPD:
            return 2
        GameEnums.WeaponClass.M2, GameEnums.WeaponClass.DSHK:
            return 3
        GameEnums.WeaponClass.M79:
            return 5
        GameEnums.WeaponClass.MORTAR_60MM, GameEnums.WeaponClass.MORTAR_82MM:
            return 5
        GameEnums.WeaponClass.M72_LAW, GameEnums.WeaponClass.RPG7:
            return 10  # Each LAW/RPG is precious
        _:
            return 1


## Process ammo consumption when firing
func consume_ammo_for_shot(weapon_class: int) -> bool:
    var cost: int = get_ammo_cost_per_shot(weapon_class)

    if current_ammo >= cost:
        current_ammo -= cost
        _check_ammo_status()
        return true  # Shot fired successfully
    else:
        return false  # Cannot fire, out of ammo
```

### 4.2 Water Depletion Per Second

```gdscript
const BASE_WATER_DEPLETION: float = 1.0 / 30.0  # 1 water per 30 seconds

## Calculate water depletion rate based on current activity
func get_water_depletion_rate() -> float:
    var rate: float = BASE_WATER_DEPLETION

    # Activity modifiers
    if state == State.COMBAT:
        rate *= 1.5  # +50% in combat
    elif state == State.MOVING and velocity.length() > move_speed * 0.8:
        rate *= 1.25  # +25% when running

    # Position modifiers
    if is_in_cover:
        rate *= 0.75  # -25% in cover
    if is_garrisoned:
        rate *= 0.5   # -50% in structure

    # Environmental modifiers (post-MVP)
    # if WeatherSystem.is_raining():
    #     rate = 0.0  # Rain collection

    return rate


## Process water depletion (called every frame)
func _process_water_depletion(delta: float) -> void:
    _water_depletion_accumulator += get_water_depletion_rate() * delta

    if _water_depletion_accumulator >= 1.0:
        var amount: int = int(_water_depletion_accumulator)
        current_water = maxi(0, current_water - amount)
        _water_depletion_accumulator -= float(amount)

        _check_water_status()
        water_changed.emit(current_water, max_water)
```

### 4.3 Resource Status Thresholds

```gdscript
const LOW_THRESHOLD: float = 0.5      # 50% - start showing yellow when selected
const CRITICAL_THRESHOLD: float = 0.2  # 20% - always show orange warning
const EMPTY_THRESHOLD: int = 0         # 0 - trigger empty behaviors

enum ResourceStatus { FULL, LOW, CRITICAL, EMPTY }


func get_ammo_status() -> ResourceStatus:
    var percent: float = float(current_ammo) / float(max_ammo)
    if current_ammo == 0:
        return ResourceStatus.EMPTY
    elif percent <= CRITICAL_THRESHOLD:
        return ResourceStatus.CRITICAL
    elif percent <= LOW_THRESHOLD:
        return ResourceStatus.LOW
    else:
        return ResourceStatus.FULL


func get_water_status() -> ResourceStatus:
    var percent: float = float(current_water) / float(max_water)
    if current_water == 0:
        return ResourceStatus.EMPTY
    elif percent <= CRITICAL_THRESHOLD:
        return ResourceStatus.CRITICAL
    elif percent <= LOW_THRESHOLD:
        return ResourceStatus.LOW
    else:
        return ResourceStatus.FULL
```

### 4.4 Auto-Resupply Logic

```gdscript
const RESUPPLY_CHECK_INTERVAL: float = 2.0
const RESUPPLY_RATE_AMMO: float = 5.0  # ammo per second
const RESUPPLY_RATE_WATER: float = 3.0  # water per second
const RESUPPLY_TRIGGER_THRESHOLD: float = 0.9  # Start resupply below 90%

var _resupply_check_timer: float = 0.0


func _process_auto_resupply(delta: float) -> void:
    _resupply_check_timer += delta
    if _resupply_check_timer < RESUPPLY_CHECK_INTERVAL:
        return
    _resupply_check_timer = 0.0

    # Check if eligible for auto-resupply
    if not _can_auto_resupply():
        return

    var depot: Node = _get_nearby_supply_depot()
    if depot == null or depot.current_supply <= 0:
        return

    # Process resupply
    _do_resupply(depot, RESUPPLY_CHECK_INTERVAL)


func _can_auto_resupply() -> bool:
    # Must be in firebase radius
    if not _is_in_firebase_radius():
        return false
    # Cannot resupply during active combat
    if _has_enemies_nearby(30.0):
        return false
    # Cannot resupply while suppressed
    if suppression_state >= GameEnums.SuppressionState.SUPPRESSED:
        return false
    # Cannot resupply while routing
    if state == State.ROUTING:
        return false
    # Must need supplies
    var ammo_percent: float = float(current_ammo) / float(max_ammo)
    var water_percent: float = float(current_water) / float(max_water)
    return ammo_percent < RESUPPLY_TRIGGER_THRESHOLD or water_percent < RESUPPLY_TRIGGER_THRESHOLD


func _do_resupply(depot: Node, delta: float) -> void:
    var supply_used: float = 0.0

    # Resupply ammo
    if current_ammo < max_ammo:
        var ammo_needed: int = max_ammo - current_ammo
        var ammo_rate: int = int(RESUPPLY_RATE_AMMO * delta)
        var ammo_to_add: int = mini(ammo_needed, ammo_rate)
        var ammo_cost: float = ammo_to_add * 0.1  # 10 supply per full ammo refill

        if depot.current_supply >= ammo_cost:
            current_ammo += ammo_to_add
            supply_used += ammo_cost

    # Resupply water
    if current_water < max_water:
        var water_needed: int = max_water - current_water
        var water_rate: int = int(RESUPPLY_RATE_WATER * delta)
        var water_to_add: int = mini(water_needed, water_rate)
        var water_cost: float = water_to_add * 0.05  # 5 supply per full water refill

        if depot.current_supply >= water_cost:
            current_water += water_to_add
            supply_used += water_cost

    # Deduct from depot
    if supply_used > 0:
        depot.consume_supply(supply_used)
        _update_resource_indicators()
```

### 4.5 Empty Ammo Retreat Behavior

```gdscript
const AMMO_EMPTY_GRACE_PERIOD: float = 3.0
var _ammo_empty_timer: float = 0.0


func _check_ammo_status() -> void:
    var status: int = get_ammo_status()

    match status:
        ResourceStatus.LOW:
            if not _is_low_ammo:
                _is_low_ammo = true
                _show_resource_warning("LOW_AMMO")
        ResourceStatus.CRITICAL:
            _is_low_ammo = true
            _show_resource_warning("LOW_AMMO", true)  # Force visible
        ResourceStatus.EMPTY:
            if _ammo_empty_timer <= 0.0:
                _ammo_empty_timer = AMMO_EMPTY_GRACE_PERIOD
        ResourceStatus.FULL:
            _is_low_ammo = false
            _hide_resource_warning("LOW_AMMO")


func _process_ammo_empty_grace(delta: float) -> void:
    if _ammo_empty_timer <= 0.0:
        return

    _ammo_empty_timer -= delta

    if _ammo_empty_timer <= 0.0 and current_ammo == 0:
        _trigger_ammo_retreat()


func _trigger_ammo_retreat() -> void:
    out_of_ammo.emit()
    BattleSignals.unit_out_of_ammo.emit(self)

    # Play voice line
    _play_voice_line("SQUAD_OUT_OF_SUPPLIES_FALLING_BACK")

    # Find nearest safe position
    var retreat_target: Vector3 = _find_nearest_safe_position()

    # Issue retreat order (can be overridden by player)
    if retreat_target != Vector3.ZERO:
        _is_retreat_for_ammo = true
        move_to(retreat_target)
```

### 4.6 Morale Penalty from Dehydration

```gdscript
## Applied in morale update loop (see Morale GDD)
func get_dehydration_morale_penalty() -> float:
    var water_percent: float = float(current_water) / float(max_water)

    if water_percent <= 0.0:
        return -1.5  # Severe: empty water
    elif water_percent <= 0.2:
        return -0.5  # Critical: below 20%
    else:
        return 0.0   # No penalty


## Combat effectiveness modifier from dehydration
func get_dehydration_combat_modifier() -> float:
    if current_water == 0:
        return 0.5  # 50% effectiveness when empty
    else:
        return 1.0  # Full effectiveness otherwise
```

---

## 5. Edge Cases

### 5.1 Resupply During Combat

**Scenario**: Squad is within firebase radius but enemies are attacking.

**Behavior**:
- Auto-resupply is **disabled** while enemies are within 30m
- Squad continues to deplete resources fighting
- If ammo empties, squad will attempt retreat even during combat
- Player can order manual hold position to fight to last round

**Rationale**: Prevents unrealistic "infinite ammo near depot" exploit while maintaining logistics pressure.

### 5.2 Simultaneous Multi-Resource Depletion

**Scenario**: Squad runs out of both ammo and water at approximately the same time.

**Behavior**:
- `resources_depleted` signal emitted (single signal, not two)
- Ammo depletion takes precedence for retreat trigger
- Voice line: "WE'RE OUT OF EVERYTHING, FALLING BACK!" (not two separate callouts)
- Squad retreats with maximum urgency (run speed, no engagement)

### 5.3 Supply Depot Destroyed While Resupplying

**Scenario**: Squad is in the middle of resupply when depot is destroyed by mortar.

**Behavior**:
- Resupply immediately halts at current resource levels
- Squad receives whatever supplies were transferred before destruction
- No "refund" of supply already consumed from depot
- Squad must find another depot or receive helicopter resupply

### 5.4 Helicopter Resupply to Contested LZ

**Scenario**: Player orders helicopter resupply but enemies are near the drop zone.

**Behavior**:
- Helicopter pilot announces "LZ is hot!"
- Helicopter still attempts delivery (historical accuracy - dustoffs landed in hot LZs)
- Helicopter takes fire while hovering (damage applied)
- Supplies dropped even if helicopter is hit
- If helicopter destroyed before drop: supplies lost

### 5.5 VC/NVA Resource Tracking

**Scenario**: AI-controlled enemies also have resource systems.

**Behavior**:
- VC/NVA units track ammo and water internally
- When VC unit empties ammo, it retreats toward tunnel entrance or map edge
- VC Porters carry supplies and can resupply VC units
- Destroying VC weapon caches prevents VC resupply
- Player cannot see enemy resource levels (no indicators visible)

### 5.6 Vehicle Resource Tracking

**Scenario**: Tanks and helicopters use different resource model.

**Behavior**:
- Vehicles track ammo only (crew has internal water supply)
- M48 Patton: 80 ammo (main gun + MG combined)
- Huey: 50 ammo (door gunner rounds)
- Vehicles do not auto-retreat when empty (crew stays with vehicle)
- Vehicles can be manually ordered to retreat for resupply
- Voice line: "Main gun empty, need resupply!"

### 5.7 Garrisoned Unit Resupply

**Scenario**: Squad garrisoned in bunker runs low on supplies.

**Behavior**:
- Garrisoned units still auto-resupply if within firebase radius
- One soldier leaves garrison briefly to collect supplies
- Garrison defense slightly weakened during resupply
- If bunker outside firebase radius: no auto-resupply
- Squad must exit garrison to receive helicopter drop

### 5.8 Patrol Route Resource Management

**Scenario**: Squad on standing patrol order runs low on resources.

**Behavior**:
- Patrol behavior monitors resource levels
- At LOW (50%), patrol route shifts to pass near depot
- At CRITICAL (20%), patrol automatically returns to firebase
- Standing order resumes after resupply
- Voice line: "Patrol returning for resupply."

---

## 6. Dependencies

| System | Dependency Type | Interaction |
|--------|-----------------|-------------|
| **Supply & Logistics** | Required | Depot supply draws, convoy delivery, helicopter resupply |
| **Firebase System** | Required | Influence radius determines auto-resupply eligibility |
| **Morale & Routing** | Required | Water depletion affects morale; empty resources affect routing |
| **Combat System** | Required | Firing consumes ammo; combat state affects depletion rates |
| **Helicopter System** | Required | Emergency resupply delivery |
| **AI Director** | Consumer | AI attacks may target units with low resources |
| **Audio Manager** | Consumer | Voice lines for resource warnings |
| **UI System** | Consumer | Resource indicators, status icons |
| **Veterancy System** | Optional | Veteran units may have slightly better resource efficiency |

### Dependency Flow Diagram

```
Combat System                  Firebase System
     │                               │
     │ (fires weapon)               │ (influence radius)
     ▼                               ▼
┌─────────────────────────────────────────┐
│          Unit Resource System           │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐ │
│  │  Ammo   │  │  Water  │  │ Morale  │ │
│  └────┬────┘  └────┬────┘  └────┬────┘ │
└───────┼────────────┼────────────┼──────┘
        │            │            │
        ▼            ▼            ▼
  ┌──────────┐  ┌──────────┐  ┌──────────┐
  │ Auto-    │  │ Morale   │  │ Routing  │
  │ Retreat  │  │ Penalty  │  │ Behavior │
  └──────────┘  └──────────┘  └──────────┘
        │            │            │
        └────────────┴────────────┘
                     │
                     ▼
           Supply & Logistics
           (depot draws, resupply)
```

---

## 7. Tuning Knobs

| Parameter | Default | Range | Gameplay Effect |
|-----------|---------|-------|-----------------|
| `ammo_per_shot_rifle` | 1 | 1-3 | Higher = more logistics pressure, shorter engagements |
| `ammo_per_shot_lmg` | 2 | 1-5 | Higher = LMGs need more frequent resupply |
| `ammo_per_shot_hmg` | 3 | 2-8 | Higher = heavy weapons become logistics-expensive |
| `water_depletion_base` | 1/30 sec | 1/20 - 1/60 | Higher = more frequent water resupply needed |
| `water_combat_multiplier` | 1.5 | 1.0-2.0 | Higher = combat drains water faster |
| `low_threshold` | 0.5 | 0.3-0.6 | When "LOW" warnings appear |
| `critical_threshold` | 0.2 | 0.1-0.3 | When urgent warnings and morale penalties apply |
| `auto_resupply_rate_ammo` | 5/sec | 2-10 | Higher = faster resupply, less time at depot |
| `auto_resupply_rate_water` | 3/sec | 1-6 | Higher = faster water resupply |
| `ammo_retreat_grace_period` | 3.0 sec | 1.0-5.0 | Time before auto-retreat after emptying ammo |
| `dehydration_morale_penalty_low` | -0.5/sec | -0.2 to -1.0 | Morale drain when water critical |
| `dehydration_morale_penalty_empty` | -1.5/sec | -1.0 to -3.0 | Severe drain when dehydrated |
| `dehydration_combat_modifier` | 0.5 | 0.3-0.7 | Combat effectiveness when dehydrated |
| `resupply_check_interval` | 2.0 sec | 0.5-5.0 | How often units check for resupply eligibility |
| `combat_resupply_block_range` | 30m | 15-50 | Enemies closer than this block auto-resupply |

### Balance Targets

| Scenario | Target Outcome |
|----------|----------------|
| Full squad in sustained firefight | Ammo lasts 3-5 minutes |
| Squad at rest | Water lasts 50 minutes |
| Squad in combat | Water lasts 30 minutes |
| Full resupply from empty | ~20 seconds at depot |
| Time from LOW to EMPTY (ammo, firing) | 45-90 seconds |
| Time from CRITICAL water to routing | 3-4 minutes (via morale) |

---

## 8. Acceptance Criteria

### Core Resource Tracking

- [ ] Squads track current and maximum ammo
- [ ] Squads track current and maximum water
- [ ] Ammo decrements when firing, proportional to weapon type
- [ ] Water decrements passively over time
- [ ] Water depletion rate increases during combat and movement

### Status Display

- [ ] Resource icons appear above units at LOW threshold
- [ ] Icons change color at CRITICAL threshold (yellow to orange)
- [ ] Icons pulse and show "X" when EMPTY
- [ ] Multiple resource warnings stack horizontally
- [ ] Icons are only visible when selected (for LOW), always visible (for CRITICAL/EMPTY)

### Auto-Resupply

- [ ] Units within firebase influence radius auto-resupply
- [ ] Resupply draws from local supply depot
- [ ] Resupply stops when enemies are nearby
- [ ] Resupply stops when suppressed
- [ ] Units at CRITICAL priority receive supplies before LOW units

### Empty Resource Behaviors

- [ ] Empty ammo triggers 3-second grace period
- [ ] After grace period, squad auto-retreats toward nearest firebase
- [ ] Voice callout plays: "SQUAD OUT OF SUPPLIES, FALLING BACK"
- [ ] Player can override retreat with hold position order
- [ ] Squad cannot fire while at zero ammo

### Water/Morale Integration

- [ ] Low water (<20%) applies -0.5/sec morale penalty
- [ ] Empty water applies -1.5/sec morale penalty
- [ ] Empty water reduces combat effectiveness by 50%
- [ ] Receiving resupply grants +3 morale bonus

### Manual Resupply

- [ ] Helicopter can be ordered to deliver supplies to specific location
- [ ] Supplies transfer to all units within 15m of drop point
- [ ] Truck convoys can be stopped for manual pickup
- [ ] Units outside firebase radius cannot auto-resupply

### Audio Feedback

- [ ] Voice lines play for LOW resource warnings
- [ ] Voice lines play for EMPTY resource retreat
- [ ] Voice lines play when resupply received
- [ ] Voice lines are distinct for ammo vs water

### Unit Type Variations

- [ ] Rifle Squad: 100 ammo, 100 water
- [ ] Weapons Squad: 150 ammo, 100 water
- [ ] Engineer Squad: 40 ammo, 100 water
- [ ] Recon Team: 60 ammo, 80 water
- [ ] Vehicles track ammo only

### Edge Case Handling

- [ ] Depot destruction mid-resupply halts transfer immediately
- [ ] Simultaneous depletion triggers single unified retreat
- [ ] Garrisoned units can still resupply (one soldier exits briefly)
- [ ] Patrol orders auto-adjust when resources are low
- [ ] VC/NVA units retreat when resources empty (toward tunnels)

---

## Historical Context

Resource management was a constant reality in Vietnam operations:

- **Ammunition expenditure**: Infantry squads carried ~200-300 rounds per rifleman; heavy contact could deplete this in 30-60 minutes
- **Water discipline**: Soldiers carried 2-4 canteens; dehydration was a constant threat in tropical heat
- **Firebase resupply**: Combat bases were resupplied daily by helicopter; isolated firebases faced critical shortages
- **Tactical retreats**: Units genuinely withdrew when ammunition ran low - fighting to the last round was rare outside defensive positions
- **"Ammo up!"**: Standard call when resupply arrived; soldiers would break cover to grab ammunition crates during lulls

The system reflects the historical reality that logistics constraints, not just enemy action, determined operational capability in Vietnam.

---

## Implementation Notes

### Existing Code Integration

The `battle_system/nodes/squad.gd` already contains:
- `current_ammo`, `max_ammo` variables
- `current_water`, `max_water` variables
- `_water_depletion_timer` and basic depletion logic
- `out_of_ammo`, `water_changed`, `water_critical` signals
- `_is_low_water`, `_is_low_ammo` status flags
- `_resupply_check_timer` for auto-resupply timing

**To complete implementation**:
1. Add weapon-specific ammo costs to firing logic
2. Implement auto-retreat behavior when ammo empty
3. Connect water depletion to morale system
4. Add visual indicator system (floating icons)
5. Implement depot resupply draw logic
6. Add voice line triggers
7. Implement unit type-specific reserve capacities via VietnamUnitData

### Signal Bus Integration

Add to `BattleSignals`:
```gdscript
signal unit_low_ammo(unit: Node3D)
signal unit_low_water(unit: Node3D)
signal unit_out_of_ammo(unit: Node3D)
signal unit_dehydrated(unit: Node3D)
signal unit_resupplied(unit: Node3D, resource_type: int)
```

### Resource Constants

Create `battle_system/data/resource_constants.gd`:
```gdscript
class_name ResourceConstants

const LOW_THRESHOLD := 0.5
const CRITICAL_THRESHOLD := 0.2
const AMMO_EMPTY_GRACE_PERIOD := 3.0
const WATER_BASE_DEPLETION := 1.0 / 30.0
const RESUPPLY_RATE_AMMO := 5.0
const RESUPPLY_RATE_WATER := 3.0
const COMBAT_RESUPPLY_BLOCK_RANGE := 30.0

# Unit reserve capacities (unit_type -> {ammo, water})
const RESERVE_CAPACITIES := {
    GameEnums.UnitType.RIFLE_PLATOON: {"ammo": 100, "water": 100},
    GameEnums.UnitType.WEAPONS_SQUAD: {"ammo": 150, "water": 100},
    GameEnums.UnitType.ENGINEERS: {"ammo": 40, "water": 100},
    GameEnums.UnitType.SOG_TEAM: {"ammo": 60, "water": 80},
    # ... etc
}
```
