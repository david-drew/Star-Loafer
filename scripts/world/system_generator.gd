extends Node
class_name SystemGenerator

## Procedural system generation for Star Loafer
## Generates stars, planets, moons, and stations using data-driven configuration

# Data storage
var station_types_data: Dictionary = {}
var moon_types_data: Dictionary = {}
var planet_types_data: Dictionary = {}

# Lazy loading flags
var _data_loaded: bool = false

## ============================================================
## PUBLIC API
## ============================================================

func generate(system_id: String, galaxy_seed: int, pop_level: int, tech_level: int, mining_quality: int) -> Dictionary:
	"""
	Generate a complete star system
	Returns dictionary with stars, bodies, and stations arrays
	"""
	# Ensure data is loaded
	_ensure_data_loaded()
	
	# Create RNG with deterministic seed
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(galaxy_seed) ^ hash(system_id.hash())
	
	# Create spatial layout manager
	var layout := SystemLayout.new()
	
	# Generate system components
	var stars := _generate_stars(rng)
	_register_stars_in_layout(stars, layout)
	
	var bodies := _generate_bodies(rng, stars, pop_level, tech_level, mining_quality, layout)
	var stations := _generate_stations(rng, bodies, stars, pop_level, tech_level, mining_quality, layout)
	
	# Log generation summary
	_print_generation_summary(system_id, stars, bodies, stations, layout)
	
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

## ============================================================
## DATA LOADING
## ============================================================

func _ensure_data_loaded() -> void:
	"""Lazy load all data files on first generation"""
	if _data_loaded:
		return
	
	print("SystemGenerator: Loading data files...")
	
	station_types_data = DataLoader.load_types_data(
		"res://data/procgen/station_types.json",
		"station"
	)
	
	moon_types_data = DataLoader.load_types_data(
		"res://data/procgen/moon_types.json",
		"moon"
	)
	
	# Planet types are optional if ContentDB handles them
	# Uncomment if you have a planet_types.json:
	# planet_types_data = DataLoader.load_types_data(
	#     "res://data/procgen/planet_types.json",
	#     "planet"
	# )
	
	_data_loaded = true
	print("SystemGenerator: Data loading complete")

## ============================================================
## STAR GENERATION
## ============================================================

func _generate_stars(rng: RandomNumberGenerator) -> Array:
	"""Generate stars for the system"""
	var star_count := _roll_star_count(rng)
	var stars := []
	
	for i in range(star_count):
		var star_data := _create_star_data(i, rng)
		stars.append(star_data)
	
	return stars

func _roll_star_count(rng: RandomNumberGenerator) -> int:
	"""Determine number of stars (1-3)"""
	var roll := rng.randf()
	if roll < 0.7:
		return 1  # 70% single star
	elif roll < 0.95:
		return 2  # 25% binary
	else:
		return 3  # 5% trinary

func _create_star_data(index: int, rng: RandomNumberGenerator) -> Dictionary:
	"""Create data for a single star"""
	var is_special := _roll_special_star(rng)
	
	if is_special["type"] != "":
		return {
			"id": "star:%s" % char(65 + index),
			"class": "Special",
			"special_type": is_special["type"],
			"sprite": is_special["sprite"],
			"effects": is_special["effects"]
		}
	else:
		var spectral_class := _roll_spectral_class(rng)
		return {
			"id": "star:%s" % char(65 + index),
			"class": spectral_class,
			"sprite": ContentDB.get_star_sprite(spectral_class, rng),
			"mass_solar": rng.randf_range(0.8, 2.0),
			"luminosity": rng.randf_range(0.5, 1.5)
		}

func _roll_special_star(rng: RandomNumberGenerator) -> Dictionary:
	"""Check if star is a special type (brown dwarf, white dwarf, etc.)"""
	var roll := rng.randf()
	var special_config: Dictionary = ContentDB.star_types.get("special", {})
	
	if roll < 0.02:
		return _get_special_star_config(special_config, "brown_dwarf")
	elif roll < 0.04:
		return _get_special_star_config(special_config, "white_dwarf")
	elif roll < 0.043:
		return _get_special_star_config(special_config, "hypergiant")
	
	return {"type": "", "sprite": "", "effects": []}

func _get_special_star_config(config: Dictionary, type_id: String) -> Dictionary:
	"""Get configuration for a special star type"""
	var star_config:Variant = config.get(type_id, {})
	return {
		"type": type_id,
		"sprite": star_config.get("sprite", ""),
		"effects": star_config.get("effects", [])
	}

