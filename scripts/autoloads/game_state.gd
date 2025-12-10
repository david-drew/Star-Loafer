extends Node

# Galaxy Data
var galaxy_seed: int = 0
var galaxy_size: String = "medium"
var galaxy_data: Dictionary = {}  # Full generated galaxy structure
var current_system_id: String = ""
var current_sector: Vector2i = Vector2i.ZERO

# Fog of War
var fog_data: Dictionary = {
	"galaxy": [],      # ["sys:00123", "sys:00456"]
	"systems": {},     # {"sys:00123": ["body:1", "station:gate"]}
	"sectors": {}      # {"sys:00123": [[0,1], [1,2]]}
}

# Player State
var credits: int = 1000
var reputation: Dictionary = {}  # {"faction_id": reputation_value}
var active_contracts: Array = []
var completed_missions: Array = []

# Ship State (Phase 0 basics)
var ship_id: String = "starter_frigate"
var ship_position: Vector2 = Vector2.ZERO
var ship_velocity: Vector2 = Vector2.ZERO
var ship_hull: float = 100.0
var ship_hull_max: float = 100.0
var ship_fuel: float = 100.0
var ship_fuel_max: float = 100.0
var ship_cargo: Array = []

# Travel State
var in_transit: bool = false
var transit_from: String = ""
var transit_to: String = ""
var transit_progress: float = 0.0
var transit_duration: float = 0.0

# Autopilot
var autopilot_enabled: bool = false
var time_compression: int = 1  # 1, 2, or 4

var AU_TO_PIXELS = 3

func _ready() -> void:
	pass

func mark_discovered(scope: String, id: String) -> void:
	match scope:
		"galaxy":
			if id not in fog_data.galaxy:
				fog_data.galaxy.append(id)
				EventBus.location_discovered.emit(scope, id)
		"system":
			if current_system_id not in fog_data.systems:
				fog_data.systems[current_system_id] = []
			if id not in fog_data.systems[current_system_id]:
				fog_data.systems[current_system_id].append(id)
				EventBus.location_discovered.emit(scope, id)
		"sector":
			if current_system_id not in fog_data.sectors:
				fog_data.sectors[current_system_id] = []
			if id not in fog_data.sectors[current_system_id]:
				fog_data.sectors[current_system_id].append(id)
				EventBus.location_discovered.emit(scope, id)

func is_discovered(scope: String, id: String) -> bool:
	match scope:
		"galaxy":
			return id in fog_data.galaxy
		"system":
			return current_system_id in fog_data.systems and \
				   id in fog_data.systems[current_system_id]
		"sector":
			return current_system_id in fog_data.sectors and \
				   id in fog_data.sectors[current_system_id]
	return false

func add_credits(amount: int) -> void:
	credits += amount
	EventBus.credits_changed.emit(credits)

func spend_credits(amount: int) -> bool:
	if credits >= amount:
		credits -= amount
		EventBus.credits_changed.emit(credits)
		return true
	return false

func get_state() -> Dictionary:
	return {
		"galaxy_seed": galaxy_seed,
		"galaxy_size": galaxy_size,
		"current_system_id": current_system_id,
		"current_sector": [current_sector.x, current_sector.y],
		"fog_data": fog_data,
		"credits": credits,
		"reputation": reputation,
		"ship_position": [ship_position.x, ship_position.y],
		"ship_hull": ship_hull,
		"ship_fuel": ship_fuel,
		"autopilot_enabled": autopilot_enabled,
		"time_compression": time_compression
	}

func set_state(state: Dictionary) -> void:
	galaxy_seed = state.get("galaxy_seed", 0)
	galaxy_size = state.get("galaxy_size", "medium")
	current_system_id = state.get("current_system_id", "")
	var sector_array = state.get("current_sector", [0, 0])
	current_sector = Vector2i(sector_array[0], sector_array[1])
	fog_data = state.get("fog_data", {"galaxy": [], "systems": {}, "sectors": {}})
	credits = state.get("credits", 1000)
	reputation = state.get("reputation", {})
	var pos_array = state.get("ship_position", [0.0, 0.0])
	ship_position = Vector2(pos_array[0], pos_array[1])
	ship_hull = state.get("ship_hull", 100.0)
	ship_fuel = state.get("ship_fuel", 100.0)
	autopilot_enabled = state.get("autopilot_enabled", false)
	time_compression = state.get("time_compression", 1)
