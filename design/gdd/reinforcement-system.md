# Reinforcement System GDD

> **Status**: `[LIVING]`
> **Last Updated**: 2026-05-21
> **Source Documents**: GAME_BIBLE.md D-101, D-901, PRD.md, CLAUDE.md
> **Pillar**: 4 (Doctrine Over Spam)

---

## 1. Overview

The reinforcement system is the primary mechanism for acquiring new units during a mission. Unlike traditional RTS games with barracks and rally points, RealVietnamRTS uses a physical delivery system where reinforcements arrive via convoy or helicopter from off-map staging areas. Units take minutes to arrive, not seconds. Losing a tank means waiting 12 minutes for a replacement. This system is the mechanical heart of Pillar 4: Doctrine Over Spam.

**Core Principle**: Force preservation matters more than force production because reinforcements are slow, expensive, and vulnerable to interception.

**Reference Games**:
- **Warno/Steel Division**: Phased reinforcement availability, deck-limited unit counts
- **Broken Arrow**: Realistic reinforcement timing, combined arms arrival
- **Company of Heroes**: Reinforcement points and timing costs

---

## 2. Player Fantasy

You are a battalion commander managing a finite force. Before the mission, you committed to a doctrine that determines what units you can request. Now, watching the firebase perimeter take fire, you must decide: do you call in a rifle squad by helicopter (fast but limited capacity) or wait for the convoy bringing your armor (slow but heavy firepower)?

Every reinforcement request is a commitment. The helicopter carrying your squad is visible, audible, and vulnerable. The convoy crawling up the jungle road can be ambushed. When your M48 Patton finally rolls into the firebase after a 12-minute wait, you feel relief and responsibility - lose that tank, and you will not get another one quickly.

The enemy knows this too. VC sappers target your LZs. Ambushes hit your convoys. The race is not to build faster, but to preserve what you have while your reinforcements are in transit.

---

## 3. Detailed Rules

### 3.1 Reinforcement Request Flow

```
[Player Request] -> [Validation] -> [Queueing] -> [Dispatch] -> [Transit] -> [Arrival]

1. PLAYER REQUEST
   - Player selects unit type from doctrine-available roster
   - Selects destination (firebase LZ or road endpoint)
   - System validates: pool availability, supply cost, destination validity

2. VALIDATION CHECKS
   - Is unit type available in current doctrine?
   - Does unit pool have available count?
   - Does player have sufficient supply?
   - Is destination valid (LZ operational, road connected)?
   - Is delivery method available (helicopters not all destroyed, road not cut)?

3. QUEUEING
   - Request enters pending queue
   - Priority sorting: EMERGENCY > HIGH > NORMAL > LOW
   - Max concurrent deliveries: 3 (configurable)

4. DISPATCH
   - Unit deducted from off-map pool
   - Delivery vehicle spawns (helicopter at airstrip, convoy at rear depot)
   - ETA calculated based on distance and doctrine modifiers

5. TRANSIT
   - Physical delivery: helicopter flies path, convoy drives road
   - Vulnerable to interception (AA fire, ambush)
   - Player can track delivery on minimap

6. ARRIVAL
   - Units spawn at destination
   - Automatically assigned to firebase garrison
   - Signal emitted for UI/audio feedback
```

### 3.2 Delivery Methods

#### Helicopter Delivery (Primary US Method)

| Aspect | Value | Notes |
|--------|-------|-------|
| Speed | 150 km/h (41.67 m/s) | Direct flight path |
| Capacity | 1 squad OR 30 supply per trip | Infantry only, no vehicles |
| Availability | Requires operational helipad/LZ | LZ can be hot (under fire) |
| Vulnerability | Medium - AA fire, weather | Can be shot down |
| Base time | 30-60 seconds transit + 30s landing | Distance dependent |

**Helicopter Reinforcement Process**:
1. Huey spawns at rear airstrip/staging area
2. Loads requested unit (hidden until arrival)
3. Flies direct path to destination LZ
4. Landing sequence (30 seconds)
5. Unit disembarks and becomes active
6. Huey returns to staging area

**Hot LZ Risks**:
- Enemy fire during landing
- Door gunners engage automatically
- Increased crash risk (5% base, +2% per AA unit in range)
- Faster unloading (15 seconds combat urgency)

