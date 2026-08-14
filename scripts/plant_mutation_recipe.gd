class_name PlantMutationRecipe
extends Resource


const LIGHT_BALANCED: StringName = &"balanced"
const WATER_DRY: StringName = &"dry"
const WATER_MOIST: StringName = &"moist"
const WATER_WET: StringName = &"wet"
const WATER_SUBMERGED: StringName = &"submerged"


## Data-only prototype recipe for choosing an environment-shaped mutation.
## The tuning resource owns the shared categorical thresholds.
@export var id: StringName = &""
@export var target_variant_id: StringName = &""
@export_range(0.0, 1000.0, 0.01, "or_greater") var weight: float = 1.0

@export_group("Allowed Birth Sources")
@export var allows_environmental: bool = true
@export var allows_reproduction: bool = true

@export_group("Current Environment Requirements")
## Empty means any environment, light profile, or water profile.
@export var required_environment_id: StringName = &""
@export var required_light_state: StringName = &""
@export var required_water_state: StringName = &""

@export_group("Reproduction Requirements")
## Requirements are unordered. An empty array accepts any parents.
@export var required_parent_variant_ids: Array[StringName] = []


func supports_source(source: StringName) -> bool:
	if source == PlantState.SOURCE_ENVIRONMENTAL:
		return allows_environmental
	if source == PlantState.SOURCE_REPRODUCTION:
		return allows_reproduction
	return false
