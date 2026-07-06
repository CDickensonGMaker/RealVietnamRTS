# Game Concept Document

> **Status**: `[LOCKED]` for vision, `[LIVING]` for details
> **Last Updated**: 2026-05-21
> **Source Documents**: GAME_BIBLE.md, PRD.md

---

## 1. Overview

RealVietnamRTS is a logistics-first Vietnam War RTS where you carve a battlespace out of jungle, build interlocking firebase networks, and run physical supply chains under constant threat. The game features an expanding persistent map campaign where every road and firebase you build carries forward across missions. Players command at the operational level as a US Army battalion commander, deciding the *shape* of the fight while the small-scale combat is automated.

**Working Title**: RealVietnamRTS (final title TBD)
**Developer**: Solo developer
**Platform**: Steam PC only
**Price Point**: $20-30 USD premium
**Engine**: Godot 4.6

---

## 2. Player Fantasy

You are a US Army battalion commander in a fictional unit operating in real Vietnamese geography during the period 1965-1972. Your AO is opaque jungle, broken terrain, and contested villages. Your job is to:

1. **Carve** the jungle into a defensible position
2. **Build** firebases that reflect your strategic choices
3. **Supply** those positions through vulnerable road/air networks
4. **Defend** against an enemy who decides when and where to fight
5. **Expand** your AO mission by mission, keeping everything you build

You are not a tactical squad leader. You are not babysitting individual soldiers. You command an operation. You decide the shape of the fight - where firebases go, where roads get cut, what your reinforcement schedule looks like. The fight itself is automated in the small and decided by you in the large.

---

## 3. The Six Pillars

Every feature must serve at least one pillar. If it doesn't, it doesn't go in.

### Pillar 1: Carve the Map
The battlespace is opaque until you make it legible. Bulldozers cut roads through hills, engineers use det-cord to clear jungle pockets and LZs. Every cleared meter is vision, mobility, and supply. The map is a first-class entity - terrain matters, height matters, every river crossing and every ridgeline shapes the campaign.

### Pillar 2: Network of Firebases
Build interlocking forward positions (max 4-6 active firebases), each with its own LZ and road link back to the supply network. Each has an HQ building that defines influence radius for logistics distribution. Place every sandbag and bunker yourself with paint/drag perimeter tools. Engineers auto-construct inside established zones; you direct them manually for forward bunker complexes outside the wire. No two firebases look the same. The firebase is your design.

### Pillar 3: Physical Supply Chains
Trucks on roads, helicopters between LZs, fixed-wing from captured airstrips. Supply is spatial, not abstract. Cut a road, crater a runway, ambush a convoy - supply chains exist in the world and they can be attacked. A firebase isolated from supply is a firebase that dies slowly.

### Pillar 4: Doctrine Over Spam
Pre-mission doctrine choice commits you to a playstyle. Air Cavalry = infantry + helis, limited ground vehicles. Mechanized = more armor, fewer helis. Reinforcements arrive by helicopter or convoy in real time - minutes, not seconds. Lose a tank and you wait for the next convoy. Lose your supply line and you starve. Force preservation matters more than force production.

### Pillar 5: The War Continues
Patrols run on standing orders. Defenses fire at will automatically. Convoys run schedules. Engineers auto-build in zones. You command the operation; you don't babysit individuals. Long missions (45-90+ min) reward planning over reflexes. The game runs whether you're watching that sector or not.

### Pillar 6: Persistent Expanding Map
The campaign uses a **single persistent map** that expands with each mission. Mission 1 starts with ~100m playable. Each subsequent mission reveals and unlocks a larger section of the same map. All terrain modifications persist - roads, cleared jungle, craters, firebase fortifications. All constructed bases persist. By mission 8-10, you have an interconnected network of everything you built. Final mission reveals the complete 3km x 3km map with all prior work visible.

---

## 4. Reference Games

| Game | What We Borrow |
|------|----------------|
| **C&C Generals** | Faction doctrines, base-building feel, persistent map control |
| **Steel Division / Wargame** | Pre-mission deck, period authenticity, combat lethality, phased availability |
| **Company of Heroes** | Sector/territory logic, cover system, suppression, squad-level combat |
| **Supreme Commander** | Automation philosophy, strategic zoom, "commander not babysitter" |
| **Foxhole** | Logistics as physical reality - supply chains you can see and cut |
| **Men of War: Vietnam** | Period detail, vehicle/weapon realism, mixed-arms combat |
| **R.U.S.E.** | Strategic zoom for managing wide AOs without losing tactical detail |
| **Battlefield Vietnam (2004)** | Visual reference for the early-2000s aesthetic target |
| **Joint Operations: Typhoon Rising (2004)** | Helicopter/jungle/firebase visual and tonal reference |
| **Warno** | Reinforcement timing, deck building, combined arms |
| **Broken Arrow** | Modern combined arms, realistic lethality, supply vulnerability |
| **Left 4 Dead** | AI Director system for dynamic difficulty |
| **Total War** | Morale and routing mechanics |