#### Convoy Delivery (Ground Transport)

| Aspect | Value | Notes |
|--------|-------|-------|
| Speed | 30 km/h on roads | Road-bound only |
| Capacity | 3-5 trucks, 100 supply each OR 3 squads | Can carry vehicles |
| Availability | Requires connected road network | Road must not be cut |
| Vulnerability | High - ambush, IED, blocked road | Very vulnerable |
| Base time | 2-5 minutes typical | Road distance dependent |

**Convoy Composition**:
- Standard convoy: 3x M35 trucks + 1 escort vehicle (if armor doctrine)
- Armor convoy: Transporter carrying M48 + 2x escort trucks
- Mixed convoy: Combination based on request queue

**Convoy Behavior**:
1. Spawns at rear depot with requested units loaded
2. Follows road network (A* pathfinding on road graph)
3. Stops if road is blocked/cratered (waits for repair or reroutes)
4. Vulnerable to ambush along entire route
5. Survivors continue to destination if ambushed
6. Units disembark at firebase road entrance

### 3.3 Unit Pool and Availability

Units are drawn from an off-map pool that represents the battalion's available reserves.

| Unit Type | Starting Pool | Max Pool | Replenishment |
|-----------|---------------|----------|---------------|
| Rifle Squad | 10 | 15 | +1 every 10 min |
| Engineer Squad | 3 | 5 | +1 every 15 min |
| Weapons Squad | 4 | 6 | +1 every 12 min |
| Recon Team | 2 | 4 | +1 every 15 min |
| M48 Patton | 2 | 3 | +1 every 30 min |
| Huey Transport | 3 | 4 | +1 every 20 min |

**Pool Rules**:
- Initial pool set by mission parameters
- Units lost are NOT automatically replaced
- Pool replenishment is slow (simulates division-level logistics)
- Some missions may have no replenishment (isolated firebase scenario)

### 3.4 Reinforcement Timing (Critical Balance Variable)

**Base Reinforcement Times** (from GAME_BIBLE D-101, D-901):

| Unit Type | Base Time | Air Cav Doctrine | Mechanized Doctrine |
|-----------|-----------|------------------|---------------------|
| Rifle Squad | 3 min (180s) | 2.4 min (144s) | 3 min (180s) |
| Engineer Squad | 4 min (240s) | 3.2 min (192s) | 4 min (240s) |
| Weapons Squad | 5 min (300s) | 4 min (240s) | 5 min (300s) |
| Recon Team | 3 min (180s) | 2.4 min (144s) | 3 min (180s) |
| M48 Patton | 12 min (720s) | N/A (not available) | 9 min (540s) |
| Huey Transport | 6 min (360s) | 4.8 min (288s) | 10 min (600s) |

**Timing Components**:
```
Total Time = Base Time * Doctrine Modifier * Delivery Modifier * Priority Modifier + Transit Time

Where:
- Base Time: Unit's inherent reinforcement time
- Doctrine Modifier: 0.8 (Air Cav heli), 0.75 (Mech convoy), 1.0 (default)
- Delivery Modifier: 0.8 (helicopter), 1.0 (convoy)
- Priority Modifier: 0.5 (Emergency), 0.7 (High), 1.0 (Normal), 1.3 (Low)
- Transit Time: Actual travel time based on distance
```

### 3.5 Doctrine Modifiers

| Doctrine | Helicopter Modifier | Convoy Modifier | Special |
|----------|--------------------|--------------------|---------|
| Air Cavalry | 0.8 (20% faster) | 1.0 | Start with 2 Hueys |
| Mechanized | 1.25 (25% slower) | 0.75 (25% faster) | Start with 1 M48 |
| Airborne | 1.0 | 1.0 | Paradrop option available |

### 3.6 Supply Costs

Reinforcements consume supply when they arrive (not when requested):

| Unit Type | Supply Cost | Notes |
|-----------|-------------|-------|
| Rifle Squad | 25 supply | Standard infantry |
| Engineer Squad | 35 supply | Equipment-heavy |
| Weapons Squad | 40 supply | Heavy weapons |
| Recon Team | 15 supply | Light footprint |
| M48 Patton | 100 supply | Fuel and ammo hungry |
| Huey Transport | 50 supply | Aviation fuel |

