extends CharacterBody2D

const MAX_SPEED = 300.0
const ACCELERATION = 600.0
const ROTATION_SPEED = 3.0
const DRAG = 0.98  # Multiplier per frame (space friction)

@onready var sprite = $Sprite2D
@onready var camera = $Camera2D

func _ready() -> void:
	# Placeholder sprite for now
	if sprite.texture == null:
		sprite.texture = PlaceholderTexture2D.new()
		sprite.texture.size = Vector2(48, 32)  # Width > Height for right-facing ship

func _physics_process(delta: float) -> void:
	_handle_input(delta)
	_apply_drag()
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
	
	# Clamp to max speed
	if velocity.length() > MAX_SPEED:
		velocity = velocity.normalized() * MAX_SPEED

func _apply_drag() -> void:
	# Space friction (very light)
	velocity *= DRAG

func _update_game_state() -> void:
	GameState.ship_position = global_position
	GameState.ship_velocity = velocity
	EventBus.ship_position_changed.emit(global_position)
