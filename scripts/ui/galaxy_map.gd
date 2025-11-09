extends Control

@onready var systems_layer = $MapContainer/SystemsLayer
@onready var info_panel = $InfoPanel
@onready var fast_travel_button = $InfoPanel/VBoxContainer/FastTravelButton
@onready var close_button = $CloseButton

var system_icons: Dictionary = {}
var hovered_system: Dictionary = {}
var hover_timer: float = 0.0
var player_icon: TextureRect = null  # Player ship indicator

func _ready() -> void:
	hide()
	info_panel.hide()
	
	# Connect buttons with null checks
	if close_button:
		close_button.pressed.connect(_on_close)
	if fast_travel_button:
		fast_travel_button.pressed.connect(_on_fast_travel)
	
	# Connect to EventBus signals
	EventBus.map_toggled.connect(_on_map_toggled)
	
	print("GalaxyMap: Ready and listening for toggle events")

func _input(event: InputEvent) -> void:
	if !visible:
		return  # Don't handle input when not visible
	
	if event.is_action_pressed("ui_map"):
		# Close the map
		hide()
		get_viewport().set_input_as_handled()
		print("GalaxyMap: Closed via key press")

func _on_map_toggled(map_type: String, should_open: bool) -> void:
	if map_type == "galaxy":
		if should_open:
			show()
			_populate_map()
			print("GalaxyMap: Opened")
		else:
			hide()
			print("GalaxyMap: Closed")

func toggle() -> void:
	visible = !visible
	if visible:
		_populate_map()
		print("GalaxyMap: Toggled ON")
	else:
		print("GalaxyMap: Toggled OFF")

func _populate_map() -> void:
	# Clear existing icons
	for child in systems_layer.get_children():
		child.queue_free()
	system_icons.clear()
	
	var galaxy_data = GameState.galaxy_data
	if galaxy_data.is_empty():
		push_warning("GalaxyMap: No galaxy data available")
		return
	
	var map_size = $MapContainer.size
	var systems = galaxy_data.get("systems", [])
	
	print("GalaxyMap: Populating map with %d total systems" % systems.size())
	
	var current_system_pos = Vector2.ZERO
	for system in systems:
		if system["id"] == GameState.current_system_id:
			current_system_pos = Vector2(system["pos"][0], system["pos"][1])
			break
	
	var icons_added = 0
	for system in systems:
		var system_id = system["id"]
		
		# For Phase 0: Show systems that are discovered OR within reasonable distance
		var is_discovered = GameState.is_discovered("galaxy", system_id)
		var system_pos = Vector2(system["pos"][0], system["pos"][1])
		var distance = current_system_pos.distance_to(system_pos)
		var is_nearby = distance < 0.3  # Show systems within 30% of map size
		
		# Show if discovered, nearby, or is current system
		if !is_discovered and !is_nearby and system_id != GameState.current_system_id:
			continue
		
		var icon = TextureRect.new()
		icon.texture = PlaceholderTexture2D.new()
		icon.texture.size = Vector2(16, 16)
		icon.custom_minimum_size = Vector2(16, 16)
		
		# Position on map
		var pos = Vector2(system["pos"][0], system["pos"][1])
		icon.position = pos * map_size - Vector2(8, 8)
		
		# Highlight current system
		if system_id == GameState.current_system_id:
			icon.modulate = Color.YELLOW
		else:
			icon.modulate = Color.WHITE
		
		icon.mouse_entered.connect(_on_system_hover.bind(system))
		icon.mouse_exited.connect(_on_system_unhover)
		icon.gui_input.connect(_on_system_clicked.bind(system))
		
		systems_layer.add_child(icon)
		system_icons[system_id] = icon
		icons_added += 1
	
	# Add player ship icon
	_create_player_icon(current_system_pos, map_size)
	
	print("GalaxyMap: Added %d system icons" % icons_added)

func _create_player_icon(current_system_pos: Vector2, map_size: Vector2) -> void:
	# Remove old player icon if it exists
	if player_icon:
		player_icon.queue_free()
		player_icon = null
	
	# Create player ship icon
	player_icon = TextureRect.new()
	
	# Try to load ship icon asset, fallback to distinctive arrow
	var ship_icon_path = "res://assets/images/ui/ship_icon.png"
	if ResourceLoader.exists(ship_icon_path):
		player_icon.texture = load(ship_icon_path)
		player_icon.custom_minimum_size = Vector2(20, 20)
		player_icon.modulate = Color.YELLOW  # Tint asset yellow too!
	else:
		# Fallback: Smaller yellow triangle/arrow (more distinctive than square)
		player_icon.texture = PlaceholderTexture2D.new()
		player_icon.texture.size = Vector2(16, 16)  # Smaller than system icons (16 vs 20)
		player_icon.modulate = Color(1.0, 0.9, 0.0, 1.0)  # Bright yellow/gold
	
	# Position at current system
	player_icon.position = current_system_pos * map_size - Vector2(8, 8)
	
	# Make it stand out
	player_icon.z_index = 10
	
	systems_layer.add_child(player_icon)
	print("GalaxyMap: Added player ship indicator")

func _process(delta: float) -> void:
	if !visible:
		return
	
	if hovered_system.is_empty():
		hover_timer = 0.0
		info_panel.hide()
	else:
		hover_timer += delta
		if hover_timer >= 0.5:  # Reduced from 1.0 for faster feedback
			_show_info_panel(hovered_system)

func _on_system_hover(system: Dictionary) -> void:
	hovered_system = system
	hover_timer = 0.0

func _on_system_unhover() -> void:
	hovered_system = {}

func _show_info_panel(system: Dictionary) -> void:
	info_panel.show()
	$InfoPanel/VBoxContainer/SystemNameLabel.text = system["name"]
	$InfoPanel/VBoxContainer/PopLabel.text = "Population: %d/10" % system["pop_level"]
	$InfoPanel/VBoxContainer/TechLabel.text = "Tech Level: %d/10" % system["tech_level"]
	$InfoPanel/VBoxContainer/MiningLabel.text = "Mining: %d/10" % system["mining_quality"]
	
	# Enable fast travel if not current system
	if fast_travel_button:
		fast_travel_button.disabled = (system["id"] == GameState.current_system_id)

func _on_system_clicked(event: InputEvent, system: Dictionary) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if system["id"] != GameState.current_system_id:
			_on_fast_travel()

func _on_fast_travel() -> void:
	if !hovered_system.is_empty():
		EventBus.fast_travel_requested.emit(hovered_system["id"])
		hide()

func _on_close() -> void:
	hide()
	print("GalaxyMap: Closed via button")
