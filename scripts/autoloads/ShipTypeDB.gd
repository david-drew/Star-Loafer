# res://scripts/systems/components/ShipTypeDB.gd
extends Node

# Ship Type database for Star Loafer.
# Loads ship definitions from ship_types_v2.json.
# Each ship has hull properties and stock component loadouts.
#
# Public API:
#   get_ship_def(id: String) -> Dictionary
#   has_ship(id: String) -> bool
#   get_all_ships() -> Array[Dictionary]
#   get_all_ship_ids() -> Array[String]
#   get_ships_by_category(category: String) -> Array[Dictionary]
#   get_ships_filtered(filters: Dictionary) -> Array[Dictionary]

var _by_id: Dictionary = {}

func _ready() -> void:
	load_all("res://data/components/ship_types_v2.json")


func load_all(json_path: String) -> void:
	_by_id.clear()
	
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("ShipTypeDB: could not open %s (error %d)" % [json_path, FileAccess.get_open_error()])
		return
	
	var text := file.get_as_text()
	file.close()
	
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("ShipTypeDB: invalid JSON root in %s" % json_path)
		return
	
	if not data.has("ships") or typeof(data["ships"]) != TYPE_ARRAY:
		push_error("ShipTypeDB: missing 'ships' array in %s" % json_path)
		return
	
	for ship in data["ships"]:
		if typeof(ship) != TYPE_DICTIONARY:
			continue
		if not ship.has("id"):
			push_warning("ShipTypeDB: ship definition missing 'id' field")
			continue
		
		var ship_id: String = str(ship["id"])
		_by_id[ship_id] = ship.duplicate(true)
	
	print("ShipTypeDB: Loaded %d ship types from %s" % [_by_id.size(), json_path])


func get_ship_def(id: String) -> Dictionary:
	if _by_id.has(id):
		return _by_id[id].duplicate(true)
	return {}


func has_ship(id: String) -> bool:
	return _by_id.has(id)


func get_all_ships() -> Array:
	var result: Array = []
	for ship in _by_id.values():
		if typeof(ship) == TYPE_DICTIONARY:
			result.append(ship.duplicate(true))
	return result


func get_all_ship_ids() -> Array:
	var result: Array = []
	for k in _by_id.keys():
		result.append(str(k))
	return result


func get_ships_by_category(category: String) -> Array:
	var result: Array = []
	for ship in _by_id.values():
		if typeof(ship) != TYPE_DICTIONARY:
			continue
		var cat := str(ship.get("category", ""))
		if cat == category:
			result.append(ship.duplicate(true))
	return result


