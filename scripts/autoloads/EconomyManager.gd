## EconomyManager.gd
## Autoload singleton managing the Star Loafer economy system
## 
## Responsibilities:
## - Load and manage commodity database
## - Maintain registry of all station markets
## - Calculate prices with all modifiers
## - Process trade transactions
## - Update supply/demand across markets
## - Coordinate with NPC convoy system
##
## Usage: Add to Project Settings -> Autoload as "EconomyManager"

extends Node

## Path constants for data files
const DATA_PATH_COMMODITIES = "res://data/economy/commodities.json"
const DATA_PATH_ECON_PROFILES = "res://data/economy/econ_profiles.json"
const DATA_PATH_FACTION_ECONOMY = "res://data/economy/faction_market_profiles.json"

## Update timing constants (in game ticks)
const TICKS_PER_GAME_HOUR = 60
const PRICE_UPDATE_INTERVAL = TICKS_PER_GAME_HOUR * 4  # Every 4 hours
const SUPPLY_DEMAND_DECAY_INTERVAL = TICKS_PER_GAME_HOUR  # Every hour

## Price calculation constants
const MIN_PRICE_MODIFIER = 0.5
const MAX_PRICE_MODIFIER = 2.0
const PRICE_VARIANCE_MIN = 0.95
const PRICE_VARIANCE_MAX = 1.05

## Core databases (loaded from JSON)
var commodity_database: Dictionary = {}  # commodity_id -> commodity_data
var econ_profiles: Dictionary = {}  # profile_id -> profile_data
var faction_market_profiles: Dictionary = {}  # faction_id -> market_profile_data

## Runtime state
var market_locations: Dictionary = {}  # station_id -> StationMarket instance
var game_tick: int = 0
var last_price_update: int = 0
var last_supply_demand_decay: int = 0

## Preloaded StationMarket class
const MarketLocation = preload("res://scripts/systems/MarketLocation.gd")

# Region Initialization

func _ready() -> void:
	print("[EconomyManager] Initializing economy system...")
	load_economy_data()
	print("[EconomyManager] Economy system ready. Commodities: %d, Profiles: %d" % [
		commodity_database.size(),
		econ_profiles.size()
	])

## Load all economy data from JSON files
func load_economy_data() -> void:
	load_commodity_database()
	load_econ_profiles()
	load_faction_market_profiles()

## Load commodities from JSON
func load_commodity_database() -> void:
	var data = _load_json_file(DATA_PATH_COMMODITIES)
	if data.is_empty():
		push_error("[EconomyManager] Failed to load commodity database")
		return
	
	# Validate schema
	if data.get("schema") != "star_loafer.economy.commodities":
		push_warning("[EconomyManager] Commodity schema mismatch: %s" % data.get("schema"))
	
	# Build lookup dictionary
	for commodity in data.get("commodities", []):
		commodity_database[commodity.id] = commodity
	
	print("[EconomyManager] Loaded %d commodities" % commodity_database.size())

## Load economic profiles from JSON
func load_econ_profiles() -> void:
	var data = _load_json_file(DATA_PATH_ECON_PROFILES)
	if data.is_empty():
		push_error("[EconomyManager] Failed to load economic profiles")
		return
	
	# Validate schema
	if data.get("schema") != "star_loafer.economy.econ_profiles":
		push_warning("[EconomyManager] Econ profiles schema mismatch: %s" % data.get("schema"))
	
	# Build lookup dictionary
	for profile in data.get("profiles", []):
		econ_profiles[profile.id] = profile
	
	print("[EconomyManager] Loaded %d economic profiles" % econ_profiles.size())

## Load faction market profiles from JSON
func load_faction_market_profiles() -> void:
	var data = _load_json_file(DATA_PATH_FACTION_ECONOMY)
	if data.is_empty():
		push_error("[EconomyManager] Failed to load faction economy profiles")
		return
	
	# Extract market_profiles section
	var market_profiles = data.get("market_profiles", {})
	
	for faction_market_id in market_profiles.keys():
		var profile = market_profiles[faction_market_id]
		# Extract faction_id from market profile id (e.g., "imperial_meridian_market" -> "imperial_meridian")
		var faction_id = profile.get("id", "").replace("_market", "")
		if faction_id.is_empty():
			push_warning("[EconomyManager] Could not extract faction_id from: %s" % profile.get("id"))
			continue
		
		faction_market_profiles[faction_id] = profile
	
	print("[EconomyManager] Loaded %d faction market profiles" % faction_market_profiles.size())

## Generic JSON loader with error handling
func _load_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[EconomyManager] File not found: %s" % path)
		return {}
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[EconomyManager] Failed to open file: %s" % path)
		return {}
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_text)
	
	if error != OK:
		push_error("[EconomyManager] JSON parse error in %s: %s" % [path, json.get_error_message()])
		return {}
	
	return json.data

