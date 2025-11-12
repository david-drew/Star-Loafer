extends Node
class_name SystemGenerator

# Station types data
var station_types_data: Dictionary = {}
var station_types_loaded: bool = false
var _asset_pattern: String = "res://assets/images/actors/stations/{type}_{variant}.png"

# Moon types data
var moon_types_data: Dictionary = {}
var moon_types_loaded: bool = false
var _moon_asset_pattern: String = "res://assets/images/stellar_bodies/moons/{type}_{variant}.png"

func _load_station_types() -> void:
	"""Load station types from JSON"""
	var path = "res://data/procgen/station_types.json"
	
	if !FileAccess.file_exists(path):
		push_warning("SystemGenerator: station_types.json not found at %s, using fallback" % path)
		station_types_data = {}
		return
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SystemGenerator: Failed to open station_types.json, using fallback")
		station_types_data = {}
		return
	
	var json_text = file.get_as_text()
	file.close()
	
	if json_text == "" or json_text.length() > 100000:
		push_error("SystemGenerator: Invalid JSON file size")
		station_types_data = {}
		return
	
	var json := JSON.new()
	var err := json.parse(json_text)
	if err != OK:
		push_error("SystemGenerator: JSON parse error in station_types.json: %s" % json.get_error_message())
		station_types_data = {}
		return
	
	station_types_data = json.data
	
	if station_types_data.is_empty():
		push_warning("SystemGenerator: station_types.json loaded but is empty")
	else:
		_asset_pattern = station_types_data.get("asset_pattern", _asset_pattern)
		print("SystemGenerator: Loaded %d station types" % station_types_data.get("types", []).size())

func _load_moon_types() -> void:
	"""Load moon types from JSON"""
	var path = "res://data/procgen/moon_types.json"
	
	if !FileAccess.file_exists(path):
		push_warning("SystemGenerator: moon_types.json not found at %s, skipping moon generation" % path)
		moon_types_data = {}
		return
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SystemGenerator: Failed to open moon_types.json, skipping moon generation")
		moon_types_data = {}
		return
	
	var json_text = file.get_as_text()
	file.close()
	
	if json_text == "" or json_text.length() > 100000:
		push_error("SystemGenerator: Invalid JSON file size for moon_types.json")
		moon_types_data = {}
		return
	
	var json := JSON.new()
	var err := json.parse(json_text)
	if err != OK:
		push_error("SystemGenerator: JSON parse error in moon_types.json: %s" % json.get_error_message())
		moon_types_data = {}
		return
	
	moon_types_data = json.data
	
	if moon_types_data.is_empty():
		push_warning("SystemGenerator: moon_types.json loaded but is empty")
	else:
		_moon_asset_pattern = moon_types_data.get("asset_pattern", _moon_asset_pattern)
		print("SystemGenerator: Loaded %d moon types" % moon_types_data.get("types", []).size())

func generate(system_id: String, galaxy_seed: int, pop_level: int, tech_level: int, mining_quality: int) -> Dictionary:
	# Lazy load station types on first use
	if !station_types_loaded:
		_load_station_types()
		station_types_loaded = true
	
	# Lazy load moon types on first use
	if !moon_types_loaded:
		_load_moon_types()
		moon_types_loaded = true
	
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(galaxy_seed) ^ hash(system_id.hash())
	
	var stars := _generate_stars(rng)
	var bodies := _generate_bodies(rng, stars, pop_level, tech_level, mining_quality)
	var stations := _generate_stations(rng, bodies, stars, pop_level, tech_level, mining_quality)
	
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

# -------------------- STARS & BODIES --------------------

func _generate_stars(rng: RandomNumberGenerator) -> Array:
	var star_count := _roll_star_count(rng)
	var stars := []
	for i in range(star_count):
		var is_special := _roll_special_star(rng)
		var star_data := {}
		if is_special["type"] != "":
			star_data = {
				"id": "star:%s" % char(65 + i),
				"class": "Special",
				"special_type": is_special["type"],
				"sprite": is_special["sprite"],
				"effects": is_special["effects"]
			}
		else:
			var spectral_class := _roll_spectral_class(rng)
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
	var roll := rng.randf()
	if roll < 0.7:
		return 1
	elif roll < 0.95:
		return 2
	else:
		return 3

