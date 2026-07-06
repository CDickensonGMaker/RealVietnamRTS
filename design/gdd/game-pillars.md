# The Six Pillars - Quick Reference

> **Status**: `[LOCKED]`
> **Last Updated**: 2026-05-21
> **Purpose**: Wall-friendly quick reference for design decisions

---

## Purpose

This document is a **quick reference for the development wall**. Print it. Tape it up. Every feature, every mechanic, every line of code must serve at least one pillar.

**The Rule**: If a feature does not serve a pillar, it does not go in the game.

---

## Quick Decision Checklist

Before implementing ANY feature, answer these questions:

```
[ ] Which pillar(s) does this serve? ________________
[ ] Is it in the MVP roster?
[ ] Is it faction-parameterized?
[ ] Does it scale to N firebases?
[ ] Is it in the Explicit Exclusions list?

If the first checkbox is empty: STOP. Do not implement.
```

---

## The Six Pillars

---

### Pillar 1: Carve the Map

**One-Line Summary**: Terrain is opaque until you make it legible.

#### Detailed Description

The battlespace is not given to you - you carve it. Dense jungle blocks sight, movement, and construction. Hills and rivers create natural chokepoints. Every cleared meter is vision, mobility, and supply. The map is a first-class entity: terrain matters, height matters, every river crossing and ridgeline shapes the campaign.

You don't just fight on the map. You fight *with* the map. The jungle is your enemy until you cut it back. Then it becomes your ally - providing concealment for your perimeter while giving you clear fields of fire.

#### Key Mechanics That Implement This Pillar

| Mechanic | System | Description |
|----------|--------|-------------|
| **Bulldozer road cutting** | Terrain Clearing | D7 Caterpillars carve roads through hills |
| **Engineer det-cord clearing** | Terrain Clearing | Engineers clear jungle pockets and LZs |
| **Progressive clearing states** | Terrain Clearing | JUNGLE -> PARTIALLY_CLEARED -> CLEARED -> FORTIFIED |
| **Heightmap terrain** | TerrainEngine | Real elevation affects LOS and movement |
| **Fog of War** | Vision System | Terrain visible, units only when spotted |
| **River crossings** | Map Design | Natural chokepoints requiring engineering |

#### What This Pillar PREVENTS (Anti-Patterns)

- **Pre-cleared maps**: No starting with open terrain. You earn visibility.
- **Instant clearing**: Clearing takes time and resources. No magic "reveal all."
- **Flat terrain**: If height doesn't matter, you're not carving.
- **Cosmetic vegetation**: If jungle doesn't block LOS and movement, it's not jungle.
- **Terrain as backdrop**: The map must be an active strategic element.

#### Acceptance Test

**The game delivers this pillar if...**
- A player who doesn't clear jungle cannot see, move, or build effectively
- Clearing a hilltop provides measurable tactical advantage (extended LOS)
- Road networks that players build are required for supply chains to function
- Players make meaningful choices about *where* to clear
- Clearing time is measured in minutes, not seconds

#### Cross-References

| Document | Section |
|----------|---------|
| `terrain-clearing.md` | Primary system GDD |
| `construction-system.md` | Cleared terrain requirements |
| `supply-logistics.md` | Road network dependencies |

---

### Pillar 2: Network of Firebases

**One-Line Summary**: Build interlocking forward positions, each your own design.

#### Detailed Description

You build a network of mutually supporting firebases (max 4-6 active), each with its own LZ and road link to the supply network. Each firebase has an HQ building that defines an influence radius for logistics distribution. You place every sandbag and bunker yourself with paint/drag perimeter tools.

Engineers auto-construct inside established zones; you direct them manually for forward bunker complexes outside the wire. No two firebases look the same. The firebase is *your* design - and you live or die by the choices you made building it.

#### Key Mechanics That Implement This Pillar

