# Warno/Wargame Series Terrain and Cover Analysis

## Sources
- [200-Page Guide to Wargame: Red Dragon](https://steamcommunity.com/sharedfiles/filedetails/?id=247884292)
- [Infantry & Armor Pillar Guide](https://suntzuwannabe.wordpress.com/2019/02/03/2-pillar-one-infantry-armor/)
- [WARNO Review](https://strategyandwargaming.com/2024/06/25/warno-review-the-best-game-eugen-has-ever-made/)
- [WARNO Return of RTT King](https://www.matchstickeyes.com/2024/09/01/warno-return-of-the-real-time-tactics-king/)

## Cover System

### Damage Reduction by Terrain Type
| Terrain Type | Damage Reduction | Stealth Rating |
|--------------|------------------|----------------|
| Forest | 40% | Very High |
| Hedgerow | 40% | High |
| Urban Block | 70% | Very High |
| Open Ground | 0% | None |

Infantry are the **only** unit type that receive damage reduction from cover. Vehicles do not.

### Cover Mechanics
1. **Infantry exclusivity** - Only infantry receive cover bonuses
2. **Stacking** - Cover damage reduction stacks with armor/HP
3. **Entrenchment** - Cost to dislodge entrenched infantry exceeds their own cost many times over
4. **Close range advantage** - Infantry force attackers into close range where infantry deal most damage

## Line of Sight System

### Forest LOS Rules
- Deep forest: Complete LOS block ("No line of sight")
- Forest edge (~350m perimeter): Stealthy but visible, can fire freely
- Inside forest: Even recon units need knife-fighting range to spot

### Hedgerow LOS
- Less concealment than forests
- Not visible when zoomed out (hidden terrain feature)
- Good for hiding command vehicles and AA
- Location less predictable than obvious forests

### Breaking LOS
1. **Smoke** - Unconditionally and instantly breaks LOS
2. **Terrain** - Forests, buildings, hills
3. **Pop-and-shoot** - Tank fires from forest edge, reverses to break guided weapon lock

## Urban Combat (WARNO)

### Key Improvements Over Wargame
1. **More buildings** - 30-50 urban blocks vs sparse housing in Wargame
2. **Destroyed buildings** - Rubble still provides infantry cover
3. **Resource drain** - Leveling a position is either impossible or extremely expensive
4. **Block system** - Movement between blocks when spotted

### Tactical Implications
- Urban areas are infantry strongholds
- Artillery effectiveness reduced
- Combined arms essential for urban assault
- Defenders can trade space for time

## Suppression/Morale System

### Training Levels
Training affects:
1. **Suppression recovery** - How fast unit recovers from suppression
2. **Stress tolerance** - How much stress before "routed"
3. **Cohesion** - How much stress before unit cohesion degrades
4. **Combat effectiveness** - Elite beats regular in head-to-head

### Color Coding
- Regular (white) - Standard training
- Trained (yellow) - Above average
- Hardened (orange) - Experienced
- Elite (red) - Best training, highest cost

## Quality of Life Features (WARNO)

1. **LOS Checker** - Preview line of sight before moving
2. **Range Checker** - See unit engagement ranges
3. **Visual Fidelity** - Fully modeled 3D infantry, ballistic trajectories
4. **Dynamic destruction** - Terrain deforms and degrades

## Applicability to RealVietnamRTS

### Immediate Implementation
```gdscript
# Terrain cover modifiers
enum TerrainCover { NONE, HEDGEROW, FOREST, URBAN }

const COVER_DAMAGE_REDUCTION = {
    TerrainCover.NONE: 0.0,
    TerrainCover.HEDGEROW: 0.4,
    TerrainCover.FOREST: 0.4,
    TerrainCover.URBAN: 0.7,
}

const COVER_STEALTH_BONUS = {
    TerrainCover.NONE: 0.0,
    TerrainCover.HEDGEROW: 0.5,
    TerrainCover.FOREST: 0.8,
    TerrainCover.URBAN: 0.9,
}
```

### Vietnam-Specific Adaptations
1. **Triple canopy jungle** - Even higher concealment than forest (95%?)
2. **Rice paddies** - Open but provides concealment when prone
3. **Bamboo thickets** - Similar to hedgerows
4. **Villages** - Urban cover with flammable structures
5. **Bunkers** - 80%+ damage reduction, indestructible by small arms

### LOS Implementation
```gdscript
func check_line_of_sight(from: Vector3, to: Vector3) -> LOSResult:
    var result = LOSResult.new()

    # Raycast for terrain blocking
    var terrain_hit = terrain.raycast_los(from, to)
    if terrain_hit.blocked:
        result.blocked = true
        result.blocker = terrain_hit.terrain_type
        return result

    # Check for concealment even if not blocked
    var concealment = _get_path_concealment(from, to)
    result.concealment = concealment
    result.detection_range = BASE_DETECTION_RANGE * (1.0 - concealment)

    return result
```

### Smoke System
```gdscript
class_name SmokeCloud extends Area3D

var opacity: float = 1.0
var duration: float = 30.0
var decay_rate: float = 0.033  # Fade over 30 seconds

func blocks_los() -> bool:
    return opacity > 0.5

func get_concealment() -> float:
    return opacity
```

## Key Design Takeaways

1. **Cover must matter** - 40-70% damage reduction makes positioning critical
2. **Infantry are kings of terrain** - Only infantry benefit from cover
3. **LOS is tactical** - Breaking sightlines is a valid strategy
4. **Suppression scales with training** - Elite units are more resilient
5. **Urban is a fortress** - Rubble still provides cover
6. **Smoke is powerful** - Instant LOS break is invaluable
