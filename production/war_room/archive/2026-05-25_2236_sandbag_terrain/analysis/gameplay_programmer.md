# Gameplay Programmer Analysis: VegetationManager Async Loading

**Analyst:** Gameplay Programmer
**Date:** 2026-05-25
**Focus:** GDScript implementation patterns, coroutine strategies, concrete code structure

---

## Executive Summary

The VegetationManager freeze stems from `generate_for_chunk()` being fully synchronous, called 144 times in a tight loop during `load_all_chunks()`. I propose a **coroutine-based incremental materialization system** that mirrors TerrainManager's `_process_rebuild_queue()` pattern but extends it with proper async/await for the initial heavy generation phase.

---

## Root Cause Analysis

### Current Call Flow (Blocking)

```
load_all_chunks() [TerrainManager:418]
  for each of 144 chunks:
    _load_chunk() [TerrainManager:248]
      vegetation_manager.generate_for_chunk() [VegetationManager:262]
        _build_terrain_from_grid()      # ~144 bundle iterations
        _build_placement_cache()        # 5000 RNG calls + dictionary builds
        _materialize_vegetation()       # Transform math for ~800 trees
        _materialize_grass()            # Transform math for ~500 grass patches
```

Total blocking time: ~144 chunks x (~15-30ms per chunk) = **2-4 seconds** of main thread stall.

### Key Insight from TerrainManager

TerrainManager already has a working async pattern at lines 84-97:

```gdscript
func _process_rebuild_queue() -> void:
    if _rebuild_queue.is_empty():
        return

    var start_time := Time.get_ticks_msec()
    while not _rebuild_queue.is_empty():
        if Time.get_ticks_msec() - start_time > REBUILD_BUDGET_MS:
            break  # Continue next frame

        var coord: Vector2i = _rebuild_queue.pop_front()
        _rebuild_chunk_immediate(coord)
```

This pattern works for **rebuilds** but the initial `_load_chunk()` call at line 265 is still synchronous:
```gdscript
vegetation_manager.generate_for_chunk(coord, heightmap, chunk_size)
```

---

## Proposed Solution: Three-Phase Async Generation

### Phase 1: Decouple Generation Request from Completion

VegetationManager needs its own queue and process loop, mirroring TerrainManager.

```gdscript
# New state in VegetationManager
var _generation_queue: Array[Dictionary] = []  # {coord, heightmap, chunk_size}
var _active_generation: Dictionary = {}  # Current work-in-progress
var _materialization_queue: Array[Dictionary] = []  # Post-cache work

const GENERATION_BUDGET_MS := 4.0  # Tight budget for smooth 60 FPS
const MATERIALIZE_BUDGET_MS := 4.0

signal chunk_vegetation_ready(coord: Vector2i)
```

### Phase 2: Split `generate_for_chunk()` into Queued Stages

```gdscript
## Public API - now non-blocking
func generate_for_chunk(chunk_coord: Vector2i, heightmap: Object, chunk_size: float) -> void:
    clear_chunk_visuals(chunk_coord)

    if _meshes.is_empty():
        return

    # Queue instead of immediate execution
    _generation_queue.append({
        "coord": chunk_coord,
        "heightmap": heightmap,
        "chunk_size": chunk_size,
        "stage": "terrain"  # terrain -> cache -> materialize
    })


## Process loop - call from _process()
func _process_generation_queue() -> void:
    if _generation_queue.is_empty() and _materialization_queue.is_empty():
        return

    var start_time := Time.get_ticks_msec()

    # Process terrain and cache building (lighter work)
    while not _generation_queue.is_empty():
        if Time.get_ticks_msec() - start_time > GENERATION_BUDGET_MS:
            return  # Continue next frame

        var work: Dictionary = _generation_queue[0]
        var done := _process_generation_step(work)
        if done:
            _generation_queue.pop_front()
            _materialization_queue.append(work)

    # Process materialization (heavier work - separate budget)
    start_time = Time.get_ticks_msec()
    while not _materialization_queue.is_empty():
        if Time.get_ticks_msec() - start_time > MATERIALIZE_BUDGET_MS:
            return

        var work: Dictionary = _materialization_queue[0]
        var done := _process_materialize_step(work)
        if done:
            _materialization_queue.pop_front()
            chunk_vegetation_ready.emit(work.coord)
```