**Supply Validation**:
- Request is accepted even if firebase lacks supply
- Arrival fails if firebase supply is insufficient at arrival time
- Failed arrival: unit waits at staging area, request re-queued

### 3.7 VC/NVA Reinforcement (Asymmetric)

VC and NVA do not use the same reinforcement system:

| Faction | Spawn Source | Method | Notes |
|---------|--------------|--------|-------|
| VC | Tunnel entrances | Instant spawn | Limited by tunnel network |
| VC | Map edges | Infiltration | Slow, stealthy |
| NVA | Map edges | Conventional march | Wave-based, AI-directed |

VC reinforcement is handled by the AI Director, not the player-facing reinforcement system.

---

## 4. Formulas

### 4.1 Reinforcement Time Calculation

```gdscript
const BASE_TIMES: Dictionary = {
    GameEnums.UnitType.RIFLE_SQUAD: 180.0,      # 3 min
    GameEnums.UnitType.ENGINEER_SQUAD: 240.0,   # 4 min
    GameEnums.UnitType.WEAPONS_SQUAD: 300.0,    # 5 min
    GameEnums.UnitType.RECON_TEAM: 180.0,       # 3 min
    GameEnums.UnitType.M48_PATTON: 720.0,       # 12 min
    GameEnums.UnitType.HUEY_TRANSPORT: 360.0,   # 6 min
}

func calculate_reinforcement_time(
    unit_type: int,
    doctrine: Doctrine,
    delivery_method: int,
    priority: int,
    distance: float
) -> float:
    var base_time: float = BASE_TIMES.get(unit_type, 300.0)

    # Doctrine modifier
    var doctrine_modifier: float = 1.0
    if delivery_method == DeliveryMethod.HELICOPTER:
        doctrine_modifier = doctrine.helicopter_time_modifier  # e.g., 0.8 for Air Cav
    elif delivery_method == DeliveryMethod.CONVOY:
        doctrine_modifier = doctrine.convoy_time_modifier  # e.g., 0.75 for Mech

    # Delivery method modifier
    var delivery_modifier: float = 1.0
    match delivery_method:
        DeliveryMethod.HELICOPTER:
            delivery_modifier = 0.8  # Helicopters are faster
        DeliveryMethod.CONVOY:
            delivery_modifier = 1.0  # Ground is baseline

    # Priority modifier
    var priority_modifier: float = _get_priority_modifier(priority)

    # Transit time (physical travel)
    var transit_time: float = _calculate_transit_time(delivery_method, distance)

    # Final calculation
    var prep_time: float = base_time * doctrine_modifier * delivery_modifier * priority_modifier
    return prep_time + transit_time


func _get_priority_modifier(priority: int) -> float:
    match priority:
        RequestPriority.EMERGENCY:
            return 0.5   # 50% of normal time
        RequestPriority.HIGH:
            return 0.7   # 70% of normal time
        RequestPriority.NORMAL:
            return 1.0   # Normal time
        RequestPriority.LOW:
            return 1.3   # 130% of normal time
    return 1.0


func _calculate_transit_time(delivery_method: int, distance: float) -> float:
    match delivery_method:
        DeliveryMethod.HELICOPTER:
            const HELI_SPEED := 41.67  # m/s (150 km/h)
            const LANDING_TIME := 30.0
            return (distance / HELI_SPEED) + LANDING_TIME
        DeliveryMethod.CONVOY:
            const CONVOY_SPEED := 8.33  # m/s (30 km/h)
            const LOADING_TIME := 60.0
            return (distance / CONVOY_SPEED) + LOADING_TIME
    return 0.0
```

### 4.2 Convoy Ambush Damage Calculation