| Mechanic | System | Description |
|----------|--------|-------------|
| **Paint/drag perimeter tools** | Construction | Free-form defensive line placement |
| **HQ influence radius** | Firebase | Logistics distribution zone |
| **Firebase levels** | Firebase | PATROL_BASE (4 slots) -> FIRE_SUPPORT_BASE (8) -> MAJOR_FIREBASE (12) |
| **Auto-construction zones** | Construction | Engineers work autonomously inside perimeter |
| **Manual construction outside wire** | Construction | Player directs forward positions |
| **LZ requirements** | Helicopter | Every firebase needs landing capability |
| **Road connections** | Supply | Physical links between firebases |
| **Interlocking fields of fire** | Combat | Firebases must support each other |

#### What This Pillar PREVENTS (Anti-Patterns)

- **Prefab bases**: No pre-designed firebase templates. You build it.
- **Unlimited firebases**: Network complexity must be manageable (4-6 max).
- **Isolated outposts**: Firebases without road/LZ links are dead firebases.
- **Copy-paste defenses**: If all your firebases look the same, you're not thinking.
- **Instant construction**: Building takes time and engineer resources.
- **Single-firebase gameplay**: The game is about the *network*, not one position.

#### Acceptance Test

**The game delivers this pillar if...**
- Players spend significant time designing firebase layouts
- A poorly designed firebase demonstrably fails under attack
- Supply flows only within firebase influence radius
- Players agonize over where to place their limited firebases
- Experienced players can identify their firebases by layout alone
- Firebase B can provide fire support to Firebase A during attack

#### Cross-References

| Document | Section |
|----------|---------|
| `firebase-system.md` | Primary system GDD |
| `construction-system.md` | Building mechanics |
| `supply-logistics.md` | Firebase influence and distribution |
| `helicopter-system.md` | LZ requirements |

---

### Pillar 3: Physical Supply Chains

**One-Line Summary**: Supply is spatial, not abstract. Cut the road, kill the firebase.

#### Detailed Description

Trucks on roads, helicopters between LZs, fixed-wing from captured airstrips. Supply is *physical* - it exists in the world, moves through space, and can be attacked. Ambush a convoy, crater a runway, interdict a road - supply chains are vulnerable.

A firebase isolated from supply is a firebase that dies slowly. Ammo runs out. Fuel runs out. Men don't get rotated. Wounded don't get evacuated. The US wins by abundance; the VC wins by cutting that abundance off.

#### Key Mechanics That Implement This Pillar

| Mechanic | System | Description |
|----------|--------|-------------|
| **Truck convoys** | Supply Logistics | Ground supply on road networks |
| **Helicopter resupply** | Helicopter | Air supply between LZs |
| **Fixed-wing logistics** | Supply Logistics | Strategic supply from airstrips |
| **Road interdiction** | Combat | Destroy/ambush convoys |
| **LZ interdiction** | Combat | AA fire prevents helicopter supply |
| **Runway cratering** | Terrain Damage | Artillery/bombing disables airstrips |
| **Supply decay** | Unit Resources | Units consume ammo, fuel, water |
| **Cached supplies (VC)** | Supply Logistics | Pre-placed, hidden, limited capacity |
| **Porter teams (VC)** | Supply Logistics | Slow but hard to interdict |

#### What This Pillar PREVENTS (Anti-Patterns)

- **Abstract supply points**: No "you have 500 supply, spend it." Supply is trucks.
- **Instant resupply**: Supply moves at truck/helicopter speed.
- **Invulnerable logistics**: If supply can't be attacked, it's not physical.
- **Global resource pools**: Supply exists at firebases, not in a global bank.
- **Magic ammo**: Units without supply lines run out of ammunition.
- **Symmetric logistics**: US and VC supply systems must play differently.

#### Acceptance Test

**The game delivers this pillar if...**
- Players can see supply trucks moving on roads
- Destroying a supply convoy causes measurable harm to a firebase
- A firebase cut off from supply degrades over 5+ minutes
- Players make tactical decisions about convoy routes and timing
- VC players can win by sustained supply interdiction alone
- US helicopter resupply is faster but more vulnerable to AA

#### Cross-References

| Document | Section |
|----------|---------|
| `supply-logistics.md` | Primary system GDD |
| `firebase-system.md` | Distribution zones |
| `helicopter-system.md` | Air resupply missions |
| `construction-system.md` | Supply depot buildings |

---

