class_name Spring1944Poses extends RefCounted
## Spring1944Poses - Direct port of Spring 1944's infantry animation data
##
## Uses Spring 1944's piece names exactly as defined in their Lua scripts:
##   head, torso, pelvis, gun, ground, flare
##   luparm (left upper arm), lloarm (left lower arm)
##   ruparm (right upper arm), rloarm (right lower arm)
##   lthigh, lleg, lfoot
##   rthigh, rleg, rfoot
##
## Rotations are in RADIANS (converted from Spring 1944's math.rad() calls)
## Format: piece -> {x: float, y: float, z: float} (axis rotations)

const DEG2RAD := PI / 180.0

## Spring 1944 piece names
const PIECE_NAMES: PackedStringArray = [
	"head",
	"torso",
	"pelvis",
	"gun",
	"ground",
	"flare",
	"luparm",  # left upper arm
	"lloarm",  # left lower arm
	"ruparm",  # right upper arm
	"rloarm",  # right lower arm
	"lthigh",
	"lleg",
	"lfoot",
	"rthigh",
	"rleg",
	"rfoot",
]


## Static poses - ported from scripts/anims/infantry/rifle.lua
## Values are degrees, will be converted to radians at runtime
const POSES: Dictionary = {
	# Standing idle - rifle at ease (stand_1 from rifle.lua)
	"stand_idle": {
		"head": Vector3(0, 0, 0),
		"ruparm": Vector3(-60, 0, 0),
		"luparm": Vector3(0, 0, 0),
		"rloarm": Vector3(-30, 20, 50),
		"lloarm": Vector3(-95, 0, 0),
		"gun": Vector3(0, 0, 0),
		"torso": Vector3(0, 0, 0),
		"pelvis": Vector3(0, 0, 0),
		"lthigh": Vector3(0, 0, 0),
		"rthigh": Vector3(0, 0, 0),
		"lleg": Vector3(0, 0, 0),
		"rleg": Vector3(0, 0, 0),
	},

	# Standing aim - rifle shouldered (stand_aim from rifle.lua)
	"stand_aim": {
		"head": Vector3(15, 70, 20),
		"ruparm": Vector3(-35, 90, -50),
		"luparm": Vector3(-65, 60, 0),
		"rloarm": Vector3(-80, -10, 25),
		"lloarm": Vector3(-50, 0, -30),
		"gun": Vector3(15, -60, -30),
		"torso": Vector3(0, 20, 10),
		"pelvis": Vector3(0, 0, -10),
		"rthigh": Vector3(5, 0, 0),
		"lthigh": Vector3(-15, 0, 25),
		"rleg": Vector3(5, 0, 0),
		"lleg": Vector3(20, 0, 0),
	},

	# Prone position (prone from rifle.lua)
	"prone_idle": {
		"head": Vector3(-60, 0, 0),
		"ruparm": Vector3(-80, 20, -70),
		"luparm": Vector3(-140, -30, 0),
		"rloarm": Vector3(-120, 30, 0),
		"lloarm": Vector3(20, 65, -40),
		"gun": Vector3(10, -35, -45),
		"torso": Vector3(-10, 20, 0),
		"pelvis": Vector3(90, 0, 0),  # From base.lua prone_base
		"lthigh": Vector3(0, 85, 0),
		"rthigh": Vector3(-90, -85, 15),
		"lleg": Vector3(10, 0, 0),
		"rleg": Vector3(120, 0, 0),
	},

	# Prone aiming (prone_aim from rifle.lua)
	"prone_aim": {
		"head": Vector3(-60, 0, 0),
		"ruparm": Vector3(-80, 20, -70),
		"luparm": Vector3(-140, -30, 0),
		"rloarm": Vector3(-120, 30, 0),
		"lloarm": Vector3(20, 65, -40),
		"gun": Vector3(10, -35, -45),
		"torso": Vector3(-10, 20, 0),
		"pelvis": Vector3(90, 0, 0),
		"lthigh": Vector3(0, 85, 0),
		"rthigh": Vector3(-90, -85, 15),
		"lleg": Vector3(10, 0, 0),
		"rleg": Vector3(120, 0, 0),
	},

	# Pinned/suppressed (pinned_1 from base.lua)
	"pinned": {
		"head": Vector3(0, 0, 0),
		"torso": Vector3(0, 0, -10),
		"ruparm": Vector3(-90, 0, 0),
		"luparm": Vector3(0, 0, 10),
		"rloarm": Vector3(0, 0, 20),
		"lloarm": Vector3(0, 0, -60),
		"gun": Vector3(60, 0, 0),
		"pelvis": Vector3(80, 0, 0),
		"rthigh": Vector3(0, 0, 0),
		"lthigh": Vector3(0, 0, 0),
		"rleg": Vector3(0, 0, 0),
		"lleg": Vector3(0, 0, 0),
	},

	# Dead/casualty
	"dead": {
		"head": Vector3(70, 0, 0),
		"torso": Vector3(0, 0, 0),
		"ruparm": Vector3(-190, 0, 0),
		"luparm": Vector3(-90, 20, 0),
		"rloarm": Vector3(0, 0, 90),
		"lloarm": Vector3(0, 0, -90),
		"gun": Vector3(0, 0, 0),
		"pelvis": Vector3(0, 40, 0),
		"rthigh": Vector3(-60, 50, 0),
		"lthigh": Vector3(0, 30, 0),
		"rleg": Vector3(150, 0, 0),
		"lleg": Vector3(0, 30, 0),
	},
}


