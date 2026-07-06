class_name SkeletonMapper extends RefCounted
## SkeletonMapper - Maps actual skeleton bone names to generic names
##
## Different modeling tools export skeletons with different naming conventions.
## This class scans a skeleton and creates a mapping from generic names
## (like "upper_arm_L") to actual bone names (like "LeftUpperArm", "Arm.Upper.L", etc.)
##
## Supports common naming conventions:
##   - Blender default: "Arm.Upper.L"
##   - Mixamo: "LeftUpperArm"
##   - Spring 1944: "lshoulder", "rshoulder"
##   - Generic: "upper_arm_l", "upper_arm_L"

## Mapping from generic name to actual bone name in skeleton
var _generic_to_actual: Dictionary = {}

## Reverse mapping for debugging
var _actual_to_generic: Dictionary = {}

## Generic bone names we look for
const GENERIC_BONES: PackedStringArray = [
	"root",
	"pelvis",
	"spine",
	"spine_1",
	"spine_2",
	"neck",
	"head",
	"shoulder_L",
	"upper_arm_L",
	"forearm_L",
	"hand_L",
	"shoulder_R",
	"upper_arm_R",
	"forearm_R",
	"hand_R",
	"thigh_L",
	"shin_L",
	"foot_L",
	"toe_L",
	"thigh_R",
	"shin_R",
	"foot_R",
	"toe_R",
]

## Pattern sets for matching bone names to generic names
## Each generic name has multiple possible patterns
const BONE_PATTERNS: Dictionary = {
	"root": ["root", "Root", "ROOT", "armature", "Armature"],
	"pelvis": ["pelvis", "Pelvis", "hips", "Hips", "hip", "Hip"],
	"spine": ["spine", "Spine", "spine.001", "Spine1", "spine_01"],
	"spine_1": ["spine.001", "spine_1", "Spine1", "spine1", "chest", "Chest", "spine_02"],
	"spine_2": ["spine.002", "spine_2", "Spine2", "spine2", "upper_chest", "UpperChest", "spine_03"],
	"neck": ["neck", "Neck", "NECK", "neck_01"],
	"head": ["head", "Head", "HEAD", "head_01"],

	# Left arm
	"shoulder_L": [
		"shoulder.L", "Shoulder.L", "shoulder_l", "LeftShoulder",
		"clavicle.L", "Clavicle.L", "clavicle_l", "LeftClavicle",
		"lshoulder", "l_shoulder", "L_Shoulder"
	],
	"upper_arm_L": [
		"upper_arm.L", "UpperArm.L", "upper_arm_l", "LeftUpperArm",
		"arm.L", "Arm.L", "arm_l", "LeftArm",
		"luarm", "l_upper_arm", "L_UpperArm", "larm"
	],
	"forearm_L": [
		"forearm.L", "Forearm.L", "forearm_l", "LeftForeArm",
		"lower_arm.L", "LowerArm.L", "lower_arm_l",
		"llarm", "l_forearm", "L_ForeArm", "lforearm"
	],
	"hand_L": [
		"hand.L", "Hand.L", "hand_l", "LeftHand",
		"lhand", "l_hand", "L_Hand"
	],

	# Right arm
	"shoulder_R": [
		"shoulder.R", "Shoulder.R", "shoulder_r", "RightShoulder",
		"clavicle.R", "Clavicle.R", "clavicle_r", "RightClavicle",
		"rshoulder", "r_shoulder", "R_Shoulder"
	],
	"upper_arm_R": [
		"upper_arm.R", "UpperArm.R", "upper_arm_r", "RightUpperArm",
		"arm.R", "Arm.R", "arm_r", "RightArm",
		"ruarm", "r_upper_arm", "R_UpperArm", "rarm"
	],
	"forearm_R": [
		"forearm.R", "Forearm.R", "forearm_r", "RightForeArm",
		"lower_arm.R", "LowerArm.R", "lower_arm_r",
		"rlarm", "r_forearm", "R_ForeArm", "rforearm"
	],
	"hand_R": [
		"hand.R", "Hand.R", "hand_r", "RightHand",
		"rhand", "r_hand", "R_Hand"
	],

	# Left leg
	"thigh_L": [
		"thigh.L", "Thigh.L", "thigh_l", "LeftUpLeg", "LeftThigh",
		"upper_leg.L", "UpperLeg.L", "upper_leg_l",
		"luleg", "l_thigh", "L_Thigh", "lleg"
	],
	"shin_L": [
		"shin.L", "Shin.L", "shin_l", "LeftLeg", "LeftShin",
		"lower_leg.L", "LowerLeg.L", "lower_leg_l", "calf.L",
		"llleg", "l_shin", "L_Shin", "lshin"
	],
	"foot_L": [
		"foot.L", "Foot.L", "foot_l", "LeftFoot",
		"lfoot", "l_foot", "L_Foot"
	],
	"toe_L": [
		"toe.L", "Toe.L", "toe_l", "LeftToe", "LeftToeBase",
		"ltoe", "l_toe", "L_Toe"
	],

	# Right leg
	"thigh_R": [
		"thigh.R", "Thigh.R", "thigh_r", "RightUpLeg", "RightThigh",
		"upper_leg.R", "UpperLeg.R", "upper_leg_r",
		"ruleg", "r_thigh", "R_Thigh", "rleg"
	],
	"shin_R": [
		"shin.R", "Shin.R", "shin_r", "RightLeg", "RightShin",
		"lower_leg.R", "LowerLeg.R", "lower_leg_r", "calf.R",
		"rlleg", "r_shin", "R_Shin", "rshin"
	],
	"foot_R": [
		"foot.R", "Foot.R", "foot_r", "RightFoot",
		"rfoot", "r_foot", "R_Foot"
	],
	"toe_R": [
		"toe.R", "Toe.R", "toe_r", "RightToe", "RightToeBase",
		"rtoe", "r_toe", "R_Toe"
	],
}