#endregion

#region Station Market Management

## Create and register a new station market
## Call this during system/station generation
func create_market_location(market_data: Dictionary) -> MarketLocation:
	var market_id = market_data.get("id", "")
	if market_id.is_empty():
		push_error("[EconomyManager] Cannot create market: market_id missing")
		return null
	
	if market_locations.has(market_id):
		push_warning("[EconomyManager] Market already exists for station: %s" % market_id)
		return market_locations[market_id]
	
	# Extract market parameters from station_data
	var faction_id = market_data.get("owner_faction", "")
	var econ_profile_id = market_data.get("econ_profile", "industrial")  # Default if not specified
	
	# Get faction's market profile
	var market_profile = faction_market_profiles.get(faction_id, {})
	if market_profile.is_empty():
		push_warning("[EconomyManager] No market profile for faction: %s, using defaults" % faction_id)
		market_profile = _get_default_market_profile()
	
	# Create market instance
	var market = MarketLocation.new()
	market.initialize(market_id, faction_id, econ_profile_id, market_profile)
	
	# Generate initial inventory
	market.generate_initial_inventory(commodity_database, econ_profiles.get(econ_profile_id, {}))
	
	# Register market
	market_locations[market_id] = market
	
	print("[EconomyManager] Created market for station: %s (faction: %s, profile: %s)" % [
		market_id, faction_id, econ_profile_id
	])
	
	return market

## Get a market by ID
func get_market(market_id: String) -> MarketLocation:
	return market_locations.get(market_id)

## Get all market IDs (for EconomySimulator and other systems)
func get_all_markets() -> Array:
	return market_locations.keys()

## Get all market instances
func get_all_market_instances() -> Array:
	return market_locations.values()

## Check if a market exists
func has_market(market_id: String) -> bool:
	return market_locations.has(market_id)

## Register an existing market (for loading saved games)
func register_market(market: MarketLocation) -> void:
	if market == null:
		push_error("[EconomyManager] Cannot register null market")
		return
	
	market_locations[market.market_id] = market

## Default market profile fallback
func _get_default_market_profile() -> Dictionary:
	return {
		"buy_price_factor": 1.0,
		"sell_price_factor": 0.90,
		"tax_rate": 0.10,
		"illegal_tolerance": 0.15,
		"supply_bias": {},
		"demand_bias": {},
		"services": []
	}

#endregion

#region Price Calculation

## Calculate price for a commodity at a station
## is_buying: true if player is buying FROM station, false if selling TO station
func calculate_price(
	commodity_id: String,
	station_id: String,
	is_buying: bool,
	quantity: int = 1
) -> float:
	
	var commodity = commodity_database.get(commodity_id)
	if commodity == null:
		push_error("[EconomyManager] Unknown commodity: %s" % commodity_id)
		return 0.0
	
	var market = get_market(station_id)
	if market == null:
		push_error("[EconomyManager] No market for station: %s" % station_id)
		return commodity.base_price
	
	# Start with base price
	var price = float(commodity.base_price)
	
	# 1. Economic profile modifier (station type)
	var econ_profile = econ_profiles.get(market.econ_profile_id, {})
	var category = commodity.get("category", "")
	var econ_modifier = econ_profile.get("category_modifiers", {}).get(category, 1.0)
	price *= econ_modifier
	
	# 2. Faction market profile modifier
	var faction_modifier = 1.0
	if is_buying:
		faction_modifier = market.market_profile.get("buy_price_factor", 1.0)
	else:
		faction_modifier = market.market_profile.get("sell_price_factor", 0.9)
	price *= faction_modifier
	
	# 3. Supply/demand modifier
	var commodity_state = market.inventory.get(commodity_id)
	if commodity_state != null:
		var supply_demand_mod = commodity_state.demand_level / max(commodity_state.supply_level, 0.1)
		supply_demand_mod = clampf(supply_demand_mod, MIN_PRICE_MODIFIER, MAX_PRICE_MODIFIER)
		price *= supply_demand_mod
	
	# 4. Rarity modifier
	var rarity_mod = _get_rarity_modifier(commodity.get("rarity", "common"))
	price *= rarity_mod
	
	# 5. Legality modifier (illegal goods cost more)
	if commodity.get("legality") in ["illegal", "restricted"]:
		var illegal_mod = _get_illegal_price_modifier(market, commodity)
		price *= illegal_mod
	
	# 6. Quantity modifier (bulk discounts/premiums)
	var quantity_mod = _calculate_quantity_modifier(quantity, is_buying)
	price *= quantity_mod
	
	# 7. Random variance (±5%)
	var variance = randf_range(PRICE_VARIANCE_MIN, PRICE_VARIANCE_MAX)
	price *= variance
	
	# 8. Apply tax if player is buying
	if is_buying:
		var tax_rate = market.market_profile.get("tax_rate", 0.0)
		price *= (1.0 + tax_rate)
	
	return floor(price)  # Round down to nearest credit

