# Jar Garden — Current Architecture

## Purpose

This document describes **how the current implementation is organized today**: ownership, data flow, invariants, and the usual place to make a change.

It is not the product-design source of truth. Product behavior belongs in `GAME_DESIGN.md`; milestone status belongs in `MVP_PLAN.md`; stable platform constraints belong in `PROJECT_CONTEXT.md`.

## System Overview

At a high level:

```text
Player input / lifecycle callbacks
            |
            v
        main.gd
     orchestration/UI
       /    |     \
      v     v      v
 GameState  GardenSimulator  LocalSave
 runtime    deterministic    persistence
 state      simulation
      \        /
       \      /
        v    v
 ContentCatalog + MvpTuning
 static content + prototype balance

Presentation:
PlantView / StallPanel / WaterEffects / scenes / Theme / localization
```

The important architectural property is that deterministic domain simulation can run without depending on live UI physics or arbitrary global state.

## `main.gd` — Application Orchestration

`main.gd` is the root controller for the main scene.

Responsibilities include:

- initialize/load `GameState`,
- request offline/foreground advancement through `GardenSimulator`,
- autosave and pause/resume handling,
- wire Water and Stall actions,
- synchronize runtime plant state to `PlantView` instances,
- persist drag results,
- handle buy/sell/jar/environment actions,
- reconcile missing/changed content safely,
- apply environment/jar/HUD presentation,
- coordinate water presentation and toast/error UI,
- lock interaction when catch-up or save safety requires it.

Do not move deterministic simulation rules into `main.gd` merely because the UI triggers them. `main.gd` should orchestrate; domain rules should stay in their domain owner.

## `GameState` — Persistent Mutable Domain State

`GameState` owns the state that must survive save/load or participate in deterministic continuation.

Current responsibilities include:

- save schema version,
- simulation checkpoint and frozen timezone bias,
- persisted RNG state,
- plant instances and stable instance-ID sequence,
- pooled water level,
- coins and discovered variants,
- active/owned jars and environments,
- environmental spawn schedule,
- reproduction-pair progress,
- current-environment jar cultivation history,
- minimum-ecology recovery behavior,
- serialization/deserialization,
- schema migration and structural validation.

`PlantState` owns per-plant runtime/persisted data such as lifecycle age, normalized position, wetness, reproduction counts, birth context, parent context, lifetime cultivation history, and current-environment cultivation history.

### Invariant

State serialization and migration must remain deterministic, conservative, and backwards-compatible within the supported schema range. New persisted fields require explicit migration/default behavior and tests.

## `GardenSimulator` — Deterministic Elapsed-Time Simulation

`GardenSimulator` owns gameplay changes driven by time or deterministic simulation rules.

Current domains include:

- foreground/offline advancement,
- deterministic event batching/checkpoints,
- lifecycle advancement,
- water evaporation,
- wetness and submersion integration,
- exact day/night exposure accumulation,
- reproduction contact/progress/attempts,
- environmental spawning,
- mutation probability and recipe resolution,
- cultivation-profile classification,
- jar-capacity behavior,
- environment-change settlement,
- watering state effects.

The simulator accepts explicit state/tuning/catalog/jar/environment inputs instead of reaching into the scene tree. Preserve this property.

### Online/offline equivalence

A long offline advance and equivalent smaller foreground advances should produce the same deterministic state when given the same initial state and inputs. Tests treat this as a core invariant.

### Geometry without runtime physics

Visible plant hitboxes are authored through `PlantVisualDefinition`. Reproduction reconstructs equivalent deterministic convex geometry in canonical jar coordinates rather than requiring live `Area2D` physics during offline simulation.

## `ContentCatalog` — Static Content Registry

`ContentCatalog` is a Resource containing the static selectable content used by the prototype:

- plant variants,
- jars,
- environments.

It provides stable-ID lookup. Add content here/data resources rather than hard-coding large ID switches into UI or simulation logic.

