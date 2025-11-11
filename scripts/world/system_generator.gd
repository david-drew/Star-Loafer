extends Node
class_name SystemGenerator

func generate(system_id: String, galaxy_seed: int, pop_level: int, tech_level: int, mining_quality: int) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(galaxy_seed) ^ hash(system_id.hash())
	
	var stars = _generate_stars(rng)
	var bodies = _generate_bodies(rng, stars, pop_level, tech_level, mining_quality)
	var stations = _generate_stations(rng, bodies, pop_level, tech_level, mining_quality)
	
	return {
		"schema": "star_loafer.system.v1",
		"system_id": system_id,
		"seed": rng.seed,
		"stars": stars,
		"bodies": bodies,
		"stations": stations,
		"summary": {
			"pop_level": pop_level,
			"tech_level": tech_level,
			"mining_quality": mining_quality
		}
	}

func _generate_stars(rng: RandomNumberGenerator) -> Array:
	var star_count = _roll_star_count(rng)
	var stars = []
	
	for i in range(star_count):
		var is_special = _roll_special_star(rng)
		var star_data = {}
		
		if is_special["type"] != "":
			star_data = {
				"id": "star:%s" % char(65 + i),
				"class": "Special",
				"special_type": is_special["type"],
				"sprite": is_special["sprite"],
				"effects": is_special["effects"]
			}
		else:
			var spectral_class = _roll_spectral_class(rng)
			star_data = {
				"id": "star:%s" % char(65 + i),
				"class": spectral_class,
				"sprite": ContentDB.get_star_sprite(spectral_class, rng),
				"mass_solar": rng.randf_range(0.8, 2.0),
				"luminosity": rng.randf_range(0.5, 1.5)
			}
		
		stars.append(star_data)
	
	return stars

func _roll_star_count(rng: RandomNumberGenerator) -> int:
	var roll = rng.randf()
	if roll < 0.7:
		return 1
	elif roll < 0.95:
		return 2
	else:
		return 3

func _roll_special_star(rng: RandomNumberGenerator) -> Dictionary:
	var roll = rng.randf()
	var special_config = ContentDB.star_types.get("special", {})
	
	if roll < 0.02:  # Brown dwarf
		return {
			"type": "brown_dwarf",
			"sprite": special_config.get("brown_dwarf", {}).get("sprite", ""),
			"effects": special_config.get("brown_dwarf", {}).get("effects", [])
		}
	elif roll < 0.04:  # White dwarf
		return {
			"type": "white_dwarf",
			"sprite": special_config.get("white_dwarf", {}).get("sprite", ""),
			"effects": special_config.get("white_dwarf", {}).get("effects", [])
		}
	elif roll < 0.043:  # Hypergiant
		return {
			"type": "hypergiant",
			"sprite": special_config.get("hypergiant", {}).get("sprite", ""),
			"effects": special_config.get("hypergiant", {}).get("effects", [])
		}
	
	return {"type": "", "sprite": "", "effects": []}

func _roll_spectral_class(rng: RandomNumberGenerator) -> String:
	var classes = ContentDB.star_types.get("spectral_classes", ["G"])
	return classes[rng.randi_range(0, classes.size() - 1)]

