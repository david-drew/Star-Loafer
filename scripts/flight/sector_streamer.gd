extends Node
class_name SectorStreamer

signal tile_spawned(tile_id: String, tile_data: Dictionary)
signal tile_despawned(tile_id: String)

const SECTOR_SIZE = 4096  # World units per tile (changed from 1024 to reduce lag)
const RING_RADIUS = 2  # Load ±2 ring around player (prevents pop-in, loads 25 tiles instead of 9)

var active_tiles: Dictionary = {}  # {tile_id: Node2D}
var current_player_sector: Vector2i = Vector2i.ZERO
var tile_parent: Node2D = null
var streaming_enabled: bool = false

var asteroid_scene = preload("res://scenes/world/asteroid.tscn")
var texture_cache: Dictionary = {}  # Cache loaded textures to avoid repeated load() calls

func _process(_delta: float) -> void:
	if !streaming_enabled or tile_parent == null:
		return
	
	var player_pos = GameState.ship_position
	var player_sector = _world_to_sector(player_pos)
	
	if player_sector != current_player_sector:
		current_player_sector = player_sector
		GameState.current_sector = player_sector
		_update_streaming()

func _world_to_sector(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / SECTOR_SIZE)),
		int(floor(world_pos.y / SECTOR_SIZE))
	)

func _update_streaming() -> void:
	var required_tiles = _get_ring_tiles(current_player_sector, RING_RADIUS)
	
	# Despawn tiles outside ring
	for tile_id in active_tiles.keys():
		if tile_id not in required_tiles:
			_despawn_tile(tile_id)
	
	# Spawn new tiles
	for tile_id in required_tiles:
		if tile_id not in active_tiles:
			_spawn_tile(tile_id)

func _get_ring_tiles(center: Vector2i, radius: int) -> Array:
	var tiles = []
	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			tiles.append("%d,%d" % [x, y])
	return tiles

func _spawn_tile(tile_id: String) -> void:
	if tile_parent == null:
		push_error("SectorStreamer: Cannot spawn tile, tile_parent is null!")
		return
	
	var coords = tile_id.split(",")
	var q = int(coords[0])
	var r = int(coords[1])
	
	var tile_seed = hash(GameState.galaxy_seed) ^ hash(GameState.current_system_id.hash()) ^ hash(tile_id.hash())
	var rng = RandomNumberGenerator.new()
	rng.seed = tile_seed
	
	# Calculate distance from origin in world units (not sectors)
	var tile_center_world = Vector2(q * SECTOR_SIZE + SECTOR_SIZE / 2, r * SECTOR_SIZE + SECTOR_SIZE / 2)
	var distance_from_origin_pixels = tile_center_world.length()
	var distance_from_origin_AU = distance_from_origin_pixels / 4000.0  # Convert to AU (changed from 8000)
	
	# Determine biome based on AU distance (match expanded system generation)
	# System now extends to 40 AU to fit 15 planets comfortably
	# Inner system (0-2 AU): Very sparse, rocky planet zone
	# Inner belt (2-4 AU): Dense asteroid field
	# Mid system (4-15 AU): Scattered, gas giant zone  
	# Outer belt (15-25 AU): Moderate density, Kuiper belt analog
	# Outer system (25-40 AU): Very sparse, ice dwarf zone
	# Deep space (40+ AU): Extremely sparse
	var biome_id = "deep_space"
	var asteroid_count = 0
	
	if distance_from_origin_AU < 5.0:
		# Inner system: very sparse
		if rng.randf() < 0.3:
			asteroid_count = rng.randi_range(0, 2)
		biome_id = "inner_system"
	elif distance_from_origin_AU < 15.0:
		# Mid system: sparse
		if rng.randf() < 0.4:
			asteroid_count = rng.randi_range(1, 3)
		biome_id = "mid_system"
	elif distance_from_origin_AU < 25.0:
		# Middle belt (15-25 AU): Dense
		asteroid_count = rng.randi_range(15, 30)
		biome_id = "middle_belt"
	elif distance_from_origin_AU < 40.0:
		# Between belts: scattered
		asteroid_count = rng.randi_range(2, 6)
		biome_id = "outer_system"
	elif distance_from_origin_AU < 60.0:
		# Outer belt (40-60 AU): Dense
		asteroid_count = rng.randi_range(12, 25)
		biome_id = "outer_belt"
	else:
		# Deep space: very sparse
		if rng.randf() < 0.15:
			asteroid_count = rng.randi_range(0, 1)
		biome_id = "deep_space"
	
	# Create container
	var tile_container = Node2D.new()
	tile_container.name = "Tile_%s" % tile_id
	tile_container.position = Vector2(q * SECTOR_SIZE, r * SECTOR_SIZE)
	tile_parent.add_child(tile_container)
	
	# Spawn asteroids
	for i in range(asteroid_count):
		var asteroid = asteroid_scene.instantiate()
		asteroid.position = Vector2(
			rng.randf_range(0, SECTOR_SIZE),
			rng.randf_range(0, SECTOR_SIZE)
		)
		asteroid.rotation = rng.randf() * TAU
		
		# Scale varies by biome
		var scale_min = 0.25
		var scale_max = 2.0
		if biome_id == "belt_field":
			scale_min = 0.5
			scale_max = 3.0  # Bigger asteroids in belt
		
		asteroid.scale = Vector2.ONE * rng.randf_range(scale_min, scale_max)
		
		# Set sprite using cached texture
		var sprite_path = ContentDB.get_asteroid_sprite(rng)
		if sprite_path != "":
			# Check cache first
			if sprite_path not in texture_cache:
				if ResourceLoader.exists(sprite_path):
					texture_cache[sprite_path] = load(sprite_path)
			
			# Apply cached texture
			if sprite_path in texture_cache:
				var sprite_node = asteroid.get_node_or_null("Sprite2D")
				if sprite_node:
					sprite_node.texture = texture_cache[sprite_path]
		
		tile_container.add_child(asteroid)
	
	active_tiles[tile_id] = tile_container
	tile_spawned.emit(tile_id, {})
	
	if asteroid_count > 0:
		print("SectorStreamer: Spawned tile %s (%s, %.1f AU) with %d asteroids" % [tile_id, biome_id, distance_from_origin_AU, asteroid_count])

func _despawn_tile(tile_id: String) -> void:
	if tile_id in active_tiles:
		active_tiles[tile_id].queue_free()
		active_tiles.erase(tile_id)
		tile_despawned.emit(tile_id)
		print("SectorStreamer: Despawned tile %s" % tile_id)

# Public API

func set_tile_parent(parent: Node2D) -> void:
	tile_parent = parent
	print("SectorStreamer: Tile parent set to ", parent.name if parent else "null")

func enable_streaming(enabled: bool) -> void:
	streaming_enabled = enabled
	if enabled:
		print("SectorStreamer: Streaming enabled")
		# Force immediate update
		current_player_sector = _world_to_sector(GameState.ship_position)
		GameState.current_sector = current_player_sector
		_update_streaming()
	else:
		print("SectorStreamer: Streaming disabled")

func clear_all_tiles() -> void:
	for tile_id in active_tiles.keys():
		_despawn_tile(tile_id)
	active_tiles.clear()
	print("SectorStreamer: All tiles cleared")

func get_active_tile_count() -> int:
	return active_tiles.size()

func force_refresh() -> void:
	print("SectorStreamer: Forcing refresh...")
	clear_all_tiles()
	if streaming_enabled and tile_parent != null:
		current_player_sector = _world_to_sector(GameState.ship_position)
		GameState.current_sector = current_player_sector
		_update_streaming()
