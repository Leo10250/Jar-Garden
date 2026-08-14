# Jar Garden — MVP Plan

## Goal

The first MVP should answer:

> Is the loop of caring + waiting + growth + reproduction + visible mutation + collection enjoyable enough to continue building?

The visual identity of the creatures matters to this test.

The basic plant is a **cute white dumpling/blob with a face**.

Mutations should eventually feel rewarding partly because they visibly change the creature through **color and/or decorations/accessories**.

Do not implement the entire long-term design at once.

## Phase 0 — Foundation

Status: project already created.

Keep:
- Godot 4.7.x
- Mobile renderer
- GDScript
- portrait mobile target
- Git
- minimal repo structure

Foundation work as needed:
- confirm project opens/runs
- confirm `main.tscn` is a valid runnable main scene
- establish portrait-responsive layout
- establish simple save approach when persistence begins

Do not add gameplay systems merely as setup.

## Phase 1 — Visual / Interaction Prototype

Goal: produce a runnable main-screen prototype and validate the **basic creature identity**.

Include:
- forest placeholder background
- large central glass jar
- simple sun or moon presentation
- **5 placeholder base plants**
- each placeholder base plant should read as:
  - a small white rounded/dumpling/blob-like creature
  - with a simple cute face/expression
- Water button
- Stall button
- portrait-responsive layout
- basic plant dragging with mouse/touch if practical

Important:
- Do not use generic green circles or realistic seedlings as the main placeholder if a simple white blob with face can be represented directly.
- The placeholder should preserve the confirmed creature concept while remaining easy to replace with final art.

Do not implement yet unless specifically requested:
- full lifecycle
- reproduction simulation
- mutation logic
- economy
- collection
- real weather
- complex water simulation

The prototype should prove:
1. Codex can reliably edit Godot scenes/UI.
2. The main jar composition works.
3. The five white blob plants already communicate the intended cute collectible direction.

## Phase 2 — Plant State + Lifecycle + Save

Implement a minimal plant-instance model.

Add:
- young/adult/old lifecycle
- configurable stage durations
- local save/load
- real-world elapsed-time advancement
- preservation of plant position/state

Visual lifecycle differences are TBD.

Do not invent permanent young/adult/old designs.

Use placeholder durations if necessary, centralized and labeled.

## Phase 3 — Water

Implement the simplest model that creates meaningful position-dependent water exposure.

Requirements:
- Water button adds water.
- Water conceptually enters from the top.
- Different positions can lead to different exposure.
- Repeated watering increases wetness.
- Water decreases with elapsed time.
- Support an extreme wet/submerged state.

Do not implement realistic fluid dynamics.

## Phase 4 — Reproduction

Implement:
- only adults reproduce
- touching/proximity requirement
- elapsed-time requirement
- same-type pair has higher reproduction likelihood
- successful reproduction creates one young plant
- per-plant adult reproduction count/limit
- mutated plants can later be configured as harder to reproduce

Keep probabilities/durations configurable.

At this stage, offspring may still use simple placeholder visuals.

## Phase 5 — Automatic Generation + Visible Mutation

Implement automatic environmental spawning:
- occurs over time
- stops when jar capacity is full
- can use current environmental state
- can create the common/base plant
- can occasionally create a mutation/variant

Implement a **simple, data-driven visible mutation system**.

The first mutation prototype should test obvious visual differences, such as:
- body color variation
- one simple head decoration/accessory
- one simple equipment-like accessory
- combinations if still simple

Important:
- these are placeholder mutation traits, not final art
- exact mutation colors/accessories are TBD
- do not build realistic genetics
- do not build a complex trait inheritance engine unless later requested

Start with only enough variants to test whether seeing a visually different newborn feels exciting.

## Phase 6 — Collection + Stall + Economy

Add:
- discovered type/variant tracking
- encyclopedia UI
- sell plants
- young sell value = 1 coin
- old sell value = 1 coin
- adult value based on type/rarity
- buy young plants only for previously discovered types/variants
- local currency persistence

The collection should visually show discovered blob variants so color/accessory differences contribute to collecting.

Keep permanent pricing configurable.

## Phase 7 — Expanded Environments and Jars

Only after the core loop works:

- additional backgrounds/environments
- different jars/materials
- environmental modifiers
- additional plant variants
- more mutation paths
- richer accessory/decor sets

## Phase 8 — Real Weather

Future, not MVP.

Only after explicit product/technical decision:
- decide how user location is handled
- decide weather source
- decide privacy/permission UX
- decide offline fallback/caching
- integrate real weather

Do not add an external weather API before this decision.

## Explicitly Deferred

Do not build during early MVP unless explicitly requested:

- account system
- backend
- cloud save
- multiplayer
- player-to-player trading
- ads
- IAP
- analytics
- push notifications
- complex auction system
- realistic genetics
- realistic fluid simulation
- complex temperature model
- anti-clock-cheat
- many jars/backgrounds
- dozens/hundreds of plants
- large production art pipeline
- advanced facial-expression state system
- complicated accessory equipment system
- complicated procedural character generator

## MVP Development Philosophy

Each phase should create something runnable and reviewable.

Prefer:

```text
small task
-> inspect diff
-> run/validate
-> playtest
-> commit checkpoint
-> next task
```

over one giant request.

Codex must not implement later phases merely because they are described here.
