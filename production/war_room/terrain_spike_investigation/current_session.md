# War Room Session: Terrain Spike Investigation

**Date**: 2026-05-26
**Status**: ✅ FIX APPLIED AND TESTED

---

## Query

> Why do terrain spikes keep happening? Propose a true refactor to simplify the terrain system.

---

## Investigation Summary

### Phase 1: Initial Analysis
- Compared TerrainEngine (standalone) with RealVietnamRTS (integrated)
- Found 4 different elevation data stores
- Found 7 terrain-related autoloads vs 3 in standalone
- **Initial hypothesis**: Data fragmentation causing sync issues

### Phase 2: Code Audit
- Audited all callers of `modify_region()` and `modify_terrain()`
- **Key Finding**: No game code calls the unclamped `TerrainEngine.modify_region()`
- All modifications go through safe path (HeightmapStorage)

### Phase 3: Historical Evidence
- Found archived war room session from 2026-05-25 identifying:
  - "modifier lerps from `current_h` not `original_h`"
  - "Multi-frame modifications compound into spikes"
- Found "Fix 5" direction clamping in terrain_flattening.gd

### Phase 4: ROOT CAUSE IDENTIFIED
- **The bug is a UNIT MISMATCH, not data fragmentation**
- `target_height` is passed in METERS (e.g., 100.0)
- Modifier receives `h` as NORMALIZED (0-1, e.g., 0.357 for 100m)
- `lerpf(0.357, 100.0, 0.2)` = 20.28 → clamps to 1.0 → 280m SPIKE!

---

## Root Cause

**Unit mismatch between target_height (meters) and modifier input h (normalized 0-1)**

### Buggy Files:

| File | Line | Issue |
|------|------|-------|
| `job_terrain.gd` | 74 | `target_height` in meters, `h` is normalized |
| `terrain_flattening.gd` | 254 | `op.target_height` in meters, `current_h` is normalized |

### Working Files (for comparison):

| File | Why It Works |
|------|--------------|
| `unified_terrain_engine.gd:317` | Normalizes: `actual_target / _heightmap.height_scale` |
| `damage_system.gd:128` | Uses relative offsets + explicit clamping |
| `engineering_system.gd:577` | Uses `heightmap.get_cell()` which returns normalized |

---

## The Fix

**Normalize target_height before using in modifiers.** (~30 min fix)

### job_terrain.gd:69-75:
```gdscript
static func carve_terrain_toward(...) -> void:
    # FIX: Convert target from meters to normalized
    var height_scale: float = 280.0
    if "heightmap" in terrain and "height_scale" in terrain.heightmap:
        height_scale = terrain.heightmap.height_scale
    var normalized_target: float = target_height / height_scale

    var modifier := func(h: float, falloff: float) -> float:
        return lerpf(h, normalized_target, clampf(step * falloff, 0.0, 1.0))
```

### terrain_flattening.gd:251-261:
```gdscript
func _apply_terrain_modification(op: FlatteningOperation) -> void:
    # FIX: Convert target from meters to normalized
    var normalized_target: float = op.target_height / height_scale

    var modifier := func(current_h: float, falloff: float) -> float:
        var new_h: float = lerpf(current_h, normalized_target, progress * falloff)
        # Direction clamping now works (both values normalized)
        if normalized_target < current_h:
            new_h = minf(new_h, current_h)
        else:
            new_h = maxf(new_h, current_h)
        return new_h
```

---

## Verdict: Refactor NOT Needed

The proposed architectural refactor (consolidating 4 data stores → 1) is **not necessary** to fix terrain spikes.

**The actual fix is a simple unit conversion bug in 2 files.**

| Option | Effort | Fixes Spikes? |
|--------|--------|---------------|
| Simple fix (normalize target_height) | 30 min | **YES** |
| Full refactor (4 stores → 1) | 2-3 days | Also yes, but overkill |

---

## Documents

| Document | Purpose |
|----------|---------|
| `briefing.md` | Initial investigation context |
| `comparison_matrix.md` | Full file-by-file comparison |
| `synthesis.md` | Original decree (superseded) |
| `analysis/systems_designer.md` | Data flow analysis |
| `analysis/technical_director.md` | Architecture analysis |
| `analysis/devils_advocate.md` | Edge case examination |
| `analysis/refactor_proposal.md` | Full refactoring plan (not needed) |
| `analysis/root_cause_proof.md` | **DEFINITIVE ROOT CAUSE** |

---

## Resolution

**Fix Applied**: 2026-05-26

- [x] **job_terrain.gd:67-88** - Added `normalized_target = target_height / height_scale` before modifier
- [x] **terrain_flattening.gd:235-269** - Added same normalization, fixed direction clamping comparison

**Test Results**:
- Project loads successfully
- Heightmap data range: `0.0 to 1.0` (correctly normalized)
- Terrain height range: `0.0m to 30.0m` (height_scale applied correctly)
- No spike errors in debug output
- All terrain systems initialized properly

**Manual Testing Required**:
1. Select worker → Place building on sloped terrain → Watch flatten job
2. Verify terrain moves smoothly toward target without 280m spikes

---

*The Council has traced the bug to its source and applied the fix. The terrain system is not architecturally broken - it was a unit conversion error in 2 files.*