## Get rarity price modifier
func _get_rarity_modifier(rarity: String) -> float:
	match rarity:
		"common": return 1.0
		"uncommon": return 1.2
		"rare": return 1.5
		"very_rare": return 2.0
		"legendary": return 3.0
		_: return 1.0

## Get illegal goods price modifier
func _get_illegal_price_modifier(market: MarketLocation, commodity: Dictionary) -> float:
	if commodity.get("legality") == "legal":
		return 1.0
	
	var base_multiplier = 1.5 if commodity.get("legality") == "restricted" else 2.0
	var tolerance = market.market_profile.get("illegal_tolerance", 0.1)
	
	# Lower tolerance = higher prices (more risk premium)
	var risk_premium = 1.0 + (1.0 - tolerance)
	
	return base_multiplier * risk_premium

## Calculate quantity-based price modifier
func _calculate_quantity_modifier(quantity: int, is_buying: bool) -> float:
	if quantity <= 5:
		return 1.0
	
	# Bulk purchases get small discount, bulk sales get small premium
	var discount_rate = 0.02  # 2% per 10 units
	var max_discount = 0.15   # Max 15% discount/premium
	
	var modifier = 1.0 + (discount_rate * floor(quantity / 10.0))
	modifier = clampf(modifier, 1.0 - max_discount, 1.0 + max_discount)
	
	if is_buying:
		modifier = 2.0 - modifier  # Invert for buyer (discount becomes premium)
	
	return modifier

#endregion

#region Transaction Processing

## Execute a trade transaction
## Returns: { success: bool, total_cost: float, message: String, [error: String] }
func execute_trade(
	market_id: String,
	player_id: String,
	commodity_id: String,
	quantity: int,
	is_player_buying: bool
) -> Dictionary:
	
	var market = get_market(market_id)
	if market == null:
		return {
			"success": false,
			"error": "no_market",
			"message": "No market exists at this station."
		}
	
	var commodity = commodity_database.get(commodity_id)
	if commodity == null:
		return {
			"success": false,
			"error": "unknown_commodity",
			"message": "Unknown commodity: %s" % commodity_id
		}
	
	# Execute transaction through market
	var result: Dictionary
	if is_player_buying:
		result = market.sell_to_player(commodity_id, quantity, self)
	else:
		result = market.buy_from_player(commodity_id, quantity, self)
	
	# If successful, emit trade event
	if result.get("success", false):
		EventBus.credits_changed.emit(result.get("player_credits", 0))
		
		# TODO: Add trade_completed signal to EventBus and uncomment
		# EventBus.trade_completed.emit({
		# 	"station_id": station_id,
		# 	"player_id": player_id,
		# 	"commodity_id": commodity_id,
		# 	"quantity": quantity,
		# 	"total_value": result.get("total_cost", 0),
		# 	"is_buy": is_player_buying
		# })
		
		# Update prices at this station
		update_market_prices(market_id)
	
	return result

#endregion

#region Supply & Demand Updates

## Apply a supply event (e.g., convoy arrival, production)
func apply_supply_event(market_id: String, commodity_id: String, quantity: int) -> void:
	var market = get_market(market_id)
	if market == null:
		return
	
	market.add_commodity(commodity_id, quantity)
	
	# Increase supply level
	var supply_increase = _calculate_supply_change(quantity, market)
	market.update_supply_level(commodity_id, supply_increase)
	
	update_market_prices(market_id)

## Apply a demand event (e.g., consumption, manufacturing needs)
func apply_demand_event(market_id: String, commodity_id: String, quantity: int) -> void:
	var market = get_market(market_id)
	if market == null:
		return
	
	# Try to remove from inventory (consumption)
	if market.has_sufficient_stock(commodity_id, quantity):
		market.remove_commodity(commodity_id, quantity)
		market.update_demand_level(commodity_id, -0.05)  # Demand met
	else:
		# Shortage increases demand
		market.update_demand_level(commodity_id, 0.15)
		
		# TODO: Add commodity_shortage signal to EventBus and uncomment
		# EventBus.commodity_shortage.emit(station_id, commodity_id, 0.5)
	
	update_market_prices(market_id)

