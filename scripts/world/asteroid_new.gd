extends Node2D
class_name Asteroid

@export var is_mineable: bool = true
@export var has_collision: bool = true

@export var max_health: float = 100.0
@export var ore_type: StringName = &"common_ore"
@export var ore_yield_min: int = 10
@export var ore_yield_max: int = 30

@export var reuse_on_deplete: bool = true
# If true: tries to hand control back to parent (e.g. AsteroidBelt) instead of destroying itself.

var health: float
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_area: Area2D = $CollisionArea


func _ready() -> void:
	_rng.randomize()
	reset_asteroid()


func reset_asteroid() -> void:
	# Called by belt or spawner to "refresh" this asteroid when reused.
	health = max_health
	visible = true

	if has_collision:
		collision_area.monitoring = true
		collision_area.monitorable = true
	else:
		collision_area.monitoring = false
		collision_area.monitorable = false


func apply_mining_damage(amount: float, source: Node = null) -> void:
	if not is_mineable:
		return

	if amount <= 0.0:
		return

	health -= amount
	if health <= 0.0:
		_on_depleted(source)


func _on_depleted(source: Node) -> void:
	var ore_amount: int = _roll_ore_yield()
	_emit_mined_event(ore_amount, source)

	# Hand control to parent (e.g. AsteroidBelt) for pooling,
	# or fallback to queue_free if no handler exists.
	var parent := get_parent()
	if reuse_on_deplete and parent != null and parent.has_method("on_asteroid_depleted"):
		visible = false
		collision_area.monitoring = false
		collision_area.monitorable = false
		parent.call("on_asteroid_depleted", self, ore_amount, ore_type, source)
	else:
		queue_free()


func _roll_ore_yield() -> int:
	if ore_yield_max < ore_yield_min:
		return ore_yield_min
	if ore_yield_min <= 0 and ore_yield_max <= 0:
		return 0
	var amount: int = _rng.randi_range(ore_yield_min, ore_yield_max)
	return amount


func _emit_mined_event(ore_amount: int, source: Node) -> void:
	# Optional integration with a global EventBus autoload.
	# Adjust signal name / payload to your existing bus.
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal("asteroid_mined"):
		bus.emit_signal("asteroid_mined", self, ore_type, ore_amount, source)
	
