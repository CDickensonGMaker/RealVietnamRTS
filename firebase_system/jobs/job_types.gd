class_name JobTypes
extends RefCounted
## JobTypes - Enum and static helpers for construction job types
##
## Used by JobNode and JobManager to classify work types and determine
## worker requirements and default work amounts.

## Job type enumeration
enum JobType {
	CLEAR_TERRAIN,    ## Remove vegetation from an area
	FLATTEN_AREA,     ## Level terrain to a consistent height
	BUILD_ROAD,       ## Create a dirt path between points
	BUILD_STRUCTURE,  ## Construct a building
	FILL_CRATER,      ## Fill bomb/artillery craters
}

## Completion state for jobs
enum CompletionState {
	PENDING,      ## Job created but no workers assigned
	IN_PROGRESS,  ## Workers actively working on job
	COMPLETE,     ## Job finished successfully
	CANCELLED,    ## Job was cancelled by player
}

## Worker class requirements
const WORKER_ENGINEER := "engineer"
const WORKER_BULLDOZER := "bulldozer"

## Clearing balance reference:
## - 1 engineer clears 1 tree in 3.5 seconds
## - 1 bulldozer clears 1 tree in 7 seconds (half engineer speed)
## - Multiple workers stack their work rates
##
## Tree density: approximately 0.5 trees per square meter in jungle
## So a 10x10m area has ~50 trees, requiring 50 work units
const TREES_PER_SQM := 0.5  # Average tree density

## Default work units per square meter for area jobs
## CLEAR: each tree = 1 work unit, ~0.5 trees/sqm
const WORK_PER_SQM_CLEAR := TREES_PER_SQM  # 0.5 work per sqm (1 work per tree)
const WORK_PER_SQM_FLATTEN := 0.75  # Flattening is faster than clearing
const WORK_PER_METER_ROAD := 1.0
const WORK_PER_CRATER := 15.0  # Craters are quick to fill

## Get the default work required for a job type and area
static func get_default_work(job_type: JobType, area_size: float) -> float:
	match job_type:
		JobType.CLEAR_TERRAIN:
			return area_size * WORK_PER_SQM_CLEAR
		JobType.FLATTEN_AREA:
			return area_size * WORK_PER_SQM_FLATTEN
		JobType.BUILD_ROAD:
			# area_size is path length in meters
			return area_size * WORK_PER_METER_ROAD
		JobType.BUILD_STRUCTURE:
			# Buildings have their own work stages; use 100 as base
			return 100.0
		JobType.FILL_CRATER:
			return WORK_PER_CRATER
		_:
			return 50.0


## Get the required worker class for a job type
static func get_required_worker_class(job_type: JobType) -> String:
	match job_type:
		JobType.CLEAR_TERRAIN:
			return WORKER_ENGINEER  # Engineers can clear with det-cord
		JobType.FLATTEN_AREA:
			return WORKER_BULLDOZER  # Bulldozers level terrain
		JobType.BUILD_ROAD:
			return WORKER_ENGINEER  # Engineers build roads
		JobType.BUILD_STRUCTURE:
			return WORKER_ENGINEER  # Engineers construct buildings
		JobType.FILL_CRATER:
			return WORKER_BULLDOZER  # Bulldozers fill craters
		_:
			return WORKER_ENGINEER


## Get a human-readable name for a job type
static func get_job_name(job_type: JobType) -> String:
	match job_type:
		JobType.CLEAR_TERRAIN:
			return "Clearing"
		JobType.FLATTEN_AREA:
			return "Flattening"
		JobType.BUILD_ROAD:
			return "Road"
		JobType.BUILD_STRUCTURE:
			return "Building"
		JobType.FILL_CRATER:
			return "Fill Crater"
		_:
			return "Unknown"


## Get the progress stage label for display
static func get_stage_label(job_type: JobType, progress_percent: float) -> String:
	match job_type:
		JobType.CLEAR_TERRAIN:
			if progress_percent < 30.0:
				return "Clearing %d%%" % int(progress_percent)
			elif progress_percent < 70.0:
				return "Removing stumps %d%%" % int(progress_percent)
			else:
				return "Finishing %d%%" % int(progress_percent)

		JobType.FLATTEN_AREA:
			if progress_percent < 50.0:
				return "Grading %d%%" % int(progress_percent)
			else:
				return "Leveling %d%%" % int(progress_percent)

		JobType.BUILD_ROAD:
			return "Paving %d%%" % int(progress_percent)

		JobType.BUILD_STRUCTURE:
			if progress_percent < 20.0:
				return "Foundation"
			elif progress_percent < 50.0:
				return "Framing"
			elif progress_percent < 75.0:
				return "Walls"
			elif progress_percent < 95.0:
				return "Roofing"
			else:
				return "Finishing"

		JobType.FILL_CRATER:
			return "Filling %d%%" % int(progress_percent)

		_:
			return "Working %d%%" % int(progress_percent)


## Check if a worker type can work on a job type
static func can_worker_do_job(worker_class: String, job_type: JobType) -> bool:
	var required: String = get_required_worker_class(job_type)

	# Exact match
	if worker_class == required:
		return true

	# Engineers can also do bulldozer work (slower)
	if worker_class == WORKER_ENGINEER:
		return true  # Engineers can do everything, just slower

	# Bulldozers can only do terrain work
	if worker_class == WORKER_BULLDOZER:
		return job_type in [JobType.CLEAR_TERRAIN, JobType.FLATTEN_AREA, JobType.FILL_CRATER]

	return false


## Get work rate multiplier for a worker doing a job
## NOTE: Clearing balance is inverted from typical RTS:
## - Engineers clear FASTER than bulldozers (det-cord is quick)
## - Bulldozers are better for flattening and road work
static func get_work_rate_multiplier(worker_class: String, job_type: JobType) -> float:
	# Clearing: engineers are 2x faster than bulldozers (3.5s vs 7s per tree)
	if job_type == JobType.CLEAR_TERRAIN:
		if worker_class == WORKER_ENGINEER:
			return 1.0  # Engineers are the baseline for clearing
		elif worker_class == WORKER_BULLDOZER:
			return 0.5  # Bulldozers clear at half the rate (7s vs 3.5s per tree)
		return 1.0

	# Flattening: bulldozers are primary, engineers are slow
	if job_type == JobType.FLATTEN_AREA:
		if worker_class == WORKER_BULLDOZER:
			return 1.0
		elif worker_class == WORKER_ENGINEER:
			return 0.3  # Engineers can flatten but slowly
		return 1.0

	# Roads: engineers primary
	if job_type == JobType.BUILD_ROAD:
		if worker_class == WORKER_ENGINEER:
			return 1.0
		elif worker_class == WORKER_BULLDOZER:
			return 0.7  # Bulldozers can help with roads
		return 1.0

	# Fill crater: bulldozers primary
	if job_type == JobType.FILL_CRATER:
		if worker_class == WORKER_BULLDOZER:
			return 1.0
		elif worker_class == WORKER_ENGINEER:
			return 0.4
		return 1.0

	# Buildings: engineers only
	if job_type == JobType.BUILD_STRUCTURE:
		if worker_class == WORKER_ENGINEER:
			return 1.0
		return 0.0  # Bulldozers can't build

	return 1.0
