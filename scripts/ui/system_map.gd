extends Control

# system_map.gd
# Displays the current star system with planets, belts, and stations

@onready var system_view = $MapContainer/SystemView
@onready var info_panel = $InfoPanel
@onready var center_marker = $MapContainer/CenterMarker
@onready var close_button = $CloseButton

var body_icons: Dictionary = {}
var station_icons: Dictionary = {}
var hovered_object: Dictionary = {}
var hover_timer: float = 0.0
var player_icon: Node2D = null  # Player ship indicator

const MAP_SCALE = 80.0  # Pixels per AU (for map display, not world space)
const ICON_SIZE = Vector2(24, 24)

func _ready() -> void:
	hide()
	info_panel.hide()
	
	# Connect button with null check
	if close_button:
		close_button.pressed.connect(_on_close)
	
	# Connect to EventBus signals
	EventBus.map_toggled.connect(_on_map_toggled)
	
	print("SystemMap: Ready and listening for toggle events")

func _input(event: InputEvent) -> void:
	if !visible:
		return  # Don't handle input when not visible
	
	if event.is_action_pressed("ui_map_system"):
		# Close the map
		hide()
		get_viewport().set_input_as_handled()
		print("SystemMap: Closed via key press")

func _on_map_toggled(map_type: String, should_open: bool) -> void:
	if map_type == "system":
		if should_open:
			show()
			_populate_map()
			print("SystemMap: Opened")
		else:
			hide()
			print("SystemMap: Closed")

func toggle() -> void:
	visible = !visible
	if visible:
		_populate_map()
		print("SystemMap: Toggled ON")
	else:
		print("SystemMap: Toggled OFF")

func _populate_map() -> void:
	# Clear existing icons
	for child in system_view.get_children():
		child.queue_free()
	body_icons.clear()
	station_icons.clear()
	
	# Get system data from SystemExploration
	var system_exploration = get_node_or_null("/root/GameRoot/WorldRoot/SystemExploration")
	if system_exploration == null:
		push_warning("SystemMap: SystemExploration not found")
		return
	
	var system_data = system_exploration.get_current_system_data()
	if system_data.is_empty():
		push_warning("SystemMap: No system data available")
		return
	
	var map_center = $MapContainer.size / 2.0
	
	print("SystemMap: Populating system '%s'" % system_data.get("system_id", "Unknown"))
	
	# Draw star(s) at center
	for star in system_data.get("stars", []):
		_create_star_icon(star, map_center)
	
	# Draw planets and belts
	for body in system_data.get("bodies", []):
		_create_body_icon(body, map_center)
	
	# Draw stations
	for station in system_data.get("stations", []):
		_create_station_icon(station, map_center)
	
	# Add player ship icon
	_create_player_ship_icon(map_center)
	
	print("SystemMap: Added %d bodies and %d stations" % [body_icons.size(), station_icons.size()])

func _create_player_ship_icon(map_center: Vector2) -> void:
	# Remove old player icon if it exists
	if player_icon:
		player_icon.queue_free()
		player_icon = null
	
	# Get player ship position from SystemExploration
	var system_exploration = get_node_or_null("/root/GameRoot/WorldRoot/SystemExploration")
	if system_exploration == null:
		return
	
	var player_ship = system_exploration.get_player_ship()
	if player_ship == null:
		return
	
	# Create player ship icon container
	player_icon = Node2D.new()
	player_icon.name = "PlayerShipIcon"
	
	# Create sprite
	var sprite = Sprite2D.new()
	
	# Try to load ship icon asset, fallback to distinctive arrow
	var ship_icon_path = "res://assets/images/ui/ship_icon.png"
	if ResourceLoader.exists(ship_icon_path):
		sprite.texture = load(ship_icon_path)
		sprite.modulate = Color.YELLOW  # Tint asset yellow!
		sprite.scale = Vector2(0.8, 0.8)  # Make it slightly smaller
	else:
		# Fallback: Smaller yellow arrow (more distinctive)
		sprite.texture = PlaceholderTexture2D.new()
		sprite.texture.size = Vector2(20, 20)  # Smaller than planets (20 vs 24)
		sprite.modulate = Color(1.0, 0.9, 0.0, 1.0)  # Bright yellow/gold
	
	sprite.rotation = -PI / 2  # Point right by default
	player_icon.add_child(sprite)
	
	# Position will be updated in _process
	system_view.add_child(player_icon)
	player_icon.z_index = 100  # On top of everything

func _create_star_icon(star: Dictionary, map_center: Vector2) -> void:
	var icon = TextureRect.new()
	icon.texture = PlaceholderTexture2D.new()
	icon.texture.size = ICON_SIZE * 1.5  # Stars larger
	icon.custom_minimum_size = ICON_SIZE * 1.5
	icon.position = map_center - (ICON_SIZE * 1.5) / 2.0
	
	# Color based on star class
	var star_class = star.get("class", "G")
	if star_class == "Special":
		icon.modulate = Color.PURPLE
	elif star_class in ["O", "B"]:
		icon.modulate = Color.DODGER_BLUE
	elif star_class == "A":
		icon.modulate = Color.WHITE
	elif star_class == "F":
		icon.modulate = Color.LIGHT_YELLOW
	elif star_class == "G":
		icon.modulate = Color.YELLOW
	elif star_class == "K":
		icon.modulate = Color.ORANGE
	elif star_class == "M":
		icon.modulate = Color.INDIAN_RED
	
	icon.mouse_entered.connect(_on_object_hover.bind(star))
	icon.mouse_exited.connect(_on_object_unhover)
	
	system_view.add_child(icon)

