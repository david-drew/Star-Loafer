extends Node2D
class_name SystemExploration

# system_exploration.gd
# Main gameplay mode for flying through a star system
# Handles player ship, sector streaming, and system-level interactions

# Node references
@onready var player_ship = $PlayerShip
@onready var background = $Background

# Dynamically created
var sectors: Node2D = null
var stellar_bodies: Node2D = null  # Container for stars and planets

# Service references (from GameRoot/Systems)
var streamer: SectorStreamer = null
var system_generator: SystemGenerator = null

# State
var current_system_data: Dictionary = {}
var is_initialized: bool = false

# Scaling constants for visual display
const AU_TO_PIXELS = 8000.0  # 1 AU = 8000 pixels (much larger for proper spacing)
const STAR_BASE_SCALE = 1.5  # Stars are already 1024x1024, scale down a bit
const PLANET_BASE_SCALE = 0.15  # Planets ~128px, scale down for distant viewing

# Distance-based scaling (LOD effect)
const DISTANCE_SCALE_MIN = 0.1  # Minimum scale when far away (10% size)
const DISTANCE_SCALE_MAX = 1.0  # Maximum scale when close (100% size)
const DISTANCE_SCALE_NEAR = 2000.0  # Distance at which objects are full size
const DISTANCE_SCALE_FAR = 15000.0  # Distance at which objects are minimum size

# Asteroid belt generation
const BELT_INNER_RADIUS = 16000.0  # 2.0 AU in pixels
const BELT_OUTER_RADIUS = 40000.0  # 5.0 AU in pixels
const BELT_ASTEROID_COUNT = 200  # Number of asteroids in belt ring

func _ready() -> void:
	print("SystemExploration: Initializing...")
	
	_create_sectors_node()
	_create_stellar_bodies_node()
	_setup_services()
	_setup_player_ship()
	_setup_background()
	_generate_current_system()
	_spawn_stellar_bodies()
	_enable_streaming()
	
	is_initialized = true
	print("SystemExploration: Ready")

func _process(_delta: float) -> void:
	if !is_initialized or player_ship == null or stellar_bodies == null:
		return
	
	# Update distance-based scaling for all stellar bodies
	_update_stellar_body_scales()

func _create_sectors_node() -> void:
	# Create the Sectors container node
	sectors = Node2D.new()
	sectors.name = "Sectors"
	add_child(sectors)
	print("SystemExploration: Created Sectors node")

func _create_stellar_bodies_node() -> void:
	# Create container for stars and planets
	stellar_bodies = Node2D.new()
	stellar_bodies.name = "StellarBodies"
	stellar_bodies.z_index = -1  # Render behind everything else
	add_child(stellar_bodies)
	print("SystemExploration: Created StellarBodies node")

func _setup_services() -> void:
	# Get references to services from GameRoot/Systems
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
	
	if streamer == null:
		push_error("SystemExploration: SectorStreamer not found!")
	
	if system_generator == null:
		push_error("SystemExploration: SystemGenerator not found!")

func _setup_player_ship() -> void:
	if player_ship == null:
		push_error("SystemExploration: PlayerShip not found!")
		return
	
	# Restore ship position from GameState or use default spawn
	if GameState.ship_position != Vector2.ZERO:
		player_ship.global_position = GameState.ship_position
		print("SystemExploration: Ship positioned at saved location: ", GameState.ship_position)
	else:
		# Default spawn near center of system (center of sector 0,0)
		player_ship.global_position = Vector2(512, 512)
		GameState.ship_position = player_ship.global_position
		print("SystemExploration: Ship positioned at default spawn: ", player_ship.global_position)
	
	# Restore velocity if saved
	if GameState.ship_velocity != Vector2.ZERO:
		player_ship.velocity = GameState.ship_velocity

func _setup_background() -> void:
	if background == null:
		push_warning("SystemExploration: Background not found, skipping")
		return
	
	# Background is set up in scene, just ensure it's visible
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
	
	print("SystemExploration: Generated system '%s'" % system_info.get("name", system_id))
	print("  - Stars: %d" % current_system_data.get("stars", []).size())
	print("  - Bodies: %d" % current_system_data.get("bodies", []).size())
	print("  - Stations: %d" % current_system_data.get("stations", []).size())
	
	# Mark system as discovered
	GameState.mark_discovered("galaxy", system_id)
	
	# Emit signal that system was entered
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

func _update_stellar_body_scales() -> void:
	# Update all stellar bodies based on distance from player
	var player_pos = player_ship.global_position
	
	for child in stellar_bodies.get_children():
		# Handle belt containers specially (they have asteroid children)
		if child.name.begins_with("belt"):
			for asteroid in child.get_children():
				var distance = player_pos.distance_to(asteroid.global_position)
				_apply_distance_scale(asteroid, distance)
		else:
			# Handle stars and planets
			var distance = player_pos.distance_to(child.global_position)
			_apply_distance_scale(child, distance)

