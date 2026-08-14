class_name PlantVisualDefinition
extends Resource


## Replaceable presentation data for a plant variant.
## Texture layers share one centered transparent canvas. The fallback blob is
## used whenever main_texture is absent, so content can migrate incrementally.
@export_group("Layered Artwork")
@export var back_texture: Texture2D
@export var main_texture: Texture2D
@export var front_texture: Texture2D
@export var visual_offset: Vector2 = Vector2.ZERO
@export var visual_scale: Vector2 = Vector2.ONE

@export_group("Hitbox")
## Adult hitbox dimensions in the PlantView's logical pixels.
@export var hitbox_size: Vector2 = Vector2(84.0, 72.0)
@export var hitbox_offset: Vector2 = Vector2.ZERO
## Optional centered convex polygon in Adult logical pixels for silhouettes
## that need more than the default rounded hitbox generated from hitbox_size.
@export var hitbox_polygon: PackedVector2Array = PackedVector2Array()

@export_group("Lifecycle Presentation — Prototype/TBD")
@export_range(0.25, 2.0, 0.01) var young_scale: float = 0.78
@export_range(0.25, 2.0, 0.01) var adult_scale: float = 1.0
@export_range(0.25, 2.0, 0.01) var old_scale: float = 0.92
@export_range(0.2, 10.0, 0.05) var young_motion_period_seconds: float = 1.35
@export_range(0.2, 10.0, 0.05) var adult_motion_period_seconds: float = 1.9
@export_range(0.2, 10.0, 0.05) var old_motion_period_seconds: float = 2.8
@export_range(0.0, 12.0, 0.1) var idle_bob_pixels: float = 1.4
@export_range(0.0, 0.2, 0.001) var idle_squash_amount: float = 0.018


func get_lifecycle_scale(lifecycle_stage: int) -> float:
	match lifecycle_stage:
		0:
			return young_scale
		2:
			return old_scale
		_:
			return adult_scale


func get_motion_period_seconds(lifecycle_stage: int) -> float:
	match lifecycle_stage:
		0:
			return young_motion_period_seconds
		2:
			return old_motion_period_seconds
		_:
			return adult_motion_period_seconds
