# Why This Folder Was Archived

## Date: 2026-05-13

## Reason
This folder contained an alternative terrain generation system that was superseded by the TerrainEngine integration in `terrain/`.

## What Was Here
- `vietnam_terrain.gd` - Procedural terrain generation
- `vietnam_cell.gd` - Cell-based terrain data
- `vietnam_world_grid.gd` - Campaign map grid (locations preserved in battle_system/data/vietnam_locations.gd)
- `cell_streamer.gd` - LOD streaming system
- `river_generator.gd` - River generation (duplicate of terrain/water/river_generator.gd)
- `trail_network.gd` - Ho Chi Minh Trail network
- `village_placer.gd` - Village placement
- `terrain_clearing_mesh.gd` - Clearing visualization

## Conflicts Resolved
- `class_name RiverGenerator` was duplicated in both this folder and `terrain/water/`
- The `terrain/` folder (TerrainEngine) is now the single source of truth for terrain

## What Was Preserved
- Vietnam location presets were extracted to `battle_system/data/vietnam_locations.gd`

## If You Need This Code
This code may still be useful for reference. If you need to re-integrate any features, check the corresponding `terrain/` implementation first.
