extends CharacterBody2D

const MAX_SPEED 		= 1200.0  	# Pixels per second
const ACCELERATION 		= 500.0  	# Pixels per second squared
const ROTATION_SPEED 	= 3.0  		# Radians per second
const DRAG_COEFFICIENT 	= 1.5  		# Units of speed removed per second (drag)

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

func _physics_process(delta: float) -> void:
	_handle_input(delta)
	move_and_slide()
	_update_game_state()

func _handle_input(delta: float) -> void:
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
