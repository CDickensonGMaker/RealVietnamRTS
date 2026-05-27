# Devil's Advocate Analysis: Edge Cases & Alternatives

## Challenging the Hypothesis

The Council hypothesizes that the rotation formula is 90° off. But let me challenge this.

### Alternative 1: Maybe the MODELS are Wrong

What if:
- The sandbag model's "length" is actually along local Z, not local X?
- The footprint_size is correct (2.0 x 0.5 = length x depth)
- But model was authored with the 2m dimension along Z?

**Test:** Load sandbag_light.glb in Blender, measure axes.

If model Z = 2m and model X = 0.5m, then:
- The current rotation (which aligns Z with perpendicular) would be CORRECT
- The "perpendicular to drag" facing would be right

**Verdict:** This would mean the model metadata is wrong, not the rotation code.

### Alternative 2: Maybe "Perpendicular" IS Correct

What if sandbag walls are SUPPOSED to face perpendicular to the paint line?

In real fortifications:
- Sandbags provide cover FROM a direction
- You place them FACING the threat
- The "long wall" runs perpendicular to the threat axis

If I paint a line from my base toward the enemy:
- I want the sandbags to FACE the enemy (parallel to my paint direction)
- The wall itself runs PERPENDICULAR to my paint

**Wait, this makes sense!**

If I paint toward the enemy, I want cover FROM that direction. So:
- Paint direction = threat direction
- Sandbag facing = same as paint direction
- Sandbag length = perpendicular to paint (forming a wall across the threat axis)

**But this contradicts CoH behavior** where you paint ALONG the wall's length.

### Alternative 3: Maybe It's a footprint_size.x vs .y Swap

The code uses:
```gdscript
var segment_length: float = _current_building_data.footprint_size.x
```

So segments are spaced by `footprint_size.x` (2.0m for sandbags).

But what if:
- `footprint_size.x` should be the DEPTH (perpendicular to wall)
- `footprint_size.y` should be the LENGTH (along wall)

Then segments would be spaced 0.5m apart, overlapping heavily (wrong).

No, this doesn't explain the issue.

### Alternative 4: Maybe the atan2 Sign is Flipped

```gdscript
atan2(perpendicular.x, -perpendicular.z)
```

The `-perpendicular.z` is unusual. Standard is `atan2(x, z)`.

The negation flips the angle by 180°. Was this intentional?

Looking at the comment: "Fix 6: Calculate perpendicular vector for correct facing (avoids atan2 edge cases)"

This suggests there WAS a previous bug and this was a fix attempt. Maybe the fix introduced a new bug?

### Alternative 5: Maybe model_rotation_y Shouldn't Be Applied

What if `model_rotation_y` is ONLY for models that need facing correction, but the linear rotation already accounts for it?

Currently:
```
Final = linear_rotation + model_rotation_y
```

But if `linear_rotation` was calculated WITH the model's native orientation in mind, adding `model_rotation_y` would double-correct.

**Test:** Remove `model_rotation_y` from spawn and see if orientation improves.

### Edge Cases to Test

1. **Diagonal paint (NE→SW)**: Does rotation interpolate correctly?
2. **Very short paint (<1 segment)**: Does single segment orient correctly?
3. **Paint backward (undo direction)**: Does facing flip?
4. **0-length paint (click without drag)**: Edge case in atan2?
5. **Paint along axis-aligned directions**: Cardinal directions vs 45° angles?

### Testing Protocol

To determine which hypothesis is correct:

1. **In-engine test scene:**
   - Place sandbag with explicit rotation.y = 0, π/4, π/2, π
   - Observe which rotation makes model span along X-axis

2. **Math verification:**
   - For paint direction (+1, 0, 0):
     - What rotation makes model's length align with +X?
   - Compare to what the current code produces

3. **Model inspection:**
   - Open sandbag_light.glb in Blender
   - Determine which local axis is the "length" axis (2m)
   - Determine which local axis is the "front" facing (-Z expected)

## Worst Case Scenarios

### What if there are MULTIPLE bugs?

1. Rotation formula is 90° off (Bug A)
2. Marker preview doesn't include model_offset (Bug B)
3. Model is authored with unexpected axis orientation (Bug C)

These could compound or partially cancel each other.

### What if the fix breaks something else?

- Wire obstacles have `model_rotation_y = 0°`
- Trenches might have different axis conventions
- Changing the formula affects ALL linear buildings

**Must test all linear building types after any fix.**

## Recommendation

Before implementing any fix:
1. Create a test scene with manual rotation testing
2. Document exact observed behavior for each cardinal direction
3. Compare to expected behavior
4. Only then propose code changes

The math is complex enough that pure analysis may not find the true root cause. Empirical testing is essential.
