# ADR-0001: Terrain Chunk Streaming

## Status
Accepted

## Context

RealVietnamRTS requires a terrain system capable of supporting the game's ambitious scope:

- **Map Size**: 3km x 3km persistent expanding maps (Pillar 6)
- **Performance Target**: 60 FPS with 300-500 active units
- **Memory Budget**: ~4GB RAM target for recommended specs
- **Terrain Modification**: Terrain must be clearable and modifiable in real-time (Pillar 1: Carve the Map)
- **State Persistence**: Terrain states (JUNGLE, PARTIALLY_CLEARED, CLEARED, FORTIFIED) must persist across missions

A monolithic terrain approach would exceed memory constraints and fail to meet performance targets. The terrain system must efficiently manage a large playable area while supporting real-time modification for jungle clearing, road cutting, and crater formation.

### Constraints

1. Godot 4.6's rendering pipeline requires careful batching to minimize draw calls
2. Terrain modification affects multiple systems: navigation, vegetation, vision, construction
3. Campaign persistence requires efficient serialization of terrain state
4. The expanding map design (100m initial -> full 3km by mission 8-10) needs progressive loading

## Decision

Implement a **32x32m cell-based terrain chunk streaming system** with the following architecture:

### Cell Structure
- **Cell Size**: 32m x 32m (approximately 1024 m^2 per cell)
- **Grid Dimensions**: 94 x 94 cells for full 3km map
- **Total Cells**: 8,836 potential cells at full expansion

### Streaming Strategy
- **Load Distance**: Chunks loaded based on camera distance (configurable per LOD tier)
- **Unload Distance**: Chunks unloaded when camera moves beyond threshold + hysteresis buffer
- **Async Loading**: Resource loading on worker threads to prevent frame stalls
- **Priority Queue**: Cells closest to camera center load first

### Per-Chunk Ownership
Each chunk independently manages:
- Terrain mesh and heightmap data
- Vegetation instances (trees, grass, undergrowth)
- Collision shapes for physics
- Navigation mesh region
- Terrain state per-cell (4-state enum)
- Clearing progress per-cell (float 0.0-1.0)

### Chunk State Machine
```
UNLOADED -> LOADING -> LOADED -> ACTIVE
                                    |
                                    v
                               UNLOADING -> UNLOADED
```

### Memory Budget Breakdown
| Component | Per Chunk | Max Active (20x20) | Total |
|-----------|-----------|---------------------|-------|
| Heightmap | 16 KB | 400 | 6.4 MB |
| Mesh | 64 KB | 400 | 25.6 MB |
| Vegetation | 128 KB | 400 | 51.2 MB |
| Collision | 32 KB | 400 | 12.8 MB |
| NavMesh | 48 KB | 400 | 19.2 MB |
| State Data | 4 KB | 400 | 1.6 MB |
| **Total** | **292 KB** | **400** | **~117 MB** |

With 400 active chunks (640m x 640m visible area), terrain uses ~117 MB, well within budget.

## Consequences

### Positive

1. **Memory Efficient**: Only visible terrain loaded; 3km map uses same memory as 640m view
2. **Scalable Map Size**: Architecture supports arbitrarily large maps without memory explosion
3. **Progressive Loading**: Pairs naturally with campaign's expanding map design
4. **Isolated Modification**: Clearing/cratering only affects single chunks; localized mesh rebuilds
5. **Parallel Processing**: Independent chunks enable multi-threaded loading and mesh generation
6. **Clean Serialization**: Each chunk saves independently; campaign persistence is straightforward
7. **LOD-Ready**: Chunk system enables per-chunk LOD without refactoring

### Negative

1. **Chunk Boundary Seams**: Height and texture seams require stitching logic at chunk edges
2. **Cross-Chunk Pathfinding**: Navigation queries spanning chunks need NavMesh region linking
3. **Async Complexity**: Loading state machine adds code complexity; race conditions must be handled
4. **Pop-in Potential**: Fast camera movement may outpace loading; mitigation strategies needed
5. **Vegetation Continuity**: Trees/grass near boundaries may have visible discontinuities
6. **Memory Fragmentation**: Frequent load/unload cycles may fragment heap over long sessions

