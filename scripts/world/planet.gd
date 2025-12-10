extends Node2D
class_name Planet

# Planet scene script
# Handles initialization, sprite loading, and visual properties
var sprite:Sprite2D
var planet_data: Dictionary = {}
var base_scale: Vector2 = Vector2.ONE
var planet_id: String = ""

func initialize(data: Dictionary, seed: int) -> void:
	planet_data = data
	planet_id = data.get("id", "unknown")
	name = planet_id
	# Mark comm group if inhabited (planets and moons share this script) # DEBUG
	var pop_level := int(planet_data.get("population", planet_data.get("inhabitant_data", {}).get("population_level", 0)))
	if pop_level > 0:
		add_to_group("inhabited_body")
	
	# Set position based on orbit data
	var orbit = data.get("orbit", {})
	var orbit_radius_au = orbit.get("a_AU", 1.0)
	var orbit_radius_pixels = orbit_radius_au * 4000.0  # AU_TO_PIXELS constant
	var angle = orbit.get("angle_rad", 0.0)
	
	position = Vector2(
		cos(angle) * orbit_radius_pixels,
		sin(angle) * orbit_radius_pixels
	)
	
	# Load sprite
	_setup_sprite(data)
	
	# Store base scale metadata for LOD system
	set_meta("base_scale", sprite.scale)
	
	print("  Planet initialized: %s (type: %s, orbit: %.1f AU)" % [
		planet_id,
		data.get("type", "unknown"),
		orbit_radius_au
	])

func _setup_sprite(data: Dictionary) -> void:
	sprite = get_node("Sprite2D")
	var sprite_path = data.get("sprite", "")
	
	# Try to load sprite asset
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
	else:
		# Fallback: create placeholder based on planet type
		_create_placeholder(data.get("type", "rocky"))
	
	# Set initial scale (will be adjusted by LOD system)
	sprite.scale = Vector2.ONE * 0.5  # Base planet scale
	base_scale = sprite.scale

func _create_placeholder(planet_type: String) -> void:
	sprite = get_node("Sprite2D")
	# Create colored placeholder texture based on type
	sprite.texture = PlaceholderTexture2D.new()
	sprite.texture.size = Vector2(128, 128)
	
	# Color based on planet type
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

func set_lod_scale(scale_factor: float) -> void:
	# Called by centralized LOD system in system_exploration
	sprite = get_node("Sprite2D")
	sprite.scale = base_scale * scale_factor

func get_planet_data() -> Dictionary:
	return planet_data
