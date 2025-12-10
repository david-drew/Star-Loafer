# MarketLocation.gd (renamed from StationMarket.gd)
## Represents an individual planet/moon/station's market with inventory and pricing
##
## Responsibilities:
## - Maintain commodity inventory with quantities
## - Track supply/demand levels per commodity
## - Process buy/sell transactions
## - Apply faction-specific market rules
## - Generate and refresh inventory
##
## Usage: Created and managed by EconomyManager

extends RefCounted
class_name MarketLocation

enum LocationType { STATION, PLANET, MOON }

## Market identity
var location_id: String
var location_type: LocationType = LocationType.STATION
var faction_id: String
var econ_profile_id: String
var population_level: int = 0  # NEW: Track population tier

var market_profile: Dictionary = {}

## Inventory: commodity_id -> CommodityState
var inventory: Dictionary = {}

## Recent activity tracking
var recent_trades: Array[Dictionary] = []
var last_restock_tick: int = 0

## Modifiers (for temporary events)
var temporary_modifiers: Dictionary = {}  # commodity_id -> {modifier: float, expires: int}


## CommodityState inner class for tracking per-commodity data
class CommodityState:
	var commodity_id: String
	var quantity: int = 0
	var current_price: float = 0.0
	var base_price: float = 0.0
	
	# Supply/demand tracking
	var supply_level: float = 1.0  # 0.0 = empty, 1.0 = normal, 2.0 = oversupplied
	var demand_level: float = 1.0  # 0.0 = no demand, 1.0 = normal, 2.0 = critical need
	
	# Historical data
	var price_history: Array[float] = []
	var last_price_update: int = 0
	
	func _init(p_commodity_id: String = "", p_base_price: float = 0.0) -> void:
		commodity_id = p_commodity_id
		base_price = p_base_price
		current_price = p_base_price

# Region Initialization

## Initialize the market with basic parameters
func initialize(
	p_station_id: String,
	p_faction_id: String,
	p_econ_profile_id: String,
	p_market_profile: Dictionary
) -> void:
	location_id = p_station_id
	faction_id = p_faction_id
	econ_profile_id = p_econ_profile_id
	market_profile = p_market_profile

## Generate initial inventory based on profiles
func generate_initial_inventory(
	commodity_database: Dictionary,
	econ_profile: Dictionary
) -> void:
	
	for commodity_id in commodity_database.keys():
		var commodity = commodity_database[commodity_id]
		
		# Determine if station stocks this commodity
		if should_stock_commodity(commodity, econ_profile):
			# Calculate initial quantity
			var quantity = calculate_initial_quantity(commodity)
			
			# Create commodity state
			var state = CommodityState.new(commodity_id, commodity.base_price)
			state.quantity = quantity
			state.current_price = commodity.base_price  # Will be recalculated by EconomyManager
			state.supply_level = 1.0
			state.demand_level = 1.0
			
			inventory[commodity_id] = state

## Determine if station should stock a commodity
func should_stock_commodity(commodity: Dictionary, econ_profile: Dictionary) -> bool:
	# Illegal goods only in criminal faction space
	if commodity.get("legality") == "illegal":
		var illegal_tolerance = market_profile.get("illegal_tolerance", 0.1)
		return illegal_tolerance > 0.5 or randf() < 0.05
	
	# Restricted goods rare in high-law areas
	if commodity.get("legality") == "restricted":
		var illegal_tolerance = market_profile.get("illegal_tolerance", 0.1)
		if illegal_tolerance < 0.2:
			return randf() < 0.3
	
	# Check rarity
	var rarity_chance = _get_rarity_stock_chance(commodity.get("rarity", "common"))
	if randf() > rarity_chance:
		return false
	
	# Check category relevance to station
	var category = commodity.get("category", "")
	var category_modifiers = econ_profile.get("category_modifiers", {})
	var modifier = category_modifiers.get(category, 1.0)
	
	# Higher modifier = more likely to stock
	var stock_chance = 0.5 + (modifier - 1.0) * 0.3
	
	return randf() < stock_chance

