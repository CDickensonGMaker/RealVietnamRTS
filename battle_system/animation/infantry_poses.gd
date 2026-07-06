class_name InfantryPoses extends RefCounted
## InfantryPoses - Pose and animation cycle definitions for infantry
##
## Based on Spring 1944's procedural infantry animations.
## All rotations are in degrees (euler angles: X=pitch, Y=yaw, Z=roll).
## Uses generic bone names that get mapped to actual skeleton bones.
##
## Generic bone naming convention:
##   spine, spine_1, spine_2
##   neck, head
##   shoulder_L, upper_arm_L, forearm_L, hand_L
##   shoulder_R, upper_arm_R, forearm_R, hand_R
##   thigh_L, shin_L, foot_L
##   thigh_R, shin_R, foot_R

## Static pose definitions
## Each pose is a Dictionary mapping generic bone names to Vector3 euler rotations
## NOTE: Rotations are RELATIVE to the model's rest pose. Use zeros to keep rest pose.
const POSES: Dictionary = {
	# =========================================================================
	# STANDING POSES
	# =========================================================================
	# Rest pose - all zeros, model stands in its natural imported pose
	"stand_idle": {
		"spine": Vector3(0, 0, 0),
		"spine_1": Vector3(0, 0, 0),
		"spine_2": Vector3(0, 0, 0),
		"neck": Vector3(0, 0, 0),
		"head": Vector3(0, 0, 0),
		"shoulder_L": Vector3(0, 0, 0),
		"upper_arm_L": Vector3(0, 0, 0),
		"forearm_L": Vector3(0, 0, 0),
		"hand_L": Vector3(0, 0, 0),
		"shoulder_R": Vector3(0, 0, 0),
		"upper_arm_R": Vector3(0, 0, 0),
		"forearm_R": Vector3(0, 0, 0),
		"hand_R": Vector3(0, 0, 0),
		"thigh_L": Vector3(0, 0, 0),
		"shin_L": Vector3(0, 0, 0),
		"foot_L": Vector3(0, 0, 0),
		"thigh_R": Vector3(0, 0, 0),
		"shin_R": Vector3(0, 0, 0),
		"foot_R": Vector3(0, 0, 0),
	},

	"stand_aim": {
		"spine": Vector3(0, -15, 0),        # Turned slightly right
		"spine_1": Vector3(8, -5, 0),       # Leaning into rifle
		"spine_2": Vector3(5, 0, 0),
		"neck": Vector3(-10, 10, 0),        # Head turned, looking down sights
		"head": Vector3(0, 5, 3),           # Slight tilt for cheek weld
		"shoulder_L": Vector3(0, 0, 0),
		"upper_arm_L": Vector3(60, 20, 60), # Left arm forward supporting rifle
		"forearm_L": Vector3(0, 0, 90),     # Bent to hold handguard
		"hand_L": Vector3(0, -15, 0),       # Gripping handguard
		"shoulder_R": Vector3(0, 0, 0),
		"upper_arm_R": Vector3(45, -30, -45),# Right arm at pistol grip
		"forearm_R": Vector3(0, 0, -60),    # Bent to grip
		"hand_R": Vector3(0, 10, 0),        # On pistol grip
		"thigh_L": Vector3(-5, -10, 0),     # Left foot forward
		"shin_L": Vector3(5, 0, 0),
		"foot_L": Vector3(-5, 0, 0),
		"thigh_R": Vector3(5, 10, 0),       # Right foot back
		"shin_R": Vector3(0, 0, 0),
		"foot_R": Vector3(0, 0, 0),
	},

	"stand_alert": {
		"spine": Vector3(0, 0, 0),
		"spine_1": Vector3(10, 0, 0),       # More forward lean - alert stance
		"spine_2": Vector3(5, 0, 0),
		"neck": Vector3(-8, 0, 0),
		"head": Vector3(0, 0, 0),
		"shoulder_L": Vector3(0, 0, 0),
		"upper_arm_L": Vector3(35, 10, 40), # Rifle at low ready
		"forearm_L": Vector3(0, 0, 45),
		"hand_L": Vector3(0, -10, 0),
		"shoulder_R": Vector3(0, 0, 0),
		"upper_arm_R": Vector3(30, -15, -35),
		"forearm_R": Vector3(0, 0, -40),
		"hand_R": Vector3(0, 5, 0),
		"thigh_L": Vector3(-3, -5, 0),
		"shin_L": Vector3(8, 0, 0),
		"foot_L": Vector3(-5, 0, 0),
		"thigh_R": Vector3(3, 5, 0),
		"shin_R": Vector3(3, 0, 0),
		"foot_R": Vector3(0, 0, 0),
	},

	# =========================================================================
	# CROUCHING POSES
	# =========================================================================
	"crouch_idle": {
		"spine": Vector3(20, 0, 0),         # Hunched forward
		"spine_1": Vector3(15, 0, 0),
		"spine_2": Vector3(10, 0, 0),
		"neck": Vector3(-25, 0, 0),         # Head up to see
		"head": Vector3(-5, 0, 0),
		"shoulder_L": Vector3(0, 0, -5),
		"upper_arm_L": Vector3(25, 15, 35),
		"forearm_L": Vector3(0, 0, 30),
		"hand_L": Vector3(0, 0, 0),
		"shoulder_R": Vector3(0, 0, 5),
		"upper_arm_R": Vector3(20, -10, -30),
		"forearm_R": Vector3(0, 0, -25),
		"hand_R": Vector3(0, 0, 0),
		"thigh_L": Vector3(-60, -5, 0),     # Deep crouch
		"shin_L": Vector3(100, 0, 0),       # Knees bent
		"foot_L": Vector3(-40, 0, 0),
		"thigh_R": Vector3(-55, 5, 0),
		"shin_R": Vector3(95, 0, 0),
		"foot_R": Vector3(-35, 0, 0),
	},

	"crouch_aim": {
		"spine": Vector3(15, -10, 0),
		"spine_1": Vector3(12, -5, 0),
		"spine_2": Vector3(8, 0, 0),
		"neck": Vector3(-20, 8, 0),
		"head": Vector3(0, 5, 3),
		"shoulder_L": Vector3(0, 0, 0),
		"upper_arm_L": Vector3(55, 25, 55),
		"forearm_L": Vector3(0, 0, 85),
		"hand_L": Vector3(0, -15, 0),
		"shoulder_R": Vector3(0, 0, 0),
		"upper_arm_R": Vector3(40, -25, -40),
		"forearm_R": Vector3(0, 0, -55),
		"hand_R": Vector3(0, 10, 0),
		"thigh_L": Vector3(-55, -10, 0),
		"shin_L": Vector3(90, 0, 0),
		"foot_L": Vector3(-35, 0, 0),
		"thigh_R": Vector3(-60, 8, 0),
		"shin_R": Vector3(100, 0, 0),
		"foot_R": Vector3(-40, 0, 0),
	},

	# =========================================================================
	# PRONE POSES
	# =========================================================================
	"prone_idle": {
		"spine": Vector3(75, 0, 0),         # Lying flat
		"spine_1": Vector3(10, 0, 0),
		"spine_2": Vector3(5, 0, 0),
		"neck": Vector3(-70, 0, 0),         # Head up to see
		"head": Vector3(-15, 0, 0),
		"shoulder_L": Vector3(0, 0, 10),
		"upper_arm_L": Vector3(80, 30, 60), # Arms forward
		"forearm_L": Vector3(0, 0, 30),
		"hand_L": Vector3(0, 0, 0),
		"shoulder_R": Vector3(0, 0, -10),
		"upper_arm_R": Vector3(75, -25, -55),
		"forearm_R": Vector3(0, 0, -25),
		"hand_R": Vector3(0, 0, 0),
		"thigh_L": Vector3(5, 0, -15),      # Legs flat, slightly spread
		"shin_L": Vector3(10, 0, 0),
		"foot_L": Vector3(-5, 0, 0),
		"thigh_R": Vector3(5, 0, 15),
		"shin_R": Vector3(10, 0, 0),
		"foot_R": Vector3(-5, 0, 0),
	},

	"prone_aim": {
		"spine": Vector3(70, -5, 0),
		"spine_1": Vector3(8, -3, 0),
		"spine_2": Vector3(5, 0, 0),
		"neck": Vector3(-65, 5, 0),
		"head": Vector3(-10, 5, 3),
		"shoulder_L": Vector3(0, 0, 5),
		"upper_arm_L": Vector3(85, 35, 55),
		"forearm_L": Vector3(0, 0, 70),
		"hand_L": Vector3(0, -10, 0),
		"shoulder_R": Vector3(0, 0, -5),
		"upper_arm_R": Vector3(70, -30, -45),
		"forearm_R": Vector3(0, 0, -45),
		"hand_R": Vector3(0, 5, 0),
		"thigh_L": Vector3(5, 0, -20),
		"shin_L": Vector3(15, 0, 0),
		"foot_L": Vector3(-5, 0, 0),
		"thigh_R": Vector3(5, 0, 20),
		"shin_R": Vector3(15, 0, 0),
		"foot_R": Vector3(-5, 0, 0),
	},

	# =========================================================================
	# DEATH POSES
	# =========================================================================
	"dead_front": {
		"spine": Vector3(85, 0, 0),         # Face down
		"spine_1": Vector3(5, 10, 5),
		"spine_2": Vector3(3, 5, 3),
		"neck": Vector3(15, 20, 10),
		"head": Vector3(10, 15, 5),
		"shoulder_L": Vector3(0, 0, 0),
		"upper_arm_L": Vector3(90, 45, 30), # Arm sprawled
		"forearm_L": Vector3(0, 0, 45),
		"hand_L": Vector3(10, 0, 0),
		"shoulder_R": Vector3(0, 0, 0),
		"upper_arm_R": Vector3(60, -20, -40),
		"forearm_R": Vector3(0, 0, -30),
		"hand_R": Vector3(-5, 0, 0),
		"thigh_L": Vector3(15, 0, -10),
		"shin_L": Vector3(25, 0, 5),
		"foot_L": Vector3(5, -10, 0),
		"thigh_R": Vector3(-5, 0, 20),
		"shin_R": Vector3(40, 0, -5),
		"foot_R": Vector3(-10, 5, 0),
	},

	"dead_back": {
		"spine": Vector3(-10, 5, 0),        # Face up, back arched
		"spine_1": Vector3(-8, -3, 2),
		"spine_2": Vector3(-5, 0, 0),
		"neck": Vector3(30, 25, 15),        # Head lolled
		"head": Vector3(15, -20, 10),
		"shoulder_L": Vector3(0, 0, 0),
		"upper_arm_L": Vector3(30, 0, 80),  # Arm out to side
		"forearm_L": Vector3(0, 0, 60),
		"hand_L": Vector3(5, 10, 0),
		"shoulder_R": Vector3(0, 0, 0),
		"upper_arm_R": Vector3(45, 0, -70),
		"forearm_R": Vector3(0, 0, -45),
		"hand_R": Vector3(-5, -5, 0),
		"thigh_L": Vector3(-20, -15, -20),
		"shin_L": Vector3(35, 10, 5),
		"foot_L": Vector3(20, -15, 10),
		"thigh_R": Vector3(-15, 20, 15),
		"shin_R": Vector3(25, -5, -10),
		"foot_R": Vector3(15, 10, -5),
	},
}


