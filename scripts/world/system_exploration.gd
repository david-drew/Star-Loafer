extends Node2D
class_name SystemExploration

# system_exploration.gd
# Main gameplay mode for flying through a star system
# Handles player ship, sector streaming, NPCs, and system-level interactions

# Preload scene files
var planet_scene = preload("res://scenes/world/planet.tscn")
var star_scene = preload("res://scenes/world/star.tscn")
var station_scene = preload("res://scenes/world/station.tscn")

# Node references
@onready var player_ship = $PlayerShip
@onready var background = $Background

# Dynamically created
var sectors: Node2D = null
var stellar_bodies: Node2D = null  # Container for stars and planets
var npc_ships: Node2D = null  		# Container for NPC ships

# Service references (from GameRoot/Systems)
var streamer: SectorStreamer = null
var system_generator: SystemGenerator = null
var npc_spawner: NPCSpawner = null  # NEW

# State
var current_system_data: Dictionary = {}
var is_initialized: bool = false

# Scaling constants for visual display
const AU_TO_PIXELS = 4000.0  # 1 AU = 4000 pixels
const STAR_BASE_SCALE = 1.5
const PLANET_BASE_SCALE = 0.15

# Distance-based scaling (LOD effect)
const DISTANCE_SCALE_MIN = 0.5
const DISTANCE_SCALE_MAX = 2.0
const DISTANCE_SCALE_NEAR = 2200.0
const DISTANCE_SCALE_FAR = 12000.0			# 15000.0

# Performance optimization
const SCALE_UPDATE_INTERVAL = 0.05
var scale_update_timer: float = 0.0

# Asteroid belt generation
const BELT_INNER_RADIUS = 16000.0
const BELT_OUTER_RADIUS = 40000.0
const BELT_ASTEROID_COUNT = 200

func _ready() -> void:
	print("SystemExploration: Initializing...")
	
	_create_sectors_node()
	_create_stellar_bodies_node()
	_create_npc_ships_node()  # NEW
	_setup_services()
	_setup_player_ship()
	_setup_background()
	_generate_current_system()
	_spawn_stellar_bodies()
	_spawn_npcs()  
	_debug_force_spawn_test_npcs()			# TODO Debug
	_enable_streaming()
	
	is_initialized = true
	print("SystemExploration: Ready")
	

func _debug_force_spawn_test_npcs() -> void:
	"""Temporary debug function to force spawn visible NPCs"""
	if npc_spawner == null or npc_ships == null:
		print("DEBUG: Can't spawn - npc_spawner or npc_ships is null")
		return
	
	print("DEBUG: Force spawning 5 test NPCs...")
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	for i in range(5):
		var ship_data = {
			"id": "debug_npc_%d" % i,
			"type": "patrol_corvette",
			"faction_id": "imperial_meridian",
			"name": "DEBUG Ship %d" % i,
			"spawn_position": player_ship.global_position + Vector2(rng.randf_range(-2000, 2000), rng.randf_range(-2000, 2000)),
			"patrol_route": [],
			"ai_behavior": "patrol"
		}
		
		var npc_ship_scene = load("res://scenes/actors/npc_ship.tscn")
		var npc = npc_ship_scene.instantiate()
		npc_ships.add_child(npc)
		npc.initialize(ship_data)
		print("  Spawned debug NPC at: ", ship_data["spawn_position"])

func _process(delta: float) -> void:
	if !is_initialized or player_ship == null or stellar_bodies == null:
		return
	
	# Update distance-based scaling periodically, not every frame
	scale_update_timer += delta
	if scale_update_timer >= SCALE_UPDATE_INTERVAL:
		scale_update_timer = 0.0
		_update_stellar_body_scales()

func _create_sectors_node() -> void:
	sectors = Node2D.new()
	sectors.name = "Sectors"
	add_child(sectors)
	print("SystemExploration: Created Sectors node")

func _create_stellar_bodies_node() -> void:
	stellar_bodies = Node2D.new()
	stellar_bodies.name = "StellarBodies"
	stellar_bodies.z_index = -1
	add_child(stellar_bodies)
	print("SystemExploration: Created StellarBodies node")

