# Jar Garden — MVP Roadmap and Status

## Purpose

This document tracks **what is implemented now and what remains next**. It is not the product-design source of truth; normative behavior belongs in `docs/GAME_DESIGN.md`.

Status labels:

- **Implemented** — present in the current prototype and covered by meaningful executable validation.
- **Substantially implemented** — the intended MVP capability exists, with polish/content/tuning still expected.
- **Partial** — meaningful work exists but the phase is not complete.
- **Deferred** — intentionally not part of the current MVP.

The original phase history is retained because it explains how the vertical slice evolved, but agents must use the status below rather than treating every later phase as future work.

## MVP Question

The MVP should answer:

> Is the loop of caring + waiting + growth + reproduction + visible mutation + collection enjoyable enough to continue building?

The common creature is a cute white dumpling/blob with a face. Visible mutation/discovery is a major emotional reward.

## Phase 0 — Foundation

**Status: Implemented**

Implemented:

- Godot 4.7.x project using Mobile renderer and GDScript.
- Portrait mobile configuration and runnable main scene.
- Git-friendly scenes/resources/scripts.
- Local project structure for assets, resources, localization, tests, and tools.

Remaining:

- Device/export validation on real iOS and Android targets as the project approaches shipping quality.

## Phase 1 — Visual / Interaction Prototype

**Status: Implemented and expanded**

Implemented:

- central glass-jar stage,
- responsive portrait main screen,
- five initial common blob plants,
- touch/mouse plant dragging,
- Water and Stall actions,
- safe-area-aware UI,
- modern shared Theme and responsive HUD/action dock,
- production-prototype blob artwork and layered environment art.

The prototype no longer relies on generic green-circle/realistic-plant placeholders.

Remaining:

- ongoing animation/presentation polish based on playtesting,
- final-device visual tuning.

## Phase 2 — Plant State + Lifecycle + Save

**Status: Implemented**

Implemented:

- Young / Adult / Old lifecycle,
- centralized prototype durations,
- stable per-instance IDs and normalized positions,
- local JSON persistence,
- save schema and migrations,
- safe write/backup/recovery behavior,
- real elapsed-time advancement,
- persisted deterministic RNG state,
- birth context and cultivation history,
- online/offline-equivalence coverage.

Remaining:

- future schema migrations only as new persisted features require them.

## Phase 3 — Water

**Status: Implemented**

Implemented:

- Water action increases pooled jar water,
- two-dimensional direct-watering falloff,
- repeated watering/wetness accumulation,
- evaporation over elapsed time,
- exact wetness/submersion integration across offline intervals,
- partial/full submersion,
- visible rear water + foreground translucent water,
- animated water surface, pour, drops, and ripples,
- retargetable short water-level tween.

This remains a lightweight scalar model, not fluid physics.

Remaining:

- tuning and final visual polish based on playtesting.

## Phase 4 — Reproduction

**Status: Implemented**

Implemented:

- adult-only reproduction,
- elapsed contact progress,
- per-plant reproduction counts/limits,
- same-variant success modifier,
- variant reproduction difficulty,
- deterministic offline reproduction,
- authored visible hitbox geometry shared with reproduction contact logic,
- parent IDs/variant context recorded on offspring,
- capacity safeguards.

Remaining:

- balance tuning and additional content-driven reproduction rules only when design requires them.

## Phase 5 — Automatic Generation + Visible Mutation

**Status: Substantially implemented**

Implemented:

- environmental spawn schedule,
- deterministic persisted RNG,
- capacity handling without spawn backlog bursts,
- common-plant fallback,
- mutation probability and data-driven recipe resolution,
- cultivation profiles using environment, moisture/submersion, light, source, and optional parent requirements,
- exact day/night duration calculation across arbitrary elapsed intervals,
- ten prototype variants using seven silhouette families,
- nine non-base prototype mutation recipes,
- discovery registration on successful mutation.

Remaining:

- continued recipe/balance iteration through playtesting,
- additional variants only when they improve the core loop rather than increasing content count for its own sake.

## Phase 6 — Collection + Stall + Economy

**Status: Implemented**

Implemented:

- discovered-variant tracking,
- Collection UI with discovered details and undiscovered hints,
- Market → Buy / Sell,
- Customize → Jars / Places,
- reusable responsive cards,
- custom segmented navigation over hidden native tabs,
- young/old low sale value and configured adult values,
- buying only discovered plant types,
- local coin persistence,
- jar/environment purchase and selection,
- persistence/reload integration tests,
- ecology-recovery safeguards preventing a permanently empty jar or free-plant coin exploit.

Remaining:

- economy tuning and usability polish from playtesting.

## Phase 7 — Expanded Environments and Jars

**Status: Partial**

Already implemented:

- 2 selectable jars,
- 3 selectable environments: Forest, Window Nook, Rainforest,
- environment far/mid/front artwork plus thumbnails,
- jar/environment prototype modifiers,
- environment-specific mutation recipes,
- production-prototype art manifest and deterministic asset preparation.

Remaining:

- decide whether additional jars/environments materially improve the MVP,
- add content only after core-loop playtesting indicates a need,
- refine environment/jar identity and balancing.

## Phase 8 — Real Weather

**Status: Deferred**

Not part of the current MVP.

Before implementation, explicitly decide:

- how user location is handled,
- weather source/provider,
- privacy and permissions UX,
- offline fallback/caching,
- how real weather maps into game mechanics without undermining deterministic/local behavior.

Do not add an external weather API before those decisions.

## Current Vertical-Slice Priorities

The project is no longer waiting for core systems to be built. Near-term work should favor:

1. playtesting the care → wait → discovery loop,
2. tuning lifecycle/water/spawn/reproduction/mutation/economy values,
3. presentation and interaction polish,
4. real-device mobile validation,
5. focused content iteration based on observed player experience,
6. keeping deterministic simulation/save invariants intact,
7. keeping documentation and executable validation synchronized.

Do not respond to this roadmap by rebuilding already implemented phases.

## Explicitly Deferred Unless Requested

- account system,
- backend,
- cloud save,
- multiplayer/player trading,
- ads,
- IAP,
- analytics,
- push-notification pressure loops,
- complex auction system,
- realistic genetics,
- realistic fluid simulation,
- complex temperature simulation,
- anti-clock-cheat,
- hundreds of variants,
- complicated procedural character generation,
- speculative service/manager architecture.

## Development Philosophy

Each change should remain runnable and reviewable.

Prefer:

```text
small coherent task
-> inspect relevant implementation/tests
-> change the owning code/data
-> update durable tests/invariants
-> run tools/validate.*
-> playtest when presentation/feel matters
-> update the owning doc if the contract/status changed
```

Do not implement future systems merely because they are mentioned here.