```gdscript
const AMBUSH_BASE_DAMAGE := 0.3  # 30% chance per truck to be destroyed
const ESCORT_PROTECTION := 0.5   # Escort reduces damage by 50%

func calculate_ambush_outcome(convoy: Convoy, ambush: AmbushEvent) -> AmbushResult:
    var result := AmbushResult.new()
    var protection_modifier: float = 1.0

    # Escort vehicle protection
    if convoy.has_escort:
        protection_modifier *= ESCORT_PROTECTION
        # Escort engages ambushers
        result.escort_engaged = true
        result.ambushers_killed = _calculate_escort_kills(convoy.escort_type, ambush.attacker_count)

    # Calculate losses per truck
    for truck in convoy.trucks:
        var destroy_chance: float = AMBUSH_BASE_DAMAGE * protection_modifier * ambush.intensity
        if randf() < destroy_chance:
            result.trucks_destroyed.append(truck)
            # Units/supply in truck are lost
            result.units_lost.append_array(truck.loaded_units)
            result.supply_lost += truck.loaded_supply
        else:
            result.trucks_survived.append(truck)

    # Surviving trucks continue to destination
    result.convoy_continues = not result.trucks_survived.is_empty()

    return result


class AmbushResult:
    var trucks_destroyed: Array[ConvoyTruck] = []
    var trucks_survived: Array[ConvoyTruck] = []
    var units_lost: Array[Node3D] = []
    var supply_lost: float = 0.0
    var escort_engaged: bool = false
    var ambushers_killed: int = 0
    var convoy_continues: bool = true
```

### 4.3 Emergency Reinforcement Request

```gdscript
const EMERGENCY_COOLDOWN := 300.0  # 5 minutes between emergency requests
const EMERGENCY_SUPPLY_MULTIPLIER := 2.0  # Costs double supply

var _last_emergency_time: float = -EMERGENCY_COOLDOWN

func request_emergency_reinforcement(
    unit_type: int,
    destination: Node3D
) -> ReinforcementRequest:
    var current_time: float = Time.get_ticks_msec() / 1000.0

    # Check cooldown
    if current_time - _last_emergency_time < EMERGENCY_COOLDOWN:
        push_warning("Emergency reinforcement on cooldown")
        return null

    # Emergency always uses fastest method
    var method: int = DeliveryMethod.HELICOPTER
    if not _has_available_helicopter():
        method = DeliveryMethod.CONVOY

    var request := ReinforcementRequest.new()
    request.unit_type = unit_type
    request.count = 1
    request.destination = destination
    request.delivery_method = method
    request.priority = RequestPriority.EMERGENCY
    request.supply_cost = _get_supply_cost(unit_type) * EMERGENCY_SUPPLY_MULTIPLIER

    _last_emergency_time = current_time
    pending_requests.push_front(request)  # Emergency goes to front

    return request
```

### 4.4 Pool Replenishment

```gdscript
const REPLENISHMENT_RATES: Dictionary = {
    GameEnums.UnitType.RIFLE_SQUAD: 600.0,      # +1 every 10 min
    GameEnums.UnitType.ENGINEER_SQUAD: 900.0,   # +1 every 15 min
    GameEnums.UnitType.WEAPONS_SQUAD: 720.0,    # +1 every 12 min
    GameEnums.UnitType.RECON_TEAM: 900.0,       # +1 every 15 min
    GameEnums.UnitType.M48_PATTON: 1800.0,      # +1 every 30 min
    GameEnums.UnitType.HUEY_TRANSPORT: 1200.0,  # +1 every 20 min
}

var _replenishment_timers: Dictionary = {}

func _process_replenishment(delta: float) -> void:
    if not _replenishment_enabled:
        return

    for unit_type in REPLENISHMENT_RATES:
        if unit_type not in _replenishment_timers:
            _replenishment_timers[unit_type] = 0.0

        _replenishment_timers[unit_type] += delta

        var rate: float = REPLENISHMENT_RATES[unit_type]
        if _replenishment_timers[unit_type] >= rate:
            _replenishment_timers[unit_type] -= rate
            var max_pool: int = _get_max_pool(unit_type)
            if unit_pool.get(unit_type, 0) < max_pool:
                unit_pool[unit_type] = unit_pool.get(unit_type, 0) + 1
                BattleSignals.pool_replenished.emit(unit_type, unit_pool[unit_type])
```

### 4.5 Helicopter Shoot-Down Probability

