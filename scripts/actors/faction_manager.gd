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

# Runtime faction database for the current game (active factions only)
# This is the authoritative, mutable set of factions for the current save.
# Includes things like the player faction and any dynamically created factions.
var factions: Dictionary = {}

func _ready() -> void:
	_load_faction_data()
	_build_lookup_tables()
	_register_with_save_system()
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
	if not FileAccess.file_exists(path):
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
	
	var data = json.data
	if data == null:
		push_warning("FactionManager: No data in JSON: %s" % path)
		return default_value
	
	return data

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

func _build_lookup_tables() -> void:
	faction_by_id.clear()
	major_factions.clear()
	minor_factions.clear()
	
	for faction_data in factions_core:
		if typeof(faction_data) != TYPE_DICTIONARY:
			continue
		
		if not faction_data.has("id"):
			continue
		
		var faction_id = str(faction_data["id"])
		faction_by_id[faction_id] = faction_data
		
		var is_major = faction_data.get("is_major", false)
		if is_major:
			major_factions.append(faction_id)
		else:
			minor_factions.append(faction_id)

# === SAVE / LOAD INTEGRATION ===

func _register_with_save_system() -> void:
	var save_system := get_node_or_null("/root/SaveSystem")
	if save_system == null:
		push_warning("FactionManager: SaveSystem not found; not registered as save provider.")
		return
	# SaveSystem will call _put_state() when saving and _get_state(state) when loading.
	save_system.register_provider(
		"factions",
		Callable(self, "_put_state"),
		Callable(self, "_get_state")
	)

func _put_state() -> Dictionary:
	# Return only runtime / mutable state. Static JSON content is reloaded on startup.
	return {
		"factions": factions.duplicate(true)
	}

func _get_state(state: Dictionary) -> void:
	# Restore runtime state from the saved data. Invoked by SaveSystem.load_from_slot().
	factions.clear()
	if state.has("factions") and typeof(state["factions"]) == TYPE_DICTIONARY:
		factions = state["factions"].duplicate(true)

# === PUBLIC API ===

func get_faction(faction_id: String) -> Dictionary:
	"""Get complete faction data by ID (from core definitions)"""
	return faction_by_id.get(faction_id, {})

func get_faction_name(faction_id: String) -> String:
	"""Get faction display name"""
	var faction = get_faction(faction_id)
	return faction.get("name", faction_id)

func get_faction_type(faction_id: String) -> String:
	"""Get faction type (state, corporate, pirate, etc.)"""
	var faction = get_faction(faction_id)
	return faction.get("type", "unknown")

func is_major_faction(faction_id: String) -> bool:
	return major_factions.has(faction_id)

func is_minor_faction(faction_id: String) -> bool:
	return minor_factions.has(faction_id)

func get_major_factions() -> Array:
	return major_factions.duplicate()

func get_minor_factions() -> Array:
	return minor_factions.duplicate()

func get_random_major_faction() -> String:
	if major_factions.is_empty():
		return ""
	return major_factions[randi() % major_factions.size()]

func get_random_minor_faction() -> String:
	if minor_factions.is_empty():
		return ""
	return minor_factions[randi() % minor_factions.size()]

func get_faction_relations(faction_id: String) -> Dictionary:
	"""Get all relations for a faction"""
	if faction_relations.has(faction_id):
		return faction_relations[faction_id]
	return {}

func get_faction_relation_value(source_id: String, target_id: String) -> float:
	"""Get specific relation value between two factions"""
	if faction_relations.has(source_id):
		var rels = faction_relations[source_id]
		if rels.has(target_id):
			return float(rels[target_id])
	return 0.0

func are_hostile(faction_a: String, faction_b: String) -> bool:
	"""Check if two factions are hostile to each other"""
	var relation = get_faction_relation_value(faction_a, faction_b)
	return relation < -30.0  # Negative relations indicate hostility

func get_system_faction_candidates(system_tags: Array) -> Array:
	"""Return factions suitable for a star system based on its tags"""
	var candidates: Array = []
	
	for faction_id in faction_by_id.keys():
		var faction = faction_by_id[faction_id]
		if not faction.has("system_affinity"):
			continue
		
		var affinity_tags = faction["system_affinity"]
		if typeof(affinity_tags) != TYPE_ARRAY:
			continue
		
		var score = 0
		for tag in system_tags:
			if affinity_tags.has(tag):
				score += 1
		
		if score > 0:
			candidates.append({
				"id": faction_id,
				"score": score
			})
	
	candidates.sort_custom(func(a, b):
		return a["score"] > b["score"]
	)
	
	return candidates

