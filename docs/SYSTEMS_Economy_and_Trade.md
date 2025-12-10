# System: Economy and Trade

## Responsibilities
- Load commodity, economic profile, and faction market data.
- Create and manage station markets; compute prices; handle supply/demand shifts.
- Run background production/consumption simulation and random economic events.
- Expose pricing and trade APIs (UI integration pending).

## Main scripts
- Autoloads: `scripts/autoloads/EconomyManager.gd`, `scripts/autoloads/EconomySimulator.gd`.
- Market class: `scripts/systems/MarketLocation.gd`.
- Data: `data/economy/*.json` (commodities, econ_profiles, faction_market_profiles, black markets, station markets), `data/sim/economy_sim_config.json`.

## Data flow
- EconomyManager `_ready` -> load `commodities.json`, `econ_profiles.json`, `faction_market_profiles` (from `faction_market_profiles.json`).
- `create_market_location` builds `MarketLocation` with faction + econ profile + generated inventory.
- Price calculation pipeline (`calculate_price`):
  1. Base price from commodity.
  2. Econ profile category modifier.
  3. Faction market profile buy/sell factors.
  4. Supply/demand ratio clamp.
  5. Rarity modifier.
  6. Legality modifier (restricted/illegal).
  7. Quantity modifier (bulk).
  8. Random variance.
  9. Tax on buys.
- Ticks: `on_game_tick` triggers price updates every 4 game hours and supply/demand decay hourly.
- EconomySimulator listens to `EventBus.time_sim_tick` → calls production/consumption per market → optional random events → uses EconomyManager supply/demand APIs.

## Signals (planned or existing)
- EventBus has placeholders: `market_prices_updated`, `commodity_shortage/surplus`, `trade_completed` (commented in code). Emit them when UI/logic needs notifications.
- EconomyManager currently emits `EventBus.credits_changed` inside `execute_trade` (credits change only).

## Key structures
- Commodity entry (commodities.json): `id`, `name`, `category`, `base_price`, `rarity`, `legality`, etc.
- Econ profile: `id`, `category_modifiers` map, other tweaks per station archetype.
- Faction market profile: buy/sell factors, tax, illegal tolerance, supply/demand biases, services.
- MarketLocation inventory entry: supply_level, demand_level, current_price, price_history.

## Extension / how to add
- Add commodity: extend `data/economy/commodities.json`; ensure schema matches `schema_economy.json`.
- Add econ profile: edit `econ_profiles.json`; hook to station/system types via generator.
- Add faction market profile: update `faction_market_profiles.json` with `market_profiles` keyed by faction id.
- Add station market: use `EconomyManager.create_market_location` with station data (faction_id, econ_profile).
- Add random event: extend `economy_sim_config.json` `random_events` array; fields `id`, `weight`, `profiles`, `effects` (supply/demand).

## Usage examples
```gdscript
# Get price to buy 10 units of ore_iron at station "station:alpha"
var price = EconomyManager.calculate_price("ore_iron", "station:alpha", true, 10)

# Apply supply event after convoy arrives
EconomyManager.apply_supply_event("station:alpha", "ore_iron", 200)

# Force an economic event (testing)
EconomySimulator.force_event("bountiful_harvest", "station:alpha")
```

## Known gaps / TODOs
- Trading UI not wired; EventBus trade/market signals are commented.
- Station markets need persistence via SaveSystem (MarketLocation.get/set state exists).
- Reputation/legality effects beyond pricing are not implemented.
- Convoys and faction logistics are design-only today.