func _generate_bodies(rng: RandomNumberGenerator, stars: Array, pop_level: int, tech_level: int, mining_quality: int) -> Array:
	var bodies = []
	
	# FIX: Planet count should NOT depend on pop_level
	# Base count 4-10, with rare chance of up to 15
	var planet_count = rng.randi_range(4, 10)
	if rng.randf() < 0.1:  # 10% chance of extra planets
		planet_count += rng.randi_range(1, 5)  # Could go up to 15
	
	planet_count = clampi(planet_count, 1, 15)  # Hard cap at 15
	
	# Generate planets
	for i in range(planet_count):
		var orbit_radius = 2.0 + i * 4.0 + rng.randf_range(-1.0, 1.0)
		var planet_type = _select_planet_type(rng, pop_level, orbit_radius)
		var orbit_angle = rng.randf() * TAU
		
		var body = {
			"id": "body:%d" % i,
			"kind": "planet",
			"type": planet_type,
			"orbit": {
				"parent": stars[0]["id"],
				"a_AU": orbit_radius,
				"angle_rad": orbit_angle,
				"period_days": _calculate_period(orbit_radius)
			},
			"sprite": ContentDB.get_planet_sprite(planet_type, rng),
			"resources": _roll_resources(rng, planet_type, mining_quality),
			"population": _calculate_planet_population(planet_type, pop_level)  # NEW
		}
		
		bodies.append(body)
	
	# Generate asteroid belts (if mining_quality high)
	if mining_quality >= 6:
		var belt_count = rng.randi_range(1, 2)
		for i in range(belt_count):
			var belt_radius = 0.0
			if i == 0:
				belt_radius = rng.randf_range(15.0, 25.0)  # Middle belt
			else:
				belt_radius = rng.randf_range(40.0, 60.0)  # Outer belt
			bodies.append({
				"id": "belt:%d" % i,
				"kind": "asteroid_belt",
				"orbit": {
					"parent": stars[0]["id"],
					"a_AU": belt_radius
				},
				"resources": _roll_resources(rng, "asteroid_belt", mining_quality)
			})
	
	return bodies

func _calculate_planet_population(planet_type: String, system_pop_level: int) -> int:
	"""
	Calculate individual planet population based on type and system pop_level
	Returns 0-10 scale for this specific planet
	"""
	
	# Base population from system level (but with variance)
	var base_pop = system_pop_level
	
	# Habitable planets get population boost
	match planet_type:
		"terran", "primordial":
			base_pop += 3  # Major boost for Earth-like
		"ocean_world":
			base_pop += 2  # Good for population
		"ice_world":
			base_pop += 1  # Can be colonized
		"volcanic", "barren":
			base_pop -= 2  # Harsh conditions
		"gas":
			base_pop -= 5  # Gas giants can't be inhabited (but moons could)
	
	return clampi(base_pop, 0, 10)

func _select_planet_type(rng: RandomNumberGenerator, pop_level: int, orbit_radius: float) -> String:
	var planet_types = ContentDB.planet_types.get("types", [])
	
	# Otherwise, select based on orbit
	if orbit_radius < 1.0:
		var inner = ["rocky", "volcanic", "barren"]
		return inner[rng.randi_range(0, inner.size() - 1)]
	elif orbit_radius > 3.0:
		var outer = ["gas", "ice_world"]
		return outer[rng.randi_range(0, outer.size() - 1)]
	else:
		return planet_types[rng.randi_range(0, planet_types.size() - 1)]["id"]

func _calculate_period(orbit_radius: float) -> float:
	# Compressed: inner ~10 days, outer ~60 days
	return 10.0 + orbit_radius * 10.0

func _roll_resources(rng: RandomNumberGenerator, body_type: String, mining_quality: int) -> Array:
	var resources = []
	var resource_types = ["iron", "nickel", "water_ice", "rare_earth"]
	
	var resource_count = clampi(mining_quality / 3, 1, 3)
	for i in range(resource_count):
		var res_type = resource_types[rng.randi_range(0, resource_types.size() - 1)]
		var richness = rng.randf_range(0.1, 1.0) * (mining_quality / 10.0)
		resources.append({
			"type": res_type,
			"richness": richness
		})
	
	return resources

func _generate_stations(rng: RandomNumberGenerator, bodies: Array, pop_level: int, tech_level: int, mining_quality: int) -> Array:
	var stations = []
	
	# Warp gate
	if pop_level >= 5 and tech_level >= 3:
		stations.append({
			"id": "station:gate",
			"kind": "warp_gate",
			"enabled": true
		})
	
	# Ore processor
	if mining_quality >= 6:
		stations.append({
			"id": "station:ore_processor",
			"kind": "ore_processor"
		})
	
	# Corporate mining
	if mining_quality >= 8:
		stations.append({
			"id": "station:mining_corp",
			"kind": "corporate_mining"
		})
	
	return stations
