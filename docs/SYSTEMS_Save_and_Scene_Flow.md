# System: Save and Scene Flow

## Responsibilities
- Manage scene transitions between main menu, game root, and gameplay modes.
- Persist and restore game state via provider pattern.

## Main scripts
- `scripts/autoloads/scene_manager.gd`
- `scripts/game_root.gd`
- `scripts/autoloads/save_system.gd`
- Providers: currently only `GameState` registered (`game_root.gd` `_register_save_providers`).

## Scene flow
1. **Start new game**: `SceneManager.start_fresh_game(config)` sets `start_new_game` and loads `scenes/game_root.tscn`.
2. **Load game**: `SceneManager.start_load_game(slot)` sets `pending_load_slot` and loads `game_root.tscn`.
3. `GameRoot._ready` registers SaveSystem providers, then branches:
   - If `pending_load_slot` >= 0 → call `_load_game`.
   - Else if `start_new_game` → call `_start_new_game`.
4. New game: GalaxyGenerator.generate(seed,size) → set GameState seed/size/data → choose starter system → load mode `system_exploration.tscn`.
5. Load game: SaveSystem.load_from_slot(slot) → regenerate galaxy from saved seed → load mode `system_exploration.tscn`.
6. Mode swap: `SceneManager.transition_to_mode(path)` emits `mode_transition_requested` (EventBus) and GameRoot loads scene under `WorldRoot`.

## SaveSystem contract (current state)
- `register_provider(name, get_state: Callable, set_state: Callable)` stores providers in `providers` dictionary.
- **Bug:** `save_to_slot` expects `providers[provider_name]["write"]` but `register_provider` stores `get`/`set`. Align keys before relying on saves.
- Save format: JSON per slot under `user://StarLoafer/saves/slot_{n}.sav`, includes `timestamp`, `version`, and provider blobs.
- `load_from_slot` reads JSON and calls `providers[provider_name]["read"]` (same key mismatch).
- Slot info helper reads timestamp/version/system/credits from `game_state` section.

## Extension points
- Fix provider key naming (`get/set` vs `write/read`) and update call sites.
- Register additional providers: Economy state (`EconomyManager.save_economy_state`), TimeManager state (`serialize_state`), FactionRelations (`get_save_data`), ShipComponentSystem instances, etc.
- Add versioning/migration: include `version` in save; perform migrations on load.
- Add autosave/manual save UI in main menu/pause menu; guard against save during mode transitions.

## Pitfalls / notes
- Save directory created on `_ready`; ensure permissions when exporting.
- SceneManager assumes `game_root.tscn` handles branching; keep flags consistent.
- When adding providers, make sure they return serializable dictionaries (no Node references).
