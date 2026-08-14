class_name MvpTuning
extends Resource


## Phase 2 prototype balance. These values are deliberately easy to observe
## during development and are not permanent game-design decisions.
@export_range(1.0, 86400.0, 1.0, "or_greater") var young_duration_seconds: float = 60.0
@export_range(1.0, 86400.0, 1.0, "or_greater") var adult_duration_seconds: float = 120.0
@export_range(0.1, 60.0, 0.1, "or_greater") var foreground_tick_seconds: float = 1.0
@export_range(1.0, 3600.0, 1.0, "or_greater") var autosave_interval_seconds: float = 30.0

@export_group("Water — Prototype")
@export_range(0.01, 1.0, 0.01) var water_level_per_press: float = 0.22
@export_range(0.01, 1.0, 0.01) var top_wetness_per_press: float = 0.42
@export_range(0.0, 1.0, 0.01) var bottom_watering_multiplier: float = 0.25
@export_range(0.00001, 0.1, 0.00001) var water_evaporation_per_second: float = 0.0025
@export_range(0.00001, 0.1, 0.00001) var wetness_decay_per_second: float = 0.0018
@export_range(0.00001, 0.2, 0.00001) var submerged_wetting_per_second: float = 0.015
@export_range(0.01, 1.0, 0.01) var plant_water_footprint_height: float = 0.16
@export_range(0.0, 1.0, 0.01) var extreme_wetness_threshold: float = 0.85

@export_group("Device Light — Prototype")
@export_range(0, 23, 1) var day_start_hour: int = 6
@export_range(0, 23, 1) var day_end_hour: int = 18
@export_range(0.0, 3.0, 0.05) var day_spawn_multiplier: float = 1.05
@export_range(0.0, 3.0, 0.05) var night_spawn_multiplier: float = 0.95
@export_range(0.0, 3.0, 0.05) var day_reproduction_multiplier: float = 1.0
@export_range(0.0, 3.0, 0.05) var night_reproduction_multiplier: float = 1.1
@export_range(0.0, 3.0, 0.05) var day_mutation_multiplier: float = 0.9
@export_range(0.0, 3.0, 0.05) var night_mutation_multiplier: float = 1.15

@export_group("Reproduction — Prototype")
@export_range(0.01, 1.0, 0.01) var reproduction_contact_distance: float = 0.17
@export_range(1.0, 86400.0, 1.0) var reproduction_attempt_seconds: float = 20.0
@export_range(0.0, 1.0, 0.01) var reproduction_base_success_chance: float = 0.55
@export_range(1.0, 5.0, 0.05) var same_variant_success_multiplier: float = 1.35
@export_range(0.0, 1.0, 0.01) var reproduction_mutation_chance: float = 0.16
@export_range(0.0, 0.25, 0.01) var offspring_position_jitter: float = 0.05
@export_range(1, 5, 1) var reproduction_limit_min: int = 1
@export_range(1, 5, 1) var reproduction_limit_max: int = 5

@export_group("Automatic Spawning — Prototype")
@export_range(1.0, 86400.0, 1.0) var spawn_interval_min_seconds: float = 45.0
@export_range(1.0, 86400.0, 1.0) var spawn_interval_max_seconds: float = 75.0
@export_range(0.0, 1.0, 0.01) var spawn_base_success_chance: float = 0.65
@export_range(0.0, 1.0, 0.01) var spawn_mutation_chance: float = 0.18
@export_range(1, 4096, 1) var maximum_events_per_advance: int = 512

@export_group("Economy — Prototype")
@export_range(0, 100000, 1) var initial_coins: int = 20