func _roll_spectral_class(rng: RandomNumberGenerator) -> String:
	"""Roll random spectral class from ContentDB"""
	var classes: Array = ContentDB.star_types.get("spectral_classes", ["G"])
	return classes[rng.randi_range(0, classes.size() - 1)]

func _register_stars_in_layout(stars: Array, layout: SystemLayout) -> void:
	"""Register stars in layout system (actual positioning done in SystemExploration)"""
	for star in stars:
		layout.place_star(star, Vector2.ZERO)  # Placeholder position

## ============================================================
## BODY GENERATION (PLANETS & MOONS)
## ============================================================

func _generate_bodies(
	rng: RandomNumberGenerator,
	stars: Array,
	pop_level: int,
	tech_level: int,
	mining_quality: int,
	layout: SystemLayout
) -> Array:
	"""Generate all celestial bodies (planets, moons, belts)"""
	var bodies := []
	
	# Generate planets with moons
	var planets := _generate_planets(rng, stars, pop_level, mining_quality, layout)
	bodies.append_array(planets)
	
	# Generate asteroid belts
	var belts := _generate_asteroid_belts(rng, stars, mining_quality)
	bodies.append_array(belts)
	
	# Add inhabitant data to all bodies
	_populate_all_inhabitants(bodies, pop_level, rng)
	
	return bodies

func _generate_planets(
	rng: RandomNumberGenerator,
	stars: Array,
	pop_level: int,
	mining_quality: int,
	layout: SystemLayout
) -> Array:
	"""Generate planets and their moons"""
	var bodies := []
	var planet_count := _calculate_planet_count(rng)
	
	print("SystemGenerator: Generating %d planets..." % planet_count)
	
	for i in range(planet_count):
		# Generate planet
		var planet_data := _create_planet_data(i, rng, stars, mining_quality)
		var placed_planet := _place_planet(planet_data, layout, rng)
		
		if placed_planet.is_empty():
			continue
		
		bodies.append(placed_planet)
		
		# Generate moons for this planet
		var moons := _generate_moons_for_planet(placed_planet, i, rng, pop_level, mining_quality, layout)
		bodies.append_array(moons)
	
	return bodies

func _calculate_planet_count(rng: RandomNumberGenerator) -> int:
	"""Determine number of planets"""
	var count := rng.randi_range(6, 14)
	
	# 15% chance of extra planets
	if rng.randf() < 0.15:
		count += rng.randi_range(2, 4)
	
	return clampi(count, 3, 18)

func _create_planet_data(
	index: int,
	rng: RandomNumberGenerator,
	stars: Array,
	mining_quality: int
) -> Dictionary:
	"""Create initial planet data (before placement)"""
	var orbit_radius_au := 1.5 + index * 3.5 + rng.randf_range(-0.8, 0.8)
	var planet_type := _select_planet_type(rng, orbit_radius_au)
	var orbit_angle := rng.randf() * TAU
	
	return {
		"id": "body:%d" % index,
		"kind": "planet",
		"type": planet_type,
		"orbit": {
			"parent": stars[0]["id"],
			"a_AU": orbit_radius_au,
			"angle_rad": orbit_angle,
			"period_days": OrbitalUtils.calculate_orbital_period(orbit_radius_au)
		},
		"sprite": ContentDB.get_planet_sprite(planet_type, rng),
		"resources": _generate_resources(rng, planet_type, mining_quality),
		"population": _calculate_planet_population(planet_type, 0),  # Will be set by _populate_all_inhabitants
		"inhabitant_data": {}
	}

func _place_planet(planet_data: Dictionary, layout: SystemLayout, rng: RandomNumberGenerator) -> Dictionary:
	"""Place planet using layout system for collision avoidance"""
	var orbit:Dictionary = planet_data["orbit"]
	var placed:Dictionary = layout.place_planet(planet_data, orbit["a_AU"], orbit["angle_rad"], rng)
	
	if placed.is_empty():
		push_warning("SystemGenerator: Failed to place planet %s" % planet_data.get("id", "unknown"))
	
	return placed

