# res://autoload/EconomySimulator.gd
extends Node

# =============================================================================
# EconomySimulator - Production, Consumption, and Economic Simulation
# =============================================================================
# Handles the background economic simulation for all markets in the galaxy.
# Produces goods, consumes resources, and triggers market events.
#
# Integration:
# - Connects to TimeManager for regular sim ticks
# - Uses EconomyManager for all market data and transactions  
# - Emits signals via EventBus for shortages, surpluses, crises
# =============================================================================

# Configuration constants
const SIM_CONFIG_PATH: String = "res://data/sim/economy_sim_config.json"

# Simulation settings (can be overridden by config)
var production_multiplier: float = 1.0
var consumption_multiplier: float = 1.0
var enable_random_events: bool = true
var event_chance_per_tick: float = 0.05  # 5% chance per tick

# Production/consumption rates by economy profile
var _profile_production: Dictionary = {}
var _profile_consumption: Dictionary = {}

# Random event definitions
var _random_events: Array = []

# State tracking
var _initialized: bool = false
var _last_tick_processed: int = -1

# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	_load_simulation_config()
	_setup_default_profiles()
	_setup_default_events()
	
	# Connect to TimeManager's sim tick signal
	if EventBus.has_signal("time_sim_tick"):
		EventBus.time_sim_tick.connect(_on_time_sim_tick)
	else:
		push_warning("EconomySimulator: EventBus doesn't have 'time_sim_tick' signal!")
	
	_initialized = true
	print("[EconomySimulator] Initialized and connected to TimeManager")


# =============================================================================
# Configuration Loading
# =============================================================================

