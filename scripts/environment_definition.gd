class_name EnvironmentDefinition
extends Resource


## Static content for a selectable background/environment.
## Palette, labels, prices, and modifiers are prototype placeholders/TBD.
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var display_name_key: StringName = &""
@export var description_key: StringName = &""

@export_group("Layered Artwork")
## Portrait layers share one canvas. The far layer is opaque; mid/front are
## transparent overlays. The thumbnail is a pre-composited shop preview.
@export var far_texture: Texture2D
@export var mid_texture: Texture2D
@export var front_texture: Texture2D
@export var thumbnail_texture: Texture2D

@export_group("Prototype Economy (TBD)")
@export_range(0, 1000000, 1, "or_greater") var price: int = 0

@export_group("Prototype Palette and Weather Label (TBD)")
@export var sky_color: Color = Color(0.58, 0.76, 0.69, 1.0)
@export var ground_color: Color = Color(0.24, 0.43, 0.29, 1.0)
@export var accent_color: Color = Color(0.31, 0.53, 0.39, 1.0)
@export var visual_style: StringName = &"forest"
## Local placeholder only; this is not an online weather source or API value.
@export var local_weather_label: String = "Calm"
@export var weather_label_key: StringName = &""

@export_group("Prototype Environment Modifiers (TBD)")
@export_range(0.0, 100.0, 0.01, "or_greater") var evaporation_modifier: float = 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var spawn_modifier: float = 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var reproduction_modifier: float = 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var mutation_modifier: float = 1.0
