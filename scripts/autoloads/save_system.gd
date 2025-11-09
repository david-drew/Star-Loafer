extends Node

const SAVE_DIR = "user://saves/"
const MAX_SLOTS = 10

var providers: Dictionary = {}  # { "provider_name": { "get": Callable, "set": Callable } }

func _ready() -> void:
	if !DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_absolute(SAVE_DIR)

func register_provider(name: String, get_state: Callable, set_state: Callable) -> void:
	providers[name] = { "get": get_state, "set": set_state }

func save_to_slot(slot: int) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		push_error("Invalid save slot: %d" % slot)
		return false
	
	var save_data = {}
	for provider_name in providers:
		var get_callable = providers[provider_name]["get"]
		save_data[provider_name] = get_callable.call()
	
	save_data["timestamp"] = Time.get_unix_time_from_system()
	save_data["version"] = "0.1.0"
	
	var file_path = SAVE_DIR + "slot_%d.sav" % slot
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open save file: %s" % file_path)
		return false
	
	var json_string = JSON.stringify(save_data, "\t")
	file.store_string(json_string)
	file.close()
	
	print("Game saved to slot %d" % slot)
	return true

func load_from_slot(slot: int) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		push_error("Invalid save slot: %d" % slot)
		return false
	
	var file_path = SAVE_DIR + "slot_%d.sav" % slot
	if !FileAccess.file_exists(file_path):
		push_error("Save file does not exist: %s" % file_path)
		return false
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open save file: %s" % file_path)
		return false
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		push_error("Failed to parse save file JSON")
		return false
	
	var save_data = json.data
	
	for provider_name in providers:
		if provider_name in save_data:
			var set_callable = providers[provider_name]["set"]
			set_callable.call(save_data[provider_name])
	
	print("Game loaded from slot %d" % slot)
	return true

func get_slot_info(slot: int) -> Dictionary:
	var file_path = SAVE_DIR + "slot_%d.sav" % slot
	if !FileAccess.file_exists(file_path):
		return {}
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		return {}
	
	var save_data = json.data
	return {
		"timestamp": save_data.get("timestamp", 0),
		"version": save_data.get("version", "unknown"),
		"system": save_data.get("game_state", {}).get("current_system_id", "unknown"),
		"credits": save_data.get("game_state", {}).get("credits", 0)
	}

func delete_slot(slot: int) -> bool:
	var file_path = SAVE_DIR + "slot_%d.sav" % slot
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)
		return true
	return false
