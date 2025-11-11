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
		var pop_level = rng.randi_range(0, 10)
		var tech_level = rng.randi_range(0, 10)
		var mining_quality = rng.randi_range(0, 10)
		
		systems.append({
			"id": system_id,
			"name": _generate_system_name(rng),
			"pos": [pos.x, pos.y],
			"region_id": "",  # Assigned later
			"pop_level": pop_level,
			"tech_level": tech_level,
			"mining_quality": mining_quality,
			"faction_id": "",  # NEW: Assigned later
			"faction_influence": 100,  # NEW: How strong faction control is (0-100)
			"tags": []
		})
	
	return systems

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
	
	# First pass: Assign primary faction to each system
	for system in systems:
		var faction_id = faction_manager.select_faction_for_system(rng, system)
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
