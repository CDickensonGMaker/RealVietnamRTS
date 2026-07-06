# Helicopter System GDD

> **Status**: `[LIVING]`
> **Last Updated**: 2026-05-21
> **Source Documents**: GAME_BIBLE.md, PRD.md, CLAUDE.md
> **Pillar**: 3 (Physical Supply Chains), 4 (Doctrine Over Spam)

---

## 1. Overview

The helicopter system handles all rotary-wing aviation operations: troop transport, supply delivery, medevac, reconnaissance, and fire support. Helicopters are the signature capability of the Air Cavalry doctrine, providing rapid deployment and vertical envelopment. Unlike instant-teleportation mechanics, helicopters fly real paths, take real time, and can be shot down - making them valuable but vulnerable assets.

---

## 2. Player Fantasy

The distinctive thump of Huey rotors means cavalry is coming. You watch your slicks insert a rifle squad into a hot LZ, door gunners blazing. A gunship makes a rocket run on the treeline. Your supply Huey delivers emergency ammo to a firebase under siege. When you lose a helicopter, you feel it - that's a 6-minute reinforcement wait before you get another.

---

## 3. Detailed Rules

### 3.1 Helicopter Types

| Type | Model | Role | Capacity | Speed | Armament |
|------|-------|------|----------|-------|----------|
| **Transport** | UH-1D | Troop lift, supply | 1 squad OR 30 supply | 150 km/h | 2x M60 door guns |
| **Gunship** | UH-1B/C | Fire support | None | 140 km/h | Rockets, miniguns |
| **Scout** | OH-6 Cayuse | Recon, marking | 2 crew | 180 km/h | Minigun (light) |

### 3.2 Landing Zones (LZs)

Helicopters require LZs to land:

| LZ Type | Size | Source | Notes |
|---------|------|--------|-------|
| **Helipad** | 15m x 15m | Constructed | Permanent, safe landing |
| **PSP Helipad** | 15m x 15m | Constructed | Reinforced, heavy use |
| **Prepared LZ** | 20m x 20m | Engineer cleared | Jungle clearing |
| **Hot LZ** | 20m x 20m | Improvised | Under fire, risky |

### 3.3 Mission Types

**Troop Transport**
1. Player orders squad embarkation at origin LZ
2. Helicopter loads squad
3. Player designates destination LZ
4. Helicopter flies to destination
5. Squad disembarks
6. Helicopter returns to base or awaits orders

**Supply Delivery**
1. Helicopter loads supply at depot/airstrip
2. Flies to firebase LZ
3. Delivers supply to local depot
4. Returns to origin

**Fire Support (Gunship)**
1. Player calls gunship to target area
2. Gunship makes attack run
3. Fires rockets/miniguns
4. Exits and returns to base
5. Cooldown before next run

**Reconnaissance (Scout)**
1. Scout helicopter orbits designated area
2. Reveals fog of war
3. Marks enemy positions
4. Can be shot down if low

**Medevac (Post-MVP)**
1. Wounded squads call medevac
2. Medical helicopter extracts wounded
3. Returns to medical station
4. Soldiers return to duty faster

### 3.4 Flight Mechanics

| Parameter | Value | Notes |
|-----------|-------|-------|
| Cruising speed | 150 km/h | Standard transit speed |
| Landing/takeoff | 30 seconds | Total hover time |
| Fuel range | ~20 minutes | Must refuel at airstrip |
| Altitude | Low (50m) or High (200m) | Player/auto choice |
| Vulnerability | Low = AA threat, High = reduced effectiveness | Tradeoff |

### 3.5 Escort Mechanics

Gunships can escort transport helicopters:
- Gunship flies formation with transport
- Engages enemies at destination LZ
- Suppresses ground fire during landing
- Increases transport survival

---

## 4. Formulas

### 4.1 Flight Time Calculation

```gdscript
const HELICOPTER_SPEED := 150.0  # km/h = 41.67 m/s

func calculate_flight_time(origin: Vector3, destination: Vector3) -> float:
    var distance := origin.distance_to(destination)
    var flight_time := distance / (HELICOPTER_SPEED * 1000.0 / 3600.0)  # Convert km/h to m/s
    var landing_time := 30.0  # Seconds for landing/takeoff
    return flight_time + landing_time
```

### 4.2 AA Threat Calculation

```gdscript
func calculate_aa_threat(flight_path: Array[Vector3], altitude: float) -> float:
    var threat := 0.0
    for waypoint in flight_path:
        var aa_units := get_aa_units_in_range(waypoint, AA_RANGE)
        for aa in aa_units:
            var effectiveness := 1.0 if altitude < 100.0 else 0.3
            threat += aa.threat_value * effectiveness
    return threat
```

### 4.3 Gunship Attack Run

