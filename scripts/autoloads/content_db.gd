extends Node

# Loaded schemas
var star_types: Dictionary = {}
var planet_types: Dictionary = {}
var moon_types: Dictionary = {}
var asteroid_types: Dictionary = {}
var biomes: Dictionary = {}
var phenomena: Dictionary = {}
var system_archetypes: Dictionary = {}
var sector_profiles: Dictionary = {}
var travel_lanes: Dictionary = {}

# Ship data
var ship_types: Dictionary = {}          # raw JSON
var ship_types_by_id: Dictionary = {}    # id -> ship dict
var hull_visuals: Dictionary = {}        # raw JSON
var hull_visuals_by_id: Dictionary = {}  # hull_class_id -> hull visual dict

# Asset validation
var missing_assets: Array = []

const SHIP_SPRITE_PATTERN := "res://assets/images/actors/ships/{type}_{variant}.png"

func _ready() -> void:
	_load_all_schemas()
	_validate_assets()
	if missing_assets.size() > 0:
		push_warning("ContentDB: %d missing assets detected" % missing_assets.size())
		for a in missing_assets:
			push_warning("\tMissing: %s" % a)

func _load_all_schemas() -> void:
	star_types     = _load_json("res://data/procgen/star_types.json")
	planet_types   = _load_json("res://data/procgen/planet_types.json")
	moon_types     = _load_json("res://data/procgen/moon_types.json")
	asteroid_types = _load_json("res://data/procgen/asteroid_types.json")
	biomes         = _load_json("res://data/procgen/biomes.json")
	phenomena      = _load_json("res://data/procgen/phenomena.json")
	system_archetypes = _load_json("res://data/procgen/system_archetypes.json")
	sector_profiles = _load_json("res://data/procgen/sector_profiles.json")
	travel_lanes   = _load_json("res://data/procgen/travel_lanes.json")
	
	ship_types     = _load_json("res://data/components/ship_types_v2.json")
	hull_visuals   = _load_json("res://data/components/hull_visuals.json")

	_build_ship_type_index()
	_build_hull_visual_index()

	print("ContentDB: All schemas loaded")

func _load_json(path: String) -> Dictionary:
	if !FileAccess.file_exists(path):
		push_error("ContentDB: File not found: %s" % path)
		return {}
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ContentDB: Failed to open file: %s" % path)
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		push_error("ContentDB: Failed to parse JSON in %s" % path)
		return {}
	
	return json.data

func _build_ship_type_index() -> void:
	ship_types_by_id.clear()
	for st in ship_types.get("ships", []):
		if typeof(st) != TYPE_DICTIONARY:
			continue
		var id := str(st.get("id", ""))
		if id == "":
			continue
		ship_types_by_id[id] = st


func _build_hull_visual_index() -> void:
	hull_visuals_by_id.clear()
	for hv in hull_visuals.get("hulls", []):
		if typeof(hv) != TYPE_DICTIONARY:
			continue
		var id := str(hv.get("id", ""))
		if id == "":
			continue
		hull_visuals_by_id[id] = hv


func _derive_sprite_type_from_hull_id(hull_id: String) -> String:
	if hull_id.begins_with("hull_"):
		return hull_id.substr(5, hull_id.length() - 5)
	return hull_id

