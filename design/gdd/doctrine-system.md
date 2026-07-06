# Doctrine System GDD

> **Status**: `[LIVING]`
> **Last Updated**: 2026-05-21
> **Source Documents**: GAME_BIBLE.md Section 13, PRD.md Section 13
> **Pillar**: 4 (Doctrine Over Spam)

---

## 1. Overview

The doctrine system implements pre-mission force composition choices that lock the player into a specific playstyle. Each doctrine determines which unit types are available, which buildings can be constructed, and reinforcement timing modifiers. This is not Age of Empires - you don't build units from barracks. You commit to a force structure before the mission starts, and reinforcements arrive over minutes via convoy or helicopter.

---

## 2. Player Fantasy

Before each mission, you study the map and choose your doctrine. Air Cavalry for rapid deployment and vertical envelopment. Mechanized for heavy firepower and armor protection. Airborne for elite infantry and artillery support. Your choice shapes every aspect of the mission - what units arrive, how fast they come, what buildings you can construct. There's no "right" choice, only the choice that fits your plan.

---

## 3. Detailed Rules

### 3.1 How Doctrines Work

1. **Pre-mission**: Player selects doctrine from available options
2. **Doctrine determines**:
   - Which unit types are available for reinforcement
   - Which buildings can be constructed
   - Reinforcement timing modifiers
   - Starting units (some doctrines start with specific assets)
   - Special abilities

### 3.2 Historical Background

The US Army in Vietnam used the **ROAD** (Reorganization Objective Army Division) structure established in 1962. Divisions had a common "division base" with specialized internal organization depending on type: Infantry, Mechanized Infantry, Armored, Airborne, and Airmobile.

---

## 4. US Doctrines

### 4.1 Air Cavalry (Primary MVP Doctrine)

*Based on: 1st Cavalry Division (Airmobile), 101st Airborne Division (Airmobile after 1968)*

**Historical Context:**
The 1st Cavalry Division (Airmobile) was created July 1, 1965, from the experimental 11th Air Assault Division. It deployed to Vietnam with **428 organic helicopters**. First saw combat at the Battle of Ia Drang (1965).

**Gameplay Identity:**
| Aspect | Description |
|--------|-------------|
| Strength | Rapid deployment, vertical envelopment, quick reaction force |
| Weakness | Limited heavy armor, dependent on helicopter availability, vulnerable LZs |
| Playstyle | Mobile defense, rapid firebase establishment, helicopter-borne assault |

**Unit Roster:**

| Unit | Historical Basis | Role | Reinforcement Time |
|------|------------------|------|-------------------|
| Rifle Squad (10) | 1/7 Cavalry standard | General infantry, M16/M60/M79 | 3 min |
| Weapons Squad (8) | Battalion weapons platoon | M2 .50cal or 81mm mortar | 5 min |
| Recon Team (4-6) | LRRP teams | Stealth scouting, extended sight | 3 min |
| Engineer Squad (8) | Division engineers | Construction, det-cord clearing | 4 min |
| UH-1D Huey Transport | 227th/229th Aviation Battalions | Troop lift (1 squad), supply delivery | 6 min |
| UH-1B/C Huey Gunship | Air Cavalry Squadron | Fire support, escort | 8 min |
| OH-6 Cayuse (Scout) | Air Cavalry Squadron | Reconnaissance, target marking | 5 min |

**Building Unlocks:**
- Helipad (required, start with 2)
- PSP Helipad (reinforced)
- All standard firebase buildings

**Special Modifiers:**
- Helicopter reinforcements arrive **20% faster**
- Start with 2 UH-1D Hueys
- Can request emergency extraction (cooldown ability)

---

### 4.2 Mechanized Infantry

*Based on: 25th Infantry Division, 1st Infantry Division mechanized battalions*

**Historical Context:**
The 25th Infantry Division ("Tropic Lightning") served in Vietnam 1966-1971 from Cu Chi Base Camp. Included mechanized battalions like 4th Battalion (Mechanized), 23rd Infantry. Supported by 1st Battalion, 69th Armor with M48A3 Patton tanks.

**Gameplay Identity:**
| Aspect | Description |
|--------|-------------|
| Strength | Heavy firepower, armor protection, road dominance |
| Weakness | Road-dependent, slow through jungle, large logistical footprint |
| Playstyle | Methodical advance, convoy operations, firebase defense with armor |

**Unit Roster:**