func _apply_distance_scale(node: Node2D, distance: float) -> void:
	# Calculate scale based on distance (lerp between min and max)
	var scale_factor = 1.0
	if distance > DISTANCE_SCALE_NEAR:
		var t = clamp(
			(distance - DISTANCE_SCALE_NEAR) / (DISTANCE_SCALE_FAR - DISTANCE_SCALE_NEAR),
			0.0,
			1.0
		)
		scale_factor = lerp(DISTANCE_SCALE_MAX, DISTANCE_SCALE_MIN, t)
	
	# Apply scale to sprite (first child is always the sprite)
	var sprite = node.get_node_or_null("Sprite2D")
	if sprite:
		# Get base scale from metadata (stored when created)
		var base_scale = node.get_meta("base_scale", Vector2.ONE)
		sprite.scale = base_scale * scale_factor

func _spawn_star(star_data: Dictionary, index: int) -> void:
	var star_node = Node2D.new()
	star_node.name = star_data.get("id", "star:%d" % index)
	
	# Position stars slightly offset if multiple
	if index > 0:
		star_node.position = Vector2(index * 1500, 0)  # Binary/trinary offset (larger spacing)
	
	# Create sprite
	var sprite = Sprite2D.new()
	var sprite_path = star_data.get("sprite", "")
	
	# Try to load the sprite, fallback to placeholder
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
	else:
		# Placeholder
		sprite.texture = PlaceholderTexture2D.new()
		sprite.texture.size = Vector2(1024, 1024)  # Match real star size
		
		# Color by spectral class
		var star_class = star_data.get("class", "G")
		if star_class == "Special":
			sprite.modulate = Color.PURPLE
		elif star_class in ["O", "B"]:
			sprite.modulate = Color.DODGER_BLUE
		elif star_class == "A":
			sprite.modulate = Color.WHITE
		elif star_class == "F":
			sprite.modulate = Color.LIGHT_YELLOW
		elif star_class == "G":
			sprite.modulate = Color.YELLOW
		elif star_class == "K":
			sprite.modulate = Color.ORANGE
		elif star_class == "M":
			sprite.modulate = Color.INDIAN_RED
	
	var base_scale = Vector2.ONE * STAR_BASE_SCALE
	sprite.scale = base_scale
	star_node.add_child(sprite)
	
	# Store base scale for distance scaling
	star_node.set_meta("base_scale", base_scale)
	
	# Add point light for glow effect (optional)
	var light = PointLight2D.new()
	light.texture_scale = 5.0  # Larger glow
	light.energy = 1.5
	light.color = sprite.modulate
	star_node.add_child(light)
	
	stellar_bodies.add_child(star_node)
	print("  Spawned star: %s (class %s)" % [star_node.name, star_data.get("class", "Unknown")])

func _spawn_planet(planet_data: Dictionary) -> void:
	var planet_node = Node2D.new()
	planet_node.name = planet_data.get("id", "planet")
	
	# Get orbital data
	var orbit = planet_data.get("orbit", {})
	var orbit_radius_au = orbit.get("a_AU", 1.0)
	var orbit_radius_pixels = orbit_radius_au * AU_TO_PIXELS
	
	# Generate random but consistent angle for this planet using RNG
	var planet_id = planet_data.get("id", "")
	var rng = RandomNumberGenerator.new()
	# Combine system seed and planet ID for consistent but random angle
	rng.seed = hash(GameState.galaxy_seed) ^ hash(current_system_data.get("system_id", "").hash()) ^ hash(planet_id.hash())
	
	# Random angle in radians (0 to 2*PI)
	var angle = rng.randf() * TAU
	var orbit_pos = Vector2(
		cos(angle) * orbit_radius_pixels,
		sin(angle) * orbit_radius_pixels
	)
	planet_node.position = orbit_pos
	
	# Create sprite
	var sprite = Sprite2D.new()
	var sprite_path = planet_data.get("sprite", "")
	
	# Try to load the sprite, fallback to placeholder
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
	else:
		# Placeholder - assume planets are ~128x128
		sprite.texture = PlaceholderTexture2D.new()
		sprite.texture.size = Vector2(128, 128)
		
		# Color by planet type
		var planet_type = planet_data.get("type", "rocky")
		if "terran" in planet_type or "primordial" in planet_type:
			sprite.modulate = Color.GREEN
		elif "ocean" in planet_type:
			sprite.modulate = Color.DEEP_SKY_BLUE
		elif "ice" in planet_type:
			sprite.modulate = Color.LIGHT_CYAN
		elif "gas" in planet_type:
			sprite.modulate = Color.SANDY_BROWN
		elif "volcanic" in planet_type:
			sprite.modulate = Color.ORANGE_RED
		elif "desert" in planet_type:
			sprite.modulate = Color.SANDY_BROWN
		elif "toxic" in planet_type:
			sprite.modulate = Color.DARK_GREEN
		else:
			sprite.modulate = Color.GRAY
	
	var base_scale = Vector2.ONE * PLANET_BASE_SCALE
	sprite.scale = base_scale
	planet_node.add_child(sprite)
	
	# Store base scale for distance scaling
	planet_node.set_meta("base_scale", base_scale)
	
	stellar_bodies.add_child(planet_node)
	print("  Spawned planet: %s (type: %s, orbit: %.1f AU)" % [
		planet_node.name,
		planet_data.get("type", "Unknown"),
		orbit_radius_au
	])