func _roll_special_star(rng: RandomNumberGenerator) -> Dictionary:
	var roll := rng.randf()
	var special_config:Dictionary = ContentDB.star_types.get("special", {})
	if roll < 0.02:
		return {"type":"brown_dwarf","sprite":special_config.get("brown_dwarf", {}).get("sprite",""),"effects":special_config.get("brown_dwarf", {}).get("effects",[])}
	elif roll < 0.04:
		return {"type":"white_dwarf","sprite":special_config.get("white_dwarf", {}).get("sprite",""),"effects":special_config.get("white_dwarf", {}).get("effects",[])}
	elif roll < 0.043:
		return {"type":"hypergiant","sprite":special_config.get("hypergiant", {}).get("sprite",""),"effects":special_config.get("hypergiant", {}).get("effects",[])}
	return {"type": "", "sprite": "", "effects": []}

func _roll_spectral_class(rng: RandomNumberGenerator) -> String:
	var classes:Array = ContentDB.star_types.get("spectral_classes", ["G"])
	return classes[rng.randi_range(0, classes.size() - 1)]

func _generate_bodies(rng: RandomNumberGenerator, stars: Array, pop_level: int, tech_level: int, mining_quality: int) -> Array:
	var bodies := []
	var planet_count := rng.randi_range(4, 10)
	if rng.randf() < 0.1:
		planet_count += rng.randi_range(1, 5)
	planet_count = clampi(planet_count, 1, 15)
	
	# Generate planets
	for i in range(planet_count):
		var orbit_radius := 2.0 + i * 4.0 + rng.randf_range(-1.0, 1.0)
		var planet_type := _select_planet_type(rng, orbit_radius)
		var orbit_angle := rng.randf() * TAU
		
		var planet := {
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
			"population": _calculate_planet_population(planet_type, pop_level),
			"inhabitant_data": {}  # Will be filled later
		}
		
		bodies.append(planet)
		
		# Generate moons for this planet
		var moons := _generate_moons_for_planet(rng, planet, i, pop_level, mining_quality)
		bodies.append_array(moons)
	
	# Generate asteroid belts
	if mining_quality >= 6:
		var belt_count := rng.randi_range(1, 2)
		for i in range(belt_count):
			var belt_radius: float
			if i == 0:
				belt_radius = rng.randf_range(15.0, 25.0)
			else:
				belt_radius = rng.randf_range(40.0, 60.0)
			
			bodies.append({
				"id":"belt:%d"%i,
				"kind":"asteroid_belt",
				"orbit":{"parent":stars[0]["id"],"a_AU":belt_radius},
				"resources":_roll_resources(rng,"asteroid_belt",mining_quality),
				"inhabitant_data": {}  # Belts typically uninhabited
			})
	
	# Add inhabitant data to all bodies
	_populate_inhabitant_data(bodies, pop_level, rng)
	
	return bodies

func _generate_moons_for_planet(rng: RandomNumberGenerator, planet: Dictionary, planet_index: int, pop_level: int, mining_quality: int) -> Array:
	"""Generate moons orbiting a planet"""
	var moons := []
	
	# Check if we should generate moons (30% chance of 0 moons)
	if rng.randf() < 0.3:
		return moons
	
	# Get planet type data from ContentDB to determine moon count range
	var planet_type: String = planet.get("type", "")
	var moon_count_range: Array = ContentDB.get_planet_moon_range(planet_type)
	
	if moon_count_range.is_empty() or moon_count_range.size() != 2:
		# No moon data for this planet type
		return moons
	
	var num_moons := rng.randi_range(moon_count_range[0], moon_count_range[1])
	
	if num_moons <= 0:
		return moons
	
	# Get available moon types
	var moon_types: Array = moon_types_data.get("types", [])
	if moon_types.is_empty():
		return moons
	
	for moon_idx in range(num_moons):
		var moon_type_data: Dictionary = _select_moon_type(rng, moon_types)
		if moon_type_data.is_empty():
			continue
		
		var moon_type: String = moon_type_data.get("id", "barren")
		
		# Get orbit radius from moon type data (in pixels)
		var orbit_range: Array = moon_type_data.get("orbit_radius_px_range", [400, 1200])
		var orbit_radius_px: float = rng.randf_range(float(orbit_range[0]), float(orbit_range[1]))
		var orbit_angle := rng.randf() * TAU
		
		# Calculate orbital period (moons orbit faster, days)
		var period_days := _calculate_moon_period(orbit_radius_px)
		
		var moon := {
			"id": "moon:%d_%d" % [planet_index, moon_idx],
			"kind": "moon",
			"type": moon_type,
			"parent_id": planet.get("id", "body:0"),
			"orbit": {
				"parent": planet.get("id", "body:0"),
				"radius_px": orbit_radius_px,
				"angle_rad": orbit_angle,
				"period_days": period_days
			},
			"sprite": ContentDB.get_moon_sprite(moon_type, rng),
			"resources": _roll_resources(rng, moon_type, mining_quality),
			"population": _calculate_moon_population(moon_type, pop_level),
			"inhabitant_data": {},  # Will be filled later
			"size_px_range": moon_type_data.get("size_px_range", [20, 40]),
			"gravity_factor": moon_type_data.get("gravity_factor", 0.1),
			"has_atmosphere": moon_type_data.get("has_atmosphere", 0.0),
			"tidal_lock": moon_type_data.get("tidal_lock", 0.8)
		}
		print("\tMoon Sprite: %s" %moon.sprite) 	# DEBUG
		
		moons.append(moon)
	
	return moons

