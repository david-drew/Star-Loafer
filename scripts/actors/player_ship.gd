extends CharacterBody2D

const MAX_SPEED 		= 2400.0  	# Pixels per second: 1800 default
const ACCELERATION 		= 150.0  	# Pixels per second squared: 300 default
const ROTATION_SPEED 	= 2.0  		# Radians per second: 3.0 default
const DRAG_COEFFICIENT 	= 1.5  		# Units of speed removed per second (drag)

# Component System Integration (optional)
@onready var component_system: ShipComponentSystem = $ShipComponentSystem if has_node("ShipComponentSystem") else null
var use_component_stats: bool = false  # Set to true to override constants with component stats
var ship_type_id: String = "scout_firefly"  # Default ship type

# Docking state
enum DockingState {
	NORMAL,
	DOCKING,
	DOCKED
}

var docking_state: DockingState = DockingState.NORMAL
var docking_autopilot: bool = false  # When true, movement is controlled by DockingManager
var is_docked: bool = false
var docked_at: Node = null  # Reference to station when docked

# Performance: only emit position signal when moved significantly
const POSITION_CHANGE_THRESHOLD = 10.0  # pixels
var last_emitted_position: Vector2 = Vector2.ZERO

@onready var sprite = $Sprite2D
@onready var camera = $Camera2D

func _ready() -> void:
	# Initialize component system if present
	if component_system != null:
		component_system.init_from_ship_type(ship_type_id)
		use_component_stats = true
		print("PlayerShip: Using component system with ship type '%s'" % ship_type_id)
	else:
		use_component_stats = false
		print("PlayerShip: Using hardcoded stats (no component system)")
	
	# Register as player ship for UI and other systems
	EventBus.player_ship_registered.emit(self)
	
	# Connect to ship systems UI requests
	EventBus.ship_component_toggle_requested.connect(_on_ship_component_toggle_requested)
	EventBus.ship_component_install_requested.connect(_on_ship_component_install_requested)
	EventBus.ship_component_remove_requested.connect(_on_ship_component_remove_requested)
	
	# Broadcast initial component state for UI
	refresh_component_ui_state()

	# Placeholder sprite for now
	if sprite.texture == null:
		sprite.texture = PlaceholderTexture2D.new()
		sprite.texture.size = Vector2(48, 32)  # Width > Height for right-facing ship
		
	# Store base scale for LOD system
	set_meta("base_scale", sprite.scale)
	_emit_ship_stats()  # Give the components UI a kick to activate the LeftColumn

func _physics_process(delta: float) -> void:
	_handle_input(delta)
	move_and_slide()
	_update_game_state()

func _handle_input(delta: float) -> void:
	# Skip input if docking autopilot is active
	if docking_autopilot:
		return
	
	# Skip input if docked
	if is_docked:
		return
	
	# Get movement stats once per frame
	var move_stats = _get_movement_stats()
	
	# Rotation
	var rotation_input = 0.0
	if Input.is_action_pressed("move_left"):
		rotation_input -= 1.0
	if Input.is_action_pressed("move_right"):
		rotation_input += 1.0
	
	rotation += rotation_input * move_stats["turn_rate"] * delta
	
	# Thrust (use transform.x because sprite points right by default)
	var thrust_input = 0.0
	if Input.is_action_pressed("move_up"):
		thrust_input += 1.0
	if Input.is_action_pressed("move_down"):
		thrust_input -= 0.5  # Reverse thrust weaker
	
	if thrust_input != 0.0:
		# transform.x points in the direction the ship is facing (right = 0°)
		var thrust_direction = transform.x
		velocity += thrust_direction * thrust_input * move_stats["acceleration"] * delta
	
	# Apply drag (proper physics: removes velocity over time)
	_apply_drag(delta)
	
	# Clamp to max speed
	if velocity.length() > move_stats["max_speed"]:
		velocity = velocity.normalized() * move_stats["max_speed"]

func _get_movement_stats() -> Dictionary:
	"""Get movement stats from component system or fallback to constants"""
	if use_component_stats and component_system != null:
		var stats = component_system.get_current_stats()
		return {
			"max_speed": stats.get("speed_rating", 1.0) * 800.0,  # Convert rating to pixels/sec
			"acceleration": stats.get("acceleration", 0.1) * 1500.0,  # Scale to feel good
			"turn_rate": stats.get("turn_rate", 2.0),
			"mass": stats.get("mass_total", 40.0)
		}
	else:
		# Fallback to hardcoded constants
		return {
			"max_speed": MAX_SPEED,
			"acceleration": ACCELERATION,
			"turn_rate": ROTATION_SPEED,
			"mass": 40.0  # Default mass
		}