func _spawn_asteroid_belt(belt_data: Dictionary) -> void:
	# Get belt orbital data
	var orbit = belt_data.get("orbit", {})
	var belt_radius_au = orbit.get("a_AU", 3.0)
	var belt_radius_pixels = belt_radius_au * AU_TO_PIXELS
	
	# Create a container for the belt
	var belt_container = Node2D.new()
	belt_container.name = belt_data.get("id", "belt")
	belt_container.position = Vector2.ZERO
	
	# Generate random seed from belt ID
	var belt_id = belt_data.get("id", "belt:0")
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(belt_id)
	
	# Spawn asteroids in a ring
	var asteroid_count = BELT_ASTEROID_COUNT
	for i in range(asteroid_count):
		var asteroid_node = Node2D.new()
		asteroid_node.name = "belt_asteroid_%d" % i
		
		# Random angle around the ring
		var angle = rng.randf() * TAU
		
		# Random distance from belt center (creates thickness)
		var thickness = belt_radius_pixels * 0.15  # Belt is 15% thick
		var distance = belt_radius_pixels + rng.randf_range(-thickness, thickness)
		
		asteroid_node.position = Vector2(
			cos(angle) * distance,
			sin(angle) * distance
		)
		
		# Create sprite
		var sprite = Sprite2D.new()
		var sprite_path = ContentDB.get_asteroid_sprite(rng)
		
		if sprite_path != "" and ResourceLoader.exists(sprite_path):
			sprite.texture = load(sprite_path)
		else:
			# Placeholder asteroid
			sprite.texture = PlaceholderTexture2D.new()
			sprite.texture.size = Vector2(32, 32)
			sprite.modulate = Color.GRAY
		
		# Random rotation
		sprite.rotation = rng.randf() * TAU
		
		# Random scale (smaller than sector asteroids)
		var base_scale = Vector2.ONE * rng.randf_range(0.05, 0.15)
		sprite.scale = base_scale
		asteroid_node.add_child(sprite)
		
		# Store base scale for distance scaling
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
	
	# Configure streamer
	streamer.set_tile_parent(sectors)
	streamer.enable_streaming(true)
	
	print("SystemExploration: Sector streaming enabled")

func _input(event: InputEvent) -> void:
	# Handle mode-specific inputs
	if event.is_action_pressed("ui_map"):
		_toggle_galaxy_map()
	elif event.is_action_pressed("ui_map_system"):
		_toggle_system_map()

func _toggle_galaxy_map() -> void:
	# Signal to open galaxy map overlay
	EventBus.map_toggled.emit("galaxy", true)
	print("SystemExploration: Galaxy map toggle requested")

func _toggle_system_map() -> void:
	# Signal to open system map overlay
	EventBus.map_toggled.emit("system", true)
	print("SystemExploration: System map toggle requested")

func _exit_tree() -> void:
	# Cleanup when leaving this mode
	if streamer:
		streamer.enable_streaming(false)
		streamer.clear_all_tiles()
	
	print("SystemExploration: Cleanup complete")

# Public API for other systems

func get_current_system_data() -> Dictionary:
	return current_system_data

func get_system_name() -> String:
	var system_id = GameState.current_system_id
	var system_info = _find_system_in_galaxy(system_id)
	return system_info.get("name", system_id)

func teleport_ship(new_position: Vector2) -> void:
	if player_ship:
		player_ship.global_position = new_position
		player_ship.velocity = Vector2.ZERO
		GameState.ship_position = new_position
		GameState.ship_velocity = Vector2.ZERO
		print("SystemExploration: Ship teleported to ", new_position)

func get_player_ship() -> CharacterBody2D:
	return player_ship

# Debug functions

func debug_print_system_info() -> void:
	print("=== System Exploration Debug ===")
	print("System ID: ", GameState.current_system_id)
	print("System Name: ", get_system_name())
	print("Ship Position: ", player_ship.global_position if player_ship else "N/A")
	print("Ship Velocity: ", player_ship.velocity if player_ship else "N/A")
	print("Current Sector: ", GameState.current_sector)
	print("Active Tiles: ", streamer.get_active_tile_count() if streamer else 0)
	print("Stars: ", current_system_data.get("stars", []).size())
	print("Bodies: ", current_system_data.get("bodies", []).size())
	print("================================")

func debug_force_streaming_refresh() -> void:
	if streamer:
		streamer.force_refresh()
		print("SystemExploration: Forced streaming refresh")