| Unit | Historical Basis | Role | Reinforcement Time |
|------|------------------|------|-------------------|
| Rifle Squad (10) | Standard infantry | General infantry | 3 min |
| Mechanized Squad (10) | 4/23 Infantry (Mech) | Infantry in M113 APC | 5 min |
| Weapons Squad (8) | Battalion weapons platoon | Heavy weapons | 5 min |
| Engineer Squad (8) | Division engineers | Construction, mine clearing | 4 min |
| M48A3 Patton | 1/69 Armor | Main battle tank, 90mm gun | 12 min |
| M113 APC | Mechanized battalions | Troop transport, .50cal mount | 8 min |
| M35 "Deuce-and-a-half" | Division logistics | Supply convoy | 4 min |
| UH-1D Huey (limited) | Division aviation | Emergency resupply only | 10 min |

**Building Unlocks:**
- Tank Revetment (required)
- Vehicle Depot
- All standard firebase buildings
- Helipad (limited to 1)

**Special Modifiers:**
- Ground convoy reinforcements arrive **25% faster**
- Start with 1 M48A3 Patton
- Road construction is **15% faster**

---

### 4.3 Airborne Infantry

*Based on: 173rd Airborne Brigade, 101st Airborne Division (pre-1968)*

**Historical Context:**
The 173rd Airborne Brigade ("Sky Soldiers") was the first major US Army ground unit deployed to Vietnam (May 1965). Famous for the Battle of Hamburger Hill (1969).

**Gameplay Identity:**
| Aspect | Description |
|--------|-------------|
| Strength | Elite infantry, high morale, versatile light forces |
| Weakness | No armor, limited heavy weapons, infantry-dependent |
| Playstyle | Aggressive patrolling, infantry-focused defense, ambush tactics |

**Unit Roster:**

| Unit | Historical Basis | Role | Reinforcement Time |
|------|------------------|------|-------------------|
| Airborne Rifle Squad (10) | 173rd/101st standard | Elite infantry (+morale bonus) | 3 min |
| Airborne Weapons Squad (8) | Battalion weapons | 81mm mortar, M60 MG | 5 min |
| Pathfinder Team (4) | Division pathfinders | LZ marking, recon, +accuracy | 4 min |
| Engineer Squad (8) | Airborne engineers | Light construction | 4 min |
| 105mm Howitzer | DIVARTY | Artillery support | 15 min |
| UH-1D Huey | Division aviation | Transport, limited | 6 min |

**Building Unlocks:**
- Artillery Pit (105mm)
- All standard firebase buildings
- Helipad (standard allocation)

**Special Modifiers:**
- Infantry squads have **+10% starting morale**
- Reinforcement by **paradrop** available (fast but risky)
- Pathfinder teams can mark LZs faster

---

### 4.4 Marine Expeditionary (Post-MVP)

*Based on: III Marine Amphibious Force (III MAF)*

**Historical Context:**
III MAF activated May 1965 at Da Nang. Peak strength: 85,500 Marines (September 1968). Unique Combined Action Platoon program integrated Marines with Vietnamese Popular Forces.

**Gameplay Identity:**
- Combined arms integration
- Naval gunfire support
- Amphibious capability
- Coastal operations

*(Detailed roster: Post-MVP)*

---

## 5. VC/NVA Doctrines

### 5.1 VC Local Force

*Regional/Provincial units*

**Historical Context:**
Local Force units were organized at provincial level. They "blended into the civilian population by day and became effective fighters at night."

**Gameplay Identity:**
| Aspect | Description |
|--------|-------------|
| Strength | Tunnels, local knowledge, night operations, attrition |
| Weakness | Light weapons, no armor, limited sustained combat |
| Playstyle | Ambush, harassment, sapper raids, tunnel networks |

**Unit Roster:**

| Unit | Size | Role | Spawn Source |
|------|------|------|--------------|
| VC Infantry Squad | 9-12 | Light infantry, AK-47/SKS | Tunnel/map edge |
| VC Sapper Cell | 3-6 | Infiltration, demolition | Tunnel |
| VC Mortar Team | 3-4 | 60mm mortar, hit-and-run | Tunnel |
| VC Recon Cell | 3 | Intelligence, target marking | Map edge |
| VC Porter Team | 4-6 | Supply movement, non-combat | Map edge |

**Structure Unlocks:**
- Tunnel Entrance (spawn point, hidden)
- Spider Hole (single-soldier ambush)
- Weapon Cache (finite resupply)
- Punji Trap (damage trap)

**Special Abilities:**
- **Night attack bonus**: +25% effectiveness after dark
- **Tunnel network spawn**: Units appear from hidden tunnels
- **Village sympathy**: Can stage from neutral villages

---

### 5.2 VC/NVA Main Force

*PLAF Main Force and NVA Regulars*