## Get rarity-based stocking chance
func _get_rarity_stock_chance(rarity: String) -> float:
	match rarity:
		"common": return 1.0
		"uncommon": return 0.8
		"rare": return 0.4
		"very_rare": return 0.1
		"legendary": return 0.02
		_: return 0.5

## Calculate initial commodity quantity
func calculate_initial_quantity(commodity: Dictionary) -> int:
	var base_quantity = 100
	
	# Adjust by rarity
	match commodity.get("rarity", "common"):
		"common": base_quantity = 200
		"uncommon": base_quantity = 100
		"rare": base_quantity = 30
		"very_rare": base_quantity = 10
		"legendary": base_quantity = 1
	
	# Add some variance
	var variance = randf_range(0.7, 1.3)
	
	return max(1, int(base_quantity * variance))

#endregion

#region Price Queries

## Get price player pays when buying FROM station
func get_buy_price(commodity_id: String, quantity: int = 1) -> float:
	var state = inventory.get(commodity_id)
	if state == null:
		push_warning("[LocationMarket] %s: Commodity not in inventory: %s" % [location_id, commodity_id])
		return 0.0
	
	# Price is calculated by EconomyManager, but we return the current price
	# Note: EconomyManager.calculate_price() should be used for accurate pricing
	return state.current_price

## Get price station pays when buying FROM player
func get_sell_price(commodity_id: String, quantity: int = 1) -> float:
	var state = inventory.get(commodity_id)
	if state == null:
		# Station might buy commodities it doesn't stock
		# Return 0 for now, EconomyManager will handle this
		return 0.0
	
	# Station pays less than sell price (typically 90-95% of buy price)
	# This is handled in EconomyManager.calculate_price() with sell_price_factor
	return state.current_price

#endregion

#region Transaction Processing

## Player sells commodity TO station (station buys FROM player)
func buy_from_player(
	commodity_id: String,
	quantity: int,
	economy_manager: Node
) -> Dictionary:
	
	# Check if commodity exists in our inventory (or can be accepted)
	var state = inventory.get(commodity_id)
	
	# Calculate payment
	var unit_price = economy_manager.calculate_price(commodity_id, location_id, false, 1)
	var total_payment = unit_price * quantity
	
	# Add to inventory
	add_commodity(commodity_id, quantity)
	
	# Update supply/demand
	var supply_increase = min(0.3, quantity * 0.01)
	update_supply_level(commodity_id, supply_increase)
	
	# Record trade
	_record_trade(commodity_id, quantity, total_payment, false)
	
	return {
		"success": true,
		"total_payment": total_payment,
		"unit_price": unit_price,
		"message": "Sold %d %s for %d credits." % [quantity, commodity_id, total_payment],
		"player_credits": 0  # EconomyManager will update player credits
	}

## Station sells commodity TO player (player buys FROM station)
func sell_to_player(
	commodity_id: String,
	quantity: int,
	economy_manager: Node
) -> Dictionary:
	
	# Check if station has stock
	if not has_sufficient_stock(commodity_id, quantity):
		return {
			"success": false,
			"error": "insufficient_stock",
			"message": "Station doesn't have enough %s in stock." % commodity_id
		}
	
	# Calculate cost
	var unit_price = economy_manager.calculate_price(commodity_id, location_id, true, 1)
	var total_cost = unit_price * quantity
	
	# Check for illegal trade detection
	var commodity = economy_manager.get_commodity_data(commodity_id)
	if commodity.get("legality") in ["illegal", "restricted"]:
		var detected = check_illegal_trade_detection(commodity_id, quantity)
		if detected:
			return _handle_illegal_detection(commodity_id, quantity, total_cost, commodity)
	
	# Remove from inventory
	remove_commodity(commodity_id, quantity)
	
	# Update supply/demand
	var supply_decrease = min(0.3, quantity * 0.01)
	update_supply_level(commodity_id, -supply_decrease)
	var demand_increase = min(0.3, quantity * 0.01)
	update_demand_level(commodity_id, demand_increase)
	
	# Record trade
	_record_trade(commodity_id, quantity, total_cost, true)
	
	return {
		"success": true,
		"total_cost": total_cost,
		"unit_price": unit_price,
		"message": "Purchased %d %s for %d credits." % [quantity, commodity_id, total_cost],
		"player_credits": 0  # EconomyManager will update player credits
	}

