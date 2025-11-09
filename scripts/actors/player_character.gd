extends CharacterBody2D

const WALK_SPEED = 150.0
const RUN_SPEED  = 250.0

func _physics_process(delta: float) -> void:
	var input_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	var speed = RUN_SPEED if Input.is_action_pressed("run") else WALK_SPEED
	velocity = input_vector * speed
	
	move_and_slide()