func get_ships_filtered(filters: Dictionary) -> Array:
	# Supported filters:
	#   "category": String or Array[String]
	#   "size_category": String or Array[String]  (small/medium/large/capital)
	#   "min_tech_level": int
	#   "max_tech_level": int
	#   "max_base_value": int
	#   "tags": String or Array[String]
	#   "tags_mode": "any" | "all" (defaults to "any")
	#   "manufacturer": String or Array[String]
	#   "has_ai_core": bool
	
	var result: Array = []
	
	# Category filter
	var has_cat_filter := filters.has("category")
	var allowed_cats: Array = []
	if has_cat_filter:
		if typeof(filters["category"]) == TYPE_STRING:
			allowed_cats.append(str(filters["category"]))
		elif typeof(filters["category"]) == TYPE_ARRAY:
			for c in filters["category"]:
				allowed_cats.append(str(c))
	
	# Size category filter
	var has_size_filter := filters.has("size_category")
	var allowed_sizes: Array = []
	if has_size_filter:
		if typeof(filters["size_category"]) == TYPE_STRING:
			allowed_sizes.append(str(filters["size_category"]))
		elif typeof(filters["size_category"]) == TYPE_ARRAY:
			for s in filters["size_category"]:
				allowed_sizes.append(str(s))
	
	# Tech level filter
	var has_min_tech := filters.has("min_tech_level")
	var has_max_tech := filters.has("max_tech_level")
	var min_tech := 0
	var max_tech := 0
	if has_min_tech:
		min_tech = int(filters["min_tech_level"])
	if has_max_tech:
		max_tech = int(filters["max_tech_level"])
	
	# Base value filter
	var has_max_value := filters.has("max_base_value")
	var max_value := 0
	if has_max_value:
		max_value = int(filters["max_base_value"])
	
	# Tags filter
	var has_tags_filter := filters.has("tags")
	var required_tags: Array = []
	if has_tags_filter:
		if typeof(filters["tags"]) == TYPE_STRING:
			required_tags.append(str(filters["tags"]))
		elif typeof(filters["tags"]) == TYPE_ARRAY:
			for tag in filters["tags"]:
				required_tags.append(str(tag))
	
	var tags_mode := "any"
	if filters.has("tags_mode"):
		tags_mode = str(filters["tags_mode"]).to_lower()
		if tags_mode != "all":
			tags_mode = "any"
	
	# Manufacturer filter
	var has_mfg_filter := filters.has("manufacturer")
	var allowed_mfgs: Array = []
	if has_mfg_filter:
		if typeof(filters["manufacturer"]) == TYPE_STRING:
			allowed_mfgs.append(str(filters["manufacturer"]))
		elif typeof(filters["manufacturer"]) == TYPE_ARRAY:
			for m in filters["manufacturer"]:
				allowed_mfgs.append(str(m))
	
	# AI core filter
	var has_ai_filter := filters.has("has_ai_core")
	var require_ai := false
	if has_ai_filter:
		require_ai = bool(filters["has_ai_core"])
	
	for ship in _by_id.values():
		if typeof(ship) != TYPE_DICTIONARY:
			continue
		
		# Category filter
		if has_cat_filter:
			var cat := str(ship.get("category", ""))
			if not _value_in_allowed(cat, allowed_cats):
				continue
		
		# Size category filter
		if has_size_filter:
			var size := str(ship.get("size_category", ""))
			if not _value_in_allowed(size, allowed_sizes):
				continue
		
		# Tech level filter
		if has_min_tech or has_max_tech:
			var tech := int(ship.get("tech_level", 0))
			if has_min_tech and tech < min_tech:
				continue
			if has_max_tech and tech > max_tech:
				continue
		
		# Base value filter
		if has_max_value:
			var value := int(ship.get("base_value", 0))
			if value > max_value:
				continue
		
		# Tags filter
		if has_tags_filter and not _matches_tags(ship, required_tags, tags_mode):
			continue
		
		# Manufacturer filter
		if has_mfg_filter:
			var mfg := str(ship.get("manufacturer", ""))
			if not _value_in_allowed(mfg, allowed_mfgs):
				continue
		
		# AI core filter
		if has_ai_filter:
			var has_ai := bool(ship.get("ai_core", false))
			if has_ai != require_ai:
				continue
		
		result.append(ship.duplicate(true))
	
	return result


# -------------------------------------------------------------------
# Internal helpers
# -------------------------------------------------------------------

func _value_in_allowed(value: String, allowed: Array) -> bool:
	for a in allowed:
		if value == str(a):
			return true
	return false


func _matches_tags(ship: Dictionary, required_tags: Array, mode: String) -> bool:
	if required_tags.is_empty():
		return true
	
	var ship_tags: Array = []
	if ship.has("tags"):
		if typeof(ship["tags"]) == TYPE_ARRAY:
			for tag in ship["tags"]:
				ship_tags.append(str(tag))
		elif typeof(ship["tags"]) == TYPE_STRING:
			ship_tags.append(str(ship["tags"]))
	
	if ship_tags.is_empty():
		return false
	
	if mode == "all":
		# All required tags must be present
		for rt in required_tags:
			var found := false
			for st in ship_tags:
				if str(st) == str(rt):
					found = true
					break
			if not found:
				return false
		return true
	else:
		# "any" mode: at least one required tag must be present
		for rt in required_tags:
			for st in ship_tags:
				if str(st) == str(rt):
					return true
		return false
