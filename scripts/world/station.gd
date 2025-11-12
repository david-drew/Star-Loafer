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
var variant: int = 1

# Services and properties (JSON-driven)
var services: Array = []
var docking_enabled: bool = true
var docking_ports: int = 0
var broadcast_enabled: bool = false
var broadcast_message: String = ""

# Extra metadata from JSON (optional)
var size_px: float = 256.0
var color_hints: Array = []
var tech_level: String = "standard"
var market_tier: int = 0
var repair_tier: int = 0
var shipyard_tier: int = 0
var security_level: int = 0
var faction_bias: String = "neutral"

# Comm system properties
var comm_profile_id: String = "default_station"
var personality: Dictionary = {}
var is_locked_down: bool = false

# Visual
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var interaction_area: Area2D = $InteractionArea

func _ready() -> void:
	# Set collision layers (Layer 4 = Stations example)
	collision_layer = 1 << 3
	collision_mask = 1 << 0
	
	if interaction_area:
		interaction_area.body_entered.connect(_on_player_entered_range)
		interaction_area.body_exited.connect(_on_player_exited_range)

func initialize(station_data: Dictionary) -> void:
	"""
	Initialize station with data (now JSON-driven)
	"""
	station_id = station_data.get("id", "station:unknown")
	station_type = station_data.get("type", "refuel_depot")
	station_name = station_data.get("name", "Unknown Station")
	faction_id = station_data.get("faction_id", "")
	variant = station_data.get("variant", 1)
	
	# Position
	global_position = station_data.get("position", Vector2.ZERO)
	
	# Services and flags
	services = station_data.get("services", [])
	docking_enabled = bool(station_data.get("can_dock", true))
	docking_ports = int(station_data.get("docking_ports", 0))
	
	# Optional meta from JSON
	size_px = float(station_data.get("size_px", size_px))
	color_hints = station_data.get("color_hints", [])
	tech_level = station_data.get("tech_level", tech_level)
	market_tier = int(station_data.get("market_tier", market_tier))
	repair_tier = int(station_data.get("repair_tier", repair_tier))
	shipyard_tier = int(station_data.get("shipyard_tier", shipyard_tier))
	security_level = int(station_data.get("security_level", security_level))
	faction_bias = station_data.get("faction_bias", faction_bias)
	
	# Broadcast
	var broadcast:String = station_data.get("broadcast", "")
	if broadcast != "":
		broadcast_enabled = true
		broadcast_message = broadcast
	
	# Configure visuals
	_load_station_sprite(station_data)
	_apply_station_scale()
	_apply_faction_tint()
	
	print("Station: Initialized %s (%s) at %s" % [station_name, station_type, global_position])

func _load_station_sprite(station_data: Dictionary) -> void:
	if sprite == null:
		return
	
	# Prefer explicit sprite path built by generator from asset_pattern
	var sprite_path: String = station_data.get("sprite_path", "")
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
	else:
		print("\tSTATION No Sprite 1: %s" %sprite_path)
		# Fallback to legacy pattern (kept for safety)
		if variant == 0: variant = 1
		var fallback := "res://assets/images/actors/stations/%s_%02d.png" % [station_type, variant]
		print("\tSTATION No Sprite 2: %s" %fallback)
		if !ResourceLoader.exists(fallback):
			fallback = "res://assets/images/actors/stations/%s.png" % station_type
		if ResourceLoader.exists(fallback):
			sprite.texture = load(fallback)
		else:
			# Placeholder + hint color
			var placeholder := PlaceholderTexture2D.new()
			placeholder.size = Vector2(128, 128)
			sprite.texture = placeholder
			# Use first color hint if provided, else neutral
			if color_hints.size() > 0:
				sprite.modulate = _color_from_hint(color_hints[0])
			else:
				sprite.modulate = Color(0.7, 0.7, 0.7)

func _apply_station_scale() -> void:
	if sprite == null or sprite.texture == null:
		return
	
	# Scale sprite to match target size in pixels (diameter)
	var tex_w := float(sprite.texture.get_width())
	if tex_w <= 0.0:
		tex_w = 128.0 # avoid div-by-zero if placeholder
	
	var scale_factor := size_px / tex_w
	var final_scale := Vector2.ONE * scale_factor
	sprite.scale = final_scale
	
	# Store as base_scale for LOD system in SystemExploration
	set_meta("base_scale", final_scale)
	
	# Scale collision (assume CircleShape2D radius ~ half of size_px)
	if collision_shape and collision_shape.shape and collision_shape.shape is CircleShape2D:
		collision_shape.shape.radius = max(size_px * 0.5, 32.0)

func _apply_faction_tint() -> void:
	if sprite == null or faction_id == "":
		return
	var tint := _get_faction_tint()
	# Blend 70% original, 30% faction
	sprite.modulate = sprite.modulate.lerp(tint, 0.3)

