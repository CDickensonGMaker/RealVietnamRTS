# Build Menu Design Document

**Status:** DRAFT - Awaiting approval before implementation
**Last Updated:** 2024-01-XX
**Related Pillar:** Network of Firebases

## Overview

The build menu is a popup HUD element that allows players to select buildings for placement. It appears as a floating panel (not fullscreen) with visual previews of building models.

## Visual Design

### Panel Layout
```
+---------------------------------------+
| BUILD MENU                      [X]   |
+---------------------------------------+
| [Thumbnail] | [Thumbnail] | [Thumb]   |
| Gate Entry  | Bunker      | MG Nest   |
| Cost: 25    | Cost: 40    | Cost: 30  |
+---------------------------------------+
| [Thumbnail] | [Thumbnail] | [Thumb]   |
| Wire Obs.   | Sandbag     | Foxhole   |
| Cost: 10    | Cost: 5     | Cost: 15  |
+---------------------------------------+
|             [SCROLL BAR]              |
+---------------------------------------+
```

### Specifications
- **Panel Size:** 400x500 pixels (adjustable)
- **Thumbnail Size:** 120x100 pixels per building
- **Grid:** 3 columns, scrollable rows
- **Background:** Semi-transparent dark (alpha 0.85)
- **Border:** 2px solid military green (#4a5c3c)

### Thumbnail Rendering
Each thumbnail shows:
1. **3D Preview:** Rendered orthographic view of building model
2. **Name Label:** Below thumbnail, 14pt font, white text
3. **Supply Cost:** Below name, 12pt font, yellow (#f0c040)

Thumbnails should be generated at runtime using a SubViewport with orthographic camera, or pre-rendered and cached.

## Interaction Flow

### Opening the Menu
1. Press `B` key or click "Build" button in HUD
2. Menu popup appears near center-right of screen
3. Menu does NOT pause gameplay

### Selecting a Building
1. Hover over thumbnail - shows highlight border
2. Click thumbnail to select
3. Menu closes immediately
4. Cursor changes to placement mode
5. Building ghost follows cursor

### Placement Modes (by building type)

| Building Type | Mode | Behavior |
|---------------|------|----------|
| **Main Buildings** | SINGLE | Click once to place, exits placement mode |
| Bunker, HQ, Helipad, etc. | | After placement, menu does NOT reopen |
| **Sandbags** | PAINTABLE | Hold click and drag to paint continuous line |
| Sandbag Wall segments | | Each segment snaps to grid, seamless connection |
| **Trenches** | PAINTABLE | Hold click and drag to paint continuous line |
| Trench segments | | Connects seamlessly, follows terrain |
| **Tank Traps** | PAINTABLE_SPACED | Hold click and drag, places at fixed intervals |
| Dragon's teeth, hedgehogs | | 1.6 unit spacing between each trap |

### Canceling Placement
- Press `ESC` key
- Press `Right-click`
- Returns to normal cursor, no building placed

### Exiting Menu Without Selection
- Press `ESC` key
- Click [X] button
- Click outside menu area

## Scroll Behavior

### When Scrolling is Needed
- More buildings than fit in visible area
- Default shows 2 rows (6 buildings)
- Scroll to see additional rows

### Scroll Implementation
- Vertical scrollbar on right side
- Mouse wheel scrolls when hovering menu
- Drag scrollbar thumb to scroll

## Building Categories

Buildings should be organized in categories (tabs or sections):

1. **Defenses** - Bunkers, MG Nests, Foxholes, Sandbags, Wire
2. **Support** - Helipad, Ammo Depot, Medical Station
3. **Command** - HQ/TOC, Commo Bunker, Observation Tower

Initial implementation: Single flat list, categories added later.

## Supply Cost Display

- Show cost in supply points (yellow number)
- If player lacks supply, thumbnail is grayed out (alpha 0.5)
- Tooltip on hover shows: "Requires X supply (have Y)"

## Ghost/Preview During Placement

### Valid Placement
- Ghost building rendered with green tint
- Footprint grid cells shown in green
- "Click to place" indicator

### Invalid Placement
- Ghost building rendered with red tint
- Footprint grid cells shown in red
- Shows reason: "Overlapping building" / "Uncleared terrain" / "Too steep"

### Rotation
- Press `R` to rotate 90 degrees
- Shows rotation in ghost preview

## Technical Implementation Notes

### Files to Create
1. `battle_system/ui/build_menu.gd` - Main popup control
2. `battle_system/ui/build_menu.tscn` - Scene file
3. `battle_system/ui/building_thumbnail.gd` - Thumbnail generator
4. `battle_system/ui/building_thumbnail.tscn` - Thumbnail scene

### Key Classes
```gdscript
class_name BuildMenu extends Control

signal building_selected(building_key: String, placement_mode: PlacementMode)
signal menu_closed()

enum PlacementMode {
    SINGLE,           # One click, one building
    PAINTABLE,        # Continuous drag placement (seamless)
    PAINTABLE_SPACED  # Continuous drag with spacing (e.g., tank traps)
}

# Building definition
var BUILDING_DATA: Dictionary = {
    "bunker": {
        "scene": "res://assets/buildings/bunker.tscn",
        "cost": 40,
        "placement_mode": PlacementMode.SINGLE,
        "category": "defenses"
    },
    "sandbag_wall": {
        "scene": "res://assets/buildings/sandbag_wall.tscn",
        "cost": 5,
        "placement_mode": PlacementMode.PAINTABLE,
        "category": "defenses"
    },
    "tank_trap": {
        "scene": "res://assets/buildings/tank_trap.tscn",
        "cost": 8,
        "placement_mode": PlacementMode.PAINTABLE_SPACED,
        "spacing": 1.6,  # Units between each trap
        "category": "defenses"
    }
}
```

### Integration Points
1. **HUD:** Add "Build" button that opens menu
2. **SelectionManager:** Detect when placement mode is active
3. **ConstructionManager:** Handle actual building placement
4. **SupplySystem:** Check and deduct supply costs

## Deferred Features (Post-MVP)

- Building upgrade indicators
- Damage/repair status in thumbnails
- Quick-build favorites bar
- Building hotkeys (B -> 1 for Bunker, etc.)
- Building placement templates (save/load perimeter layouts)

## Open Questions

1. Should clicking the same building type again after placement re-enter placement mode?
   - Current answer: No, must reopen menu

2. Should paintable buildings show total cost during drag?
   - Current answer: Yes, show running total

3. Should there be a "confirm" for expensive buildings?
   - Current answer: No, but show cost clearly before click

---

## Approval Checklist

- [ ] Visual design approved
- [ ] Interaction flow approved
- [ ] Placement modes approved
- [ ] Technical approach approved
- [ ] Ready for implementation
