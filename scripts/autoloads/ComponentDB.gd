# res://scripts/systems/components/ComponentDB.gd
extends Node
#class_name ComponentDB

# Component database for Star Loafer.
# - Loads a JSON file (components.json).
# - Stores definitions keyed by canonical ID: "type__local_name".
# - Accepts legacy IDs like "reactor_fission_mk1" or "reactor/fission_mk1"
#   and normalizes them to "reactor__fission_mk1".
#
# Public API:
#   load_all(json_path: String) -> void
#   get_def(id_in: String) -> Dictionary
#   has(id_in: String) -> bool
#   validate_type(id_in: String, expected_type: String) -> bool
#
# Convenience helpers:
#   get_all_components() -> Array[Dictionary]
#   get_all_ids() -> Array[String]
#   get_components_by_type(type: String) -> Array[Dictionary]
#   get_component_ids_by_type(type: String) -> Array[String]
#   get_components_filtered(filters: Dictionary) -> Array[Dictionary]
#   get_random_component(filters: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary
#
# Supported filters for get_components_filtered():
#   "type": String or Array[String]
#   "min_tier": int
#   "max_tier": int
#   "min_tech_level": int
#   "max_tech_level": int
#   "max_space_cost": int
#   "tags": String or Array[String]
#   "tags_mode": "any" | "all" (defaults to "any")


var _by_id: Dictionary = {}
var _aliases: Dictionary = {}
var defaults: Dictionary = {}

const COMPONENT_SPRITE_PATH_TEMPLATE := "res://assets/images/ui/components/{type}_{variant}.png"

var _sprite_defaults: Dictionary = {
	"path_template": COMPONENT_SPRITE_PATH_TEMPLATE,
	"num_variants": 1,
}


func _ready() -> void:
	load_all("res://data/components/components.json")


# Canonical ID format:
#   "<type>__<local_name>"
# Examples:
#   "reactor__fission_mk1"
#   "drive__chem_impulse_mk1"
#
# Acceptable input forms that will normalize to canonical:
#   "reactor__fission_mk1"  -> "reactor__fission_mk1"
#   "reactor_fission_mk1"   -> "reactor__fission_mk1"
#   "reactor-fission_mk1"   -> "reactor__fission_mk1"
#   "reactor/fission_mk1"   -> "reactor__fission_mk1"
static func _canonicalize_id(id: String) -> String:
	var s := id.strip_edges()
	if s == "":
		return s

	# Already canonical? e.g. "reactor__fission_mk1"
	var idx := s.find("__")
	if idx != -1 and idx > 0 and idx < s.length() - 2:
		return s

	# Normalize obvious separators so we can treat left side as "type"
	s = s.replace("/", "_")
	s = s.replace("-", "_")

	# Split on first underscore: "<type>_<rest>" -> "<type>__<rest>"
	var parts := s.split("_", false, 1)
	if parts.size() == 2:
		var t := parts[0]
		var rest := parts[1]
		if t != "" and rest != "":
			return "%s__%s" % [t, rest]

	# Fallback: unknown format, return as-is
	return s

static func _derive_sprite_type_from_id(canon_id: String) -> String:
	# Convert canonical id like "reactor__fission_mk1" into "reactor_fission_mk1"
	var s := canon_id
	s = s.replace("/", "_")
	s = s.replace("__", "_")
	return s


func load_all(json_path: String) -> void:
	_by_id.clear()
	_aliases.clear()
	defaults.clear()

	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("ComponentDB: could not open %s (error %d)" % [json_path, FileAccess.get_open_error()])
		return

	var text := file.get_as_text()
	file.close()

	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("ComponentDB: invalid JSON root in %s" % json_path)
		return

	# Load defaults if present
	if data.has("defaults") and typeof(data["defaults"]) == TYPE_DICTIONARY:
		defaults = data["defaults"]

	# Load defaults if present
	if data.has("defaults") and typeof(data["defaults"]) == TYPE_DICTIONARY:
		defaults = data["defaults"]

	# Load sprite defaults if present
	if data.has("sprite_defaults") and typeof(data["sprite_defaults"]) == TYPE_DICTIONARY:
		var sd: Dictionary = data["sprite_defaults"]
		_sprite_defaults = {
			"path_template": str(sd.get("path_template", COMPONENT_SPRITE_PATH_TEMPLATE)),
			"num_variants": int(sd.get("num_variants", 1)),
		}
	else:
		_sprite_defaults = {
			"path_template": COMPONENT_SPRITE_PATH_TEMPLATE,
			"num_variants": 1,
		}

	# Resolve component array key: new 'components' or legacy 'component_types'
	var comp_array: Array = []

	if data.has("components") and typeof(data["components"]) == TYPE_ARRAY:
		comp_array = data["components"]
	elif data.has("component_types") and typeof(data["component_types"]) == TYPE_ARRAY:
		comp_array = data["component_types"]
		push_warning("ComponentDB: using legacy 'component_types' array in %s; please migrate to 'components'" % json_path)
	else:
		push_error("ComponentDB: no valid 'components' or 'component_types' array in %s" % json_path)
		return

	# Load all components
	for comp in comp_array:
		if typeof(comp) != TYPE_DICTIONARY:
			continue
		if not comp.has("id"):
			continue

		var raw_id: String = str(comp["id"])
		var canon_id := _canonicalize_id(raw_id)

		# Store a deep copy so we can safely mutate if needed.
		var stored: Dictionary = comp.duplicate(true)
		stored["id"] = canon_id
		_by_id[canon_id] = stored

		# Alias raw->canonical if they differ.
		if raw_id != canon_id:
			_aliases[raw_id] = canon_id

		# Also alias a couple of common variations if you ever construct
		# IDs by hand in older styles.
		var alias_single := canon_id.replace("__", "_")
		if alias_single != canon_id:
			_aliases[alias_single] = canon_id

		var alias_slash := canon_id.replace("__", "/")
		if alias_slash != canon_id:
			_aliases[alias_slash] = canon_id

	print("ComponentDB: Loaded %d components from %s" % [_by_id.size(), json_path])


