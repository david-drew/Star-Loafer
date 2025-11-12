extends Node
class_name GalaxyGenerator

const SIZE_CONFIG = {
	"small": 50,
	"medium": 150,
	"large": 300,
	"huge": 600
}

# Reference to FactionManager (will be set from GameRoot/Systems)
@onready var faction_manager: FactionManager = FactionManager.new()

# System archetype data loaded from JSON
var system_archetypes: Dictionary = {}

func _ready() -> void:
	_load_system_archetypes()

func _load_system_archetypes() -> void:
	"""Load system archetype definitions from JSON"""
	var path = "res://data/system_archetypes.json"
	
	if not FileAccess.file_exists(path):
		push_warning("GalaxyGenerator: system_archetypes.json not found at %s" % path)
		return
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("GalaxyGenerator: Failed to open system_archetypes.json")
		return
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_error("GalaxyGenerator: JSON parse error in system_archetypes.json: %s" % json.get_error_message())
		return
	
	system_archetypes = json.data
	print("GalaxyGenerator: Loaded %d system archetypes" % system_archetypes.get("archetypes", []).size())

func generate(seed_value: int, size: String) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var system_count = SIZE_CONFIG.get(size, 150)
	var systems = _generate_systems(rng, system_count)
	var routes = _generate_routes(systems, rng)
	var regions = _generate_regions(systems, rng)
	
	# NEW: Assign factions to systems
	_assign_factions_to_systems(systems, rng)
	
	return {
		"schema": "star_loafer.galaxy.v1",
		"seed": seed_value,
		"size": size,
		"bounds": {"width": 1.0, "height": 1.0},
		"systems": systems,
		"routes": routes,
		"regions": regions
	}

func _generate_systems(rng: RandomNumberGenerator, count: int) -> Array:
	var systems = []
	var min_separation = 0.05
	
	# Poisson disk sampling for distribution
	for i in range(count):
		var valid_position = false
		var pos = Vector2.ZERO
		var attempts = 0
		
		while !valid_position and attempts < 100:
			pos = Vector2(rng.randf(), rng.randf())
			valid_position = true
			
			for existing in systems:
				var existing_pos = Vector2(existing["pos"][0], existing["pos"][1])
				if pos.distance_to(existing_pos) < min_separation:
					valid_position = false
					break
			
			attempts += 1
		
		if !valid_position:
			continue
		
		var system_id = "sys:%05d" % i
		
		# Create the base system structure
		var system = {
			"id": system_id,
			"name": _generate_system_name(rng),
			"pos": [pos.x, pos.y],
			"region_id": "",  # Assigned later
			"pop_level": 5,  # Default, will be set by archetype
			"tech_level": 5,  # Default, will be set by archetype
			"mining_quality": 5,  # Default, will be set by archetype
			"faction_id": "",  # Assigned later
			"faction_influence": 100,  # How strong faction control is (0-100)
			"tags": [],  # Will be populated by archetype
			"archetype": ""  # Will be assigned below
		}
		
		# Assign archetype and apply its properties
		_assign_system_archetype(system, rng)
		
		systems.append(system)
	
	return systems

func _assign_system_archetype(system: Dictionary, rng: RandomNumberGenerator) -> void:
	"""
	Assign an archetype to the system and apply its properties.
	This determines the system's tags, base stats, and character.
	"""
	var archetypes = system_archetypes.get("archetypes", [])
	
	if archetypes.is_empty():
		# Fallback: Generate basic stats without archetypes
		system["pop_level"] = rng.randi_range(0, 10)
		system["tech_level"] = rng.randi_range(0, 10)
		system["mining_quality"] = rng.randi_range(0, 10)
		system["tags"] = _generate_fallback_tags(rng)
		system["archetype"] = "generic"
		return
	
	# Build weighted list of archetypes
	var weighted_archetypes = []
	for archetype in archetypes:
		var weight = archetype.get("weight", 10)
		weighted_archetypes.append({
			"archetype": archetype,
			"weight": weight
		})
	
	# Select archetype using weighted random
	var total_weight = 0
	for entry in weighted_archetypes:
		total_weight += entry["weight"]
	
	var roll = rng.randi_range(0, total_weight - 1)
	var accum = 0
	var selected_archetype = null
	
	for entry in weighted_archetypes:
		accum += entry["weight"]
		if roll < accum:
			selected_archetype = entry["archetype"]
			break
	
	if selected_archetype == null:
		selected_archetype = weighted_archetypes[0]["archetype"]
	
	# Apply archetype properties
	system["archetype"] = selected_archetype.get("id", "generic")
	
	# Set base stats from archetype with some variance
	var base_pop = selected_archetype.get("base_pop_level", 5)
	var base_tech = selected_archetype.get("base_tech_level", 5)
	var base_mining = selected_archetype.get("base_mining_quality", 5)
	
	system["pop_level"] = clampi(base_pop + rng.randi_range(-2, 2), 0, 10)
	system["tech_level"] = clampi(base_tech + rng.randi_range(-2, 2), 0, 10)
	system["mining_quality"] = clampi(base_mining + rng.randi_range(-2, 2), 0, 10)
	
	# Copy tags from archetype
	var archetype_tags = selected_archetype.get("tags", [])
	system["tags"] = archetype_tags.duplicate()

