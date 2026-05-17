extends RefCounted
## Vietnam War location presets for campaigns and missions
## Extracted from map_maker/vietnam_world_grid.gd before archival

## =============================================================================
## REAL VIETNAM LOCATION PRESETS
## =============================================================================
const LOCATION_PRESETS: Dictionary = {
	# Ia Drang Valley - 1965
	"ia_drang": {
		"name": "Ia Drang Valley",
		"campaign_year": 1965,
		"features": {
			"lz_xray": Vector2(1000, 400),  # Converted to world coords
			"lz_albany": Vector2(1200, 600),
			"chu_pong_massif": Vector2(800, 200),
			"plei_me": Vector2(1400, 800),
		},
		"default_terrain": "triple_canopy",
		"description": "Site of the first major battle between US and NVA forces",
	},

	# A Shau Valley - Multiple operations
	"a_shau": {
		"name": "A Shau Valley",
		"campaign_year": 1966,
		"features": {
			"valley_floor": Vector2(200, -1200),
			"ho_chi_minh_trail": Vector2(0, -1000),
			"firebase_bastogne": Vector2(400, -1600),
		},
		"default_terrain": "triple_canopy",
		"description": "Major NVA infiltration route, heavily contested valley",
	},

	# Khe Sanh - 1968 Siege
	"khe_sanh": {
		"name": "Khe Sanh Combat Base",
		"campaign_year": 1968,
		"features": {
			"combat_base": Vector2(-800, -1200),
			"hill_881s": Vector2(-1000, -1400),
			"hill_861": Vector2(-600, -1400),
			"hill_881n": Vector2(-1000, -1600),
			"lang_vei": Vector2(-400, -1000),
		},
		"default_terrain": "hill",
		"description": "77-day siege, massive NVA assault, B-52 Arc Light support",
	},

	# Hue City - Tet Offensive 1968
	"hue": {
		"name": "Hue City",
		"campaign_year": 1968,
		"features": {
			"citadel": Vector2(2400, 400),
			"perfume_river": Vector2(2200, 600),
			"macv_compound": Vector2(2600, 600),
			"university": Vector2(2800, 400),
		},
		"default_terrain": "urban",
		"description": "Urban combat during Tet Offensive, house-to-house fighting",
	},

	# Hamburger Hill - 1969
	"hamburger_hill": {
		"name": "Hamburger Hill (Ap Bia)",
		"campaign_year": 1969,
		"features": {
			"hill_937": Vector2(200, -600),
			"firebase_airborne": Vector2(400, -400),
		},
		"default_terrain": "triple_canopy",
		"description": "Infamous assault on Hill 937, high casualties",
	},

	# Central Highlands - Multiple operations
	"central_highlands": {
		"name": "Central Highlands",
		"campaign_year": 1965,
		"features": {
			"pleiku": Vector2(-1000, 0),
			"kontum": Vector2(-600, -600),
			"an_khe": Vector2(400, 400),
		},
		"default_terrain": "single_canopy",
		"description": "Strategic highland region, key battlefield",
	},

	# Mekong Delta
	"mekong_delta": {
		"name": "Mekong Delta",
		"campaign_year": 1967,
		"features": {
			"can_tho": Vector2(2000, 4000),
			"my_tho": Vector2(1600, 3600),
		},
		"default_terrain": "rice_paddy",
		"description": "Riverine warfare, VC stronghold, flooded terrain",
	},
}


## Get location by key
static func get_location(key: String) -> Dictionary:
	return LOCATION_PRESETS.get(key, {})


## Get all location keys
static func get_all_locations() -> Array[String]:
	var keys: Array[String] = []
	for key in LOCATION_PRESETS.keys():
		keys.append(key)
	return keys


## Get locations by campaign year
static func get_locations_by_year(year: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in LOCATION_PRESETS:
		var loc: Dictionary = LOCATION_PRESETS[key]
		if loc.get("campaign_year", 0) == year:
			result.append(loc)
	return result