func get_def(id_in: String) -> Dictionary:
	var cid := _canonicalize_id(id_in)

	# Direct lookup by canonical ID
	if _by_id.has(cid):
		return _by_id[cid]

	# Lookup by raw/alias, if we saw it during load
	if _aliases.has(id_in):
		var real_id: String = _aliases[id_in]
		if _by_id.has(real_id):
			return _by_id[real_id]

	# As a fallback, try alias map with canonicalized form as key
	if _aliases.has(cid):
		var real_id_2: String = _aliases[cid]
		if _by_id.has(real_id_2):
			return _by_id[real_id_2]

	return {}


func has(id_in: String) -> bool:
	return not get_def(id_in).is_empty()


func validate_type(id_in: String, expected_type: String) -> bool:
	var d := get_def(id_in)
	if d.is_empty():
		return false
	var t := str(d.get("type", ""))
	return t == expected_type


# -------------------------------------------------------------------
# Convenience helpers
# -------------------------------------------------------------------

func get_all_components() -> Array:
	# Returns an array of all component definitions (dictionaries).
	var result: Array = []
	for v in _by_id.values():
		if typeof(v) == TYPE_DICTIONARY:
			result.append(v)
	return result


func get_all_ids() -> Array:
	# Returns an array of all canonical component IDs (strings).
	var result: Array = []
	for k in _by_id.keys():
		result.append(str(k))
	return result


func get_components_by_type(type_name: String) -> Array:
	# Returns an array of component dictionaries of the given type.
	var result: Array = []
	for comp in _by_id.values():
		if typeof(comp) != TYPE_DICTIONARY:
			continue
		var t := str(comp.get("type", ""))
		if t == type_name:
			result.append(comp)
	return result


func get_component_ids_by_type(type_name: String) -> Array:
	# Returns an array of canonical IDs for components of the given type.
	var result: Array = []
	for k in _by_id.keys():
		var comp: Dictionary = _by_id[k]
		if typeof(comp) != TYPE_DICTIONARY:
			continue
		var t := str(comp.get("type", ""))
		if t == type_name:
			result.append(str(k))
	return result


func get_components_filtered(filters: Dictionary) -> Array:
	# Simple filter system for components.
	# Supported filters (all optional):
	#   "type": String or Array[String]
	#   "min_tier": int
	#   "max_tier": int
	#   "min_tech_level": int
	#   "max_tech_level": int
	#   "max_space_cost": int
	#   "tags": String or Array[String]
	#   "tags_mode": "any" | "all" (default "any")
	#
	# Example:
	#   var options := db.get_components_filtered({
	#       "type": "reactor",
	#       "max_tier": 2,
	#       "max_space_cost": 6,
	#       "tags": ["civilian", "starter"],
	#       "tags_mode": "any"
	#   })
	#
	var result: Array = []

	# Type filter
	var has_type_filter := filters.has("type")
	var allowed_types: Array = []
	if has_type_filter:
		if typeof(filters["type"]) == TYPE_STRING:
			allowed_types.append(str(filters["type"]))
		elif typeof(filters["type"]) == TYPE_ARRAY:
			for t in filters["type"]:
				allowed_types.append(str(t))

	# Tier filter
	var has_min_tier := filters.has("min_tier")
	var has_max_tier := filters.has("max_tier")
	var min_tier := 0
	var max_tier := 0
	if has_min_tier:
		min_tier = int(filters["min_tier"])
	if has_max_tier:
		max_tier = int(filters["max_tier"])

	# Tech level filter
	var has_min_tech := filters.has("min_tech_level")
	var has_max_tech := filters.has("max_tech_level")
	var min_tech := 0
	var max_tech := 0
	if has_min_tech:
		min_tech = int(filters["min_tech_level"])
	if has_max_tech:
		max_tech = int(filters["max_tech_level"])

	# Space cost filter
	var has_max_space := filters.has("max_space_cost")
	var max_space := 0
	if has_max_space:
		max_space = int(filters["max_space_cost"])

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

	for comp in _by_id.values():
		if typeof(comp) != TYPE_DICTIONARY:
			continue

		# Type filter
		if has_type_filter:
			var t := str(comp.get("type", ""))
			if not _type_in_allowed(t, allowed_types):
				continue

		# Tier filter
		if has_min_tier or has_max_tier:
			var tier := int(comp.get("tier", 0))
			if has_min_tier and tier < min_tier:
				continue
			if has_max_tier and tier > max_tier:
				continue

		# Tech level filter
		if has_min_tech or has_max_tech:
			var tech_level := int(comp.get("tech_level", 0))
			if has_min_tech and tech_level < min_tech:
				continue
			if has_max_tech and tech_level > max_tech:
				continue

		# Space cost filter
		if has_max_space:
			var space_cost := int(comp.get("space_cost", 0))
			if space_cost > max_space:
				continue

		# Tags filter
		if has_tags_filter and not _component_matches_tags(comp, required_tags, tags_mode):
			continue

		result.append(comp)

	return result


