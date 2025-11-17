extends Node
class_name RoleDB

const ROLES_PATH := "res://data/ai/roles.json"

var _roles: Dictionary = {}
var _loaded: bool = false

func _ready() -> void:
	_load_roles()

func _load_roles() -> void:
	_roles.clear()
	var file := FileAccess.open(ROLES_PATH, FileAccess.READ)
	if file == null:
		push_warning("RoleDB: Could not open roles file at %s" % ROLES_PATH)
		return

	var text := file.get_as_text()
	var result:Variant = JSON.parse_string(text)
	if typeof(result) != TYPE_ARRAY:
		push_warning("RoleDB: Expected JSON array at root of roles.json")
		return

	for role_data in result:
		if typeof(role_data) != TYPE_DICTIONARY:
			continue
		var role_id:String = role_data.get("role_id", "")
		if role_id == "":
			continue
		_roles[role_id] = role_data

	_loaded = true
	print("RoleDB: Loaded %d role definitions" % _roles.size())

func get_role(role_id: String) -> Dictionary:
	if not _loaded:
		_load_roles()

	if _roles.has(role_id):
		return _roles[role_id]
	return {}

func has_role(role_id: String) -> bool:
	if not _loaded:
		_load_roles()
	return _roles.has(role_id)

func get_all_roles() -> Dictionary:
	if not _loaded:
		_load_roles()
	return _roles
