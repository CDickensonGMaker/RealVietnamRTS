# ⛧ ACTIVE COUNCIL SESSION ⛧

## The Matter: Road System + Automated Bulldozer Clearing

## Stage: Deliberating

## The Query
> Verify implementation plan for road terrain fixes, dirt road texture, and automated bulldozer dispatch for supply chain road clearing.

## Architects Present
- ▸ systems-designer (Supply chain architecture, JobSystem)
- ▸ gameplay-programmer (WorkerController, bulldozer behavior)
- ▸ technical-artist (Road rendering, terrain height, textures)
- ▸ devil-advocate (Risks, assumptions, edge cases)

## The Ritual Progresses
- [x] Phase 1: The Summoning
- [x] Phase 2: Individual Sight
- [ ] Phase 3: The Debate
- [ ] Phase 4: The Weaving
- [ ] Phase 5: The Decree

## The Plan Under Review

### Change 1: Road Terrain Fix
- HEIGHT_OFFSET: 0.05m → 0.12m across all road renderers
- Files: road_decal_renderer.gd, terrain_spline.gd, road_segment_node.gd

### Change 2: Dirt Road Texture
- Add texture loading to `_setup_material()` in road_decal_renderer.gd
- New asset: assets/textures/terrain/dirt_road.png (512x512, tileable)

### Change 3: Automated Bulldozer Clearing
- Add WorkerController to Bulldozer following Squad pattern
- Bulldozers will autonomously find and work CLEAR_TERRAIN jobs

## Mysteries Yet Unresolved
- ▸ Is 0.12m the right offset or could it look "floating"?
- ▸ What happens if no bulldozer is available when depot links?
- ▸ Does WorkerController handle bulldozer's blade animation states?
- ▸ What if bulldozer is already manually commanded when depot links?

*The Council remains in session.*
