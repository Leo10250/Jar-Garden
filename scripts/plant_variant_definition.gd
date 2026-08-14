class_name PlantVariantDefinition
extends Resource


## Static content for one visually distinct plant variant.
## All prototype catalog values and selectors remain replaceable/TBD.
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var rarity: StringName = &"common"

@export_group("Prototype Visuals (TBD)")
@export var body_color: Color = Color(0.985, 0.985, 0.97, 1.0)
@export var head_accessory: StringName = &"none"
@export var equipment: StringName = &"none"

@export_group("Prototype Balance (TBD)")
@export_range(0.0, 1000.0, 0.01, "or_greater") var mutation_weight: float = 0.0
## Baseline is 1.0; larger values mean the variant is harder to reproduce.
@export_range(0.01, 100.0, 0.01, "or_greater") var reproduction_difficulty: float = 1.0
@export_range(0, 1000000, 1, "or_greater") var adult_sell_value: int = 1
@export_range(0, 1000000, 1, "or_greater") var young_buy_price: int = 1
