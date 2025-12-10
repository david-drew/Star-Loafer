# STAR LOAFER ECONOMY SYSTEM SPECIFICATION v1.0

**Status:** Design Complete | **Date:** 2025-11-17 | **For:** Future Development & AI Context

---

## 1. SYSTEM OVERVIEW

### Purpose
Autonomous, consequence-driven economy that operates independently while providing rich player trading gameplay across a procedurally generated galaxy.

### Core Principles
- **Loosely Simulationist:** Believable without being a full economic simulation
- **Data-Driven:** All parameters in JSON files
- **Modular:** Systems communicate via EventBus
- **Faction-Centric:** Each faction has distinct economic identity
- **Consequence-Driven:** Actions create cascading effects

---

## 2. ARCHITECTURE

```
EconomyManager (Singleton)
├── CommodityDatabase (from commodities.json)
├── StationMarkets (Dictionary of StationMarket instances)
├── ConvoySystem (spawns/manages NPC trade convoys)
├── TradeRouteAnalyzer (discovers/ranks profitable routes)
└── BlackMarketSystem (illegal trade mechanics)

EventBus Integration:
- market_prices_updated, trade_completed
- convoy_arrived, convoy_destroyed  
- commodity_shortage, economic_crisis_triggered
```

### Key Classes
- **EconomyManager** - Central authority, price calculation, transaction processing
- **StationMarket** - Per-station inventory, pricing, trades
- **ConvoyData** - NPC trade vessel data
- **TradeRoute** - Route profitability analysis
- **CommodityState** - Per-station commodity tracking

---

## 3. PRICE CALCULATION SYSTEM

### Formula
```
final_price = base_price 
  × econ_profile_modifier      // Station type (industrial, mining, etc.)
  × faction_market_modifier    // Faction buy/sell factors
  × supply_demand_modifier     // 0.5× to 2.0× based on local conditions
  × rarity_modifier            // 1.0× to 3.0× by rarity tier
  × legality_modifier          // 1.0× to 4.0× for illegal goods
  × quantity_modifier          // Bulk discount/premium
  × variance                   // ±5-10% random
  × (1 + tax_rate)            // If player is buying
```

### Modifiers

**Economic Profile** (from econ_profiles.json):
- Industrial: Buys raw materials cheap (0.8×), sells manufactured expensive
- Mining: Sells minerals cheap (0.6×), buys food expensive (1.3×)
- Agricultural: Sells food cheap (0.7×), buys tech expensive (1.2×)
- Frontier: Everything expensive (1.1-1.5×)
- Luxury: Luxury goods cheap (0.7×), others normal

**Faction Market Profile** (from faction_economy_profiles.json):
| Faction | Buy Factor | Sell Factor | Tax | Tolerance |
|---------|-----------|-------------|-----|-----------|
| Imperial Meridian | 1.00 | 0.95 | 15% | 10% |
| Black Exchange | 1.05 | 1.05 | 0% | 95% |
| Artilect Custodians | 0.85 | 0.90 | 10% | 10% |
| Free Hab League | 0.90 | 0.98 | 5% | 30% |

**Supply/Demand Modifier:**
```gdscript
modifier = demand_level / supply_level
modifier = clamp(modifier, 0.5, 2.0)

// Examples:
// High supply (1.8), low demand (0.6): 0.33 → 0.5 (50% price)
// Low supply (0.3), high demand (1.5): 5.0 → 2.0 (200% price)
```

**Rarity Modifier:**
- Common: 1.0×
- Uncommon: 1.2×
- Rare: 1.5×
- Very Rare: 2.0×
- Legendary: 3.0×

---

## 4. STATION MARKET SYSTEM

### StationMarket Class

**Properties:**
```gdscript
var station_id: String
var faction_id: String
var econ_profile_id: String  // References econ_profiles.json
var market_profile: Dictionary  // From faction_economy_profiles.json

var inventory: Dictionary = {}  // commodity_id -> CommodityState
```

**CommodityState:**
```gdscript
var commodity_id: String
var quantity: int
var current_price: float
var supply_level: float = 1.0  // 0.0=empty, 1.0=normal, 2.0=surplus
var demand_level: float = 1.0  // 0.0=none, 1.0=normal, 2.0=critical
var price_history: Array[float]
```

