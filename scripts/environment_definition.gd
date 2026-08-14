class_name EnvironmentDefinition
extends Resource


## Static content for a selectable background/environment.
## Palette, labels, prices, and modifiers are prototype placeholders/TBD.
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export_group("Prototype Economy (TBD)")
@export_range(0, 1000000, 1, "or_greater") var price: int = 0

@export_group("Prototype Palette and Weather Label (TBD)")
@export var sky_color: Color = Color(0.58, 0.76, 0.69, 1.0)
@export var ground_color: Color = Color(0.24, 0.43, 0.29, 1.0)
@export var accent_color: Color = Color(0.31, 0.53, 0.39, 1.0)
@export var visual_style: StringName = &"forest"
## Local placeholder only; this is not an online weather source or API value.
@export var local_weather_label: String = "Calm"

@export_group("Prototype Environment Modifiers (TBD)")
@export_range(0.0, 100.0, 0.01, "or_greater") var evaporation_modifier: float = 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var spawn_modifier: float = 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var reproduction_modifier: float = 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var mutation_modifier: float = 1.0
