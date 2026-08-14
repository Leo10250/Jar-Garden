# AGENTS.md — Jar Garden

## Purpose

This file is the **agent entrypoint and routing contract** for Jar Garden. It intentionally does not duplicate the full game design or implementation details.

Jar Garden is a relaxing 2D mobile collection/nurturing game built with Godot 4.7.x and GDScript. The player cares for cute blob-like plant creatures inside a glass jar, then observes growth, reproduction, spawning, mutation, discovery, and collection over real elapsed time.

The user's latest explicit request wins over repository guidance when they conflict.

## Read Only What the Task Needs

Always read this file first. Then route to the smallest relevant source of truth:

- Product behavior, player experience, long-term intent → `docs/GAME_DESIGN.md`
- Stable platform/product constraints → `docs/PROJECT_CONTEXT.md`
- Current code/data/test architecture and ownership → `docs/ARCHITECTURE.md`
- Current milestone status and remaining roadmap → `docs/MVP_PLAN.md`
- Art provenance, generation prompts, dimensions, preparation → `assets/ART_ASSET_MANIFEST.md`
- Executable validation contract → `tools/validate.ps1` or `tools/validate.sh`

Do **not** reread every long document for every small task. Inspect the relevant code, scene, resource, and tests directly.

## Truth Hierarchy

When sources disagree, use this order:

1. The user's latest explicit request.
2. Executable behavior and tests in the current branch.
3. `docs/GAME_DESIGN.md` for normative product intent.
4. `docs/PROJECT_CONTEXT.md` for stable project constraints.
5. `docs/ARCHITECTURE.md` for the intended current ownership map.
6. `docs/MVP_PLAN.md` for milestone/status information.
7. Comments and historical prose.

Never preserve stale documentation merely because it calls itself a source of truth. If implementation intentionally changes a documented contract, update the owning document in the same task.

## Core Technical Constraints

- Engine: Godot 4.7.x.
- Renderer: Mobile.
- Language: GDScript, not C#.
- Targets: iOS and Android.
- Orientation: portrait.
- Core game: offline-first, single-player.
- Do not add backend services, accounts, multiplayer, cloud saves, analytics, ads, networking libraries, or other online dependencies unless explicitly requested.
- Real-world online weather integration remains deferred.
- Prefer Git-friendly text scenes/resources.
- Never edit `.godot/`.
- Do not fabricate resource UIDs or generated cache metadata.
- Do not add third-party runtime dependencies without explicit approval.

## Repository Map

```text
/
├── AGENTS.md
├── README.md
├── project.godot
├── assets/
│   ├── ART_ASSET_MANIFEST.md
│   ├── environments/
│   ├── fonts/
│   ├── icons/
│   └── plants/
├── docs/
│   ├── ARCHITECTURE.md
│   ├── GAME_DESIGN.md
│   ├── MVP_PLAN.md
│   └── PROJECT_CONTEXT.md
├── localization/
│   ├── en.po
│   └── zh_CN.po
├── resources/
│   ├── prototype_content_catalog.tres
│   ├── prototype_mvp_tuning.tres
│   └── ui_theme.tres
├── scenes/
├── scripts/
├── tests/
└── tools/
    ├── prepare_ai_assets.gd
    ├── validate.ps1
    └── validate.sh
```

Do not create a speculative `.ai/` hierarchy, AI memory file, duplicate coding-agent guide, service layer, or folder taxonomy without a concrete need. This file is the agent router.

## Existing Architecture: Preserve the Good Seams

The repository already has useful AI-friendly boundaries. Prefer extending them instead of bypassing them:

- `GameState` owns persistent mutable domain state and save-schema migration.
- `GardenSimulator` owns deterministic elapsed-time simulation.
- `ContentCatalog` owns static selectable content definitions.
- `MvpTuning` owns prototype/TBD balance values and mutation recipes.
- `LocalSave` owns local persistence and recovery behavior.
- `PlantView` owns plant presentation, hitboxes, dragging, and visual contact feedback.
- `StallPanel` owns collection/market/customization presentation and emits public request signals.
- `main.gd` is the orchestration layer connecting UI, state, simulation, save/load, and presentation.

Do not introduce managers/services/repositories/DI/event buses merely to make the project look architected. Extract a new boundary only when a real responsibility has become independently useful.

## Engineering Style

- Use typed GDScript where practical.
- Prefer simple, readable, Godot-native code.
- Prefer composition over deep inheritance.
- Keep simulation/domain state separate from purely visual presentation.
- Prefer signals for clear Godot-style node communication.
- Avoid global singletons unless state genuinely must be global.
- Keep design values that are still being tuned in Resources such as `MvpTuning`/catalog definitions rather than scattering literals through logic.
- Do not silently turn prototype balance values into permanent design rules.
- Reuse existing rendering/data paths rather than creating parallel preview-only implementations when practical.