### Mitigations

| Risk | Mitigation |
|------|------------|
| Seams | Overlap heightmap edges by 1 vertex; blend normals at boundaries |
| Pathfinding | Use Godot's NavigationRegion3D linking; pre-compute inter-chunk connections |
| Pop-in | Predictive loading based on camera velocity; LOD fade-in transitions |
| Vegetation discontinuity | Seed vegetation RNG by world position, not chunk index |
| Fragmentation | Use object pooling for chunk resources; periodic defrag during loading screens |

## ADR Dependencies

**None** - This is a foundational architecture decision.

Downstream decisions that depend on this ADR:
- Vegetation system design (vegetation-lod.md)
- Navigation mesh architecture
- Terrain clearing implementation
- Campaign persistence format

## Engine Compatibility

**Godot 4.6**

| Godot Feature | Usage |
|---------------|-------|
| `Thread` / `WorkerThreadPool` | Async chunk loading without main thread stalls |
| `Resource` system | Chunk data as resources for clean load/save |
| `NavigationRegion3D` | Per-chunk nav regions with edge linking |
| `MultiMeshInstance3D` | Efficient vegetation instancing per chunk |
| `ArrayMesh` / `SurfaceTool` | Dynamic terrain mesh generation |
| `CollisionShape3D` / `ConcavePolygonShape3D` | Per-chunk collision |

No GDExtension required; pure GDScript implementation viable for MVP.

## GDD Requirements Addressed

| GDD | Requirement | How Addressed |
|-----|-------------|---------------|
| `terrain-clearing.md` | Chunk-based terrain modification | Per-chunk state tracking; localized mesh/navmesh rebuilds |
| `terrain-clearing.md` | TerrainEngine integration | Chunk system provides the `get_chunks_in_radius()` API |
| `terrain-clearing.md` | Campaign persistence | Independent chunk serialization |
| `game-concept.md` | Pillar 1 (Carve the Map) | Terrain states per cell; clearing progress tracking |
| `game-concept.md` | Pillar 6 (Persistent Expanding Map) | Progressive chunk revelation; state persistence |
| `game-concept.md` | 60 FPS with 300-500 units | Memory-efficient streaming keeps terrain budget low |
| `game-concept.md` | 3km x 3km map support | Streaming architecture enables large maps |

## Implementation Notes

### File Structure
```
map_maker/
  terrain_chunk.gd         # Individual chunk class
  chunk_streamer.gd        # Streaming manager
  chunk_loader.gd          # Async loading worker
  terrain_state.gd         # Per-cell state enum and data
  vietnam_terrain.gd       # Main terrain interface
  vietnam_cell.gd          # Cell data structures
  vietnam_world_grid.gd    # World-to-chunk coordinate mapping
```

### Key Interfaces

```gdscript
# ChunkStreamer API
func get_chunks_in_radius(center: Vector3, radius: float) -> Array[TerrainChunk]
func request_chunk_load(chunk_coords: Vector2i) -> void
func get_chunk_at_world_pos(world_pos: Vector3) -> TerrainChunk

# TerrainChunk API
func get_terrain_state(local_pos: Vector2) -> TerrainState
func set_terrain_state(local_pos: Vector2, state: TerrainState) -> void
func update_vegetation() -> void
func update_navmesh() -> void
func serialize() -> Dictionary
func deserialize(data: Dictionary) -> void
```

### Performance Monitoring

Track these metrics during development:
- Chunk load time (target: < 50ms per chunk)
- Active chunk count vs. memory usage
- NavMesh rebuild time after clearing
- Frame time during rapid camera movement

## References

- CLAUDE.md: Performance Targets section
- CLAUDE.md: Key Directories - map_maker/
- GAME_BIBLE.md: Decision D-103 (terrain engine architecture)
- terrain-clearing.md: TerrainEngine Integration section
- game-concept.md: Technical Requirements section