Current prototype content includes 10 plant variants, 2 jars, and 3 environments.

Stable IDs matter because save data and recipes refer to them.

## `MvpTuning` — Prototype Balance and Rules Configuration

`MvpTuning` centralizes values that are intentionally expected to change during balancing, including:

- lifecycle durations,
- foreground/autosave timing,
- water and evaporation behavior,
- day/night boundaries/modifiers,
- reproduction timing/chance/limits,
- environmental spawn timing/chance,
- mutation chance/classification thresholds,
- data-driven mutation recipes,
- initial economy values.

Do not scatter duplicate balance literals through gameplay code when a tuning seam already exists.

Values in the prototype tuning Resource are **working balance**, not automatically permanent game-design commitments.

## Mutation Recipes

`PlantMutationRecipe` represents explicit data-driven mutation eligibility instead of a genetics engine.

A recipe can constrain:

- target variant,
- environmental-spawn vs reproduction source,
- environment,
- light profile,
- water/moisture/submersion profile,
- required parent variants,
- weighted selection.

Cultivation profiles are derived from accumulated current-environment history. Natural spawning uses jar-level history; reproduction uses the two parents' profiles.

## `LocalSave` — Persistence Boundary

`LocalSave` owns disk IO and save safety.

Current behavior includes:

- JSON local save,
- validation through `GameState`,
- temporary write then verification,
- last-good backup,
- invalid-save quarantine/preservation behavior,
- backup recovery,
- unsupported/newer-schema handling.

UI controllers should not recreate ad-hoc save-file logic.

Tests use isolated temporary filesystem paths rather than relying on production `user://` state.

## `PlantView` — Plant Presentation and Interaction

`PlantView` is the reusable presentation/interaction scene for both jar plants and preview rendering.

Responsibilities include:

- apply `PlantVariantDefinition` / `PlantVisualDefinition`,
- layered back/main/front textures,
- fallback white blob rendering when art is absent,
- lifecycle scale/motion presentation,
- wetness presentation,
- authored convex hitbox creation,
- mouse/touch drag handling,
- drag collision resolution,
- contact squeeze/tilt/rebound feedback,
- exposing stable collision geometry.

Visual-only animation must not mutate persisted plant positions.

Collection/Buy/Sell previews intentionally reuse the same plant presentation path rather than maintaining unrelated duplicate renderers.

## `PlantVisualDefinition` — Art and Collision Metadata

This Resource owns replaceable presentation data for a plant variant:

- optional back/main/front textures,
- visual offset/scale,
- hitbox size/offset or authored convex polygon,
- lifecycle presentation scales,
- lifecycle motion periods,
- idle motion tuning.

The catalog's 10 prototype plants intentionally use 7 authored collision-silhouette families.

## `StallPanel` and `StallItemCard` — Collection/Economy UI

`StallPanel` owns presentation/navigation for:

- Collection,
- Market → Buy / Sell,
- Customize → Jars / Places.

It receives current state/catalog/tuning through refresh calls and emits request signals rather than directly owning persistence/simulation state transitions.

`StallItemCard` is the reusable responsive card presentation, including compact narrow-screen action layout.

Preserve the existing public signals when changing stall presentation unless an explicit API change is required.

## Water Presentation

Simulation water remains lightweight scalar state. Presentation is deliberately richer.

`WaterEffects` owns:

- smoothed visual water-level targeting,
- animated surface line,
- pour stream/drops,
- ripples.

The main scene has both rear and translucent foreground water layers so plant portions can visually read as submerged. Presentation must follow simulation state; it must not become a second gameplay state source.

## Environments

`EnvironmentDefinition` binds selectable environment metadata and layered art.

Current environments:

- Forest,
- Window Nook,
- Rainforest.

Each production-prototype environment has far, mid, front, and thumbnail textures. Night presentation is handled by Godot-side tint/presentation rather than requiring duplicate night raster sets.

