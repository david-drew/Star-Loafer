# System: Ship Components and Ship Types

## Responsibilities
- Load and index component definitions and ship types from JSON.
- Provide sprite lookup for hulls and components.
- Manage per-ship runtime loadout, capacities, and derived stats.

## Main scripts
- Autoloads: `scripts/autoloads/ComponentDB.gd`, `scripts/autoloads/ShipTypeDB.gd`.
- Runtime per-ship: `scripts/systems/ShipComponentSystem.gd`.
- Data: `data/components/components.json`, `schema_components.json`, `ship_types_v2.json`, `hull_visuals.json`.

## Data model
- Component IDs canonical form: `type__local_name` (ComponentDB normalizes legacy forms).
- Components include type, tier, tags, space_cost, hardpoint data (for weapons), power draw/output, bonuses (hull/shield/sensors/cargo/etc.), sprite info, crew requirements, damage/condition fields.
- Ship type: `id`, category, size_category, hull stats (mass, component_space, hardpoints by size, hull_points, shields, sensors, cargo, maneuverability, range), tags, manufacturer, stock_components array of component IDs, hull_class_id for visuals.
- Hull visuals: map hull_class_id to sprite type and variants; defaults in `hull_visuals.defaults`.

## Runtime (ShipComponentSystem)
- `init_from_ship_type(ship_type_id, db, ship_db)` loads hull data and installs stock components.
- Tracks `installed` array entries `{id, state, throttle, priority, condition_hp}`.
- Capacity checks: `get_component_space_free`, `get_hardpoints_free(size)` consider bonuses and retrofit caps.
- Power model: sums power_output vs power_draw; if negative, sheds lowest-priority operational components.
- Derived stats: hull_points, shields, sensors, cargo, speed_rating, range, signature/stealth, heat, reliability, crew support, thrust/torque, acceleration/turn_rate, power margin.
- Stacking rules: diminishing returns for armor, speed, ecm; crew efficiency impacts outputs; condition_hp scales effectiveness.

## Key APIs
```gdscript
# Query data
var def = ComponentDB.get_def("reactor__fission_mk1")
var ship_def = ShipTypeDB.get_ship_def("starter_frigate")

# Initialize a ship
var scs = ShipComponentSystem.new()
scs.init_from_ship_type("starter_frigate", ComponentDB, ShipTypeDB)

# Install/toggle components
scs.install("weapon__light_laser_mk1")
scs.toggle("weapon__light_laser_mk1", false)
var stats = scs.get_current_stats()
```

## Extension steps
- Add a component: update `components.json` (respect schema), supply sprites using `sprite_defaults` or per-component `sprite`. Keep type IDs canonical.
- Add a hull visual: extend `hull_visuals.json` and ensure assets match `assets/images/actors/ships/{type}_{variant}.png`.
- Add a ship type: update `ship_types_v2.json` (see workflows); include `stock_components` and `hull_class_id`.
- UI integration: use EventBus signals (`ship_stats_updated`, `ship_loadout_updated`, `ship_component_candidates_updated`) to sync panels; emit on install/remove/toggle actions.

## Pitfalls / notes
- ComponentDB loader accepts `components` or legacy `component_types`; prefer `components`.
- ShipComponentSystem assumes ComponentDB/ShipTypeDB exist (autoload) unless passed explicitly.
- Hardpoint retrofits capped by `retrofit_hardpoint_caps` defaults; adjust in ComponentDB defaults if needed.
- Avoid ternary operators in examples; keep helper functions small and explicit.