**Historical Context:**
Main Force units were organized into battalions and regiments. Battalion strength averaged 425-600 personnel. Equipped with heavier weapons: 12.7mm AA MGs, 82mm mortars, 75mm recoilless rifles.

**Gameplay Identity:**
| Aspect | Description |
|--------|-------------|
| Strength | Coordinated assaults, heavy weapons, conventional tactics |
| Weakness | Logistics-dependent, vulnerable to air power, less stealth |
| Playstyle | Massed infantry assault, siege tactics, conventional defense |

**Unit Roster:**

| Unit | Size | Role |
|------|------|------|
| NVA Infantry Squad | 10-12 | Regular infantry, AK-47 |
| NVA Weapons Squad | 8 | RPD LMG, RPG-7 |
| NVA Mortar Team | 4 | 82mm mortar |
| NVA Recoilless Rifle Team | 3 | 75mm RR, anti-armor |
| NVA Sapper Squad | 6-8 | Elite infiltrators |
| 12.7mm DShK AA Team | 3 | Anti-aircraft, anti-helicopter |

**Structure Unlocks:**
- Fortified bunker complex
- AA emplacement
- Mortar pit
- Tunnel network (main force variant)

**Special Abilities:**
- **Human wave assault**: Mass attack with morale bonus
- **Siege tactics**: Sustained pressure
- **Trail resupply**: Ho Chi Minh Trail logistics

---

## 6. Formulas

### 6.1 Reinforcement Time Calculation

```gdscript
func calculate_reinforcement_time(unit_type: UnitType, doctrine: Doctrine) -> float:
    var base_time := unit_type.base_reinforcement_time
    var doctrine_modifier := doctrine.get_modifier_for_unit(unit_type)
    var delivery_method_modifier := 1.0

    if unit_type.arrives_by == DeliveryMethod.HELICOPTER:
        delivery_method_modifier = doctrine.helicopter_modifier
    elif unit_type.arrives_by == DeliveryMethod.CONVOY:
        delivery_method_modifier = doctrine.convoy_modifier

    return base_time * doctrine_modifier * delivery_method_modifier
```

### 6.2 Doctrine Selection Validation

```gdscript
func can_request_unit(unit_type: UnitType) -> bool:
    return current_doctrine.available_units.has(unit_type)

func can_build_structure(building_type: BuildingType) -> bool:
    return current_doctrine.available_buildings.has(building_type)
```

---

## 7. Tuning Knobs

| Parameter | Default | Range | Notes |
|-----------|---------|-------|-------|
| `base_infantry_reinf_time` | 3 min | 2-5 min | Rifle squad arrival time |
| `base_armor_reinf_time` | 12 min | 8-15 min | Tank arrival time |
| `air_cav_heli_modifier` | 0.8 | 0.7-0.9 | 20% faster helicopters |
| `mech_convoy_modifier` | 0.75 | 0.7-0.85 | 25% faster convoys |
| `airborne_morale_bonus` | 0.1 | 0.05-0.15 | +10% starting morale |

---

## 8. Acceptance Criteria

### Core Functionality
- [ ] Player selects doctrine before mission starts
- [ ] Doctrine determines available unit types
- [ ] Doctrine determines available building types
- [ ] Reinforcement timing modified by doctrine

### Unit Availability
- [ ] Air Cavalry has full helicopter roster, limited armor
- [ ] Mechanized has full armor roster, limited helicopters
- [ ] Airborne has elite infantry, artillery support

### Building Restrictions
- [ ] Tank Revetment only available to Mechanized
- [ ] Multiple helipads available to Air Cavalry
- [ ] Artillery Pit available to Airborne

### Special Modifiers
- [ ] Air Cavalry helicopters arrive 20% faster
- [ ] Mechanized convoys arrive 25% faster
- [ ] Airborne infantry has +10% starting morale

### UI Requirements
- [ ] Pre-mission doctrine selection screen
- [ ] Doctrine description shows strengths/weaknesses
- [ ] Unit roster preview for selected doctrine
- [ ] Building availability preview

---

## Unit Organization Reference

**US Rifle Squad (Vietnam Era):**
- 10 soldiers total
- Squad Leader (E-6)
- 2 Fire Teams (Alpha: 4 men, Bravo: 5 men)
- Weapons per squad: 8x M16, 1x M60 LMG, 1x M79 grenade launcher

**US Rifle Platoon:**
- Platoon HQ (4)
- 3 Rifle Squads (10 each)
- 1 Weapons Squad
- Total: ~40 soldiers

**VC/NVA Company:**
- Company HQ (25)
- Heavy Weapons Platoon (40): 3x 60mm mortars, 3x MMG
- 3 Rifle Platoons (35 each)
- Total: ~170 soldiers