## Confirmed Visual Direction

The common plant is a small soft white dumpling/blob creature with a cute face, not a realistic botanical plant.

Variants may differ through silhouette, color, decorations, headwear, equipment-like accessories, or combinations. Visible discovery is a core reward.

The repository now contains a production-prototype art set. Do not replace existing authored assets with placeholders unless a task specifically calls for replacement or fallback behavior. When changing production art, update `assets/ART_ASSET_MANIFEST.md` and use the deterministic preparation pipeline where applicable.

## UI and Mobile Rules

- Touch is primary; mouse support is useful for desktop development.
- Use Control nodes and Containers for UI layout.
- Preserve responsive behavior across target portrait sizes and safe areas.
- Full-bleed backgrounds may extend to screen edges; interactive controls must remain safe-area aware.
- Keep primary touch targets at least 48 logical pixels where the existing UI contract expects it.
- Use localization keys for player-facing text. English is the fallback locale and Simplified Chinese resources are wired into the project.
- Reuse the centralized `resources/ui_theme.tres` instead of scattering visual state styles in scripts when the Theme can own them.

## Persistence, Time, and Determinism

- The game advances using real-world elapsed time while closed.
- Save locally on device; do not add cloud persistence.
- Deterministic simulation and online/offline equivalence are important invariants.
- Preserve persisted RNG state and save-schema compatibility unless a migration is intentionally changed and tested.
- Avoid per-second loops for long offline intervals when an exact/event-based calculation is practical.

## Executable Rules Beat Prose

If an invariant can be encoded as a test or validation step, prefer that over adding another paragraph of instructions.

Examples already enforced by tests include content counts, texture dimensions, silhouette families, minimum jar capacity, responsive viewport behavior, safe areas, localization, save migration, deterministic simulation, and water presentation.

When adding a durable invariant:

1. Put the rule in the correct data/code boundary.
2. Add or update the narrowest relevant automated test.
3. Document it only where a human/agent needs intent or ownership context.

## Workflow Before Editing

For every task:

1. Read this file.
2. Read only the task-relevant routed docs.
3. Inspect the current implementation, Resources, scenes, and relevant tests before changing them.
4. Check for unrelated user changes and preserve them.
5. Make the smallest coherent change that fulfills the request.
6. Update the owning documentation when the architectural/product/status contract changes.
7. Run the canonical validator for code/resource/scene changes.

## Canonical Validation

For Windows PowerShell:

```powershell
./tools/validate.ps1
```

For macOS/Linux:

```bash
./tools/validate.sh
```

Both wrappers implement the same contract:

1. Resolve Godot from `GODOT_BIN`, then PATH fallbacks.
2. Import/parse the project headlessly.
3. Run every repository test suite in deterministic order.
4. Smoke-run the configured main scene headlessly.
5. Return nonzero on any failure and print a concise PASS/FAIL summary.

If Godot is installed somewhere not on PATH, set `GODOT_BIN` to the executable path. Do not claim validation passed if the command was not run successfully.

Documentation-only changes that cannot affect Godot parsing may be reviewed without executing Godot, but any validator changes themselves must be inspected carefully and should be executed in a local checkout before merge when Godot is available.

## Documentation Ownership

Avoid repeating mutable facts across multiple files.

- Architecture/responsibility/data-flow changes → update `docs/ARCHITECTURE.md`.
- Product behavior or player-experience rules → update `docs/GAME_DESIGN.md`.
- Milestone completion/current roadmap changes → update `docs/MVP_PLAN.md`.
- Stable engine/platform/offline/product constraints → update `docs/PROJECT_CONTEXT.md`.
- Production art/provenance/pipeline changes → update `assets/ART_ASSET_MANIFEST.md`.
- Agent workflow/validation routing changes → update this file and executable validation tools.

## Definition of Done

A task is done when:

- The requested behavior is implemented without unrelated features.
- Existing architectural boundaries remain coherent or an intentional new boundary is documented.
- Relevant tests cover durable behavior/invariants.
- Canonical validation passes when the task can affect executable project content, or the reason it could not be run is stated.
- Relevant owning docs are updated rather than duplicated elsewhere.
- The final summary reports what changed, validation performed, and any intentional assumptions/TBD values.

## Git Safety

- Do not delete or rewrite unrelated user work.
- Do not reset, force-push, amend, rebase, or rewrite history unless explicitly requested.
- Do not commit or push unless explicitly requested by the user/task workflow.
- Preserve unrelated existing modifications and `project.godot` ordering unless the requested change requires touching them.