func get_ship_sprite_info(ship_type_id: String, variant: int = -1) -> Dictionary:
	var st: Dictionary = ship_types_by_id.get(ship_type_id, {})
	if st.is_empty():
		return _build_fallback_ship_sprite_info(ship_type_id, variant)

	var hull_id: String = str(st.get("hull_class_id", ""))
	if hull_id == "":
		return _build_fallback_ship_sprite_info(ship_type_id, variant)

	var hv: Dictionary = hull_visuals_by_id.get(hull_id, {})
	var defaults: Dictionary = hull_visuals.get("defaults", {})

	var sprite_type: String = ""
	if hv.is_empty():
		sprite_type = _derive_sprite_type_from_hull_id(hull_id)
	else:
		sprite_type = str(hv.get("sprite_type", ""))
		if sprite_type == "":
			sprite_type = _derive_sprite_type_from_hull_id(hull_id)

	var num_variants: int = 1
	if hv.is_empty():
		num_variants = int(defaults.get("num_variants", 1))
	else:
		num_variants = int(hv.get("num_variants", defaults.get("num_variants", 1)))

	if num_variants < 1:
		num_variants = 1

	var v: int = int(variant)
	if v <= 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		v = rng.randi_range(1, num_variants)
	if v < 1:
		v = 1
	if v > num_variants:
		v = num_variants

	var path := SHIP_SPRITE_PATTERN.format({
		"type": sprite_type,
		"variant": "%02d" % v,
	})

	return {
		"ship_type_id": ship_type_id,
		"hull_class_id": hull_id,
		"sprite_type": sprite_type,
		"variant": v,
		"path": path,
	}


func _build_fallback_ship_sprite_info(ship_type_id: String, variant: int) -> Dictionary:
	var defaults: Dictionary = hull_visuals.get("defaults", {})
	var num_variants: int = int(defaults.get("num_variants", 1))
	if num_variants < 1:
		num_variants = 1

	var v: int = int(variant)
	if v <= 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		v = rng.randi_range(1, num_variants)
	if v < 1:
		v = 1
	if v > num_variants:
		v = num_variants

	var sprite_type := ship_type_id
	var path := SHIP_SPRITE_PATTERN.format({
		"type": sprite_type,
		"variant": "%02d" % v,
	})

	return {
		"ship_type_id": ship_type_id,
		"hull_class_id": "",
		"sprite_type": sprite_type,
		"variant": v,
		"path": path,
	}


func get_ship_sprite_path(ship_type_id: String, variant: int = -1) -> String:
	var info := get_ship_sprite_info(ship_type_id, variant)
	return str(info.get("path", ""))


func _validate_assets() -> void:
	# Validate star sprites
	for color in star_types.get("colors", []):
		for variant in range(1, star_types.get("variants_per_color", 4) + 1):
			var pattern = star_types.get("sprite_resolver", {}).get("pattern", "")
			var path = pattern.format({"color": color, "variant": variant})
			if !ResourceLoader.exists(path):
				missing_assets.append(path)
	
	# Validate planet sprites
	for planet_type in planet_types.get("types", []):
		var type_id = planet_type.get("id", "")
		var variants = planet_type.get("variants", 3)
		for variant in range(1, variants + 1):
			var pattern = planet_types.get("asset_pattern", "")
			var path = pattern.format({"type": type_id, "variant": variant})
			if !ResourceLoader.exists(path):
				missing_assets.append(path)
	
	# Validate asteroid sprites
	for i in range(1, asteroid_types.get("variants", 6) + 1):
		var pattern = asteroid_types.get("asset_pattern", "")
		var path = pattern.format({"nn": "%02d" % i})
		if !ResourceLoader.exists(path):
			missing_assets.append(path)

	# Validate ship hull sprites if hull_visuals is present
	if !hull_visuals.is_empty():
		var defaults: Dictionary = hull_visuals.get("defaults", {})
		var default_variants: int = int(defaults.get("num_variants", 1))
		if default_variants < 1:
			default_variants = 1

		for hv in hull_visuals.get("hulls", []):
			if typeof(hv) != TYPE_DICTIONARY:
				continue

			var hull_id: String = str(hv.get("id", ""))
			if hull_id == "":
				continue

			var sprite_type: String = str(hv.get("sprite_type", ""))
			if sprite_type == "":
				sprite_type = _derive_sprite_type_from_hull_id(hull_id)

			var num_variants: int = int(hv.get("num_variants", default_variants))
			if num_variants < 1:
				num_variants = 1

			for v in range(1, num_variants + 1):
				var path := SHIP_SPRITE_PATTERN.format({
					"type": sprite_type,
					"variant": "%02d" % v,
				})
				if !ResourceLoader.exists(path):
					missing_assets.append(path)


