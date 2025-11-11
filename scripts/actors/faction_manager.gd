extends Node
class_name FactionManager

# Singleton for managing faction data and relationships
# Loads faction JSON files and provides faction-related queries

# Faction data storage
var factions_core: Array = []
var faction_relations: Dictionary = {}
var faction_subfactions: Array = []
var faction_missions: Dictionary = {}
var faction_economy: Dictionary = {}

# Quick lookup tables
var faction_by_id: Dictionary = {}
var major_factions: Array = []
var minor_factions: Array = []

func _ready() -> void:
	_load_faction_data()
	_build_lookup_tables()
	print("FactionManager: Loaded %d factions" % factions_core.size())

func _load_faction_data() -> void:
	# Load core faction definitions
	var core_path = "res://data/factions/factions_core.json"
	factions_core = _load_json_file(core_path, [])
	
	# Load faction relations
	var relations_path = "res://data/factions/faction_relations.json"
	faction_relations = _load_json_file(relations_path, {})
	
	# Load subfactions
	var subfactions_path = "res://data/factions/faction_subfactions.json"
	faction_subfactions = _load_json_file(subfactions_path, [])
	
	# Load mission templates
	var missions_path = "res://data/factions/faction_mission_templates.json"
	faction_missions = _load_json_file(missions_path, {})
	
	# Load economy profiles
	var economy_path = "res://data/factions/faction_economy_profiles.json"
	faction_economy = _load_json_file(economy_path, {})

