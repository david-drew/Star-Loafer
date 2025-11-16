extends Node2D
class_name SystemExploration

# Preload scene files
var planet_scene = preload("res://scenes/world/planet.tscn")
var star_scene = preload("res://scenes/world/star.tscn")
var station_scene = preload("res://scenes/world/station.tscn")
var npc_ship_scene = preload("res://scenes/actors/npc_ship.tscn")

# Node references
@onready var player_ship = $PlayerShip
@onready var background = $Background

# Dynamically created
var sectors: Node2D = null
var stellar_bodies: Node2D = null
var npc_ships: Node2D = null

# Service references (from GameRoot/Systems)
var streamer: SectorStreamer = null
var system_generator: SystemGenerator = null
var npc_spawner: NPCSpawner = null

# State
var current_system_data: Dictionary = {}
var is_initialized: bool = false

# Scaling constants for visual display
const AU_TO_PIXELS = 4000.0
const STAR_BASE_SCALE = 1.5
const PLANET_BASE_SCALE = 0.15
const MOON_BASE_SCALE = 0.05  # Moons are 1/3 the scale of planets (0.05 vs 0.15)

# Moon scale multiplier - adjust this to make moons relatively larger or smaller
# 1.0 = normal size (1/3 of planet), 0.5 = half size (1/6 of planet), 2.0 = double size (2/3 of planet)
const MOON_SCALE_MULTIPLIER = 1.0

# Distance-based scaling (LOD effect)
const DISTANCE_SCALE_MIN = 0.5
const DISTANCE_SCALE_MAX = 2.0
const DISTANCE_SCALE_NEAR = 2500.0			# default 3000
const DISTANCE_SCALE_FAR = 18000.0 			# default 20000

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
	_create_npc_ships_node()
	_setup_services()
	_setup_player_ship()
	_setup_background()
	_generate_current_system()
	_spawn_stellar_bodies()
	_spawn_stations()
	_spawn_npcs()
	_enable_streaming()
	is_initialized = true
	print("SystemExploration: Ready")

func _process(delta: float) -> void:
	if !is_initialized or player_ship == null or stellar_bodies == null:
		return
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
	npc_ships = Node2D.new()
	npc_ships.name = "NPCShips"
	npc_ships.z_index = 0
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
	var system_id := GameState.current_system_id
	if system_id == "":
		push_error("SystemExploration: No current system ID in GameState!")
		return
	var system_info := _find_system_in_galaxy(system_id)
	if system_info.is_empty():
		push_error("SystemExploration: System '%s' not found in galaxy data!" % system_id)
		return
	
	current_system_data = system_generator.generate(
		system_id,
		GameState.galaxy_seed,
		system_info.get("pop_level", 5),
		system_info.get("tech_level", 5),
		system_info.get("mining_quality", 5)
	)
	
	current_system_data["faction_id"] = system_info.get("faction_id", "")
	current_system_data["faction_influence"] = system_info.get("faction_influence", 100)
	
	# Apply faction_id to all inhabitant_data
	_apply_faction_to_inhabitants(current_system_data.get("faction_id", ""))
	
	# Count moons separately for logging
	var bodies: Array = current_system_data.get("bodies", [])
	var planet_count := 0
	var moon_count := 0
	for body in bodies:
		match body.get("kind", ""):
			"planet":
				planet_count += 1
			"moon":
				moon_count += 1
	
	print("SystemExploration: Generated system '%s'" % system_info.get("name", system_id))
	print("  - Stars: %d" % current_system_data.get("stars", []).size())
	print("  - Planets: %d" % planet_count)
	print("  - Moons: %d" % moon_count)
	print("  - Stations: %d" % current_system_data.get("stations", []).size())
	print("  - Faction: %s (influence: %d)" % [
		current_system_data.get("faction_id", "none"),
		current_system_data.get("faction_influence", 0)
	])
	
	GameState.mark_discovered("galaxy", system_id)
	EventBus.system_entered.emit(system_id)