func _select_moon_type(rng: RandomNumberGenerator, moon_types: Array) -> Dictionary:
	"""Select a random moon type from available types"""
	if moon_types.is_empty():
		return {}
	return moon_types[rng.randi_range(0, moon_types.size() - 1)]

func _calculate_moon_period(orbit_radius_px: float) -> float:
	"""Calculate orbital period for a moon (faster than planets)"""
	# Moons orbit much faster - scale based on pixel distance
	# Rough approximation: closer moons orbit faster
	return max(0.5, orbit_radius_px / 400.0)  # 0.5 to ~5 days typically

func _calculate_moon_population(moon_type: String, system_pop_level: int) -> int:
	"""Calculate moon population based on type and system pop (similar to planets)"""
	if moon_types_data.is_empty():
		return 0
	
	var moon_types: Array = moon_types_data.get("types", [])
	var moon_data: Dictionary = {}
	
	# Find the moon type data
	for mt in moon_types:
		if mt.get("id", "") == moon_type:
			moon_data = mt
			break
	
	if moon_data.is_empty():
		return 0
	
	var pop_bias: String = moon_data.get("pop_bias", "low")
	var base_pop := system_pop_level
	
	# Adjust based on pop_bias
	match pop_bias:
		"very_high":
			base_pop += 3
		"high":
			base_pop += 2
		"any":
			base_pop += 0
		"low":
			base_pop -= 2
		"none":
			base_pop -= 5
	
	return clampi(base_pop, 0, 10)

func _populate_inhabitant_data(bodies: Array, pop_level: int, rng: RandomNumberGenerator) -> void:
	"""Add inhabitant data to all bodies (planets and moons)"""
	for body in bodies:
		var kind: String = body.get("kind", "")
		
		if kind in ["planet", "moon"]:
			var population: int = body.get("population", 0)
			var body_type: String = body.get("type", "")
			
			var inhabitant_data := {
				"is_inhabited": population > 0,
				"population": population,
				"faction_id": "",  # Will be set by SystemExploration from system data
				"settlement_type": _determine_settlement_type(population),
				"has_spaceport": population >= 5,
				"tech_level": _determine_body_tech_level(population, pop_level),
			}
			
			body["inhabitant_data"] = inhabitant_data
		
		elif kind == "asteroid_belt":
			# Belts typically have mining outposts, not settlements
			body["inhabitant_data"] = {
				"is_inhabited": false,
				"population": 0,
				"faction_id": "",
				"settlement_type": "none",
				"has_spaceport": false,
				"tech_level": 0
			}

func _determine_settlement_type(population: int) -> String:
	"""Determine settlement type based on population level"""
	if population <= 0:
		return "none"
	elif population <= 2:
		return "outpost"
	elif population <= 4:
		return "colony"
	elif population <= 6:
		return "settlement"
	elif population <= 8:
		return "city"
	else:
		return "metropolis"

