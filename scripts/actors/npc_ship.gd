# npc_ship.gd
# Attached to npc_ship.tscn root node
# NPC ships that patrol systems, trade, and interact with player
# Follows same pattern as planet.gd and star.gd (scene instancing with initialize())

extends CharacterBody2D
class_name NPCShip

# Ship data
var ship_id: String = ""
var ship_type: String = "generic_freighter"
var faction_id: String = ""
var ship_name: String = ""

# AI state
enum AIState {
	IDLE,
	PATROL,
	TRADE,
	FLEE,
	ATTACK
}

var ai_state: AIState = AIState.PATROL
var patrol_waypoints: Array = []
var current_waypoint_index: int = 0

# Movement
var max_speed: float = 150.0
var acceleration: float = 100.0
var turn_speed: float = 2.0

# Combat stats (for future)
var hull_max: float = 100.0
var hull_current: float = 100.0
var shields_max: float = 50.0
var shields_current: float = 50.0

# References
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var detection_area: Area2D = $DetectionArea

# Avoidance
var avoidance_radius: float = 200.0
var nearby_obstacles: Array = []

func _ready() -> void:
	# Set collision layers
	# Layer 8 = NPC ships
	# Collides with: Layer 1 (player), Layer 2 (asteroids), Layer 8 (other NPCs)
	collision_layer = 1 << 7  # Layer 8
	collision_mask = (1 << 0) | (1 << 1) | (1 << 7)  # Layers 1, 2, 8
	
	# Set up detection area for obstacle avoidance
	if detection_area:
		detection_area.body_entered.connect(_on_body_entered_detection)
		detection_area.body_exited.connect(_on_body_exited_detection)

func initialize(ship_data: Dictionary) -> void:
	"""
	Initialize NPC ship with data
	Called after instancing, following same pattern as planet/star initialization
	
	ship_data format:
	{
		"id": "npc:00001",
		"type": "patrol_corvette",
		"faction_id": "imperial_meridian",
		"name": "INS Vigilant",
		"spawn_position": Vector2(x, y),
		"patrol_route": [Vector2(...), Vector2(...), ...],
		"ai_behavior": "patrol"  # or "trade", "aggressive", "defensive"
	}
	"""
	ship_id = ship_data.get("id", "npc:unknown")
	ship_type = ship_data.get("type", "generic_freighter")
	faction_id = ship_data.get("faction_id", "")
	ship_name = ship_data.get("name", "Unknown Ship")
	
	# Set initial position
	var spawn_pos = ship_data.get("spawn_position", Vector2.ZERO)
	global_position = spawn_pos
	
	# Set up patrol route
	patrol_waypoints = ship_data.get("patrol_route", [])
	if patrol_waypoints.is_empty():
		# Generate simple circular patrol if none provided
		_generate_default_patrol(spawn_pos)
	
	# Configure ship stats based on type
	_configure_ship_type(ship_type)
	
	# Set up AI behavior
	var behavior = ship_data.get("ai_behavior", "patrol")
	_set_ai_behavior(behavior)
	
	# Load sprite
	_load_ship_sprite()
	
	print("NPCShip: Initialized %s (%s) from %s" % [ship_name, ship_type, faction_id])

func _configure_ship_type(type: String) -> void:
	"""Configure ship stats based on ship type"""
	match type:
		"patrol_corvette", "customs_frigate":
			max_speed = 180.0
			acceleration = 120.0
			hull_max = 150.0
			shields_max = 80.0
		"military_destroyer", "assault_frigate":
			max_speed = 140.0
			acceleration = 90.0
			hull_max = 250.0
			shields_max = 120.0
		"corporate_freighter", "hauler", "generic_freighter":
			max_speed = 100.0
			acceleration = 60.0
			hull_max = 120.0
			shields_max = 40.0
		"raider", "pirate_corvette", "merc_fighter":
			max_speed = 200.0
			acceleration = 150.0
			hull_max = 100.0
			shields_max = 50.0
		"survey_ship", "scout_corvette":
			max_speed = 160.0
			acceleration = 110.0
			hull_max = 90.0
			shields_max = 60.0
		_:
			# Generic defaults
			max_speed = 150.0
			acceleration = 100.0
			hull_max = 100.0
			shields_max = 50.0
	
	hull_current = hull_max
	shields_current = shields_max

func _set_ai_behavior(behavior: String) -> void:
	"""Set initial AI behavior"""
	match behavior:
		"patrol":
			ai_state = AIState.PATROL
		"trade":
			ai_state = AIState.TRADE
		"aggressive":
			ai_state = AIState.ATTACK
		"defensive":
			ai_state = AIState.IDLE
		_:
			ai_state = AIState.PATROL

func _load_ship_sprite() -> void:
	"""Load ship sprite based on type and faction"""
	if sprite == null:
		return
	
	# Try to load faction-specific sprite
	var sprite_path = "res://assets/ships/%s/%s.png" % [faction_id, ship_type]
	
	if !ResourceLoader.exists(sprite_path):
		# Fallback to generic ship sprite
		sprite_path = "res://assets/ships/generic/%s.png" % ship_type
		print("\tError: Failed sprite path: ", sprite_path)
		sprite_path = "res://assets/images/actors/ships/junker_corsair.png"
	
	if ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
	else:
		# Placeholder
		var placeholder = PlaceholderTexture2D.new()
		placeholder.size = Vector2(64, 64)
		sprite.texture = placeholder
		
		# Color by faction type
		sprite.modulate = _get_faction_color()

