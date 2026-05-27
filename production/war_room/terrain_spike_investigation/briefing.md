# WAR ROOM BRIEFING: Terrain Spike Investigation

**Session Date**: 2026-05-26
**Priority**: CRITICAL - Blocking project flow
**Summoner**: User

---

## THE QUERY

Why do terrain spikes keep happening? Compare TerrainEngine (original) project with RealVietnamRTS (integrated) to identify root causes.

## CONTEXT

- **TerrainEngine**: Standalone terrain generation lab at `C:\Users\caleb\TerrainEngine\`
- **RealVietnamRTS**: Full game project at `C:\Users\caleb\RealVietnamRTS\`
- Problem has persisted "for a while" despite multiple attempts to fix

## CONSTRAINTS

1. Must preserve existing game functionality
2. Must maintain 60 FPS with 300-500 units (GAME_BIBLE.md)
3. Must support 3km x 3km maps
4. Must not break vegetation, clearing, or damage systems

## ARCHITECTS SUMMONED

| Architect | Domain |
|-----------|--------|
| technical-director | System architecture, code flow |
| systems-designer | Terrain/heightmap data flow |
| godot-specialist | Godot-specific issues |
| programmer | Implementation details |
| devils-advocate | Edge cases, hidden assumptions |

---

## INITIAL EVIDENCE GATHERED

### File Inventory Comparison

| Component | TerrainEngine | RealVietnamRTS | Status |
|-----------|---------------|----------------|--------|
| terrain_engine.gd | core/ | terrain/core/ | PRESENT (modified) |
| terrain_chunk.gd | core/ | terrain/core/ | PRESENT (modified with spike detection!) |
| terrain_manager.gd | core/ | terrain/core/ | PRESENT (modified) |
| heightmap_storage.gd | core/ | terrain/core/ | PRESENT |
| terrain_mesh.gd | core/ | terrain/core/ | IDENTICAL |
| gameplay_grid.gd | core/ | NOT PRESENT | REPLACED by terrain_grid.gd |
| quality_settings.gd | core/ | terrain/core/ | PRESENT |
| unified_terrain_engine.gd | NOT PRESENT | terrain/core/ | NEW ADDITION |
| terrain_integration.gd | NOT PRESENT | terrain/ | NEW ADDITION |
| terrain_grid.gd | NOT PRESENT | terrain/core/ | NEW ADDITION |
| terrain_types.gd | NOT PRESENT | terrain/ | NEW ADDITION |

### Autoload Configuration (project.godot)

```
TerrainEngine="*res://terrain/core/terrain_engine.gd"
DamageSystem="*res://terrain/systems/damage_system.gd"
ClearingSystem="*res://terrain/systems/clearing_system.gd"
UnifiedTerrain="*res://terrain/core/unified_terrain_engine.gd"   # NEW
TerrainIntegration="*res://terrain/terrain_integration.gd"       # NEW
TerrainClearingSystem="*res://firebase_system/terrain_clearing.gd"  # DUPLICATE?
TerrainFlattening="*res://firebase_system/terrain_flattening.gd"    # NEW
```

### Smoking Gun Evidence

**terrain_chunk.gd (RealVietnamRTS) lines 74-100**:
```gdscript
# Spike detection - find min/max in region data
var min_h: float = INF
var max_h: float = -INF
var spike_count: int = 0
for i in range(region_data.size()):
    var val: float = region_data[i]
    min_h = minf(min_h, val)
    max_h = maxf(max_h, val)
    # Flag values outside expected 0-1 normalized range
    if val < -0.1 or val > 1.1:
        spike_count += 1

if spike_count > 0 or max_h > 1.1 or min_h < -0.1:
    push_warning("[TerrainChunk] Chunk %s has %d spike values! Range: %.3f to %.3f (expected 0-1)" % [
        coord, spike_count, min_h, max_h
    ])

# ... later ...
# Clamp normalized height to prevent spikes from bad data
var normalized_h: float = clampf(region_data[z * data_width + x], 0.0, 1.0)
```

**INTERPRETATION**: Someone already KNEW about spikes and added:
1. Diagnostic detection code
2. Clamping as a band-aid fix

But the **ROOT CAUSE** was never fixed - the clamping just masks the symptom.

---

## HYPOTHESES TO INVESTIGATE

### H1: Multiple Terrain Systems Conflict
- TerrainEngine, UnifiedTerrain, TerrainIntegration all manipulate terrain data
- Race conditions or conflicting writes could cause spikes

### H2: HeightmapStorage Initialization Timing
- If chunks are built before heightmap is fully generated, garbage data
- Async generation + async chunk loading = potential race

### H3: Double-Scaling Bug
- TerrainEngine.get_height_at() multiplies by height_scale
- TerrainChunk.build_mesh() also multiplies by height_scale
- If wrong API is used, heights get doubled (280m becomes 560m -> spikes!)

### H4: River Carving Underflow
- _carve_riverbed() subtracts from heightmap
- If carving below 0.0, negative values = rendering artifacts

### H5: Region Extraction Boundary Bug
- heightmap.extract_region() could access out-of-bounds
- Uninitialized memory read = garbage values

### H6: Modify_terrain() During Chunk Build
- DamageSystem/ClearingSystem modify terrain
- If modification happens during rebuild, partial data = spikes

---

## NEXT STEPS

1. Each Architect examines their domain independently
2. Document findings in analysis/<role>.md
3. Cross-reference hypotheses
4. Identify most likely root cause
5. Propose fix strategy