```gdscript
const BASE_SHOOTDOWN_CHANCE := 0.02  # 2% base per AA unit in range
const ALTITUDE_MODIFIER_LOW := 1.0   # Full vulnerability at low altitude
const ALTITUDE_MODIFIER_HIGH := 0.3  # 30% vulnerability at high altitude
const ESCORT_PROTECTION := 0.5       # Gunship escort halves risk

func calculate_shootdown_chance(
    helicopter: Helicopter,
    flight_path: Array[Vector3]
) -> float:
    var total_chance: float = 0.0

    for waypoint in flight_path:
        var aa_units: Array[Node3D] = _get_aa_units_in_range(waypoint, AA_DETECTION_RANGE)

        for aa in aa_units:
            var base_chance: float = BASE_SHOOTDOWN_CHANCE * aa.effectiveness

            # Altitude modifier
            var alt_mod: float = ALTITUDE_MODIFIER_LOW if helicopter.altitude < 100.0 else ALTITUDE_MODIFIER_HIGH

            # Escort modifier
            var escort_mod: float = ESCORT_PROTECTION if helicopter.has_escort else 1.0

            total_chance += base_chance * alt_mod * escort_mod

    return clampf(total_chance, 0.0, 0.95)  # Cap at 95%
```

---

## 5. Edge Cases

### 5.1 Convoy Ambush During Transit

**Scenario**: VC ambush a supply convoy carrying reinforcements.

**What Happens**:
1. Convoy enters ambush zone (VC units within 50m of road)
2. Ambush event triggers
3. Convoy stops, escort (if any) engages
4. Damage calculated per truck
5. Destroyed trucks: units inside are KIA, supply lost
6. Surviving trucks: pause 30 seconds (combat), then continue
7. If all trucks destroyed: request fails, partial refund to pool (50%)
8. Player receives notification: "Convoy ambushed - X trucks lost"

**Player Recourse**:
- Send gunship escort (if Air Cav doctrine)
- Clear ambush zone with patrols before convoy
- Use helicopter delivery for critical reinforcements
- Repair/clear alternate road

### 5.2 LZ Destroyed While Helicopter En Route

**Scenario**: Helipad/LZ is destroyed while helicopter is in flight.

**What Happens**:
1. Helicopter receives LZ destruction signal
2. Helicopter searches for alternate LZ within 500m
3. If alternate found: diverts to alternate LZ
4. If no alternate: helicopter returns to staging area with units
5. Request status changes to "PENDING_LZ" - units not lost
6. Player must designate new LZ or repair original
7. Once LZ available, helicopter re-dispatches

**Player Notification**: "Inbound Huey diverted - LZ Charlie destroyed"

### 5.3 Road Cut After Convoy Dispatch

**Scenario**: Road is cratered/blocked after convoy has departed.

**What Happens**:
1. Convoy pathfinding recalculates when road state changes
2. If alternate route exists: convoy reroutes (adds time)
3. If no alternate route: convoy stops at blockage
4. Convoy waits up to 5 minutes for repair
5. If still blocked: convoy returns to staging area
6. Request status: "BLOCKED" - units returned to pool

**Player Notification**: "Convoy route blocked - awaiting road repair"

### 5.4 Insufficient Supply at Arrival

**Scenario**: Firebase lacks supply when reinforcements arrive.

**What Happens**:
1. Reinforcements arrive at destination
2. System checks: `firebase.supply >= request.supply_cost`
3. If insufficient: units offload but are "out of supply" state
4. Out of supply units: 50% combat effectiveness, cannot build
5. Units auto-resupply when supply is restored
6. No units are lost - they just arrive degraded

**Player Notification**: "Reinforcements arrived at Firebase Alpha - LOW SUPPLY"

### 5.5 All Helicopters Destroyed

**Scenario**: Player has lost all transport helicopters.

**What Happens**:
1. Helicopter requests automatically convert to convoy
2. Infantry-only convoy dispatched
3. Reinforcement time significantly increased
4. Player can request helicopter reinforcement (6-minute wait for new Huey)
5. Air Cav doctrine: critical warning - "Aviation assets depleted"

**System Behavior**:
```gdscript
func _select_delivery_method(request: ReinforcementRequest) -> int:
    var preferred: int = request.delivery_method

    if preferred == DeliveryMethod.HELICOPTER:
        if not _has_available_helicopter():
            push_warning("No helicopters available - falling back to convoy")
            return DeliveryMethod.CONVOY

    if preferred == DeliveryMethod.CONVOY:
        if not _has_connected_road(request.destination):
            if _has_available_helicopter():
                push_warning("Road cut - falling back to helicopter")
                return DeliveryMethod.HELICOPTER
            else:
                return DeliveryMethod.NONE  # Request fails

    return preferred
```

