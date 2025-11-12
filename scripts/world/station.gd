# station.gd
# Attached to station.tscn root node
# Space stations with dynamic appearance based on type
# Follows same pattern as planet.gd and npc_ship.gd

extends StaticBody2D
class_name Station

# Station data
var station_id: String = ""
var station_type: String = "refuel_depot"
var station_name: String = ""
var faction_id: String = ""
var variant: int = 0

# Services and properties
var services: Array = []
var docking_enabled: bool = true
var broadcast_enabled: bool = false
var broadcast_message: String = ""

# Comm system properties
var comm_profile_id: String = "default_station"
var personality: Dictionary = {}
var is_locked_down: bool = false

# Visual
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var interaction_area: Area2D = $InteractionArea

# Size scaling by type
const STATION_SCALES = {
	"habitat": 2.0,
	"shipyard": 2.5,
	"naval_station": 2.2,
	"trading_station": 1.8,
	"warp_gate": 3.0,
	"corporate_hq": 1.5,
	"ore_refinery": 1.3,
	"mining_outpost": 0.8,
	"refuel_depot": 1.0,
	"research_lab": 1.2,
	"small_market": 0.9,
	"observation_post": 0.7,
	"comm_relay": 1.0
}

func _ready() -> void:
	# Set collision layers
	# Layer 4 = Stations (example - adjust to your needs)
	collision_layer = 1 << 3  # Layer 4
	collision_mask = 1 << 0  # Collides with player (layer 1)
	
	# Set up interaction area
	if interaction_area:
		interaction_area.body_entered.connect(_on_player_entered_range)
		interaction_area.body_exited.connect(_on_player_exited_range)

func initialize(station_data: Dictionary) -> void:
	"""
	Initialize station with data
	
	station_data format:
	{
		"id": "station:gate_001",
		"type": "warp_gate",
		"name": "Nexus Gate Alpha",
		"faction_id": "imperial_meridian",
		"variant": 0,
		"position": Vector2(x, y),
		"services": ["dock", "refuel", "market"],
		"broadcast": "Welcome to Nexus Station"
	}
	"""
	station_id = station_data.get("id", "station:unknown")
	station_type = station_data.get("type", "refuel_depot")
	station_name = station_data.get("name", "Unknown Station")
	faction_id = station_data.get("faction_id", "")
	variant = station_data.get("variant", 0)
	
	# Set position
	global_position = station_data.get("position", Vector2.ZERO)
	
	# Set services
	services = station_data.get("services", [])
	
	# Set broadcast message
	var broadcast = station_data.get("broadcast", "")
	if broadcast != "":
		broadcast_enabled = true
		broadcast_message = broadcast
	
	# Configure visuals
	_load_station_sprite()
	_apply_station_scale()
	_apply_faction_tint()
	
	print("Station: Initialized %s (%s) at %s" % [station_name, station_type, global_position])

func _load_station_sprite() -> void:
	"""Load station sprite based on type and variant"""
	if sprite == null:
		return
	
	# Try to load sprite from asset pattern
	var sprite_path = "res://assets/images/actors/stations/%s_%02d.png" % [station_type, variant]
	
	if !ResourceLoader.exists(sprite_path):
		# Try without variant
		print("\tStation sprite not found: %s" % sprite_path)
		sprite_path = "res://assets/images/actors/stations/%s.png" % station_type
	
	if ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
	else:
		# Placeholder
		var placeholder = PlaceholderTexture2D.new()
		placeholder.size = Vector2(128, 128)
		sprite.texture = placeholder
		
		# Color by station type
		sprite.modulate = _get_station_type_color()

func _get_station_type_color() -> Color:
	"""Get placeholder color for station type"""
	match station_type:
		"warp_gate":
			return Color(0.5, 0.8, 1.0)  # Light blue
		"habitat", "trading_station":
			return Color(0.9, 0.9, 0.9)  # White
		"naval_station":
			return Color(0.8, 0.3, 0.3)  # Red
		"shipyard":
			return Color(0.7, 0.7, 0.8)  # Gray-blue
		"ore_refinery", "mining_outpost":
			return Color(0.8, 0.6, 0.3)  # Orange
		"research_lab":
			return Color(0.6, 1.0, 0.6)  # Green
		"corporate_hq":
			return Color(1.0, 0.9, 0.5)  # Gold
		"refuel_depot", "small_market":
			return Color(0.8, 0.8, 0.8)  # Light gray
		"observation_post", "comm_relay":
			return Color(0.6, 0.8, 1.0)  # Cyan
		_:
			return Color(0.7, 0.7, 0.7)  # Default gray

func _apply_station_scale() -> void:
	"""Apply scale based on station type"""
	if sprite == null:
		return
	
	var scale_factor = STATION_SCALES.get(station_type, 1.0)
	sprite.scale = Vector2.ONE * scale_factor
	
	# Also scale collision shape
	if collision_shape and collision_shape.shape:
		var base_radius = 64.0  # Base collision radius
		if collision_shape.shape is CircleShape2D:
			collision_shape.shape.radius = base_radius * scale_factor

