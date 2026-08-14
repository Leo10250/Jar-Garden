class_name JarDefinition
extends Resource


## Static content for a selectable jar. All prototype balance and colors are TBD.
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export_group("Prototype Economy and Capacity (TBD)")
@export_range(0, 1000000, 1, "or_greater") var price: int = 0
@export_range(1, 1000, 1, "or_greater") var capacity: int = 10

@export_group("Prototype Glass Palette (TBD)")
@export var glass_fill_color: Color = Color(0.78, 0.93, 0.96, 0.24)
@export var glass_border_color: Color = Color(0.89, 0.98, 1.0, 0.82)

@export_group("Prototype Environment Modifiers (TBD)")
## Baseline is 1.0; larger values make accumulated water evaporate faster.
@export_range(0.0, 100.0, 0.01, "or_greater") var evaporation_modifier: float = 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var spawn_modifier: float = 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var reproduction_modifier: float = 1.0
