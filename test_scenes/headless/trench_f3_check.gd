extends Node3D
## Headless F3 check: TrenchNode completes, joins cover group, and CoverSystem
## grants FORTIFIED cover anywhere inside the footprint (not just the center).
## Also checks BuildingComponentFactory assigns cover tiers from cover_value.
## Run: godot --headless res://test_scenes/headless/trench_f3_check.tscn

const TrenchNodeScript = preload("res://firebase_system/nodes/trench_node.gd")
const CoverSystemScript = preload("res://battle_system/systems/cover_system.gd")
const BuildingDataScript = preload("res://firebase_system/building_data.gd")
const BuildingComponentFactory = preload("res://firebase_system/building_component_factory.gd")

var _failures: int = 0


func _ready() -> void:
	# Let the tree settle so child _ready ordering matches real gameplay
	await get_tree().process_frame
	_run_checks()
	print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(_failures)


func _run_checks() -> void:
	var trench: Node3D = TrenchNodeScript.create(Vector3(10, 0, 5), 12.0, 2.0, 0.5)
	add_child(trench)

	# Dig to completion
	var done: bool = trench.add_work(1.0)
	_check(done and trench.is_complete, "trench completes via add_work")
	_check(trench.is_in_group("cover_fortified"), "complete trench joins cover_fortified")
	_check(trench.rotation.y != 0.0, "rotation applied via factory")

	# Footprint containment: center, far end (5m from center, beyond the 2m
	# point-radius CoverSystem used to require), and a point off to the side
	var end_pt: Vector3 = trench.to_global(Vector3(5, 0, 0))
	var side_pt: Vector3 = trench.to_global(Vector3(0, 0, 3))
	_check(trench.is_position_inside(trench.global_position), "center inside")
	_check(trench.is_position_inside(end_pt), "trench end inside")
	_check(not trench.is_position_inside(side_pt), "beside trench outside")

	# CoverSystem sees the trench along its full length
	var cs: Node = CoverSystemScript.new()
	add_child(cs)
	var cover_end: int = cs.get_cover_at_position(end_pt)
	var cover_side: int = cs.get_cover_at_position(side_pt)
	_check(cover_end == GameEnums.CoverType.FORTIFIED, "FORTIFIED cover at trench end (got %d)" % cover_end)
	_check(cover_side != GameEnums.CoverType.FORTIFIED, "no trench cover beside it (got %d)" % cover_side)

	# Incomplete trench grants nothing
	var trench2: Node3D = TrenchNodeScript.create(Vector3(100, 0, 100), 8.0, 2.0)
	add_child(trench2)
	trench2.add_work(0.5)
	_check(not trench2.is_in_group("cover_fortified"), "half-dug trench grants no cover")

	# Factory cover tiers: sandbag light (0.4) -> light, foxhole (0.6) -> heavy,
	# bunker (0.8) -> fortified, mess hall (class default 0.5) -> heavy,
	# concertina wire (provides_cover = false) -> nothing
	var cases: Array = [
		[BuildingDataScript.BuildingType.SANDBAG_LIGHT, "cover_light"],
		[BuildingDataScript.BuildingType.FOXHOLE, "cover_heavy"],
		[BuildingDataScript.BuildingType.BUNKER, "cover_fortified"],
		[BuildingDataScript.BuildingType.MESS_HALL, "cover_heavy"],
		[BuildingDataScript.BuildingType.WIRE_OBSTACLE, ""],
	]
	for case in cases:
		var data: Resource = BuildingDataScript.get_building_data(case[0])
		var node := Node3D.new()
		add_child(node)
		BuildingComponentFactory.attach_building_components(node, data)
		var in_any: String = ""
		for g in ["cover_light", "cover_heavy", "cover_fortified"]:
			if node.is_in_group(g):
				in_any = g
		_check(in_any == case[1], "%s -> %s (got '%s')" % [data.display_name, case[1] if case[1] else "no cover group", in_any])


func _check(ok: bool, label: String) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", label])
	if not ok:
		_failures += 1
