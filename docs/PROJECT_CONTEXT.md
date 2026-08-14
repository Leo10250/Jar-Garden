# Jar Garden — Stable Project Context

## Purpose

This document contains **slow-changing project constraints and product context**. It intentionally avoids current folder snapshots, implementation status, and milestone completion details because those become stale quickly.

For current implementation ownership and data flow, read `docs/ARCHITECTURE.md`.
For current roadmap/status, read `docs/MVP_PLAN.md`.
For normative game behavior and product intent, read `docs/GAME_DESIGN.md`.

## Product Summary

Jar Garden is a relaxing 2D mobile collection and nurturing game for iOS and Android.

The player cares for cute plant-like creatures living inside a glass jar. The experience is intentionally low pressure and centered on observation, care, waiting, growth, reproduction, environmental spawning, visible mutation, discovery, and collection.

The core emotional promise is that actions taken earlier can produce a cute or surprising change when the player returns later.

## Stable Technology Choices

- Engine: Godot 4.7.x.
- Renderer: Mobile.
- Language: GDScript.
- Presentation: 2D.
- Target platforms: iOS and Android.
- Orientation: portrait.
- Version control: Git.
- Core experience: single-player and offline-first.

Do not switch engine, renderer, language, or core platform model without an explicit product/technical decision.

## Creature Identity

The collectible creatures are called plants, but they are stylized creatures rather than realistic botanical plants.

The common/base creature is a small soft white dumpling/blob with a cute face. It should feel friendly, simple, collectible, and calming.

Variants may visibly differ through:

- silhouette,
- color,
- decorations,
- headwear,
- equipment-like accessories,
- or combinations of those traits.

Visible differentiation is an important discovery reward. Do not reinterpret the common creature as a conventional flower, seedling, or realistic plant.

The repository contains a production-prototype art set, but individual final production choices can still evolve. Art provenance and preparation rules belong in `assets/ART_ASSET_MANIFEST.md`.

## Core Screen and Interaction Model

The game is portrait-first and centered on one primary jar screen. The glass jar and creatures inside it are the visual focus, with environmental presentation behind/around the jar and primary actions such as Water and Stall exposed through mobile-safe UI.

Primary input is touch. Mouse input should remain useful for desktop development where practical.

Important interaction principles:

- plants can be positioned/dragged inside the jar,
- watering should have visible and simulated consequences,
- the Stall/collection flow should expose discovery and economy without turning the game into a high-pressure menu loop,
- UI must adapt to phone aspect ratios and safe areas.

The project uses a 720x1280 portrait reference viewport, but implementations must remain responsive rather than assuming one physical screen size.

## Offline Progression and Time

Jar Garden progresses while closed.

The stable model is:

1. Persist the state and simulation checkpoint needed for deterministic continuation.
2. On load/resume, calculate real elapsed time.
3. Advance implemented simulation systems.
4. Persist the resulting state locally.

No anti-cheat or clock-tampering system is required for the MVP unless explicitly requested.

Online/offline equivalence and deterministic catch-up are important engineering invariants.

## Water Model

Water is spatially meaningful but intentionally lightweight.

Stable constraints:

- the player manually adds water,
- watering can affect plants differently based on position,
- repeated watering accumulates water/wetness,
- water changes over real elapsed time,
- partial and full submersion can matter,
- presentation should make the water state understandable,
- do not implement realistic fluid physics unless the product direction explicitly changes.

Exact rates and balance values are prototype tuning and should remain data-driven/configurable.

## Light and Environment Model

Sunlight and moonlight can affect spawning, reproduction, mutation, and cultivation history. The implementation may use device/local time without requiring a network service.

Selectable environments can affect presentation and prototype simulation modifiers.

Long-term real-world weather remains a possible future feature. Do not introduce weather APIs, location permissions, backend services, or networking merely because the design mentions weather.

## Content/Data Direction

The project favors data-driven content over hard-coded branching when a value or content definition is expected to change.

Stable concepts include:

- static plant/variant definitions,
- per-instance runtime plant state,
- selectable jar definitions,
- selectable environment definitions,
- centralized prototype tuning,
- stable content IDs for persistence and lookup.

Do not build a complex genetics taxonomy or trait-inheritance engine without a concrete requirement. Visible mutation outcomes can remain explicit data-driven variants.

## Localization

The project has an active localization path. English is the fallback language and Simplified Chinese resources are registered.

Player-facing strings should use translation keys rather than being embedded as permanent English prose in gameplay logic.

## Performance and Complexity

This is a small 2D mobile game. Favor clarity, determinism, and inspectability over speculative optimization.

Avoid:

- unnecessary per-frame work for slow simulation,
- per-second loops for long offline intervals when exact/event-based math is practical,
- unnecessary physics for purely visual effects,
- speculative ECS/manager/service architectures,
- dependencies that make local/offline behavior harder to reason about.

## Services Outside the Current Scope

Do not add without explicit instruction:

- accounts,
- backend services,
- multiplayer,
- cloud saves,
- ads,
- IAP,
- analytics,
- social systems,
- push-notification retention mechanics,
- third-party runtime networking dependencies.

## AI-Friendly Repository Principle

Jar Garden is intentionally designed so humans and coding agents can reason about it from repository state:

- product intent is documented separately from implementation status,
- content and balance are represented in Resources,
- elapsed-time simulation is deterministic and directly testable,
- persistence has explicit schema/migration behavior,
- art generation has recorded provenance and deterministic preparation,
- durable invariants should become executable tests/validation rather than duplicated prose.

When a mutable implementation fact changes, update its owning architecture/status document instead of adding that fact here.