## Record a trade for analytics
func _record_trade(commodity_id: String, quantity: int, value: float, is_buy: bool) -> void:
	recent_trades.append({
		"commodity_id": commodity_id,
		"quantity": quantity,
		"value": value,
		"is_buy": is_buy,
		"timestamp": Time.get_ticks_msec()
	})
	
	# Keep only last 50 trades
	if recent_trades.size() > 50:
		recent_trades.pop_front()

#endregion

#region Illegal Trade

## Check if illegal trade is detected
func check_illegal_trade_detection(commodity_id: String, quantity: int) -> bool:
	var tolerance = market_profile.get("illegal_tolerance", 0.1)
	
	# Base detection chance (1.0 = no tolerance, full detection)
	var base_detection = 1.0 - tolerance
	
	# Larger quantities increase risk
	var quantity_multiplier = 1.0 + (quantity * 0.02)  # +2% per unit
	
	var detection_chance = base_detection * quantity_multiplier
	detection_chance = clampf(detection_chance, 0.0, 0.95)  # Never 100%
	
	return randf() < detection_chance

## Handle illegal trade detection
func _handle_illegal_detection(
	commodity_id: String,
	quantity: int,
	cargo_value: float,
	commodity: Dictionary
) -> Dictionary:
	
	# Calculate consequences
	var fine_multiplier = 2.0 if commodity.get("legality") == "restricted" else 5.0
	var fine = int(cargo_value * fine_multiplier)
	var rep_loss = -10 if commodity.get("legality") == "restricted" else -25
	
	return {
		"success": false,
		"detected": true,
		"error": "illegal_trade_detected",
		"message": "Illegal cargo detected! Fine: %d credits. Reputation loss: %d" % [fine, rep_loss],
		"consequences": {
			"fine": fine,
			"reputation_loss": rep_loss,
			"faction": faction_id,
			"cargo_seized": true,
			"bounty_placed": cargo_value > 10000,
			"bounty_amount": int(cargo_value * 0.5) if cargo_value > 10000 else 0
		}
	}

#endregion

#region Inventory Management

## Add commodity to inventory
func add_commodity(commodity_id: String, quantity: int) -> void:
	var state = inventory.get(commodity_id)
	if state == null:
		# Create new entry (station accepting commodity it doesn't normally stock)
		state = CommodityState.new(commodity_id, 0.0)
		inventory[commodity_id] = state
	
	state.quantity += quantity

## Remove commodity from inventory
func remove_commodity(commodity_id: String, quantity: int) -> bool:
	var state = inventory.get(commodity_id)
	if state == null:
		return false
	
	if state.quantity < quantity:
		return false
	
	state.quantity -= quantity
	
	# Remove from inventory if quantity hits zero
	if state.quantity <= 0:
		inventory.erase(commodity_id)
	
	return true

## Check if station has sufficient stock
func has_sufficient_stock(commodity_id: String, quantity: int) -> bool:
	var state = inventory.get(commodity_id)
	if state == null:
		return false
	return state.quantity >= quantity

## Get commodity quantity
func get_commodity_quantity(commodity_id: String) -> int:
	var state = inventory.get(commodity_id)
	if state == null:
		return 0
	return state.quantity

