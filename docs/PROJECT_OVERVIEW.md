# Star Loafer – Project Overview

## What this is
- 2D space-exploration RPG (Godot 4.5, GDScript-first).
- Pillars: procedural galaxy/system generation, data-driven ships/components, economy and factions, lightweight missions/away-team hooks, EventBus-driven UI and systems.
- Current playable slice: galaxy + system procgen, system exploration mode with streaming sectors, player ship flight, NPC spawning, economy scaffolding, comms/docking interactions, and data-driven ships/components.

## Current implementation status (high level)
- **Core loop**: start game → generate galaxy → enter a system → explore, dock, trade scaffold, talk to stations/NPCs.
- **Procgen**: galaxy generation with factions, routes, regions; per-system generation with stars, planets, moons, stations, belts (see `GalaxyGenerator`, `SystemGenerator`, `ContentDB` data).
- **Flight/System Exploration**: `system_exploration` mode spawns bodies, stations, NPCs, and streams sectors for performance.
- **Economy**: `EconomyManager` loads commodities/econ profiles; `EconomySimulator` ticks production/consumption/events; pricing logic exists but UI hookup is minimal.
- **Factions/Relations**: `FactionRelations` tracks reputation tiers and reports interactions; faction assignment occurs during galaxy gen.
- **Comms/Docking**: `CommSystem` handles hails/templates/AI profiles; `DockingManager` handles approvals and docking phases; UI uses EventBus signals.
- **Ships/Components**: `ComponentDB`, `ShipTypeDB`, `ShipComponentSystem` provide data and runtime stats for hulls and loadouts.
- **AI/NPCs**: `NPCSpawner` (not shown in this doc) hooks into system gen; `AIManager` tracks agents; `ShipAgentController`/`AgentBrain` handle behaviors (simple scaffolding).
- **Save/Load & Scene Flow**: `SceneManager` swaps scenes and flags new vs load; `SaveSystem` exists but provider API mismatch is WIP (see notes).
- **UI**: HUD, galaxy/system maps, comm panel, ship systems panel, notifier panel; EventBus toggles and updates.

## WIP / fuzzy areas
- Economy UI and actual player trade transactions are not fully wired to gameplay.
- Missions/away-team systems are mostly design docs; runtime hooks not present yet.
- SaveSystem provider interface is inconsistent (`register_provider` stores `get/set` but calls `write/read`); needs alignment.
- Combat, damage, and detailed ship flight model are largely TBD.
- NPC AI behaviors are minimal; many stubs and TODOs remain.

## Godot layout (top level)
- Main scene: `scenes/game_root.tscn` (`scripts/game_root.gd`) owns:
  - `Systems` (GalaxyGenerator, FactionManager, NPCSpawner, SectorStreamer, SystemGenerator, etc.).
  - `WorldRoot` (swapped per mode).
  - `LoadingOverlay`.
- Modes: primary mode is `scenes/modes/system_exploration.tscn` (`scripts/world/system_exploration.gd`); other modes not yet present.
- Autoloads (see `project.godot`):
  - EventBus, SaveSystem, SceneManager, GameState, ContentDB, ComponentDB, ShipTypeDB, TimeManager, EconomyManager, EconomySimulator, AiManager, RoleDb, PersonalityDb.

## Core flow (current slice)
1. **Main menu** (UI scene) calls `SceneManager.start_fresh_game(config)` or load.
2. **GameRoot** generates galaxy via `GalaxyGenerator.generate(seed, size)`; stores in `GameState`.
3. Select starter system → mark discovered → load mode `system_exploration.tscn`.
4. **SystemExploration** generates system via `SystemGenerator` using ContentDB data; spawns stars/planets/moons/stations, NPCs via `NPCSpawner`, enables `SectorStreamer`.
5. Player flies ship; EventBus toggles maps/UI; comms and docking use CommSystem and DockingManager signals; TimeManager drives ticks, EconomySimulator/EconomyManager react.
6. Save/load: SaveSystem intended to gather providers, but integration is partial (see Save doc).

## Extension hooks to keep in mind
- Add data first (JSON) then code: ContentDB, ComponentDB, ShipTypeDB, Economy data, faction data, comm templates.
- EventBus for cross-system messages (time ticks, map toggles, ship stats/loadout, comms/docking).
- System generators respect data files (procgen and system schemas); prefer extending JSON archetypes over hardcoding.
- Autoload managers expose helper APIs (ComponentDB.get_def, ShipTypeDB.get_ship_def, EconomyManager.calculate_price, etc.).