func _create_npc_ships_node() -> void:
	"""NEW: Create container for NPC ships"""
	npc_ships = Node2D.new()
	npc_ships.name = "NPCShips"
	npc_ships.z_index = 0  # Same layer as player
	add_child(npc_ships)
	print("SystemExploration: Created NPCShips node")

func _setup_services() -> void:
	var game_root = get_node_or_null("/root/GameRoot")
	if game_root == null:
		push_error("SystemExploration: Cannot find GameRoot!")
		return
	
	var systems_node = game_root.get_node_or_null("Systems")
	if systems_node == null:
		push_error("SystemExploration: Cannot find GameRoot/Systems!")
		return
	
	streamer = systems_node.get_node_or_null("SectorStreamer")
	system_generator = systems_node.get_node_or_null("SystemGenerator")
	npc_spawner = systems_node.get_node_or_null("NPCSpawner")
	
	if streamer == null:
		push_error("SystemExploration: SectorStreamer not found!")
	
	if system_generator == null:
		push_error("SystemExploration: SystemGenerator not found!")
	
	if npc_spawner == null:
		push_error("SystemExploration: NPCSpawner not found! NPCs will not spawn.")
		push_error("SystemExploration: Make sure NPCSpawner is added as a child of GameRoot/Systems")
		# Print debug info to help locate the issue
		print("SystemExploration: Available nodes under Systems:")
		for child in systems_node.get_children():
			print("  - ", child.name, " (", child.get_class(), ")")

func _setup_player_ship() -> void:
	if player_ship == null:
		push_error("SystemExploration: PlayerShip not found!")
		return
	
	if GameState.ship_position != Vector2.ZERO:
		player_ship.global_position = GameState.ship_position
		print("SystemExploration: Ship positioned at saved location: ", GameState.ship_position)
	else:
		player_ship.global_position = Vector2(512, 512)
		GameState.ship_position = player_ship.global_position
		print("SystemExploration: Ship positioned at default spawn: ", player_ship.global_position)
	
	if GameState.ship_velocity != Vector2.ZERO:
		player_ship.velocity = GameState.ship_velocity

func _setup_background() -> void:
	if background == null:
		push_warning("SystemExploration: Background not found, skipping")
		return
	
	background.visible = true
	print("SystemExploration: Background configured")

func _generate_current_system() -> void:
	if system_generator == null:
		push_error("SystemExploration: Cannot generate system, SystemGenerator is null")
		return
	
	var system_id = GameState.current_system_id
	if system_id == "":
		push_error("SystemExploration: No current system ID in GameState!")
		return
	
	# Find system data in galaxy
	var system_info = _find_system_in_galaxy(system_id)
	if system_info.is_empty():
		push_error("SystemExploration: System '%s' not found in galaxy data!" % system_id)
		return
	
	# Generate full system details
	current_system_data = system_generator.generate(
		system_id,
		GameState.galaxy_seed,
		system_info.get("pop_level", 5),
		system_info.get("tech_level", 5),
		system_info.get("mining_quality", 5)
	)
	
	# NEW: Add faction data to system_data for NPC spawning
	current_system_data["faction_id"] = system_info.get("faction_id", "")
	current_system_data["faction_influence"] = system_info.get("faction_influence", 100)
	
	print("SystemExploration: Generated system '%s'" % system_info.get("name", system_id))
	print("  - Stars: %d" % current_system_data.get("stars", []).size())
	print("  - Bodies: %d" % current_system_data.get("bodies", []).size())
	print("  - Stations: %d" % current_system_data.get("stations", []).size())
	print("  - Faction: %s (influence: %d)" % [
		current_system_data.get("faction_id", "none"),
		current_system_data.get("faction_influence", 0)
	])
	
	GameState.mark_discovered("galaxy", system_id)
	EventBus.system_entered.emit(system_id)

