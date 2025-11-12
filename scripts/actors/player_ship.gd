extends CharacterBody2D

const MAX_SPEED 		= 1800.0  	# Pixels per second
const ACCELERATION 		= 300.0  	# Pixels per second squared
const ROTATION_SPEED 	= 3.0  		# Radians per second
const DRAG_COEFFICIENT 	= 1.5  		# Units of speed removed per second (drag)

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
	# Placeholder sprite for now
	if sprite.texture == null:
		sprite.texture = PlaceholderTexture2D.new()
		sprite.texture.size = Vector2(48, 32)  # Width > Height for right-facing ship
		
	# Store base scale for LOD system
	set_meta("base_scale", sprite.scale)

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
	
	# Rotation
	var rotation_input = 0.0
	if Input.is_action_pressed("move_left"):
		rotation_input -= 1.0
	if Input.is_action_pressed("move_right"):
		rotation_input += 1.0
	
	rotation += rotation_input * ROTATION_SPEED * delta
	
	# Thrust (use transform.x because sprite points right by default)
	var thrust_input = 0.0
	if Input.is_action_pressed("move_up"):
		thrust_input += 1.0
	if Input.is_action_pressed("move_down"):
		thrust_input -= 0.5  # Reverse thrust weaker
	
	if thrust_input != 0.0:
		# transform.x points in the direction the ship is facing (right = 0°)
		var thrust_direction = transform.x
		velocity += thrust_direction * thrust_input * ACCELERATION * delta
	
	# Apply drag (proper physics: removes velocity over time)
	_apply_drag(delta)
	
	# Clamp to max speed
	if velocity.length() > MAX_SPEED:
		velocity = velocity.normalized() * MAX_SPEED

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