## Get all available commodity IDs
func get_available_commodities() -> Array[String]:
	var result: Array[String] = []
	for commodity_id in inventory.keys():
		if inventory[commodity_id].quantity > 0:
			result.append(commodity_id)
	return result

#endregion

#region Supply & Demand

## Update supply level for a commodity
func update_supply_level(commodity_id: String, change: float) -> void:
	var state = inventory.get(commodity_id)
	if state == null:
		return
	
	state.supply_level += change
	state.supply_level = clampf(state.supply_level, 0.0, 2.0)

## Update demand level for a commodity
func update_demand_level(commodity_id: String, change: float) -> void:
	var state = inventory.get(commodity_id)
	if state == null:
		return
	
	state.demand_level += change
	state.demand_level = clampf(state.demand_level, 0.0, 2.0)

## Decay supply/demand toward baseline
func decay_supply_demand(decay_rate: float) -> void:
	for state in inventory.values():
		# Gradually return to baseline (1.0)
		state.supply_level = lerpf(state.supply_level, 1.0, decay_rate)
		state.demand_level = lerpf(state.demand_level, 1.0, decay_rate)

## Get supply/demand status as string
func get_supply_status(commodity_id: String) -> String:
	var state = inventory.get(commodity_id)
	if state == null:
		return "unknown"
	
	if state.supply_level < 0.3:
		return "critical_shortage"
	elif state.supply_level < 0.6:
		return "shortage"
	elif state.supply_level > 2.0:
		return "surplus"
	elif state.supply_level > 1.5:
		return "oversupply"
	else:
		return "normal"

func get_demand_status(commodity_id: String) -> String:
	var state = inventory.get(commodity_id)
	if state == null:
		return "unknown"
	
	if state.demand_level < 0.3:
		return "no_demand"
	elif state.demand_level < 0.7:
		return "low_demand"
	elif state.demand_level > 1.5:
		return "high_demand"
	elif state.demand_level > 1.8:
		return "critical_demand"
	else:
		return "normal"

#endregion

#region Refresh & Restock

## Refresh inventory (periodic restocking)
func refresh_inventory(game_tick: int) -> void:
	# This could be expanded to add new commodities or increase quantities
	# For now, it's a placeholder for future functionality
	last_restock_tick = game_tick

#endregion

#region State Management

## Get market state for saving
func get_market_state() -> Dictionary:
	var inventory_data = {}
	for commodity_id in inventory.keys():
		var state = inventory[commodity_id]
		inventory_data[commodity_id] = {
			"quantity": state.quantity,
			"current_price": state.current_price,
			"base_price": state.base_price,
			"supply_level": state.supply_level,
			"demand_level": state.demand_level,
			"price_history": state.price_history.duplicate()
		}
	
	return {
		"location_id": location_id,
		"faction_id": faction_id,
		"econ_profile_id": econ_profile_id,
		"market_profile": market_profile.duplicate(),
		"inventory": inventory_data,
		"last_restock_tick": last_restock_tick
	}

## Set market state from saved data
func set_market_state(state: Dictionary) -> void:
	location_id = state.get("location_id", "")
	faction_id = state.get("faction_id", "")
	econ_profile_id = state.get("econ_profile_id", "")
	market_profile = state.get("market_profile", {})
	last_restock_tick = state.get("last_restock_tick", 0)
	
	# Restore inventory
	inventory.clear()
	var inventory_data = state.get("inventory", {})
	for commodity_id in inventory_data.keys():
		var data = inventory_data[commodity_id]
		var commodity_state = CommodityState.new(commodity_id, data.get("base_price", 0.0))
		commodity_state.quantity = data.get("quantity", 0)
		commodity_state.current_price = data.get("current_price", 0.0)
		commodity_state.supply_level = data.get("supply_level", 1.0)
		commodity_state.demand_level = data.get("demand_level", 1.0)
		commodity_state.price_history = data.get("price_history", [])
		
		inventory[commodity_id] = commodity_state

#endregion
