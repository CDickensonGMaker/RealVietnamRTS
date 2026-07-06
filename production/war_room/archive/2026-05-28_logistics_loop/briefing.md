# WAR ROOM BRIEFING: Test Scene Strategy Decision

**Date**: 2026-05-28
**Summoner**: User
**Priority**: High - Blocking logistics development

## The Query

Should we:
1. **Continue debugging** the isolated `supply_loop_test.tscn` scene, OR
2. **Migrate logistics loop testing** into `combined_test.tscn` which has working tree clearing and more complete systems?

## User's Concern

> "I feel like I'm almost working against myself because it's just not a complete system like we have in combined test"

## Current State

### supply_loop_test.tscn (Isolated Scene)
- Purpose: Test supply chain in isolation (depots, roads, trucks, bulldozers)
- **Problem**: Bulldozer keeps going IDLE - JobSystem/WorkerController not finding jobs
- Multiple debug sessions have not resolved the core issue
- Systems feel incomplete - missing terrain, tree clearing integration

### combined_test.tscn (Integration Scene)
- Has working terrain generation
- Has working tree clearing (TerrainClearing + VegetationManager)
- Has working VegetationLODManager
- Has NOT been tested with the full logistics loop

## Architects Summoned

| Architect | Domain |
|-----------|--------|
| Systems Designer | Test architecture, system integration patterns |
| Technical Director | Engineering workflow, debugging efficiency |
| Devil's Advocate | Challenge assumptions, find what we're missing |

## Constraints (Project Pillars)

- **Pillar 1 (Carve the Map)**: Bulldozers cut roads - core mechanic, MUST work
- **Pillar 3 (Physical Supply Chains)**: Roads enable supply convoys - visible logistics
- Integration: All systems must work together eventually