func _spawn_stellar_bodies() -> void:
	if stellar_bodies == null:
		push_error("SystemExploration: Cannot spawn bodies, StellarBodies node is null")
		return
	
	if current_system_data.is_empty():
		push_warning("SystemExploration: No system data to spawn bodies from")
		return
	
	# Clear any existing bodies
	for child in stellar_bodies.get_children():
		child.queue_free()
	
	# Spawn stars at origin (0,0)
	var stars = current_system_data.get("stars", [])
	for i in range(stars.size()):
		var star = stars[i]
		_spawn_star(star, i)
	
	# Spawn planets at their orbital distances
	var bodies = current_system_data.get("bodies", [])
	for body in bodies:
		if body.get("kind", "") == "planet":
			_spawn_planet(body)
	
	# Spawn asteroid belts if they exist
	for body in bodies:
		if body.get("kind", "") == "asteroid_belt":
			_spawn_asteroid_belt(body)
	
	print("SystemExploration: Spawned %d stars and %d bodies" % [stars.size(), bodies.size()])

func _spawn_npcs() -> void:
	"""NEW: Spawn NPC ships for this system"""
	if npc_spawner == null:
		push_warning("SystemExploration: NPCSpawner not available, skipping NPC spawn")
		return
	
	if npc_ships == null:
		push_error("SystemExploration: NPCShips container is null")
		return
	
	# Set the NPC container
	npc_spawner.set_npc_container(npc_ships)
	
	# Spawn NPCs based on system data
	var system_seed = current_system_data.get("seed", 0)
	npc_spawner.spawn_npcs_for_system(current_system_data, system_seed)
	
	print("SystemExploration: Spawned %d NPC ships" % npc_spawner.get_npc_count())

func _update_stellar_body_scales() -> void:
	var player_pos = player_ship.global_position
	
	for child in stellar_bodies.get_children():
		if child.name.begins_with("belt"):
			for asteroid in child.get_children():
				var distance = player_pos.distance_to(asteroid.global_position)
				_apply_distance_scale(asteroid, distance)
		else:
			var distance = player_pos.distance_to(child.global_position)
			_apply_distance_scale(child, distance)

func _apply_distance_scale(node: Node2D, distance: float) -> void:
	var scale_factor = DISTANCE_SCALE_MAX
	if distance > DISTANCE_SCALE_NEAR:
		var t = clamp(
			(distance - DISTANCE_SCALE_NEAR) / (DISTANCE_SCALE_FAR - DISTANCE_SCALE_NEAR),
			0.0,
			1.0
		)
		scale_factor = lerp(DISTANCE_SCALE_MAX, DISTANCE_SCALE_MIN, t)
	
	var sprite = node.get_node_or_null("Sprite2D")
	if sprite:
		var base_scale = node.get_meta("base_scale", Vector2.ONE)
		sprite.scale = base_scale * scale_factor

func _spawn_star(star_data: Dictionary, index: int) -> void:
	var star = star_scene.instantiate()
	star.initialize(star_data, index)
	stellar_bodies.add_child(star)

func _spawn_planet(planet_data: Dictionary) -> void:
	var planet = planet_scene.instantiate()
	planet.initialize(planet_data, GameState.galaxy_seed)
	stellar_bodies.add_child(planet)

func _spawn_asteroid_belt(belt_data: Dictionary) -> void:
	var orbit = belt_data.get("orbit", {})
	var belt_radius_au = orbit.get("a_AU", 3.0)
	var belt_radius_pixels = belt_radius_au * AU_TO_PIXELS
	
	var belt_container = Node2D.new()
	belt_container.name = belt_data.get("id", "belt")
	belt_container.position = Vector2.ZERO
	
	var belt_id = belt_data.get("id", "belt:0")
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(belt_id)
	
	var asteroid_count = BELT_ASTEROID_COUNT
	for i in range(asteroid_count):
		var asteroid_node = Node2D.new()
		asteroid_node.name = "belt_asteroid_%d" % i
		
		var angle = rng.randf() * TAU
		var thickness = belt_radius_pixels * 0.15
		var distance = belt_radius_pixels + rng.randf_range(-thickness, thickness)
		
		asteroid_node.position = Vector2(
			cos(angle) * distance,
			sin(angle) * distance
		)
		
		var sprite = Sprite2D.new()
		var sprite_path = ContentDB.get_asteroid_sprite(rng)
		
		if sprite_path != "" and ResourceLoader.exists(sprite_path):
			sprite.texture = load(sprite_path)
		else:
			sprite.texture = PlaceholderTexture2D.new()
			sprite.texture.size = Vector2(32, 32)
			sprite.modulate = Color.GRAY
		
		sprite.rotation = rng.randf() * TAU
		var base_scale = Vector2.ONE * rng.randf_range(0.05, 0.15)
		sprite.scale = base_scale
		asteroid_node.add_child(sprite)
		asteroid_node.set_meta("base_scale", base_scale)
		
		belt_container.add_child(asteroid_node)
	
	stellar_bodies.add_child(belt_container)
	print("  Spawned asteroid belt: %s (%d asteroids at %.1f AU)" % [
		belt_container.name,
		asteroid_count,
		belt_radius_au
	])

