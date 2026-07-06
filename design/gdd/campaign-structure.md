# Campaign Structure GDD

> **Status**: `[LIVING]`
> **Last Updated**: 2026-05-21
> **Source Documents**: GAME_BIBLE.md D-305, PRD.md Section 14
> **Pillar**: 6 (Persistent Expanding Map)

---

## 1. Overview

The campaign is the core differentiator of RealVietnamRTS. It uses a **single persistent map** that expands with each mission. Mission 1 starts with a small playable area (~100m x 100m). Each subsequent mission reveals and unlocks a larger section of the same map. All terrain modifications persist - roads, cleared jungle, craters, firebase fortifications. By the final mission, you have an interconnected network of everything you built across the entire campaign.

---

## 2. Player Fantasy

You watch your campaign unfold on a single map. Mission 1's small firebase becomes the anchor of Mission 5's network. The road you cut in Mission 2 is still there in Mission 8, now part of a larger supply network. When you zoom out on the final mission, you see the entire history of your campaign written on the terrain - every decision, every construction, every cleared path. The map IS the story.

---

## 3. Detailed Rules

### 3.1 Map Expansion Progression

| Mission | Playable Area | Cumulative | New Features Introduced |
|---------|---------------|------------|------------------------|
| 1 | ~100m x 100m | 100m x 100m | Basic construction, first firebase |
| 2 | ~200m x 200m | 300m x 300m | Road cutting, supply convoys |
| 3 | ~300m x 300m | 600m x 600m | Second firebase, helicopter ops |
| 4 | ~400m x 400m | 1km x 1km | Night cycle, mortar support |
| 5 | ~500m x 500m | 1.5km x 1.5km | Third firebase, tunnel clearing |
| 6 | ~500m x 500m | 2km x 2km | Full combined arms |
| 7 | ~500m x 500m | 2.5km x 2.5km | Advanced tactics |
| 8-10 | Variable | 3km x 3km (full) | Final defensive/offensive objectives |

### 3.2 Persistence Rules

Everything carries forward between missions:

| Element | Persistence | Notes |
|---------|-------------|-------|
| Terrain clearing | Full | Roads, LZs, clearings remain |
| Craters | Full | Bomb/artillery damage persists |
| Buildings | Full | Firebases, bunkers, all structures |
| Roads | Full | Supply network preserved |
| Unit veterancy | Full | Experience carries forward |
| Unit KIA | Permanent | Lost soldiers don't return |
| Supply stockpiles | Partial | Reduced between missions |
| Firebase levels | Full | Upgrades preserved |

### 3.3 Mission Structure

Each mission has:

1. **Briefing**: Map overview, objectives, new area preview
2. **Objectives**: Specific goals (clear area, destroy target, hold position)
3. **Time Limit**: Some missions have time pressure, others are "hold for X days"
4. **Map Expansion Trigger**: Completing objectives reveals new playable area
5. **Debriefing**: Casualty report, progress summary, next mission preview

### 3.4 Victory/Loss Conditions

**Mission Victory:**
- Complete primary objectives within time limit (if any)
- Survive day count (for "hold" missions)

**Mission Failure:**
- All firebases fall (all HQ buildings destroyed)
- Primary objective failed (time expires)
- Total supply collapse for 5+ minutes
- Return to checkpoint (see Save System)

**Campaign Victory:**
- Complete all 8-10 missions
- Final mission: Combined defensive and offensive objectives

### 3.5 New Area Mechanics

When new area is revealed:
1. Fog of war lifts from terrain
2. New area starts as JUNGLE (must be cleared)
3. Enemy positions may exist in new area
4. New objectives become available
5. Supply network must be extended

### 3.6 Inter-Mission Events

Between missions:
- **Time skip**: 1-7 in-game days pass
- **Supply refresh**: Partial resupply from rear depot
- **Reinforcement window**: Replace casualties before next mission
- **Enemy reinforcement**: VC/NVA also rebuild
- **Narrative beat**: Light framing text or briefing

---

## 4. Campaign Missions

### Mission 1: "Establish Firebase Alpha"
**Setting:** Pleiku Province, II Corps, late 1965
**Playable Area:** 100m x 100m
**Objectives:**
1. Establish Firebase Alpha at designated hilltop
2. Construct basic defensive perimeter
3. Survive first VC probing attack

**New Mechanics Introduced:**
- Basic construction (sandbags, wire, bunker)
- Engineer commands
- Squad movement and positioning

**Enemy Forces:** Light VC infantry probes

---

### Mission 2: "Cut the Road"
**Playable Area:** Expands to 300m x 300m
**Objectives:**
1. Cut road from Firebase Alpha to rear depot
2. Establish supply convoy route
3. Defend convoy from ambush

**New Mechanics Introduced:**
- Bulldozer road cutting
- Supply convoy system
- Ambush mechanics

**Enemy Forces:** VC ambush teams, mortar harassment

---

### Mission 3: "Firebase Bravo"
**Playable Area:** Expands to 600m x 600m
**Objectives:**
1. Establish Firebase Bravo at forward position
2. Connect Bravo to Alpha via road
3. Establish helicopter resupply

