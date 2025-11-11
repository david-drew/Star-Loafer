# asteroid.gd
# Simple asteroid object that exists in space sectors
# Phase 0: Static collision object
# Phase 1+: Will support mining, health, etc.

extends StaticBody2D
class_name Asteroid_2

# Phase 1 properties (not used in Phase 0)
var ore_type: String = ""
var ore_amount: int = 0
var is_depleted: bool = false

func _ready() -> void:
	_setup_collision()

func _setup_collision() -> void:
	# Set collision layer and mask
	collision_layer = 2  # Layer 2: asteroids
	collision_mask = 1 | 16 | 32  # player_ship | npcs | projectiles
	
	# Ensure we have a collision shape
	if not has_node("CollisionShape2D"):
		push_error("Asteroid missing CollisionShape2D!")

# Phase 1: Mining interaction
func mine(amount: int) -> Dictionary:
	if is_depleted:
		return {"success": false, "message": "Asteroid depleted"}
	
	var mined = min(amount, ore_amount)
	ore_amount -= mined
	
	if ore_amount <= 0:
		is_depleted = true
	
	return {
		"success": true,
		"ore_type": ore_type,
		"amount": mined,
		"depleted": is_depleted
	}

# Phase 1: Take damage from weapons
func take_damage(damage: float) -> void:
	# TODO: Implement asteroid destruction/fragmentation
	pass
