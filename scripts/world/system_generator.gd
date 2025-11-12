extends Node
class_name SystemGenerator

const SystemLayout = preload("res://scripts/systems/system_layout.gd")

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
	
	# Create spatial layout manager
	var layout := SystemLayout.new()
	
	# Generate stars (these are positioned separately in system_exploration)
	var stars := _generate_stars(rng)
	
	# Place stars in layout (assume they're at specific positions handled by system_exploration)
	# For layout purposes, we'll assume single star at origin (multi-star handled in system_exploration)
	for star in stars:
		layout.place_star(star, Vector2.ZERO)  # Placeholder, actual positioning in system_exploration
	
	# Generate bodies with layout validation
	var bodies := _generate_bodies_with_layout(rng, stars, pop_level, tech_level, mining_quality, layout)
	
	# Generate stations with layout validation
	var stations := _generate_stations_with_layout(rng, bodies, stars, pop_level, tech_level, mining_quality, layout)
	
	print("SystemGenerator: Layout summary:")
	layout.print_layout_summary()
	
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

func _generate_bodies_with_layout(rng: RandomNumberGenerator, stars: Array, pop_level: int, tech_level: int, mining_quality: int, layout: SystemLayout) -> Array:
	"""Generate bodies using the layout system for proper positioning"""
	var bodies := []
	
	# Increase planet count range (you wanted more planets)
	var planet_count := rng.randi_range(6, 14)
	if rng.randf() < 0.15:  # Increased chance of extra planets
		planet_count += rng.randi_range(2, 4)
	planet_count = clampi(planet_count, 3, 18)  # More generous range
	
	print("SystemGenerator: Generating %d planets..." % planet_count)
	
	# Generate and place planets
	for i in range(planet_count):
		var orbit_radius_au := 1.5 + i * 3.5 + rng.randf_range(-0.8, 0.8)  # Slightly tighter spacing
		var planet_type := _select_planet_type(rng, orbit_radius_au)
		var orbit_angle := rng.randf() * TAU
		
		var planet_data := {
			"id": "body:%d" % i,
			"kind": "planet",
			"type": planet_type,
			"orbit": {
				"parent": stars[0]["id"], 
				"a_AU": orbit_radius_au,  # Will be updated by layout
				"angle_rad": orbit_angle,  # Will be updated by layout
				"period_days": _calculate_period(orbit_radius_au)
			},
			"sprite": ContentDB.get_planet_sprite(planet_type, rng),
			"resources": _roll_resources(rng, planet_type, mining_quality),
			"population": _calculate_planet_population(planet_type, pop_level),
			"inhabitant_data": {}  # Will be filled later
		}
		
		# Use layout system to validate and adjust position
		var placed_planet := layout.place_planet(planet_data, orbit_radius_au, orbit_angle, rng)
		
		if not placed_planet.is_empty():
			bodies.append(placed_planet)
			
			# Generate moons for this planet
			var moons := _generate_moons_for_planet_with_layout(rng, placed_planet, i, pop_level, mining_quality, layout)
			bodies.append_array(moons)
		else:
			push_warning("SystemGenerator: Failed to place planet %d, skipping" % i)
	
	# Generate asteroid belts (these don't need collision checking as they're spread out)
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