### Phase 3: Incremental Materialization

The heaviest work is transform buffer building. Split it across frames:

```gdscript
## Process a single generation step, returns true when stage complete
func _process_generation_step(work: Dictionary) -> bool:
    var coord: Vector2i = work.coord
    var heightmap: Object = work.heightmap
    var chunk_size: float = work.chunk_size

    match work.stage:
        "terrain":
            _bundles_per_chunk = int(chunk_size / bundle_meters)
            _build_terrain_from_grid(coord, chunk_size)
            work.stage = "cache"
            return false  # More work to do

        "cache":
            if not _chunk_placements.has(coord):
                _build_placement_cache(coord, heightmap, chunk_size)
            work.stage = "done"
            return true  # Ready for materialization

    return true


## Incremental materialization with cursor tracking
func _process_materialize_step(work: Dictionary) -> bool:
    var coord: Vector2i = work.coord
    var heightmap: Object = work.heightmap

    # Initialize materialization state if needed
    if not work.has("mat_state"):
        work.mat_state = {
            "phase": "trees",  # trees -> grass -> complete
            "tree_cursor": 0,
            "grass_cursor": 0,
            "tree_transforms": {},  # terrain_type -> Array[Transform3D]
            "fallback_transforms": [],
            "grass_transforms": [],
        }

    var state: Dictionary = work.mat_state

    match state.phase:
        "trees":
            var done := _materialize_trees_incremental(coord, heightmap, state)
            if done:
                _finalize_tree_multimeshes(coord, state)
                state.phase = "grass"
            return false

        "grass":
            var done := _materialize_grass_incremental(coord, heightmap, state)
            if done:
                _finalize_grass_multimesh(coord, state)
                state.phase = "complete"
            return false

        "complete":
            return true

    return true


## Process trees in batches
const TREES_PER_FRAME := 200

func _materialize_trees_incremental(coord: Vector2i, heightmap: Object, state: Dictionary) -> bool:
    if not _chunk_placements.has(coord) or not _chunk_terrain.has(coord):
        return true

    var placements: Array = _chunk_placements[coord]
    var terrain: PackedByteArray = _chunk_terrain[coord]
    var cursor: int = state.tree_cursor
    var processed := 0

    while cursor < placements.size() and processed < TREES_PER_FRAME:
        var p: Dictionary = placements[cursor]
        cursor += 1

        if p.type != "tree":
            continue

        processed += 1

        var bundle_idx: int = p.bundle_z * _bundles_per_chunk + p.bundle_x
        if bundle_idx >= terrain.size():
            continue

        var terrain_type: int = terrain[bundle_idx]
        var props: Array = TYPE_PROPS.get(terrain_type, [0.0])
        var tree_chance: float = props[0]

        if tree_chance <= 0.0 or p.accept_roll > tree_chance:
            continue

        var height := heightmap.sample_world(p.world_x, p.world_z) as float

        var t := Transform3D.IDENTITY
        t = t.rotated(Vector3.RIGHT, p.tilt_x)
        t = t.rotated(Vector3.FORWARD, p.tilt_z)
        t = t.rotated(Vector3.UP, p.rot_y)
        t = t.scaled(Vector3.ONE * p.scale)
        t.origin = Vector3(p.world_x, height, p.world_z)

        if _jungle_meshes.has(terrain_type):
            if not state.tree_transforms.has(terrain_type):
                state.tree_transforms[terrain_type] = []
            state.tree_transforms[terrain_type].append(t)
        else:
            state.fallback_transforms.append(t)

    state.tree_cursor = cursor
    return cursor >= placements.size()


## Finalize tree MultiMeshes after incremental building
func _finalize_tree_multimeshes(coord: Vector2i, state: Dictionary) -> void:
    var container := Node3D.new()
    container.name = "Veg_%d_%d" % [coord.x, coord.y]
    add_child(container)
    _chunk_instances[coord] = container

    var total_trees := 0

    # Build MultiMesh for each terrain type
    for terrain_type: int in state.tree_transforms:
        var transforms: Array = state.tree_transforms[terrain_type]
        if transforms.is_empty():
            continue

        var multimesh := _create_multimesh_from_transforms(
            _jungle_meshes[terrain_type], transforms
        )

        var mm_instance := MultiMeshInstance3D.new()
        mm_instance.multimesh = multimesh
        container.add_child(mm_instance)
        total_trees += transforms.size()

    # Build fallback MultiMesh
    if not state.fallback_transforms.is_empty() and not _meshes.is_empty():
        var multimesh := _create_multimesh_from_transforms(
            _meshes[0], state.fallback_transforms
        )
        var mm_instance := MultiMeshInstance3D.new()
        mm_instance.multimesh = multimesh
        container.add_child(mm_instance)
        total_trees += state.fallback_transforms.size()

    print("[VegetationManager] Chunk %s: %d trees materialized (async)" % [coord, total_trees])


## Helper: Create MultiMesh from transform array
func _create_multimesh_from_transforms(mesh: Mesh, transforms: Array) -> MultiMesh:
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = transforms.size()

    var buffer := PackedFloat32Array()
    buffer.resize(transforms.size() * 12)
    for i in transforms.size():
        var xform: Transform3D = transforms[i]
        var b := i * 12
        buffer[b+0] = xform.basis.x.x; buffer[b+1] = xform.basis.y.x
        buffer[b+2] = xform.basis.z.x; buffer[b+3] = xform.origin.x
        buffer[b+4] = xform.basis.x.y; buffer[b+5] = xform.basis.y.y
        buffer[b+6] = xform.basis.z.y; buffer[b+7] = xform.origin.y
        buffer[b+8] = xform.basis.x.z; buffer[b+9] = xform.basis.y.z
        buffer[b+10] = xform.basis.z.z; buffer[b+11] = xform.origin.z
    multimesh.buffer = buffer

    return multimesh
```