---

## 5. Anti-Pillars (What the Game is NOT)

- **Not Age of Empires.** No rapid unit production. No rally points spitting units. No instant-buy reinforcements. If you want a tank, you wait for the convoy that's bringing it.
- **Not WARNO pure.** This is not a deployment-then-fight game. You carve, build, reinforce, and adapt throughout the mission.
- **Not Foxhole.** Single-player and co-op campaign. Not a persistent MMO war.
- **Not Spec Ops: The Line.** Villages, civilians, and morally complex situations exist and are handled with care, but the primary tone is *strategy in a difficult setting*, not a moral-weight piece. We are not making a war crimes simulator.
- **Not a sandbox.** Missions have objectives, escalation curves, time pressure. Skirmish is open-ended; campaign missions are not.
- **Not retro.** Early-2000s RTS aesthetic (Generals, Rome: Total War, Battlefield Vietnam '04) - mid-poly, hand-painted, real lighting. Not PS1, not voxel, not pixel art.
- **Not symmetric.** US and VC play fundamentally different games. We are not making a "VC with re-skinned tanks" faction.
- **Not Company of Heroes meta.** Defense building is rewarded, not just capping points.
- **Not ultra-realistic.** Authentic feel, gameplay-tuned stats.

---

## 6. Faction Asymmetry

This game is *about* the asymmetry of the Vietnam War. The two sides do not play the same game.

| Aspect | US | VC / NVA |
|--------|-----|----------|
| **Logistics** | Trucks on roads, helicopters to LZs, fixed-wing from airstrips. High capacity, visible, vulnerable to interdiction. | Cached supplies (pre-placed or via Ho Chi Minh Trail), porter teams, tunnel storage. Low capacity, hard to spot. |
| **Force Generation** | Reinforcements arrive at firebase LZs over minutes | Spawn from tunnel networks and infiltrate from map edges |
| **Buildings** | Bunkers, wire, sandbags, helipads, airstrips, mortar pits | Tunnel entrances, spider holes, weapon caches, punji traps, sapper staging |
| **Win Condition (Skirmish)** | Hold firebases, clear the AO | Destroy firebases, sustain attrition, survive |
| **Tempo** | Deliberate buildup, then sustained pressure | Strike-and-fade, harassment, occasional all-out offensive |

In MVP: US is the campaign faction. VC is playable in skirmish only. Post-MVP: VC gets campaign missions.

---

## 7. Tone & Period

**Setting:** Fictional US Army battalion (1st Battalion, 7th Cavalry analogue) operating in II Corps Tactical Zone (Pleiku Province, Central Highlands), 1965-1972. Campaign takes place in 1969.

**Tone:** Filmic. Period-authentic. Respectful of the war's weight without sanitizing or wallowing. The game is about *operating* in this conflict, not about morally judging it. Villages, civilians, and ambiguous combat situations exist as mechanics because they were the reality of Vietnam ground operations - they are handled with care, not as the central theme.

**Visual Style:** Early-2000s RTS aesthetic. Mid-poly models with hand-painted textures, real lighting and shadows, readable at strategic zoom. Specific references: C&C Generals (2003), Rome: Total War (2004), Battlefield Vietnam (2004), Joint Operations: Typhoon Rising (2004). Ages well. Achievable as a small team. Not retro slop, not photorealistic.

**Asset Targets:**
- ~1500-3000 tris per unit
- ~512px hand-painted diffuse textures
- Standard diffuse + spec/gloss (PBR overkill)

**Audio:** Era-appropriate radio chatter, M16/AK-47 distinct soundscapes, Huey rotor wash as a recurring motif. Dynamic combat music that ramps with combat intensity. Period-influenced where appropriate, original score for the strategic layer.

---

## 8. Target Audience

### Primary Audience
Players who:
- Love **base building, turtling, and defense maintenance** in RTS games
- Find C&C/Age of Empires **too simple** in the strategic layer
- Find Company of Heroes **too meta-focused** with less rewarding defense building
- Appreciate **Steel Division's scale** but want persistent base construction
- Want to be **rewarded for good defensive construction** - the better you build, the easier defense becomes

### Secondary Audience
- Vietnam War / military history enthusiasts
- Players who enjoy logistics puzzles (Factorio-lite appeal)
- Strategy gamers seeking a unique persistent map experience

---

## 9. Win Conditions

### Campaign Mission Win
Specific objectives complete (varies per mission - clear AO, hold for duration, destroy specific position, etc.)

### Campaign Mission Loss
- Designated command post / main firebase destroyed, OR
- All player forces eliminated, OR
- Total supply collapse for 5+ minutes

### Skirmish (US)
Hold all firebases against escalating waves for duration, OR achieve specified destruction objectives

### Skirmish (VC)
Destroy US firebases, OR sustain attrition victory by depleting US supply over time

---

## 10. Core Gameplay Loop

### Minute-to-Minute
1. **Survey** your AO via satellite view (terrain visible, enemies only when spotted)
2. **Order** engineers to clear jungle or bulldozers to cut roads
3. **Construct** defensive positions within firebase influence radius
4. **Position** squads on patrol routes or defensive positions
5. **Monitor** supply levels via HUD indicators
6. **Respond** to AI Director attacks by repositioning reserves
7. **Request** reinforcements and resupply as needed

### Mission-to-Mission
1. **Complete** mission objectives (time-limited or objective-based)
2. **Survive** AI Director escalation
3. **Preserve** forces (veterancy carries forward in campaign)
4. **Expand** into newly revealed map area
5. **Connect** new firebases to existing supply network

### Control Granularity (Steel Division Approach)
Primarily operational with smart automation, but player CAN micro when needed.

| Situation | Control Level |
|-----------|---------------|
| Firebase defense | Automated (fire at will) |
| Patrol routes | Set and forget (standing orders) |
| Supply runs | Automated within network |
| Offensive operations | Player-directed |
| Emergency response | Player micro when needed |
| High-value units (tanks, gunships) | Direct control available |

---

## 11. Technical Requirements

### Target Specs (Potato-Friendly)
| Setting | Minimum | Recommended |
|---------|---------|-------------|
| GPU | Intel UHD 620 | GTX 1060 / RX 580 |
| CPU | i5-4590 | i5-8400 |
| RAM | 8 GB | 16 GB |
| Storage | 2 GB | 5 GB |

### Performance Targets
- 60 FPS with 300-500 units on recommended specs
- 30 FPS minimum on potato specs
- Efficient spatial hashing for unit queries (SpatialHashGrid)
- LOD system for large battles
- Cell streaming for large maps (TerrainEngine integration)

---

## 12. Edge Cases & Constraints

### Scale Constraints
- Multi-firebase strategic scale (not single-firebase tactical)
- Missions are 45-90+ min
- Map sizes are 2-9 km squared
- Player manages 40-80+ units across multiple positions
- Strategic zoom is mandatory, not optional

### Design Constraints
- Maximum 4-6 firebases active simultaneously
- No barracks/unit production - reinforcements only via convoy/helicopter
- All systems must be faction-parameterized (no hardcoded US assumptions)
- All systems must be designed to scale UP from 2 to N firebases
- Serialization-friendly architecture for save system

---

## Dependencies

This document is the authoritative vision reference. All other GDDs derive requirements from it.

**Systems that implement these pillars:**
- `combat-system.md` - Implements suppression, cover, lethality
- `firebase-system.md` - Implements Pillar 2 (Network of Firebases)
- `supply-logistics.md` - Implements Pillar 3 (Physical Supply Chains)
- `construction-system.md` - Implements building mechanics
- `terrain-clearing.md` - Implements Pillar 1 (Carve the Map)
- `doctrine-system.md` - Implements Pillar 4 (Doctrine Over Spam)
- `ai-director.md` - Implements enemy behavior
- `morale-routing.md` - Implements unit psychology
- `campaign-structure.md` - Implements Pillar 6 (Persistent Expanding Map)

---

## Acceptance Criteria

- [ ] Player can carve roads through jungle with bulldozers
- [ ] Player can clear LZs with engineer det-cord
- [ ] Player can build interconnected firebases with paint/drag perimeter tools
- [ ] Supply flows physically via truck convoys and helicopters
- [ ] Pre-mission doctrine choice locks force composition
- [ ] Reinforcements arrive over minutes, not seconds
- [ ] Firebases auto-defend without micromanagement
- [ ] Patrols and convoys run on standing orders
- [ ] Campaign map persists between missions
- [ ] All construction and terrain changes carry forward
- [ ] US and VC play fundamentally different games
- [ ] 60 FPS with 300-500 units on recommended specs