### 5.6 Emergency Request on Cooldown

**Scenario**: Player requests emergency reinforcement while cooldown is active.

**What Happens**:
1. Request is rejected immediately
2. Player sees: "Emergency reinforcement on cooldown (X:XX remaining)"
3. Player can submit normal-priority request instead
4. Cooldown UI shows remaining time
5. No penalty for attempted request

### 5.7 Multiple Concurrent Requests Exceed Limit

**Scenario**: Player requests 4th reinforcement when max concurrent is 3.

**What Happens**:
1. Request is accepted and queued
2. Request enters pending queue (not active)
3. Pending requests sorted by priority
4. When active delivery completes, next pending dispatches
5. Player sees queue position in UI

**Queue Behavior**:
- EMERGENCY requests always process next
- HIGH requests jump ahead of NORMAL
- NORMAL requests in FIFO order
- LOW requests only process when no higher priority waiting

### 5.8 Request Cancellation

**Scenario**: Player cancels reinforcement request.

**What Happens**:
- **If pending (not dispatched)**: Full refund to pool, no cost
- **If en route (helicopter)**: No refund, helicopter returns empty
- **If en route (convoy)**: No refund, convoy returns to depot
- Supply cost is NOT refunded once dispatched

---

## 6. Dependencies

| System | Dependency Type | Integration Notes |
|--------|-----------------|-------------------|
| **Doctrine System** | Required (upstream) | Determines available units, time modifiers |
| **Supply Logistics** | Required (consumer) | Supply cost deducted at arrival |
| **Helicopter System** | Required (delivery) | Helicopter insertion missions |
| **Firebase System** | Required (destination) | LZs, road endpoints, supply depots |
| **Road Network** | Required (convoy) | Pathfinding for convoys |
| **AI Director** | Consumer | Monitors reinforcement timing for difficulty |
| **BattleSignals** | Required (events) | Reinforcement arrived/failed signals |
| **Selection Manager** | Consumer | New units auto-selected on arrival |
| **HUD** | Consumer | Displays reinforcement queue, ETA, pool |

**Bidirectional Dependencies**:
- Helicopter System notifies Reinforcement System of helicopter availability
- Supply Logistics notifies Reinforcement System of firebase supply levels
- Doctrine System provides unit roster and modifiers
- Reinforcement System emits signals consumed by UI, AI, and campaign

---

## 7. Tuning Knobs

| Parameter | Default | Range | Affects | Notes |
|-----------|---------|-------|---------|-------|
| `base_infantry_time` | 180s (3 min) | 120s-300s | Infantry arrival pace | Primary balance lever |
| `base_armor_time` | 720s (12 min) | 480s-900s | Armor scarcity | Higher = more precious |
| `base_helicopter_time` | 360s (6 min) | 240s-480s | Air asset availability | |
| `air_cav_heli_modifier` | 0.8 | 0.7-0.9 | Air Cav doctrine value | Lower = stronger Air Cav |
| `mech_convoy_modifier` | 0.75 | 0.7-0.85 | Mech doctrine value | Lower = stronger Mech |
| `max_concurrent_deliveries` | 3 | 2-5 | Reinforcement throughput | Higher = easier game |
| `emergency_cooldown` | 300s (5 min) | 180s-600s | Emergency spam prevention | |
| `emergency_time_modifier` | 0.5 | 0.3-0.7 | Emergency speed | Lower = faster emergency |
| `emergency_supply_multiplier` | 2.0 | 1.5-3.0 | Emergency cost | Higher = more expensive |
| `convoy_ambush_base_damage` | 0.3 | 0.1-0.5 | Convoy vulnerability | Higher = more dangerous roads |
| `helicopter_shootdown_base` | 0.02 | 0.01-0.05 | AA effectiveness | Per AA unit in range |
| `pool_replenish_infantry` | 600s (10 min) | 300s-900s | Long-term sustainability | 0 = no replenishment |
| `pool_replenish_armor` | 1800s (30 min) | 1200s-2400s | Armor scarcity | |
| `supply_cost_infantry` | 25 | 15-40 | Supply pressure | Higher = more logistics focus |
| `supply_cost_armor` | 100 | 50-150 | Armor supply footprint | |

