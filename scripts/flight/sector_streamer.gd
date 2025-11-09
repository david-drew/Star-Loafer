extends Node
class_name SectorStreamer

signal tile_spawned(tile_id: String, tile_data: Dictionary)
signal tile_despawned(tile_id: String)

const SECTOR_SIZE = 4096  	# World units per tile
const RING_RADIUS = 2 	 	# Load ±1 ring around player

var active_tiles: Dictionary = {}  # {tile_id: Node2D}
var current_player_sector: Vector2i = Vector2i.ZERO
var tile_parent: Node2D = null
var streaming_enabled: bool = false

var asteroid_scene = preload("res://scenes/world/asteroid.tscn")

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
	
	# Determine biome based on distance from origin
	var distance_from_origin = Vector2i(q, r).length()
	var biome_id = "deep_space"
	if distance_from_origin < 3:
		biome_id = "inner_lane"
	elif distance_from_origin < 6:
		biome_id = "belt_field"
	
	var profile = ContentDB.get_sector_profile(biome_id)
	if profile.is_empty():
		push_warning("SectorStreamer: No profile found for biome '%s', using empty profile" % biome_id)
		profile = {"asteroid_density": [0, 5]}
	
	# Create container
	var tile_container = Node2D.new()
	tile_container.name = "Tile_%s" % tile_id
	tile_container.position = Vector2(q * SECTOR_SIZE, r * SECTOR_SIZE)
	tile_parent.add_child(tile_container)
	
	# Spawn asteroids
	var asteroid_count = rng.randi_range(
		profile.get("asteroid_density", [0, 10])[0],
		profile.get("asteroid_density", [0, 10])[1]
	)
	
	for i in range(asteroid_count):
		var asteroid = asteroid_scene.instantiate()
		asteroid.position = Vector2(
			rng.randf_range(0, SECTOR_SIZE),
			rng.randf_range(0, SECTOR_SIZE)
		)
		asteroid.rotation = rng.randf() * TAU
		asteroid.scale = Vector2.ONE * rng.randf_range(0.25, 5.0)
		
		# Set sprite
		var sprite_path = ContentDB.get_asteroid_sprite(rng)
		if ResourceLoader.exists(sprite_path):
			var sprite_node = asteroid.get_node_or_null("Sprite2D")
			if sprite_node:
				sprite_node.texture = load(sprite_path)
		
		tile_container.add_child(asteroid)
	
	active_tiles[tile_id] = tile_container
	tile_spawned.emit(tile_id, {})
	
	print("SectorStreamer: Spawned tile %s with %d asteroids" % [tile_id, asteroid_count])

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
