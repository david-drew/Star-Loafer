extends Node
class_name GalaxyGenerator

const SIZE_CONFIG = {
	"small": 50,
	"medium": 150,
	"large": 300,
	"huge": 600
}

func generate(seed_value: int, size: String) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var system_count = SIZE_CONFIG.get(size, 150)
	var systems = _generate_systems(rng, system_count)
	var routes = _generate_routes(systems, rng)
	var regions = _generate_regions(systems, rng)
	
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
		if system["pop_level"] >= 3 and system["tech_level"] >= 3:
			valid_systems.append(system)
	
	if valid_systems.is_empty():
		return galaxy_data["systems"][0]  # Fallback
	
	var rng = RandomNumberGenerator.new()
	rng.seed = galaxy_data["seed"]
	return valid_systems[rng.randi_range(0, valid_systems.size() - 1)]