### Pillar 4: Doctrine Over Spam

**One-Line Summary**: Pre-mission commitment locks your playstyle. No instant-buy reinforcements.

#### Detailed Description

Before the mission, you choose a doctrine that commits you to a playstyle. Air Cavalry means infantry plus helicopters with limited ground vehicles. Mechanized means more armor but fewer helicopters. Your choice shapes everything.

Reinforcements arrive by helicopter or convoy in real time - minutes, not seconds. Lose a tank and you wait for the next convoy. Lose your supply line and you don't get reinforcements at all. Force *preservation* matters more than force *production*.

There are no barracks. There is no rally point spitting units. There is only what you brought and what the rear echelon can send you.

#### Key Mechanics That Implement This Pillar

| Mechanic | System | Description |
|----------|--------|-------------|
| **Pre-mission deck** | Doctrine | Force composition locked before mission start |
| **Doctrine types** | Doctrine | Air Cav, Mechanized, Infantry-Heavy, etc. |
| **Reinforcement timing** | Reinforcement | 3-12 minutes per unit type |
| **Helicopter delivery** | Reinforcement | Fast but exposed to AA |
| **Convoy delivery** | Reinforcement | Slower but higher capacity |
| **Veterancy persistence** | Campaign | Experienced units are precious |
| **No barracks** | — | You cannot produce units mid-mission |
| **Supply-gated reinforcement** | Supply | Can't reinforce without supply line |

**Reinforcement Timing Reference:**

| Unit Type | Arrival Time |
|-----------|--------------|
| Rifle Squad | 3 minutes |
| Engineer Squad | 4 minutes |
| Weapons Squad | 5 minutes |
| Recon Team | 3 minutes |
| M48 Patton | 12 minutes |
| Huey Transport | 6 minutes |

#### What This Pillar PREVENTS (Anti-Patterns)

- **Rapid unit production**: No spamming infantry from barracks.
- **Instant reinforcement**: Reinforcements take real time to arrive.
- **Mid-mission doctrine switching**: You're committed to your choices.
- **Disposable units**: Every unit lost is painful to replace.
- **Economy-based scaling**: No "build more factories for faster units."
- **Symmetric force composition**: Doctrine choices create unique armies.

#### Acceptance Test

**The game delivers this pillar if...**
- Players spend time in pre-mission deck building
- Losing a tank is a significant setback (12-minute wait)
- Different doctrine choices produce visibly different gameplay
- Players feel the weight of reinforcement decisions
- A cut supply line means no reinforcements, period
- Veteran units are treated as precious resources

#### Cross-References

| Document | Section |
|----------|---------|
| `doctrine-system.md` | Primary system GDD |
| `reinforcement-system.md` | Delivery mechanics |
| `supply-logistics.md` | Reinforcement prerequisites |
| `campaign-structure.md` | Veterancy persistence |

---

### Pillar 5: The War Continues

**One-Line Summary**: You command the operation, not babysit individuals. The battle runs while you're looking away.

#### Detailed Description

Patrols run on standing orders. Defenses fire at will automatically. Convoys run schedules. Engineers auto-build in zones. You command the *operation*; you don't babysit individuals.

Long missions (45-90+ minutes) reward planning over reflexes. The game runs whether you're watching that sector or not. If you've built a good defense, it holds without your attention. If you've set up good patrol routes, they run without your micromanagement.

You are a battalion commander, not a squad leader. Act like it.

#### Key Mechanics That Implement This Pillar

| Mechanic | System | Description |
|----------|--------|-------------|
| **Patrol standing orders** | Combat | Units follow assigned routes indefinitely |
| **Fire-at-will automation** | Combat | Defensive positions engage automatically |
| **Convoy scheduling** | Supply | Supply runs without manual triggers |
| **Auto-construction zones** | Construction | Engineers build autonomously in zones |
| **Strategic zoom** | Camera | SupCom-style zoom for operational view |
| **Long mission timers** | Mission | 45-90+ minute missions |
| **Alert/notification system** | UI | Significant events surface to player |
| **Control granularity** | Combat | Auto by default, micro when needed |

**Control Granularity Reference:**