func _apply_faction_to_inhabitants(faction_id: String) -> void:
	"""Apply system faction to all inhabited bodies and stations"""
	var bodies: Array = current_system_data.get("bodies", [])
	for body in bodies:
		if body.has("inhabitant_data"):
			body["inhabitant_data"]["faction_id"] = faction_id
	
	var stations: Array = current_system_data.get("stations", [])
	for station in stations:
		if station.has("inhabitant_data"):
			station["inhabitant_data"]["faction_id"] = faction_id

func _spawn_stellar_bodies() -> void:
	if stellar_bodies == null:
		push_error("SystemExploration: Cannot spawn bodies, StellarBodies node is null")
		return
	if current_system_data.is_empty():
		push_warning("SystemExploration: No system data to spawn bodies from")
		return
	
	for child in stellar_bodies.get_children():
		child.queue_free()
	
	var stars:Array = current_system_data.get("stars", [])
	_spawn_stars_with_formation(stars)
	
	var bodies:Array = current_system_data.get("bodies", [])
	
	# Spawn planets first
	for body in bodies:
		if body.get("kind", "") == "planet":
			_spawn_planet(body)
	
	# Spawn moons (they need planets to exist first for positioning)
	for body in bodies:
		if body.get("kind", "") == "moon":
			_spawn_moon(body)
	
	# Spawn asteroid belts
	for body in bodies:
		if body.get("kind", "") == "asteroid_belt":
			_spawn_asteroid_belt(body)
	
	var planet_count := bodies.filter(func(b): return b.get("kind") == "planet").size()
	var moon_count := bodies.filter(func(b): return b.get("kind") == "moon").size()
	print("SystemExploration: Spawned %d stars, %d planets, %d moons" % [stars.size(), planet_count, moon_count])

func _spawn_stations() -> void:
	if stellar_bodies == null:
		push_error("SystemExploration: Cannot spawn stations, StellarBodies node is null")
		return
	if current_system_data.is_empty():
		push_warning("SystemExploration: No system data to spawn stations from")
		return
	var stations:Array = current_system_data.get("stations", [])
	if stations.is_empty():
		print("SystemExploration: No stations in this system")
		return
	for station_data in stations:
		_spawn_station(station_data)
	print("SystemExploration: Spawned %d stations" % stations.size())

func _spawn_station(station_data: Dictionary) -> void:
	var station = station_scene.instantiate()
	var pos_array:Array = station_data.get("position", [0, 0])
	var position:Vector2 = Vector2(pos_array[0], pos_array[1])
	if !station_data.has("faction_id"):
		station_data["faction_id"] = current_system_data.get("faction_id", "")
	station_data["position"] = position
	stellar_bodies.add_child(station)
	station.initialize(station_data)

func _spawn_npcs() -> void:
	if npc_spawner == null:
		push_warning("SystemExploration: NPCSpawner not available, skipping NPC spawn")
		return
	if npc_ships == null:
		push_error("SystemExploration: NPCShips container is null")
		return
	npc_spawner.set_npc_container(npc_ships)
	var system_seed = current_system_data.get("seed", 0)
	npc_spawner.spawn_npcs_for_system(current_system_data, system_seed)
	print("SystemExploration: Spawned %d NPC ships" % npc_spawner.get_npc_count())

func _update_stellar_body_scales() -> void:
	if stellar_bodies == null or player_ship == null:
		return
	for node in stellar_bodies.get_children():
		if node.has_meta("base_scale"):
			_update_node_scale(node)

