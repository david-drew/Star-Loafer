extends Control

# System map: shows current system bodies/stations/player with pan/zoom.

# Lightweight icon nodes (Controls with custom draw so they get mouse signals)
class IconDot:
	extends Control
	var radius: float = 4.0
	var color: Color = Color.WHITE
	func _ready() -> void:
		custom_minimum_size = Vector2.ONE * radius * 2.0
	func _draw() -> void:
		var center := size * 0.5
		draw_circle(center, radius, color)

class IconSquare:
	extends Control
	var size_vec: Vector2 = Vector2.ONE * 8.0
	var color: Color = Color.WHITE
	func _ready() -> void:
		custom_minimum_size = size_vec
	func _draw() -> void:
		var half := size_vec * 0.5
		var rect := Rect2((size * 0.5) - half, size_vec)
		draw_rect(rect, color)

class IconDiamond:
	extends Control
	var size_len: float = 8.0
	var color: Color = Color.WHITE
	func _ready() -> void:
		custom_minimum_size = Vector2.ONE * size_len * 2.0
	func _draw() -> void:
		var c := size * 0.5
		var pts := PackedVector2Array([
			c + Vector2(0, -size_len),
			c + Vector2(size_len, 0),
			c + Vector2(0, size_len),
			c + Vector2(-size_len, 0)
		])
		draw_colored_polygon(pts, color)

@onready var map_container: Control = $MapContainer
@onready var system_view: Control = $MapContainer/SystemView
@onready var info_panel = $InfoPanel
@onready var close_button = $CloseButton

var body_icons: Dictionary = {}
var station_icons: Dictionary = {}
var hovered_object: Dictionary = {}
var hover_timer: float = 0.0
var player_icon: Node2D = null  # Player ship indicator

var map_scale: float = 80.0  # pixels per AU (fit-to-view base scale)
const AU_TO_PIXELS = 4000.0  # Match SystemExploration's scaling

# Pan/zoom
var current_zoom: float = 1.0
const ZOOM_MIN = 0.35
const ZOOM_MAX = 3.0
const ZOOM_STEP = 0.1
var view_offset: Vector2 = Vector2.ZERO
var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var view_offset_start: Vector2 = Vector2.ZERO

# Performance: throttle player icon updates
const PLAYER_ICON_UPDATE_INTERVAL = 0.05
var player_icon_update_timer: float = 0.0

func _ready() -> void:
	hide()
	info_panel.hide()
	map_container.custom_minimum_size = get_viewport_rect().size * 0.5  # at least half screen
	system_view.position = map_container.size * 0.5
	
	if close_button:
		close_button.pressed.connect(_on_close)
	
	EventBus.map_toggled.connect(_on_map_toggled)
	print("SystemMap: Ready and listening for toggle events")

