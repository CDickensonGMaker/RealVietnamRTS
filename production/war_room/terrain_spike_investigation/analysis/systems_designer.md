# Systems Designer Analysis: Terrain Data Flow

## Executive Summary

**ROOT CAUSE IDENTIFIED**: Multiple interconnected issues in terrain data flow cause spikes. The primary culprit is **unclamped modifier output** in `TerrainEngine.modify_region()`, but there are also data path conflicts between the old and new terrain systems.

---

## Data Flow Diagram

```
TerrainEngine.generate()
    |
    v
TerrainEngine.heightmap_data (normalized 0-1)
    |
    +---> terrain_manager.heightmap.data = duplicate()
    |         |
    |         +---> HeightmapStorage (HAS clamping)
    |         |         |
    |         |         v
    |         |     extract_region() --> TerrainChunk.build_mesh()
    |         |
    |         +---> TerrainGrid.build_from_heightmap()
    |                   |
    |                   v
    |               UnifiedTerrainEngine.init_from_heightmap()
    |
    +---> DamageSystem.apply_damage()
              |
              v
          TerrainEngine.modify_region() <-- BUG: NO CLAMPING!
```

---

## Critical Bug #1: TerrainEngine.modify_region() Lacks Clamping

**File**: `terrain/core/terrain_engine.gd` lines 741-762

```gdscript
func modify_region(center: Vector2i, radius: int, modifier: Callable) -> void:
    # ...
    for y in range(affected.position.y, affected.position.y + affected.size.y):
        for x in range(affected.position.x, affected.position.x + affected.size.x):
            # ...
            heightmap_data[idx] = modifier.call(heightmap_data[idx], falloff)  # <-- NO CLAMP!
```

**Compare to HeightmapStorage.modify_region()** (lines 162-183):
```gdscript
var new_h: float = modifier.call(data[idx], falloff)
if is_nan(new_h) or is_inf(new_h):
    new_h = data[idx]  # Reject NaN/Inf, keep original
data[idx] = clampf(new_h, 0.0, 1.0)  # <-- HAS CLAMP!
```

**Impact**: If any system calls `TerrainEngine.modify_region()` with a modifier that produces values outside 0-1, those values persist and cause spikes.

---

## Critical Bug #2: Two modify_region() Functions Exist

The RealVietnamRTS project has TWO terrain modification APIs:

1. **TerrainEngine.modify_region()** - NO clamping, writes to `heightmap_data`
2. **HeightmapStorage.modify_region()** - HAS clamping, writes to `data`

**Problem**: `terrain_manager.gd` line 142 copies TerrainEngine data to HeightmapStorage:
```gdscript
heightmap.data = terrain_generator.heightmap_data.duplicate()
```

But after the copy, if something modifies `TerrainEngine.heightmap_data`, the HeightmapStorage copy becomes stale!

**Systems that might call the wrong API**:
- DamageSystem
- ClearingSystem
- UnifiedTerrainEngine.modify_terrain()

---

## Critical Bug #3: UnifiedTerrainEngine Creates Third Data Path

**File**: `terrain/core/unified_terrain_engine.gd`

UnifiedTerrainEngine creates its OWN HeightmapStorage reference:
```gdscript
func _init(map_size_meters: float = 3000.0) -> void:
    # ...
    _heightmap = HeightmapStorageClass.new(map_size_meters, HEIGHTMAP_RESOLUTION)
```

Then it can be initialized from an external heightmap:
```gdscript
func init_from_heightmap(heightmap: HeightmapStorageClass) -> void:
    _heightmap = heightmap  # Points to SAME object
```

**Problem**: If someone creates UnifiedTerrainEngine without calling `init_from_heightmap()`, it has its own EMPTY heightmap. Queries to this will return 0 or garbage.

**TerrainIntegration.gd line 50-52**:
```gdscript
unified_terrain = get_node_or_null("/root/UnifiedTerrain")
if unified_terrain:
    print("[TerrainIntegration] UnifiedTerrain autoload found - will use for height queries")
```

If `/root/UnifiedTerrain` exists as an autoload but hasn't been initialized, it returns bad data!

---

## Critical Bug #4: Height Scale Applied Twice

**TerrainEngine.get_height_at()** (line 703-725):
```gdscript
func get_height_at(world_pos: Vector3) -> float:
    # ...
    return lerp(h0, h1, dz) * height_scale  # Multiplies by height_scale (280m)
```

**TerrainChunk.build_mesh()** (line 101):
```gdscript
var h: float = normalized_h * height_scale  # Multiplies by height_scale AGAIN
```

**IF** any code path uses `TerrainEngine.get_height_at()` and passes the result to chunk building expecting normalized values, you get heights of `value * 280 * 280 = value * 78,400`!

This would cause EXTREME spikes - vertices at 78km altitude!

---

## HeightmapStorage Protection Layers

The HeightmapStorage.gd has extensive spike protection that TerrainEngine lacks:

1. **set_cell()** line 65: `data[idx] = clampf(value, 0.0, 1.0)`
2. **sample_world()** lines 73-76: NaN/Inf check with fallback
3. **sample_bilinear()** lines 96-106: NaN checks + clamp on all 4 corners
4. **modify_region()** lines 178-181: NaN/Inf rejection + clamp

**TerrainEngine.gd has NONE of these protections**.

---

## Data Synchronization Problem

**The Problem**:
1. `terrain_manager.generate_terrain()` copies `TerrainEngine.heightmap_data` to `HeightmapStorage.data`
2. Later, damage/clearing modifies terrain
3. Some code calls `TerrainEngine.modify_region()` (no clamp)
4. Some code calls `HeightmapStorage.modify_region()` (has clamp)
5. The two data stores diverge
6. Chunks are rebuilt from HeightmapStorage, but queries might hit TerrainEngine
7. Confusion, spikes, inconsistency

---

## Recommended Fixes (Priority Order)

### Fix 1: Add Clamping to TerrainEngine.modify_region()
```gdscript
var new_h: float = modifier.call(heightmap_data[idx], falloff)
if is_nan(new_h) or is_inf(new_h):
    new_h = heightmap_data[idx]
heightmap_data[idx] = clampf(new_h, 0.0, 1.0)
```

### Fix 2: Consolidate to Single Source of Truth
Either:
- A) Remove TerrainEngine.modify_region(), force all modifications through HeightmapStorage
- B) Add sync mechanism to keep both in sync

### Fix 3: Audit All Callers of modify_region()
Find every place that modifies terrain and ensure they use the safe API.

### Fix 4: Add Validation to UnifiedTerrainEngine
```gdscript
func get_height_at(world_pos: Vector3) -> float:
    if not _heightmap or _heightmap.data.is_empty():
        push_warning("[UnifiedTerrainEngine] Heightmap not initialized!")
        return 0.0
    return _heightmap.sample_world(world_pos.x, world_pos.z)
```

---

## Verification Steps

1. Run with `[DIAG]` print statements enabled
2. Check for any warnings about "spike values" or "outside 0-1 range"
3. Place damage craters and watch for spikes at crater edges
4. Check if spikes appear on chunk boundaries