func _determine_body_tech_level(population: int, system_pop_level: int) -> int:
	"""Determine tech level for a body based on its population"""
	if population <= 0:
		return 0
	
	# Tech level scales with population but capped by system level
	var base_tech := clampi(population / 2, 1, 5)
	var system_tech := clampi(system_pop_level / 2, 1, 5)
	
	return mini(base_tech, system_tech)

func _select_planet_type(rng: RandomNumberGenerator, orbit_radius: float) -> String:
	if orbit_radius < 1.0:
		var inner := ["rocky","volcanic","barren"]
		return inner[rng.randi_range(0, inner.size()-1)]
	elif orbit_radius > 10.0:
		var outer := ["gas","ice_world"]
		return outer[rng.randi_range(0, outer.size()-1)]
	else:
		var mid_zone := ["terran","primordial","ocean_world","rocky","barren"]
		return mid_zone[rng.randi_range(0, mid_zone.size()-1)]

func _calculate_planet_population(planet_type: String, system_pop_level: int) -> int:
	var base_pop := system_pop_level
	match planet_type:
		"terran", "primordial":
			base_pop += 3
		"ocean_world":
			base_pop += 2
		"ice_world":
			base_pop += 1
		"volcanic", "barren":
			base_pop -= 2
		"gas":
			base_pop -= 5
	return clampi(base_pop, 0, 10)

func _calculate_period(orbit_radius: float) -> float:
	return 10.0 + orbit_radius * 10.0

func _roll_resources(rng: RandomNumberGenerator, body_type: String, mining_quality: int) -> Array:
	var resources := []
	var resource_types := ["iron","nickel","water_ice","rare_earth"]
	var resource_count := clampi(mining_quality / 3, 1, 3)
	for i in range(resource_count):
		var res_type:String = resource_types[rng.randi_range(0, resource_types.size()-1)]
		var richness := rng.randf_range(0.1, 1.0) * (mining_quality / 10.0)
		resources.append({"type":res_type,"richness":richness})
	return resources

# -------------------- STATIONS --------------------

func _generate_stations(rng: RandomNumberGenerator, bodies: Array, stars: Array, pop_level: int, tech_level: int, mining_quality: int) -> Array:
	var stations := []
	if station_types_data.is_empty():
		push_warning("SystemGenerator: No station types loaded, using fallback generation")
		return _generate_stations_fallback(rng, pop_level, tech_level, mining_quality)
	
	var types: Array = station_types_data.get("types", [])
	if types.is_empty():
		return _generate_stations_fallback(rng, pop_level, tech_level, mining_quality)
	
	var budget := _calculate_station_budget(pop_level, tech_level)
	var categorized := _categorize_stations_by_bias(types, pop_level)
	var available := _get_all_available_types(categorized, pop_level)
	
	if available.is_empty():
		return []
	
	var station_counter := 0
	for _i in range(budget):
		if available.is_empty():
			break
		
		var station_type: Dictionary = available[rng.randi_range(0, available.size() - 1)]
		var position := _calculate_station_position_json(station_type, bodies, stars, rng)
		
		var station_data := _create_station_data(
			"station:%d" % station_counter,
			station_type,
			position,
			rng
		)
		
		# Add inhabitant data for stations
		_add_station_inhabitant_data(station_data, station_type, rng)
		
		stations.append(station_data)
		station_counter += 1
	
	print("SystemGenerator: Generated %d stations" % stations.size())
	return stations

func _add_station_inhabitant_data(station_data: Dictionary, station_type: Dictionary, rng: RandomNumberGenerator) -> void:
	"""Add inhabitant data to a station"""
	var pop_range: Array = station_type.get("population_range", [10, 500])
	var population := rng.randi_range(pop_range[0], pop_range[1]) if pop_range.size() == 2 else 100
	
	var inhabitant_data := {
		"is_inhabited": true,  # Stations are almost always inhabited
		"population": population,
		"faction_id": "",  # Will be set by SystemExploration from system data
		"settlement_type": "station",
		"has_spaceport": station_data.get("can_dock", true),
		"tech_level": _station_tech_level(station_type.get("tech_level", "standard")),
	}
	
	station_data["inhabitant_data"] = inhabitant_data