func _apply_drag(delta: float) -> void:
	# Proper drag: remove velocity proportional to current velocity
	if velocity.length() > 0:
		var drag_force = velocity.normalized() * DRAG_COEFFICIENT * delta * 60.0
		if drag_force.length() < velocity.length():
			velocity -= drag_force
		else:
			velocity = Vector2.ZERO  # Stop completely if drag would reverse direction

func _update_game_state() -> void:
	# Always update GameState (needed for streaming)
	GameState.ship_position = global_position
	GameState.ship_velocity = velocity
	
	# Only emit signal when position changed significantly (reduces event spam)
	if last_emitted_position.distance_to(global_position) >= POSITION_CHANGE_THRESHOLD:
		last_emitted_position = global_position
		EventBus.ship_position_changed.emit(global_position)


## Comm System Integration

func request_docking_at_station(station: Node) -> void:
	"""Player requests docking at a station via comm system"""
	if is_docked:
		print("Player: Already docked")
		return
	
	var docking_manager = get_node_or_null("/root/GameRoot/Systems/DockingManager")
	if not docking_manager:
		push_error("Player: DockingManager not found")
		return
	
	# Request docking (DockingManager will coordinate with station)
	docking_manager.request_docking(self, station)
	print("Player: Requested docking at %s" % station.name)


func initiate_hail(target: Node) -> void:
	"""Player initiates a comm hail to another entity"""
	var comm_system = get_node_or_null("/root/GameRoot/Systems/CommSystem")
	if not comm_system:
		push_error("Player: CommSystem not found")
		return
	
	var conversation_id = comm_system.initiate_hail(self, target, "player_hail")
	
	if conversation_id >= 0:
		print("Player: Hailed %s (conversation ID: %d)" % [target.name, conversation_id])
	else:
		print("Player: Could not hail %s (busy or cooldown)" % target.name)


func can_accept_hail() -> bool:
	"""Check if player can currently accept incoming hails"""
	# Player can generally accept hails unless docked or in specific states
	if is_docked:
		return true  # Can talk while docked
	
	return true  # Player can always be hailed for now


func cancel_docking() -> void:
	"""Cancel an active docking sequence"""
	var docking_manager = get_node_or_null("/root/GameRoot/Systems/DockingManager")
	if docking_manager:
		docking_manager.cancel_docking(self, "player_cancelled")


func undock_from_station() -> void:
	"""Leave the currently docked station"""
	if not is_docked:
		print("Player: Not currently docked")
		return
	
	var docking_manager = get_node_or_null("/root/GameRoot/Systems/DockingManager")
	if docking_manager:
		docking_manager.undock(self)


# === Component System API ===

func get_ship_stats() -> Dictionary:
	"""Get current ship stats (for UI display)"""
	if use_component_stats and component_system != null:
		return component_system.get_current_stats()
	else:
		# Return basic stats from constants
		return {
			"hull_points": 100,
			"shield_strength": 0,
			"power_margin": 0,
			"max_speed": MAX_SPEED,
			"acceleration": ACCELERATION,
			"turn_rate": ROTATION_SPEED
		}


func swap_ship_type(new_ship_type_id: String) -> void:
	"""Change to a different ship type (for buying/selling ships)"""
	if component_system == null:
		push_warning("PlayerShip: Cannot swap ship - no component system")
		return
	
	ship_type_id = new_ship_type_id
	component_system.init_from_ship_type(ship_type_id)
	print("PlayerShip: Swapped to ship type '%s'" % ship_type_id)


func install_component(component_id: String) -> bool:
	"""Install a component on the ship"""
	if component_system == null:
		push_warning("PlayerShip: Cannot install component - no component system")
		return false
	
	var ok: bool = component_system.install(component_id)
	if ok:
		refresh_component_ui_state()
	return ok


func remove_component(component_id: String) -> bool:
	"""Remove a component from the ship"""
	if component_system == null:
		push_warning("PlayerShip: Cannot remove component - no component system")
		return false

	var ok: bool = component_system.remove(component_id)
	if ok:
		refresh_component_ui_state()
	return ok


func get_installed_components() -> Array:
	"""Get list of installed components"""
	if component_system != null:
		return component_system.get_installed_component_ids()
	return []

# Optional: reference to a cargo/inventory node (if you have one)
@onready var cargo: Node = get_node_or_null("Cargo")  # Adjust path if needed


# === Ship Systems UI bridge helpers ===

