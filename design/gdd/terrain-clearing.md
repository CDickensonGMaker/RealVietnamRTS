# Terrain Clearing System GDD

> **Status**: `[LIVING]`
> **Last Updated**: 2026-05-21
> **Source Documents**: GAME_BIBLE.md D-103, D-304
> **Pillar**: 1 (Carve the Map)

---

## 1. Overview

The terrain clearing system implements Pillar 1: Carve the Map. The battlespace starts opaque - dense jungle that blocks vision, slows movement, and prevents construction. Players use bulldozers for large-scale clearing and road cutting, and engineer det-cord for tactical jungle pockets and LZ preparation. Every cleared meter is vision, mobility, and supply capability gained.

---

## 2. Player Fantasy

You're carving civilization out of the jungle. Watch bulldozers grind forward, pushing through undergrowth as your road takes shape. See engineers plant det-cord and blow a clearing for an LZ. The map transforms as you play - what was impenetrable green becomes your firebase, your road network, your supply lines. The jungle is the first enemy you defeat.

---

## 3. Detailed Rules

### 3.1 Terrain States

| State | Code | Vision | Movement | Construction | Visual |
|-------|------|--------|----------|--------------|--------|
| JUNGLE | 0 | Blocked | 50% speed | None | Dense canopy |
| PARTIALLY_CLEARED | 1 | Reduced | 75% speed | Basic only | Broken vegetation |
| CLEARED | 2 | Normal | 100% speed | All buildings | Open ground |
| FORTIFIED | 3 | Normal | 100% speed | All + bonus | Improved defensive |

### 3.2 Clearing Tools

| Tool | Operator | Area Size | Speed | Best For |
|------|----------|-----------|-------|----------|
| **Bulldozer** | D7 vehicle | Large (10m wide) | Fast | Roads, large clearings |
| **Engineer Det-cord** | Engineer squad | Small (5m radius) | Slow | LZs, fire lanes, precise work |

### 3.3 Bulldozer Operations

Bulldozers are specialized vehicles for terrain modification:

| Operation | Time | Width | Notes |
|-----------|------|-------|-------|
| Road cutting | 90 sec/100m | 10m | Creates road-grade terrain |
| Large clearing | 30 sec | 10m radius | For firebase footprints |
| Jungle push | Continuous | 10m | Clears while moving |

**Bulldozer Constraints:**
- Cannot traverse steep slopes (>30 degrees)
- Vulnerable while operating (no combat capability)
- Requires road access to reach work site (or very slow off-road)
- Single operator - losing bulldozer is costly

### 3.4 Engineer Det-Cord Operations

Engineers use explosive det-cord for precise clearing:

| Operation | Time | Size | Notes |
|-----------|------|------|-------|
| Jungle pocket | 60 sec | 5m radius | Precise clearing |
| LZ preparation | 90 sec | 15m radius | Landing zone size |
| Fire lane | 45 sec | 3m x 20m | Defensive sightlines |

**Engineer Constraints:**
- Squad of 8 works together
- Mediocre combat capability during clearing
- Can work on slopes bulldozer cannot reach
- Multiple squads can clear simultaneously

### 3.5 Progressive Clearing

Terrain doesn't jump directly to CLEARED:

```
JUNGLE → PARTIALLY_CLEARED → CLEARED → FORTIFIED

Time for each transition:
- JUNGLE → PARTIALLY: 40% of total clear time
- PARTIALLY → CLEARED: 60% of total clear time
- CLEARED → FORTIFIED: Requires construction (see Firebase System)
```

### 3.6 Vegetation and Cover

Clearing affects more than just pathability:

| State | Infantry Cover | Vehicle Cover | Concealment |
|-------|----------------|---------------|-------------|
| JUNGLE | 25% (light) | 0% (impassable) | Full |
| PARTIALLY_CLEARED | 15% | 0% | Partial |
| CLEARED | 0% | 0% | None |
| FORTIFIED | 0% (use structures) | 0% | None |

---

## 4. Formulas

### 4.1 Clearing Progress

```gdscript
const BULLDOZER_CLEAR_RATE := 10.0  # sq meters per second
const ENGINEER_CLEAR_RATE := 2.0    # sq meters per second per engineer

func update_clearing(delta: float) -> void:
    var rate := 0.0
    if active_bulldozer:
        rate = BULLDOZER_CLEAR_RATE
    else:
        rate = ENGINEER_CLEAR_RATE * engineer_count

    clearing_progress += rate * delta

    var area := PI * clearing_radius * clearing_radius
    var percent := clearing_progress / area

    if percent >= 0.4 and terrain_state == TerrainState.JUNGLE:
        set_terrain_state(TerrainState.PARTIALLY_CLEARED)
    elif percent >= 1.0:
        set_terrain_state(TerrainState.CLEARED)
```

### 4.2 Road Cutting

```gdscript
const ROAD_WIDTH := 10.0  # meters
const ROAD_CLEAR_RATE := 1.0  # meters per second

func update_road_cutting(delta: float) -> void:
    var distance_cleared := ROAD_CLEAR_RATE * delta
    road_progress += distance_cleared

    # Clear terrain along road path
    var cells_to_clear := get_cells_along_road(
        road_start,
        road_start.direction_to(road_end) * road_progress,
        ROAD_WIDTH
    )

    for cell in cells_to_clear:
        cell.set_state(TerrainState.CLEARED)
```