func _input(event: InputEvent) -> void:
	if !visible:
		return
	
	if event.is_action_pressed("ui_map_system"):
		hide()
		get_viewport().set_input_as_handled()
		return
	
	# Zoom with mouse wheel
	if event is InputEventMouseButton and map_container.get_rect().has_point(event.position):
		var emb := event as InputEventMouseButton
		if emb.button_index == MOUSE_BUTTON_WHEEL_UP and emb.pressed:
			_set_zoom(current_zoom + ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif emb.button_index == MOUSE_BUTTON_WHEEL_DOWN and emb.pressed:
			_set_zoom(current_zoom - ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif emb.button_index == MOUSE_BUTTON_LEFT:
			if emb.pressed:
				is_dragging = true
				drag_start = emb.position
				view_offset_start = view_offset
				get_viewport().set_input_as_handled()
			else:
				is_dragging = false
	
	# Drag pan with mouse motion
	if is_dragging and event is InputEventMouseMotion:
		var emm := event as InputEventMouseMotion
		view_offset = view_offset_start + (emm.position - drag_start)
		_apply_view_transform()
		get_viewport().set_input_as_handled()

func _on_map_toggled(map_type: String, should_open: bool) -> void:
	if map_type != "system":
		return
	if should_open:
		show()
		_reset_view()
		_populate_map()
	else:
		hide()

func toggle() -> void:
	visible = !visible
	if visible:
		_reset_view()
		_populate_map()

func _reset_view() -> void:
	current_zoom = 1.0
	view_offset = Vector2.ZERO
	_apply_view_transform()

func _apply_view_transform() -> void:
	system_view.scale = Vector2.ONE * current_zoom
	system_view.position = map_container.size * 0.5 + view_offset

func _set_zoom(value: float) -> void:
	current_zoom = clamp(value, ZOOM_MIN, ZOOM_MAX)
	_apply_view_transform()

func _populate_map() -> void:
	for child in system_view.get_children():
		child.queue_free()
	body_icons.clear()
	station_icons.clear()
	player_icon = null
	
	var system_exploration = get_node_or_null("/root/GameRoot/WorldRoot/SystemExploration")
	if system_exploration == null:
		push_warning("SystemMap: SystemExploration not found")
		return
	
	var system_data = system_exploration.get_current_system_data()
	if system_data.is_empty():
		push_warning("SystemMap: No system data available")
		return
	
	# Calculate fit-to-view scale
	var max_orbit := 0.0
	for body in system_data.get("bodies", []):
		var orbit: Dictionary = body.get("orbit", {})
		var radius := float(orbit.get("a_AU", 0.0))
		if radius > max_orbit:
			max_orbit = radius
	
	var min_dim:float = min(map_container.size.x, map_container.size.y)
	var available_radius:float = min_dim * 0.45  # leave margin
	if max_orbit > 0.0:
		map_scale = available_radius / (max_orbit * 1.2)
	else:
		map_scale = 80.0
	
	system_view.position = map_container.size * 0.5 + view_offset
	
	# Stars at center
	for star in system_data.get("stars", []):
		_create_star_icon(star)
	
	# Bodies
	for body in system_data.get("bodies", []):
		_create_body_icon(body)
	
	# Stations
	for station in system_data.get("stations", []):
		_create_station_icon(station)
	
	# Player ship
	_create_player_ship_icon()

func _create_player_ship_icon() -> void:
	if player_icon:
		player_icon.queue_free()
		player_icon = null
	
	var system_exploration = get_node_or_null("/root/GameRoot/WorldRoot/SystemExploration")
	if system_exploration == null:
		return
	var player_ship = system_exploration.get_player_ship()
	if player_ship == null:
		return
	
	player_icon = Node2D.new()
	player_icon.name = "PlayerShipIcon"
	var sprite = Sprite2D.new()
	var ship_icon_path = "res://assets/images/ui/ship_icon.png"
	if ResourceLoader.exists(ship_icon_path):
		sprite.texture = load(ship_icon_path)
		sprite.modulate = Color(1.0, 0.9, 0.2)
		sprite.scale = Vector2(0.25, 0.25)
	else:
		sprite.texture = PlaceholderTexture2D.new()
		sprite.texture.size = Vector2(18, 18)
		sprite.modulate = Color(1.0, 0.9, 0.0, 1.0)
		#sprite.scale = Vector2(0.25,0.25)

	#sprite.rotation = -PI / 2
	player_icon.add_child(sprite)
	system_view.add_child(player_icon)
	player_icon.z_index = 100
	_update_player_ship_position()

func _create_star_icon(star: Dictionary) -> void:
	var icon := IconDot.new()
	icon.radius = 4.0
	var star_class = star.get("class", "G")
	match star_class:
		"Special":
			icon.color = Color(1.0, 0.6, 1.0)
		"O", "B":
			icon.color = Color(0.7, 0.85, 1.0)
		"A":
			icon.color = Color.WHITE
		"F":
			icon.color = Color(1.0, 1.0, 0.9)
		"G":
			icon.color = Color(1.0, 0.95, 0.5)
		"K":
			icon.color = Color(1.0, 0.7, 0.35)
		"M":
			icon.color = Color(1.0, 0.45, 0.35)
		_:
			icon.color = Color(1, 1, 1)
	
	icon.position = Vector2.ZERO
	icon.mouse_filter = Control.MOUSE_FILTER_STOP
	icon.mouse_entered.connect(_on_object_hover.bind(star))
	icon.mouse_exited.connect(_on_object_unhover)
	system_view.add_child(icon)

func _create_body_icon(body: Dictionary) -> void:
	var body_kind = body.get("kind", "planet")
	var body_id = body.get("id", "")
	var icon: Node
	var color := Color.LIGHT_GRAY
	var radius: float = 6.0
	var orbit: Dictionary = body.get("orbit", {})
	var orbit_radius := float(orbit.get("a_AU", 0.5))
	var angle := float(orbit.get("angle_rad", 0.0))
	
	match body_kind:
		"planet", _:
			icon = IconDot.new()
			var body_type = body.get("type", "rocky")
			if "terran" in body_type or "primordial" in body_type:
				color = Color(0.5, 0.9, 0.5)
			elif "ocean" in body_type:
				color = Color(0.4, 0.7, 1.0)
			elif "ice" in body_type:
				color = Color(0.7, 0.9, 1.0)
			elif "gas" in body_type:
				color = Color(0.9, 0.7, 0.4)
				radius = 9.0
			elif "volcanic" in body_type:
				color = Color(1.0, 0.5, 0.25)
			else:
				color = Color(0.8, 0.8, 0.8)
			var dot := icon as IconDot
			dot.radius = radius
			dot.color = color
		"asteroid_belt":
			icon = IconDiamond.new()
			var dia := icon as IconDiamond
			dia.size_len = 6.0
			dia.color = Color(0.7, 0.7, 0.7)
		"phenomena", "anomaly":
			icon = IconDiamond.new()
			var dia2 := icon as IconDiamond
			dia2.size_len = 7.0
			dia2.color = Color(0.7, 0.5, 1.0)
	
	var offset := Vector2(cos(angle), sin(angle)) * orbit_radius * map_scale
	icon.position = offset
	icon.mouse_filter = Control.MOUSE_FILTER_STOP
	icon.mouse_entered.connect(_on_object_hover.bind(body))
	icon.mouse_exited.connect(_on_object_unhover)
	system_view.add_child(icon)
	body_icons[body_id] = icon

func _create_station_icon(station: Dictionary) -> void:
	var station_id = station.get("id", "")
	var icon := IconSquare.new()
	icon.size_vec = Vector2.ONE * 10.0
	var has_market:bool = station.get("has_market", false) or station.get("market", false)
	if has_market:
		icon.color = Color(0.3, 0.85, 0.9)
	else:
		icon.color = Color(0.8, 0.8, 0.9)
	
	var pos := Vector2.ZERO
	if station.has("position"):
		var p = station.get("position")
		if p is Vector2:
			pos = _world_to_map(p)
		elif p is Array and p.size() >= 2:
			pos = _world_to_map(Vector2(p[0], p[1]))
	elif station.has("orbit"):
		var orbit: Dictionary = station.get("orbit", {})
		var r := float(orbit.get("a_AU", 0.0))
		var a := float(orbit.get("angle_rad", 0.0))
		pos = Vector2(cos(a), sin(a)) * r * map_scale
	else:
		var angle := deg_to_rad(float(hash(station_id) % 360))
		pos = Vector2(cos(angle), sin(angle)) * 3.0 * map_scale
	
	icon.position = pos
	icon.mouse_filter = Control.MOUSE_FILTER_STOP
	icon.mouse_entered.connect(_on_object_hover.bind(station))
	icon.mouse_exited.connect(_on_object_unhover)
	system_view.add_child(icon)
	station_icons[station_id] = icon

func _process(delta: float) -> void:
	if !visible:
		return
	
	player_icon_update_timer += delta
	if player_icon_update_timer >= PLAYER_ICON_UPDATE_INTERVAL:
		player_icon_update_timer = 0.0
		_update_player_ship_position()
	
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
	var map_pos = _world_to_map(player_ship.global_position)
	player_icon.position = map_pos
	player_icon.rotation = player_ship.rotation
	var sprite = player_icon.get_node_or_null("Sprite2D")
	if sprite:
		# Keep sprite pointing right relative to node rotation
		sprite.rotation = -PI / 2

func _world_to_map(world_pos: Vector2) -> Vector2:
	var world_to_map_scale := map_scale / AU_TO_PIXELS
	return world_pos * world_to_map_scale

func _on_object_hover(obj: Dictionary) -> void:
	hovered_object = obj
	hover_timer = 0.0

func _on_object_unhover() -> void:
	hovered_object = {}

func _show_info_panel(obj: Dictionary) -> void:
	info_panel.show()
	if obj.has("class"):
		$InfoPanel/VBoxContainer/NameLabel.text = obj.get("id", "Unknown Star")
		$InfoPanel/VBoxContainer/TypeLabel.text = "Class: %s" % obj.get("class", "Unknown")
		$InfoPanel/VBoxContainer/DetailLabel.text = ""
	elif obj.has("kind"):
		var kind = obj.get("kind", "unknown")
		$InfoPanel/VBoxContainer/NameLabel.text = obj.get("id", "Unknown")
		if kind == "planet":
			$InfoPanel/VBoxContainer/TypeLabel.text = "Planet: %s" % obj.get("type", "Unknown")
			var orbit = obj.get("orbit", {})
			$InfoPanel/VBoxContainer/DetailLabel.text = "Orbit: %.1f AU" % orbit.get("a_AU", 0.0)
		elif kind == "asteroid_belt":
			$InfoPanel/VBoxContainer/TypeLabel.text = "Asteroid Belt"
			var orbit_belt = obj.get("orbit", {})
			$InfoPanel/VBoxContainer/DetailLabel.text = "Orbit: %.1f AU" % orbit_belt.get("a_AU", 0.0)
		else:
			$InfoPanel/VBoxContainer/TypeLabel.text = "Station"
			$InfoPanel/VBoxContainer/DetailLabel.text = ""

func _on_close() -> void:
	hide()
	is_dragging = false
	print("SystemMap: Closed via button")
