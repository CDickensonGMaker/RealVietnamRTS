# Adoption Plan

> **Generated**: 2026-05-21
> **Project phase**: Production
> **Engine**: Godot 4.6
> **Template version**: v1.0+

Work through these steps in order. Check off each item as you complete it.
Re-run `/adopt` anytime to check remaining gaps.

---

## Overview

Your project has excellent design documentation (GAME_BIBLE.md, PRD.md) but it's not in the format Game Studios skills expect. This plan migrates your content into structured GDDs while preserving your original documents as references.

**Source documents to migrate:**
- `GAME_BIBLE.md` — Vision, Pillars, MVP scope, decisions log
- `PRD.md` — Detailed system designs, technical requirements

**Target structure:**
```
design/gdd/
├── game-concept.md          # Core vision (from GAME_BIBLE sections 1-5)
├── game-pillars.md          # The Six Pillars (extracted)
├── systems-index.md         # Index of all systems with status
├── combat-system.md         # From PRD section 11
├── firebase-system.md       # From PRD section 8
├── supply-logistics.md      # From PRD section 9
├── construction-system.md   # From PRD section 10
├── doctrine-system.md       # From PRD section 13
├── ai-director.md           # From PRD section 12
├── morale-routing.md        # From PRD section 7
├── campaign-structure.md    # From PRD section 14
├── terrain-clearing.md      # From GAME_BIBLE Pillar 1
├── helicopter-system.md     # From codebase + PRD
├── reinforcement-system.md  # From codebase + PRD
├── unit-resources.md        # From PRD section 6
├── day-night-weather.md     # From PRD section 17
└── save-system.md           # From PRD section 15
```

---

## Step 1: Fix Blocking Gaps - COMPLETE

### 1a. Create game-concept.md

Extract from GAME_BIBLE.md sections 1-5 and reformat to the 8-section GDD template.

**Source content:**
- Section 1: Vision / Logline
- Section 2: Player Fantasy
- Section 3: The Six Pillars
- Section 4: Reference Games
- Section 5: Anti-Pillars

- [x] `design/gdd/game-concept.md` created with all 8 required sections

### 1b. Create systems-index.md

Create a master index of all game systems with their design status.

- [x] `design/gdd/systems-index.md` created

---

## Step 2: Fix High-Priority Gaps - COMPLETE

### 2a. Create combat-system.md GDD

Extract from PRD.md Section 11 (Combat System) and reformat.

- [x] `design/gdd/combat-system.md` created

### 2b. Create firebase-system.md GDD

Extract from PRD.md Section 8 and GAME_BIBLE.md Pillar 2.

- [x] `design/gdd/firebase-system.md` created

### 2c. Create supply-logistics.md GDD

Extract from PRD.md Section 9 and GAME_BIBLE.md Pillar 3.

- [x] `design/gdd/supply-logistics.md` created

---

## Step 3: Bootstrap Infrastructure - PARTIAL

### 3a. Create remaining system GDDs - COMPLETE

For each system in systems-index.md that has implementation but no GDD:

- [x] `design/gdd/construction-system.md` (from PRD Section 10)
- [x] `design/gdd/terrain-clearing.md` (from codebase + GAME_BIBLE Pillar 1)
- [x] `design/gdd/doctrine-system.md` (from PRD Section 13)
- [x] `design/gdd/ai-director.md` (from PRD Section 12)
- [x] `design/gdd/helicopter-system.md` (reverse-doc from codebase)
- [x] `design/gdd/reinforcement-system.md` (reverse-doc from codebase)
- [x] `design/gdd/morale-routing.md` (from PRD Section 7)
- [x] `design/gdd/campaign-structure.md` (from PRD Section 14)
- [x] `design/gdd/unit-resources.md` (from PRD Section 6)
- [x] `design/gdd/day-night-weather.md` (from PRD Section 17)
- [x] `design/gdd/save-system.md` (from PRD Section 15)

### 3b. Create Architecture Decision Records

Document major technical decisions already made:

- [ ] `docs/architecture/adr-0001-terrain-chunk-streaming.md`
- [ ] `docs/architecture/adr-0002-vegetation-lod-system.md`
- [ ] `docs/architecture/adr-0003-spatial-hash-grid.md`
- [ ] `docs/architecture/adr-0004-signal-bus-pattern.md`
- [ ] `docs/architecture/adr-0005-job-system-architecture.md`

**Command:** `/architecture-decision` for each, or `/reverse-document architecture`

### 3c. Bootstrap TR Registry

Run `/architecture-review` to create the traceability registry from your GDDs.

- [ ] `docs/architecture/tr-registry.yaml` populated

### 3d. Create Control Manifest

Run `/create-control-manifest` after ADRs exist.

- [ ] `docs/architecture/control-manifest.md` created

### 3e. Set Authoritative Project Stage

Run `/gate-check Production` to validate and write stage.txt authoritatively.

- [ ] `production/stage.txt` confirmed as Production

---

## Step 4: Medium-Priority Gaps - COMPLETE

### 4a. Add Acceptance Criteria to all GDDs

Each GDD needs testable acceptance criteria for `/create-stories` to work.

- [x] All 17 GDDs include Acceptance Criteria section

### 4b. Add Formulas sections

Combat, suppression, supply consumption, construction time formulas.

- [x] All 17 GDDs include Formulas section with GDScript examples

### 4c. Create game-pillars.md

Extract the Six Pillars into a standalone reference document.

- [x] `design/gdd/game-pillars.md` created

### 4d. Add Dependencies sections

Each GDD should list which other systems it depends on.

- [x] All 17 GDDs include Dependencies section

---

## Step 5: Optional Improvements

### 5a. Create narrative docs

If campaign has story elements, create `design/narrative/` structure.

- [ ] `design/narrative/` created if needed

### 5b. Create level design docs

Document firebase scenarios, map layouts.

- [ ] `design/levels/` created if needed

---

## GDD Completion Summary

| GDD | Status |
|-----|--------|
| `game-concept.md` | Complete |
| `game-pillars.md` | Complete |
| `systems-index.md` | Complete |
| `combat-system.md` | Complete |
| `firebase-system.md` | Complete |
| `supply-logistics.md` | Complete |
| `construction-system.md` | Complete |
| `terrain-clearing.md` | Complete |
| `doctrine-system.md` | Complete |
| `ai-director.md` | Complete |
| `morale-routing.md` | Complete |
| `campaign-structure.md` | Complete |
| `helicopter-system.md` | Complete |
| `reinforcement-system.md` | Complete |
| `unit-resources.md` | Complete |
| `day-night-weather.md` | Complete |
| `save-system.md` | Complete |

**Total: 17/17 GDDs Complete**

---

## Next Steps

With all GDDs complete, you can now:

1. **Run `/create-epics`** to generate work breakdown from your design
2. **Run `/architecture-review`** to create the TR registry
3. **Create ADRs** using `/architecture-decision` for existing technical decisions
4. **Run `/gate-check Production`** to validate project stage

---

## What to Expect from Existing Code

Your 195 GDScript files continue to work normally. The GDD migration is about making your design documentation machine-readable for the Game Studios workflow — it doesn't change your code.

---

## Re-run

Run `/adopt` again after completing Step 3b-3e to verify infrastructure gaps are resolved.