func _station_tech_level(tech_level_str: String) -> int:
	"""Convert station tech level string to numeric value"""
	match tech_level_str:
		"primitive":
			return 1
		"standard":
			return 3
		"advanced":
			return 5
		"cutting_edge":
			return 7
		_:
			return 3

func _calculate_station_position_json(station_type: Dictionary, bodies: Array, stars: Array, rng: RandomNumberGenerator) -> Vector2:
	var type_id:String = station_type.get("id", "")
	var prefs:Dictionary = station_type.get("placement_prefs", {})
	
	# If explicit pixel radius range is given, use it directly
	if typeof(prefs) == TYPE_DICTIONARY and prefs.has("orbit_radius_px_range"):
		var rr:Array = prefs["orbit_radius_px_range"]
		if typeof(rr) == TYPE_ARRAY and rr.size() == 2:
			var a := rng.randf() * TAU
			var rp := rng.randf_range(float(rr[0]), float(rr[1]))
			return Vector2(cos(a), sin(a)) * rp
	
	# Otherwise keep previous per-type heuristics (AU)
	match type_id:
		"warp_gate":
			return _random_orbit_position(rng, 8.0, 15.0)
		"habitat", "trading_station", "shipyard":
			var habitable := bodies.filter(func(b): return b.get("kind") == "planet" and b.get("population", 0) >= 5)
			if !habitable.is_empty():
				return _orbit_position_near_body(habitable[0], rng, 1.0)
			else:
				return _orbit_position_near_body(bodies[0], rng, 1.0)
		"ore_refinery", "mining_outpost":
			var mining_targets := bodies.filter(func(b):
				return b.get("kind") == "asteroid_belt" or (b.get("resources", []).size() > 0)
			)
			if !mining_targets.is_empty():
				return _orbit_position_near_body(mining_targets[0], rng, 0.5)
			else:
				return _random_orbit_position(rng, 15.0, 30.0)
		"observation_post", "research_lab":
			return _random_orbit_position(rng, 40.0, 60.0)
		"naval_station", "corporate_hq":
			return _random_orbit_position(rng, 8.0, 25.0)
		_:
			return _random_orbit_position(rng, 8.0, 20.0)

func _orbit_position_near_body(body: Dictionary, rng: RandomNumberGenerator, offset_au: float = 0.5) -> Vector2:
	var orbit_data:Dictionary = body.get("orbit", {})
	var radius_au:float = orbit_data.get("a_AU", 5.0)
	var angle:float = orbit_data.get("angle_rad", rng.randf() * TAU)
	var offset_angle:float = angle + rng.randf_range(-0.3, 0.3)
	var offset_radius:float = radius_au + offset_au + rng.randf_range(-0.2, 0.2)
	var AU_TO_PIXELS := 4000.0
	return Vector2(cos(offset_angle), sin(offset_angle)) * offset_radius * AU_TO_PIXELS

func _random_orbit_position(rng: RandomNumberGenerator, min_au: float, max_au: float) -> Vector2:
	var angle := rng.randf() * TAU
	var radius := rng.randf_range(min_au, max_au)
	var AU_TO_PIXELS := 4000.0
	return Vector2(cos(angle), sin(angle)) * radius * AU_TO_PIXELS

