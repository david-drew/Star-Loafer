# Contributing / Coding Standards

## Language & engine
- Godot 4.5, GDScript-first. Avoid ternary operators; use explicit if/else.
- Keep helpers small and well-named; prefer composition over monoliths.
- Use autoloads/managers and EventBus signals for decoupling; avoid tight node lookups across scenes.

## Project structure
- Autoloads live in `scripts/autoloads/`; add new global services there and register in `project.godot`.
- Systems under `scripts/systems/`; world/procgen under `scripts/world/`; AI under `scripts/ai/`; UI under `scripts/ui/`; actors under `scripts/actors/`.
- Data lives in `data/` (JSON). Extend data first, then code. Keep schemas in sync.
- Scenes under `scenes/` mirror code locations (world, ui, actors, modes).

## Signals & EventBus
- Prefer EventBus for cross-system communication:
  - Time: `time_sim_tick`, `time_day_changed`.
  - Navigation: `system_entered`, `location_discovered`.
  - UI: `map_toggled`, `ship_screen_toggled`, `comm_message_received`.
  - Ship systems: `ship_stats_updated`, `ship_loadout_updated`, `ship_component_*_requested`.
  - Comms/docking: `hail_received`, `comm_response_chosen`, `docking_approved/denied`.
- When adding new interactions, add signals to EventBus and emit/listen instead of direct calls.

## Data-driven rules
- Use canonical IDs: components `type__name`, ship types `snake_case`, factions `snake_case`.
- Keep schemas documented (see `DATA_SCHEMAS.md`); mark INFERRED fields when guessing.
- Validate assets: ContentDB logs missing sprites; match file names to patterns.

## Code style
- No ternary operators in GDScript examples or code.
- Use typed variables where practical for clarity (e.g., `var timer: float = 0.0`).
- Keep process callbacks light; defer heavy work to timers or signals.
- Check for `null`/empty dictionaries before use; fail loudly with `push_warning`/`push_error`.
- Avoid hardcoded paths when a DB/manager lookup exists.

## Testing & debugging
- Use print/logging for warnings; avoid silent failures on missing data.
- Add debug helpers like `debug_print_system_info` (see SystemExploration) to inspect runtime state.
- When changing save formats, bump `version` and add migration notes.

## Pull request checklist (informal)
- Data added? Update relevant JSON and verify with loaders (run game, check console).
- Signals added? Declared on EventBus and connected where needed.
- UI changes? Wire through EventBus and test toggles (`ui_map`, `ui_map_system`, `ui_ship_systems`).
- Performance-sensitive code? Keep per-frame work minimal; consider streaming or batching.