func _update_node_scale(node: Node2D) -> void:
	if player_ship == null:
		return
	var distance:float = player_ship.global_position.distance_to(node.global_position)
	var camera_zoom := 1.0
	if player_ship.has_node("Camera2D"):
		var cam = player_ship.get_node("Camera2D")
		camera_zoom = cam.zoom.x
	
	var adjusted_near := DISTANCE_SCALE_NEAR * camera_zoom
	var adjusted_far := DISTANCE_SCALE_FAR * camera_zoom
	var target_scale_factor := DISTANCE_SCALE_MAX
	
	if distance > adjusted_near:
		var t:float = clamp(
			(distance - adjusted_near) / (adjusted_far - adjusted_near),
			0.0,
			1.0
		)
		target_scale_factor = lerp(DISTANCE_SCALE_MAX, DISTANCE_SCALE_MIN, t)
	
	# If this is a moon, also consider parent planet's scale
	var final_scale_factor := target_scale_factor
	if node.has_meta("is_moon") and node.has_meta("parent_id"):
		var parent_id: String = node.get_meta("parent_id")
		var parent_planet = _find_body_node_by_id(parent_id)
		if parent_planet and parent_planet.has_node("Sprite2D"):
			var parent_sprite = parent_planet.get_node("Sprite2D")
			var parent_base_scale = parent_planet.get_meta("base_scale", Vector2.ONE * PLANET_BASE_SCALE)
			
			# Calculate parent's current scale factor
			var parent_current_scale:float = parent_sprite.scale.x
			var parent_scale_factor:float  = parent_current_scale / parent_base_scale.x if parent_base_scale.x > 0 else 1.0
			
			# Moon scales proportionally with parent (if parent shrinks, moon shrinks too)
			final_scale_factor *= parent_scale_factor
	
	var sprite = node.get_node_or_null("Sprite2D")
	if sprite:
		var base_scale = node.get_meta("base_scale", Vector2.ONE)
		var target_scale = base_scale * final_scale_factor
		sprite.scale = sprite.scale.lerp(target_scale, 0.15)

func _spawn_star(star_data: Dictionary, index: int) -> void:
	var star = star_scene.instantiate()
	star.initialize(star_data, index)
	stellar_bodies.add_child(star)

func _spawn_stars_with_formation(stars: Array) -> void:
	if stars.is_empty():
		return
	
	var star_count = stars.size()
	var rng = RandomNumberGenerator.new()
	rng.seed = current_system_data.get("seed", 0)
	
	match star_count:
		1:
			_spawn_star_at_position(stars[0], 0, Vector2.ZERO)
		2:
			var separation = rng.randf_range(1200.0, 2500.0)
			_spawn_star_at_position(stars[0], 0, Vector2(-separation / 2, 0))
			_spawn_star_at_position(stars[1], 1, Vector2(separation / 2, 0))
		3:
			var radius = rng.randf_range(1000.0, 2000.0)
			var rotation = rng.randf() * TAU
			for i in range(3):
				var angle = (TAU / 3.0) * i + rotation
				var position = Vector2(cos(angle), sin(angle)) * radius
				_spawn_star_at_position(stars[i], i, position)
		_:
			var radius = rng.randf_range(1200.0, 2000.0)
			var rotation = rng.randf() * TAU
			for i in range(stars.size()):
				var angle = (TAU / stars.size()) * i + rotation
				var position = Vector2(cos(angle), sin(angle)) * radius
				_spawn_star_at_position(stars[i], i, position)

func _spawn_star_at_position(star_data: Dictionary, index: int, position: Vector2) -> void:
	var star = star_scene.instantiate()
	star.initialize(star_data, index)
	stellar_bodies.add_child(star)
	star.global_position = position

func _spawn_planet(planet_data: Dictionary) -> void:
	var planet = planet_scene.instantiate()
	planet.initialize(planet_data, GameState.galaxy_seed)
	stellar_bodies.add_child(planet)
	
	# Store body_id metadata so moons can find their parent
	planet.set_meta("body_id", planet_data.get("id", "unknown"))
	
	# Set base_scale for distance-based LOD (if planet has size data)
	# This metadata is used by _update_stellar_body_scales()
	if not planet.has_meta("base_scale"):
		planet.set_meta("base_scale", Vector2.ONE * PLANET_BASE_SCALE)

