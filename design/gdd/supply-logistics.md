# Supply & Logistics System GDD

> **Status**: `[LIVING]`
> **Last Updated**: 2026-05-21
> **Source Documents**: GAME_BIBLE.md Section 9, PRD.md Section 9
> **Pillar**: 3 (Physical Supply Chains)

---

## 1. Overview

Supply in RealVietnamRTS is spatial, not abstract. Trucks drive on roads, helicopters fly between LZs, and every supply shipment can be intercepted. Cut a road, crater a runway, ambush a convoy - supply chains exist in the world and they can be attacked. A firebase isolated from supply is a firebase that dies slowly as ammo runs dry and water depletes.

---

## 2. Player Fantasy

You watch your supply network as a living system. Trucks snake along jungle roads you carved. Hueys shuttle supplies to forward LZs. When the VC ambush your convoy, you feel it immediately - that firebase's supply icon turns yellow, then red. You scramble helicopters for emergency resupply while engineers repair the road. Supply is not a number in a corner; it's trucks on roads that your enemy is hunting.

---

## 3. Detailed Rules

### 3.1 Supply Sources

| Source | Type | Capacity | Notes |
|--------|------|----------|-------|
| Rear Depot | Fixed map feature | Infinite | Starting supply point |
| Captured Airstrip | Fixed map feature | Infinite (when operational) | Enables fixed-wing, can be cratered |
| Supply Depot (building) | Constructed | 500 supply | Stores and distributes locally |

### 3.2 Supply Movement Methods

| Method | Capacity | Speed | Vulnerability | When to Use |
|--------|----------|-------|---------------|-------------|
| Truck Convoy | 100 supply/truck | Road-dependent (~30 km/h) | High - ambush vulnerable | Steady resupply to road-connected bases |
| Helicopter | 30 supply/trip | Fast, direct (~150 km/h) | Medium - limited by weather/AA | Emergency resupply, isolated positions |

### 3.3 Supply Flow Rules

1. **Automatic within network**: If a road connects firebases, supply flows automatically
2. **Truck convoys**: Spawn at rear depot, follow roads, deliver to firebase depot, return
3. **Helicopter resupply**: Player-dispatched or automated for isolated/emergency positions
4. **Supply depots**: Store supply locally, distribute to units within firebase influence radius

### 3.4 Supply Consumption

| Activity | Supply Cost | Notes |
|----------|-------------|-------|
| Squad ammo resupply (full) | 10 supply | From depot to squad |
| Squad water resupply (full) | 5 supply | From depot to squad |
| Building construction | Varies | See Construction System GDD |
| Reinforcement arrival | Varies | See Reinforcement System GDD |
| Mortar fire (per round) | 2 supply | Indirect fire consumes supply |
| Artillery fire (per round) | 5 supply | Heavy indirect fire |

### 3.5 Road Network

Roads are the arteries of your supply network:
- **Cleared roads**: Cut by bulldozers through jungle
- **Road speed**: 100% movement speed for vehicles
- **Road vulnerability**: Can be cratered by mortars, IEDs, sappers
- **Road repair**: Engineers can repair cratered roads

### 3.6 Convoy Behavior

Truck convoys operate semi-autonomously:
1. Spawn at rear depot when firebase supply falls below threshold
2. Follow road network to destination firebase
3. Deliver supply to local depot
4. Return to rear depot for reload
5. Repeat cycle

**Convoy Composition (MVP)**:
- 3 M35 "Deuce-and-a-half" trucks
- Optional: 1 escort vehicle (if available)

### 3.7 Helicopter Resupply

Helicopter supply missions:
1. Player orders resupply mission to target LZ
2. Huey loads supply at airstrip/rear LZ (30 supply)
3. Flies direct route to target LZ
4. Delivers supply to local depot
5. Returns to origin

**Automatic helicopter resupply**: Triggered when firebase supply is critical (<20%) and road is cut.

---

## 4. Formulas

### 4.1 Convoy Spawn Threshold

```
# Spawn convoy when firebase supply drops below threshold
CONVOY_SPAWN_THRESHOLD = 0.5  # 50% of depot capacity

if firebase.supply_depot.current < firebase.supply_depot.max * CONVOY_SPAWN_THRESHOLD:
    if not convoy_en_route_to(firebase):
        spawn_convoy(rear_depot, firebase)
```

### 4.2 Supply Distribution Rate

```
SUPPLY_DISTRIBUTION_RATE = 5.0  # supply/second

for unit in firebase.units_in_radius():
    if unit.needs_supply():
        transfer = min(
            unit.supply_needed(),
            firebase.supply_depot.current,
            SUPPLY_DISTRIBUTION_RATE * delta
        )
        unit.add_supply(transfer)
        firebase.supply_depot.remove(transfer)
```

### 4.3 Convoy Travel Time

```
# Calculate ETA for supply convoy
road_distance = calculate_road_distance(origin, destination)
convoy_speed = 30.0  # km/h on roads
travel_time_hours = road_distance / convoy_speed
travel_time_minutes = travel_time_hours * 60
```

### 4.4 Supply Consumption Rate

