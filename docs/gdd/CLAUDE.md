# CLAUDE.md - GDD Reference Guidance for Agents

## Purpose

GDD reference documents are **war-room consultation resources** for design decisions. They capture:
- Reference game mechanics and patterns (Company of Heroes, Supreme Commander, RUSE, Warno, etc.)
- Implementation checklists and technical patterns
- Combat balance curves and timing data
- Visual/audio direction references
- Design questions and deferred decisions

**NOT canonical** - See GAME_BIBLE.md for authoritative decisions.

## Document Structure Standards

Every GDD should include:

1. **Title & Scope** - What problem does this doc solve?
2. **Reference Games** - Which titles inspired these mechanics?
3. **Core Mechanics** - The essential rules/systems
4. **Implementation Checklist** - Steps to implement
5. **Design Questions** - Open issues or alternatives
6. **Deferred Decisions** - Marked `[DEFER: D-XXX]` linking to Bible

Example header:
```
# GDD: Suppression System
**Scope:** Squad-level morale and pinning mechanics
**References:** Company of Heroes, Broken Arrow
**Status:** [REFERENCE - See D-901 in Bible for final design]
```

## Referencing in Design Discussions

When proposing a feature:

1. Start with Bible status: "D-901 covers suppression..."
2. Cite GDD for implementation: "See GDD-Suppression.md for CoH pattern"
3. Propose minimal viable version for phase being built
4. Flag deferred complexity explicitly

Example:
```
DESIGN PROPOSAL: Suppression thresholds
Bible Reference: D-901 (deferred balance values)
GDD Reference: GDD-Suppression.md § Core Mechanics
Proposal: MVP with static PINNED=0.5, BROKEN=0.8 (tune post-playtest)
```

## Rules for Updating GDD Docs

1. **Don't contradict Bible** - If Bible says "no weather," GDD cannot propose weather systems
2. **Preserve history** - Append new insights, don't delete old approaches
3. **Link to Bible decisions** - Every major section should cite relevant D-XXX
4. **Mark as REFERENCE** - Include banner: `[REFERENCE MATERIAL - Check Bible for final design]`
5. **Date entries** - When adding new patterns or alternatives, timestamp them

## Relationship to GAME_BIBLE.md

| Document | Authority | Use Case |
|----------|-----------|----------|
| **GAME_BIBLE.md** | Canonical | What will ship (final decisions) |
| **GDD-*.md** | Reference | How comparable games solved it (inspiration) |

- Bible is **locked decisions** and production checklist
- GDD is **design inspiration** and technical cookbook
- When Bible and GDD conflict: **Bible wins always**
- GDD can propose alternatives; Bible decides which one ships

### Quick Rule
**"Is this decision locked in the Bible?"**
- YES → Use Bible decision, cite GDD as reference
- NO → Propose based on GDD patterns, ask user to lock in Bible

---

**Last Updated:** 2026-05-25
**Maintainer:** Claude Development Agent