func _find_system_in_galaxy(system_id: String) -> Dictionary:
	var galaxy_data = GameState.galaxy_data
	if galaxy_data.is_empty():
		return {}
	
	for system in galaxy_data.get("systems", []):
		if system.get("id", "") == system_id:
			return system
	
	return {}

func _enable_streaming() -> void:
	if streamer == null:
		push_error("SystemExploration: Cannot enable streaming, SectorStreamer is null")
		return
	
	if sectors == null:
		push_error("SystemExploration: Cannot enable streaming, Sectors node is null")
		return
	
	streamer.set_tile_parent(sectors)
	streamer.enable_streaming(true)
	
	print("SystemExploration: Sector streaming enabled")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_map"):
		_toggle_galaxy_map()
	elif event.is_action_pressed("ui_map_system"):
		_toggle_system_map()

func _toggle_galaxy_map() -> void:
	EventBus.map_toggled.emit("galaxy", true)
	print("SystemExploration: Galaxy map toggle requested")

func _toggle_system_map() -> void:
	EventBus.map_toggled.emit("system", true)
	print("SystemExploration: System map toggle requested")

func _exit_tree() -> void:
	if streamer:
		streamer.enable_streaming(false)
		streamer.clear_all_tiles()
	
	# NEW: Clean up NPCs
	if npc_spawner:
		npc_spawner.clear_all_npcs()
	
	print("SystemExploration: Cleanup complete")

# === PUBLIC API ===

func get_current_system_data() -> Dictionary:
	return current_system_data

func get_system_name() -> String:
	var system_id = GameState.current_system_id
	var system_info = _find_system_in_galaxy(system_id)
	return system_info.get("name", system_id)

func get_system_faction() -> String:
	"""NEW: Get the faction controlling this system"""
	return current_system_data.get("faction_id", "")

func teleport_ship(new_position: Vector2) -> void:
	if player_ship:
		player_ship.global_position = new_position
		player_ship.velocity = Vector2.ZERO
		GameState.ship_position = new_position
		GameState.ship_velocity = Vector2.ZERO
		print("SystemExploration: Ship teleported to ", new_position)

func get_player_ship() -> CharacterBody2D:
	return player_ship

func get_nearby_npcs(range_radius: float = 1000.0) -> Array:
	"""NEW: Get NPCs near the player"""
	if npc_spawner == null or player_ship == null:
		return []
	
	return npc_spawner.get_npcs_in_range(player_ship.global_position, range_radius)

func get_hostile_npcs_nearby(range_radius: float = 2000.0) -> Array:
	"""NEW: Get hostile NPCs near the player"""
	if npc_spawner == null or player_ship == null:
		return []
	
	return npc_spawner.get_hostile_npcs_in_range(player_ship.global_position, range_radius)

# === DEBUG FUNCTIONS ===

func debug_print_system_info() -> void:
	print("=== System Exploration Debug ===")
	print("System ID: ", GameState.current_system_id)
	print("System Name: ", get_system_name())
	print("System Faction: ", get_system_faction())
	print("Ship Position: ", player_ship.global_position if player_ship else "N/A")
	print("Ship Velocity: ", player_ship.velocity if player_ship else "N/A")
	print("Current Sector: ", GameState.current_sector)
	print("Active Tiles: ", streamer.get_active_tile_count() if streamer else 0)
	print("Stars: ", current_system_data.get("stars", []).size())
	print("Bodies: ", current_system_data.get("bodies", []).size())
	print("NPCs: ", npc_spawner.get_npc_count() if npc_spawner else 0)
	print("================================")

func debug_force_streaming_refresh() -> void:
	if streamer:
		streamer.force_refresh()
		print("SystemExploration: Forced streaming refresh")