func get_random_component(filters: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	# Returns a single random component that matches the given filters.
	# Uses get_components_filtered() under the hood.
	#
	# If rng is null, a local RNG is created and randomized.
	#
	# Returns {} if no matching components exist.
	var candidates := get_components_filtered(filters)
	if candidates.is_empty():
		return {}

	var local_rng: RandomNumberGenerator = rng
	if local_rng == null:
		local_rng = RandomNumberGenerator.new()
		local_rng.randomize()

	var idx := local_rng.randi_range(0, candidates.size() - 1)
	var comp: Dictionary = candidates[idx]
	return comp

func get_component_sprite_info(id_in: String, variant: int = 1) -> Dictionary:
	# Returns:
	# {
	#   "type": "reactor_fission_mk1",
	#   "variant": 1,
	#   "path": "res://assets/images/ui/components/reactor_fission_mk1_01.png"
	# }
	var def := get_def(id_in)
	if def.is_empty():
		return {}

	var canon_id: String = str(def.get("id", ""))
	var sprite_data: Dictionary = {}
	if def.has("sprite") and typeof(def["sprite"]) == TYPE_DICTIONARY:
		sprite_data = def["sprite"]

	var sprite_type := ""
	if sprite_data.has("type"):
		sprite_type = str(sprite_data["type"])
	else:
		sprite_type = _derive_sprite_type_from_id(canon_id)

	var num_variants: int = 1
	if sprite_data.has("num_variants"):
		num_variants = int(sprite_data["num_variants"])
	else:
		num_variants = int(_sprite_defaults.get("num_variants", 1))

	if num_variants < 1:
		num_variants = 1

	var v := int(variant)
	if v < 1:
		v = 1
	if v > num_variants:
		v = num_variants

	var pattern: String = COMPONENT_SPRITE_PATH_TEMPLATE
	if sprite_data.has("path_template"):
		pattern = str(sprite_data["path_template"])
	else:
		pattern = str(_sprite_defaults.get("path_template", COMPONENT_SPRITE_PATH_TEMPLATE))

	var path := pattern.format({
		"type": sprite_type,
		"variant": "%02d" % v,
	})

	return {
		"type": sprite_type,
		"variant": v,
		"path": path,
	}


func get_component_sprite_path(id_in: String, variant: int = 1) -> String:
	var info := get_component_sprite_info(id_in, variant)
	return info.get("path", "")


# -------------------------------------------------------------------
# Internal helpers (non-API)
# -------------------------------------------------------------------

func _type_in_allowed(t: String, allowed_types: Array) -> bool:
	for at in allowed_types:
		if t == str(at):
			return true
	return false


func _component_matches_tags(comp: Dictionary, required_tags: Array, mode: String) -> bool:
	if required_tags.is_empty():
		return true

	var comp_tags: Array = []
	if comp.has("tags"):
		if typeof(comp["tags"]) == TYPE_ARRAY:
			for tag in comp["tags"]:
				comp_tags.append(str(tag))
		elif typeof(comp["tags"]) == TYPE_STRING:
			comp_tags.append(str(comp["tags"]))

	if comp_tags.is_empty():
		return false

	if mode == "all":
		# All required_tags must be present
		for rt in required_tags:
			var found := false
			for ct in comp_tags:
				if str(ct) == str(rt):
					found = true
					break
			if not found:
				return false
		return true
	else:
		# "any" mode: at least one required tag must be present
		for rt2 in required_tags:
			for ct2 in comp_tags:
				if str(ct2) == str(rt2):
					return true
		return false
