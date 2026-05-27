# UX Designer Analysis: Player Expectations

## Company of Heroes Reference

In CoH and CoH3, linear defense placement works as follows:

1. **Click** to set start point
2. **Drag** to extend the line
3. **Preview** shows green/red rectangles along the line
4. **Release** to confirm placement
5. **Engineers** walk the line, building each segment

### Visual Feedback

- Green segments = valid placement
- Red segments = invalid (blocked, water, slope)
- Segments form a continuous preview of the final wall
- **Preview matches final result exactly**

### Player Mental Model

When painting a line, players expect:
- The wall to **form along** the painted line
- Segments to **connect** at their ends
- The "front" of defenses to face **away from the base** (toward enemy)

## Current System Issues

### Issue 1: Preview ≠ Reality

The segment markers show footprint rectangles but don't include the model's rotation offset. This means:
- What player sees during placement ≠ what gets built
- Player can't predict final orientation

**Impact:** Surprise and frustration when walls face wrong direction.

### Issue 2: Inconsistent "Front" Direction

Depending on paint direction (left-right vs right-left):
- Wall may face north or south
- Player has no control or feedback about which way "front" faces

**Impact:** Defensive positions might face the wrong way.

### Issue 3: Segments Don't Visually Connect

If rotation is 90° off, segment "length" is perpendicular to the line:
- Gaps appear between segments
- Wall looks fragmented instead of continuous

**Impact:** Defeats the purpose of linear placement.

## Expected Behavior

### Paint Left to Right (West to East)

```
Start ●━━━━━━━━━━━━━━━━● End

Expected wall:
  [═══] [═══] [═══] [═══]
  (segments span E-W, face N or S)

Current bug (if 90° off):
  [║] [║] [║] [║] [║] [║] [║] [║]
  (segments span N-S, creating a "ladder" effect)
```

### Paint Top to Bottom (North to South)

```
Start ●
      ┃
      ┃
      ┃
      ● End

Expected wall:
  [║]
  [║]
  [║]
  [║]
  (segments span N-S, face E or W)
```

## Recommendations

### 1. Preview Must Match Final

The segment marker visualization must include the `model_rotation_y` offset so what the player sees during placement is exactly what they'll get.

### 2. Consistent Facing Convention

Establish a rule:
- "Front" of the wall faces the **direction you painted from**
- E.g., paint West→East means front faces West (toward where you started)
- This lets players intuitively control facing by choosing paint direction

### 3. Visual Facing Indicator

Add a small arrow or highlight showing which direction the wall faces:
```
  [═══→] [═══→] [═══→]
  (arrows show front of wall)
```

### 4. Segment Count Display

Show "5 segments - 10 supply" during drag so player knows exactly what they're placing.

## Acceptance Criteria

After fix, verify:
1. Place sandbag line West→East: segments span horizontally, connect at ends
2. Place sandbag line North→South: segments span vertically, connect at ends
3. Preview rectangles exactly match final model orientation
4. Walls form continuous defensive lines without gaps
