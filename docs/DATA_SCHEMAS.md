# Data Schemas

Overview of major JSON files in `data/`. Marked **INFERRED** where code implied structure.

## Procgen
- `data/procgen/system_archetypes.json`
  - `archetypes`: [{`id`, `weight`, `base_pop_level`, `base_tech_level`, `base_mining_quality`, `tags`[], ...}]
  - `regional_modifiers`: biome -> `{pop_modifier, tech_modifier}`.
- `data/procgen/star_types.json`
  - `colors`, `variants_per_color`, `class_to_color`, `sprite_resolver` (`pattern`, `fallback`).
- `data/procgen/planet_types.json`
  - `types`: [{`id`, `name`, `variants`, `num_moons_range`, `asset_pattern`, ...}]
- `data/procgen/moon_types.json` **INFERRED**
  - `types`: [{`id`, `variants`}]; `asset_pattern`.
- `data/procgen/asteroid_types.json`
  - `variants`, `asset_pattern`.
- `data/procgen/biomes.json`, `phenomena.json`, `sector_profiles.json`, `travel_lanes.json`, `station_types.json`
  - Biome/phenomena entries with ids and weights; sector/travel lane profiles with ids and parameters.

## Components and Ships
- `data/components/components.json`
  - Root: `schema`, `defaults`, `sprite_defaults`, `components` (or legacy `component_types`).
  - Component entry:
    - Core: `id` (canonicalizable), `type`, `tier`, `tech_level`, `space_cost`, `tags`, `ai_core` flag.
    - Power/engine: `power_output`, `power_draw`, `thrust`, `turning_torque`, `speed_bonus`.
    - Weapons: `hardpoint_size`, `slot_cost`, `weapon_class`, `damage`, `fire_rate`, `range`, `energy_cost`.
    - Defense: `hull_points_bonus`, `shield_hp_bonus`, `signature_mult`, `signature_flat`, `ecm` bonuses, `armor` stacking.
    - Utility: `cargo_bonus`, `crew_support`, `component_space_bonus_pct`, `add_hardpoints`.
    - Damage block: `damage.condition_hp_max`, etc.
    - Sprite: optional `sprite` dict (`type`, `num_variants`, `path_template`).
- `data/components/schema_components.json`
  - Documentation for component `type` categories and required properties (reactor, drive, shield, weapon, sensor, armor, ecm, computer, cloaking, radiator, cargo_module, habitat, fabricator, lab, hangar, industrial, utility).
- `data/components/ship_types_v2.json`
  - Root: `ships`: [{`id`, `name`, `category`, `size_category`, `manufacturer`, `tech_level`, `base_value`, `tags`[], `mass_base`, `component_space`, `hardpoints`{size:int}, `hull_points`, `shield_strength`, `sensor_strength`, `cargo_capacity`, `maneuverability`, `range_au`, `crew_support`, `stock_components`[], `hull_class_id`}].
- `data/components/hull_visuals.json`
  - `defaults`: `num_variants`; `hulls`: [{`id`, `sprite_type`, `num_variants`}] mapping hull_class_id to sprite assets (`assets/images/actors/ships/{type}_{variant}.png`).

## Economy
- `data/economy/commodities.json`
  - `schema`: `star_loafer.economy.commodities`; `commodities`: [{`id`, `name`, `category`, `base_price`, `rarity`, `legality`, `tags`, ...}].
- `data/economy/econ_profiles.json`
  - `profiles`: [{`id`, `name`, `category_modifiers` map, other bias fields}] keyed by station archetype.
- `data/economy/faction_market_profiles.json`
  - `market_profiles`: map faction -> `{id, buy_price_factor, sell_price_factor, tax_rate, illegal_tolerance, supply_bias, demand_bias, services}`.
- `data/economy/black_market_profiles.json`, `station_markets.json`, `econ_profiles.json` (see above) — used for special markets.
- `data/sim/economy_sim_config.json`
  - `production_multiplier`, `consumption_multiplier`, `enable_random_events`, `event_chance_per_tick`, `production_profiles`, `consumption_profiles`, `random_events` (effects: supply/demand with amounts).
- `data/economy/schema_economy.json` — reference schema for economy files.

## Factions
- `data/factions/factions_core.json` **INFERRED**
  - Expected fields: `id`, `name`, `type` (state/corporate/pirate/etc.), `tags`, `economy_profile`, `relations`.
- `data/factions/faction_relations.json`
  - Pairwise relation presets (hostile, neutral, allied).
- `data/factions/faction_economy_profiles.json`, `faction_market_profiles.json` — faction-specific economy modifiers.
- `data/factions/faction_mission_templates.json` — stubs for missions.
- `data/factions/faction_subfactions.json` — subfaction definitions.

## Dialogue / Comms
- `data/dialogue/comm_message_templates.json`
  - `templates`: map category -> array of templates with `id`, `text`, `base_weight`, optional `context_requirements`, `personality_modifiers`, `reputation_modifiers`, `response_options` (each with `leads_to_category`, etc.).
- `data/dialogue/comm_ai_profiles.json`
  - `profiles`: [{`id`, `personality_traits` map, `outgoing_hail_behavior.max_hail_frequency_per_min`}] used by CommSystem.

## AI roles/personalities
- `data/ai/roles.json`
  - Array of role definitions `{role_id, name, description, tags, weights...}` loaded by RoleDb.
- `data/ai/personalities.json`
  - Array of personality profiles `{profile_id, traits...}` loaded by PersonalityDb.

## Simulation / Time
- `data/sim/time_scale.json`
  - `time_constants` (`HOURS_PER_DAY`, `DAYS_PER_YEAR`), `base_speed.BASE_HOURS_PER_REAL_SECOND`, `tick_settings.SIM_TICK_INTERVAL_HOURS`, `mode_scales` map for time modes.

## Systems/schema references
- `data/systems/system_schema.json`
  - Defines structure for generated systems: `id`, `name`, `pos`, `region_id`, `pop_level`, `tech_level`, `mining_quality`, `faction_id`, `tags`, `archetype`, arrays of bodies/stations, routes.
- `data/systems/sol_system.json`
  - Example/manual system definition.

## Procgen support assets
- `data/procgen/asteroid_types.json`, `planet_types.json`, `moon_types.json`, `star_types.json`, `station_types.json`, `travel_lanes.json`, `sector_profiles.json`, `biomes.json`, `phenomena.json` — used by SystemGenerator/ContentDB.

## Notes
- Many files carry a `schema` string for validation/logging; ensure loaders warn on mismatches.
- When adding new fields, update the relevant loader (ContentDB, ComponentDB, ShipTypeDB, EconomyManager, etc.) to avoid silent ignores.