func select_faction_for_system(system: Dictionary, allow_minor: bool = true) -> String:
	"""
	Choose a faction for a system based on its properties.
	FIXED: Now accepts the full system Dictionary instead of just tags.
	
	Args:
		system: Full system dictionary containing tags, archetype, stats, etc.
		allow_minor: Whether to allow minor factions to be selected
	
	Returns:
		String: The selected faction_id
	"""
	# Extract tags from the system
	var system_tags: Array = system.get("tags", [])
	
	# Try to find factions with matching affinities
	var candidates = get_system_faction_candidates(system_tags)
	
	# If no candidates based on tags, consider system properties
	if candidates.is_empty():
		candidates = _get_faction_candidates_by_properties(system, allow_minor)
	
	# Still no candidates? Fall back to random selection
	if candidates.is_empty():
		if major_factions.size() > 0:
			return get_random_major_faction()
		elif allow_minor and minor_factions.size() > 0:
			return get_random_minor_faction()
		return ""
	
	# Weighted random selection from candidates
	var total_score = 0
	for c in candidates:
		total_score += int(c["score"])
	
	if total_score <= 0:
		return candidates[0]["id"] if candidates.size() > 0 else ""
	
	var roll = randi() % total_score
	var accum = 0
	
	for c in candidates:
		accum += int(c["score"])
		if roll < accum:
			return c["id"]
	
	return candidates[0]["id"]

func _get_faction_candidates_by_properties(system: Dictionary, allow_minor: bool) -> Array:
	"""
	Get faction candidates based on system properties when tag matching fails.
	This provides a fallback that considers population, tech level, and archetype.
	"""
	var candidates: Array = []
	var pop_level = system.get("pop_level", 5)
	var tech_level = system.get("tech_level", 5)
	var archetype = system.get("archetype", "")
	
	for faction_id in faction_by_id.keys():
		var faction = faction_by_id[faction_id]
		
		# Skip minor factions if not allowed
		if not allow_minor and is_minor_faction(faction_id):
			continue
		
		var score = 1  # Base score for all factions
		var faction_type = faction.get("type", "")
		
		# Score based on faction type and system properties
		match faction_type:
			"state":
				# States prefer high population systems
				if pop_level >= 6:
					score += 3
				if tech_level >= 5:
					score += 1
			
			"corporate":
				# Corporations prefer wealthy, high-tech systems
				if tech_level >= 7:
					score += 3
				if pop_level >= 5:
					score += 2
			
			"pirate_confederacy", "smuggler_network":
				# Pirates prefer frontier/lawless systems
				if pop_level <= 4:
					score += 2
				if archetype in ["frontier_settlement", "pirate_den", "abandoned_ruins"]:
					score += 3
			
			"nomad_confederation":
				# Nomads are flexible but prefer moderate systems
				if pop_level >= 3 and pop_level <= 7:
					score += 2
			
			"trade_league":
				# Trade leagues prefer trade hubs
				if archetype in ["trade_nexus", "nomad_waystation"]:
					score += 4
				if pop_level >= 5:
					score += 1
		
		if score > 1:  # Only include if there's some affinity
			candidates.append({
				"id": faction_id,
				"score": score
			})
	
	# Sort by score
	candidates.sort_custom(func(a, b):
		return a["score"] > b["score"]
	)
	
	return candidates

func get_faction_color(faction_id: String) -> Color:
	"""Get display color for faction (for maps/UI)"""
	var faction = get_faction(faction_id)
	
	if faction.has("color"):
		var c = faction["color"]
		if typeof(c) == TYPE_ARRAY and c.size() >= 3:
			return Color(float(c[0]) / 255.0, float(c[1]) / 255.0, float(c[2]) / 255.0)
	
	if is_major_faction(faction_id):
		return Color(0.8, 0.8, 1.0)
	
	if is_minor_faction(faction_id):
		return Color(0.7, 0.7, 0.7)
	
	return Color(0.5, 0.5, 0.5)

func get_faction_description(faction_id: String) -> String:
	"""Get long-form description for UI/lore"""
	var faction = get_faction(faction_id)
	return faction.get("description", "")

func get_faction_economy_profile(faction_id: String) -> Dictionary:
	"""Get economic profile and trade specialties"""
	if faction_economy.has(faction_id):
		return faction_economy[faction_id]
	return {}

