# Vegetation Density Sync Fix

## Problem Statement

`ClearingSystem.vegetation_map` starts at 1.0 (full jungle) everywhere and only reduces when clearing zones are created. This is disconnected from `VegetationManager` which knows the actual terrain types (CLEAR, GRASSLAND, LIGHT_JUNGLE, etc.).

**Result:** Units think they're blocked everywhere outside cleared zones, even in areas with no actual trees. Path clearing triggers on "phantom jungle."

## Goal

Sync `ClearingSystem.vegetation_map` with `VegetationManager`'s terrain type data so path blocking only triggers where actual vegetation exists.

## Scope

**Files to modify:**
1. `terrain/systems/clearing_system.gd`
2. `terrain/vegetation/vegetation_manager.gd`

**Files NOT modified:**
- `terrain/terrain_integration.gd` (no API changes)
- `firebase_system/builder_ai.gd` (path clearing logic unchanged)
- Any test scenes or other systems

## Implementation

### Step 1: Add density lookup to VegetationManager

Add a method to VegetationManager that returns vegetation density (0.0-1.0) based on terrain type at a world position:

```gdscript
# In vegetation_manager.gd

## Get vegetation density at world position based on terrain type
## Returns 0.0 (clear) to 1.0 (heavy jungle)
func get_density_at(world_pos: Vector3, chunk_size: float) -> float:
    var terrain_type: int = get_terrain_type_at(world_pos, chunk_size)

    # Map terrain types to density values
    match terrain_type:
        TerrainType.CLEAR:
            return 0.0
        TerrainType.RICE_PADDY:
            return 0.0  # No trees in paddies
        TerrainType.GRASSLAND:
            return 0.1  # Very sparse
        TerrainType.LIGHT_JUNGLE:
            return 0.35
        TerrainType.MEDIUM_JUNGLE:
            return 0.6
        TerrainType.HEAVY_JUNGLE:
            return 0.9
        _:
            return 0.5  # Default moderate
```

### Step 2: Update ClearingSystem.get_vegetation_density()

Modify `get_vegetation_density()` to check BOTH the clearing zones AND the actual terrain type:

```gdscript
# In clearing_system.gd

## Reference to vegetation manager (set during init)
var vegetation_manager: Node = null

func set_vegetation_manager(veg_mgr: Node) -> void:
    vegetation_manager = veg_mgr

## Get vegetation density at world position (0-1)
## Now checks both clearing zones AND actual terrain type
func get_vegetation_density(world_pos: Vector3) -> float:
    if not terrain_manager:
        return 1.0

    # First check the clearing map (zones that have been actively cleared)
    var scale: float = float(vegetation_size) / terrain_manager.map_size
    var x: int = clampi(int(world_pos.x * scale), 0, vegetation_size - 1)
    var y: int = clampi(int(world_pos.z * scale), 0, vegetation_size - 1)
    var cleared_density: float = vegetation_map.get_pixel(x, y).r

    # If this area has been actively cleared, use that value
    if cleared_density < 0.9:
        return cleared_density

    # Otherwise, check actual terrain type from VegetationManager
    if vegetation_manager and vegetation_manager.has_method("get_density_at"):
        var chunk_size: float = terrain_manager.chunk_size if terrain_manager else 256.0
        return vegetation_manager.get_density_at(world_pos, chunk_size)

    # Fallback to clearing map value
    return cleared_density
```

### Step 3: Wire up VegetationManager reference in TerrainIntegration

In `_create_terrain_systems()`, pass vegetation_manager to clearing_system:

```gdscript
# In terrain_integration.gd, inside _create_terrain_systems()

# Add after existing wiring (around line 87):
if clearing_system.has_method("set_vegetation_manager"):
    clearing_system.set_vegetation_manager(vegetation_manager)
```

## Behavior After Fix

| Location | Before Fix | After Fix |
|----------|------------|-----------|
| Cleared zone | Density from clearing_map | Density from clearing_map (unchanged) |
| Heavy jungle (not cleared) | 1.0 (always blocked) | 0.9 (blocked - has actual trees) |
| Grassland (not cleared) | 1.0 (wrongly blocked) | 0.1 (not blocked - sparse) |
| Clear terrain | 1.0 (wrongly blocked) | 0.0 (not blocked - no trees) |
| Rice paddy | 1.0 (wrongly blocked) | 0.0 (not blocked - no trees) |

## Path Clearing Threshold

`BuilderAI._check_path_blocked()` uses density > 0.3 as the blocking threshold.

After this fix:
- CLEAR, RICE_PADDY, GRASSLAND (0.0 - 0.1): **Not blocked** - units walk through
- LIGHT_JUNGLE (0.35): **Blocked** - units clear path
- MEDIUM_JUNGLE (0.6): **Blocked** - units clear path
- HEAVY_JUNGLE (0.9): **Blocked** - units clear path

This matches reality: units only stop to clear actual jungle, not open ground.

## Testing

1. Run construction test scene
2. Assign clearing job in jungle area
3. Verify units path toward job, only stopping to clear where actual trees exist
4. Verify units in grassland/clear areas move freely without path clearing

## Risk Assessment

**Low risk** - This change:
- Only affects the density lookup, not clearing mechanics
- Preserves existing clearing zone behavior
- Uses existing VegetationManager data (no new generation)
- Falls back gracefully if vegetation_manager is null