func _apply_faction_tint() -> void:
	"""Apply subtle faction color tint"""
	if sprite == null or faction_id == "":
		return
	
	var tint = _get_faction_tint()
	# Blend 70% original color, 30% faction tint
	sprite.modulate = sprite.modulate.lerp(tint, 0.3)

func _get_faction_tint() -> Color:
	"""Get faction color tint"""
	match faction_id:
		"imperial_meridian":
			return Color(0.9, 0.9, 1.0)  # Light blue
		"spindle_cartel":
			return Color(1.0, 0.95, 0.7)  # Gold
		"free_hab_league":
			return Color(1.0, 0.8, 0.8)  # Light red
		"nomad_clans":
			return Color(0.9, 0.8, 1.0)  # Purple
		"covenant_quiet_suns":
			return Color(1.0, 1.0, 1.0)  # White
		"black_exchange", "ashen_crown":
			return Color(0.5, 0.5, 0.5)  # Dark
		"artilect_custodians":
			return Color(0.7, 1.0, 0.9)  # Cyan
		"iron_wakes":
			return Color(0.9, 0.5, 0.5)  # Red
		_:
			return Color(1.0, 1.0, 1.0)  # White

func _on_player_entered_range(body: Node2D) -> void:
	"""Player entered interaction range"""
	if body.name == "PlayerShip":
		# TODO: Signal that player can interact (add to EventBus later)
		print("Station: Player entered range of %s" % station_name)
		
		# Auto-broadcast if enabled
		if broadcast_enabled and broadcast_message != "":
			_broadcast_message()

func _on_player_exited_range(body: Node2D) -> void:
	"""Player left interaction range"""
	if body.name == "PlayerShip":
		# TODO: Signal player left range (add to EventBus later)
		print("Station: Player left range of %s" % station_name)

func _broadcast_message() -> void:
	"""Broadcast message to player"""
	# TODO: Add EventBus.station_broadcast signal later
	print("Station Broadcast [%s]: %s" % [station_name, broadcast_message])

# === PUBLIC API ===

func get_station_name() -> String:
	return station_name

func get_station_type() -> String:
	return station_type

func get_faction_id() -> String:
	return faction_id

func get_services() -> Array:
	return services

func has_service(service_name: String) -> bool:
	return service_name in services

func can_dock() -> bool:
	return docking_enabled and has_service("dock")

func dock_ship() -> void:
	"""Initiate docking sequence"""
	if !can_dock():
		print("Station: Docking not available at %s" % station_name)
		return
	
	print("Station: Docking at %s" % station_name)
	# TODO: Add EventBus.station_docking_started signal later
	# TODO: Actual docking logic


## Comm System Integration

func can_accept_hail() -> bool:
	"""Check if station can currently accept a comm hail"""
	if is_locked_down:
		return false
	
	# Stations are generally very responsive
	return true


func handle_docking_request(requesting_ship: Node) -> void:
	"""Handle a docking request from a ship via comm system"""
	var comm_system = get_node_or_null("/root/GameRoot/Systems/CommSystem")
	if not comm_system:
		push_error("Station: CommSystem not found")
		return
	
	# Build context for response
	var context = comm_system.build_comm_context(self, requesting_ship)
	
	# Check if we can approve docking
	var can_approve = can_dock()
	var denial_reason = ""
	
	if not can_approve:
		denial_reason = "no_docking_services"
	
	# Check faction relations
	if requesting_ship.has("faction_id") and requesting_ship.faction_id:
		var faction_relations = get_node_or_null("/root/GameRoot/Systems/FactionRelations")
		if faction_relations:
			var rep_tier = faction_relations.get_reputation_tier(faction_id)
			if rep_tier == "Hostile":
				can_approve = false
				denial_reason = "hostile_faction"
	
	if is_locked_down:
		can_approve = false
		denial_reason = "station_lockdown"
	
	# Generate response
	var response_type = "docking_approved" if can_approve else "docking_denied"
	var response = comm_system.generate_response(self, context, response_type)
	
	# Emit appropriate signal
	if can_approve:
		var bay_id = 0  # TODO: Implement bay assignment
		EventBus.emit_signal("docking_approved", self, requesting_ship, bay_id)
	
	# TODO: Send response to UI system for display
	print("Station %s: Docking request from %s - %s" % [station_name, requesting_ship.name, "APPROVED" if can_approve else "DENIED (" + denial_reason + ")"])


func get_docking_point(bay_id: int = 0) -> Vector2:
	"""Get the position for a specific docking bay"""
	# For now, return position near station
	# TODO: Implement proper bay positions based on station size/type
	var offset_angle = (bay_id * PI / 4.0)  # Spread bays around station
	var offset = Vector2(150, 0).rotated(offset_angle)
	return global_position + offset


func initiate_broadcast(message: String, priority: String = "normal") -> void:
	"""Send a broadcast message from this station"""
	if not broadcast_enabled:
		return
	
	var comm_system = get_node_or_null("/root/GameRoot/Systems/CommSystem")
	if not comm_system:
		return
	
	# Determine tech level based on station type
	var tech_level = 2  # Default
	if station_type in ["research_station", "military_base"]:
		tech_level = 3
	elif station_type in ["habitat", "mining_outpost"]:
		tech_level = 1
	
	comm_system.broadcast_message(self, message, "station_announcement", priority, tech_level)
