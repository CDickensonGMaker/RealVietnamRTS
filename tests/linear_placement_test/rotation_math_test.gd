## Mathematical Verification: Rotation Formula Comparison
##
## This test compares the CURRENT rotation formula output vs the PROPOSED fix
## for all cardinal directions, to verify the 90° discrepancy hypothesis.
##
## Reference: War Room analysis at:
## production/war_room/linear_placement_orientation/analysis/gameplay_programmer.md
extends Node

# Test directions (normalized drag vectors)
const TEST_DIRECTIONS := {
	"East (+X)": Vector3(1, 0, 0),
	"West (-X)": Vector3(-1, 0, 0),
	"North (-Z)": Vector3(0, 0, -1),
	"South (+Z)": Vector3(0, 0, 1),
	"NE (+X,-Z)": Vector3(0.707, 0, -0.707),
	"SE (+X,+Z)": Vector3(0.707, 0, 0.707),
	"SW (-X,+Z)": Vector3(-0.707, 0, 0.707),
	"NW (-X,-Z)": Vector3(-0.707, 0, -0.707),
}

# Model rotation offsets to test
const MODEL_OFFSETS := {
	"Sandbag (180°)": 180.0,
	"Wire (0°)": 0.0,
}


func _ready() -> void:
	var sep := "======================================================================"
	print(sep)
	print("ROTATION FORMULA MATHEMATICAL VERIFICATION")
	print(sep)
	print("")

	for model_name in MODEL_OFFSETS:
		var model_offset_deg: float = MODEL_OFFSETS[model_name]
		var model_offset_rad: float = deg_to_rad(model_offset_deg)

		print("--- %s (model_rotation_y = %.0f°) ---" % [model_name, model_offset_deg])
		print("")
		print("| Direction | Current | Proposed | Final (Current) | Final (Proposed) | Delta |")
		print("|-----------|---------|----------|-----------------|------------------|-------|")

		for dir_name in TEST_DIRECTIONS:
			var direction: Vector3 = TEST_DIRECTIONS[dir_name]

			# CURRENT formula (from placement_controller.gd:392-396)
			var perpendicular := Vector3(-direction.z, 0, direction.x)
			var current_linear_rotation := atan2(perpendicular.x, -perpendicular.z)

			# PROPOSED formula
			var proposed_linear_rotation := atan2(direction.x, direction.z) - model_offset_rad

			# Final rotation (what the model actually gets)
			var current_final := current_linear_rotation + model_offset_rad
			var proposed_final := proposed_linear_rotation + model_offset_rad

			# Delta between current and proposed (should be ~90° if hypothesis is correct)
			var delta := rad_to_deg(angle_difference(current_final, proposed_final))

			print("| %-9s | %6.1f° | %7.1f° | %14.1f° | %15.1f° | %4.0f° |" % [
				dir_name,
				rad_to_deg(current_linear_rotation),
				rad_to_deg(proposed_linear_rotation),
				rad_to_deg(current_final),
				rad_to_deg(proposed_final),
				delta
			])

		print("")

	print(sep)
	print("INTERPRETATION")
	print(sep)
	print("")
	print("If Delta consistently shows ~90° (or ~-90°), the hypothesis is CONFIRMED:")
	print("  The current formula produces rotation 90° off from parallel alignment.")
	print("")
	print("Expected behavior for CoH-style placement:")
	print("  - Paint East: Model's +X should align with world +X (final rotation ~0°)")
	print("  - Paint North: Model's +X should align with world -Z (final rotation ~-90°)")
	print("")
	print("Current formula uses perpendicular vector -> model FACES the drag direction")
	print("Proposed formula aligns model's length ALONG the drag direction")
	print(sep)

	# Also test what rotation is needed for model's +X to align with each direction
	print("")
	print("--- REQUIRED ROTATIONS FOR +X ALIGNMENT ---")
	print("")
	print("To make model's local +X axis align with a world direction:")
	print("")
	for dir_name in TEST_DIRECTIONS:
		var direction: Vector3 = TEST_DIRECTIONS[dir_name]
		var required := atan2(direction.x, direction.z)
		print("  %s: rotation.y = %.1f° (%.3f rad)" % [dir_name, rad_to_deg(required), required])


func angle_difference(a: float, b: float) -> float:
	# Returns the smallest angle difference between two angles
	var diff := fmod(b - a + PI, TAU) - PI
	return diff