Art provenance and deterministic preparation details belong in `assets/ART_ASSET_MANIFEST.md`.

## UI, Theme, Safe Areas, Localization

- `resources/ui_theme.tres` is the centralized shared visual Theme.
- Nunito font files and OFL license are checked into `assets/fonts/`.
- `SafeAreaContainer` centralizes safe-area inset calculations for relevant interaction/feedback layers.
- English and Simplified Chinese translation resources live under `localization/`.
- Player-facing text should use translation keys.

Responsive behavior is covered at multiple portrait viewport sizes and with enlarged UI text.

## Test Architecture

Repository test scripts are standalone `SceneTree` entrypoints that exit 0 on success and nonzero on failure. This makes them directly runnable by agents/CI without an external testing framework.

Canonical suites currently include:

- `tests/content_asset_tests.gd` — catalog counts/IDs, artwork bindings/dimensions, silhouette families, jar-capacity invariant.
- `tests/environment_provider_tests.gd` — environment/time calculations.
- `tests/phase2_tests.gd` — lifecycle, state/save/migration, recovery, input basics; historical filename retained for now.
- `tests/mvp_simulation_tests.gd` — water, cultivation, reproduction, spawning, mutation, offline equivalence, serialization.
- `tests/plant_visual_tests.gd` — layered/fallback visuals, hitbox/input geometry, drag collision, contact animation.
- `tests/main_integration_tests.gd` — real main-scene flows, economy/customization, save/restart, safety/catch-up behavior.
- `tests/main_visual_tests.gd` — responsive main UI, safe areas, art binding, localization, water presentation.
- `tests/stall_ui_tests.gd` — stall navigation, cards, responsiveness, accessibility sizing, public signals.

`tests/test_temp_paths.gd` is a helper, not a standalone suite.

Run all suites through `tools/validate.ps1` or `tools/validate.sh` rather than inventing a different list in task prompts.

## Where to Put Changes

Typical routing:

- New/changed durable product rule → `GAME_DESIGN.md` + relevant code/data/tests.
- Balance-only adjustment → `MvpTuning` or catalog Resources + targeted tests if invariant changes.
- New plant/jar/environment content → content Resources + localization + art manifest/assets when applicable + content tests.
- Time/water/reproduction/spawn/mutation logic → `GardenSimulator`/state data + simulation tests.
- Persisted field → `GameState`/`PlantState` + migration/round-trip tests.
- Save IO/recovery → `LocalSave` + save/integration tests.
- Plant interaction/presentation → `PlantView`/plant scene/visual Resource + visual/integration tests.
- Stall presentation → `StallPanel`/`StallItemCard` + stall UI/integration tests.
- Main orchestration → `main.gd` + main integration tests.
- Shared UI visual styling → `ui_theme.tres`/scenes, not scattered script constants when Theme supports the state.
- Agent validation workflow → `tools/validate.*` + `AGENTS.md`.

## Extraction Guidance

Some files are growing, especially simulation and integration tests. File size alone is not a reason to introduce new architecture.

When future work makes a responsibility independently useful, natural extraction seams include water simulation, reproduction/mutation, or presentation coordination. Prefer domain extraction over generic manager/service abstractions.

Tests are candidates for domain-based splitting when it improves focused iteration. Historical filenames such as `phase2_tests.gd` can eventually be replaced with domain names, but avoid renaming churn without a practical benefit.

## Documentation Ownership

- This file: current implementation ownership and architectural invariants.
- `GAME_DESIGN.md`: what the game should do/feel like.
- `PROJECT_CONTEXT.md`: slow-changing project constraints.
- `MVP_PLAN.md`: current status and roadmap.
- `ART_ASSET_MANIFEST.md`: production asset provenance/pipeline.
- `AGENTS.md`: agent routing/workflow contract.

If a fact is likely to change every few tasks, do not copy it into several documents.