```gdscript
const ROCKET_DAMAGE := 100.0
const ROCKET_COUNT := 14  # Per pod
const MINIGUN_DPS := 50.0

func execute_attack_run(target_area: Vector3, duration: float) -> void:
    # Rockets on approach
    var rockets_fired := min(ROCKET_COUNT, int(duration * 2))
    for i in rockets_fired:
        spawn_rocket(target_area + random_spread(10.0))

    # Minigun during pass
    var minigun_damage := MINIGUN_DPS * duration
    apply_suppression(target_area, 50.0, minigun_damage)
```

---

## 5. Edge Cases

### 5.1 Hot LZ (Under Fire)
- Helicopter takes damage during landing
- Door gunners engage targets automatically
- Increased crash risk
- Faster unloading (combat urgency)

### 5.2 Helicopter Shot Down
- All passengers killed
- Supply lost
- Reinforcement timer starts for replacement
- Crash site visible (no recovery mechanics in MVP)

### 5.3 LZ Blocked
- If LZ is occupied or destroyed, helicopter cannot land
- Helicopter hovers awaiting orders
- Burns fuel while waiting
- Player must designate alternate LZ

### 5.4 Fuel Depletion
- Helicopter with low fuel returns to airstrip automatically
- If airstrip is lost, helicopter searches for nearest safe LZ
- Crash if no landing possible

### 5.5 Weather Impact
- Bad weather grounds helicopters (see Weather System)
- Heavy rain: 50% effectiveness
- Monsoon storm: GROUNDED
- Fog: Limited visibility, risky operations

### 5.6 Night Operations
- Reduced accuracy for gunships
- Scout less effective
- Transport still functional
- VC AA more effective at night

---

## 6. Dependencies

| System | Dependency Type | Notes |
|--------|-----------------|-------|
| **Firebase System** | Required | LZs within firebase radius |
| **Supply Logistics** | Required | Helicopter resupply missions |
| **Reinforcement System** | Required | Helicopter insertion |
| **Construction System** | Required | Building helipads |
| **Combat System** | Required | Door guns, gunship weapons |
| **Weather System** | Optional | Weather affects operations |

---

## 7. Tuning Knobs

| Parameter | Default | Range | Notes |
|-----------|---------|-------|-------|
| `helicopter_speed` | 150 km/h | 100-200 | Flight speed |
| `transport_capacity` | 1 squad | 1-2 | Troops per flight |
| `supply_capacity` | 30 | 20-50 | Supply per flight |
| `landing_time` | 30 sec | 20-45 | Land/takeoff duration |
| `gunship_cooldown` | 90 sec | 60-120 | Between attack runs |
| `fuel_duration` | 20 min | 15-30 | Flight time before refuel |
| `aa_damage_multiplier` | 1.0 | 0.5-2.0 | AA effectiveness |
| `escort_survival_bonus` | 0.5 | 0.3-0.7 | Reduced damage with escort |

---

## 8. Acceptance Criteria

### Core Functionality
- [ ] Helicopters fly from origin to destination in real time
- [ ] Transport helicopters carry 1 squad or supply
- [ ] Gunships can attack ground targets
- [ ] Scouts reveal fog of war in designated area

### LZ System
- [ ] Helicopters require LZ to land
- [ ] Helipads can be constructed
- [ ] Engineers can prepare LZ in jungle
- [ ] Hot LZ mechanics (under fire landing)

### Flight Mechanics
- [ ] Helicopters have realistic flight speed
- [ ] Landing and takeoff take time
- [ ] Helicopters have fuel limits
- [ ] High vs low altitude affects vulnerability

### Combat Integration
- [ ] Door gunners engage during landing
- [ ] Gunship attack runs deal damage
- [ ] Helicopters can be shot down
- [ ] Lost helicopters require reinforcement

### Visual/Audio
- [ ] Distinctive Huey rotor sound
- [ ] Helicopter models visible in flight
- [ ] Rocket and minigun visual effects
- [ ] Landing dust kick-up

---

## Helicopter Reference

### UH-1D "Huey" (Transport)
- **Historical**: Primary troop transport of Vietnam War
- **Capacity**: 1 squad (10 soldiers) or supply
- **Crew**: 2 pilots, 2 door gunners
- **Speed**: 205 km/h max (reduced for gameplay)
- **Armament**: 2x M60 7.62mm door guns

### UH-1B/C "Huey" (Gunship)
- **Historical**: Armed variant for fire support
- **Armament**:
  - 2.75" rocket pods (14 rockets each)
  - M60 door guns or miniguns
  - Some variants: 40mm grenade launcher
- **Role**: Attack, escort, suppression

### OH-6 "Cayuse" (Scout)
- **Historical**: Light observation helicopter
- **Speed**: 241 km/h (fastest of the three)
- **Role**: Reconnaissance, target marking
- **Armament**: M134 minigun (light)
- **Crew**: 2 (pilot, observer)