func _spawn_moon(moon_data: Dictionary) -> void:
	"""Spawn a moon orbiting a planet"""
	# Moons use the same planet scene but are initialized differently
	var moon = planet_scene.instantiate()
	moon.initialize(moon_data, GameState.galaxy_seed)
	stellar_bodies.add_child(moon)
	
	# Use the pre-calculated absolute position from layout system
	if moon_data.has("_position_px"):
		moon.global_position = moon_data["_position_px"]
	else:
		# Fallback: calculate position relative to parent planet
		var parent_id: String = moon_data.get("parent_id", "")
		var parent_planet = _find_body_node_by_id(parent_id)
		
		if parent_planet:
			# Get moon orbit data
			var orbit: Dictionary = moon_data.get("orbit", {})
			var radius_px: float = orbit.get("radius_px", 500.0)
			var angle_rad: float = orbit.get("angle_rad", 0.0)
			
			# Position moon in orbit around planet
			var offset := Vector2(cos(angle_rad), sin(angle_rad)) * radius_px
			moon.global_position = parent_planet.global_position + offset
		else:
			push_warning("SystemExploration: Could not find parent planet '%s' for moon '%s'" % [parent_id, moon_data.get("id", "unknown")])
	
	# Calculate moon scale based on size data
	var moon_size_range: Array = moon_data.get("size_px_range", [20, 40])
	var avg_moon_size: float = (float(moon_size_range[0]) + float(moon_size_range[1])) / 2.0
	
	# Moon base scale: smaller than planets (MOON_BASE_SCALE is 0.05, PLANET_BASE_SCALE is 0.15)
	# This gives moons 1/3 the scale of planets by default
	# Adjust with MOON_SCALE_MULTIPLIER if you want all moons larger/smaller
	var moon_scale: float = MOON_BASE_SCALE * (avg_moon_size / 40.0) * MOON_SCALE_MULTIPLIER  # Normalize to typical moon size
	
	# Store metadata for orbital updates and scaling
	var orbit: Dictionary = moon_data.get("orbit", {})
	var parent_id: String = moon_data.get("parent_id", "")
	
	moon.set_meta("orbit_radius_px", orbit.get("radius_px", 500.0))
	moon.set_meta("orbit_angle_rad", orbit.get("angle_rad", 0.0))
	moon.set_meta("orbit_period_days", orbit.get("period_days", 1.0))
	moon.set_meta("parent_id", parent_id)
	moon.set_meta("body_id", moon_data.get("id", "unknown"))
	moon.set_meta("base_scale", Vector2.ONE * moon_scale)  # For distance-based LOD
	moon.set_meta("is_moon", true)  # Flag for special moon handling
	
	# Apply initial scale to sprite
	var sprite = moon.get_node_or_null("Sprite2D")
	if sprite:
		sprite.scale = Vector2.ONE * moon_scale

func _find_body_node_by_id(body_id: String) -> Node2D:
	"""Find a spawned body node by its ID"""
	if stellar_bodies == null:
		return null
	
	for node in stellar_bodies.get_children():
		if node.has_meta("body_id") and node.get_meta("body_id") == body_id:
			return node
	
	return null

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
	if npc_spawner == null or player_ship == null:
		return []
	return npc_spawner.get_npcs_in_range(player_ship.global_position, range_radius)

func get_hostile_npcs_nearby(range_radius: float = 2000.0) -> Array:
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
	
	var bodies: Array = current_system_data.get("bodies", [])
	var planet_count := bodies.filter(func(b): return b.get("kind") == "planet").size()
	var moon_count := bodies.filter(func(b): return b.get("kind") == "moon").size()
	print("Planets: ", planet_count)
	print("Moons: ", moon_count)
	print("Stations: ", current_system_data.get("stations", []).size())
	print("NPCs: ", npc_spawner.get_npc_count() if npc_spawner else 0)
	print("================================")

func debug_force_streaming_refresh() -> void:
	if streamer:
		streamer.force_refresh()
		print("SystemExploration: Forced streaming refresh")
