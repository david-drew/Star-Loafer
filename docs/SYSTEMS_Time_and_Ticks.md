# System: Time and Ticks

## Responsibilities
- Maintain global game time, calendar, and mode-based time scaling.
- Emit simulation ticks for downstream systems (economy, future sim).
- Allow time jumps (fast travel, script-driven) while keeping tick cadence consistent.
- Expose serialized state for saves.

## Main scripts
- `scripts/autoloads/time_manager.gd` (autoload)
- Signals defined on `scripts/autoloads/EventBus.gd`: `time_sim_tick(hours_elapsed, ticks)`, `time_big_jump(jump_hours, source)`, `time_mode_changed`, `time_day_changed`.

## How it works
- Loads config from `data/sim/time_scale.json`: hours/day, days/year, base hours per real second, tick interval, per-mode scales.
- `_process(delta)` advances `game_hours_since_start` using current mode scale and any active modifiers.
- Emits `time_sim_tick` whenever accumulated hours exceed `SIM_TICK_INTERVAL_HOURS` (default 6h); increments `game_tick`.
- Emits `time_day_changed` when calendar day flips; `time_mode_changed` when `set_mode` called; `time_big_jump` on manual `advance_time_hours`.
- On each tick: calls `EconomyManager.on_game_tick(game_tick)`.

## Data & state
- Config constants: `BASE_HOURS_PER_REAL_SECOND`, `SIM_TICK_INTERVAL_HOURS`, per-mode scales (FLIGHT, AWAY_TEAM, DIALOGUE, COMBAT, TRAVEL, PAUSED).
- Runtime: `game_tick`, `game_hours_since_start`, `current_mode`, `_time_modifiers` map (id -> multiplier).

## Extension points
- Add new modes by extending `_mode_scales` (and updating config JSON).
- Listen to EventBus time signals for periodic work instead of polling.
- Use `push_time_modifier`/`pop_time_modifier` for temporary slow/fast effects (e.g., UI pause, cinematics).
- Implement responders to `time_day_changed` for faction/mission resets.

## Pitfalls / notes
- `advance_time_hours` also emits ticks; avoid double-calling downstream systems manually.
- TimeManager expects EconomyManager autoload to exist (calls `EconomyManager.on_game_tick` directly) — keep that autoload loaded or guard if refactoring.
- Keep `SIM_TICK_INTERVAL_HOURS` aligned with economy pacing; large jumps update economy in batches.