### Key Methods
- `get_buy_price(commodity_id, quantity)` - What player pays
- `get_sell_price(commodity_id, quantity)` - What player receives
- `buy_from_player(commodity_id, quantity)` - Player sells to station
- `sell_to_player(commodity_id, quantity)` - Player buys from station
- `update_prices()` - Recalculate based on supply/demand
- `generate_initial_inventory()` - Create starting stock
- `refresh_inventory()` - Periodic restocking

---

## 5. SUPPLY & DEMAND SIMULATION

### Supply Events (Increase Supply)
1. **Convoy Arrivals** - NPC convoys deliver goods
2. **Local Production** - Systems produce based on planet types
3. **Player Sales** - Player selling increases station stock

### Demand Events (Increase Demand)
1. **Station Consumption** - Population consumes goods
2. **Player Purchases** - Player buying depletes stock
3. **Manufacturing Needs** - Industrial stations need raw materials

### Supply/Demand Tracking
```gdscript
// On trade:
market.update_supply_level(commodity_id, change)
market.update_demand_level(commodity_id, change)

// Periodic decay toward baseline:
supply_level = lerp(supply_level, 1.0, 0.05)  // 5% per update
demand_level = lerp(demand_level, 1.0, 0.05)
```

### Shortage/Surplus Classification
```gdscript
ratio = supply_level / demand_level

if ratio < 0.3: "critical_shortage"  // Prices 2.0×
elif ratio < 0.6: "shortage"         // Prices 1.5×
elif ratio > 2.0: "surplus"          // Prices 0.5×
elif ratio > 1.5: "oversupply"       // Prices 0.7×
else: "normal"
```

---

## 6. NPC CONVOY SYSTEM

### Purpose
- Create visible autonomous economic activity
- Generate missions (escorts, piracy)
- Physically move commodities between stations
- Create consequences when disrupted

### Convoy Types
1. **Trade Convoys** - General goods, mixed cargo
2. **Mining Convoys** - Ore from belts to processors
3. **Luxury Convoys** - High-value, heavily guarded
4. **Smuggler Runs** - Illegal goods, stealthy
5. **Humanitarian** - Aid to crisis zones

### ConvoyData Structure
```gdscript
var convoy_id: String
var faction_id: String
var origin_station_id: String
var destination_station_id: String
var cargo: Array[{commodity_id, quantity}]
var total_value: int
var escort_strength: int
var route_risk: float  // 0.0 safe - 1.0 dangerous
var status: String  // "departing", "in_transit", "arrived", "destroyed"
var eta_tick: int
```

### Convoy Generation
```gdscript
// Every 12 game hours per faction:
1. Analyze supply/demand across faction territory
2. Find opportunities (surplus at origin, shortage at destination)
3. Sort by profitability
4. Create convoys for top opportunities
5. Assign escorts based on value and route risk
6. Spawn physical entities in game world
```

### Convoy Impact

**Arrival:**
- Add cargo to destination inventory
- Increase supply_level
- Decrease prices (supply increase)

**Destruction:**
- Cargo never arrives
- Increase demand_level at destination
- Increase prices (supply shortage)
- Reputation impact on attacker
- Check for economic crisis

### Economic Crisis Thresholds
- **Minor** (3-5 convoys lost): +10-20% prices, delivery missions
- **Moderate** (6-9 lost): +30-50% prices, emergency missions
- **Severe** (10-14 lost): +80-120% prices, system-wide disruption
- **Catastrophic** (15+ lost): +150-250% prices, economic collapse event

---

## 7. BLACK MARKET SYSTEM

### Access Methods
1. **Reputation** - Black Exchange rep ≥ threshold
2. **Contacts** - Unlocked through quests
3. **Location** - Criminal faction territory
4. **Quest Unlock** - Special story unlocks

### Black Market vs Legal Market

| Aspect | Legal | Black Market |
|--------|-------|--------------|
| Tax Rate | 5-15% | 0% |
| Illegal Tolerance | 0-40% | 90-100% |
| Detection Risk | High | Very Low |
| Illegal Goods Price | 2-4× markup | 0.7× discount (buying) / 1.4× premium (selling) |

### Illegal Trade Detection
```gdscript
detection_chance = (1.0 - faction_tolerance) 
                 × quantity_multiplier 
                 × legality_multiplier

// If detected:
- Fine (2-5× cargo value)
- Reputation loss (-10 to -25)
- Cargo seized
- Possible bounty placed
- Security dispatch
```

### Consequences
**Successful Illegal Trade:**
- +2-5 rep with criminal factions
- High profit (100-300% margin)