## Animation cycles - arrays of keyframes with pose and duration
## Each frame: { "pose": Dictionary, "duration": float (seconds) }
const CYCLES: Dictionary = {
	# =========================================================================
	# WALKING CYCLE - Natural military march
	# =========================================================================
	"walk": [
		# Contact - right heel strike
		{
			"duration": 0.25,
			"pose": {
				"spine": Vector3(3, 0, 0),
				"spine_1": Vector3(5, 2, 0),
				"spine_2": Vector3(3, 0, 0),
				"neck": Vector3(-8, 0, 0),
				"head": Vector3(0, 0, 0),
				"upper_arm_L": Vector3(-20, 0, 25),  # Left arm back
				"forearm_L": Vector3(0, 0, 20),
				"upper_arm_R": Vector3(25, 0, -25),  # Right arm forward
				"forearm_R": Vector3(0, 0, -25),
				"thigh_L": Vector3(25, 0, 0),       # Left leg forward
				"shin_L": Vector3(5, 0, 0),
				"foot_L": Vector3(10, 0, 0),
				"thigh_R": Vector3(-25, 0, 0),      # Right leg back
				"shin_R": Vector3(35, 0, 0),
				"foot_R": Vector3(-15, 0, 0),
			}
		},
		# Passing - left leg swinging through
		{
			"duration": 0.25,
			"pose": {
				"spine": Vector3(3, 0, 0),
				"spine_1": Vector3(5, 0, 0),
				"spine_2": Vector3(3, 0, 0),
				"neck": Vector3(-8, 0, 0),
				"head": Vector3(0, 0, 0),
				"upper_arm_L": Vector3(5, 0, 25),
				"forearm_L": Vector3(0, 0, 15),
				"upper_arm_R": Vector3(-5, 0, -25),
				"forearm_R": Vector3(0, 0, -15),
				"thigh_L": Vector3(5, 0, 0),
				"shin_L": Vector3(40, 0, 0),        # Knee bent during swing
				"foot_L": Vector3(-10, 0, 0),
				"thigh_R": Vector3(-5, 0, 0),
				"shin_R": Vector3(10, 0, 0),
				"foot_R": Vector3(0, 0, 0),
			}
		},
		# Contact - left heel strike
		{
			"duration": 0.25,
			"pose": {
				"spine": Vector3(3, 0, 0),
				"spine_1": Vector3(5, -2, 0),
				"spine_2": Vector3(3, 0, 0),
				"neck": Vector3(-8, 0, 0),
				"head": Vector3(0, 0, 0),
				"upper_arm_L": Vector3(25, 0, 25),  # Left arm forward
				"forearm_L": Vector3(0, 0, 25),
				"upper_arm_R": Vector3(-20, 0, -25),# Right arm back
				"forearm_R": Vector3(0, 0, -20),
				"thigh_L": Vector3(-25, 0, 0),     # Left leg back
				"shin_L": Vector3(35, 0, 0),
				"foot_L": Vector3(-15, 0, 0),
				"thigh_R": Vector3(25, 0, 0),      # Right leg forward
				"shin_R": Vector3(5, 0, 0),
				"foot_R": Vector3(10, 0, 0),
			}
		},
		# Passing - right leg swinging through
		{
			"duration": 0.25,
			"pose": {
				"spine": Vector3(3, 0, 0),
				"spine_1": Vector3(5, 0, 0),
				"spine_2": Vector3(3, 0, 0),
				"neck": Vector3(-8, 0, 0),
				"head": Vector3(0, 0, 0),
				"upper_arm_L": Vector3(-5, 0, 25),
				"forearm_L": Vector3(0, 0, 15),
				"upper_arm_R": Vector3(5, 0, -25),
				"forearm_R": Vector3(0, 0, -15),
				"thigh_L": Vector3(-5, 0, 0),
				"shin_L": Vector3(10, 0, 0),
				"foot_L": Vector3(0, 0, 0),
				"thigh_R": Vector3(5, 0, 0),
				"shin_R": Vector3(40, 0, 0),        # Knee bent during swing
				"foot_R": Vector3(-10, 0, 0),
			}
		},
	],

	# =========================================================================
	# RUNNING CYCLE - Combat rush
	# =========================================================================
	"run": [
		# Right foot contact, aggressive lean
		{
			"duration": 0.15,
			"pose": {
				"spine": Vector3(15, 0, 0),        # More forward lean
				"spine_1": Vector3(10, 3, 0),
				"spine_2": Vector3(5, 0, 0),
				"neck": Vector3(-20, 0, 0),
				"head": Vector3(-5, 0, 0),
				"upper_arm_L": Vector3(-35, 10, 30),
				"forearm_L": Vector3(0, 0, 70),    # Arms bent more
				"upper_arm_R": Vector3(45, -10, -35),
				"forearm_R": Vector3(0, 0, -75),
				"thigh_L": Vector3(50, 0, 0),
				"shin_L": Vector3(15, 0, 0),
				"foot_L": Vector3(20, 0, 0),
				"thigh_R": Vector3(-40, 0, 0),
				"shin_R": Vector3(60, 0, 0),
				"foot_R": Vector3(-30, 0, 0),
			}
		},
		# Flight phase - both feet off ground
		{
			"duration": 0.1,
			"pose": {
				"spine": Vector3(18, 0, 0),
				"spine_1": Vector3(10, 0, 0),
				"spine_2": Vector3(5, 0, 0),
				"neck": Vector3(-22, 0, 0),
				"head": Vector3(-5, 0, 0),
				"upper_arm_L": Vector3(5, 5, 28),
				"forearm_L": Vector3(0, 0, 50),
				"upper_arm_R": Vector3(-5, -5, -28),
				"forearm_R": Vector3(0, 0, -50),
				"thigh_L": Vector3(15, 0, 0),
				"shin_L": Vector3(65, 0, 0),       # Recovery
				"foot_L": Vector3(-20, 0, 0),
				"thigh_R": Vector3(10, 0, 0),
				"shin_R": Vector3(50, 0, 0),
				"foot_R": Vector3(-10, 0, 0),
			}
		},
		# Left foot contact
		{
			"duration": 0.15,
			"pose": {
				"spine": Vector3(15, 0, 0),
				"spine_1": Vector3(10, -3, 0),
				"spine_2": Vector3(5, 0, 0),
				"neck": Vector3(-20, 0, 0),
				"head": Vector3(-5, 0, 0),
				"upper_arm_L": Vector3(45, 10, 35),
				"forearm_L": Vector3(0, 0, 75),
				"upper_arm_R": Vector3(-35, -10, -30),
				"forearm_R": Vector3(0, 0, -70),
				"thigh_L": Vector3(-40, 0, 0),
				"shin_L": Vector3(60, 0, 0),
				"foot_L": Vector3(-30, 0, 0),
				"thigh_R": Vector3(50, 0, 0),
				"shin_R": Vector3(15, 0, 0),
				"foot_R": Vector3(20, 0, 0),
			}
		},
		# Flight phase
		{
			"duration": 0.1,
			"pose": {
				"spine": Vector3(18, 0, 0),
				"spine_1": Vector3(10, 0, 0),
				"spine_2": Vector3(5, 0, 0),
				"neck": Vector3(-22, 0, 0),
				"head": Vector3(-5, 0, 0),
				"upper_arm_L": Vector3(-5, 5, 28),
				"forearm_L": Vector3(0, 0, 50),
				"upper_arm_R": Vector3(5, -5, -28),
				"forearm_R": Vector3(0, 0, -50),
				"thigh_L": Vector3(10, 0, 0),
				"shin_L": Vector3(50, 0, 0),
				"foot_L": Vector3(-10, 0, 0),
				"thigh_R": Vector3(15, 0, 0),
				"shin_R": Vector3(65, 0, 0),
				"foot_R": Vector3(-20, 0, 0),
			}
		},
	],

	# =========================================================================
	# CRAWLING CYCLE - Prone movement
	# =========================================================================
	"crawl": [
		# Right arm, left leg forward
		{
			"duration": 0.4,
			"pose": {
				"spine": Vector3(75, 0, 0),
				"spine_1": Vector3(10, 3, 0),
				"spine_2": Vector3(5, 0, 0),
				"neck": Vector3(-70, -3, 0),
				"head": Vector3(-15, 0, 0),
				"upper_arm_L": Vector3(70, 25, 55),
				"forearm_L": Vector3(0, 0, 25),
				"upper_arm_R": Vector3(95, -30, -60),  # Right arm reaching
				"forearm_R": Vector3(0, 0, -30),
				"thigh_L": Vector3(20, 0, -25),        # Left leg bent up
				"shin_L": Vector3(35, 0, 0),
				"foot_L": Vector3(-5, 0, 0),
				"thigh_R": Vector3(-5, 0, 15),
				"shin_R": Vector3(10, 0, 0),
				"foot_R": Vector3(-5, 0, 0),
			}
		},
		# Middle - switching
		{
			"duration": 0.2,
			"pose": {
				"spine": Vector3(75, 0, 0),
				"spine_1": Vector3(10, 0, 0),
				"spine_2": Vector3(5, 0, 0),
				"neck": Vector3(-70, 0, 0),
				"head": Vector3(-15, 0, 0),
				"upper_arm_L": Vector3(80, 28, 58),
				"forearm_L": Vector3(0, 0, 28),
				"upper_arm_R": Vector3(78, -28, -58),
				"forearm_R": Vector3(0, 0, -28),
				"thigh_L": Vector3(5, 0, -18),
				"shin_L": Vector3(15, 0, 0),
				"foot_L": Vector3(-5, 0, 0),
				"thigh_R": Vector3(5, 0, 18),
				"shin_R": Vector3(15, 0, 0),
				"foot_R": Vector3(-5, 0, 0),
			}
		},
		# Left arm, right leg forward
		{
			"duration": 0.4,
			"pose": {
				"spine": Vector3(75, 0, 0),
				"spine_1": Vector3(10, -3, 0),
				"spine_2": Vector3(5, 0, 0),
				"neck": Vector3(-70, 3, 0),
				"head": Vector3(-15, 0, 0),
				"upper_arm_L": Vector3(95, 30, 60),    # Left arm reaching
				"forearm_L": Vector3(0, 0, 30),
				"upper_arm_R": Vector3(70, -25, -55),
				"forearm_R": Vector3(0, 0, -25),
				"thigh_L": Vector3(-5, 0, -15),
				"shin_L": Vector3(10, 0, 0),
				"foot_L": Vector3(-5, 0, 0),
				"thigh_R": Vector3(20, 0, 25),         # Right leg bent up
				"shin_R": Vector3(35, 0, 0),
				"foot_R": Vector3(-5, 0, 0),
			}
		},
		# Middle - switching back
		{
			"duration": 0.2,
			"pose": {
				"spine": Vector3(75, 0, 0),
				"spine_1": Vector3(10, 0, 0),
				"spine_2": Vector3(5, 0, 0),
				"neck": Vector3(-70, 0, 0),
				"head": Vector3(-15, 0, 0),
				"upper_arm_L": Vector3(78, 28, 58),
				"forearm_L": Vector3(0, 0, 28),
				"upper_arm_R": Vector3(80, -28, -58),
				"forearm_R": Vector3(0, 0, -28),
				"thigh_L": Vector3(5, 0, -18),
				"shin_L": Vector3(15, 0, 0),
				"foot_L": Vector3(-5, 0, 0),
				"thigh_R": Vector3(5, 0, 18),
				"shin_R": Vector3(15, 0, 0),
				"foot_R": Vector3(-5, 0, 0),
			}
		},
	],

	# =========================================================================
	# CROUCH WALK CYCLE
	# =========================================================================
	"crouch_walk": [
		{
			"duration": 0.3,
			"pose": {
				"spine": Vector3(20, 0, 0),
				"spine_1": Vector3(15, 2, 0),
				"spine_2": Vector3(10, 0, 0),
				"neck": Vector3(-25, 0, 0),
				"head": Vector3(-5, 0, 0),
				"upper_arm_L": Vector3(20, 12, 32),
				"forearm_L": Vector3(0, 0, 28),
				"upper_arm_R": Vector3(25, -15, -35),
				"forearm_R": Vector3(0, 0, -30),
				"thigh_L": Vector3(-45, -8, 0),
				"shin_L": Vector3(85, 0, 0),
				"foot_L": Vector3(-35, 0, 0),
				"thigh_R": Vector3(-70, 8, 0),
				"shin_R": Vector3(110, 0, 0),
				"foot_R": Vector3(-45, 0, 0),
			}
		},
		{
			"duration": 0.3,
			"pose": {
				"spine": Vector3(20, 0, 0),
				"spine_1": Vector3(15, -2, 0),
				"spine_2": Vector3(10, 0, 0),
				"neck": Vector3(-25, 0, 0),
				"head": Vector3(-5, 0, 0),
				"upper_arm_L": Vector3(25, 15, 35),
				"forearm_L": Vector3(0, 0, 30),
				"upper_arm_R": Vector3(20, -12, -32),
				"forearm_R": Vector3(0, 0, -28),
				"thigh_L": Vector3(-70, -8, 0),
				"shin_L": Vector3(110, 0, 0),
				"foot_L": Vector3(-45, 0, 0),
				"thigh_R": Vector3(-45, 8, 0),
				"shin_R": Vector3(85, 0, 0),
				"foot_R": Vector3(-35, 0, 0),
			}
		},
	],
}


## Get a pose by name
static func get_pose(pose_name: String) -> Dictionary:
	if POSES.has(pose_name):
		return POSES[pose_name].duplicate(true)
	return {}


## Get a cycle by name
static func get_cycle(cycle_name: String) -> Array:
	if CYCLES.has(cycle_name):
		return CYCLES[cycle_name].duplicate(true)
	return []


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