**New Mechanics Introduced:**
- Second firebase
- Helicopter operations
- Firebase networking

**Enemy Forces:** Coordinated VC attacks on both firebases

---

### Mission 4: "Night Watch"
**Playable Area:** Expands to 1km x 1km
**Objectives:**
1. Survive 2 full day/night cycles
2. Repel night attack
3. Establish mortar support

**New Mechanics Introduced:**
- Day/night cycle (if implemented)
- Night attack mechanics
- Mortar fire support

**Enemy Forces:** Night assault, sapper infiltration

---

### Mission 5: "Tunnel Rats"
**Playable Area:** Expands to 1.5km x 1.5km
**Objectives:**
1. Locate and destroy tunnel network
2. Establish third firebase
3. Clear AO of tunnel entrances

**New Mechanics Introduced:**
- Tunnel discovery mechanics
- Tunnel destruction
- Third firebase management

**Enemy Forces:** Tunnel-based spawn system fully active

---

### Missions 6-10: Escalation
Progressive escalation toward final objectives with full combined arms, maximum enemy intensity, and complete map control.

---

## 5. Formulas

### 5.1 Casualty Replacement (Inter-Mission)

```gdscript
const REPLACEMENT_RATE := 0.5  # 50% of casualties replaced

func calculate_replacements(casualties: Dictionary) -> Dictionary:
    var replacements := {}
    for unit_type in casualties:
        var lost := casualties[unit_type]
        var replaced := int(lost * REPLACEMENT_RATE)
        replacements[unit_type] = replaced
    return replacements
```

### 5.2 Supply Refresh

```gdscript
const INTER_MISSION_SUPPLY := 0.75  # Restore to 75% capacity

func refresh_supply() -> void:
    for firebase in active_firebases:
        var depot := firebase.supply_depot
        depot.current = max(depot.current, depot.max * INTER_MISSION_SUPPLY)
```

### 5.3 Enemy Rebuild

```gdscript
func rebuild_enemy_forces(days_passed: int) -> void:
    var rebuild_rate := 0.1 * days_passed  # 10% per day
    enemy_strength = min(enemy_strength + rebuild_rate, 1.0)
```

---

## 6. Edge Cases

### 6.1 Total Firebase Loss
- If all firebases destroyed in Mission N, reload from checkpoint
- Player keeps progress up to last autosave
- Cannot proceed with 0 firebases

### 6.2 Resource Depletion
- If supply collapses for 5+ minutes, mission fails
- Must maintain at least one connected supply route

### 6.3 Unit Loss Cascade
- If too many units lost, mission may become unwinnable
- Game provides warning before critical threshold
- Reload option always available

### 6.4 Building Destruction
- Destroyed buildings stay destroyed between missions
- Can rebuild in next mission at supply cost
- Ruins remain as terrain features

---

## 7. Dependencies

| System | Dependency Type | Notes |
|--------|-----------------|-------|
| **All Gameplay Systems** | Required | Campaign ties everything together |
| **Save System** | Required | Persistence requires serialization |
| **Terrain Clearing** | Required | Terrain state persists |
| **Firebase System** | Required | Firebase state persists |
| **AI Director** | Required | Escalation per mission |

---

## 8. Tuning Knobs

| Parameter | Default | Range | Notes |
|-----------|---------|-------|-------|
| `total_missions` | 10 | 8-12 | Campaign length |
| `mission_1_area` | 100m | 50-150m | Starting playable area |
| `area_expansion_rate` | 200m | 100-400m | Per mission expansion |
| `casualty_replacement_rate` | 0.5 | 0.3-0.7 | % casualties replaced |
| `inter_mission_supply` | 0.75 | 0.5-0.9 | Supply refresh % |
| `enemy_rebuild_rate` | 0.1/day | 0.05-0.2 | Enemy strength recovery |

---

## 9. Acceptance Criteria

### Map Persistence
- [ ] Terrain clearing state persists between missions
- [ ] Roads built in Mission N visible in Mission N+1
- [ ] Buildings persist between missions
- [ ] Craters and damage persist

### Map Expansion
- [ ] Each mission reveals new playable area
- [ ] Previously accessible area remains accessible
- [ ] Fog of war covers unexplored new area
- [ ] New area starts as jungle terrain

### Unit Persistence
- [ ] Unit veterancy carries forward
- [ ] Casualties are permanent
- [ ] Partial replacement between missions
- [ ] Unit composition reflects previous losses

### Mission Progression
- [ ] Clear objectives for each mission
- [ ] New mechanics introduced progressively
- [ ] Difficulty escalates through campaign
- [ ] Final mission tests all systems

### Narrative
- [ ] Mission briefings provide context
- [ ] Debriefings summarize results
- [ ] Map visually tells campaign story
- [ ] Player progress is visible on terrain

---

## Campaign Setting

**Year:** 1969
**Location:** Pleiku Province, II Corps Tactical Zone, Central Highlands
**Unit:** Fictional 1st Battalion, 7th Cavalry analogue
**Starting Doctrine:** Air Cavalry (player can switch for later missions)

**Narrative Approach:** Light framing. Briefings set historical context but no named characters or plot. The story is told through the map - you see your progress in the terrain itself.