## Calculate supply level change from quantity
func _calculate_supply_change(quantity: int, market: MarketLocation) -> float:
	# Larger quantities have bigger impact
	var base_change = 0.1
	var quantity_factor = min(1.0, quantity / 100.0)
	return base_change * (1.0 + quantity_factor)

#endregion

#region Price Updates

## Update prices at a specific market
func update_market_prices(market_id: String) -> void:
	var market = get_market(market_id)
	if market == null:
		return
	
	var price_changes = {}
	
	for commodity_id in market.inventory.keys():
		var old_price = market.inventory[commodity_id].current_price
		
		# Recalculate price
		var new_price = calculate_price(commodity_id, market_id, true, 1)
		market.inventory[commodity_id].current_price = new_price
		
		# Track significant changes
		if abs(new_price - old_price) > 1.0:
			price_changes[commodity_id] = {
				"old": old_price,
				"new": new_price,
				"change_percent": (new_price - old_price) / old_price * 100.0
			}
		
		# Update price history
		market.inventory[commodity_id].price_history.append(new_price)
		if market.inventory[commodity_id].price_history.size() > 100:
			market.inventory[commodity_id].price_history.pop_front()
	
	# TODO: Add market_prices_updated signal to EventBus and uncomment
	# if not price_changes.is_empty():
	# 	EventBus.market_prices_updated.emit(station_id, price_changes)

## Update all station prices (called periodically)
func update_all_prices() -> void:
	for market_id in market_locations.keys():
		update_market_prices(market_id)

## Decay supply/demand toward baseline across all markets
func decay_all_supply_demand() -> void:
	var decay_rate = 0.05  # 5% per update
	
	for market in market_locations.values():
		market.decay_supply_demand(decay_rate)

#endregion

#region Periodic Updates

## Call this from your game time system when game tick increments
func on_game_tick(new_tick: int) -> void:
	game_tick = new_tick
	
	# Price updates every 4 game hours
	if game_tick - last_price_update >= PRICE_UPDATE_INTERVAL:
		update_all_prices()
		last_price_update = game_tick
	
	# Supply/demand decay every hour
	if game_tick - last_supply_demand_decay >= SUPPLY_DEMAND_DECAY_INTERVAL:
		decay_all_supply_demand()
		last_supply_demand_decay = game_tick

#endregion

#region Query Methods

## Get commodity data by ID
func get_commodity_data(commodity_id: String) -> Dictionary:
	return commodity_database.get(commodity_id, {})

## Get all commodities
func get_all_commodities() -> Array:
	return commodity_database.values()

## Get commodities by category
func get_commodities_by_category(category: String) -> Array:
	var result = []
	for commodity in commodity_database.values():
		if commodity.get("category") == category:
			result.append(commodity)
	return result

## Check if commodity is illegal
func is_commodity_illegal(commodity_id: String) -> bool:
	var commodity = commodity_database.get(commodity_id)
	if commodity == null:
		return false
	return commodity.get("legality") == "illegal"

## Check if commodity is restricted
func is_commodity_restricted(commodity_id: String) -> bool:
	var commodity = commodity_database.get(commodity_id)
	if commodity == null:
		return false
	return commodity.get("legality") in ["illegal", "restricted"]

## Get economic profile by ID
func get_econ_profile(profile_id: String) -> Dictionary:
	return econ_profiles.get(profile_id, {})

## Get faction market profile by faction ID
func get_faction_market_profile(faction_id: String) -> Dictionary:
	return faction_market_profiles.get(faction_id, {})

#endregion

#region Save/Load

## Save economy state to dictionary
func save_economy_state() -> Dictionary:
	var state = {
		"game_tick": game_tick,
		"last_price_update": last_price_update,
		"last_supply_demand_decay": last_supply_demand_decay,
		"market_locations": {}
	}
	
	# Save each market's state
	for market_id in market_locations.keys():
		state.market_locations[market_id] = market_locations[market_id].get_market_state()
	
	return state

## Load economy state from dictionary
func load_economy_state(state: Dictionary) -> void:
	game_tick = state.get("game_tick", 0)
	last_price_update = state.get("last_price_update", 0)
	last_supply_demand_decay = state.get("last_supply_demand_decay", 0)
	
	# Load markets (support both old "station_markets" and new "market_locations" keys)
	var markets_data = state.get("market_locations", state.get("station_markets", {}))
	for market_id in markets_data.keys():
		var market_data = markets_data[market_id]
		
		# Create or get existing market
		var market = market_locations.get(market_id)
		if market == null:
			market = MarketLocation.new()
			market_locations[market_id] = market
		
		# Load market state
		market.set_market_state(market_data)
	
	print("[EconomyManager] Loaded economy state: %d markets, tick %d" % [
		market_locations.size(), game_tick
	])

#endregion
