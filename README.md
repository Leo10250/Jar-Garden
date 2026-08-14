# Jar Garden

Jar Garden is a relaxing 2D mobile collection/nurturing game built with Godot 4.7.x and GDScript. Players care for cute blob-like plant creatures in a glass jar, then observe growth, reproduction, environmental spawning, mutation, discovery, and collection over real elapsed time.

## Requirements

- Godot 4.7.x
- Mobile renderer
- GDScript
- Portrait mobile target (iOS / Android)

## Open and Run

Open the repository root in Godot and run the configured main scene.

If using the command line, make sure Godot is available on PATH or set `GODOT_BIN` to the executable path.

## Validate

Windows PowerShell:

```powershell
./tools/validate.ps1
```

macOS/Linux:

```bash
bash ./tools/validate.sh
```

The validator imports/parses the project, runs all repository test suites in deterministic order, then performs a short headless main-scene smoke run. A failure returns a nonzero exit code.

## Documentation Map

- `AGENTS.md` — coding-agent entrypoint, workflow, and routing rules.
- `docs/PROJECT_CONTEXT.md` — slow-changing platform/product constraints.
- `docs/GAME_DESIGN.md` — normative game-design intent and player-facing rules.
- `docs/ARCHITECTURE.md` — current code/data/test ownership and data flow.
- `docs/MVP_PLAN.md` — living implementation status and roadmap.
- `assets/ART_ASSET_MANIFEST.md` — production-prototype asset provenance and deterministic art preparation.

Do not treat the roadmap as the architecture or the architecture as product intent; each document has one owner role to reduce staleness.

## AI-First Development

The repository favors executable and data-driven contracts over duplicated prose:

- deterministic simulation lives outside UI code,
- prototype balance/content lives in Resources,
- save state has explicit schema/migrations,
- tests run as standalone headless Godot scripts,
- production art has provenance plus deterministic preparation,
- `tools/validate.*` is the canonical feedback loop.

When a durable rule can be tested, prefer adding/updating the test instead of creating another instruction document.
