# AGENTS.md — Jar Garden

## Purpose

This repository contains **Jar Garden**, a relaxing 2D plant collection and nurturing game built with Godot 4.

Before doing any implementation work, read:

1. `docs/PROJECT_CONTEXT.md`
2. `docs/GAME_DESIGN.md`
3. `docs/MVP_PLAN.md`

These documents are the source of truth for the current project.

If the user's current request conflicts with these documents, the user's latest explicit request wins.

## Core Technical Constraints

- Engine: Godot 4.7.x.
- Current project uses the **Mobile renderer**.
- Language: **GDScript**, not C#.
- Target platforms: iOS and Android.
- Target orientation: portrait.
- Game is primarily offline and single-player.
- Do not add backend services, accounts, multiplayer, cloud saves, analytics, ads, networking libraries, or other online dependencies unless explicitly requested.
- Real-world online weather integration is a future feature, not part of the initial MVP.
- Use Git-friendly text resources and scenes where practical.
- Codex may create and edit `.gd`, `.tscn`, `.tres`, and `project.godot` when needed.
- Do not fabricate resource UIDs or generated cache metadata.
- Never edit files inside `.godot/`.
- Do not add third-party dependencies without explicit approval.

## Repository Layout

Current intended layout:

```text
/
├── AGENTS.md
├── project.godot
├── scenes/
│   └── main.tscn
├── scripts/
├── assets/
└── docs/
    ├── PROJECT_CONTEXT.md
    ├── GAME_DESIGN.md
    └── MVP_PLAN.md
```

Create additional folders only when there is a concrete need.

Do not build a speculative folder hierarchy up front.

## Engineering Style

- Use typed GDScript where practical.
- Prefer simple, readable, Godot-native code.
- Keep scripts focused and reasonably small.
- Prefer composition over deep inheritance.
- Avoid enterprise-style overengineering.
- Do not introduce service/repository/DI/event-bus abstractions unless they solve a current problem.
- Separate static plant/variant definitions from per-plant runtime state where useful.
- Keep simulation/game state separate from purely visual presentation where practical.
- Prefer signals for clear Godot-style communication between loosely coupled nodes.
- Avoid global singletons unless state genuinely needs to be global.
- Prefer data-driven values for design parameters expected to change during balancing.
- Do not hard-code design-critical probabilities, durations, capacities, or prices that the design documents mark as TBD.
- When a temporary value is required, keep it in one obvious configurable place and label it as a placeholder.

## Confirmed Plant Visual Direction

The base/common plant is **not a realistic plant**.

Confirmed baseline:
- It is a small, soft-looking **white dumpling/blob-like creature**.
- It has a **cute facial expression**.
- It should feel adorable, friendly, simple, and collectible.

Mutation/variant visual direction:
- Mutations may change **color**.
- Mutations may add **decorations/accessories**, such as headwear or equipment-like items.
- Mutations may combine multiple visual traits.
- These visible differences are a major part of collection and discovery.

Do not reinterpret the base plant as a normal flower, leaf, seedling, or realistic botanical plant.

Exact:
- shape details,
- face designs,
- accessory designs,
- mutation colors,
- animation style,
- final art style,
- final palette

remain TBD unless explicitly provided.

During prototyping, use simple placeholders that preserve the concept:
**white cute blob + simple face**, with replaceable placeholder mutation traits.

## Scene and UI Rules

- This is a 2D portrait mobile game.
- World/gameplay objects may use `Node2D`-based scenes.
- UI should use `Control` nodes and Godot Containers where appropriate.
- UI must adapt to different iOS and Android aspect ratios.
- Avoid fixed pixel placement for UI when anchors/containers are more appropriate.
- Account for mobile safe areas when implementing final edge UI.
- Touch input is primary.
- Mouse input should also work during desktop development when easy to support.
- Plants must eventually be draggable by touch.
- Keep `.tscn` files readable and avoid unnecessary node nesting.
- Use placeholder visuals during prototyping unless actual art assets are provided.
- Respect the confirmed base-plant visual direction above.
- Do not invent permanent accessory sets, mutation colors, fonts, or UI styling.

## Persistence and Time

The game uses real-world elapsed time for growth and other simulation systems.

For MVP:
- Save locally on device.
- Record timestamps/state needed to calculate elapsed offline time.
- On resume/load, calculate elapsed time and advance relevant systems.
- No anti-cheat or clock-tampering prevention is required unless explicitly requested.

Do not create cloud persistence.

## Product Rules

- Preserve the relaxing, collectible, nurturing tone.
- Favor observation and anticipation over constant tapping.
- Do not add quests, battle systems, energy systems, daily-login streak pressure, red-dot notification spam, or unrelated retention mechanics unless explicitly requested.
- Do not add features just because they are common in mobile games.

## Handling Ambiguity

Many balance and content values are intentionally undecided.

If a task depends on an undecided product decision:

1. Do not silently invent a permanent rule.
2. Prefer a configurable placeholder if implementation requires a value.
3. Clearly report the assumption in the final summary.
4. Ask only when the ambiguity materially blocks the requested work.

## Workflow Before Editing

For every task:

1. Read this file and the three docs listed above.
2. Inspect the relevant existing files before modifying them.
3. Check `git status`.
4. Understand the current scene tree and scripts.
5. Make the smallest coherent change that fulfills the request.
6. Do not implement unrelated future systems.

## Validation

If Godot is available as `godot` in PATH, use command-line validation when useful.

Useful commands include:

```bash
godot --headless --path . --import
```

and, once a valid main scene exists:

```bash
godot --headless --path . --quit-after 2
```

If `godot` is unavailable, do not fail the task solely for that reason. Report that automated Godot validation could not be run.

Also:
- Check for GDScript parser errors.
- Check for broken scene/resource paths.
- Check that referenced scripts/resources exist.
- Do not claim validation you did not perform.

## Definition of Done

A task is done when:

- The requested behavior is implemented.
- The project remains structurally simple.
- No unrelated features were added.
- New scenes/scripts/resources are correctly referenced.
- Relevant validation was run when available.
- The final response summarizes:
  - what changed,
  - which files changed,
  - what was validated,
  - any assumptions/TBD values introduced.

## Git Safety

- Do not delete or rewrite unrelated user work.
- Do not reset, force-push, amend, rebase, or rewrite history unless explicitly requested.
- Do not commit unless explicitly requested.
- Preserve unrelated existing modifications.
