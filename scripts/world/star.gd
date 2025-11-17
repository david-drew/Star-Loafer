extends Node2D
class_name Star

# Star scene script
# Handles initialization, sprite loading, and visual effects

var sprite:Sprite2D
var star_data: Dictionary = {}
var base_scale: Vector2 = Vector2.ONE
var star_id: String = ""

func initialize(data: Dictionary, index: int = 0) -> void:
	star_data = data
	star_id = data.get("id", "star:A")
	name = star_id
	
	sprite = get_node("Sprite2D")
	
	# Position stars with offset if multiple (binary/trinary systems)
	if index > 0:
		position = Vector2(index * 1500, 0)  # Offset for binary/trinary
	
	# Load sprite
	_setup_sprite(data)
	
	# Setup lighting
	_setup_light(data)
	
	# Store base scale for LOD system
	base_scale = sprite.scale
	set_meta("base_scale", base_scale)
	
	print("  Star initialized: %s (class: %s)" % [
		star_id,
		data.get("class", "Unknown")
	])

func _setup_sprite(data: Dictionary) -> void:
	var sprite_path = data.get("sprite", "")
	
	# Try to load sprite asset
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
	else:
		# Fallback: create placeholder based on star class
		_create_placeholder(data.get("class", "G"))
	
	# Stars are larger than planets
	sprite.scale = Vector2.ONE * 1.5

func _create_placeholder(star_class: String) -> void:
	# Create colored placeholder texture based on star class
	sprite.texture = PlaceholderTexture2D.new()
	sprite.texture.size = Vector2(1024, 1024)  # Stars are large
	
	# Color based on spectral class
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
	else:
		sprite.modulate = Color.YELLOW

func _setup_light(data: Dictionary) -> void:
	var light = get_node("PointLight2D")
	# Add glow effect
	light.texture_scale = 5.0
	light.energy = 1.5
	light.color = sprite.modulate

func set_lod_scale(scale_factor: float) -> void:
	# Called by centralized LOD system
	sprite.scale = base_scale * scale_factor

func get_star_data() -> Dictionary:
	return star_data
