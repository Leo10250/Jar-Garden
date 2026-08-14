# Jar Garden — Project Context

## 1. Project Summary

**Jar Garden** is a small 2D mobile game for iOS and Android.

It is a **collection + nurturing + relaxing/healing** game centered on cute plant-like creatures living inside a glass jar.

The developers are two experienced software engineers. Codex is expected to be used heavily for:

- GDScript implementation
- Godot scene generation
- UI generation
- node-tree creation
- resource wiring
- refactoring
- debugging
- local persistence
- validation/testing where practical

The project should remain text-friendly, Git-friendly, readable, and easy for an agent to inspect and modify.

## 2. Current Technology Choices

Confirmed:

- Engine: **Godot 4.7.1 stable**
- Renderer: **Mobile**
- Language: **GDScript**
- Version control: **Git**
- Development environment currently includes Windows and VS Code
- Targets: **iOS + Android**
- Presentation: **2D**
- Orientation: **Portrait**
- Game type: **single-player**
- Core game should work offline

Do not switch engine, renderer, or scripting language unless explicitly requested.

## 3. Current Repository State

The project is newly created and intentionally minimal.

Known structure:

```text
JAR-GARDEN/
├── .godot/                 # generated Godot cache; do not edit
├── assets/
├── scenes/
│   └── main.tscn
├── scripts/
├── .editorconfig
├── .gitattributes
├── .gitignore
├── AGENTS.md
├── icon.svg
├── icon.svg.import
└── project.godot
```

Important:
- `scenes/main.tscn` already exists.
- Inspect it before assuming its root node/type.
- `assets/` and `scripts/` are intentionally mostly empty.
- Do not add speculative architecture.

## 4. Core Visual Identity

The central collectible creatures are called plants, but they are **stylized plant-like creatures rather than realistic plants**.

### Confirmed base/common plant appearance

The basic plant should look like:

- a small **white dumpling/blob**
- soft, round, simple silhouette
- a **cute face / cute expression**
- friendly, healing, collectible feeling

The five starting plants use this same basic/common visual identity.

### Mutation / variant appearance

Mutations should visibly differentiate plants.

Confirmed directions include:
- different **colors**
- different **decorations/accessories**
- possible **headwear**
- possible **equipment-like accessories**
- combinations of multiple visible traits

The mutation system should make a player immediately feel:

> “This one looks different. I discovered something new.”

The exact designs, colors, accessory catalog, silhouettes, and art style remain TBD.

Do not replace this direction with realistic flowers/leaves/seedlings.

## 5. Intended Main Screen

The core game takes place on one main screen.

Conceptually:

```text
Forest / environment background
        |
        | sunlight / moonlight / weather
        v

      [ GLASS JAR ]
      [            ]
      [ cute white ]
      [ blob plants]
      [            ]
      [   water    ]

[Water button]                 [Stall button]
```

This is conceptual, not a locked final composition.

The glass jar and the creatures inside it are the visual focus.

## 6. Mobile Layout

Portrait-first.

A logical reference resolution such as **720 x 1280** is acceptable if the project is not already configured differently.

This is not an art-resolution commitment.

The implementation must adapt to different phone aspect ratios.

Use anchors/containers where appropriate.

## 7. Interaction Model

Primary input:
- touch

Desktop-development fallback:
- mouse

Important planned interactions:
- drag individual plants inside the jar
- press Water to add water
- press Stall to open the economy/shop interface

Exact gestures and animations are TBD.

## 8. Offline-First and Weather

Long-term, the game may reflect real-world weather.

However:
- real online weather integration is **not part of the initial MVP**
- do not add HTTP/weather APIs early
- sun/moon can use device time
- weather-dependent systems should remain separable from the eventual weather data source
- MVP weather can be simulated, hard-coded for testing, or omitted depending on the task

Exact future weather source is TBD.

## 9. Data Model Direction

Avoid a complex genetics engine.

A simple separation is preferred.

### Static plant/variant definition

May eventually contain:
- stable ID
- display name
- rarity
- base visual configuration
- color/visual-trait configuration
- accessory/decor configuration
- adult sale value
- reproduction modifiers if needed later
- discovery metadata

A Godot `Resource`-based definition is reasonable.

### Runtime plant instance

May eventually contain:
- unique instance ID
- plant/variant definition reference
- lifecycle stage
- birth timestamp
- current position
- reproduction count used
- hydration/environment history needed by current mechanics
- mutation-related state if required
- parent information only if actually needed

Do not implement all fields prematurely.

### Visual-trait note

The final distinction between:
- “species”
- “mutation”
- “variant”
- “visual trait”

is not fully finalized.

Do not build a complicated inheritance/genetics taxonomy yet.

For now, treat visible mutation results as data-driven variants that can alter color and add/remove visual decorations.

## 10. Time Model

The game continues progressing while closed.

General model:

1. Store relevant timestamp/state.
2. On load/resume, calculate elapsed real time.
3. Advance implemented systems.
4. Save locally.

Exact durations are TBD and should be configurable.

No clock-tampering protection is required for MVP.

## 11. Water Model Direction

Water is spatially meaningful.

Confirmed:
- player adds water manually from the top of the jar
- different plant positions may receive different water amounts
- player can water multiple times
- jar can become increasingly wet and even effectively submerged
- water decreases over real-world time

Do not build realistic fluid simulation.

Use the simplest understandable model that satisfies the current task.

## 12. Light Model Direction

Sunlight/moonlight affect the jar broadly rather than requiring detailed per-plant shadows.

Light may affect:
- growth
- spawning
- reproduction
- mutation

Exact sunlight-vs-moonlight differences are TBD.

## 13. Scene Architecture Direction

Keep it simple.

A future main scene may evolve toward:

```text
Main
├── Background
├── Environment
├── Jar
│   ├── Water
│   └── Plants
└── UI
    ├── WaterButton
    └── StallButton
```

This is guidance, not a mandatory exact tree.

Reusable plant presentation/interaction can become its own scene when useful.

Avoid many singleton managers.

## 14. Art and Audio

The **broad plant visual direction is now partially confirmed**:

- common/base = white cute blob/dumpling with face
- mutations = visible color/accessory/decor changes

Still TBD:
- exact silhouette
- exact facial expressions
- exact colors
- exact accessories/headwear/equipment
- animation style
- final background style
- final UI style
- fonts
- audio direction

During prototyping:
- use simple replaceable shapes/assets
- preserve the confirmed white-blob-with-face concept
- mutation placeholders may use simple color changes and small icon-like accessories
- do not treat placeholder choices as final art

Do not download third-party art/audio without approval.

## 15. Localization

Localization requirements are TBD.

Avoid embedding large amounts of permanent player-facing text directly into gameplay logic.

## 16. Performance

This is a small 2D mobile game.

Favor clarity over premature optimization.

Avoid obvious waste:
- expensive per-frame logic for slow simulation
- unnecessary physics for purely visual elements
- overly complex architecture

Do not introduce ECS without a demonstrated need.

## 17. Services Not Currently Part of the Project

Do not add without explicit instruction:

- accounts
- backend
- multiplayer
- cloud save
- ads
- IAP
- analytics
- social features
