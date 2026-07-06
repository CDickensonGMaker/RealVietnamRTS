# Systems Designer Analysis: Vegetation Pipeline Failure

## Issue #2: Trees Not Showing - ROOT CAUSES IDENTIFIED

### Critical Finding #1: BillboardVegetation is DISABLED

In `terrain/vegetation/billboard_vegetation.gd` line 11:
```gdscript
var enabled: bool = false  # <-- DISABLED BY DEFAULT!
```

This means:
- **No distant trees render** (150-1500m range)
- Only close-range 3D trees from VegetationManager render
- If VegetationManager also fails, you get ZERO trees

### Critical Finding #2: Local Jungle Spawning Commented Out

In `supply_loop_test.gd` lines 147-149:
```gdscript
# Note: VegetationManager already spawns jungle trees via chunks
# Don't spawn additional test trees - they cause "ghost jungle" duplication
# _spawn_jungle_along_route()  # <-- DISABLED!
```

The test scene disabled its own tree spawning, relying entirely on VegetationManager.

### Critical Finding #3: VegetationManager Depends on Chunks

VegetationManager spawns trees via `generate_for_chunk(chunk_key)`. This requires:
1. TerrainManager to generate chunks
2. Chunks to be loaded via `_load_chunk()`
3. Chunk terrain data to exist

**If terrain generation freezes or fails**, no chunks load, so no trees spawn.

### Critical Finding #4: Camera Reference Required

```gdscript
func _process(delta: float) -> void:
    if not _camera:
        return  # <-- EXITS EARLY IF NO CAMERA
```

VegetationManager needs `set_camera()` called. Test scene does this, but timing matters.

### Data Flow

```
TerrainManager.generate_terrain()
  └─> Creates chunks
        └─> VegetationManager.generate_for_chunk()
              └─> Spawns trees per chunk

If generate_terrain() hangs:
  └─> No chunks created
        └─> No generate_for_chunk() calls
              └─> No trees
```

## Verdict: CASCADING FAILURE

Trees don't show because:
1. BillboardVegetation disabled (distant trees)
2. VegetationManager depends on chunks that never load (terrain freeze)
3. Local fallback spawning is commented out

## Recommended Fix

1. Enable BillboardVegetation: `enabled = true`
2. Add fallback tree spawning if chunks fail
3. Fix the terrain freeze (primary cause)