func _get_faction_tint() -> Color:
	match faction_id:
		"imperial_meridian":
			return Color(0.9, 0.9, 1.0)
		"spindle_cartel":
			return Color(1.0, 0.95, 0.7)
		"free_hab_league":
			return Color(1.0, 0.8, 0.8)
		"nomad_clans":
			return Color(0.9, 0.8, 1.0)
		"covenant_quiet_suns":
			return Color(1.0, 1.0, 1.0)
		"black_exchange", "ashen_crown":
			return Color(0.5, 0.5, 0.5)
		"artilect_custodians":
			return Color(0.7, 1.0, 0.9)
		"iron_wakes":
			return Color(0.9, 0.5, 0.5)
		_:
			return Color(1.0, 1.0, 1.0)

func _color_from_hint(h: String) -> Color:
	# Map a few known hints to colors; fall back to neutral
	match h:
		"blue_white": return Color(0.8, 0.9, 1.0)
		"warm_white": return Color(1.0, 0.95, 0.85)
		"rust_orange": return Color(0.85, 0.55, 0.25)
		"industrial_gray": return Color(0.6, 0.65, 0.7)
		"signal_yellow": return Color(1.0, 0.9, 0.3)
		"corporate_blue": return Color(0.45, 0.6, 1.0)
		"steel_blue": return Color(0.55, 0.7, 0.9)
		"navy_blue": return Color(0.2, 0.3, 0.6)
		"warning_red": return Color(0.9, 0.3, 0.3)
		"teal": return Color(0.3, 0.8, 0.75)
		"neon_signs": return Color(0.8, 0.9, 1.0)
		"cyan": return Color(0.6, 1.0, 1.0)
		"pale_cyan": return Color(0.8, 1.0, 1.0)
		"violet": return Color(0.7, 0.5, 1.0)
		"gold": return Color(1.0, 0.85, 0.4)
		"white": return Color(1,1,1)
		"white_glow": return Color(0.95, 0.98, 1.0)
		"magenta_core": return Color(1.0, 0.3, 0.8)
		"amber_fuel": return Color(1.0, 0.75, 0.3)
		"gunmetal": return Color(0.3, 0.35, 0.4)
		"ancient_gold": return Color(1.0, 0.8, 0.4)
		"void_violet": return Color(0.5, 0.3, 0.9)
		"black": return Color(0.1, 0.1, 0.12)
		"neon_magenta": return Color(1.0, 0.3, 0.7)
		"red_cross": return Color(1.0, 0.2, 0.2)
		"arc_welder_blue": return Color(0.5, 0.7, 1.0)
		"scaffold_gray": return Color(0.6, 0.6, 0.65)
		_:
			return Color(0.7, 0.7, 0.7)

# --- Interaction & comms (unchanged) ---

func _on_player_entered_range(body: Node2D) -> void:
	if body.name == "PlayerShip":
		print("Station: Player entered range of %s" % station_name)
		if broadcast_enabled and broadcast_message != "":
			_broadcast_message()

func _on_player_exited_range(body: Node2D) -> void:
	if body.name == "PlayerShip":
		print("Station: Player left range of %s" % station_name)

func _broadcast_message() -> void:
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
	# JSON-driven docking flag; keep simple and decouple from services
	return docking_enabled

func dock_ship() -> void:
	if !can_dock():
		print("Station: Docking not available at %s" % station_name)
		return
	print("Station: Docking at %s" % station_name)
	# TODO: EventBus + docking logic

## Comm System Integration

func can_accept_hail() -> bool:
	if is_locked_down:
		return false
	return true

func handle_docking_request(requesting_ship: Node) -> void:
	var comm_system = get_node_or_null("/root/GameRoot/Systems/CommSystem")
	if not comm_system:
		push_error("Station: CommSystem not found")
		return
	
	var context = comm_system.build_comm_context(self, requesting_ship)
	var can_approve := can_dock()
	var denial_reason := ""
	if not can_approve:
		denial_reason = "no_docking_services"
	
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
	
	var response_type: String
	if can_approve:
		response_type = "docking_approved"
	else:
		response_type = "docking_denied"
	
	var response = comm_system.generate_response(self, context, response_type)
	
	if can_approve:
		var bay_id := 0
		EventBus.emit_signal("docking_approved", self, requesting_ship, bay_id)
		
	var docking_status: String
	if can_approve:
		docking_status = "APPROVED"
	else:
		docking_status = "DENIED (" + denial_reason + ")"

	print("Station %s: Docking request from %s - %s" % [station_name, requesting_ship.name, docking_status])


func get_docking_point(bay_id: int = 0) -> Vector2:
	var offset_angle := (bay_id * PI / 4.0)
	var offset := Vector2(150, 0).rotated(offset_angle)
	return global_position + offset

func initiate_broadcast(message: String, priority: String = "normal") -> void:
	if not broadcast_enabled:
		return
	var comm_system = get_node_or_null("/root/GameRoot/Systems/CommSystem")
	if not comm_system:
		return
	var tl := 2
	if station_type in ["research_station", "military_base"]:
		tl = 3
	elif station_type in ["habitat", "mining_outpost"]:
		tl = 1
	comm_system.broadcast_message(self, message, "station_announcement", priority, tl)
