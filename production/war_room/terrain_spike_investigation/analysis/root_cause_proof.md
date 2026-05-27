# ROOT CAUSE PROOF: Terrain Spikes

**Date**: 2026-05-26
**Status**: PROVEN - Simple fix identified

---

## The Bug: Unit Mismatch

**Both `job_terrain.gd` and `terrain_flattening.gd` pass METERS to modifiers that expect NORMALIZED (0-1) values.**

### Evidence 1: job_terrain.gd:69-75

```gdscript
static func carve_terrain_toward(center: Vector3, radius: float, target_height: float, amount: float, terrain: Node) -> void:
    var modifier := func(h: float, falloff: float) -> float:
        return lerpf(h, target_height, clampf(step * falloff, 0.0, 1.0))
    terrain.modify_terrain(center, radius, modifier)
```

**Problem**:
- `target_height` comes from `get_flatten_target_height()` which calls `terrain.get_height_at()`
- `get_height_at()` returns **METERS** (e.g., 100.0 for 100m elevation)
- But `h` parameter is **NORMALIZED** (0-1 range, e.g., 0.357 for 100m at 280m scale)

**Trace through a real scenario**:
```
h = 0.357 (normalized, representing ~100m terrain)
target_height = 50.0 (METERS - worker trying to flatten to 50m)

lerpf(0.357, 50.0, 0.2) = 0.357 + (50.0 - 0.357) * 0.2
                        = 0.357 + 9.93
                        = 10.28  ← INVALID NORMALIZED VALUE!

HeightmapStorage clamps: clampf(10.28, 0.0, 1.0) = 1.0
Final height: 1.0 * 280m = 280m ← SPIKE!
```

### Evidence 2: terrain_flattening.gd:251-261

```gdscript
var target_h: float = op.target_height  // METERS (from get_height_at)
var modifier := func(current_h: float, falloff: float) -> float:
    var new_h: float = lerpf(current_h, target_h, progress * falloff)
    // "Fix 5" direction clamping - ALSO BROKEN:
    if target_h < current_h:  // Comparing METERS to NORMALIZED!
        new_h = minf(new_h, current_h)
    else:
        new_h = maxf(new_h, current_h)
    return new_h
```

**The "Fix 5" doesn't work** because it compares `target_h` (meters, e.g., 50.0) to `current_h` (normalized, e.g., 0.357):
```
target_h = 50.0 (meters)
current_h = 0.357 (normalized)

target_h < current_h → 50.0 < 0.357 → FALSE
// Goes to else branch, allows the spike!
```

### Evidence 3: Contrast with working code

**unified_terrain_engine.gd:311-323 (flatten_area) - CORRECT**:
```gdscript
var actual_target := target_height  // meters
var normalized_target := actual_target / _heightmap.height_scale  // NORMALIZED!
var modifier := func(h: float, falloff: float) -> float:
    return lerpf(h, normalized_target, falloff)  // Both normalized
```

**damage_system.gd:115-128 (crater_func) - CORRECT**:
```gdscript
var modifier := func(current_height: float, falloff_amount: float) -> float:
    // Uses relative offsets (depth, rim) not absolute targets
    return clampf(current_height - depression + rim, 0.0, 1.0)
```

---

## Why Clamping Creates Spikes

HeightmapStorage.modify_region() line 181:
```gdscript
data[idx] = clampf(new_h, 0.0, 1.0)
```

When the buggy modifier produces values like 10.28 or 50.0, they clamp to **1.0**.
In mesh building: `1.0 * 280m (height_scale)` = **280m spike** at maximum terrain height.

---

## The Fix

**Normalize target_height before using in modifiers.**

### Fix for job_terrain.gd:

```gdscript
static func carve_terrain_toward(center: Vector3, radius: float, target_height: float, amount: float, terrain: Node) -> void:
    if not terrain or not terrain.has_method("modify_terrain"):
        return

    # FIX: Convert target from meters to normalized (0-1)
    var height_scale: float = 280.0
    if "heightmap" in terrain and "height_scale" in terrain.heightmap:
        height_scale = terrain.heightmap.height_scale
    var normalized_target: float = target_height / height_scale

    var step: float = clampf(amount, 0.0, 1.0)
    var modifier := func(h: float, falloff: float) -> float:
        return lerpf(h, normalized_target, clampf(step * falloff, 0.0, 1.0))
    terrain.modify_terrain(center, radius, modifier)
```

### Fix for terrain_flattening.gd:

```gdscript
func _apply_terrain_modification(op: FlatteningOperation) -> void:
    var terrain := _get_terrain_system()
    if not terrain or not terrain.has_method("modify_terrain"):
        return

    var radius := maxf(op.size.x, op.size.y) * 0.5

    # FIX: Convert target from meters to normalized (0-1)
    var height_scale: float = 280.0
    if "heightmap" in terrain and "height_scale" in terrain.heightmap:
        height_scale = terrain.heightmap.height_scale
    var normalized_target: float = op.target_height / height_scale

    var progress: float = op.progress
    var modifier := func(current_h: float, falloff: float) -> float:
        var new_h: float = lerpf(current_h, normalized_target, progress * falloff)
        // Direction clamping now works correctly (both values are normalized)
        if normalized_target < current_h:
            new_h = minf(new_h, current_h)
        else:
            new_h = maxf(new_h, current_h)
        return new_h

    terrain.modify_terrain(op.center, radius, modifier)
```

---

## Impact Assessment

| System | Has Bug? | Spikes From? |
|--------|----------|--------------|
| job_terrain.gd (worker carving) | **YES** | Workers flattening construction sites |
| terrain_flattening.gd (sandbags) | **YES** | Sandbag/structure placement |
| damage_system.gd (craters) | NO | Uses relative offsets, has clamp |
| unified_terrain_engine.gd | NO | Normalizes correctly |
| engineering_system.gd | **POSSIBLY** | Uses local `_get_average_height()` |

---

## Conclusion

**The architectural refactor is NOT needed to fix spikes.**

The root cause is a simple unit mismatch in 2 files:
1. `job_terrain.gd:74` - worker terrain carving
2. `terrain_flattening.gd:254` - sandbag terrain flattening

Both need to normalize `target_height` by dividing by `height_scale` (280.0).

**Estimated fix time**: 30 minutes
**Risk**: Low - localized to modifier functions
**Testing**: Run worker flatten jobs, place sandbags, verify no 280m spikes

---

*The Council has identified the true root cause. This is not architectural debt - it's a unit conversion bug.*