func _select_planet_type(rng: RandomNumberGenerator, orbit_radius_au: float) -> String:
	"""Select planet type based on orbital distance"""
	if orbit_radius_au < 2.0:
		var inner_types := ["volcanic", "toxic", "desert", "rocky"]
		return inner_types[rng.randi_range(0, inner_types.size() - 1)]
	elif orbit_radius_au < 4.0:
		var habitable_types := ["terran", "ocean", "rocky", "desert", "thick_atmo"]
		return habitable_types[rng.randi_range(0, habitable_types.size() - 1)]
	elif orbit_radius_au < 10.0:
		var mid_types := ["gas", "ice", "rocky", "thick_atmo"]
		return mid_types[rng.randi_range(0, mid_types.size() - 1)]
	else:
		var outer_types := ["ice", "gas", "barren"]
		return outer_types[rng.randi_range(0, outer_types.size() - 1)]

func _calculate_planet_population(planet_type: String, system_pop_level: int) -> int:
	"""Calculate base planet population (modified later by system pop level)"""
	var base_pop := system_pop_level
	
	match planet_type:
		"terran":
			base_pop += 3
		"ocean":
			base_pop += 2
		"thick_atmo", "ice_world":
			base_pop += 1
		"volcanic", "barren":
			base_pop -= 2
		"gas":
			base_pop -= 5
	
	return clampi(base_pop, 0, 10)

## ============================================================
## MOON GENERATION
## ============================================================

func _generate_moons_for_planet(
	planet: Dictionary,
	planet_index: int,
	rng: RandomNumberGenerator,
	pop_level: int,
	mining_quality: int,
	layout: SystemLayout
) -> Array:
	"""Generate moons orbiting a planet"""
	var moons := []
	
	# 30% chance of no moons
	if rng.randf() < 0.3:
		return moons
	
	# Get moon count from planet type
	var planet_type: String = planet.get("type", "")
	var moon_count_range: Array = ContentDB.get_planet_moon_range(planet_type)
	
	if moon_count_range.is_empty() or moon_count_range.size() != 2:
		return moons
	
	var num_moons := rng.randi_range(moon_count_range[0], moon_count_range[1])
	
	if num_moons <= 0:
		return moons
	
	var moon_types: Array = moon_types_data.get("types", [])
	if moon_types.is_empty():
		return moons
	
	var planet_id: String = planet.get("id", "")
	
	for moon_idx in range(num_moons):
		var moon_data := _create_moon_data(planet_id, planet_index, moon_idx, rng, moon_types, pop_level, mining_quality)
		var placed_moon := _place_moon(moon_data, planet_id, layout, rng)
		
		if not placed_moon.is_empty():
			moons.append(placed_moon)
	
	return moons

func _create_moon_data(
	parent_id: String,
	planet_index: int,
	moon_index: int,
	rng: RandomNumberGenerator,
	moon_types: Array,
	pop_level: int,
	mining_quality: int
) -> Dictionary:
	"""Create initial moon data"""
	var moon_type_data: Dictionary = moon_types[rng.randi_range(0, moon_types.size() - 1)]
	var moon_type: String = moon_type_data.get("id", "barren")
	
	var orbit_range: Array = moon_type_data.get("orbit_radius_px_range", [400, 1200])
	var desired_orbit_radius_px := DataLoader.get_random_from_range(orbit_range, rng, 600.0)
	var desired_orbit_angle := rng.randf() * TAU
	
	return {
		"id": "moon:%d_%d" % [planet_index, moon_index],
		"kind": "moon",
		"type": moon_type,
		"parent_id": parent_id,
		"orbit": {
			"parent": parent_id,
			"radius_px": desired_orbit_radius_px,
			"angle_rad": desired_orbit_angle,
			"period_days": OrbitalUtils.calculate_moon_orbital_period(desired_orbit_radius_px)
		},
		"sprite": ContentDB.get_moon_sprite(moon_type, rng),
		"resources": _generate_resources(rng, moon_type, mining_quality),
		"population": 0,  # Will be set by _populate_all_inhabitants
		"size_px_range": moon_type_data.get("size_px_range", [20, 40]),
		"gravity_factor": moon_type_data.get("gravity_factor", 0.1),
		"has_atmosphere": moon_type_data.get("has_atmosphere", 0.0),
		"tidal_lock": moon_type_data.get("tidal_lock", 0.8),
		"inhabitant_data": {}
	}