func _get_faction_color() -> Color:
	"""Get color tint for faction (placeholder visual)"""
	# This would ideally come from FactionManager
	match faction_id:
		"imperial_meridian":
			return Color(0.8, 0.8, 1.0)  # Light blue
		"spindle_cartel":
			return Color(1.0, 0.9, 0.5)  # Gold
		"free_hab_league":
			return Color(0.9, 0.5, 0.5)  # Red
		"black_exchange", "ashen_crown":
			return Color(0.4, 0.4, 0.4)  # Dark gray
		"covenant_quiet_suns":
			return Color(0.9, 0.9, 0.9)  # White
		"artilect_custodians":
			return Color(0.5, 1.0, 0.8)  # Cyan
		"iron_wakes":
			return Color(0.8, 0.3, 0.3)  # Dark red
		"nomad_clans":
			return Color(0.7, 0.6, 0.9)  # Purple
		_:
			return Color(0.7, 0.7, 0.7)  # Gray

func _generate_default_patrol(center: Vector2) -> void:
	"""Generate a simple circular patrol route around spawn point"""
	var radius = 2000.0
	var num_waypoints = 4
	
	for i in range(num_waypoints):
		var angle = (TAU / num_waypoints) * i
		var waypoint = center + Vector2(cos(angle), sin(angle)) * radius
		patrol_waypoints.append(waypoint)

func _physics_process(delta: float) -> void:
	if patrol_waypoints.is_empty():
		return
	
	match ai_state:
		AIState.PATROL:
			_update_patrol(delta)
		AIState.IDLE:
			_update_idle(delta)
		AIState.FLEE:
			_update_flee(delta)
		AIState.ATTACK:
			_update_attack(delta)
	
	# Apply avoidance
	_apply_collision_avoidance(delta)
	
	# Move
	move_and_slide()

func _update_patrol(delta: float) -> void:
	"""Patrol between waypoints"""
	if patrol_waypoints.is_empty():
		return
	
	var target = patrol_waypoints[current_waypoint_index]
	var direction = (target - global_position).normalized()
	
	# Steer toward target
	var desired_velocity = direction * max_speed
	velocity = velocity.lerp(desired_velocity, acceleration * delta / max_speed)
	
	# Rotate to face movement direction
	if velocity.length() > 10.0:
		var target_rotation = velocity.angle()
		rotation = lerp_angle(rotation, target_rotation, turn_speed * delta)
	
	# Check if reached waypoint
	if global_position.distance_to(target) < 100.0:
		current_waypoint_index = (current_waypoint_index + 1) % patrol_waypoints.size()

func _update_idle(delta: float) -> void:
	"""Idle state - slow down"""
	velocity = velocity.lerp(Vector2.ZERO, delta * 2.0)

func _update_flee(delta: float) -> void:
	"""Flee from threats (future implementation)"""
	# TODO: Flee from player/hostile ships
	pass

func _update_attack(delta: float) -> void:
	"""Attack behavior (future implementation)"""
	# TODO: Attack player if hostile
	pass

func _apply_collision_avoidance(delta: float) -> void:
	"""Simple collision avoidance - steer away from nearby obstacles"""
	if nearby_obstacles.is_empty():
		return
	
	var avoidance_force = Vector2.ZERO
	
	for obstacle in nearby_obstacles:
		if !is_instance_valid(obstacle):
			continue
		
		var to_obstacle = obstacle.global_position - global_position
		var distance = to_obstacle.length()
		
		if distance < avoidance_radius and distance > 0:
			# Push away from obstacle (inverse square falloff)
			var push_strength = (avoidance_radius - distance) / avoidance_radius
			avoidance_force -= to_obstacle.normalized() * push_strength * 300.0
	
	# Apply avoidance force
	if avoidance_force.length() > 0:
		velocity += avoidance_force * delta

func _on_body_entered_detection(body: Node2D) -> void:
	"""Track nearby bodies for collision avoidance"""
	if body != self and body not in nearby_obstacles:
		nearby_obstacles.append(body)

func _on_body_exited_detection(body: Node2D) -> void:
	"""Stop tracking bodies that left detection range"""
	nearby_obstacles.erase(body)

# === PUBLIC API ===

func get_ship_name() -> String:
	return ship_name

func get_faction_id() -> String:
	return faction_id

func get_ship_type() -> String:
	return ship_type

func is_hostile_to_player() -> bool:
	"""Check if this NPC should be hostile to player"""
	# TODO: Check player faction reputation
	# For now, only pirates/criminals are hostile
	return faction_id in ["black_exchange", "ashen_crown"]

func take_damage(amount: float) -> void:
	"""Apply damage to ship (future combat system)"""
	# First deplete shields
	if shields_current > 0:
		shields_current -= amount
		if shields_current < 0:
			var overflow = abs(shields_current)
			shields_current = 0
			hull_current -= overflow
	else:
		hull_current -= amount
	
	# Check if destroyed
	if hull_current <= 0:
		_on_destroyed()

func _on_destroyed() -> void:
	"""Handle ship destruction"""
	print("NPCShip: %s destroyed!" % ship_name)
	# TODO: Spawn wreckage, drop loot, emit signal
	queue_free()
