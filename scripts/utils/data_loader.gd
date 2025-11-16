extends RefCounted
class_name DataLoader

## Utility class for loading and validating JSON data files
## Handles all the boilerplate of file I/O and JSON parsing

const MAX_JSON_SIZE: int = 100000  # 100KB limit for safety

## ============================================================
## JSON LOADING
## ============================================================

static func load_json_file(path: String) -> Dictionary:
	"""
	Load and parse a JSON file
	Returns empty Dictionary on error
	"""
	# Check file exists
	if !FileAccess.file_exists(path):
		push_warning("DataLoader: File not found: %s" % path)
		return {}
	
	# Open file
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DataLoader: Failed to open file: %s (Error: %d)" % [path, FileAccess.get_open_error()])
		return {}
	
	# Read content
	var json_text := file.get_as_text()
	file.close()
	
	# Validate size
	if json_text.is_empty():
		push_error("DataLoader: File is empty: %s" % path)
		return {}
	
	if json_text.length() > MAX_JSON_SIZE:
		push_error("DataLoader: File too large: %s (%d bytes)" % [path, json_text.length()])
		return {}
	
	# Parse JSON
	var json := JSON.new()
	var error := json.parse(json_text)
	
	if error != OK:
		push_error("DataLoader: JSON parse error in %s: %s (line %d)" % [
			path,
			json.get_error_message(),
			json.get_error_line()
		])
		return {}
	
	# Validate result is a dictionary
	if typeof(json.data) != TYPE_DICTIONARY:
		push_error("DataLoader: JSON root must be a dictionary in: %s" % path)
		return {}
	
	return json.data

## ============================================================
## TYPED DATA LOADING
## ============================================================

static func load_types_data(path: String, type_name: String) -> Dictionary:
	"""
	Load types data (planet_types, moon_types, station_types, etc.)
	Returns dictionary with 'types' array and 'asset_pattern' string
	"""
	var data := load_json_file(path)
	
	if data.is_empty():
		return {}
	
	# Validate structure
	if !data.has("types"):
		push_warning("DataLoader: No 'types' array in %s" % path)
		return {}
	
	if typeof(data["types"]) != TYPE_ARRAY:
		push_error("DataLoader: 'types' must be an array in %s" % path)
		return {}
	
	print("DataLoader: Loaded %d %s types from %s" % [
		data["types"].size(),
		type_name,
		path
	])
	
	return data

## ============================================================
## DATA VALIDATION
## ============================================================

static func validate_type_has_fields(type_data: Dictionary, required_fields: Array[String]) -> bool:
	"""
	Validate that a type entry has all required fields
	Returns true if valid, false otherwise
	"""
	for field in required_fields:
		if !type_data.has(field):
			push_warning("DataLoader: Type missing required field '%s': %s" % [
				field,
				type_data.get("id", "unknown")
			])
			return false
	return true

static func get_type_by_id(types_array: Array, type_id: String) -> Dictionary:
	"""Find a type entry by its ID"""
	for type_entry in types_array:
		if type_entry.get("id", "") == type_id:
			return type_entry
	return {}

static func filter_types_by_bias(types_array: Array, bias_filter: String) -> Array:
	"""Filter types array by pop_bias or other bias field"""
	var filtered: Array = []
	for type_entry in types_array:
		if type_entry.get("pop_bias", "any") == bias_filter:
			filtered.append(type_entry)
	return filtered

## ============================================================
## ASSET PATH HELPERS
## ============================================================

static func resolve_asset_path(pattern: String, type_id: String, variant: int) -> String:
	"""
	Resolve an asset path pattern with substitutions
	Pattern example: "res://assets/images/stellar_bodies/planets/{type}_{variant}.png"
	"""
	var path := pattern
	path = path.replace("{type}", type_id)
	path = path.replace("{variant}", "%02d" % variant)
	return path

static func validate_asset_exists(path: String) -> bool:
	"""Check if an asset file exists"""
	return ResourceLoader.exists(path)

## ============================================================
## RANGE HELPERS
## ============================================================

static func get_random_from_range(range_array: Array, rng: RandomNumberGenerator, default_value: float = 0.0) -> float:
	"""
	Get random value from a range array [min, max]
	Returns default_value if range is invalid
	"""
	if typeof(range_array) != TYPE_ARRAY:
		return default_value
	
	if range_array.size() < 2:
		return default_value
	
	var min_val := float(range_array[0])
	var max_val := float(range_array[1])
	
	return rng.randf_range(min_val, max_val)

static func get_random_int_from_range(range_array: Array, rng: RandomNumberGenerator, default_value: int = 0) -> int:
	"""
	Get random integer from a range array [min, max]
	Returns default_value if range is invalid
	"""
	if typeof(range_array) != TYPE_ARRAY:
		return default_value
	
	if range_array.size() < 2:
		return default_value
	
	var min_val := int(range_array[0])
	var max_val := int(range_array[1])
	
	return rng.randi_range(min_val, max_val)

static func get_average_from_range(range_array: Array, default_value: float = 0.0) -> float:
	"""
	Get average value from a range array [min, max]
	Returns default_value if range is invalid
	"""
	if typeof(range_array) != TYPE_ARRAY:
		return default_value
	
	if range_array.size() < 2:
		return default_value
	
	var min_val := float(range_array[0])
	var max_val := float(range_array[1])
	
	return (min_val + max_val) / 2.0

## ============================================================
## ERROR RECOVERY
## ============================================================

static func get_safe_value(data: Dictionary, key: String, default_value: Variant) -> Variant:
	"""
	Safely get a value from dictionary with default fallback
	Type-checks the returned value against default_value type
	"""
	if !data.has(key):
		return default_value
	
	var value = data[key]
	var expected_type := typeof(default_value)
	var actual_type := typeof(value)
	
	if actual_type != expected_type:
		push_warning("DataLoader: Type mismatch for key '%s': expected %s, got %s" % [
			key,
			type_string(expected_type),
			type_string(actual_type)
		])
		return default_value
	
	return value

## ============================================================
## DEBUG UTILITIES
## ============================================================

static func print_data_summary(data: Dictionary, data_name: String) -> void:
	"""Print a summary of loaded data"""
	print("=== %s Data Summary ===" % data_name)
	print("  Schema: %s" % data.get("schema", "unknown"))
	print("  Types: %d" % data.get("types", []).size())
	
	if data.has("asset_pattern"):
		print("  Asset pattern: %s" % data["asset_pattern"])
	
	if data.has("enums"):
		print("  Enums: %d" % data["enums"].size())
	
	print("========================")

static func validate_data_structure(data: Dictionary, expected_schema: String = "") -> bool:
	"""
	Validate that data has expected structure
	Returns true if valid
	"""
	if data.is_empty():
		push_error("DataLoader: Data is empty")
		return false
	
	if !data.has("types"):
		push_error("DataLoader: Data missing 'types' array")
		return false
	
	if expected_schema != "" and data.get("schema", "") != expected_schema:
		push_warning("DataLoader: Schema mismatch. Expected '%s', got '%s'" % [
			expected_schema,
			data.get("schema", "unknown")
		])
		# Don't fail on schema mismatch, just warn
	
	return true