---

## Integration with TerrainManager

### Option A: Fire-and-Forget (Recommended for MVP)

TerrainManager calls `generate_for_chunk()` as before, but VegetationManager queues it. TerrainManager does NOT wait for completion.

```gdscript
# In TerrainManager._load_chunk() - line 265
# No change needed! VegetationManager handles async internally
vegetation_manager.generate_for_chunk(coord, heightmap, chunk_size)
```

VegetationManager emits `chunk_vegetation_ready(coord)` when done. Systems that need vegetation can listen.

### Option B: Await Pattern (For Strict Ordering)

If we need chunks to be fully ready before reporting `chunk_loaded`:

```gdscript
# TerrainManager modified _load_chunk (async version)
func _load_chunk_async(coord: Vector2i) -> void:
    loading_chunks.append(coord)

    # ... existing chunk creation code ...

    # Await vegetation
    vegetation_manager.generate_for_chunk(coord, heightmap, chunk_size)
    await vegetation_manager.chunk_vegetation_ready
    # Note: Need to filter by coord in practice

    chunks[coord] = chunk
    loading_chunks.erase(coord)
    chunk_loaded.emit(coord, is_playable)
```

**Complication**: The signal doesn't carry coord, so we'd need a dictionary tracking in-flight awaits. For MVP, Option A is cleaner.

---

## Alternative: Frame-Yield Coroutine Pattern

GDScript coroutines using `await get_tree().process_frame` can spread work without explicit queues:

```gdscript
## Coroutine version - yields every N items
func generate_for_chunk_async(chunk_coord: Vector2i, heightmap: Object, chunk_size: float) -> void:
    clear_chunk_visuals(chunk_coord)

    if _meshes.is_empty():
        return

    _bundles_per_chunk = int(chunk_size / bundle_meters)

    # Build terrain (fast enough to not yield)
    _build_terrain_from_grid(chunk_coord, chunk_size)

    # Build placement cache with yields
    if not _chunk_placements.has(chunk_coord):
        await _build_placement_cache_async(chunk_coord, heightmap, chunk_size)

    # Materialize with yields
    await _materialize_vegetation_async(chunk_coord, heightmap)
    await _materialize_grass_async(chunk_coord, heightmap)

    chunk_vegetation_ready.emit(chunk_coord)


func _build_placement_cache_async(chunk_coord: Vector2i, heightmap: Object, chunk_size: float) -> void:
    var placements: Array = []
    # ... setup code ...

    var yield_counter := 0
    const YIELD_INTERVAL := 500

    for i in TREE_CANDIDATES_PER_CHUNK:
        # ... existing placement logic ...
        placements.append({...})

        yield_counter += 1
        if yield_counter >= YIELD_INTERVAL:
            yield_counter = 0
            await get_tree().process_frame

    # ... grass candidates with similar yielding ...

    _chunk_placements[chunk_coord] = placements
```

### Coroutine Pros/Cons

**Pros:**
- Simpler mental model - linear code flow
- No explicit queue management
- Automatic frame spreading

**Cons:**
- Less control over exact time budget
- Multiple concurrent calls create interleaved execution (may confuse ordering)
- Harder to prioritize camera-near chunks

---

## Recommended Implementation Order

1. **Immediate (30 min)**: Add `_generation_queue` and `_process_generation_queue()` to VegetationManager's `_process()`.

2. **Split generate_for_chunk (1 hr)**: Make it queue work instead of blocking.

3. **Incremental materialization (2 hr)**: Split `_materialize_vegetation()` with cursor tracking.

4. **Grass materialization (30 min)**: Same pattern for grass.

5. **Signal emission (15 min)**: Add `chunk_vegetation_ready` signal.

6. **Priority queue (optional, 1 hr)**: Sort queue by distance to camera for near-first loading.

---

## Performance Budget Tuning

```gdscript
# Conservative for 60 FPS (16.67ms frame budget)
const GENERATION_BUDGET_MS := 4.0   # Light work (terrain, cache)
const MATERIALIZE_BUDGET_MS := 4.0  # Heavy work (transforms)
# Total: 8ms for vegetation, leaving 8.67ms for everything else

# Aggressive for faster loading (may drop frames)
const GENERATION_BUDGET_MS := 8.0
const MATERIALIZE_BUDGET_MS := 8.0
# Total: 16ms - will drop some frames but loads faster
```

Consider making these configurable or adaptive based on current frame time.

---

## Test Plan

1. **Freeze test**: Load main scene, verify no freeze during `load_all_chunks()`
2. **Visual test**: Verify all 144 chunks eventually have vegetation
3. **Ordering test**: Verify near-camera chunks render vegetation first (if priority implemented)
4. **Clearing test**: Verify `clear_area()` still works correctly with async system
5. **Performance test**: Profile with 300+ units, verify 60 FPS maintained

---

## Files to Modify

| File | Changes |
|------|---------|
| `vegetation_manager.gd` | Add queue, split generation, incremental materialization |
| `terrain_manager.gd` | (Optional) await pattern if strict ordering needed |

---

## Summary

The fix requires transforming VegetationManager from a synchronous generator into an async state machine with:

1. Work queue (mirrors TerrainManager's rebuild queue)
2. Staged processing (terrain -> cache -> materialize)
3. Incremental materialization with cursor tracking
4. Time budgets to maintain 60 FPS
5. Completion signal for dependent systems

Total estimated implementation time: **4-5 hours**

This approach is minimally invasive to TerrainManager and follows established patterns already in the codebase.