func _emit_ship_stats() -> void:
	var stats: Dictionary = get_ship_stats()
	EventBus.ship_stats_updated.emit(self, stats)


func _emit_ship_loadout() -> void:
	if component_system == null:
		EventBus.ship_loadout_updated.emit(self, [])
		return
	
	var installed: Array = component_system.get_installed_components()
	var loadout: Array = []
	var index: int = 0
	for entry in installed:
		var id_str: String = str(entry.get("id", ""))
		if id_str == "":
			continue
		
		var state_str: String = str(entry.get("state", "operational"))
		var enabled: bool = state_str == "operational"
		
		var thin_entry: Dictionary = {}
		thin_entry["component_id"] = id_str
		thin_entry["instance_id"] = "%s_%d" % [id_str, index]
		thin_entry["enabled"] = enabled
		
		loadout.append(thin_entry)
		index += 1
	
	EventBus.ship_loadout_updated.emit(self, loadout)


func _emit_component_candidates() -> void:
	# NOTE: This is a stub. Integrate with your cargo/inventory system here.
	# Expected shape per candidate: { "component_id": String, "count": int }
	var candidates: Array = []
	
	# Example skeleton if your cargo node exposes something like get_component_counts():
	# if cargo != null and cargo.has_method("get_component_counts"):
	#     var counts: Dictionary = cargo.get_component_counts()
	#     for comp_id in counts.keys():
	#         var count_value: int = int(counts[comp_id])
	#         if count_value > 0:
	#             var entry: Dictionary = {}
	#             entry["component_id"] = str(comp_id)
	#             entry["count"] = count_value
	#             candidates.append(entry)
	
	EventBus.ship_component_candidates_updated.emit(self, candidates)


func refresh_component_ui_state() -> void:
	# Convenience function to refresh all component-related UI at once
	_emit_ship_stats()
	_emit_ship_loadout()
	_emit_component_candidates()

func _on_ship_component_toggle_requested(ship: Node, component_id: String, enabled: bool) -> void:
	if ship != self:
		return
	
	if component_system == null:
		EventBus.ship_component_action_failed.emit(self, "toggle", "no_component_system", {"component_id": component_id})
		return
	
	var ok: bool = component_system.toggle(component_id, enabled)
	if ok:
		refresh_component_ui_state()
	else:
		EventBus.ship_component_action_failed.emit(self, "toggle", "component_not_found", {"component_id": component_id})


func _on_ship_component_install_requested(ship: Node, component_id: String) -> void:
	if ship != self:
		return
	
	if component_system == null:
		EventBus.ship_component_action_failed.emit(self, "install", "no_component_system", {"component_id": component_id})
		return
	
	# TODO: enforce cargo/inventory rules and docking rules here.
	# For now, we just attempt to install and assume rules are handled elsewhere.
	var ok: bool = component_system.install(component_id)
	if ok:
		# In a full implementation, you would also remove one item from cargo here.
		refresh_component_ui_state()
	else:
		EventBus.ship_component_action_failed.emit(self, "install", "install_failed", {"component_id": component_id})


func _on_ship_component_remove_requested(ship: Node, component_id: String) -> void:
	if ship != self:
		return
	
	if component_system == null:
		EventBus.ship_component_action_failed.emit(self, "remove", "no_component_system", {"component_id": component_id})
		return
	
	var ok: bool = component_system.remove(component_id)
	if ok:
		# In a full implementation, you would typically add one item back to cargo here.
		refresh_component_ui_state()
	else:
		EventBus.ship_component_action_failed.emit(self, "remove", "remove_failed", {"component_id": component_id})

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_ship_systems"):
		print("Show Components UI")
		_toggle_ship_screen()


func _toggle_ship_screen() -> void:
	var ship: Node = null
	# If you know the PlayerShip, reference it directly; example:
	ship = get_node_or_null("/root/GameRoot/SystemExploration/PlayerShip")  # adjust path
	
	if ship == null:
		ship = $"."
		if ship == null:
			print("\tError Can's get PlayerShip node")
			return
	
	# Simple: just flip based on UI panel visibility.
	var ui_root: Node = get_node_or_null("/root/GameRoot/UI")
	if ui_root == null:
		print("\tError: ui_root null, can't open Components UI Panel")
		return
	var panel: Control = ui_root.get_node_or_null("ShipSystemsPanel")
	if panel == null:
		print("\tError: ShipSystemsPanel null, can't open Components UI Panel")
		return
	
	var should_open: bool = not panel.visible
	EventBus.ship_screen_toggled.emit(ship, should_open)
