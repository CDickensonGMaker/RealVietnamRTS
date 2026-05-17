class_name SquadData extends Resource
## Squad Data Resource - Defines unit stats and properties
## Create .tres files for each unit type

@export_group("Identity")
@export var display_name: String = "Squad"
@export var unit_type: int = 0  # GameEnums.UnitType
@export var faction: int = 0    # GameEnums.Faction

@export_group("Composition")
@export var squad_size: int = 10  # Number of soldiers
@export var model_scene: PackedScene  # Optional: custom model scene

@export_group("Model Transform")
@export var model_path: String = ""  # Path to GLB model file
@export var model_scale: float = 1.0  # Uniform scale multiplier
@export var model_rotation_y: float = 0.0  # Y-axis rotation in degrees (facing direction)
@export var model_offset_y: float = 0.0  # Vertical offset from ground

@export_group("Combat Stats")
@export var health_per_soldier: float = 100.0
@export var damage_per_second: float = 10.0
@export var attack_range: float = 25.0
@export var armor: float = 0.0
## Training level affects suppression resistance and recovery
## CONSCRIPT=0, REGULAR=1, VETERAN=2, ELITE=3
@export_range(0, 3) var training_level: int = 1  # Default to REGULAR

@export_group("Movement")
@export var move_speed: float = 5.0
@export var rotation_speed: float = 3.0

## --- Slope/Verticality ----------------------------------------------------
## max_slope: hard cutoff above which the unit refuses to move (0-1, where
##   slope 0 = flat ground and slope 1 = vertical wall, matching gameplay_grid).
## slope_speed_penalty: linear penalty applied as slope approaches max_slope.
##   At slope == 0: full speed.
##   At slope == max_slope: speed = move_speed * (1 - slope_speed_penalty).
## Suggested defaults by class (set in .tres files):
##   Infantry: max_slope = 0.65, slope_speed_penalty = 0.7  (steep but slow)
##   Tank:     max_slope = 0.35, slope_speed_penalty = 0.6
##   Wheeled:  max_slope = 0.25, slope_speed_penalty = 0.7
##   Artillery (mobile): max_slope = 0.20, slope_speed_penalty = 0.8
@export_range(0.0, 1.0) var max_slope: float = 0.65
@export_range(0.0, 1.0) var slope_speed_penalty: float = 0.7

@export_group("Detection")
@export var sight_range: float = 30.0
@export var stealth_rating: float = 0.0  # 0.0 = visible, 1.0 = hard to detect

@export_group("Special")
@export var can_build: bool = false
@export var can_capture: bool = false
@export var is_vehicle: bool = false
## If true, this unit can pack up and redeploy (artillery, mortars).
## Static guns/howitzers should leave this false.
@export var can_redeploy: bool = true


## Get total squad health
func get_total_health() -> float:
	return health_per_soldier * squad_size


## Compute effective move speed at a given slope value (0..1).
## Returns 0.0 if slope exceeds max_slope (unit cannot enter the cell).
func get_speed_at_slope(slope_value: float) -> float:
	if slope_value >= max_slope:
		return 0.0
	# Linear interpolation: full speed at 0, (1 - penalty) * speed at max_slope
	var t: float = slope_value / max_slope if max_slope > 0.0 else 0.0
	var multiplier: float = 1.0 - (slope_speed_penalty * t)
	return move_speed * multiplier


## Check if the unit can traverse the given slope at all.
func can_traverse_slope(slope_value: float) -> bool:
	return slope_value < max_slope


## Get faction color for placeholder visuals
func get_faction_color() -> Color:
	match faction:
		GameEnums.Faction.US_ARMY:
			return Color(0.2, 0.6, 0.2)  # Green
		GameEnums.Faction.ARVN:
			return Color(0.4, 0.6, 0.3)  # Light green
		GameEnums.Faction.VC:
			return Color(0.6, 0.3, 0.1)  # Brown
		GameEnums.Faction.NVA:
			return Color(0.5, 0.2, 0.2)  # Dark red
		_:
			return Color(0.5, 0.5, 0.5)  # Gray