func _create_body_icon(body: Dictionary, map_center: Vector2) -> void:
	var body_kind = body.get("kind", "planet")
	var body_id = body.get("id", "")
	
	# Phase 0: Show all bodies in current system (no fog of war within system)
	
	var icon = TextureRect.new()
	icon.texture = PlaceholderTexture2D.new()
	icon.texture.size = ICON_SIZE
	icon.custom_minimum_size = ICON_SIZE
	
	# Position based on orbit
	var orbit = body.get("orbit", {})
	var orbit_radius = orbit.get("a_AU", 1.0)
	var angle = hash(body_id) % 360  # Pseudo-random angle
	var offset = Vector2(
		cos(deg_to_rad(angle)) * orbit_radius * MAP_SCALE,
		sin(deg_to_rad(angle)) * orbit_radius * MAP_SCALE
	)
	icon.position = map_center + offset - ICON_SIZE / 2.0
	
	# Color based on body type
	if body_kind == "asteroid_belt":
		icon.modulate = Color.GRAY
	else:
		var body_type = body.get("type", "rocky")
		if "terran" in body_type or "primordial" in body_type:
			icon.modulate = Color.GREEN
		elif "ocean" in body_type:
			icon.modulate = Color.DEEP_SKY_BLUE
		elif "ice" in body_type:
			icon.modulate = Color.LIGHT_CYAN
		elif "gas" in body_type:
			icon.modulate = Color.SANDY_BROWN
		elif "volcanic" in body_type:
			icon.modulate = Color.ORANGE_RED
		else:
			icon.modulate = Color.LIGHT_GRAY
	
	icon.mouse_entered.connect(_on_object_hover.bind(body))
	icon.mouse_exited.connect(_on_object_unhover)
	
	system_view.add_child(icon)
	body_icons[body_id] = icon

func _create_station_icon(station: Dictionary, map_center: Vector2) -> void:
	var station_id = station.get("id", "")
	
	# Phase 0: Show all stations in current system (no fog of war within system)
	
	var icon = TextureRect.new()
	icon.texture = PlaceholderTexture2D.new()
	icon.texture.size = ICON_SIZE * 0.8
	icon.custom_minimum_size = ICON_SIZE * 0.8
	
	# Position stations in a ring around center (simplified)
	var angle = hash(station_id) % 360
	var offset = Vector2(
		cos(deg_to_rad(angle)) * 3.0 * MAP_SCALE,
		sin(deg_to_rad(angle)) * 3.0 * MAP_SCALE
	)
	icon.position = map_center + offset - (ICON_SIZE * 0.8) / 2.0
	icon.modulate = Color.CYAN
	
	icon.mouse_entered.connect(_on_object_hover.bind(station))
	icon.mouse_exited.connect(_on_object_unhover)
	
	system_view.add_child(icon)
	station_icons[station_id] = icon

func _process(delta: float) -> void:
	if !visible:
		return
	
	# Update player ship icon position
	_update_player_ship_position()
	
	# Handle hover info panel
	if hovered_object.is_empty():
		hover_timer = 0.0
		info_panel.hide()
	else:
		hover_timer += delta
		if hover_timer >= 0.5:
			_show_info_panel(hovered_object)

func _update_player_ship_position() -> void:
	if player_icon == null:
		return
	
	var system_exploration = get_node_or_null("/root/GameRoot/WorldRoot/SystemExploration")
	if system_exploration == null:
		return
	
	var player_ship = system_exploration.get_player_ship()
	if player_ship == null:
		return
	
	# Convert player world position to map position
	var map_center = $MapContainer.size / 2.0
	var player_world_pos = player_ship.global_position
	
	# Scale down from world space (8000 pixels/AU) to map space (80 pixels/AU)
	var world_to_map_scale = MAP_SCALE / 8000.0  # 80 / 8000 = 0.01
	var map_offset = player_world_pos * world_to_map_scale
	
	player_icon.position = map_center + map_offset
	
	# Update rotation to match ship facing
	var sprite = player_icon.get_node_or_null("Sprite2D")
	if sprite and player_ship:
		sprite.rotation = player_ship.rotation

func _on_object_hover(obj: Dictionary) -> void:
	hovered_object = obj
	hover_timer = 0.0

func _on_object_unhover() -> void:
	hovered_object = {}

func _show_info_panel(obj: Dictionary) -> void:
	info_panel.show()
	
	# Display different info based on object type
	if obj.has("class"):  # Star
		$InfoPanel/VBoxContainer/NameLabel.text = obj.get("id", "Unknown Star")
		$InfoPanel/VBoxContainer/TypeLabel.text = "Class: %s" % obj.get("class", "Unknown")
		$InfoPanel/VBoxContainer/DetailLabel.text = ""
	elif obj.has("kind"):  # Body or Station
		var kind = obj.get("kind", "unknown")
		$InfoPanel/VBoxContainer/NameLabel.text = obj.get("id", "Unknown")
		
		if kind == "planet":
			$InfoPanel/VBoxContainer/TypeLabel.text = "Planet: %s" % obj.get("type", "Unknown")
			var orbit = obj.get("orbit", {})
			$InfoPanel/VBoxContainer/DetailLabel.text = "Orbit: %.1f AU" % orbit.get("a_AU", 0.0)
		elif kind == "asteroid_belt":
			$InfoPanel/VBoxContainer/TypeLabel.text = "Asteroid Belt"
			var orbit = obj.get("orbit", {})
			$InfoPanel/VBoxContainer/DetailLabel.text = "Orbit: %.1f AU" % orbit.get("a_AU", 0.0)
		else:  # Station
			$InfoPanel/VBoxContainer/TypeLabel.text = "Station: %s" % obj.get("kind", "Unknown")
			$InfoPanel/VBoxContainer/DetailLabel.text = ""

func _on_close() -> void:
	hide()
	print("SystemMap: Closed via button")