func _generate_moons_for_planet_with_layout(rng: RandomNumberGenerator, planet: Dictionary, planet_index: int, pop_level: int, mining_quality: int, layout: SystemLayout) -> Array:
	"""Generate moons orbiting a planet using layout system"""
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
	
	var planet_id: String = planet.get("id", "body:0")
	
	for moon_idx in range(num_moons):
		var moon_type_data: Dictionary = _select_moon_type(rng, moon_types)
		if moon_type_data.is_empty():
			continue
		
		var moon_type: String = moon_type_data.get("id", "barren")
		
		# Get orbit radius from moon type data (in pixels)
		var orbit_range: Array = moon_type_data.get("orbit_radius_px_range", [400, 1200])
		var desired_orbit_radius_px: float = rng.randf_range(float(orbit_range[0]), float(orbit_range[1]))
		var desired_orbit_angle := rng.randf() * TAU
		
		# Calculate orbital period (moons orbit faster, days)
		var period_days := _calculate_moon_period(desired_orbit_radius_px)
		
		var moon_data := {
			"id": "moon:%d_%d" % [planet_index, moon_idx],
			"kind": "moon",
			"type": moon_type,
			"parent_id": planet_id,
			"orbit": {
				"parent": planet_id,
				"radius_px": desired_orbit_radius_px,  # Will be updated by layout
				"angle_rad": desired_orbit_angle,  # Will be updated by layout
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
		
		# Use layout system to place moon relative to planet
		var placed_moon := layout.place_moon_relative_to_planet(moon_data, planet_id, desired_orbit_radius_px, desired_orbit_angle, rng)
		
		if not placed_moon.is_empty():
			moons.append(placed_moon)
		else:
			push_warning("SystemGenerator: Failed to place moon %d for planet %s" % [moon_idx, planet_id])
	
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
		
		if kind == "planet" or kind == "moon":
			var population: int = body.get("population", 0)
			var is_inhabited := population > 0
			
			if is_inhabited:
				body["inhabitant_data"] = {
					"is_inhabited": true,
					"population": population,
					"faction_id": "",  # Will be set by SystemExploration
					"settlement_type": "colony" if kind == "planet" else "outpost",
					"has_spaceport": population >= 5,
					"tech_level": _calculate_settlement_tech_level(population, rng)
				}
			else:
				body["inhabitant_data"] = {
					"is_inhabited": false,
					"population": 0,
					"faction_id": "",
					"settlement_type": "none",
					"has_spaceport": false,
					"tech_level": 0
				}

func _calculate_settlement_tech_level(population: int, rng: RandomNumberGenerator) -> int:
	"""Calculate tech level based on population with some randomness"""
	var base_tech := clampi(population / 2, 1, 5)
	var variation := rng.randi_range(-1, 1)
	return clampi(base_tech + variation, 1, 7)

func _select_planet_type(rng: RandomNumberGenerator, orbit_radius_au: float) -> String:
	var types := ["rocky","barren","desert","ice","terran","ocean","gas","volcanic","toxic","thick_atmo"]
	if orbit_radius_au < 2.0:
		return ["volcanic","toxic","desert","rocky"][rng.randi_range(0,3)]
	elif orbit_radius_au < 4.0:
		return ["terran","ocean","rocky","desert","thick_atmo"][rng.randi_range(0,4)]
	elif orbit_radius_au < 10.0:
		return ["gas","ice","rocky","thick_atmo"][rng.randi_range(0,3)]
	else:
		return ["ice","gas","barren"][rng.randi_range(0,2)]

func _calculate_planet_population(planet_type: String, system_pop_level: int) -> int:
	var base_pop := system_pop_level
	match planet_type:
		"terran":
			base_pop += 3
		"ocean":
			base_pop += 2
		"thick_atmo":
			base_pop += 1
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

func _generate_stations_with_layout(rng: RandomNumberGenerator, bodies: Array, stars: Array, pop_level: int, tech_level: int, mining_quality: int, layout: SystemLayout) -> Array:
	"""Generate stations using layout system for proper positioning"""
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
	
	print("SystemGenerator: Attempting to place %d stations..." % budget)
	
	var station_counter := 0
	var failed_placements := 0
	
	for _i in range(budget):
		if available.is_empty():
			break
		
		# Select station type
		var station_type: Dictionary = available[rng.randi_range(0, available.size() - 1)]
		var placement_prefs: Dictionary = station_type.get("placement_prefs", {})
		
		# Create base station data
		var station_id := "station:%d" % station_counter
		var station_data := _create_station_data_base(station_id, station_type, rng)
		
		# Use layout system to place station
		var placed_station := layout.place_station(station_data, placement_prefs, bodies, rng)
		
		if not placed_station.is_empty():
			# Add inhabitant data
			_add_station_inhabitant_data(placed_station, station_type, rng)
			stations.append(placed_station)
			station_counter += 1
		else:
			failed_placements += 1
			push_warning("SystemGenerator: Failed to place station of type '%s'" % station_type.get("id", "unknown"))
	
	if failed_placements > 0:
		print("SystemGenerator: Placed %d/%d stations (%d failed)" % [stations.size(), budget, failed_placements])
	else:
		print("SystemGenerator: Successfully placed all %d stations" % stations.size())
	
	return stations

func _create_station_data_base(id: String, station_type: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	"""Create base station data without position (position added by layout)"""
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
		"position": [0, 0],  # Will be set by layout
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
