extends Node

var pending_load_slot: int = -1
var start_new_game: bool = false
var new_game_config: Dictionary = {}

func start_fresh_game(config: Dictionary) -> void:
	start_new_game = true
	new_game_config = config  # { "seed": 12345, "size": "medium" }
	pending_load_slot = -1
	get_tree().change_scene_to_file("res://scenes/game_root.tscn")


func start_load_game(slot: int) -> void:
	pending_load_slot = slot
	start_new_game = false
	get_tree().change_scene_to_file("res://scenes/game_root.tscn")

func return_to_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func transition_to_mode(mode_scene_path: String) -> void:
	# Called by GameRoot to swap WorldRoot children
	EventBus.mode_transition_requested.emit(mode_scene_path)