| Situation | Control Level |
|-----------|---------------|
| Firebase defense | Automated (fire at will) |
| Patrol routes | Set and forget (standing orders) |
| Supply runs | Automated within network |
| Offensive operations | Player-directed |
| Emergency response | Player micro when needed |
| High-value units | Direct control available |

#### What This Pillar PREVENTS (Anti-Patterns)

- **Constant micromanagement**: If players must watch every unit, the game fails.
- **Twitch reflexes rewarded**: Planning beats APM.
- **Pause-dependent gameplay**: Game should flow at operational pace.
- **Sector amnesia**: Firebases you're not watching should not collapse.
- **Short mission loops**: 10-minute missions don't test logistics.
- **Manual everything**: Automation is the default, not the exception.

#### Acceptance Test

**The game delivers this pillar if...**
- Players can look away from a firebase for 5 minutes without it collapsing
- Patrol routes execute without player input
- A well-designed defense repels a probe without player intervention
- Strategic zoom is used more than tactical zoom
- Players feel like commanders, not squad leaders
- Mission length supports supply/reinforcement timing mechanics

#### Cross-References

| Document | Section |
|----------|---------|
| `combat-system.md` | Automation rules |
| `morale-routing.md` | Autonomous morale behavior |
| `ai-director.md` | Pacing for long missions |
| `supply-logistics.md` | Convoy automation |

---

### Pillar 6: Persistent Expanding Map

**One-Line Summary**: The campaign map grows and everything you build carries forward.

#### Detailed Description

The campaign uses a **single persistent map** that expands with each mission. Mission 1 starts with approximately 100m of playable area. Each subsequent mission reveals and unlocks a larger section of the same map.

All terrain modifications persist - roads, cleared jungle, craters, firebase fortifications. All constructed bases persist. By mission 8-10, you have an interconnected network of everything you built across the entire campaign. The final mission reveals the complete 3km x 3km map with all prior work visible.

Your decisions in mission 2 affect your options in mission 8. That road you cut through the ridge? Still there. That firebase you built on the hill? Still yours - or was it overrun?

#### Key Mechanics That Implement This Pillar

| Mechanic | System | Description |
|----------|--------|-------------|
| **Progressive map reveal** | Campaign | 100m -> 3km over campaign |
| **Terrain persistence** | Save System | Roads, clearing, craters save |
| **Building persistence** | Save System | Firebases and fortifications save |
| **Unit persistence** | Campaign | Veterancy carries forward |
| **Damage persistence** | Campaign | Battle damage visible in later missions |
| **Network expansion** | Campaign | Each mission connects to prior work |
| **Strategic layer** | Campaign | Choose which sector to push next |

**Campaign Progression Reference:**

| Mission | Playable Area | Map % |
|---------|---------------|-------|
| 1 | ~100m radius | ~5% |
| 2-3 | ~300m radius | ~10% |
| 4-5 | ~600m radius | ~25% |
| 6-7 | ~1km radius | ~50% |
| 8-9 | ~2km radius | ~75% |
| 10 (Final) | Full 3km x 3km | 100% |

#### What This Pillar PREVENTS (Anti-Patterns)

- **Isolated missions**: No throwaway maps that reset.
- **Start-from-scratch**: Prior work must carry forward.
- **Consequence-free decisions**: Early mistakes haunt late game.
- **Linear mission order**: Player choice in expansion direction.
- **Cosmetic persistence**: Persistence must have gameplay impact.
- **Fresh resources each mission**: You inherit what you built.

#### Acceptance Test

**The game delivers this pillar if...**
- A road built in mission 2 is visible and usable in mission 8
- Players feel the weight of early firebase placement decisions
- The final mission shows the entire network players built
- Players can choose which direction to expand
- A firebase lost in mission 5 is absent (or ruined) in mission 6
- Veteran units are recognizable across missions

#### Cross-References

| Document | Section |
|----------|---------|
| `campaign-structure.md` | Primary system GDD |
| `firebase-system.md` | Persistence requirements |
| `terrain-clearing.md` | Terrain modification persistence |
| `construction-system.md` | Building serialization |

---