## Scan a skeleton and create mappings
func scan_skeleton(skeleton: Skeleton3D) -> void:
	_generic_to_actual.clear()
	_actual_to_generic.clear()

	if not skeleton:
		push_error("SkeletonMapper: skeleton is null")
		return

	var bone_count: int = skeleton.get_bone_count()
	var actual_names: PackedStringArray = []

	# Collect all bone names
	for i in bone_count:
		actual_names.append(skeleton.get_bone_name(i))

	# Try to match each generic name to an actual bone
	for generic_name: String in GENERIC_BONES:
		var matched: String = _find_matching_bone(generic_name, actual_names)
		if not matched.is_empty():
			_generic_to_actual[generic_name] = matched
			_actual_to_generic[matched] = generic_name

	print("[SkeletonMapper] Mapped %d/%d bones" % [_generic_to_actual.size(), GENERIC_BONES.size()])


## Find a matching bone name from actual names
func _find_matching_bone(generic_name: String, actual_names: PackedStringArray) -> String:
	if not BONE_PATTERNS.has(generic_name):
		return ""

	var patterns: Array = BONE_PATTERNS[generic_name]

	# First pass: exact match
	for pattern: String in patterns:
		if pattern in actual_names:
			return pattern

	# Second pass: case-insensitive match
	for actual: String in actual_names:
		var actual_lower: String = actual.to_lower()
		for pattern: String in patterns:
			if actual_lower == pattern.to_lower():
				return actual

	# Third pass: contains match (less strict)
	for actual: String in actual_names:
		var actual_lower: String = actual.to_lower()
		# Check if bone name contains key identifiers
		if _matches_generic_loosely(generic_name, actual_lower):
			return actual

	return ""


## Loose matching based on generic name parts
func _matches_generic_loosely(generic_name: String, actual_lower: String) -> bool:
	# Parse generic name parts
	var parts: PackedStringArray = generic_name.split("_")
	if parts.size() < 1:
		return false

	var main_part: String = parts[0]
	var side: String = parts[-1] if parts.size() > 1 else ""

	# Check side indicator
	var side_matches: bool = true
	if side == "L":
		side_matches = actual_lower.contains("left") or actual_lower.contains(".l") or \
					   actual_lower.ends_with("_l") or actual_lower.ends_with("l")
	elif side == "R":
		side_matches = actual_lower.contains("right") or actual_lower.contains(".r") or \
					   actual_lower.ends_with("_r") or actual_lower.ends_with("r")

	if not side_matches:
		return false

	# Check main bone type
	match main_part:
		"upper":
			return actual_lower.contains("upper") or actual_lower.contains("uarm") or \
				   actual_lower.contains("uleg")
		"forearm":
			return actual_lower.contains("fore") or actual_lower.contains("lower") or \
				   actual_lower.contains("larm")
		"thigh":
			return actual_lower.contains("thigh") or actual_lower.contains("upleg") or \
				   actual_lower.contains("uleg")
		"shin":
			return actual_lower.contains("shin") or actual_lower.contains("calf") or \
				   actual_lower.contains("lleg") or actual_lower.contains("leg")
		"shoulder":
			return actual_lower.contains("shoulder") or actual_lower.contains("clavicle")
		"spine":
			return actual_lower.contains("spine") and not actual_lower.contains("1") and \
				   not actual_lower.contains("2")
		_:
			return actual_lower.contains(main_part)


## Get the actual bone name for a generic name
func get_actual_bone_name(generic_name: String) -> String:
	return _generic_to_actual.get(generic_name, "")


## Get the generic name for an actual bone name
func get_generic_bone_name(actual_name: String) -> String:
	return _actual_to_generic.get(actual_name, "")


## Get all mapped generic names
func get_all_generic_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for key: String in _generic_to_actual.keys():
		names.append(key)
	return names


## Get all mapped actual names
func get_all_actual_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for value: String in _generic_to_actual.values():
		names.append(value)
	return names


## Check if a generic bone is mapped
func has_generic_bone(generic_name: String) -> bool:
	return _generic_to_actual.has(generic_name)


## Get mapping dictionary (for debugging)
func get_mapping() -> Dictionary:
	return _generic_to_actual.duplicate()


## Create a custom mapping manually
func set_mapping(generic_name: String, actual_name: String) -> void:
	_generic_to_actual[generic_name] = actual_name
	_actual_to_generic[actual_name] = generic_name


## Clear all mappings
func clear() -> void:
	_generic_to_actual.clear()
	_actual_to_generic.clear()


## Print mapping for debugging
func print_mapping() -> void:
	print("[SkeletonMapper] Current mapping:")
	for generic: String in GENERIC_BONES:
		var actual: String = _generic_to_actual.get(generic, "(unmapped)")
		print("  %s -> %s" % [generic, actual])