**Detected:**
- Fines, cargo seizure
- -25 rep with catching faction
- -10 rep with allied factions
- +5 rep with rival criminals (street cred)
- Possible bounty and combat encounter

---

## 8. TRADE ROUTE SYSTEM

### TradeRoute Structure
```gdscript
var route_id: String
var origin_station_id: String
var destination_station_id: String
var commodity_id: String
var buy_price: float
var sell_price: float
var profit_per_unit: float
var profit_margin: float
var distance_ly: float
var travel_time_hours: float
var risk_level: float  // 0.0 safe - 1.0 dangerous
var recommended_quantity: int
var discovered_by_player: bool
```

### Discovery Methods
1. **Visiting Stations** - Learn prices, can calculate routes
2. **Purchasing Data** - Buy trade intelligence
3. **NPC Tips** - Dialogue reveals hints
4. **Observing Convoys** - Following NPCs

### Route Ranking
```gdscript
profit_score = profit_per_unit × player_cargo_capacity
time_score = profit_score / travel_time_hours  // Profit per hour
risk_penalty = 1.0 - (risk_level × 0.5)
overall_score = time_score × risk_penalty
```

### Route Updates
- Recalculate when prices change significantly (>15%)
- Mark routes as fresh/current/stale/outdated based on age
- Notify player of major route changes

---

## 9. ECONOMIC CONSEQUENCES

### Cascade Effects
```
Event: Iron Ore Convoys Destroyed (10)
  ↓
Iron ore shortage at industrial station
  ↓
Can't produce ship components
  ↓
Component shortage develops
  ↓
Component prices rise in region (+80%)
  ↓
Shipyard upgrade costs increase (+30%)
  ↓
Players delay upgrades
  ↓
Escort mission demand increases
```

### Cascade Implementation
```gdscript
1. Initial shortage triggers
2. Check commodity dependencies (ore → components → ships)
3. Propagate shortage to dependent commodities (70% severity)
4. Spread to connected stations (50% severity within 2 jumps)
5. Trigger market reactions (panic buying, hoarding)
6. Emit economic_cascade event
```

### Faction Economic Actions

**Embargoes:**
- Ban trade with target faction
- Apply to all faction stations
- Affected goods see price increases
- Creates smuggling opportunities

**Subsidies:**
- Reduce price of specific commodity
- Duration-based (expires)
- Encourages specific trade behavior
- Faction-wide application

---

## 10. PROCEDURAL GENERATION INTEGRATION

### System Economy Initialization
```gdscript
func initialize_system_economy(system_data):
    1. Determine economic character
       - Dominant faction → market profile
       - System archetype → economic profile
       - Planet types → production bias
    
    2. Create station markets
       - For each station, select econ_profile
       - Apply faction market_profile
       - Generate initial inventory
    
    3. Generate local trade routes
    
    4. Spawn initial convoys
    
    5. Set up production/consumption profiles
```

### Station Market Generation
```gdscript
func create_station_market(station, system_economy):
    // Select economic profile based on:
    - Station type (industrial_station → "industrial" profile)
    - System archetype (core_world → "luxury")
    - Tech level, resources
    
    // Generate inventory:
    - Check if commodity should be stocked
      - Illegal goods only in black markets/criminal space
      - Rarity affects stock chance
      - Economic profile affects relevance
    - Calculate initial quantity
    - Set starting prices
```

### Production & Consumption
```gdscript
// Production (adds supply):
- Mining systems → ore_iron, ore_titanium
- Agricultural planets → food_basic, grain_bulk
- Industrial stations → microchips, components

// Consumption (creates demand):
- Population × 20 → food_basic
- Population × 5 → medkits
- Industrial stations → raw materials
```

---

## 11. EVENTBUS INTEGRATION

### Signal Categories

**Market Signals:**
```gdscript
signal market_prices_updated(station_id, price_changes)
signal commodity_shortage(station_id, commodity_id, severity)
signal commodity_surplus(station_id, commodity_id, amount)
signal station_restocked(station_id, commodities)
```

**Trade Signals:**
```gdscript
signal trade_completed(trade_data)  // {station_id, player_id, commodity_id, quantity, total_value, is_buy}
signal illegal_trade_detected(detection_data)  // {station_id, player_id, commodity_id, consequences}
signal trade_route_discovered(player_id, route)
```