func _load_json_file(path: String, default_value) -> Variant:
	if !FileAccess.file_exists(path):
		push_warning("FactionManager: File not found: %s" % path)
		return default_value
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("FactionManager: Failed to open: %s" % path)
		return default_value
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_error("FactionManager: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return default_value
	
	return json.data

func _build_lookup_tables() -> void:
	# Build quick lookup by ID
	for faction in factions_core:
		var faction_id = faction.get("id", "")
		if faction_id != "":
			faction_by_id[faction_id] = faction
			
			# Categorize by tier
			var tier = faction.get("tier", "minor")
			if tier == "major":
				major_factions.append(faction_id)
			else:
				minor_factions.append(faction_id)

# === PUBLIC API ===

func get_faction(faction_id: String) -> Dictionary:
	"""Get complete faction data by ID"""
	return faction_by_id.get(faction_id, {})

func get_faction_name(faction_id: String) -> String:
	"""Get faction display name"""
	var faction = get_faction(faction_id)
	return faction.get("name", faction_id)

func get_faction_type(faction_id: String) -> String:
	"""Get faction type (state, corporate, cooperative, etc.)"""
	var faction = get_faction(faction_id)
	return faction.get("type", "")

func get_faction_tier(faction_id: String) -> String:
	"""Get faction tier (major/minor)"""
	var faction = get_faction(faction_id)
	return faction.get("tier", "minor")

func get_faction_ethos(faction_id: String) -> String:
	"""Get faction ethos/motto"""
	var faction = get_faction(faction_id)
	return faction.get("ethos", "")

func get_major_factions() -> Array:
	"""Get list of all major faction IDs"""
	return major_factions.duplicate()

func get_minor_factions() -> Array:
	"""Get list of all minor faction IDs"""
	return minor_factions.duplicate()

func get_relation(faction_a: String, faction_b: String) -> int:
	"""Get relationship value between two factions (-100 to 100)"""
	if faction_a == faction_b:
		return 100  # Faction always likes itself
	
	if faction_a == "" or faction_b == "" or faction_a == "independent" or faction_b == "independent":
		return 0  # Neutral
		
	# Check if relation exists
	if faction_a in faction_relations:
		return faction_relations[faction_a].get(faction_b, 0)
	
	return 0  # Neutral by default

func are_hostile(faction_a: String, faction_b: String) -> bool:
	"""Check if two factions are hostile (relation < -30)"""
	return get_relation(faction_a, faction_b) < -30

func are_friendly(faction_a: String, faction_b: String) -> bool:
	"""Check if two factions are friendly (relation > 30)"""
	return get_relation(faction_a, faction_b) > 30

func are_allied(faction_a: String, faction_b: String) -> bool:
	"""Check if two factions are allied (relation > 60)"""
	return get_relation(faction_a, faction_b) > 60

func get_system_archetype_weights(faction_id: String) -> Dictionary:
	"""Get system archetype weights for a faction"""
	var faction = get_faction(faction_id)
	var weights_ref = faction.get("default_system_archetype_weights_ref", "")
	
	if weights_ref == "":
		return {}
	
	var system_weights = faction_economy.get("system_archetype_weights", {})
	return system_weights.get(weights_ref, {})

func get_market_profile(faction_id: String) -> Dictionary:
	"""Get market profile for a faction"""
	var faction = get_faction(faction_id)
	var market_ref = faction.get("default_market_profile_ref", "")
	
	if market_ref == "":
		return {}
	
	var market_profiles = faction_economy.get("market_profiles", {})
	return market_profiles.get(market_ref, {})

func get_faction_missions(faction_id: String) -> Array:
	"""Get mission templates for a faction"""
	var faction = get_faction(faction_id)
	var missions_ref = faction.get("default_mission_templates_ref", "")
	
	if missions_ref == "":
		return []
	
	return faction_missions.get(missions_ref, [])

func select_faction_for_system(rng: RandomNumberGenerator, system_data: Dictionary) -> String:
	"""
	Select an appropriate faction for a system based on:
	- pop_level (higher = more likely major faction)
	- tech_level (higher = more corporate/imperial)
	- region (core vs rim)
	- mining_quality (attracts resource factions)
	"""
	var pop_level = system_data.get("pop_level", 5)
	var tech_level = system_data.get("tech_level", 5)
	var mining_quality = system_data.get("mining_quality", 5)
	var region_id = system_data.get("region_id", "")
	
	# Determine if this should be major or minor faction
	var use_major = pop_level >= 5 or rng.randf() < 0.7
	
	if use_major:
		return _select_major_faction(rng, pop_level, tech_level, mining_quality, region_id)
	else:
		return _select_minor_faction(rng, pop_level, tech_level, mining_quality, region_id)

func _select_major_faction(rng: RandomNumberGenerator, pop: int, tech: int, mining: int, region: String) -> String:
	"""Select a major faction with weighted probabilities"""
	var weights = {}
	
	# Imperial Meridian - likes high pop, high tech, core systems
	weights["imperial_meridian"] = 10
	if pop >= 7:
		weights["imperial_meridian"] += 15
	if tech >= 7:
		weights["imperial_meridian"] += 10
	if region.contains("0"):  # Core region
		weights["imperial_meridian"] += 10
	
	# Spindle Cartel - likes trade hubs, moderate pop
	weights["spindle_cartel"] = 10
	if pop >= 5 and pop <= 8:
		weights["spindle_cartel"] += 15
	if tech >= 6:
		weights["spindle_cartel"] += 10
	
	# Free Hab League - likes mining, lower tech, rim systems
	weights["free_hab_league"] = 10
	if mining >= 6:
		weights["free_hab_league"] += 20
	if pop >= 4 and pop <= 7:
		weights["free_hab_league"] += 10
	if not region.contains("0"):  # Rim regions
		weights["free_hab_league"] += 10
	
	# Nomad Clans - likes low pop, any region
	weights["nomad_clans"] = 8
	if pop <= 4:
		weights["nomad_clans"] += 15
	
	# Covenant of Quiet Suns - likes moderate pop, hospice systems
	weights["covenant_quiet_suns"] = 8
	if pop >= 3 and pop <= 6:
		weights["covenant_quiet_suns"] += 10
	
	# Black Exchange - likes low pop, fringe systems
	weights["black_exchange"] = 5
	if pop <= 5:
		weights["black_exchange"] += 10
	if not region.contains("0"):
		weights["black_exchange"] += 10
	
	# Artilect Custodians - likes high tech systems
	weights["artilect_custodians"] = 7
	if tech >= 8:
		weights["artilect_custodians"] += 20
	
	# Iron Wakes - mercenaries, any system
	weights["iron_wakes"] = 6
	if pop >= 4:
		weights["iron_wakes"] += 5
	
	# Drift Cartographers - likes fringe, exploration
	weights["drift_cartographers"] = 6
	if pop <= 6:
		weights["drift_cartographers"] += 10
	
	# Radiant Communion - zealots, any system
	weights["radiant_communion"] = 5
	
	return _weighted_random_faction(rng, weights)

func _select_minor_faction(rng: RandomNumberGenerator, pop: int, tech: int, mining: int, region: String) -> String:
	"""Select a minor faction with weighted probabilities"""
	var weights = {
		"silent_current_guild": 10,
		"aurum_combine": 8,
		"ashen_crown": 6,
		"eidolon_circle": 5,
		"echo_wardens": 5,
		"frontier_compacts": 12
	}
	
	# Frontier Compacts dominate low-pop systems
	if pop <= 3:
		weights["frontier_compacts"] += 20
	
	# Ashen Crown (pirates) likes fringe
	if pop <= 4 and not region.contains("0"):
		weights["ashen_crown"] += 10
	
	# Aurum Combine likes mining systems
	if mining >= 6:
		weights["aurum_combine"] += 15
	
	return _weighted_random_faction(rng, weights)

func _weighted_random_faction(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	"""Select a faction based on weighted probabilities"""
	var total_weight = 0
	for weight in weights.values():
		total_weight += weight
	
	var roll = rng.randf_range(0, total_weight)
	var current = 0.0
	
	for faction_id in weights.keys():
		current += weights[faction_id]
		if roll <= current:
			return faction_id
	
	# Fallback
	return weights.keys()[0]

func get_npc_ship_count(faction_id: String, pop_level: int, tech_level: int) -> int:
	"""
	Determine how many NPC ships should spawn in a system
	Based on faction type and system stats
	"""
	var faction = get_faction(faction_id)
	var faction_type = faction.get("type", "")
	
	# Base count from pop_level
	var base_count = clampi(pop_level / 2, 0, 5)
	
	# Modifiers by faction type
	match faction_type:
		"state", "corporate":
			# Imperial/Corporate have more ships in high-pop systems
			if pop_level >= 7:
				base_count += 2
		"mercenary_legion":
			# Mercs always have some presence
			base_count = max(base_count, 2)
		"smuggler_network", "pirate_confederacy":
			# Criminals prefer low-pop systems
			if pop_level <= 4:
				base_count += 1
		"nomad_confederation":
			# Nomads have variable presence
			base_count = max(base_count, 1)
	
	return clampi(base_count, 1, 8)

func get_npc_ship_types(faction_id: String) -> Array:
	"""
	Get list of ship type IDs that this faction uses
	Returns array of ship type strings like ["fighter", "corvette", "freighter"]
	"""
	var faction = get_faction(faction_id)
	var faction_type = faction.get("type", "")
	
	if faction_id == "independent" or faction_id == "":
		return ["independent_hauler", "independent_trader", "independent_patrol"]
	
	# Default ship types by faction category
	match faction_type:
		"state":
			return ["patrol_corvette", "customs_frigate", "military_destroyer"]
		"corporate":
			return ["corporate_freighter", "security_corvette", "mining_barge"]
		"cooperative":
			return ["hauler", "repair_ship", "militia_fighter"]
		"mercenary_legion":
			return ["merc_fighter", "assault_frigate", "heavy_corvette"]
		"smuggler_network", "pirate_confederacy":
			return ["raider", "smuggler_ship", "pirate_corvette"]
		"nomad_confederation":
			return ["nomad_hauler", "clan_frigate", "pilgrim_ship"]
		"religious_order", "religious_cult":
			return ["pilgrim_ship", "zealot_fighter", "temple_ship"]
		"ai_order":
			return ["drone_ship", "ai_corvette", "custodian_frigate"]
		"navigator_guild":
			return ["survey_ship", "scout_corvette", "explorer_frigate"]
		_:
			return ["generic_freighter", "generic_fighter", "generic_corvette"]