## Animation cycles - ported from scripts/anims/infantry/base.lua
## Each frame has: turns (piece rotations), moves (piece translations), wait (frame duration range)
const CYCLES: Dictionary = {
	# Run cycle (from base.lua anims.run)
	"run": [
		{
			"duration": 0.17,  # ~5-6 frames at 30fps
			"pose": {
				"rleg": Vector3(85, 0, 0),
				"lleg": Vector3(10, 0, 0),
				"lthigh": Vector3(30, 0, 0),
				"rthigh": Vector3(-60, 0, 0),
				"torso": Vector3(0, 10, 0),
				"pelvis": Vector3(0, 0, 0),
				# Arm positions from run_1 in rifle.lua
				"head": Vector3(-25, 0, 0),
				"ruparm": Vector3(-35, 10, -25),
				"luparm": Vector3(-10, 0, 5),
				"rloarm": Vector3(-35, -5, 75),
				"lloarm": Vector3(-205, -55, 130),
				"gun": Vector3(0, 0, 0),
			}
		},
		{
			"duration": 0.17,
			"pose": {
				"rleg": Vector3(85, 0, 0),
				"lleg": Vector3(10, 0, 0),
				"lthigh": Vector3(30, 0, 0),
				"rthigh": Vector3(-60, 0, 0),
				"torso": Vector3(0, 10, 0),
				"pelvis": Vector3(0, 1, 0),  # Small bounce
				"head": Vector3(-25, 0, 0),
				"ruparm": Vector3(-35, 10, -25),
				"luparm": Vector3(-10, 0, 5),
				"rloarm": Vector3(-35, -5, 75),
				"lloarm": Vector3(-205, -55, 130),
				"gun": Vector3(0, 0, 0),
			}
		},
		{
			"duration": 0.17,
			"pose": {
				"rleg": Vector3(10, 0, 0),
				"lleg": Vector3(85, 0, 0),
				"lthigh": Vector3(-60, 0, 0),
				"rthigh": Vector3(30, 0, 0),
				"torso": Vector3(0, -10, 0),
				"pelvis": Vector3(0, 0, 0),
				"head": Vector3(-25, 0, 0),
				"ruparm": Vector3(-35, 10, -25),
				"luparm": Vector3(-10, 0, 5),
				"rloarm": Vector3(-35, -5, 75),
				"lloarm": Vector3(-205, -55, 130),
				"gun": Vector3(0, 0, 0),
			}
		},
		{
			"duration": 0.17,
			"pose": {
				"rleg": Vector3(10, 0, 0),
				"lleg": Vector3(85, 0, 0),
				"lthigh": Vector3(-60, 0, 0),
				"rthigh": Vector3(30, 0, 0),
				"torso": Vector3(0, -10, 0),
				"pelvis": Vector3(0, 1, 0),  # Small bounce
				"head": Vector3(-25, 0, 0),
				"ruparm": Vector3(-35, 10, -25),
				"luparm": Vector3(-10, 0, 5),
				"rloarm": Vector3(-35, -5, 75),
				"lloarm": Vector3(-205, -55, 130),
				"gun": Vector3(0, 0, 0),
			}
		},
	],

	# Crawl cycle (from base.lua anims.crawl)
	"crawl": [
		{
			"duration": 0.4,
			"pose": {
				"head": Vector3(-60, 30, -40),
				"ruparm": Vector3(-80, -60, 0),
				"luparm": Vector3(-100, 50, 0),
				"rloarm": Vector3(-120, 30, 0),
				"lloarm": Vector3(-60, -10, 0),
				"gun": Vector3(-40, 45, 0),
				"torso": Vector3(-10, -20, -20),
				"pelvis": Vector3(90, 15, 15),
				"rthigh": Vector3(-90, -85, 15),
				"lthigh": Vector3(0, 100, 0),
				"rleg": Vector3(120, 0, 0),
				"lleg": Vector3(10, 0, 0),
			}
		},
		{
			"duration": 0.4,
			"pose": {
				"head": Vector3(-60, -30, 40),
				"ruparm": Vector3(-100, -50, 0),
				"luparm": Vector3(-80, 60, 0),
				"rloarm": Vector3(-60, 10, 0),
				"lloarm": Vector3(-120, -30, 0),
				"gun": Vector3(-105, 35, 0),
				"torso": Vector3(-10, 20, 20),
				"pelvis": Vector3(90, -15, -15),
				"rthigh": Vector3(0, -100, 0),
				"lthigh": Vector3(-90, 85, -15),
				"rleg": Vector3(10, 0, 0),
				"lleg": Vector3(120, 0, 0),
			}
		},
	],

	# Walk cycle (slower version of run)
	"walk": [
		{
			"duration": 0.3,
			"pose": {
				"rleg": Vector3(45, 0, 0),
				"lleg": Vector3(5, 0, 0),
				"lthigh": Vector3(15, 0, 0),
				"rthigh": Vector3(-30, 0, 0),
				"torso": Vector3(0, 5, 0),
				"pelvis": Vector3(0, 0, 0),
				"head": Vector3(0, 0, 0),
				"ruparm": Vector3(-60, 0, 0),
				"luparm": Vector3(0, 0, 0),
				"rloarm": Vector3(-30, 20, 50),
				"lloarm": Vector3(-95, 0, 0),
				"gun": Vector3(0, 0, 0),
			}
		},
		{
			"duration": 0.3,
			"pose": {
				"rleg": Vector3(5, 0, 0),
				"lleg": Vector3(45, 0, 0),
				"lthigh": Vector3(-30, 0, 0),
				"rthigh": Vector3(15, 0, 0),
				"torso": Vector3(0, -5, 0),
				"pelvis": Vector3(0, 0, 0),
				"head": Vector3(0, 0, 0),
				"ruparm": Vector3(-60, 0, 0),
				"luparm": Vector3(0, 0, 0),
				"rloarm": Vector3(-30, 20, 50),
				"lloarm": Vector3(-95, 0, 0),
				"gun": Vector3(0, 0, 0),
			}
		},
	],

	# Work cycle - engineer swinging tool (construction/clearing)
	"work": [
		{
			"duration": 0.5,
			"pose": {
				# Wind up - arms raised
				"rleg": Vector3(5, 0, 0),
				"lleg": Vector3(5, 0, 0),
				"lthigh": Vector3(10, 0, 0),
				"rthigh": Vector3(10, 0, 0),
				"torso": Vector3(-10, 20, 0),
				"pelvis": Vector3(10, 0, 0),
				"head": Vector3(-15, 0, 0),
				"ruparm": Vector3(-120, 30, -20),
				"luparm": Vector3(-100, -20, 0),
				"rloarm": Vector3(-60, 0, 30),
				"lloarm": Vector3(-70, 0, -30),
				"gun": Vector3(-30, 0, 0),
			}
		},
		{
			"duration": 0.3,
			"pose": {
				# Swing down - arms lowered, body leaning forward
				"rleg": Vector3(15, 0, 0),
				"lleg": Vector3(5, 0, 0),
				"lthigh": Vector3(-5, 0, 0),
				"rthigh": Vector3(20, 0, 0),
				"torso": Vector3(15, -10, 0),
				"pelvis": Vector3(-5, 0, 0),
				"head": Vector3(10, 0, 0),
				"ruparm": Vector3(-30, 0, 0),
				"luparm": Vector3(-40, 10, 0),
				"rloarm": Vector3(-90, 0, 45),
				"lloarm": Vector3(-100, 0, -20),
				"gun": Vector3(60, 0, 0),
			}
		},
		{
			"duration": 0.4,
			"pose": {
				# Recovery - return to neutral
				"rleg": Vector3(5, 0, 0),
				"lleg": Vector3(10, 0, 0),
				"lthigh": Vector3(5, 0, 0),
				"rthigh": Vector3(5, 0, 0),
				"torso": Vector3(0, 0, 0),
				"pelvis": Vector3(5, 0, 0),
				"head": Vector3(0, 0, 0),
				"ruparm": Vector3(-80, 15, -10),
				"luparm": Vector3(-70, -10, 0),
				"rloarm": Vector3(-45, 0, 40),
				"lloarm": Vector3(-80, 0, -25),
				"gun": Vector3(0, 0, 0),
			}
		},
	],
}