func _apply_regional_modifiers(systems: Array, regions: Array) -> void:
	"""
	Apply regional modifiers to systems based on their region.
	This adjusts archetypes and stats based on location (core vs frontier).
	"""
	var regional_modifiers = system_archetypes.get("regional_modifiers", {})
	
	for system in systems:
		var region_id = system.get("region_id", "")
		if region_id == "":
			continue
		
		# Find the region
		var region = null
		for r in regions:
			if r["id"] == region_id:
				region = r
				break
		
		if region == null:
			continue
		
		var biome = region.get("biome", "neutral_zone")
		var modifier = regional_modifiers.get(biome, {})
		
		if modifier.is_empty():
			continue
		
		# Apply stat modifiers
		var pop_mod = modifier.get("pop_modifier", 0)
		var tech_mod = modifier.get("tech_modifier", 0)
		
		system["pop_level"] = clampi(system["pop_level"] + pop_mod, 0, 10)
		system["tech_level"] = clampi(system["tech_level"] + tech_mod, 0, 10)

func _generate_fallback_tags(rng: RandomNumberGenerator) -> Array:
	"""Generate basic tags when archetypes aren't available"""
	var possible_tags = [
		"industrial", "trade", "frontier", "mining", 
		"agricultural", "military", "research", "peaceful", "lawless"
	]
	
	var tag_count = rng.randi_range(1, 3)
	var selected_tags = []
	
	for i in range(tag_count):
		var tag = possible_tags[rng.randi_range(0, possible_tags.size() - 1)]
		if not selected_tags.has(tag):
			selected_tags.append(tag)
	
	return selected_tags

func _generate_routes(systems: Array, rng: RandomNumberGenerator) -> Array:
	var routes = []
	
	# Connect each system to 3 nearest neighbors
	for system in systems:
		var system_pos = Vector2(system["pos"][0], system["pos"][1])
		var neighbors = []
		
		for other in systems:
			if other["id"] == system["id"]:
				continue
			
			var other_pos = Vector2(other["pos"][0], other["pos"][1])
			var dist = system_pos.distance_to(other_pos)
			neighbors.append({"id": other["id"], "dist": dist})
		
		neighbors.sort_custom(func(a, b): return a["dist"] < b["dist"])
		
		for i in range(min(3, neighbors.size())):
			var neighbor = neighbors[i]
			
			# Check if route already exists (bidirectional)
			var route_exists = false
			for existing_route in routes:
				if (existing_route["a"] == system["id"] and existing_route["b"] == neighbor["id"]) or \
				   (existing_route["b"] == system["id"] and existing_route["a"] == neighbor["id"]):
					route_exists = true
					break
			
			if !route_exists:
				routes.append({
					"a": system["id"],
					"b": neighbor["id"],
					"dist": neighbor["dist"]
				})
	
	return routes

func _generate_regions(systems: Array, rng: RandomNumberGenerator) -> Array:
	# Simple grid-based regions for Phase 0
	var region_count = 4
	var regions = []
	
	for i in range(region_count):
		regions.append({
			"id": "region:%d" % i,
			"name": _generate_region_name(rng),
			"aabb": [],  # TODO: Calculate bounds
			"biome": "core_space" if i == 0 else "outer_rim"
		})
	
	# Assign systems to regions based on position
	for system in systems:
		var pos = Vector2(system["pos"][0], system["pos"][1])
		var region_index = int(pos.x * 2) + int(pos.y * 2) * 2
		region_index = clampi(region_index, 0, region_count - 1)
		system["region_id"] = "region:%d" % region_index
	
	# Apply regional modifiers to systems
	_apply_regional_modifiers(systems, regions)
	
	return regions

func _assign_factions_to_systems(systems: Array, rng: RandomNumberGenerator) -> void:
	"""
	Assign factions to systems based on system properties and faction preferences
	Creates faction territories and borders
	"""
	if faction_manager == null:
		push_warning("GalaxyGenerator: FactionManager not set, skipping faction assignment")
		return
	
	print("GalaxyGenerator: Assigning factions to %d systems..." % systems.size())
	var use_minor_factions = true
	
	# First pass: Assign primary faction to each system
	for system in systems:
		# FIXED: Pass the entire system dictionary, not just tags
		var faction_id = faction_manager.select_faction_for_system(system, use_minor_factions)
		
		system["faction_id"] = faction_id
		
		# Determine influence strength (how much control faction has)
		var pop_level = system.get("pop_level", 5)
		var influence = _calculate_faction_influence(faction_id, pop_level, rng)
		system["faction_influence"] = influence
	
	# Second pass: Create faction borders and contested zones
	_create_faction_borders(systems, rng)
	
	# Log faction distribution
	_log_faction_distribution(systems)

