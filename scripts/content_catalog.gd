class_name ContentCatalog
extends Resource


## Small, inspectable prototype content catalog. Content remains data-driven so
## placeholder art and TBD balance can be replaced without changing game state.
@export var plant_variants: Array[PlantVariantDefinition] = []
@export var jars: Array[JarDefinition] = []
@export var environments: Array[EnvironmentDefinition] = []


func get_variant(variant_id: StringName) -> PlantVariantDefinition:
	for definition in plant_variants:
		if definition != null and definition.id == variant_id:
			return definition
	return null


func get_jar(jar_id: StringName) -> JarDefinition:
	for definition in jars:
		if definition != null and definition.id == jar_id:
			return definition
	return null


func get_environment(environment_id: StringName) -> EnvironmentDefinition:
	for definition in environments:
		if definition != null and definition.id == environment_id:
			return definition
	return null