func _place_moon(
	moon_data: Dictionary,
	parent_id: String,
	layout: SystemLayout,
	rng: RandomNumberGenerator
) -> Dictionary:
	"""Place moon relative to parent planet"""
	var orbit:Dictionary = moon_data["orbit"]
	var placed := layout.place_moon_relative_to_planet(
		moon_data,
		parent_id,
		orbit["radius_px"],
		orbit["angle_rad"],
		rng
	)
	
	if placed.is_empty():
		push_warning("SystemGenerator: Failed to place moon %s around %s" % [
			moon_data.get("id", "unknown"),
			parent_id
		])
	
	return placed

## ============================================================
## ASTEROID BELT GENERATION
## ============================================================

func _generate_asteroid_belts(
	rng: RandomNumberGenerator,
	stars: Array,
	mining_quality: int
) -> Array:
	"""Generate asteroid belts"""
	var belts := []
	
	if mining_quality < 6:
		return belts
	
	var belt_count := rng.randi_range(1, 2)
	
	for i in range(belt_count):
		var belt_radius_au := 15.0 + i * 25.0 + rng.randf_range(-5.0, 5.0)
		
		belts.append({
			"id": "belt:%d" % i,
			"kind": "asteroid_belt",
			"orbit": {
				"parent": stars[0]["id"],
				"a_AU": belt_radius_au
			},
			"resources": _generate_resources(rng, "asteroid_belt", mining_quality),
			"inhabitant_data": {}
		})
	
	return belts

## ============================================================
## STATION GENERATION
## ============================================================

func _generate_stations(
	rng: RandomNumberGenerator,
	bodies: Array,
	stars: Array,
	pop_level: int,
	tech_level: int,
	mining_quality: int,
	layout: SystemLayout
) -> Array:
	"""Generate stations using layout system"""
	var stations := []
	
	var types: Array = station_types_data.get("types", [])
	if types.is_empty():
		push_warning("SystemGenerator: No station types available")
		return stations
	
	var budget := _calculate_station_budget(pop_level, tech_level)
	var available := _get_available_station_types(types, pop_level)
	
	if available.is_empty():
		return stations
	
	print("SystemGenerator: Attempting to place %d stations..." % budget)
	
	var placed_count := 0
	var failed_count := 0
	
	for _i in range(budget):
		var station_type: Dictionary = available[rng.randi_range(0, available.size() - 1)]
		var station_data := _create_station_data(placed_count, station_type, rng)
		
		var placement_prefs: Dictionary = station_type.get("placement_prefs", {})
		var placed_station := layout.place_station(station_data, placement_prefs, bodies, rng)
		
		if not placed_station.is_empty():
			_add_station_inhabitants(placed_station, station_type, rng)
			stations.append(placed_station)
			placed_count += 1
		else:
			failed_count += 1
	
	if failed_count > 0:
		print("SystemGenerator: Placed %d/%d stations (%d failed)" % [placed_count, budget, failed_count])
	
	return stations

func _calculate_station_budget(pop_level: int, tech_level: int) -> int:
	"""Calculate how many stations to generate"""
	var base_count := pop_level / 2
	var tech_bonus := tech_level / 3
	return clampi(base_count + tech_bonus, 1, 12)

func _get_available_station_types(types: Array, pop_level: int) -> Array:
	"""Filter station types by population level"""
	var categorized := {
		"very_high": [],
		"high": [],
		"medium": [],
		"low": [],
		"any": []
	}
	
	# Categorize by bias
	for type in types:
		var bias:String = type.get("pop_bias", "any")
		if bias in categorized:
			categorized[bias].append(type)
	
	# Build available list based on pop level
	var available: Array = []
	
	if pop_level >= 8:
		available += categorized["very_high"] + categorized["high"]
	elif pop_level >= 6:
		available += categorized["high"] + categorized["medium"]
	elif pop_level >= 3:
		available += categorized["medium"] + categorized["low"]
	else:
		available += categorized["low"]
	
	available += categorized["any"]
	
	return available

