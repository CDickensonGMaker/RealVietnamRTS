# War Room Briefing: Clearing Test Scene Issues

**Session Date:** 2026-05-26
**Summoner:** User
**Project:** RealVietnamRTS

---

## The Query

Five interconnected issues in the clearing test scene that affect game playability:

1. **TOC Circle Display** - "The TOC circle should go on the ground not around it. And it should be a bit larger of an area, maybe that's a doctrine upgrade."

2. **MG Nest Rotation** - "Wasn't able to rotate freely the direction of the MG nest once I placed it. Should have a 360 spin of choice where we initially place it."

3. **Test Scene Freeze** - "The test scene totally freezes up after just a second. This constant rate of crashing has me really concerned."

4. **Billboard Vegetation Loading** - "Vegetation manager is still loading the 2D billboard sprites into the scene even though we talked about only using the 3D trees."

5. **Unnecessary Loading** - "What else is being loaded into the game state scenes that we might not need?"

---

## Context Gathered

### TOC Building Data (building_data.gd:614-631)
- influence_radius = 150.0 (150m zone for firebase building placement)
- is_hq_building = true (activates firebase)
- can_place_anywhere = true (doesn't require existing firebase)
- No weapon_range or fire_arc - NOT a directional weapon

### MG Nest Building Data (building_data.gd:~410-417)
- fire_arc = 60.0 (60-degree arc, directional)
- weapon_range = 500.0 (500m range)
- This IS a directional weapon, so SHOULD get arc rotation mode

### Clearing Test Terrain Generation (clearing_test.gd:282)
```gdscript
local_terrain.generate_terrain(42)  # SYNCHRONOUS - NO AWAIT!
```
vs test_combined.gd:260:
```gdscript
await local_terrain.generate_terrain(42)  # ASYNC - HAS AWAIT
```

### Billboard Vegetation (billboard_vegetation.gd:10-11)
var enabled: bool = false  # Disabled but node still instantiated
