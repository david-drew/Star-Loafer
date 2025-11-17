extends Node2D
class_name ShipAgentController

@export var ship_controller: Node = null
@export var desired_speed: float = 200.0

var _current_move_target: Vector2 = Vector2.ZERO
var _has_move_target: bool = false

var _current_orbit_target: Node2D = null
var _orbit_radius: float = 400.0

var _flee_target: Vector2 = Vector2.ZERO
var _has_flee_target: bool = false


func set_move_target(target: Vector2) -> void:
	_current_move_target = target
	_has_move_target = true
	_current_orbit_target = null
	_has_flee_target = false


func set_orbit_target(target: Node2D, radius: float) -> void:
	_current_orbit_target = target
	_orbit_radius = radius
	_has_move_target = false
	_has_flee_target = false


func clear_movement() -> void:
	_has_move_target = false
	_current_orbit_target = null
	_has_flee_target = false
	_apply_stop()


func set_flee_direction(away_from: Vector2, distance: float) -> void:
	var owner_node: Node2D = owner as Node2D
	if owner_node == null:
		return

	var dir: Vector2 = (owner_node.global_position - away_from)
	if dir.length_squared() == 0.0:
		dir = Vector2.RIGHT
	else:
		dir = dir.normalized()

	_flee_target = owner_node.global_position + dir * distance
	_has_flee_target = true
	_has_move_target = false
	_current_orbit_target = null


func _physics_process(delta: float) -> void:
	if ship_controller == null:
		return

	if _has_flee_target:
		_move_towards(_flee_target, delta)
		return

	if _current_orbit_target != null:
		_update_orbit(delta)
		return

	if _has_move_target:
		_move_towards(_current_move_target, delta)
		return

	_apply_stop()


func _move_towards(target: Vector2, delta: float) -> void:
	var owner_node: Node2D = owner as Node2D
	if owner_node == null:
		return

	var to_target: Vector2 = target - owner_node.global_position
	var distance: float = to_target.length()
	if distance < 10.0:
		_has_move_target = false
		_apply_stop()
		return

	var desired_dir: Vector2 = to_target.normalized()
	_apply_steering(desired_dir, desired_speed)


func _update_orbit(delta: float) -> void:
	var owner_node: Node2D = owner as Node2D
	if owner_node == null:
		return

	if _current_orbit_target == null:
		_apply_stop()
		return

	var center: Vector2 = _current_orbit_target.global_position
	var to_center: Vector2 = center - owner_node.global_position
	var distance: float = to_center.length()

	if distance == 0.0:
		_apply_stop()
		return

	var radial_dir: Vector2 = to_center.normalized()
	var tangent_dir: Vector2 = Vector2(-radial_dir.y, radial_dir.x)

	var radial_error: float = distance - _orbit_radius
	var move_dir: Vector2

	if abs(radial_error) > 25.0:
		var correction_dir: Vector2 = -radial_dir
		if radial_error > 0.0:
			correction_dir = radial_dir
		move_dir = (tangent_dir + correction_dir * 0.25).normalized()
	else:
		move_dir = tangent_dir

	_apply_steering(move_dir, desired_speed)


func _apply_steering(direction: Vector2, speed: float) -> void:
	if ship_controller == null:
		return

	if ship_controller.has_method("set_desired_heading_and_speed"):
		ship_controller.call("set_desired_heading_and_speed", direction, speed)
	elif ship_controller.has_method("set_thrust_vector"):
		ship_controller.call("set_thrust_vector", direction * speed)


func _apply_stop() -> void:
	if ship_controller == null:
		return

	if ship_controller.has_method("set_desired_heading_and_speed"):
		ship_controller.call("set_desired_heading_and_speed", Vector2.ZERO, 0.0)
	elif ship_controller.has_method("set_thrust_vector"):
		ship_controller.call("set_thrust_vector", Vector2.ZERO)
