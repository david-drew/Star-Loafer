# Architecture

## Godot scene/layout overview
- **Main entry**: `scenes/game_root.tscn` with `scripts/game_root.gd`.
  - Children: `Systems` (GalaxyGenerator, FactionManager, NPCSpawner, SectorStreamer, SystemGenerator, etc.), `WorldRoot` (mode container), `LoadingOverlay`.
  - GameRoot registers SaveSystem providers, starts new game or loads, and swaps modes via `SceneManager.transition_to_mode`.
- **Modes**: primary mode `scenes/modes/system_exploration.tscn` (`scripts/world/system_exploration.gd`) handles local system play; other modes TBD.
- **UI scenes**: main_menu, galaxy_map, system_map, ship_systems_panel, comm_panel, hud, notifier_panel, pause_menu (toggle via EventBus signals).

## Autoloads (singletons) and responsibilities
- `EventBus`: signal hub (time ticks/mode change/day change, system_entered/location_discovered, ship position/stats/loadout updates, map toggles, comms/docking/component actions, fast travel, credits/trade hooks).
- `SaveSystem`: save slots API; providers register `get/set` callables (note: implementation currently uses `write/read` keys; see Save doc).
- `SceneManager`: sets new game vs load flags, scene transitions to game_root, main menu, or specific mode scenes.
- `GameState`: session state (galaxy seed/size/data, fog-of-war, credits/reputation, ship state/position, transit flags).
- `ContentDB`: loads procgen datasets (stars/planets/moons/asteroids/biomes/phenomena/archetypes/sector profiles/travel lanes) and ship visuals; validates assets; provides sprite lookups and archetype/lane/profile helpers.
- `ComponentDB`: loads components JSON, canonicalizes IDs, exposes filtering and sprite helpers.
- `ShipTypeDB`: loads ship_types_v2, filtering helpers.
- `TimeManager`: global time, mode scaling, ticks, big jumps, day changes; emits EventBus signals; calls EconomyManager.on_game_tick.
- `EconomyManager`: commodity/econ/faction market profiles, price calc, market registry, trade execution scaffold, tick-based updates.
- `EconomySimulator`: production/consumption and random events on sim ticks.
- `AiManager`: registry for AgentBrains; currently minimal.
- `RoleDb`, `PersonalityDb`: load NPC role and personality data.

## Runtime systems (non-autoload)
- `GalaxyGenerator`: builds galaxy (systems, routes, regions) using procgen data; assigns factions via FactionManager; chooses starter system.
- `SystemGenerator`: builds per-system bodies/stations using ContentDB data (see `scripts/world/system_generator.gd`).
- `SystemExploration`: in-mode controller; spawns bodies/stations, NPCs, LOD scaling, handles map toggles, streaming, and NPC spawner hookup.
- `SectorStreamer`: streams sector tiles for performance (see `scripts/flight/sector_streamer.gd`).
- `CommSystem`: hails, templates, AI profiles, conversation queue; emits comm messages.
- `DockingManager`: evaluates/approves docking, manages approach/alignment/completion and player control override.
- `FactionRelations`: tracks reputation tiers, interaction memory, and adjusts rep based on events.
- `ShipComponentSystem`: per-ship runtime stats/loadout logic (space/hardpoints, power, stacking, crew efficiency).
- `NPCSpawner`, `FactionManager`, `AgentBrain`, `ShipAgentController`, `ShipSensors`: NPC/AI scaffolding.

## Data-driven approach
- JSON under `data/` drives nearly everything: procgen archetypes/types, components/hulls/ship types, economy profiles/commodities, factions/relations/profiles, dialogue templates/AI profiles, sim configs, time scale.
- Managers typically load in `_ready()` and expose lookups; prefer extending JSON and using helper APIs over hardcoding.

## Signal/event flow (text sketch)
```
[TimeManager] --time_sim_tick--> [EconomySimulator] -> production/consumption -> EconomyManager supply/demand
[TimeManager] --time_day_changed--> (listeners)
[GameRoot/SystemExploration] --EventBus.system_entered--> (UI, state)
[DockingManager] --docking_approved/denied--> [CommSystem] -> comm_message_received -> UI
[CommSystem] --comm_message_received--> UI panels; --comm_response_chosen--> CommSystem follow-ups
[ShipComponentSystem/GameState] --ship_stats_updated/ship_loadout_updated--> UI (ShipSystemsPanel)
[SystemExploration] --map_toggled--> UI maps
```

## Node hierarchy (main flow)
```
GameRoot (Node2D)
  Systems (Node)
    GalaxyGenerator
    SystemGenerator
    SectorStreamer
    FactionManager
    NPCSpawner
    FactionRelations
    DockingManager
    CommSystem
    EconomyManager
    EconomySimulator
    ... (other managers as added)
  WorldRoot (Node)   <- swapped per mode
    SystemExploration (Node2D)
      PlayerShip (CharacterBody2D)
      Background
      Sectors
      StellarBodies (stars, planets, moons, belts, stations)
      NPCShips
  LoadingOverlay (Control)
```

## Extension points
- **New systems**: add as child under `GameRoot/Systems` or autoload; use EventBus signals for loose coupling.
- **New modes**: create scene and load via `SceneManager.transition_to_mode`, adding required systems to `Systems` or mode scene.
- **New data**: extend JSON and update relevant DB loader if new schema fields are required.
- **UI**: listen to EventBus or expose dedicated signals instead of direct node references.

## Cross-system contracts (key)
- TimeManager emits ticks; EconomyManager/EconomySimulator consume them.
- GameState holds canonical session/ship state; SaveSystem should serialize via providers.
- CommSystem and DockingManager rely on EventBus docking signals; stations/ships should emit/receive through EventBus.
- ComponentDB/ShipTypeDB are single sources of truth for loadouts and stats; ShipComponentSystem uses them for runtime effects.