func _load_simulation_config() -> void:
	if not FileAccess.file_exists(SIM_CONFIG_PATH):
		print("[EconomySimulator] No config file found at %s, using defaults" % SIM_CONFIG_PATH)
		return
	
	var file := FileAccess.open(SIM_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("[EconomySimulator] Failed to open config file")
		return
	
	var text := file.get_as_text()
	file.close()
	
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[EconomySimulator] Failed to parse config JSON")
		return
	
	var config: Dictionary = data
	
	# Load multipliers
	if config.has("production_multiplier"):
		production_multiplier = float(config["production_multiplier"])
	if config.has("consumption_multiplier"):
		consumption_multiplier = float(config["consumption_multiplier"])
	
	# Load event settings
	if config.has("enable_random_events"):
		enable_random_events = bool(config["enable_random_events"])
	if config.has("event_chance_per_tick"):
		event_chance_per_tick = float(config["event_chance_per_tick"])
	
	# Load production profiles
	if config.has("production_profiles"):
		_profile_production = config["production_profiles"].duplicate(true)
	
	# Load consumption profiles
	if config.has("consumption_profiles"):
		_profile_consumption = config["consumption_profiles"].duplicate(true)
	
	# Load random events
	if config.has("random_events"):
		_random_events = config["random_events"].duplicate(true)
	
	print("[EconomySimulator] Loaded config from %s" % SIM_CONFIG_PATH)


func _setup_default_profiles() -> void:
	# Only set defaults if not loaded from config
	if _profile_production.is_empty():
		_profile_production = {
			"mining": {
				"ore_iron": 50.0,
				"ore_titanium": 25.0,
				"ore_copper": 30.0,
				"ore_rare": 5.0
			},
			"agricultural": {
				"food_basic": 100.0,
				"grain_bulk": 60.0,
				"water": 80.0
			},
			"industrial": {
				"components_basic": 40.0,
				"microchips": 30.0,
				"alloys": 35.0
			},
			"high_tech": {
				"microchips": 60.0,
				"components_advanced": 25.0,
				"nanotech": 10.0
			},
			"refining": {
				"alloys": 50.0,
				"fuel_deuterium": 40.0,
				"chemicals": 30.0
			}
		}
	
	if _profile_consumption.is_empty():
		_profile_consumption = {
			"mining": {
				"food_basic": 30.0,
				"water": 25.0,
				"components_basic": 15.0
			},
			"agricultural": {
				"food_basic": 10.0,  # They produce it, but still need some
				"water": 15.0,
				"components_basic": 20.0
			},
			"industrial": {
				"food_basic": 25.0,
				"water": 20.0,
				"ore_iron": 30.0,
				"ore_copper": 15.0
			},
			"high_tech": {
				"food_basic": 20.0,
				"water": 18.0,
				"components_basic": 25.0,
				"alloys": 20.0
			},
			"refining": {
				"food_basic": 20.0,
				"water": 20.0,
				"ore_iron": 40.0,
				"ore_titanium": 20.0
			}
		}


func _setup_default_events() -> void:
	# Only set defaults if not loaded from config
	if _random_events.is_empty():
		_random_events = [
			{
				"id": "bountiful_harvest",
				"weight": 10,
				"profiles": ["agricultural"],
				"effects": {
					"food_basic": {"type": "supply", "amount": 500},
					"grain_bulk": {"type": "supply", "amount": 300}
				},
				"message": "Bountiful harvest increases food production"
			},
			{
				"id": "mining_accident",
				"weight": 5,
				"profiles": ["mining"],
				"effects": {
					"ore_iron": {"type": "demand", "amount": -200},
					"ore_titanium": {"type": "demand", "amount": -100}
				},
				"message": "Mining accident reduces ore output"
			},
			{
				"id": "equipment_shortage",
				"weight": 8,
				"profiles": ["industrial", "high_tech"],
				"effects": {
					"components_basic": {"type": "demand", "amount": 300},
					"microchips": {"type": "demand", "amount": 200}
				},
				"message": "Equipment shortage increases demand for components"
			},
			{
				"id": "refinery_breakthrough",
				"weight": 3,
				"profiles": ["refining"],
				"effects": {
					"alloys": {"type": "supply", "amount": 400},
					"fuel_deuterium": {"type": "supply", "amount": 300}
				},
				"message": "Refinery breakthrough boosts production"
			}
		]


# =============================================================================
# TimeManager Integration
# =============================================================================

func _on_time_sim_tick(hours_elapsed: float, ticks: int) -> void:
	if not _initialized:
		return
	
	# Process multiple ticks if time jumped significantly
	for i in range(ticks):
		_process_single_tick()


func _process_single_tick() -> void:
	# Core simulation loop
	simulate_all_production()
	simulate_all_consumption()
	
	# Random economic events
	if enable_random_events:
		_try_trigger_random_event()


# =============================================================================
# Production Simulation
# =============================================================================

func simulate_all_production() -> void:
	# Get all markets from EconomyManager
	var all_market_ids := EconomyManager.get_all_markets()
	
	for market_id in all_market_ids:
		var market = EconomyManager.get_market(market_id)
		if market == null:
			continue
		
		# Calculate production for this market
		var production := _calculate_production(market)
		
		# Apply production to market
		for commodity_id in production:
			var amount: float = production[commodity_id]
			if amount > 0:
				EconomyManager.apply_supply_event(
					market_id,
					commodity_id,
					int(amount)
				)


func _calculate_production(market) -> Dictionary:
	var output := {}
	
	# Get the economy profile for this market
	var profile_id: String = market.econ_profile_id if market.has("econ_profile_id") else ""
	if profile_id.is_empty():
		return output
	
	# Check if we have production data for this profile
	if not _profile_production.has(profile_id):
		return output
	
	var profile_data: Dictionary = _profile_production[profile_id]
	
	# Get population and tech level
	var pop_level: int = market.population_level if market.has("population_level") else 1
	var tech_level: int = market.tech_level if market.has("tech_level") else 1
	
	# Calculate base production for each commodity
	for commodity_id in profile_data:
		var base_rate: float = float(profile_data[commodity_id])
		
		# Apply population scaling (more population = more production)
		var pop_multiplier: float = sqrt(float(pop_level))
		
		# Apply tech level bonus (better tech = more efficient)
		var tech_multiplier: float = 1.0 + (float(tech_level) * 0.1)
		
		# Final production amount
		var production: float = base_rate * pop_multiplier * tech_multiplier * production_multiplier
		
		output[commodity_id] = production
	
	return output


# =============================================================================
# Consumption Simulation
# =============================================================================

func simulate_all_consumption() -> void:
	var all_market_ids := EconomyManager.get_all_markets()
	
	for market_id in all_market_ids:
		var market = EconomyManager.get_market(market_id)
		if market == null:
			continue
		
		# Calculate consumption for this market
		var consumption := _calculate_consumption(market)
		
		# Apply consumption to market
		for commodity_id in consumption:
			var amount: float = consumption[commodity_id]
			if amount > 0:
				EconomyManager.apply_demand_event(
					market_id,
					commodity_id,
					int(amount)
				)


func _calculate_consumption(market) -> Dictionary:
	var needs := {}
	
	# Get the economy profile for this market
	var profile_id: String = market.econ_profile_id if market.has("econ_profile_id") else ""
	var pop_level: int = market.population_level if market.has("population_level") else 1
	
	if profile_id.is_empty():
		# Default consumption for any populated location
		needs["food_basic"] = 15.0 * float(pop_level)
		needs["water"] = 12.0 * float(pop_level)
		return needs
	
	# Use profile-specific consumption if available
	if not _profile_consumption.has(profile_id):
		# Fallback to basics
		needs["food_basic"] = 15.0 * float(pop_level)
		needs["water"] = 12.0 * float(pop_level)
		return needs
	
	var profile_data: Dictionary = _profile_consumption[profile_id]
	
	# Calculate consumption for each commodity
	for commodity_id in profile_data:
		var base_rate: float = float(profile_data[commodity_id])
		
		# Population scaling (more people = more consumption)
		var pop_multiplier: float = float(pop_level)
		
		# Final consumption amount
		var consumption: float = base_rate * pop_multiplier * consumption_multiplier
		
		needs[commodity_id] = consumption
	
	return needs


# =============================================================================
# Random Economic Events
# =============================================================================

func _try_trigger_random_event() -> void:
	# Roll for event chance
	if randf() > event_chance_per_tick:
		return
	
	# Pick a random event from weighted list
	var event := _select_random_event()
	if event.is_empty():
		return
	
	# Find markets that match the event's profile requirements
	var eligible_markets := _find_eligible_markets(event)
	if eligible_markets.is_empty():
		return
	
	# Pick a random eligible market
	var target_market: String = eligible_markets[randi() % eligible_markets.size()]
	
	# Apply the event
	_apply_random_event(event, target_market)


func _select_random_event() -> Dictionary:
	if _random_events.is_empty():
		return {}
	
	# Calculate total weight
	var total_weight: float = 0.0
	for event in _random_events:
		total_weight += float(event.get("weight", 1))
	
	# Select based on weight
	var roll: float = randf() * total_weight
	var current_weight: float = 0.0
	
	for event in _random_events:
		current_weight += float(event.get("weight", 1))
		if roll <= current_weight:
			return event
	
	# Fallback to first event
	return _random_events[0]


func _find_eligible_markets(event: Dictionary) -> Array:
	var eligible := []
	var required_profiles: Array = event.get("profiles", [])
	
	if required_profiles.is_empty():
		return eligible
	
	var all_market_ids := EconomyManager.get_all_markets()
	
	for market_id in all_market_ids:
		var market = EconomyManager.get_market(market_id)
		if market == null:
			continue
		
		var profile_id: String = market.econ_profile_id if market.has("econ_profile_id") else ""
		if profile_id in required_profiles:
			eligible.append(market_id)
	
	return eligible


func _apply_random_event(event: Dictionary, market_id: String) -> void:
	var event_id: String = event.get("id", "unknown")
	var effects: Dictionary = event.get("effects", {})
	var message: String = event.get("message", "Economic event occurred")
	
	print("[EconomySimulator] Event '%s' triggered at %s: %s" % [event_id, market_id, message])
	
	# Apply each effect
	for commodity_id in effects:
		var effect: Dictionary = effects[commodity_id]
		var effect_type: String = effect.get("type", "supply")
		var amount: int = int(effect.get("amount", 0))
		
		if effect_type == "supply":
			EconomyManager.apply_supply_event(market_id, commodity_id, amount)
		elif effect_type == "demand":
			EconomyManager.apply_demand_event(market_id, commodity_id, amount)
	
	# Emit event notification (could be used by UI)
	# EventBus could have a signal like: economic_event_occurred(event_id, market_id, message)


# =============================================================================
# Public API
# =============================================================================

func get_production_rate(market_id: String, commodity_id: String) -> float:
	"""Get the current production rate for a commodity at a market"""
	var market = EconomyManager.get_market(market_id)
	if market == null:
		return 0.0
	
	var production := _calculate_production(market)
	return production.get(commodity_id, 0.0)


func get_consumption_rate(market_id: String, commodity_id: String) -> float:
	"""Get the current consumption rate for a commodity at a market"""
	var market = EconomyManager.get_market(market_id)
	if market == null:
		return 0.0
	
	var consumption := _calculate_consumption(market)
	return consumption.get(commodity_id, 0.0)


func get_net_rate(market_id: String, commodity_id: String) -> float:
	"""Get the net rate (production - consumption) for a commodity"""
	var production := get_production_rate(market_id, commodity_id)
	var consumption := get_consumption_rate(market_id, commodity_id)
	return production - consumption


func force_event(event_id: String, market_id: String) -> bool:
	"""Manually trigger a specific event at a market (for testing/scripted events)"""
	for event in _random_events:
		if event.get("id", "") == event_id:
			_apply_random_event(event, market_id)
			return true
	
	push_warning("[EconomySimulator] Event '%s' not found" % event_id)
	return false


# =============================================================================
# Serialization (for SaveSystem)
# =============================================================================

func serialize_state() -> Dictionary:
	return {
		"last_tick_processed": _last_tick_processed,
		"production_multiplier": production_multiplier,
		"consumption_multiplier": consumption_multiplier,
		"enable_random_events": enable_random_events
	}


func restore_state(state: Dictionary) -> void:
	if state.has("last_tick_processed"):
		_last_tick_processed = int(state["last_tick_processed"])
	if state.has("production_multiplier"):
		production_multiplier = float(state["production_multiplier"])
	if state.has("consumption_multiplier"):
		consumption_multiplier = float(state["consumption_multiplier"])
	if state.has("enable_random_events"):
		enable_random_events = bool(state["enable_random_events"])