**Convoy Signals:**
```gdscript
signal convoy_spawned(convoy_data)
signal convoy_departed(convoy_data)
signal convoy_arrived(convoy_data)
signal convoy_destroyed(convoy_data, attacker_faction)
signal convoy_under_attack(convoy_data, location)
```

**Economic Impact Signals:**
```gdscript
signal economic_crisis_triggered(system_id, crisis_type, severity)
signal system_economy_disrupted(system_id, severity)
signal regional_price_shift(commodity_id, region, modifier)
signal faction_embargo_imposed(issuer_faction, target_faction, commodities)
```

### Event Usage Pattern
```gdscript
// In EconomyManager:
EventBus.market_prices_updated.emit(station_id, changes)

// In UI:
func _ready():
    EventBus.market_prices_updated.connect(_on_prices_updated)

// In MissionSystem:
func _ready():
    EventBus.convoy_destroyed.connect(_generate_escort_mission)
```

---

## 12. BALANCE PARAMETERS

### Price Ranges by Category
| Category | Common | Uncommon | Rare | Very Rare |
|----------|--------|----------|------|-----------|
| Agri | 20-60 | 60-120 | 120-300 | 300-800 |
| Mineral | 40-80 | 80-150 | 150-400 | 400-1000 |
| Tech | 100-300 | 300-600 | 600-1500 | 1500-5000 |
| Medical | 80-200 | 200-400 | 400-1000 | 1000-3000 |
| Luxury | 200-500 | 500-1200 | 1200-3000 | 3000-10000 |
| Weapons | 300-800 | 800-2000 | 2000-5000 | 5000-20000 |
| Contraband | 400-1000 | 1000-2500 | 2500-7000 | 7000-30000 |

### Target Profit Margins
| Trade Type | Margin | Risk | Examples |
|------------|--------|------|----------|
| Bulk Commodities | 10-20% | Low | Grain, ore |
| Standard Trade | 20-35% | Low-Med | Food, tech |
| Specialized | 35-60% | Medium | Medical, luxury |
| Restricted | 60-100% | High | Weapons |
| Illegal | 100-300% | Very High | Contraband |

### Cargo Economics
**Small Bay (50 units):**
- Focus: High-value goods (luxury, tech, contraband)
- Profit per trip: 5,000-20,000 credits
- Trips per hour: 3-4

**Medium Bay (100 units):**
- Focus: Mixed strategy (medical, tech, weapons)
- Profit per trip: 15,000-50,000 credits
- Trips per hour: 2-3

**Large Bay (200 units):**
- Focus: Bulk hauling (agri, minerals)
- Profit per trip: 30,000-80,000 credits
- Trips per hour: 1-2

### Update Frequencies
```gdscript
const TICKS_PER_GAME_HOUR = 60

PRICE_UPDATE_INTERVAL = 4 hours  // Price recalculation
SUPPLY_DEMAND_DECAY_INTERVAL = 1 hour  // Normalization
RESTOCK_INTERVAL = 1 day  // Station restocking
CONVOY_SPAWN_INTERVAL = 12 hours  // Per faction
PRODUCTION_TICK = 6 hours  // Local production/consumption
HEALTH_CHECK_INTERVAL = 8 hours  // Economic crisis checks
```

---

## 13. IMPLEMENTATION ROADMAP

### Phase 1: Core Foundation (Week 1-2)
**Deliverables:**
- EconomyManager.gd singleton
- StationMarket.gd class
- CommodityState.gd helper
- Basic UI (market overview, buy/sell)
- EventBus trading signals

**Testing:** Basic trading works, prices reflect modifiers, cargo enforced

### Phase 2: Dynamic Pricing (Week 3-4)
**Deliverables:**
- Supply/demand tracking
- Price update system with decay
- Station inventory generation
- Price history tracking
- Enhanced UI (indicators, graphs)

**Testing:** Prices change based on trades, decay works, profiles apply

### Phase 3: NPC Activity (Week 5-7)
**Deliverables:**
- ConvoySystem.gd manager
- Convoy.gd class with movement
- Convoy arrival/destruction processing
- Trade route generation
- Economic cascade system

**Testing:** NPCs trade autonomously, destruction creates shortages, cascades work

### Phase 4: Advanced Features (Week 8-10)
**Deliverables:**
- Black market system
- Trade route analyzer
- Economic consequence systems (crises, embargoes, subsidies)
- Enhanced UI (route planner, alerts, news)

**Testing:** All systems integrated, black markets work, crises trigger correctly