## Rejected Features (Did Not Serve Pillars)

The following features were considered and rejected for failing the pillar test:

| Rejected Feature | Why Rejected | Pillar Violation |
|------------------|--------------|------------------|
| **Instant barracks production** | Units should come from off-map, not be produced | Violates Pillar 4 |
| **Global resource pool** | Supply must be physical and local | Violates Pillar 3 |
| **Pre-cleared starting areas** | Players must carve their own space | Violates Pillar 1 |
| **Auto-layout firebases** | Every firebase must be player-designed | Violates Pillar 2 |
| **Pause-and-command gameplay** | War continues; automation handles routine | Violates Pillar 5 |
| **Episode-style standalone missions** | Campaign must be persistent and expanding | Violates Pillar 6 |
| **Symmetric VC faction** | VC plays a fundamentally different game | Violates all pillars |
| **Quick-save mid-mission** | No save-scumming; decisions have weight | Violates Pillar 6 |
| **Unit rally points** | No production, therefore no rally points | Violates Pillar 4 |
| **Abstract supply numbers** | You must see the trucks | Violates Pillar 3 |
| **Cosmetic terrain** | Terrain must block, channel, and matter | Violates Pillar 1 |
| **10-minute missions** | Logistics needs time to matter | Violates Pillars 3, 4, 5 |

---

## Feature Rejection Protocol

When someone proposes a feature:

1. **Ask**: "Which pillar does this serve?"
2. If the answer is vague: "How specifically does this serve Pillar X?"
3. If no clear pillar connection: **Reject the feature.**
4. If it contradicts a pillar: **Reject immediately.**
5. Document rejection in the table above.

**It is easier to cut features than to add them later. When in doubt, cut.**

---

## Pillar Priority in Conflicts

When two pillars seem to conflict, use this priority:

1. **Pillar 3: Physical Supply Chains** - Supply is the core differentiator
2. **Pillar 2: Network of Firebases** - Base building is the core loop
3. **Pillar 1: Carve the Map** - Terrain shapes everything
4. **Pillar 5: The War Continues** - Automation enables scale
5. **Pillar 4: Doctrine Over Spam** - Force structure enables stakes
6. **Pillar 6: Persistent Expanding Map** - Campaign requires other systems

**Example**: If automation (Pillar 5) would make supply trivial (Pillar 3), supply wins. Supply convoys still need player routing decisions.

---

## Summary Table

| # | Pillar | One-Liner | Core System |
|---|--------|-----------|-------------|
| 1 | Carve the Map | Terrain opaque until cleared | `terrain-clearing.md` |
| 2 | Network of Firebases | Build interlocking positions | `firebase-system.md` |
| 3 | Physical Supply Chains | Supply is spatial and attackable | `supply-logistics.md` |
| 4 | Doctrine Over Spam | Pre-mission commitment, slow reinforcement | `doctrine-system.md` |
| 5 | The War Continues | Automation, standing orders, long missions | `combat-system.md` |
| 6 | Persistent Expanding Map | Campaign map grows and persists | `campaign-structure.md` |

---

## Print This Page

Cut along the dotted line. Tape to wall.

```
-----------------------------------------------------------------
|  BEFORE IMPLEMENTING ANY FEATURE, ASK:                        |
|                                                               |
|  [ ] Does it CARVE THE MAP?                                   |
|  [ ] Does it build the FIREBASE NETWORK?                      |
|  [ ] Does it make SUPPLY PHYSICAL?                            |
|  [ ] Does it enforce DOCTRINE OVER SPAM?                      |
|  [ ] Does it let THE WAR CONTINUE without babysitting?        |
|  [ ] Does it support the PERSISTENT EXPANDING MAP?            |
|                                                               |
|  If NONE are checked: DO NOT IMPLEMENT.                       |
-----------------------------------------------------------------
```

---

## Dependencies

This document extracts and expands content from:
- `game-concept.md` - Source of pillar definitions
- `GAME_BIBLE.md` - Authoritative decision log

This document is referenced by:
- All system GDDs (pillar justification required)
- `systems-index.md` - Pillar mapping to systems
- Sprint planning (pillar coverage check)