```
# Per-squad consumption rates
AMMO_PER_SHOT = 1.0
WATER_PER_SECOND = 1.0 / 30.0  # 1 water every 30 seconds

# Aggregate consumption
firebase_consumption_rate = sum(squad.consumption_rate for squad in firebase.squads)
time_until_empty = firebase.supply_depot.current / firebase_consumption_rate
```

---

## 5. Edge Cases

### 5.1 Road Cut
- If all roads to firebase are cut (cratered/blocked), convoy cannot reach
- Firebase begins depleting local supply only
- Helicopter resupply becomes only option
- Automatic helicopter resupply triggers at critical supply levels

### 5.2 Convoy Ambush
- VC can ambush convoys on roads
- Destroyed trucks = supply lost
- Surviving trucks continue to destination
- Escort vehicles engage attackers

### 5.3 Supply Depot Destruction
- Destroyed depot cannot store or distribute supply
- Units in radius must resupply manually (move to another depot)
- Ammo depot explosion causes area damage (secondary explosions)
- Fuel depot fire spreads to nearby structures

### 5.4 Helicopter Loss
- Huey shot down = supply lost
- Replacement helicopter must be requested as reinforcement
- Loss of all helicopters forces road-only supply

### 5.5 Isolated Firebase
- Firebase with no road AND no LZ = no resupply possible
- Units slowly deplete reserves
- Must clear/build LZ or road to restore supply

### 5.6 Supply Overflow
- If depot is full, convoy waits or returns
- Helicopter hovers until space available (burns fuel)
- Excess supply from reinforcements is lost

---

## 6. Dependencies

| System | Dependency Type | Notes |
|--------|-----------------|-------|
| **Firebase System** | Required | Depots within firebase radius |
| **Construction System** | Required | Building supply depots, roads |
| **Terrain Clearing** | Required | Roads require cleared terrain |
| **Helicopter System** | Required | Helicopter resupply missions |
| **Unit Resources** | Consumer | Units consume ammo, water |
| **Reinforcement System** | Consumer | Reinforcements require supply |
| **Combat System** | Consumer | Combat consumes ammo |

---

## 7. Tuning Knobs

| Parameter | Default | Range | Notes |
|-----------|---------|-------|-------|
| `supply_depot_capacity` | 500 | 300-1000 | Local storage limit |
| `convoy_capacity` | 100/truck | 50-150 | Per-truck capacity |
| `convoy_spawn_threshold` | 0.5 | 0.3-0.7 | % depot capacity triggers convoy |
| `convoy_speed` | 30 km/h | 20-40 | Road travel speed |
| `helicopter_capacity` | 30 | 20-50 | Per-trip supply |
| `supply_distribution_rate` | 5/sec | 2-10 | Depot to unit transfer |
| `ammo_resupply_cost` | 10 | 5-20 | Full squad ammo refill |
| `water_resupply_cost` | 5 | 2-10 | Full squad water refill |
| `critical_supply_threshold` | 0.2 | 0.1-0.3 | Triggers emergency resupply |

---

## 8. Acceptance Criteria

### Core Functionality
- [ ] Truck convoys spawn automatically when firebase supply is low
- [ ] Convoys follow road network from rear depot to firebase
- [ ] Helicopters can deliver supply to any LZ
- [ ] Supply depots store and distribute supply within influence radius
- [ ] Units auto-resupply when inside firebase influence radius

### Visual Feedback
- [ ] Convoy trucks visible on roads during transit
- [ ] Helicopters visible during supply missions
- [ ] Supply depot shows current/max capacity
- [ ] Firebase shows supply status icon (green/yellow/red)
- [ ] Low supply warning notification

### Road Network
- [ ] Convoys only travel on cleared roads
- [ ] Cratered roads block convoy passage
- [ ] Engineers can repair cratered roads
- [ ] Road visualization shows network connectivity

### Combat Integration
- [ ] Convoys can be ambushed by VC
- [ ] Destroyed trucks drop/lose supply
- [ ] Supply depot explosion causes secondary damage
- [ ] Cut supply lines affect firebase combat effectiveness

### Emergency Resupply
- [ ] Helicopter resupply triggers automatically at critical levels
- [ ] Player can manually order helicopter resupply
- [ ] Isolated firebases show warning indicators

---

## Supply Chain Visualization

```
[Rear Depot]          [Airstrip]
     │                     │
     │ (Truck)             │ (Helicopter)
     ▼                     ▼
[Road Network] ─────► [Firebase LZ]
     │                     │
     │                     │
     ▼                     ▼
[Firebase A] ◄───────► [Firebase B]
     │                     │
     │ (Influence         │ (Influence
     │  Radius)            │  Radius)
     ▼                     ▼
 [Squads]               [Squads]
```

---

## Historical Context

In Vietnam, firebase resupply was a constant challenge:
- **Road Convoys**: Primary resupply method but highly vulnerable to ambush
- **Helicopter Resupply**: Critical for isolated positions, limited by weather and enemy AA
- **Firebase Isolation**: Khe Sanh (1968) was nearly cut off, requiring massive aerial resupply
- **Supply Vulnerabilities**: VC specifically targeted supply convoys and depots
