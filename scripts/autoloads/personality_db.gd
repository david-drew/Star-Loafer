extends Node
class_name PersonalityDB

const PERSONALITIES_PATH := "res://data/ai/personalities.json"

var _profiles: Dictionary = {}
var _loaded: bool = false

func _ready() -> void:
	_load_profiles()

func _load_profiles() -> void:
	_profiles.clear()
	var file := FileAccess.open(PERSONALITIES_PATH, FileAccess.READ)
	if file == null:
		push_warning("PersonalityDB: Could not open file at %s" % PERSONALITIES_PATH)
		return

	var text := file.get_as_text()
	var result:Variant = JSON.parse_string(text)
	if typeof(result) != TYPE_ARRAY:
		push_warning("PersonalityDB: Expected JSON array at root of personalities.json")
		return

	for profile in result:
		if typeof(profile) != TYPE_DICTIONARY:
			continue
		var profile_id:String = profile.get("profile_id", "")
		if profile_id == "":
			continue
		_profiles[profile_id] = profile

	_loaded = true
	print("PersonalityDB: Loaded %d personality profiles" % _profiles.size())

func get_profile(profile_id: String) -> Dictionary:
	if not _loaded:
		_load_profiles()

	if _profiles.has(profile_id):
		return _profiles[profile_id]
	return {}

func has_profile(profile_id: String) -> bool:
	if not _loaded:
		_load_profiles()
	return _profiles.has(profile_id)

func get_all_profiles() -> Dictionary:
	if not _loaded:
		_load_profiles()
	return _profiles
