extends Node
class_name SystemGenerator

# Station types data
var station_types_data: Dictionary = {}
var station_types_loaded: bool = false
var _asset_pattern: String = "res://assets/images/actors/stations/{type}_{variant}.png"

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

func generate(system_id: String, galaxy_seed: int, pop_level: int, tech_level: int, mining_quality: int) -> Dictionary:
	# Lazy load station types on first use
	if !station_types_loaded:
		_load_station_types()
		station_types_loaded = true
	
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

# -------------------- STARS & BODIES (unchanged) --------------------

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
	for i in range(planet_count):
		var orbit_radius := 2.0 + i * 4.0 + rng.randf_range(-1.0, 1.0)
		var planet_type := _select_planet_type(rng, orbit_radius)
		var orbit_angle := rng.randf() * TAU
		var body := {
			"id": "body:%d" % i,
			"kind": "planet",
			"type": planet_type,
			"orbit": {"parent": stars[0]["id"], "a_AU": orbit_radius, "angle_rad": orbit_angle, "period_days": _calculate_period(orbit_radius)},
			"sprite": ContentDB.get_planet_sprite(planet_type, rng),
			"resources": _roll_resources(rng, planet_type, mining_quality),
			"population": _calculate_planet_population(planet_type, pop_level)
		}
		bodies.append(body)
	if mining_quality >= 6:
		var belt_count := rng.randi_range(1, 2)
		for i in range(belt_count):
			var belt_radius: float
			if i == 0:
				belt_radius = rng.randf_range(15.0, 25.0)
			else:
				belt_radius = rng.randf_range(40.0, 60.0)

			bodies.append({"id":"belt:%d"%i,"kind":"asteroid_belt","orbit":{"parent":stars[0]["id"],"a_AU":belt_radius},"resources":_roll_resources(rng,"asteroid_belt",mining_quality)})
	return bodies

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

# -------------------- STATIONS (rewired to JSON) --------------------

func _generate_stations(rng: RandomNumberGenerator, bodies: Array, stars: Array, pop_level: int, tech_level: int, mining_quality: int) -> Array:
	var stations := []
	if station_types_data.is_empty():
		push_warning("SystemGenerator: No station types loaded, using fallback generation")
		return _generate_stations_fallback(rng, pop_level, tech_level, mining_quality)
	
	var types: Array = station_types_data.get("types", [])
	var station_counter := 0
	
	# Always spawn warp gate in high-pop/high-tech systems (using JSON def)
	if pop_level >= 5 and tech_level >= 3:
		var gate_type := _find_station_type(types, "warp_gate")
		if gate_type:
			var pos := _position_from_prefs_or_safe_ring(rng, gate_type, 8.0, 15.0) # AU ring fallback
			stations.append(_create_station_data("station:%d" % station_counter, gate_type, pos, rng))
			station_counter += 1
	
	var station_budget := _calculate_station_budget(pop_level, tech_level)
	var available_by_bias := _categorize_stations_by_bias(types, pop_level)
	var available_types := _get_all_available_types(available_by_bias, pop_level)
	
	if available_types.is_empty():
		print("SystemGenerator: No available station types for pop_level %d" % pop_level)
		return stations
	
	for i in range(station_budget):
		if station_counter >= 20:
			# hard cap to avoid overcrowding
			break
		
		var station_type: Dictionary = available_types[rng.randi() % available_types.size()]
		var position := _calculate_station_position_json(station_type, bodies, stars, rng)
		
		# Enforce minimum distance from star (>= 8000 px ≈ 2 AU)
		var MIN_DISTANCE_FROM_STAR := 8000.0
		if position.length() < MIN_DISTANCE_FROM_STAR:
			var ang := position.angle()
			position = Vector2(cos(ang), sin(ang)) * MIN_DISTANCE_FROM_STAR
		
		stations.append(_create_station_data("station:%d" % station_counter, station_type, position, rng))
		station_counter += 1
	
	print("SystemGenerator: Generated %d stations" % stations.size())
	return stations

func _position_from_prefs_or_safe_ring(rng: RandomNumberGenerator, station_type: Dictionary, min_au: float, max_au: float) -> Vector2:
	# Prefer JSON placement_prefs.orbit_radius_px_range if present
	var prefs:Dictionary = station_type.get("placement_prefs", {})
	if typeof(prefs) == TYPE_DICTIONARY and prefs.has("orbit_radius_px_range"):
		var r:Array = prefs["orbit_radius_px_range"]
		if typeof(r) == TYPE_ARRAY and r.size() == 2:
			var angle := rng.randf() * TAU
			var radius_px := rng.randf_range(float(r[0]), float(r[1]))
			return Vector2(cos(angle), sin(angle)) * radius_px
	# Fallback to AU ring
	return _random_orbit_position(rng, min_au, max_au)

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
	
	# Otherwise keep your previous per-type heuristics (AU), minimal change
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
	
	# Size selection (pixels) from range; pass as scalar for Station.gd to scale exactly
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
	
	# Pass through key fields so Station.gd can configure itself
	var station_data := {
		"id": id,
		"type": station_type.get("id",""),
		"name": _generate_station_name(station_type.get("id",""), rng),
		"faction_id": "", # filled by SystemExploration from system_data if needed
		"variant": variant,
		"position": [position.x, position.y],
		"services": services,
		"broadcast": _generate_broadcast_message(station_type.get("id",""), rng),
		
		# JSON-driven visuals/flags
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
		"faction_bias": station_type.get("faction_bias", "neutral")
	}
	
	return station_data

# ---- Existing helpers (names kept) ----

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
		stations.append({"id":"station:gate","type":"warp_gate","name":"System Gate","variant":0,"position":[0,0],"services":["warp"],"broadcast":""})
	if mining_quality >= 6:
		stations.append({"id":"station:refinery","type":"ore_refinery","name":"Ore Processing","variant":0,"position":[20000,10000],"services":["dock","sell_ore"],"broadcast":""})
	return stations

func _calculate_station_budget(pop_level: int, tech_level: int) -> int:
	"""Calculate how many stations to spawn"""
	var base_count = pop_level / 2  # 0-5 base stations
	var tech_bonus = tech_level / 3  # 0-3 tech bonus
	return clampi(base_count + tech_bonus, 1, 12)

func _categorize_stations_by_bias(types: Array, pop_level: int) -> Dictionary:
	"""Group station types by their pop_bias"""
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
	"""Get flat list of all available station types for this pop level"""
	var available: Array = []
	# Determine which bias levels are appropriate
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
	# Always include "any" bias types
	available += available_by_bias["any"]
	return available
