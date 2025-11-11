extends Node2D
class_name Station

# Station scene script
# Handles initialization, sprite loading, and interaction

var station_data: Dictionary = {}
var station_id: String = ""
var station_kind: String = ""

func _ready() -> void:
	# Set collision layer for stations
	var area = get_node_or_null("Area2D")
	if area:
		area.collision_layer = 4
		area.collision_mask = 1  # Detect player

func initialize(data: Dictionary, system_id: String) -> void:
	station_data = data
	station_id = data.get("id", "unknown")
	station_kind = data.get("kind", "generic")
	name = station_id
	
	# Position stations in orbit (simplified - ring around center)
	# TODO: Later we can orbit specific planets or be at specific coordinates
	var angle = hash(station_id) % 360
	var orbit_radius = 3.0 * 4000.0  # 3 AU from star in pixels
	position = Vector2(
		cos(deg_to_rad(angle)) * orbit_radius,
		sin(deg_to_rad(angle)) * orbit_radius
	)
	
	# Load sprite based on station kind
	_setup_sprite(data)
	
	print("  Station initialized: %s (kind: %s)" % [station_id, station_kind])

func _setup_sprite(data: Dictionary) -> void:
	var sprite = get_node("Sprite2D")
	# Try to get sprite based on station kind
	var sprite_path = _get_station_sprite_path(data.get("kind", "generic"))
	
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
	else:
		# Fallback: create placeholder
		_create_placeholder(data.get("kind", "generic"))
	
	sprite.scale = Vector2.ONE * 0.5  # Stations are medium-sized

func _get_station_sprite_path(kind: String) -> String:
	# TODO: Use ContentDB to get proper sprite paths
	# For now, return empty to use placeholder
	return ""

func _create_placeholder(kind: String) -> void:
	var sprite = get_node("Sprite2D")
	# Create colored placeholder based on station type
	sprite.texture = PlaceholderTexture2D.new()
	sprite.texture.size = Vector2(64, 64)
	
	# Color based on station kind
	match kind:
		"warp_gate":
			sprite.modulate = Color.CYAN
		"ore_processor":
			sprite.modulate = Color.ORANGE
		"corporate_mining":
			sprite.modulate = Color.GOLD
		_:
			sprite.modulate = Color.LIGHT_GRAY

func get_station_data() -> Dictionary:
	return station_data

func interact() -> void:
	# Called when player interacts with station
	print("Interacting with station: %s" % station_id)
	# TODO: Emit signal or call interaction system