### Phase 5: Polish & Balance (Week 11-12)
**Deliverables:**
- Balance pass on all prices
- Performance optimization
- Save/load integration
- Tutorial/documentation

**Testing:** Stable, performant, no exploits, good player experience

---

## 14. KEY DATA STRUCTURES

### Existing JSON Files
- **commodities.json** - 10 commodities with base prices, categories, legality
- **econ_profiles.json** - 5 profiles (industrial, mining, agri, frontier, luxury)
- **faction_economy_profiles.json** - Market profiles + system weights per faction
- **factions_core.json** - 16 factions with economic references
- **planet_types.json** - Production biases (resource_bias field)
- **system_archetypes.json** - System economic characteristics

### New Runtime Structures
```gdscript
# MarketState (per station, saved)
{
    "station_id": String,
    "owner_faction": String,
    "econ_profile": String,
    "inventory": {
        "commodity_id": {
            "quantity": int,
            "current_price": float,
            "supply_level": float,
            "demand_level": float,
            "price_history": Array[float]
        }
    }
}

# ConvoyData (runtime, saved)
{
    "convoy_id": String,
    "faction_id": String,
    "origin": String,
    "destination": String,
    "cargo": [{commodity_id, quantity}],
    "total_value": int,
    "status": String,
    "eta_tick": int,
    "escort_strength": int,
    "route_risk": float
}

# TradeRoute (player discovered, saved)
{
    "route_id": String,
    "origin": String,
    "destination": String,
    "commodity_id": String,
    "buy_price": float,
    "sell_price": float,
    "profit_per_unit": float,
    "distance_ly": float,
    "risk_level": float,
    "discovered_by_player": bool,
    "last_updated": int
}
```

---

## 15. CRITICAL DESIGN NOTES

### For AI Context (Future Chats)
When continuing work on this economy system, remember:

1. **Modularity is Key** - All systems communicate via EventBus, no tight coupling
2. **Data-Driven** - Prices, profiles, behaviors all in JSON
3. **Autonomous NPCs** - Convoys make logical decisions, not scripted
4. **Consequences Matter** - 1 convoy = minor, 10 convoys = crisis
5. **Faction Identity** - Each faction's market behavior reflects their ethos
6. **Performance** - Target <50ms for full economy update (100 stations, 50 convoys)

### Integration Points
- **Ship Component System** - cargo_capacity stat determines trading capability
- **Faction Relations** - affects trade availability, detection risk, embargo participation
- **Mission System** - convoy events generate missions (escorts, emergencies)
- **Procedural Generation** - systems generate with coherent economic profiles

### Known Gaps (To Implement)
- Faction economic AI (when to impose embargoes, adjust subsidies)
- Market manipulation detection system
- Trade insurance mechanics
- Loan/credit system for large purchases
- Commodity futures/contracts
- Station-specific production modifiers

---

## 16. QUICK REFERENCE

### Most Important Methods
```gdscript
# EconomyManager
EconomyManager.calculate_price(commodity_id, station_id, is_buying, quantity) -> float
EconomyManager.execute_trade(station_id, player_id, commodity_id, quantity, is_buying) -> Dictionary
EconomyManager.update_station_prices(station_id) -> void

# StationMarket
market.get_buy_price(commodity_id, quantity) -> float
market.get_sell_price(commodity_id, quantity) -> float
market.has_sufficient_stock(commodity_id, quantity) -> bool

# ConvoySystem (to implement)
ConvoySystem.spawn_faction_convoys(faction_id) -> void
ConvoySystem.on_convoy_arrived(convoy) -> void
ConvoySystem.on_convoy_destroyed(convoy, attacker) -> void
```

### Most Important Events
```gdscript
EventBus.trade_completed.emit(trade_data)
EventBus.convoy_destroyed.emit(convoy_data, attacker)
EventBus.market_prices_updated.emit(station_id, changes)
EventBus.commodity_shortage.emit(station_id, commodity_id, severity)
EventBus.economic_crisis_triggered.emit(system_id, crisis_type, severity)
```

---

## DOCUMENT END

**Version:** 1.0  
**Status:** Complete - Ready for Implementation  
**Next Steps:** Begin Phase 1 with EconomyManager and StationMarket

**For Questions:**
- Implementation details → Sections 2-11
- Balance → Section 12
- Roadmap → Section 13
- Quick lookup → Section 16

**Attach this document to future AI chats about Star Loafer economy for full context.**