func _create_station_data(id: String, station_type: Dictionary, position: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	# Variant selection
	var variants := int(station_type.get("variants", 1))
	variants = max(variants, 1)
	var variant := rng.randi_range(1, variants)
	
	# Size selection (pixels) from range
	var size_px := 256.0
	if station_type.has("size_px_range"):
		var r:Array = station_type["size_px_range"]
		if typeof(r) == TYPE_ARRAY and r.size() == 2:
			size_px = rng.randf_range(float(r[0]), float(r[1]))
	
	# Build sprite path from asset_pattern
	var sprite_path := _asset_pattern
	sprite_path = sprite_path.replace("{type}", String(station_type.get("id","station")))
	sprite_path = sprite_path.replace("{variant}", "%02d" % variant)
	
	# Compose services directly from JSON
	var services: Array = station_type.get("services", [])
	
	var station_data := {
		"id": id,
		"type": station_type.get("id",""),
		"name": _generate_station_name(station_type.get("id",""), rng),
		"faction_id": "",
		"variant": variant,
		"position": [position.x, position.y],
		"services": services,
		"broadcast": _generate_broadcast_message(station_type.get("id",""), rng),
		"sprite_path": sprite_path,
		"size_px": size_px,
		"color_hints": station_type.get("color_hints", []),
		"can_dock": bool(station_type.get("can_dock", true)),
		"docking_ports": int(station_type.get("docking_ports", 0)),
		"population_range": station_type.get("population_range", [0,0]),
		"tech_level": station_type.get("tech_level", "standard"),
		"market_tier": int(station_type.get("market_tier", 0)),
		"repair_tier": int(station_type.get("repair_tier", 0)),
		"shipyard_tier": int(station_type.get("shipyard_tier", 0)),
		"security_level": int(station_type.get("security_level", 0)),
		"faction_bias": station_type.get("faction_bias", "neutral"),
		"inhabitant_data": {}  # Will be filled by _add_station_inhabitant_data
	}
	
	return station_data

# ---- Helper functions ----

func _generate_station_name(type_id: String, rng: RandomNumberGenerator) -> String:
	var prefixes := ["Alpha","Beta","Gamma","Delta","Epsilon","Station","Hub","Post"]
	var suffixes := ["Prime","Station","Outpost","Complex","Terminal","Port","Depot"]
	match type_id:
		"warp_gate":
			return "%s Gate" % prefixes[rng.randi_range(0, prefixes.size()-1)]
		"habitat":
			return "%s Habitat" % prefixes[rng.randi_range(0, prefixes.size()-1)]
		"trading_station":
			return "%s Trade Hub" % prefixes[rng.randi_range(0, prefixes.size()-1)]
		"shipyard":
			return "%s Shipyard" % prefixes[rng.randi_range(0, prefixes.size()-1)]
		_:
			return "%s %s" % [prefixes[rng.randi_range(0, prefixes.size()-1)], suffixes[rng.randi_range(0, suffixes.size()-1)]]

func _generate_broadcast_message(type_id: String, rng: RandomNumberGenerator) -> String:
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
	var type_messages:Array = messages.get(type_id, [])
	if type_messages.is_empty():
		return ""
	return type_messages[rng.randi_range(0, type_messages.size()-1)]

func _find_station_type(types: Array, type_id: String) -> Dictionary:
	for t in types:
		if t.get("id","") == type_id:
			return t
	return {}

func _generate_stations_fallback(rng: RandomNumberGenerator, pop_level: int, tech_level: int, mining_quality: int) -> Array:
	var stations := []
	if pop_level >= 5 and tech_level >= 3:
		stations.append({"id":"station:gate","type":"warp_gate","name":"System Gate","variant":0,"position":[0,0],"services":["warp"],"broadcast":"","inhabitant_data":{"is_inhabited":true,"population":50,"faction_id":"","settlement_type":"station","has_spaceport":true,"tech_level":3}})
	if mining_quality >= 6:
		stations.append({"id":"station:refinery","type":"ore_refinery","name":"Ore Processing","variant":0,"position":[20000,10000],"services":["dock","sell_ore"],"broadcast":"","inhabitant_data":{"is_inhabited":true,"population":30,"faction_id":"","settlement_type":"station","has_spaceport":true,"tech_level":2}})
	return stations

func _calculate_station_budget(pop_level: int, tech_level: int) -> int:
	var base_count = pop_level / 2
	var tech_bonus = tech_level / 3
	return clampi(base_count + tech_bonus, 1, 12)

func _categorize_stations_by_bias(types: Array, pop_level: int) -> Dictionary:
	var categorized = {
		"very_high": [],
		"high": [],
		"medium": [],
		"low": [],
		"any": []
	}
	for type in types:
		var bias = type.get("pop_bias", "any")
		if bias in categorized:
			categorized[bias].append(type)
	return categorized

func _get_all_available_types(available_by_bias: Dictionary, pop_level: int) -> Array:
	var available: Array = []
	if pop_level >= 8:
		available += available_by_bias["very_high"]
		available += available_by_bias["high"]
	elif pop_level >= 6:
		available += available_by_bias["high"]
		available += available_by_bias["medium"]
	elif pop_level >= 3:
		available += available_by_bias["medium"]
		available += available_by_bias["low"]
	else:
		available += available_by_bias["low"]
	available += available_by_bias["any"]
	return available
