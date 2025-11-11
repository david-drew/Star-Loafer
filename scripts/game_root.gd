extends Node2D

@onready var galaxy_gen = $Systems/GalaxyGenerator
@onready var loading_overlay = $LoadingOverlay
#@onready var FactionManager  = $Systems/FactionManager
#@onready var NpcSpawner      = $Systems/NpcSpawner

@onready var galaxy_generator:GalaxyGenerator = GalaxyGenerator.new()
@onready var faction_manager:FactionManager = FactionManager.new()
@onready var npc_spawner:NPCSpawner = NPCSpawner.new()

#$Systems.add_child(faction_manager)
#faction_manager.name = "FactionManager"

# Add NPCSpawner as child of Systems

#$Systems.add_child(npc_spawner)
#npc_spawner.name = "NPCSpawner"

func _ready() -> void:
	_register_save_providers()
	
	if SceneManager.pending_load_slot >= 0:
		_load_game()
	elif SceneManager.start_new_game:
		_start_new_game()

	#faction_manager = FactionManager.new()
	#npc_spawner = NPCSpawner.new()

	# Connect FactionManager to other services
	npc_spawner.faction_manager = faction_manager
	galaxy_generator.faction_manager = faction_manager

func _register_save_providers() -> void:
	SaveSystem.register_provider("game_state", 
		Callable(GameState, "get_state"),
		Callable(GameState, "set_state"))

func _start_new_game() -> void:
	loading_overlay.show()
	
	var config = SceneManager.new_game_config
	var seed = config.get("seed", randi())
	var size = config.get("size", "medium")
	
	print("Generating galaxy with seed %d, size %s" % [seed, size])
	
	# Generate galaxy
	var galaxy_data = galaxy_gen.generate(seed, size)
	GameState.galaxy_seed = seed
	GameState.galaxy_size = size
	GameState.galaxy_data = galaxy_data
	
	# Find starter system
	var starter_system = galaxy_gen.find_valid_starter_system(galaxy_data)
	GameState.current_system_id = starter_system["id"]
	GameState.mark_discovered("galaxy", starter_system["id"])
	
	print("Starting in system: %s" % starter_system["name"])
	
	# Load SystemExploration mode
	_load_mode("res://scenes/modes/system_exploration.tscn")
	
	loading_overlay.hide()
	SceneManager.start_new_game = false

func _load_game() -> void:
	loading_overlay.show()
	
	SaveSystem.load_from_slot(SceneManager.pending_load_slot)
	
	# Regenerate galaxy from saved seed
	var galaxy_data = galaxy_gen.generate(GameState.galaxy_seed, GameState.galaxy_size)
	GameState.galaxy_data = galaxy_data
	
	_load_mode("res://scenes/modes/system_exploration.tscn")
	
	loading_overlay.hide()
	SceneManager.pending_load_slot = -1

func _load_mode(scene_path: String) -> void:
	# Clear WorldRoot
	for child in $WorldRoot.get_children():
		child.queue_free()
	
	# Load new mode
	var mode_scene = load(scene_path).instantiate()
	$WorldRoot.add_child(mode_scene)