func _create_station_data(id: int, station_type: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	"""Create base station data (position added by layout)"""
	var type_id: String = station_type.get("id", "")
	var variants := int(station_type.get("variants", 1))
	var variant := rng.randi_range(1, max(variants, 1))
	
	var size_px := DataLoader.get_random_from_range(
		station_type.get("size_px_range", [200, 300]),
		rng,
		256.0
	)
	
	var asset_pattern: String = station_types_data.get("asset_pattern", "")
	var sprite_path := DataLoader.resolve_asset_path(asset_pattern, type_id, variant)
	
	return {
		"id": "station:%d" % id,
		"type": type_id,
		"name": _generate_station_name(type_id, rng),
		"faction_id": "",
		"variant": variant,
		"position": [0, 0],  # Set by layout
		"services": station_type.get("services", []),
		"broadcast": _generate_broadcast(type_id, rng),
		"sprite_path": sprite_path,
		"size_px": size_px,
		"color_hints": station_type.get("color_hints", []),
		"can_dock": bool(station_type.get("can_dock", true)),
		"docking_ports": int(station_type.get("docking_ports", 0)),
		"population_range": station_type.get("population_range", [0, 0]),
		"tech_level": station_type.get("tech_level", "standard"),
		"market_tier": int(station_type.get("market_tier", 0)),
		"repair_tier": int(station_type.get("repair_tier", 0)),
		"shipyard_tier": int(station_type.get("shipyard_tier", 0)),
		"security_level": int(station_type.get("security_level", 0)),
		"faction_bias": station_type.get("faction_bias", "neutral"),
		"inhabitant_data": {}
	}

func _add_station_inhabitants(station_data: Dictionary, station_type: Dictionary, rng: RandomNumberGenerator) -> void:
	"""Add inhabitant data to station"""
	var pop_range: Array = station_type.get("population_range", [10, 500])
	var population := DataLoader.get_random_int_from_range(pop_range, rng, 100)
	
	var tech_level_str: String = station_type.get("tech_level", "standard")
	var tech_level_int := _convert_tech_level_to_int(tech_level_str)
	
	station_data["inhabitant_data"] = {
		"is_inhabited": true,
		"population": population,
		"faction_id": "",
		"settlement_type": "station",
		"has_spaceport": station_data.get("can_dock", true),
		"tech_level": tech_level_int
	}

func _convert_tech_level_to_int(tech_level: String) -> int:
	"""Convert tech level string to numeric value"""
	match tech_level:
		"primitive": return 1
		"low": return 2
		"standard": return 3
		"advanced": return 5
		"experimental", "cutting_edge": return 7
		"alien": return 9
		_: return 3

## ============================================================
## POPULATION & INHABITANTS
## ============================================================

func _populate_all_inhabitants(bodies: Array, pop_level: int, rng: RandomNumberGenerator) -> void:
	"""Add inhabitant data to all bodies"""
	for body in bodies:
		var kind: String = body.get("kind", "")
		
		if kind == "planet":
			_add_planet_inhabitants(body, pop_level, rng)
		elif kind == "moon":
			_add_moon_inhabitants(body, pop_level, rng)

func _add_planet_inhabitants(planet: Dictionary, pop_level: int, rng: RandomNumberGenerator) -> void:
	"""Add inhabitant data to planet"""
	var planet_type: String = planet.get("type", "")
	var population := _calculate_planet_population(planet_type, pop_level)
	
	planet["population"] = population
	
	if population > 0:
		planet["inhabitant_data"] = {
			"is_inhabited": true,
			"population": population,
			"faction_id": "",
			"settlement_type": "colony",
			"has_spaceport": population >= 5,
			"tech_level": _calculate_settlement_tech_level(population, rng)
		}
	else:
		planet["inhabitant_data"] = {
			"is_inhabited": false,
			"population": 0,
			"faction_id": "",
			"settlement_type": "none",
			"has_spaceport": false,
			"tech_level": 0
		}

func _add_moon_inhabitants(moon: Dictionary, pop_level: int, rng: RandomNumberGenerator) -> void:
	"""Add inhabitant data to moon"""
	var moon_type: String = moon.get("type", "")
	var population := _calculate_moon_population(moon_type, pop_level)
	
	moon["population"] = population
	
	if population > 0:
		moon["inhabitant_data"] = {
			"is_inhabited": true,
			"population": population,
			"faction_id": "",
			"settlement_type": "outpost",
			"has_spaceport": population >= 3,
			"tech_level": _calculate_settlement_tech_level(population, rng)
		}
	else:
		moon["inhabitant_data"] = {
			"is_inhabited": false,
			"population": 0,
			"faction_id": "",
			"settlement_type": "none",
			"has_spaceport": false,
			"tech_level": 0
		}

func _calculate_moon_population(moon_type: String, system_pop_level: int) -> int:
	"""Calculate moon population"""
	var moon_types: Array = moon_types_data.get("types", [])
	var moon_data := DataLoader.get_type_by_id(moon_types, moon_type)
	
	if moon_data.is_empty():
		return 0
	
	var pop_bias: String = moon_data.get("pop_bias", "low")
	var base_pop := system_pop_level
	
	match pop_bias:
		"very_high": base_pop += 3
		"high": base_pop += 2
		"any": base_pop += 0
		"low": base_pop -= 2
		"none": base_pop -= 5
	
	return clampi(base_pop, 0, 10)

func _calculate_settlement_tech_level(population: int, rng: RandomNumberGenerator) -> int:
	"""Calculate settlement tech level based on population"""
	var base_tech := clampi(population / 2, 1, 5)
	var variation := rng.randi_range(-1, 1)
	return clampi(base_tech + variation, 1, 7)

## ============================================================
## RESOURCE GENERATION
## ============================================================

func _generate_resources(rng: RandomNumberGenerator, body_type: String, mining_quality: int) -> Array:
	"""Generate resource deposits for a body"""
	var resources := []
	var resource_types := ["iron", "nickel", "water_ice", "rare_earth"]
	var resource_count := clampi(mining_quality / 3, 1, 3)
	
	for i in range(resource_count):
		var res_type: String = resource_types[rng.randi_range(0, resource_types.size() - 1)]
		var richness := rng.randf_range(0.1, 1.0) * (mining_quality / 10.0)
		resources.append({"type": res_type, "richness": richness})
	
	return resources

## ============================================================
## NAME GENERATION
## ============================================================

func _generate_station_name(type_id: String, rng: RandomNumberGenerator) -> String:
	"""Generate a name for a station"""
	var prefixes := ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Station", "Hub", "Post"]
	var suffixes := ["Prime", "Station", "Outpost", "Complex", "Terminal", "Port", "Depot"]
	
	match type_id:
		"warp_gate":
			return "%s Gate" % prefixes[rng.randi_range(0, prefixes.size() - 1)]
		"habitat":
			return "%s Habitat" % prefixes[rng.randi_range(0, prefixes.size() - 1)]
		"trading_station":
			return "%s Trade Hub" % prefixes[rng.randi_range(0, prefixes.size() - 1)]
		"shipyard":
			return "%s Shipyard" % prefixes[rng.randi_range(0, prefixes.size() - 1)]
		_:
			return "%s %s" % [
				prefixes[rng.randi_range(0, prefixes.size() - 1)],
				suffixes[rng.randi_range(0, suffixes.size() - 1)]
			]

func _generate_broadcast(type_id: String, rng: RandomNumberGenerator) -> String:
	"""Generate broadcast message for a station"""
	var messages := {
		"trading_station": [
			"Welcome traders! Current market prices available on request.",
			"All ships: docking clearance required. No weapons hot in trade zone.",
			"Fresh supplies and competitive prices. Dock at bay 3-7."
		],
		"warp_gate": [
			"Gate operational. Queue for transit at beacon Alpha.",
			"All vessels: submit jump coordinates for clearance.",
			"Welcome to the gate network. Safe travels."
		],
		"habitat": [
			"Habitat facilities open to all peaceful travelers.",
			"Medical bay and rest facilities available. Welcome home.",
			"Fresh food, clean water, and warm beds. Dock at your leisure."
		],
		"refuel_depot": [
			"Fuel depot online. All grades available.",
			"Quick refuel service. No questions asked.",
			"Fill your tanks. We run 24/7."
		]
	}
	
	var type_messages: Array = messages.get(type_id, [])
	if type_messages.is_empty():
		return ""
	
	return type_messages[rng.randi_range(0, type_messages.size() - 1)]

## ============================================================
## DEBUG / LOGGING
## ============================================================

func _print_generation_summary(
	system_id: String,
	stars: Array,
	bodies: Array,
	stations: Array,
	layout: SystemLayout
) -> void:
	"""Print generation summary"""
	var planet_count := bodies.filter(func(b): return b.get("kind") == "planet").size()
	var moon_count := bodies.filter(func(b): return b.get("kind") == "moon").size()
	var belt_count := bodies.filter(func(b): return b.get("kind") == "asteroid_belt").size()
	
	print("SystemGenerator: Generated system '%s'" % system_id)
	print("  Stars: %d" % stars.size())
	print("  Planets: %d" % planet_count)
	print("  Moons: %d" % moon_count)
	print("  Belts: %d" % belt_count)
	print("  Stations: %d" % stations.size())
	layout.print_layout_summary()