### 4.3 Movement Speed Modifier

```gdscript
func get_movement_speed_modifier(terrain_state: TerrainState) -> float:
    match terrain_state:
        TerrainState.JUNGLE:
            return 0.5
        TerrainState.PARTIALLY_CLEARED:
            return 0.75
        TerrainState.CLEARED, TerrainState.FORTIFIED:
            return 1.0
    return 1.0
```

---

## 5. Edge Cases

### 5.1 Clearing Under Fire
- Bulldozers stop when taking fire (no operator protection)
- Engineers stop when suppressed (see Construction System)
- Progress is preserved when resuming

### 5.2 Bulldozer Destruction
- Lost bulldozer must be reinforced (12+ minute wait)
- Engineers can still clear but much slower
- Partial roads remain passable

### 5.3 Slopes and Terrain
- Bulldozers cannot clear steep slopes (>30 degrees)
- Engineers can work on any slope
- Roads follow terrain contours (player draws path)

### 5.4 Rivers and Water
- Cannot clear water terrain
- Must find fords or build bridges (post-MVP)
- Rivers permanently block bulldozer paths

### 5.5 Regrowth (Post-MVP)
- Jungle regrowth over abandoned clearings
- Not implemented for MVP
- Cleared terrain stays cleared

### 5.6 Craters
- Explosions (mortars, artillery) create craters
- Craters persist as terrain modification
- Craters block road passage until repaired

---

## 6. Dependencies

| System | Dependency Type | Notes |
|--------|-----------------|-------|
| **TerrainEngine** | Required | Chunk-based terrain modification |
| **Construction System** | Consumer | Building requires cleared terrain |
| **Combat System** | Required | Suppression stops clearing |
| **Pathfinding** | Consumer | Cleared terrain changes nav costs |
| **Vegetation System** | Consumer | Clearing removes vegetation |
| **Firebase System** | Consumer | Firebase requires cleared terrain |

---

## 7. Tuning Knobs

| Parameter | Default | Range | Notes |
|-----------|---------|-------|-------|
| `bulldozer_clear_rate` | 10 m²/sec | 5-20 | Bulldozer clearing speed |
| `engineer_clear_rate` | 2 m²/sec | 1-4 | Per-engineer clearing speed |
| `road_cut_rate` | 1 m/sec | 0.5-2.0 | Road cutting speed |
| `road_width` | 10m | 8-15 | Width of cut roads |
| `jungle_movement_penalty` | 0.5 | 0.3-0.6 | Speed in jungle |
| `partial_movement_penalty` | 0.75 | 0.6-0.85 | Speed in partial clearing |
| `max_bulldozer_slope` | 30 deg | 20-40 | Slope limit for bulldozers |

---

## 8. Acceptance Criteria

### Core Functionality
- [ ] Jungle terrain blocks vision and slows movement
- [ ] Bulldozers can cut roads through jungle
- [ ] Engineers can clear jungle pockets with det-cord
- [ ] Terrain state transitions: JUNGLE → PARTIALLY_CLEARED → CLEARED

### Bulldozer Operations
- [ ] Bulldozer clears wide path (10m) while moving
- [ ] Road cutting creates passable road terrain
- [ ] Bulldozer cannot traverse steep slopes
- [ ] Bulldozer is vulnerable while operating

### Engineer Operations
- [ ] Engineer squad clears 5m radius area
- [ ] Det-cord clearing takes ~60 seconds
- [ ] Engineers can clear slopes bulldozers cannot
- [ ] Engineers stop clearing when suppressed

### Visual Feedback
- [ ] Jungle, partially cleared, and cleared terrain visually distinct
- [ ] Clearing progress visible (vegetation disappearing)
- [ ] Roads clearly visible on terrain
- [ ] Craters visible as terrain damage

### Integration
- [ ] Cleared terrain required for building placement
- [ ] Roads improve vehicle movement speed
- [ ] Clearing affects pathfinding costs
- [ ] Vegetation LOD respects clearing state

---

## Technical Implementation

### TerrainEngine Integration

The clearing system integrates with the existing TerrainEngine:

```gdscript
# Clearing modifies terrain chunks
func clear_area(center: Vector3, radius: float) -> void:
    var affected_chunks := terrain_engine.get_chunks_in_radius(center, radius)
    for chunk in affected_chunks:
        var cells := chunk.get_cells_in_radius(center, radius)
        for cell in cells:
            cell.clearing_progress += clearing_amount
            if cell.clearing_progress >= CLEAR_THRESHOLD:
                cell.state = TerrainState.CLEARED
                chunk.update_vegetation()
                chunk.update_navmesh()
```

### Persistence (Campaign)

Cleared terrain persists across missions:
- Save terrain state per chunk
- Load terrain state on mission start
- Roads and clearings carry forward

---

## Historical Context

Terrain clearing was critical in Vietnam operations:
- **Rome Plows**: Massive D7 bulldozers with special blades cleared jungle
- **LZ Preparation**: Engineers used explosives to create helicopter landing zones
- **Fire lanes**: Cleared sightlines around firebases for defensive fire
- **Road building**: Critical for supply convoys, constantly attacked
