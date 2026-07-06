# DEVIL'S ADVOCATE ANALYSIS
## Technical Standards Audit - 2026-05-29

---

## CHALLENGING THE "PASS" NARRATIVE

The other architects are celebrating compliance. Let me poke holes.

---

## WHAT WE'RE NOT SEEING

### 1. The 27:1 Connection Ratio Is Worse Than It Looks

305 connects vs 11 disconnects sounds manageable until you realize:
- **Squad spawns**: If you spawn 50 squads in a battle, each with 8 connections...
- **Projectiles**: 41 connections in `projectile.gd` - even pooled, reconnection patterns matter
- **Extended sessions**: RTS games run for hours. Memory creep kills.

**The Question Nobody Asked**: Has anyone run a 2-hour stress test monitoring memory?

### 2. Those 5 Untyped Functions Are Suspicious

```gdscript
func get_mapper():  # Returns SkeletonMapper
func get_threat_heatmap():  # Returns __ThreatHeatmap instance
```

Why the comments instead of types? This suggests:
- Circular dependency issues
- Late-binding design choices
- Types that can't be declared (forward reference problems)

**The Question Nobody Asked**: Are there hidden architectural constraints forcing dynamic typing?

### 3. Only 7 Files Have _exit_tree()

The optimistic interpretation: "Most connections are to autoloads."

The pessimistic interpretation: "Nobody thought about cleanup."

**Files with ZERO cleanup that probably need it:**
- `battle_system/nodes/soldier.gd` - Dies frequently
- `battle_system/nodes/infantry_squad.gd` - Gets killed
- `battle_system/units/tank.gd` - Destroyed in combat
- `helicopter_system/helicopter.gd` - Crashes, lands, leaves

### 4. The Archive Folder

`test_scenes/_archive/` contains code that:
- Has type violations
- May be copy-pasted from for new features
- Pollutes scan results

**The Question Nobody Asked**: Should archived code be excluded from project, or is it actively referenced?

---

## WHAT'S BEING SACRIFICED

### By Passing This Audit
- **We accept** the memory leak risk as theoretical
- **We assume** connections to autoloads don't need cleanup
- **We trust** that pooled objects handle reconnection correctly

### The Real Cost of Inaction
- Subtle memory growth in long sessions
- Crash reports from players after 3+ hour sessions
- Debugging signal-related issues with no cleanup trail

---

## TRADEOFFS NAMED

| Decision | Gain | Sacrifice |
|----------|------|-----------|
| Skip return type fixes | Save time | Lose IDE completion on 5 functions |
| Skip disconnect audit | Ship faster | Risk memory leaks in production |
| Ignore archive code | Clean metrics | Legacy patterns may propagate |

---

## MY VERDICT

**CONDITIONAL PASS WITH MANDATORY FOLLOW-UP**

The codebase is good. But "good enough for development" and "good enough for shipping" are different standards.

Before any public release:
1. Run soak test (2+ hours, memory monitoring)
2. Audit the 10 highest-churn node types for cleanup
3. Delete or isolate `_archive/` folder from active development

The Council should not rubber-stamp this. The signal ratio is a smell.
