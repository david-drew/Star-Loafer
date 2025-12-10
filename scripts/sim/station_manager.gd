# Create: res://economy/StationConsumption.gd
# Or add to your existing StationManager.gd

extends Node

func simulate_consumption_for_all_stations() -> void:
	for station in get_all_stations():
		simulate_station_consumption(station.id)

func simulate_station_consumption(station_id: String) -> void:
	var station = get_station_by_id(station_id)
	var population = station.population_level
	
	# Food consumption (example: 2 units per population level)
	var food_needed = population * 2
	EconomyManager.apply_demand_event(station_id, "food_basic", food_needed)
	
	# Fuel consumption
	var fuel_needed = population * 1
	EconomyManager.apply_demand_event(station_id, "fuel", fuel_needed)
	
	# Medical supplies
	var meds_needed = population * 1
	EconomyManager.apply_demand_event(station_id, "medkits", meds_needed)

# Call this periodically from your game time manager
func _on_game_time_advanced() -> void:
	# Every game day, simulate consumption
	simulate_consumption_for_all_stations()

func get_all_stations():
	print("WARN: StationManager:get_all_stations() not implemented.")
	
func get_station_by_id(station_id):
	print("WARN: StationManager:get_station_by_id() not implemented.")
	
