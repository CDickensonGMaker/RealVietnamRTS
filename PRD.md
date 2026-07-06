# RealVietnamRTS — Product Requirements Document

**Status:** `[LIVING]` — This is the authoritative design document
**Last updated:** 2026-05-20
**Working title:** RealVietnamRTS (final title TBD)

> This document supersedes GAME_BIBLE.md for design decisions. Read this before every session.

---

## Table of Contents

1. [Product Overview](#1-product-overview)
2. [Target Audience](#2-target-audience)
3. [Core Design Philosophy](#3-core-design-philosophy)
4. [The Six Pillars](#4-the-six-pillars)
5. [Core Gameplay Loop](#5-core-gameplay-loop)
6. [Unit Resource System](#6-unit-resource-system)
7. [Morale & Routing System](#7-morale--routing-system)
8. [Firebase System](#8-firebase-system)
9. [Supply & Logistics](#9-supply--logistics)
10. [Construction System](#10-construction-system)
11. [Combat System](#11-combat-system)
12. [AI Director](#12-ai-director)
13. [Doctrine System](#13-doctrine-system)
14. [Campaign Structure](#14-campaign-structure)
15. [Save System](#15-save-system)
16. [Skirmish Mode](#16-skirmish-mode)
17. [Day/Night & Weather](#17-daynight--weather)
18. [UI/UX Requirements](#18-uiux-requirements)
19. [Audio Direction](#19-audio-direction)
20. [Technical Requirements](#20-technical-requirements)
21. [MVP Scope](#21-mvp-scope)
22. [Post-MVP Roadmap](#22-post-mvp-roadmap)
23. [Open Questions & Research Needed](#23-open-questions--research-needed)
24. [Decision Log](#24-decision-log)

---

# PART I — PRODUCT DEFINITION

## 1. Product Overview

### 1.1 Logline
*RealVietnamRTS is a logistics-first Vietnam War RTS where you carve a battlespace out of jungle, build interlocking firebase networks, and run physical supply chains under constant threat — with an expanding persistent map campaign where every road and firebase you build carries forward across missions.*

### 1.2 Business Model
| Attribute | Value |
|-----------|-------|
| Developer | Solo developer |
| Platform | Steam PC only |
| Price Point | $20-30 USD premium |
| Release Strategy | No fixed deadline — ship when quality is right |
| Mod Support | Yes, post-launch |
| DLC Plans | Potential doctrine/campaign expansions |

### 1.3 Project Location
`C:\Users\caleb\RealVietnamRTS`

---

## 2. Target Audience

### 2.1 Primary Audience
Players who:
- Love **base building, turtling, and defense maintenance** in RTS games
- Find C&C/Age of Empires **too simple** in the strategic layer
- Find Company of Heroes **too meta-focused** with less rewarding defense building
- Appreciate **Steel Division's scale** but want persistent base construction
- Want to be **rewarded for good defensive construction** — the better you build, the easier defense becomes

### 2.2 Secondary Audience
- Vietnam War / military history enthusiasts
- Players who enjoy logistics puzzles (Factorio-lite appeal)
- Strategy gamers seeking a unique persistent map experience

### 2.3 Player Fantasy
You are a US Army battalion commander. Your job is to:
1. **Carve** the jungle into a defensible position
2. **Build** firebases that reflect your strategic choices
3. **Supply** those positions through vulnerable road/air networks
4. **Defend** against an enemy who decides when and where to fight
5. **Expand** your AO mission by mission, keeping everything you build

You command the operation. You decide the *shape* of the fight. The small-scale combat is automated; you control the big picture.

---

## 3. Core Design Philosophy

### 3.1 What This Game IS
- A **base-building focused** RTS with meaningful defensive construction
- A **logistics puzzle** where supply chains can be seen and attacked
- A **persistent experience** where your work carries forward
- **Steel Division scale** with added construction depth
- **Operational-level command** — you're the battalion commander, not a squad leader

### 3.2 What This Game is NOT
- **Not Age of Empires** — No unit production spam, no rally points
- **Not WARNO pure** — You build and adapt throughout, not just deploy-then-fight
- **Not Company of Heroes meta** — Defense building is rewarded, not just capping points
- **Not a war crimes simulator** — Respectful of the setting's weight
- **Not PS1 retro** — Early-2000s RTS aesthetic (Generals, Rome: Total War era)
- **Not ultra-realistic** — Authentic feel, gameplay-tuned stats

---

## 4. The Six Pillars

Every feature must serve at least one pillar. If it doesn't, it doesn't go in.

### Pillar 1: Carve the Map
The battlespace is opaque until you make it legible. Bulldozers cut roads, engineers clear jungle. Every cleared meter is vision, mobility, and supply. The map is a first-class entity.

### Pillar 2: Network of Firebases
Build interlocking forward positions (max 4-6 active firebases). Each has an HQ building that defines influence radius for logistics distribution. Place every sandbag and bunker yourself. No two firebases look the same.

### Pillar 3: Physical Supply Chains
Trucks on roads, helicopters to LZs. Supply is spatial, not abstract. Cut a road, ambush a convoy — supply exists in the world. A firebase cut off from supply dies slowly.

### Pillar 4: Doctrine Over Spam
Pre-mission doctrine choice commits you to a playstyle. Air Cavalry = infantry + helis, limited ground vehicles. Mechanized = more armor, fewer helis. Reinforcements arrive in real time. Force preservation matters.

### Pillar 5: The War Continues
Defenses fire at will automatically. Patrols run on standing orders. Convoys run schedules. You command the operation; you don't babysit. Long missions (45-90+ min) reward planning.

### Pillar 6: Persistent Expanding Map (NEW)
The campaign uses a **single persistent map** that expands with each mission. Mission 1 starts with ~100m playable. Each mission reveals more. All terrain modifications persist — roads, cleared jungle, craters, firebases. By mission 8-10, you have an interconnected network of everything you built.

---

# PART II — CORE SYSTEMS

## 5. Core Gameplay Loop

### 5.1 Minute-to-Minute
1. **Survey** your AO via satellite view (terrain visible, enemies only when spotted)
2. **Order** engineers to clear jungle or bulldozers to cut roads
3. **Construct** defensive positions within firebase influence radius
4. **Position** squads on patrol routes or defensive positions
5. **Monitor** supply levels via HUD indicators
6. **Respond** to AI Director attacks by repositioning reserves
7. **Request** reinforcements and resupply as needed

### 5.2 Mission-to-Mission
1. **Complete** mission objectives (time-limited or objective-based)
2. **Survive** AI Director escalation
3. **Preserve** forces (veterancy carries forward in campaign)
4. **Expand** into newly revealed map area
5. **Connect** new firebases to existing supply network

### 5.3 Control Granularity
**Steel Division approach**: Primarily operational with smart automation, but player CAN micro when needed.

| Situation | Control Level |
|-----------|---------------|
| Firebase defense | Automated (fire at will) |
| Patrol routes | Set and forget (standing orders) |
| Supply runs | Automated within network |
| Offensive operations | Player-directed |
| Emergency response | Player micro when needed |
| High-value units (tanks, gunships) | Direct control available |

---

## 6. Unit Resource System

Squads carry **internal reserves** that deplete through action and time. This creates the logistics pressure.

### 6.1 Resource Types

| Resource | Depletion Trigger | Effect When Low | Effect When Empty |
|----------|-------------------|-----------------|-------------------|
| **Ammo** | Shooting | "LOW AMMO" icon | Auto-retreat to nearest safe area + voice callout |
| **Water** | Time-based | Accelerated morale drain | Severe morale drain |
| **Morale** | Combat, casualties, dehydration | Reduced effectiveness | Routing (see Section 7) |

### 6.2 Reserve Capacities (Example)
| Unit Type | Ammo Reserve | Water Reserve | Notes |
|-----------|--------------|---------------|-------|
| Rifle Squad | 100 units | 100 units | Depletes ~1/shot, ~1 water/30sec |
| Weapons Squad | 150 units | 100 units | Heavy weapons burn ammo faster |
| Recon Team | 60 units | 80 units | Light loadout |
| Engineer Squad | 40 units | 100 units | Limited combat role |

### 6.3 Resupply Mechanics
- Squads **within firebase influence radius** automatically resupply from depot
- Squads **outside influence** must:
  - Return to firebase, OR
  - Receive helicopter/truck resupply delivery
- When ammo hits EMPTY: Squad auto-retreats to nearest cluster of friendlies + audio notification "SQUAD OUT OF SUPPLIES, FALLING BACK"

---

## 7. Morale & Routing System

**Reference implementation:** `BP_RTS_Dark_Shadows/battle_system/morale/` — adapt for Vietnam context.

### 7.1 Morale States

| State | Morale Value | Combat Effectiveness | Behavior |
|-------|--------------|---------------------|----------|
| STEADY | 70-100 | 100% | Normal operations |
| WAVERING | 40-70 | 90% | Slightly impaired |
| SHAKEN | 20-40 | 75% | Significantly impaired |
| BROKEN | 0-20 | 30% | Routing behavior |

### 7.2 Morale Modifiers (Continuous, per second)

| Modifier | Effect | Notes |
|----------|--------|-------|
| Under fire | -0.3/sec | Taking ranged fire |
| Surrounded | -1.25/sec | Enemies on 3+ sides |
| Dehydrated (low water) | -0.5/sec | Water below 20% |
| Near firebase | +1.0/sec | Within influence radius |
| Near allies | +0.5/sec | Per nearby friendly squad (max 3) |
| Winning engagement | +0.6/sec | Inflicting more casualties |
| Natural recovery (safe) | +1.0/sec | No enemies nearby |

### 7.3 One-Time Morale Events

| Event | Morale Change |
|-------|---------------|
| Nearby ally killed | -3 |
| Squad leader killed | -15 |
| Flanked/ambushed | -8 |
| Reinforcements arrive | +10 |
| Enemy unit routed | +5 |

### 7.4 Routing Behavior (Total War-style)
When morale hits BROKEN (squad has 50%+ soldiers in broken state):
1. Squad **attempts to return to nearest firebase**
2. If they "break hard" (80%+ broken = SHATTERED), they go **rogue** — ignore orders, run in survival mode
3. Eventually can **recover** if they reach safety and have 5+ seconds without contact
4. **SHATTERED squads cannot rally** — effectively combat-ineffective until medevac'd or mission end

---

## 8. Firebase System

### 8.1 Firebase Definition
A firebase is defined by placing an **HQ Building** (Command Post, TOC, or Firebase HQ).

### 8.2 HQ Influence Radius
The HQ building creates an **influence radius** where:
- Squads automatically receive supplies (ammo, water)
- Morale recovery bonus applies
- Engineer auto-construction is enabled
- Defensive structures fire at will

| HQ Type | Influence Radius | Building Slots |
|---------|------------------|----------------|
| Firebase HQ | 150m | 12 |

### 8.3 Firebase Limit
**Maximum 4-6 firebases active at one time.** This forces strategic choices about positioning.

### 8.4 Outposts (Informal)
Players can build **sandbag positions outside firebase radius** — these are informal outposts with:
- No influence radius
- No auto-supply
- No morale bonus
- Manual resupply required
- Purely defensive positions

---

## 9. Supply & Logistics

### 9.1 Supply Sources
| Source | Type | Notes |
|--------|------|-------|
| Rear Depot | Fixed map feature | Infinite supply, starting point |
| Airstrip | Fixed map feature | Enables fixed-wing, can be cratered |
| Supply Depot (building) | Constructed | Stores supplies, distributes within radius |

### 9.2 Supply Movement

| Method | Capacity | Speed | Vulnerability |
|--------|----------|-------|---------------|
| Truck Convoy | High | Road-dependent | Ambush-vulnerable |
| Helicopter | Medium | Fast, direct | Limited capacity, fuel cost |

### 9.3 Supply Flow
1. **Automatic within network**: If road connects firebases, supply flows automatically
2. **Truck convoys**: Spawn at depot, follow roads, deliver to firebase, return
3. **Helicopter resupply**: For emergency/isolated positions, player-dispatched or automated

### 9.4 Supply Consumption
| Activity | Cost |
|----------|------|
| Squad ammo resupply | 10 supply/full refill |
| Squad water resupply | 5 supply/full refill |
| Building construction | Varies by building |
| Reinforcement arrival | Varies by unit type |

---

## 10. Construction System

### 10.1 Who Can Build What

| Builder | Inside Firebase Radius | Outside Firebase Radius |
|---------|------------------------|-------------------------|
| Any Squad | Sandbags, Foxholes, Wire | Sandbags, Foxholes, Wire |
| Engineer Squad | All buildings (auto-build) | All buildings (manual command) |
| Bulldozer | Roads, large clearing | Roads, large clearing |

### 10.2 Building Categories

**Player-Constructible (Costs Supply)**
| Building | Supply Cost | Function |
|----------|-------------|----------|
| Sandbag Wall | 5 | Basic cover, drag-paint |
| Wire Obstacle | 10 | Slows enemies, channels attacks |
| Foxhole | Free | Infantry fighting position |
| Bunker | 40 | Heavy cover, garrison 1 squad |
| MG Nest | 30 | Auto-fires arc, suppresses |
| Mortar Pit | 35 | Indirect fire, auto or manual |
| Supply Depot | 45 | Stores supplies, resupplies squads |
| Helipad | 50 | LZ for helicopters |
| Observation Tower | 30 | Extended sight, spots for mortars |
| Command Post | 80 | HQ building, defines firebase |

**Terrain Modification**
| Action | Tool | Time |
|--------|------|------|
| Clear jungle (small) | Engineer det-cord | 60 sec |
| Clear jungle (large) | Bulldozer | 30 sec |
| Cut road through jungle | Bulldozer | 2-3 min per 100m |
| Prepare LZ | Engineer or Bulldozer | 90 sec |

---

## 11. Combat System

### 11.1 Lethality
**Steel Division style**: Casualties over time. A full squad wipe takes 30-60 seconds of sustained fire. Cover is meaningful but not instant-death without it.

### 11.2 Cover System
| Cover Type | Damage Reduction | Notes |
|------------|------------------|-------|
| None (open) | 0% | Exposed |
| Light (jungle) | 25% | Natural cover |
| Partial (sandbags) | 50% | Standard defensive |
| Heavy (bunker) | 75% | Strong defensive |

### 11.3 Suppression
Units under heavy fire become suppressed:
- Movement speed reduced 50%
- Accuracy reduced 50%
- Morale drains faster

### 11.4 Auto-Defense Behavior
All defensive structures and garrisoned squads use **fire at will** — engage any enemy in range automatically. No complex ROE system.

### 11.5 Damage Types
| Type | Source | Notes |
|------|--------|-------|
| Small Arms | M16, AK-47 | Standard infantry |
| Heavy MG | M2, DShK | Suppression-focused |
| Explosive | Mortars, grenades | Area damage |
| Armor-Piercing | LAW, RPG | Anti-vehicle |

---

## 12. AI Director

**L4D-style dynamic system** — monitors player stress and adapts attack intensity.

### 12.1 Director Inputs
| Input | Measurement |
|-------|-------------|
| Firebase integrity | % of firebases under attack |
| Supply status | Supply reserves across all firebases |
| Casualty rate | Recent losses |
| Defensive coverage | Unmanned sectors |
| Player idle time | Time since last command |

### 12.2 Director Outputs
| Output | Range |
|--------|-------|
| Attack frequency | 5-15 min between waves |
| Attack intensity | 1-4 squads per wave |
| Attack direction | Probes weak points |
| Attack type | Infantry assault, sapper raid, mortar harassment |

### 12.3 Escalation
The Director escalates over mission duration:
- **Early** (0-15 min): Probing attacks, 1-2 squads
- **Mid** (15-35 min): Coordinated attacks, 2-3 squads, mortars
- **Late** (35+ min): Full assaults, 3-4 squads, sappers, multi-direction

### 12.4 VC Tactics (Historical Patterns)
| Tactic | When Used |
|--------|-----------|
| Night attack | After sunset (reduced visibility) |
| Sapper raid | Target ammo/fuel depots |
| Mortar harassment | Sustained pressure, no assault |
| Human wave | When player is weakened |
| Ambush | On supply convoys |

---

## 13. Doctrine System

### 13.1 How Doctrines Work
1. **Pre-mission**: Player selects doctrine
2. **Doctrine determines**:
   - Which unit types are available
   - Which buildings can be constructed
   - Reinforcement timing modifiers
   - Playstyle strengths/weaknesses

### 13.2 Historical Background

The US Army in Vietnam used the **ROAD** (Reorganization Objective Army Division) structure established in 1962. Divisions had a common "division base" with specialized internal organization depending on type. The five division types were: Infantry, Mechanized Infantry, Armored, Airborne, and Airmobile.

**Sources:**
- [US Army in Vietnam War - Wikipedia](https://en.wikipedia.org/wiki/United_States_Army_during_the_Vietnam_War)
- [Formations of US Army in Vietnam - Wikipedia](https://en.wikipedia.org/wiki/Formations_of_the_United_States_Army_during_the_Vietnam_War)
- [1st Cavalry Division History](https://www.first-team.us/tableaux/chapt_08/)

---

### 13.3 US DOCTRINES

#### **DOCTRINE: Air Cavalry** (Primary MVP Doctrine)
*Based on: 1st Cavalry Division (Airmobile), 101st Airborne Division (Airmobile after 1968)*

**Historical Context:**
The 1st Cavalry Division (Airmobile) was created July 1, 1965, from the experimental 11th Air Assault Division. It deployed to Vietnam with **428 organic helicopters** — unprecedented at the time. The division consisted of eight infantry battalions controlled by three brigades, four artillery battalions, an air cavalry squadron, and an aviation group with UH-1 Huey and CH-47 Chinook helicopters. First saw combat at the Battle of Ia Drang (1965).

**Gameplay Identity:**
- **Strength:** Rapid deployment, vertical envelopment, quick reaction force
- **Weakness:** Limited heavy armor, dependent on helicopter availability, vulnerable LZs
- **Playstyle:** Mobile defense, rapid firebase establishment, helicopter-borne assault

**Unit Roster:**
| Unit | Historical Basis | Role |
|------|------------------|------|
| Rifle Squad (10) | 1/7 Cavalry standard | General infantry, M16/M60/M79 |
| Weapons Squad (8) | Battalion weapons platoon | M2 .50cal or 81mm mortar |
| Recon Team (4-6) | LRRP teams | Stealth scouting, extended sight |
| Engineer Squad (8) | Division engineers | Construction, det-cord clearing |
| UH-1D Huey Transport | 227th/229th Aviation Battalions | Troop lift (1 squad), supply delivery |
| UH-1B/C Huey Gunship | Air Cavalry Squadron | Fire support, escort |
| OH-6 Cayuse (Scout) | Air Cavalry Squadron | Reconnaissance, target marking |

**Building Unlocks:**
- Helipad (required)
- PSP Helipad (reinforced)
- All standard firebase buildings

**Reinforcement Modifier:** Helicopter reinforcements arrive 20% faster

---

#### **DOCTRINE: Mechanized Infantry**
*Based on: 25th Infantry Division, 1st Infantry Division mechanized battalions*

**Historical Context:**
The 25th Infantry Division ("Tropic Lightning") served in Vietnam 1966-1971 from Cu Chi Base Camp. It included mechanized battalions like 4th Battalion (Mechanized), 23rd Infantry — the "Tomahawks" — the first unit converted to mechanized in-country. Supported by 1st Battalion, 69th Armor with M48A3 Patton tanks. Participated in Operations Attleboro, Cedar Falls, Junction City, and the Battle of Saigon during Tet.

**Gameplay Identity:**
- **Strength:** Heavy firepower, armor protection, road dominance
- **Weakness:** Road-dependent, slow through jungle, large logistical footprint
- **Playstyle:** Methodical advance, convoy operations, firebase defense with armor

**Unit Roster:**
| Unit | Historical Basis | Role |
|------|------------------|------|
| Rifle Squad (10) | Standard infantry | General infantry |
| Mechanized Squad (10) | 4/23 Infantry (Mech) | Infantry in M113 APC |
| Weapons Squad (8) | Battalion weapons platoon | Heavy weapons |
| Engineer Squad (8) | Division engineers | Construction, mine clearing |
| M48A3 Patton | 1/69 Armor | Main battle tank, 90mm gun |
| M113 APC | Mechanized battalions | Troop transport, .50cal mount |
| M35 "Deuce-and-a-half" | Division logistics | Supply convoy |
| UH-1D Huey (limited) | Division aviation | Emergency resupply only |

**Building Unlocks:**
- Tank Revetment (required)
- Vehicle Depot
- All standard firebase buildings
- Helipad (limited to 1)

**Reinforcement Modifier:** Ground convoy reinforcements arrive 25% faster; M48 available from mission start

---

#### **DOCTRINE: Airborne Infantry**
*Based on: 173rd Airborne Brigade, 101st Airborne Division (pre-1968)*

**Historical Context:**
The 173rd Airborne Brigade ("Sky Soldiers") was the first major US Army ground unit deployed to Vietnam (May 1965). The 101st Airborne Division served 1965-1972, converting to airmobile in August 1968. Airborne units emphasized light, mobile infantry with organic firepower. Famous for the Battle of Hamburger Hill (1969).

**Gameplay Identity:**
- **Strength:** Elite infantry, high morale, versatile light forces
- **Weakness:** No armor, limited heavy weapons, infantry-dependent
- **Playstyle:** Aggressive patrolling, infantry-focused defense, ambush tactics

**Unit Roster:**
| Unit | Historical Basis | Role |
|------|------------------|------|
| Airborne Rifle Squad (10) | 173rd/101st standard | Elite infantry (+morale bonus) |
| Airborne Weapons Squad (8) | Battalion weapons | 81mm mortar, M60 MG |
| Pathfinder Team (4) | Division pathfinders | LZ marking, recon, +accuracy |
| Engineer Squad (8) | Airborne engineers | Light construction |
| 105mm Howitzer | DIVARTY | Artillery support |
| UH-1D Huey | Division aviation | Transport, limited |

**Building Unlocks:**
- Artillery Pit (105mm)
- All standard firebase buildings
- Helipad (standard allocation)

**Reinforcement Modifier:** Infantry squads have +10% morale; reinforcement by paradrop available (fast but risky)

---

#### **DOCTRINE: Marine Expeditionary** (Post-MVP)
*Based on: III Marine Amphibious Force (III MAF)*

**Historical Context:**
III MAF activated May 1965 at Da Nang, grew to include 1st and 3rd Marine Divisions plus 1st Marine Aircraft Wing (500+ aircraft). Operated in I Corps Tactical Zone (northern provinces). Unique Combined Action Platoon program integrated Marines with Vietnamese Popular Forces. Peak strength: 85,500 Marines (September 1968).

**Gameplay Identity:**
- **Strength:** Combined arms integration, naval gunfire support, amphibious capability
- **Weakness:** Operates separately from Army logistics
- **Playstyle:** Coastal operations, village pacification, aggressive small-unit tactics

*(Detailed roster: Post-MVP)*

---

### 13.4 VC/NVA DOCTRINES

**Historical Background:**
Communist forces consisted of three tiers operating interdependently:
1. **Guerrilla Forces** — Part-time fighters at village/hamlet level (squads/platoons)
2. **Local Force (Regional)** — Semi-professional provincial troops (companies/battalions)
3. **Main Force (PLAF/NVA)** — Full-time professional soldiers (battalions/regiments/divisions)

All used the "system of three" — three cells to a squad, three squads to a platoon, etc.

**Sources:**
- [GlobalSecurity - Viet Cong Organization](https://www.globalsecurity.org/military/world/vietnam/vietcong-org.htm)
- [NLF and PAVN Strategy - Wikipedia](https://en.wikipedia.org/wiki/NLF_and_PAVN_strategy,_organization_and_structure)

---

#### **DOCTRINE: VC Local Force**
*Regional/Provincial units*

**Historical Context:**
Local Force units were organized at provincial level into companies and battalions, attached to district/provincial headquarters. They "blended into the civilian population by day and became effective fighters at night." Provided intelligence, logistics, and harassment while supporting Main Force operations.

**Gameplay Identity:**
- **Strength:** Tunnels, local knowledge, night operations, attrition
- **Weakness:** Light weapons, no armor, limited sustained combat capability
- **Playstyle:** Ambush, harassment, sapper raids, tunnel networks

**Unit Roster:**
| Unit | Size | Role |
|------|------|------|
| VC Infantry Squad | 9-12 | Light infantry, AK-47/SKS |
| VC Sapper Cell | 3-6 | Infiltration, demolition, structure targeting |
| VC Mortar Team | 3-4 | 60mm mortar, hit-and-run |
| VC Recon Cell | 3 | Intelligence, target marking |
| VC Porter Team | 4-6 | Supply movement, non-combat |

**Building/Structure Unlocks:**
- Tunnel Entrance (spawn point, hidden)
- Spider Hole (single-soldier ambush)
- Weapon Cache (finite resupply)
- Punji Trap (damage trap)

**Special Abilities:**
- Night attack bonus (+25% effectiveness after dark)
- Tunnel network spawn (units appear from hidden tunnels)
- Village sympathy (can stage from neutral villages)

---

#### **DOCTRINE: VC/NVA Main Force**
*PLAF Main Force and NVA Regulars*

**Historical Context:**
Main Force units were "organized into battalions and regiments, but could also be organized into divisions." Battalion strength averaged 425-600 personnel. Equipped with heavier weapons: 12.7mm AA MGs, 82mm mortars, 75mm recoilless rifles. NVA units ("hard hats" with pith helmets) were better equipped and could deploy heavy artillery and tanks in later war phases.

**Gameplay Identity:**
- **Strength:** Coordinated assaults, heavy weapons, conventional tactics
- **Weakness:** Logistics-dependent, vulnerable to air power, less stealth
- **Playstyle:** Massed infantry assault, siege tactics, conventional defense

**Unit Roster:**
| Unit | Size | Role |
|------|------|------|
| NVA Infantry Squad | 10-12 | Regular infantry, AK-47 |
| NVA Weapons Squad | 8 | RPD LMG, RPG-7 |
| NVA Mortar Team | 4 | 82mm mortar |
| NVA Recoilless Rifle Team | 3 | 75mm RR, anti-armor |
| NVA Sapper Squad | 6-8 | Elite infiltrators |
| 12.7mm DShK AA Team | 3 | Anti-aircraft, anti-helicopter |

**Building/Structure Unlocks:**
- Fortified bunker complex
- AA emplacement
- Mortar pit
- Tunnel network (main force variant)

**Special Abilities:**
- Human wave assault (mass attack with morale bonus)
- Siege tactics (sustained pressure)
- Trail resupply (Ho Chi Minh Trail logistics)

---

### 13.5 Unit Organization Reference

**US Rifle Squad (Vietnam Era):**
- 10 soldiers total
- Squad Leader (E-6)
- 2 Fire Teams (Alpha: 4 men, Bravo: 5 men)
- Weapons per squad: 8x M16, 1x M60 LMG, 1x M79 grenade launcher
- Later: M203 underbarrel grenade launcher replaced M79 (1969+)

**US Rifle Platoon:**
- Platoon HQ (4)
- 3 Rifle Squads (10 each)
- 1 Weapons Squad (M60s, may have 90mm recoilless rifle)
- Total: ~40 soldiers

**VC/NVA Company (circa 1965-66):**
- Company HQ (25)
- Heavy Weapons Platoon (40): 3x 60mm mortars, 3x MMG
- 3 Rifle Platoons (35 each)
- Total: ~170 soldiers

**VC/NVA Battalion:**
- 3 Rifle Companies
- 1 Combat Support Company (82mm mortars, recoilless rifles, MGs)
- Total: ~425-600 soldiers

---

## 14. Campaign Structure

### 14.1 Persistent Expanding Map
The campaign is the **core differentiator**. One map that grows:

| Mission | Playable Area | New Features Introduced |
|---------|---------------|------------------------|
| 1 | ~100m x 100m | Basic construction, first firebase |
| 2 | ~300m x 300m | Road cutting, supply convoys |
| 3 | ~600m x 600m | Second firebase, helicopter ops |
| 4 | ~1km x 1km | Night cycle, mortar support |
| 5 | ~1.5km x 1.5km | Third firebase, tunnel clearing |
| 6-8 | ~2km x 2km | Full combined arms |
| 9-10 | ~3km x 3km (full) | Final defensive/offensive objectives |

### 14.2 Mission Structure
Each mission has:
1. **Objectives**: Specific goals (clear area, destroy target, hold position)
2. **Time limit**: Some missions have time pressure, others are "hold for X days"
3. **Map expansion**: Completing objectives reveals new playable area
4. **Persistence**: All construction, terrain changes, and surviving units carry forward

### 14.3 Victory/Loss Conditions

**Mission Victory:**
- Complete primary objectives within time limit (if any)
- Survive day count (for "hold" missions)

**Mission Failure:**
- All firebases fall (all HQ buildings destroyed)
- Primary objective failed (time expires)
- Return to checkpoint (see Save System)

**Campaign Victory:**
- Complete all 8-10 missions
- Final mission: Combined defensive and offensive objectives

### 14.4 Campaign Consequences
| Element | Persistence |
|---------|-------------|
| Terrain clearing | Persists |
| Roads built | Persists |
| Buildings constructed | Persists |
| Unit veterancy | Persists |
| Unit KIA | Permanent loss |
| Supply stockpiles | Persists |

### 14.5 Narrative Approach
**Light framing**: Briefings set historical context, but no named characters or plot. The story is told through the map — you can see your progress in the terrain itself.

---

## 15. Save System

### 15.1 Save Points
| Trigger | Save Type |
|---------|-----------|
| Mission start | Automatic |
| Map expansion (new area revealed) | Automatic |
| Every 10 minutes | Autosave |
| Player-initiated | Manual save |

### 15.2 On Mission Failure
Player can reload from:
1. **Mission start** — Retry with pre-mission state
2. **Last map expansion** — Return to when new area opened
3. **Last autosave** — Most recent 10-minute checkpoint
4. **Manual save** — Player's chosen point

### 15.3 What Gets Saved
- Terrain state (clearing, craters, roads)
- Building positions and health
- Unit positions, health, veterancy
- Supply levels at all depots
- Mission timer/progress
- AI Director state

---

## 16. Skirmish Mode

### 16.1 Playable Factions
- **US** (all available doctrines)
- **VC** (AI or player-controlled, depending on development)

### 16.2 Victory Conditions (Player Selects)
| Mode | Win Condition |
|------|---------------|
| Annihilation | Destroy all enemy forces/bases |
| Hold Points | Control key positions for duration |
| Timed Survival | Survive escalating waves until timer |

### 16.3 Skirmish Settings
- Map selection
- Doctrine selection
- Starting resources
- AI difficulty (single balanced setting for campaign; skirmish may have options)

---

## 17. Day/Night & Weather

### 17.1 Day/Night Cycle
**Real-time compressed cycle** — day passes during mission, affecting gameplay.

| Time | Gameplay Effect |
|------|-----------------|
| Day (0600-1800) | Full visibility, normal operations |
| Dusk (1800-1930) | Reduced visibility (-25%), atmospheric |
| Night (1930-0500) | Significantly reduced sight range (-60%), VC attack bonus (+25%) |
| Dawn (0500-0600) | Reduced visibility (-25%), fog chance increased |

**Time Compression:** 1 real minute = 10-15 game minutes (tunable). A 60-minute mission spans ~1-1.5 in-game days.

### 17.2 Central Highlands Weather (Historical)

**Setting:** Pleiku Province, II Corps Tactical Zone
**Altitude:** ~750 meters (2,450 feet)
**Climate:** Tropical monsoon with distinct wet/dry seasons

**Sources:**
- [Pleiku Climate Data](https://www.climatestotravel.com/climate/vietnam/pleiku)
- [Vietnam Climate - Wikipedia](https://en.wikipedia.org/wiki/Climate_of_Vietnam)

---

### 17.3 Seasonal Calendar

**Campaign Setting: 1969**
The campaign takes place across multiple months, with weather reflecting the actual Central Highlands seasonal pattern.

| Month | Season | Rainfall | Weather Pattern |
|-------|--------|----------|-----------------|
| **January** | Dry | 9mm | Clear, warm days (25-27°C), cool nights |
| **February** | Dry | 15mm | Clear, warming trend |
| **March** | Dry/Hot | 40mm | Hot (up to 32°C), occasional showers |
| **April** | Pre-Monsoon | 80mm | Hottest month (33°C peak), building humidity |
| **May** | Monsoon Start | 180mm | Southwest monsoon arrives, daily rain |
| **June** | Monsoon | 220mm | Heavy afternoon rains, high humidity |
| **July** | Monsoon | 240mm | Sustained rain, muddy conditions |
| **August** | Monsoon Peak | 280mm | Heaviest rainfall, flooding possible |
| **September** | Monsoon Peak | 390mm | Maximum precipitation, severe conditions |
| **October** | Monsoon End | 250mm | Rains tapering, still wet |
| **November** | Transition | 100mm | Clearing, cooler nights |
| **December** | Dry | 25mm | Dry season begins, pleasant conditions |

---

### 17.4 Weather Types & Gameplay Effects

| Weather | Occurrence | Movement | Visibility | Air Ops | Morale | Special |
|---------|------------|----------|------------|---------|--------|---------|
| **Clear** | Dry season common | 100% | 100% | Full | Neutral | — |
| **Overcast** | Year-round | 100% | 90% | 90% effectiveness | Neutral | CAS accuracy -10% |
| **Light Rain** | Monsoon daily | 90% | 75% | 75% effectiveness | -0.1/sec | Extinguishes fires |
| **Heavy Rain** | Monsoon peaks | 70% | 50% | 50% effectiveness | -0.2/sec | Roads become mud |
| **Monsoon Storm** | June-Sept | 50% | 25% | **Grounded** | -0.5/sec | No helicopter ops, flash floods |
| **Fog** | Dawn, valleys | 80% | 30% | **Grounded** | Neutral | Common at dawn, burns off |
| **Ground Fog** | Night/dawn | 90% | 50% | Limited | Neutral | Low-lying areas only |

---

### 17.5 Weather State Machine

```
CLEAR ←→ OVERCAST ←→ LIGHT_RAIN ←→ HEAVY_RAIN ←→ MONSOON_STORM
                ↓
              FOG (dawn only)
```

**Transition Rules:**
- Dry season (Nov-Apr): 70% Clear, 20% Overcast, 10% Light Rain
- Monsoon (May-Oct): 20% Clear, 30% Overcast, 30% Light Rain, 15% Heavy Rain, 5% Storm
- Fog: 30% chance at dawn during any season, 50% chance in valleys
- Weather changes every 2-4 in-game hours

---

### 17.6 Tactical Weather Implications

| Condition | US Advantage | VC/NVA Advantage |
|-----------|--------------|------------------|
| Clear Day | Air superiority, observation, firepower | Exposed movement |
| Overcast | Adequate operations | Some concealment |
| Rain | Reduced effectiveness | Movement concealment, noise cover |
| Monsoon Storm | **Disadvantage** — no air support | **Advantage** — assault opportunity |
| Night + Rain | Major disadvantage | Ideal attack conditions |
| Fog | Limited observation | Infiltration opportunity |

**Historical Note:** VC/NVA forces deliberately timed major attacks during monsoon storms when US air support was grounded. The Tet Offensive (January 1968) was timed during a period of poor weather.

---

### 17.7 Implementation Notes

**MVP Status:** Weather system is **parked for MVP**. Missions use fixed "Clear/Overcast" weather.

**Post-MVP Integration:**
1. Implement weather state machine with seasonal probabilities
2. Add movement/visibility modifiers per weather type
3. Integrate with AI Director (VC attacks more likely in bad weather)
4. Add visual effects (rain particles, fog volumes, puddles)
5. Optional: Historical weather data for specific 1969 dates

---

## 18. UI/UX Requirements

### 18.1 Camera
- **Seamless strategic zoom**: One view, zoom out far enough and it becomes strategic
- **WASD/Arrow pan** + edge scroll
- **Mouse wheel zoom** (smooth from ~10m to ~500m altitude)
- **Q/E rotate**
- **Focus on selection**
- At extreme zoom-out: Units render as NATO-style markers

### 18.2 Selection
- **Box select** (drag rectangle)
- **Click select** (single unit/building)
- **Control groups** (Ctrl+1-9 to save, 1-9 to recall)
- **Double-click** selects all of type on screen

### 18.3 Build Menu
**Intuitive and easy to understand** — specific layout TBD during implementation. Options:
- Bottom bar with categories (C&C style)
- Radial menu on right-click
- Sidebar panel

### 18.4 HUD Elements
| Element | Purpose |
|---------|---------|
| Minimap | Overview with fog of war |
| Supply indicator | Current supply at selected firebase |
| Reinforcement clock | Time until next reinforcement |
| Unit resource icons | LOW/EMPTY ammo/water indicators floating above units |
| Mission objectives | Current objectives and progress |
| Day/time indicator | Current time of day |

### 18.5 Map Visibility
**Satellite view**: Terrain visible everywhere. Enemies only visible when spotted by units or observation posts.

### 18.6 Accessibility Features
- **Pause and issue orders**: Full control while paused
- **Speed controls**: Slow down or speed up game time
- No colorblind mode required

---

## 19. Audio Direction

### 19.1 Music
**Dynamic combat music**:
- Quiet/ambient during exploration and building
- Intensity ramps up during combat
- Distinct cues for enemy contact, firebase under attack

### 19.2 Sound Design
| Category | Examples |
|----------|----------|
| Weapons | M16 distinct from AK-47, M60, etc. |
| Vehicles | Huey rotor wash as signature sound |
| Radio chatter | Period-appropriate callouts on events |
| Ambient | Jungle sounds, insects, distant artillery |
| UI feedback | Build complete, low ammo warning, etc. |

### 19.3 Voice Lines
- "SQUAD OUT OF SUPPLIES, FALLING BACK"
- "FIREBASE UNDER ATTACK"
- "REINFORCEMENTS INBOUND"
- Period-authentic military radio protocol

---

## 20. Technical Requirements

### 20.1 Target Specs
**Potato-friendly**: Intel integrated graphics should work on low settings.

| Setting | Minimum | Recommended |
|---------|---------|-------------|
| GPU | Intel UHD 620 | GTX 1060 / RX 580 |
| CPU | i5-4590 | i5-8400 |
| RAM | 8 GB | 16 GB |
| Storage | 2 GB | 5 GB |

### 20.2 Performance Targets
- 60 FPS with 300-500 units on recommended specs
- 30 FPS minimum on potato specs
- Efficient spatial hashing for unit queries
- LOD system for large battles
- Cell streaming for large maps (TerrainEngine integration)

### 20.3 Visual Style
**Early-2000s RTS aesthetic**: Mid-poly models, hand-painted textures, real lighting.
- Reference: C&C Generals (2003), Rome: Total War (2004), Battlefield Vietnam (2004)
- Target: ~1500-3000 tris per unit
- Textures: ~512px hand-painted diffuse
- NOT PS1 retro, NOT photorealistic

### 20.4 Engine
- Godot 4.5+
- TerrainEngine integration for terrain generation

---

# PART III — SCOPE & ROADMAP

## 21. MVP Scope

### 21.1 MVP Definition of Done
A playable mission that delivers all six pillars in 60-90 minutes:
1. Carve at least one road through jungle
2. Build two interconnected firebases
3. Physical supply chain (trucks + helicopters)
4. Doctrine-locked force composition
5. Auto-defending firebases, scheduled convoys
6. Persistent terrain changes visible

### 21.2 MVP Unit Roster

**US Units (6)**
| Unit | Role | Notes |
|------|------|-------|
| Rifle Squad | General infantry | 10 soldiers, can garrison |
| Engineer Squad | Construction | 8 soldiers, det-cord, mediocre combat |
| Weapons Squad | Fire support | M2 .50cal or 81mm mortar |
| Recon Team | Stealth scouting | 4 soldiers, extended sight |
| M48 Patton | Heavy armor | Tank, requires road access |
| Huey Transport | Air mobility | Transport + supply delivery |

**Air Assets (Called-in)**
- Huey Gunship — fire support pass, cooldown-based

**VC Units (4, AI-controlled)**
| Unit | Role | Notes |
|------|------|-------|
| VC Infantry | Light infantry | AK-47, basic |
| VC Sappers | Infiltrators | Bypass wire, target structures |
| VC Mortar Team | Indirect fire | Hit-and-run |
| VC Porter | Supply carriers | Non-combat |

**Vehicles (Non-combat)**
- M35 Truck — convoy supply
- D7 Bulldozer — road grading

### 21.3 MVP Buildings
10 US buildings (see Section 10)
4 VC buildings (Tunnel entrance, Spider hole, Weapon cache, Punji trap)

### 21.4 MVP Exclusions
- Weather system (parked)
- Strategic air strikes (napalm, B-52)
- Village civic action
- SOG operations
- Multiplayer/co-op
- Map editor
- Additional helicopter types (Cobra, Chinook)
- NVA conventional armor

---

## 22. Post-MVP Roadmap

### Phase 7: Scale Up
- Expand to 4-6 firebases per mission
- Weather system integration with historical data
- Village allegiance mechanics
- Strategic air support
- Additional doctrines

### Phase 8: Campaign Mode
- Full 8-10 mission persistent campaign
- Complete save/load implementation
- Mission briefings and debrief screens

### Phase 9: VC Campaign
- VC playable in campaign
- Full asymmetric VC mechanics

### Phase 10: Polish & Launch
- Audio overhaul
- Visual polish
- Performance optimization

### Parking Lot (No Timeline)
- SOG missions
- Multiplayer/co-op
- Map editor
- Mod support tools

---

## 23. Open Questions & Research Needed

### 23.1 Historical Research — COMPLETED
| Topic | Status | Notes |
|-------|--------|-------|
| US Army Vietnam-era doctrine names | ✅ DONE | See Section 13.3 — Air Cavalry, Mechanized, Airborne, Marine |
| VC/NVA organizational structure | ✅ DONE | See Section 13.4 — Local Force, Main Force tiers |
| 1969 Vietnam weather patterns | ✅ DONE | See Section 17 — Central Highlands seasonal calendar |
| Firebase construction methods | 🔄 LOW | Research as needed during building implementation |
| Radio communication protocols | 🔄 LOW | Research during audio implementation |

### 23.2 Design Questions to Resolve
| Question | When to Resolve |
|----------|-----------------|
| Exact reinforcement timing values | After first playtest |
| Final map size progression | After mission 1 testing |
| Helicopter control specifics | During Phase 4 implementation |
| Build menu layout | During UI implementation |

### 23.3 Technical Questions
| Question | When to Resolve |
|----------|-----------------|
| TerrainEngine integration approach | Phase 1 |
| Save system architecture | Phase 0 (architect), Phase 8 (implement) |
| AI Director tuning | Phase 5 |

---

## APPENDIX A: Historical References

### Primary Sources Used

**US Army Organization:**
- [US Army during Vietnam War - Wikipedia](https://en.wikipedia.org/wiki/United_States_Army_during_the_Vietnam_War)
- [Formations of US Army in Vietnam - Wikipedia](https://en.wikipedia.org/wiki/Formations_of_the_United_States_Army_during_the_Vietnam_War)
- [1st Cavalry Division History - First-Team.us](https://www.first-team.us/tableaux/chapt_08/)
- [1st Air Cav Organization - CherriesWriter](https://cherrieswriter.com/2017/02/28/organization-of-the-1st-cavalry-division-airmobile/)
- [25th Infantry Division History](https://www.25thida.org/division/)
- [US Army Armor & Mech-Infantry in Vietnam - TheMilitaryMark](https://www.themilitarymark.com/us-army-in-vietnam-war/)
- [M48 Patton in Vietnam - Army Historical Foundation](https://armyhistory.org/the-m48-patton-main-battle-tank/)
- [III MAF in Vietnam - Hotel 2/5 Combat Marines](https://hotel25vv.com/iii-maf-in-vietnam)

**VC/NVA Organization:**
- [Viet Cong Organization - GlobalSecurity.org](https://www.globalsecurity.org/military/world/vietnam/vietcong-org.htm)
- [NLF and PAVN Strategy - Wikipedia](https://en.wikipedia.org/wiki/NLF_and_PAVN_strategy,_organization_and_structure)
- [NVA Army - 212Warriors](https://www.212warriors.com/nva_army.html)

**Weather & Climate:**
- [Pleiku Climate - ClimatesToTravel](https://www.climatestotravel.com/climate/vietnam/pleiku)
- [Climate of Vietnam - Wikipedia](https://en.wikipedia.org/wiki/Climate_of_Vietnam)
- [Monsoon in Vietnam - VietnamDrive](https://www.vietnamdrive.com/monsoon-seasons/)

**Weapons & Equipment:**
- [M79 Grenade Launcher - Wikipedia](https://en.wikipedia.org/wiki/M79_grenade_launcher)
- [M16 Rifle - Wikipedia](https://en.wikipedia.org/wiki/M16_rifle)
- [US Rifle Company Organization 1970 - BattleOrder.org](https://www.battleorder.org/us-army-vietnam-1970)

### Key Historical Data Points

**1st Cavalry Division (Airmobile) - 1965:**
- 428 organic helicopters
- 8 infantry battalions, 3 brigades
- Aviation Group: 227th, 228th, 229th Aviation Battalions
- First combat: Battle of Ia Drang, November 1965

**25th Infantry Division - 1966-1970:**
- Based at Cu Chi Base Camp
- Mechanized battalions: 4/23 Infantry (Mech)
- Armor support: 1/69 Armor (M48A3 Pattons)
- Operations: Attleboro, Cedar Falls, Junction City, Tet defense

**III Marine Amphibious Force - 1965-1971:**
- Peak strength: 85,500 Marines (September 1968)
- 1st and 3rd Marine Divisions + 1st Marine Aircraft Wing
- I Corps Tactical Zone (northern provinces)

**Central Highlands Weather (Pleiku):**
- Dry Season: November - April (peak: January, 9mm rain)
- Monsoon Season: May - October (peak: September, 390mm rain)
- Annual rainfall: ~2,228mm
- Temperature range: 22-33°C

---

## 24. Decision Log

> Every significant design decision, why it was made, alternatives considered. New decisions appended chronologically.

### D-001: Six Pillars (Updated from Five)
**Date:** 2026-05-20
**Decision:** Added "Persistent Expanding Map" as sixth pillar.
**Rationale:** This is the core differentiator — no other RTS does persistent expanding maps. Elevating it to pillar status ensures it's protected.

### D-002: Unit Resource System
**Date:** 2026-05-20
**Decision:** Squads carry internal Ammo + Water + Morale reserves.
**Rationale:** Creates tangible logistics pressure. Units must be resupplied or they auto-retreat.

### D-003: Firebase Limit (4-6)
**Date:** 2026-05-20
**Decision:** Maximum 4-6 firebases active simultaneously.
**Rationale:** Forces strategic choice about positioning rather than spamming bases everywhere.

### D-004: AI Director System
**Date:** 2026-05-20
**Decision:** L4D-style AI Director monitors player stress and adapts attacks.
**Rationale:** More interesting than scripted waves. Creates tension without unfair difficulty.

### D-005: Satellite View (Not Full Fog of War)
**Date:** 2026-05-20
**Decision:** Player can see terrain everywhere, enemies only when spotted.
**Rationale:** Fits the "commander with aerial recon" fantasy. Simpler than full fog of war while maintaining tactical uncertainty.

### D-006: No Difficulty Options
**Date:** 2026-05-20
**Decision:** Single balanced experience, no Easy/Normal/Hard.
**Rationale:** Focus development on one tuned experience rather than balancing multiple.

### D-007: Checkpoint Save System
**Date:** 2026-05-20
**Decision:** Autosave at mission start, map expansion, and every 10 minutes.
**Rationale:** Supports the "save anywhere" flexibility user requested while keeping implementation manageable.

### D-008: Morale Routing (Total War-style)
**Date:** 2026-05-20
**Decision:** Broken units try to return to firebase; shattered units go rogue.
**Rationale:** Reference implementation exists in BP_RTS_Dark_Shadows. Creates dramatic moments without instant squad wipes.

### D-009: Historical Doctrine Research Complete
**Date:** 2026-05-20
**Decision:** Four US doctrines defined based on historical divisions:
- Air Cavalry (1st Cav Airmobile)
- Mechanized Infantry (25th ID)
- Airborne Infantry (173rd/101st)
- Marine Expeditionary (III MAF, post-MVP)

Two VC/NVA doctrines defined:
- Local Force (regional guerrillas)
- Main Force (PLAF/NVA regulars)

**Rationale:** Historical accuracy provides authenticity and avoids "hallucinated" game design. Each doctrine based on actual unit compositions, equipment, and tactics from the Vietnam War period.

### D-010: Central Highlands Weather Calendar
**Date:** 2026-05-20
**Decision:** Weather system based on actual Pleiku Province climate data:
- Dry season: November-April (70% clear weather)
- Monsoon season: May-October (up to 390mm rain in September)
- Weather affects gameplay: movement, visibility, air operations, morale
- AI Director uses weather for attack timing (VC attacks more likely in storms)

**Rationale:** Historical weather patterns add authenticity and strategic depth. Monsoon storms create natural dramatic tension when US air support is grounded.

---

*End of document. Version 1.1. Last updated: 2026-05-20.*
