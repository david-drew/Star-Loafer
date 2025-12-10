# System: Procgen and Streaming

## Responsibilities
- Generate galaxy layout (systems, routes, regions) with faction assignment.
- Generate per-system contents (stars, planets, moons, belts, stations) using JSON-driven archetypes.
- Stream sector tiles for performance during flight.

## Main scripts
- Galaxy: `scripts/world/galaxy_generator.gd`.
- Systems: `scripts/world/system_generator.gd` and helpers (orbital utils, layout).
- Streaming: `scripts/flight/sector_streamer.gd`.
- Data: `data/procgen/*.json` (system_archetypes, star/planet/moon/asteroid types, biomes, phenomena, sector_profiles, travel_lanes, station types).
- Content loader: `scripts/autoloads/content_db.gd` (provides data and sprite lookup).

## Galaxy generation flow
1. Input: seed + size (`small/medium/large/huge` counts).
2. Poisson-like placement with min separation to create `systems` array.
3. Assign archetype per system (weighted by `system_archetypes.json`), setting pop/tech/mining and tags.
4. Create routes: connect each system to 3 nearest neighbors.
5. Regions: simple 2x2 grid tagged `core_space` vs `outer_rim`; apply regional modifiers from archetype data.
6. Assign factions: call `FactionManager.select_faction_for_system`, compute influence, mark contested borders if hostile neighbors.
7. Starter system selection: choose reasonable pop/tech and non-hostile factions.

## System generation flow (SystemGenerator)
- Input: system id, seed, pop/tech/mining levels.
- Uses ContentDB datasets to pick star types, planets, moons, belts, stations.
- Produces structured data with bodies (kind: star/planet/moon/asteroid_belt), orbits, sizes, station data, faction info.
- Faction id is applied from galaxy data to inhabitants/stations (see SystemExploration `_apply_faction_to_inhabitants`).

## Runtime (SystemExploration)
- Spawns stars/planets/moons/belts/stations from generated data; uses ContentDB for sprites.
- Uses `AU_TO_PIXELS` scaling constants; distance-based LOD scaling for sprites.
- NPCSpawner uses system data to spawn ships; SectorStreamer streams tiles.
- Map toggles emit EventBus signals for UI.

## Streaming (SectorStreamer)
- Manages sector tiles under a parent node (`Sectors`).
- Enables/disables tiles as player moves; SystemExploration sets parent and enables streaming.

## Extension points
- Add new archetypes/tags in `system_archetypes.json` (define weights, stat baselines, tags, regional modifiers).
- Add body types (planets/moons/asteroids/stations) in corresponding JSON files and ensure ContentDB loads them.
- Hook new per-system services: append station data during generation; add fields to station entries consumed by station scenes.
- Swap streaming strategy: extend SectorStreamer to load/unload gameplay nodes per tile.

## Notes / pitfalls
- ContentDB validates sprite assets; missing assets are logged; keep file names aligned with patterns.
- GalaxyGenerator directly references FactionManager methods (`select_faction_for_system`, `get_faction_type`, `are_hostile`); ensure they exist when refactoring.
- Scaling constants in SystemExploration (AU_TO_PIXELS, DISTANCE_SCALE_NEAR/FAR) impact readability; adjust carefully alongside camera zoom defaults.