func _calculate_faction_influence(faction_id: String, pop_level: int, rng: RandomNumberGenerator) -> int:
	"""
	Calculate how strongly a faction controls this system
	Returns 0-100, where 100 = total control, 0 = no control
	"""
	var base_influence = 50
	
	# Higher pop = stronger control for state/corporate factions
	var faction_type = faction_manager.get_faction_type(faction_id)
	match faction_type:
		"state", "corporate":
			if pop_level >= 7:
				base_influence += 30
			elif pop_level >= 4:
				base_influence += 15
		"smuggler_network", "pirate_confederacy":
			# Criminals have weaker control
			base_influence -= 20
			if pop_level <= 3:
				base_influence += 10
		"nomad_confederation":
			# Nomads have variable control
			base_influence -= 10
	
	# Add some randomness
	base_influence += rng.randi_range(-10, 10)
	
	return clampi(base_influence, 20, 100)

func _create_faction_borders(systems: Array, rng: RandomNumberGenerator) -> void:
	"""
	Create natural faction borders by checking neighboring systems
	Reduces influence in systems bordering hostile factions
	"""
	for system in systems:
		var system_pos = Vector2(system["pos"][0], system["pos"][1])
		var faction_id = system.get("faction_id", "")
		
		if faction_id == "":
			continue
		
		# Check nearby systems for hostile factions
		var hostile_neighbors = 0
		for other in systems:
			if other["id"] == system["id"]:
				continue
			
			var other_pos = Vector2(other["pos"][0], other["pos"][1])
			var dist = system_pos.distance_to(other_pos)
			
			# Only check close neighbors (within 0.1 normalized distance)
			if dist <= 0.1:
				var other_faction = other.get("faction_id", "")
				if other_faction != "" and faction_manager.are_hostile(faction_id, other_faction):
					hostile_neighbors += 1
		
		# Reduce influence if surrounded by hostiles (contested border)
		if hostile_neighbors >= 2:
			system["faction_influence"] = max(system["faction_influence"] - 25, 30)
			if not system["tags"].has("contested"):
				system["tags"].append("contested")

func _log_faction_distribution(systems: Array) -> void:
	"""Log faction distribution for debugging"""
	var faction_counts = {}
	
	for system in systems:
		var faction_id = system.get("faction_id", "none")
		if faction_id not in faction_counts:
			faction_counts[faction_id] = 0
		faction_counts[faction_id] += 1
	
	print("GalaxyGenerator: Faction distribution:")
	for faction_id in faction_counts.keys():
		var count = faction_counts[faction_id]
		var faction_name = faction_manager.get_faction_name(faction_id)
		print("  - %s: %d systems (%.1f%%)" % [faction_name, count, (count * 100.0) / systems.size()])

func _generate_system_name(rng: RandomNumberGenerator) -> String:
	var prefixes = ["Alpha", "Beta", "Gamma", "Delta", "Kestrel", "Vekara", "Thalys", "Nexor"]
	var suffixes = ["Prime", "Minor", "Reach", "Gate", "Haven", "Station"]
	
	return prefixes[rng.randi_range(0, prefixes.size() - 1)] + " " + \
		   suffixes[rng.randi_range(0, suffixes.size() - 1)]

func _generate_region_name(rng: RandomNumberGenerator) -> String:
	var names = ["Inner Core", "Outer Rim", "Frontier Zone", "Contested Space"]
	return names[rng.randi_range(0, names.size() - 1)]

func find_valid_starter_system(galaxy_data: Dictionary) -> Dictionary:
	var valid_systems = []
	
	for system in galaxy_data["systems"]:
		# Must have decent pop/tech
		if system["pop_level"] >= 3 and system["tech_level"] >= 3:
			# Avoid starting in hostile/extreme factions
			var faction_id = system.get("faction_id", "")
			if faction_id in ["imperial_meridian", "spindle_cartel", "free_hab_league", "frontier_compacts"]:
				valid_systems.append(system)
	
	if valid_systems.is_empty():
		return galaxy_data["systems"][0]  # Fallback
	
	var rng = RandomNumberGenerator.new()
	rng.seed = galaxy_data["seed"]
	return valid_systems[rng.randi_range(0, valid_systems.size() - 1)]