## Get a pose by name (returns copy with degrees converted to radians)
static func get_pose(pose_name: String) -> Dictionary:
	if not POSES.has(pose_name):
		return {}

	var pose: Dictionary = {}
	var src: Dictionary = POSES[pose_name]
	for piece: String in src.keys():
		var deg: Vector3 = src[piece]
		pose[piece] = Vector3(
			deg_to_rad(deg.x),
			deg_to_rad(deg.y),
			deg_to_rad(deg.z)
		)
	return pose


## Get a cycle by name (returns copy with degrees converted to radians)
static func get_cycle(cycle_name: String) -> Array:
	if not CYCLES.has(cycle_name):
		return []

	var cycle: Array = []
	for frame: Dictionary in CYCLES[cycle_name]:
		var new_frame: Dictionary = {
			"duration": frame.get("duration", 0.2),
			"pose": {}
		}
		var pose: Dictionary = frame.get("pose", {})
		for piece: String in pose.keys():
			var deg: Vector3 = pose[piece]
			new_frame.pose[piece] = Vector3(
				deg_to_rad(deg.x),
				deg_to_rad(deg.y),
				deg_to_rad(deg.z)
			)
		cycle.append(new_frame)
	return cycle


## Get all pose names
static func get_pose_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for key: String in POSES.keys():
		names.append(key)
	return names


## Get all cycle names
static func get_cycle_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for key: String in CYCLES.keys():
		names.append(key)
	return names