**Balance Philosophy**:
- Reinforcement timing is THE most important balance variable (per GAME_BIBLE D-901)
- Too fast: game becomes AOE-style spam fest (violates Pillar 4)
- Too slow: player feels helpless, can not recover from losses
- Sweet spot: player can recover but must plan ahead and preserve forces

---

## 8. Acceptance Criteria

### Core Functionality

- [ ] Player can request reinforcements from doctrine-available roster
- [ ] Reinforcements arrive via helicopter or convoy (physical delivery)
- [ ] Reinforcement timing matches doctrine modifiers (Air Cav 20% faster heli)
- [ ] Unit pool decrements on dispatch, not on arrival
- [ ] Supply cost deducted at arrival, not at request
- [ ] Max concurrent deliveries enforced (3 default)
- [ ] Priority queue correctly sorts EMERGENCY > HIGH > NORMAL > LOW

### Delivery Methods

- [ ] Helicopters fly from staging area to destination LZ
- [ ] Convoys drive road network from rear depot to firebase
- [ ] Helicopter delivery takes 30s landing time
- [ ] Convoy delivery takes loading time + road travel time
- [ ] Helicopter falls back to convoy if no helicopters available
- [ ] Convoy fails if no connected road

### Doctrine Integration

- [ ] Air Cavalry: helicopter reinforcements 20% faster
- [ ] Mechanized: convoy reinforcements 25% faster
- [ ] Unit roster filtered by doctrine (no M48 for Air Cav)
- [ ] Starting pool set by doctrine + mission parameters

### Combat Integration

- [ ] Convoys can be ambushed by VC units near road
- [ ] Ambushed trucks can be destroyed (units/supply lost)
- [ ] Helicopters can be shot down by AA
- [ ] Lost delivery vehicle: units KIA, partial pool refund (50%)

### Emergency System

- [ ] Emergency requests process with 50% time modifier
- [ ] Emergency requests cost 2x supply
- [ ] Emergency cooldown prevents spam (5 min default)
- [ ] Emergency requests jump to front of queue

### UI/UX

- [ ] HUD shows reinforcement queue with ETA for each request
- [ ] HUD shows unit pool counts by type
- [ ] Minimap shows convoy/helicopter positions during transit
- [ ] Audio cue when reinforcements arrive
- [ ] Warning notification when delivery fails/intercepted

### Edge Case Handling

- [ ] LZ destroyed mid-flight: helicopter diverts or returns
- [ ] Road cut mid-transit: convoy reroutes or returns
- [ ] Pool empty: request rejected with clear message
- [ ] Supply insufficient: units arrive but degraded
- [ ] All helicopters lost: automatic convoy fallback

### Performance

- [ ] Reinforcement calculations complete within 1ms
- [ ] Convoy pathfinding uses cached road graph
- [ ] No per-frame allocations in delivery tracking
- [ ] Supports 10+ concurrent reinforcement requests without lag

---

## Historical Context

The reinforcement system reflects the logistical realities of Vietnam operations:

**Helicopter Resupply**: The UH-1 Huey was the workhorse of Vietnam, with the 1st Cavalry Division maintaining 428 organic helicopters. A firebase could receive reinforcements within 30-60 minutes via air, but helicopters were vulnerable to ground fire and weather.

**Convoy Operations**: Ground convoys were the primary resupply method but highly vulnerable. The VC specifically targeted convoys, leading to armed escort requirements. Convoy ambushes like the one at Mang Yang Pass (1954) remained a constant threat.

**Force Preservation**: Unlike WWII, US forces in Vietnam could not easily replace casualties. The "body count" metric reflected this - every soldier lost was a political and logistical cost. This reality is reflected in the slow reinforcement timing and finite unit pools.

**Doctrine Differences**: Air Cavalry emphasized helicopter mobility (1st Cav), while Mechanized Infantry used armored vehicles and road-bound operations (25th Infantry Division). These historical doctrines inform the gameplay doctrines.