func get_star_sprite(spectral_class: String, rng: RandomNumberGenerator) -> String:
	var color = star_types.get("class_to_color", {}).get(spectral_class, "white")
	var variant = rng.randi_range(1, star_types.get("variants_per_color", 4))
	var pattern = star_types.get("sprite_resolver", {}).get("pattern", "")
	var path = pattern.format({"color": color, "variant": variant})
	
	if ResourceLoader.exists(path):
		return path
	else:
		return star_types.get("sprite_resolver", {}).get("fallback", "")

func get_planet_sprite(type_id: String, rng: RandomNumberGenerator) -> String:
	for planet_type in planet_types.get("types", []):
		if planet_type.get("id") == type_id:
			var variant = rng.randi_range(1, planet_type.get("variants", 3))
			var pattern = planet_types.get("asset_pattern", "")
			return pattern.format({"type": type_id, "variant": variant})
	return ""

func get_moon_sprite(moon_type: String, rng: RandomNumberGenerator) -> String:
	"""Get sprite path for a moon type with random variant"""
	if moon_types.is_empty():
		push_warning("ContentDB: Moon types not loaded")
		return ""
	
	var types: Array = moon_types.get("types", [])
	var moon_data: Dictionary = {}
	
	# Find the moon type
	for mt in types:
		if mt.get("id", "") == moon_type:
			moon_data = mt
			break
	
	if moon_data.is_empty():
		push_warning("ContentDB: Moon type '%s' not found" % moon_type)
		return ""
	
	var variants: int = moon_data.get("variants", 1)
	var variant: int = rng.randi_range(0, variants - 1)
	
	var asset_pattern: String = moon_types.get("asset_pattern", "res://assets/images/stellar_bodies/moons/moon_{type}_{variant}.png")
	var sprite_path := asset_pattern.replace("{type}", moon_type)
	sprite_path = sprite_path.replace("{variant}", "%02d" % variant)
	
	return sprite_path


func get_asteroid_sprite(rng: RandomNumberGenerator) -> String:
	var variant = rng.randi_range(1, asteroid_types.get("variants", 6))
	var pattern = asteroid_types.get("asset_pattern", "")
	return pattern.format({"nn": "%02d" % variant})

func get_random_archetype(rng: RandomNumberGenerator, filters: Dictionary = {}) -> Dictionary:
	var valid_archetypes = []
	for archetype in system_archetypes.get("archetypes", []):
		var matches = true
		for key in filters:
			if key in archetype and archetype[key] != filters[key]:
				matches = false
				break
		if matches:
			valid_archetypes.append(archetype)
	
	if valid_archetypes.is_empty():
		return {}
	
	return valid_archetypes[rng.randi_range(0, valid_archetypes.size() - 1)]

func get_sector_profile(biome_id: String) -> Dictionary:
	for profile in sector_profiles.get("profiles", []):
		if profile.get("biome") == biome_id:
			return profile
	return {}

func get_travel_lane(lane_id: String) -> Dictionary:
	for lane in travel_lanes.get("lanes", []):
		if lane.get("id") == lane_id:
			return lane
	return {}

func get_planet_moon_range(planet_type: String) -> Array:
	"""Get the num_moons_range for a planet type from planet_types data"""
	# This assumes you have a planet_types dictionary loaded similar to moon_types
	# If planet data is structured differently, adjust accordingly
	
	if !planet_types.has("types"):
		return [0, 0]  # No moons if planet types not loaded
	
	var types: Array = planet_types.get("types", [])
	
	for pt in types:
		if pt.get("id", "") == planet_type:
			return pt.get("num_moons_range", [0, 0])
	
	# Default fallback based on planet type if not in JSON
	match planet_type:
		"gas":
			return [2, 8]  # Gas giants have many moons
		"ice_world":
			return [1, 4]  # Ice worlds can have several moons
		"terran", "primordial", "ocean_world":
			return [0, 2]  # Habitable worlds typically have 0-2 moons
		"rocky", "barren":
			return [0, 1]  # Rocky worlds might have one moon
		"volcanic":
			return [0, 1]  # Volcanic worlds rarely have moons
		_:
			return [0, 1]  # Default: 0-1 moons