func get_faction_mission_templates(faction_id: String) -> Array:
	"""Get mission templates associated with this faction"""
	if faction_missions.has(faction_id):
		return faction_missions[faction_id]
	return []

func get_faction_subfactions(faction_id: String) -> Array:
	"""Get all sub-factions associated with a parent faction"""
	var result: Array = []
	for sub in faction_subfactions:
		if typeof(sub) != TYPE_DICTIONARY:
			continue
		if sub.get("parent_id", "") == faction_id:
			result.append(sub)
	return result

func get_weighted_random_faction(exclude_ids: Array = [], prefer_major: bool = true) -> String:
	"""Get a random faction, optionally weighted and excluding some"""
	var pool: Array = []
	
	if prefer_major:
		for id in major_factions:
			if not exclude_ids.has(id):
				pool.append({"id": id, "weight": 3})
		for id in minor_factions:
			if not exclude_ids.has(id):
				pool.append({"id": id, "weight": 1})
	else:
		for id in major_factions:
			if not exclude_ids.has(id):
				pool.append({"id": id, "weight": 2})
		for id in minor_factions:
			if not exclude_ids.has(id):
				pool.append({"id": id, "weight": 2})
	
	if pool.is_empty():
		return ""
	
	var total_weight = 0
	for entry in pool:
		total_weight += int(entry["weight"])
	
	var roll = randi() % total_weight
	var accum = 0
	for entry in pool:
		accum += int(entry["weight"])
		if roll < accum:
			return entry["id"]
	
	return pool[0]["id"]

func get_faction_home_system_hint(faction_id: String) -> String:
	"""Return a hint about where the faction's home system might be"""
	var faction = get_faction(faction_id)
	return faction.get("home_system_hint", "")

func get_faction_presence_in_system(faction_id: String, system_tags: Array) -> float:
	"""Return approximate influence level of a faction in a system"""
	var base = 0.0
	
	if is_major_faction(faction_id):
		base = 0.6
	elif is_minor_faction(faction_id):
		base = 0.3
	else:
		base = 0.1
	
	var faction = get_faction(faction_id)
	if faction.has("system_affinity"):
		var affinity_tags = faction["system_affinity"]
		if typeof(affinity_tags) == TYPE_ARRAY:
			for tag in system_tags:
				if affinity_tags.has(tag):
					base += 0.1
	
	return clamp(base, 0.0, 1.0)

func get_faction_ship_prefix(faction_id: String) -> String:
	"""Get ship naming prefix for a faction"""
	var faction = get_faction(faction_id)
	return faction.get("ship_prefix", "")

func get_faction_ship_styles(faction_id: String) -> Dictionary:
	"""Get visual + gameplay style hints for faction ships"""
	var faction = get_faction(faction_id)
	return faction.get("ship_styles", {})

func get_default_ship_archetypes_for_faction(faction_id: String) -> Array:
	"""Suggest default ship archetypes for the faction."""
	var faction = get_faction(faction_id)
	if faction.is_empty():
		return ["generic_freighter", "generic_fighter", "generic_corvette"]
	
	var role = faction.get("role", "")
	var faction_type = faction.get("type", "")
	
	# Role-based overrides
	match role:
		"trade_league":
			return ["bulk_freighter", "escort_corvette", "contractor_frigate"]
		"pirate_confederacy":
			return ["raider", "boarding_frigate", "strike_corvette"]
		"mercenary_legion":
			return ["gunship", "assault_frigate", "siege_corvette"]
		"frontier_alliance":
			return ["scout_corvette", "patrol_frigate", "salvage_ship"]
		"technocrat_union":
			return ["research_vessel", "advanced_frigate", "drone_carrier"]
		"holy_dominion":
			return ["pilgrim_ship", "crusader_frigate", "cathedral_ship"]
		"syndicate":
			return ["smuggler_ship", "interceptor", "covert_frigate"]
		"explorer_guild":
			return ["survey_ship", "pathfinder_corvette", "long_range_frigate"]
		"ai_order":
			return ["drone_ship", "ai_corvette", "custodian_frigate"]
		"navigator_guild":
			return ["survey_ship", "scout_corvette", "explorer_frigate"]
		_:
			return ["generic_freighter", "generic_fighter", "generic_corvette"]

func register_player_faction(faction_data: Dictionary) -> void:
	if not factions.has("player_faction"):
		factions["player_faction"] = faction_data
		print("FactionManager: Registered player faction")

func get_all_faction_ids() -> Array:
	return faction_by_id.keys()
