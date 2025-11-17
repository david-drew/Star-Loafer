extends Node
class_name AgentBrain

enum State {
	IDLE,
	TRAVEL_ROUTE,
	PATROL,
	GUARD,
	HUNT,
	ESCORT,
	ENGAGE,
	FLEE,
	CALL_FOR_HELP,
	SURRENDER,
	WANDER,
	STUDY_ANOMALY
}

@export var role_id: String = "trader"
@export var faction_id: String = ""
@export var personality_id: String = "default"

@export var think_interval: float = 0.25

@export var sensors: ShipSensors
@export var ship_agent: ShipAgentController

var current_state: int = State.IDLE
var blackboard: Dictionary = {}

var morale: float = 1.0              # 0.0 - 1.0
var morale_resilience: float = 0.8   # how quickly morale recovers

# Cached config
var _role_config: Dictionary = {}
var _personality: Dictionary = {}

var _time_accum: float = 0.0

var _event_bus: Node = null
var _faction_manager: Node = null

func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus")
	_faction_manager = get_node_or_null("/root/FactionManager")

	if sensors == null:
		sensors = get_node_or_null("ShipSensors") as ShipSensors

	if ship_agent == null:
		ship_agent = get_node_or_null("ShipAgentController") as ShipAgentController

	_load_configs()
	_init_state()

	if sensors != null:
		sensors.targets_updated.connect(_on_targets_updated)

	var ai_manager := get_node_or_null("/root/AIManager")
	if ai_manager != null and ai_manager.has_method("register_agent"):
		ai_manager.call("register_agent", self)

func _exit_tree() -> void:
	var ai_manager := get_node_or_null("/root/AIManager")
	if ai_manager != null and ai_manager.has_method("unregister_agent"):
		ai_manager.call("unregister_agent", self)

func _load_configs() -> void:
	if RoleDB != null and RoleDB.has_role(role_id):
		_role_config = RoleDB.get_role(role_id)
	else:
		_role_config = {}

	if PersonalityDB != null and PersonalityDB.has_profile(personality_id):
		_personality = PersonalityDB.get_profile(personality_id)
	else:
		_personality = {}

func _init_state() -> void:
	current_state = State.IDLE
	blackboard.clear()
	# You can set smarter initial state based on role.
	if _role_config.has("allowed_states"):
		var states: Array = _role_config["allowed_states"]
		if "TravelRoute" in states:
			current_state = State.TRAVEL_ROUTE
		elif "Patrol" in states:
			current_state = State.PATROL

func _physics_process(delta: float) -> void:
	_time_accum += delta
	if _time_accum < think_interval:
		return
	_time_accum = 0.0

	_tick_brain(delta)

func _tick_brain(delta: float) -> void:
	# High-level state update, then per-state behavior.
	_update_state_transitions(delta)
	_update_state_behavior(delta)

	_emit_debug()

func _update_state_transitions(delta: float) -> void:
	# Simple example transitions; expand per role as needed.
	var has_threat := _blackboard_has_threat()

	match current_state:
		State.IDLE:
			if has_threat and _wants_to_engage():
				current_state = State.ENGAGE
			elif _has_route_assignment():
				current_state = State.TRAVEL_ROUTE

		State.TRAVEL_ROUTE:
			if has_threat and _wants_to_engage():
				current_state = State.ENGAGE
			elif _should_flee():
				current_state = State.FLEE

		State.HUNT:
			if has_threat:
				current_state = State.ENGAGE

		State.PATROL, State.GUARD, State.ESCORT:
			if has_threat and _wants_to_engage():
				current_state = State.ENGAGE
			elif _should_flee():
				current_state = State.FLEE

		State.ENGAGE:
			if _should_flee():
				current_state = State.FLEE
			elif not has_threat:
				current_state = State.TRAVEL_ROUTE

		State.FLEE:
			# If we reach safety (simplified): if no threat for a while.
			if not has_threat:
				if _has_route_assignment():
					current_state = State.TRAVEL_ROUTE
				else:
					current_state = State.IDLE

		State.WANDER:
			if has_threat:
				if _should_flee():
					current_state = State.FLEE
				elif _wants_to_engage():
					current_state = State.ENGAGE

		State.STUDY_ANOMALY:
			if has_threat:
				current_state = State.FLEE

		State.CALL_FOR_HELP:
			# Usually paired with FLEE or ENGAGE, so we rarely stay here as main state.
			pass

		State.SURRENDER:
			# No transitions for now; external game logic may change state if attacker releases them.
			pass

func _update_state_behavior(delta: float) -> void:
	match current_state:
		State.IDLE:
			_do_idle(delta)
		State.TRAVEL_ROUTE:
			_do_travel_route(delta)
		State.PATROL:
			_do_patrol(delta)
		State.GUARD:
			_do_guard(delta)
		State.HUNT:
			_do_hunt(delta)
		State.ESCORT:
			_do_escort(delta)
		State.ENGAGE:
			_do_engage(delta)
		State.FLEE:
			_do_flee(delta)
		State.CALL_FOR_HELP:
			_do_call_for_help(delta)
		State.SURRENDER:
			_do_surrender(delta)
		State.WANDER:
			_do_wander(delta)
		State.STUDY_ANOMALY:
			_do_study_anomaly(delta)

# ------------ State behavior implementations ------------

func _do_idle(delta: float) -> void:
	if ship_agent != null:
		ship_agent.clear_movement()

func _do_travel_route(delta: float) -> void:
	if ship_agent == null:
		return
	var dest: Vector2 = blackboard.get("route_target_point", Vector2.ZERO)
	if dest == Vector2.ZERO:
		return
	ship_agent.set_move_target(dest)

func _do_patrol(delta: float) -> void:
	# Placeholder: patrol between two points. Replace with your system's patrol waypoints.
	if ship_agent == null:
		return
	var patrol_points: Array = blackboard.get("patrol_points", [])
	if patrol_points.is_empty():
		return

	var index: int = blackboard.get("patrol_index", 0)
	index = clamp(index, 0, patrol_points.size() - 1)
	var target_point: Vector2 = patrol_points[index]
	ship_agent.set_move_target(target_point)

	var owner_node := owner
	if owner_node != null:
		if owner_node.global_position.distance_to(target_point) < 20.0:
			index += 1
			if index >= patrol_points.size():
				index = 0
			blackboard["patrol_index"] = index

func _do_guard(delta: float) -> void:
	# Stay near a guard center; maybe orbit.
	if ship_agent == null:
		return
	var center_node := blackboard.get("guard_target", null)
	if center_node != null and center_node is Node2D:
		ship_agent.set_orbit_target(center_node, 300.0)
	else:
		ship_agent.clear_movement()

func _do_hunt(delta: float) -> void:
	# Simple hunt: pick region center from blackboard or wander region.
	if ship_agent == null:
		return
	var hunt_point: Vector2 = blackboard.get("hunt_point", Vector2.ZERO)
	if hunt_point == Vector2.ZERO:
		return
	ship_agent.set_move_target(hunt_point)

func _do_escort(delta: float) -> void:
	if ship_agent == null:
		return
	var leader := blackboard.get("escort_leader", null)
	if leader == null or not (leader is Node2D):
		ship_agent.clear_movement()
		return

	var offset_radius: float = 250.0
	ship_agent.set_orbit_target(leader, offset_radius)

func _do_engage(delta: float) -> void:
	if ship_agent == null:
		return
	var target := blackboard.get("current_target", null)
	if target == null or not (target is Node2D):
		return

	var preferred_ranges := _role_config.get("preferred_ranges", {"min": 200, "max": 600})
	var min_range: float = float(preferred_ranges.get("min", 200))
	var max_range: float = float(preferred_ranges.get("max", 600))

	var owner_node := owner
	if owner_node == null:
		return

	var distance := owner_node.global_position.distance_to(target.global_position)

	if distance > max_range:
		ship_agent.set_move_target(target.global_position)
	elif distance < min_range:
		ship_agent.set_flee_direction(target.global_position, min_range + 150.0)
	else:
		# Hold range: circle target.
		ship_agent.set_orbit_target(target, clamp(distance, min_range, max_range))

	# Real firing logic should be handled by a weapon controller subscribed to this target.
	blackboard["attack_target"] = target

func _do_flee(delta: float) -> void:
	if ship_agent == null:
		return
	var threat_target := _pick_main_threat()
	var owner_node := owner
	if owner_node == null:
		return

	var flee_distance: float = 1200.0
	if threat_target != null and threat_target is Node2D:
		ship_agent.set_flee_direction(threat_target.global_position, flee_distance)
	else:
		var escape_point: Vector2 = blackboard.get("escape_point", Vector2.ZERO)
		if escape_point != Vector2.ZERO:
			ship_agent.set_move_target(escape_point)
		else:
			# Default: move along +X.
			var pos := owner_node.global_position
			ship_agent.set_move_target(pos + Vector2.RIGHT * flee_distance)

func _do_call_for_help(delta: float) -> void:
	if _event_bus != null and _event_bus.has_signal("ai_call_for_help"):
		var payload := {
			"source": self,
			"faction_id": faction_id,
			"position": owner.global_position if owner != null else Vector2.ZERO
		}
		_event_bus.emit_signal("ai_call_for_help", payload)

func _do_surrender(delta: float) -> void:
	if ship_agent != null:
		ship_agent.clear_movement()
	# Additional: mark this ship as non-hostile, drop cargo, etc.

func _do_wander(delta: float) -> void:
	if ship_agent == null:
		return
	var wander_target: Vector2 = blackboard.get("wander_target", Vector2.ZERO)
	var owner_node := owner
	if owner_node == null:
		return

	if wander_target == Vector2.ZERO or owner_node.global_position.distance_to(wander_target) < 50.0:
		var radius: float = 800.0
		var random_dir := Vector2(randf() * 2.0 - 1.0, randf() * 2.0 - 1.0)
		if random_dir.length_squared() == 0.0:
			random_dir = Vector2.RIGHT
		random_dir = random_dir.normalized()
		wander_target = owner_node.global_position + random_dir * radius
		blackboard["wander_target"] = wander_target

	ship_agent.set_move_target(wander_target)

func _do_study_anomaly(delta: float) -> void:
	if ship_agent == null:
		return
	var anomaly := blackboard.get("anomaly_target", null)
	if anomaly != null and anomaly is Node2D:
		ship_agent.set_orbit_target(anomaly, 500.0)
	else:
		ship_agent.clear_movement()

# ------------ Helpers ------------

func _on_targets_updated() -> void:
	# Called when ShipSensors updates visible_ships.
	# Pick best threat and valuable target here.
	var threats: Array = []
	var all_targets: Array = []

	if sensors == null:
		return

	for info in sensors.visible_ships:
		all_targets.append(info)
		if _is_threat(info):
			threats.append(info)

	blackboard["visible_targets"] = all_targets
	blackboard["threat_targets"] = threats

	var primary := _pick_main_threat()
	if primary != null and primary.has("node"):
		blackboard["current_target"] = primary["node"]

func _is_threat(info: Dictionary) -> bool:
	var target_faction_id:String = info.get("faction_id", "")
	if target_faction_id == "":
		return false

	if _faction_manager != null and _faction_manager.has_method("is_hostile"):
		var hostile:bool = _faction_manager.call("is_hostile", faction_id, target_faction_id)
		if hostile:
			return true

	# Basic rule: non-faction aware threats could be determined by other flags later.
	return false

func _pick_main_threat() -> Dictionary:
	var threats: Array = blackboard.get("threat_targets", [])
	if threats.is_empty():
		return {}

	var owner_node := owner
	if owner_node == null:
		return threats[0]

	var best: Dictionary = {}
	var best_score: float = -INF

	for info in threats:
		if not info.has("node"):
			continue
		var node:Variant = info["node"]
		if not (node is Node2D):
			continue

		var distance:float = owner_node.global_position.distance_to(node.global_position)
		if distance == 0.0:
			distance = 1.0

		var score:float = 1.0 / distance
		# Personality adjustments: more aggressive prefers closer targets.
		var aggression: float = float(_personality.get("aggression", 0.5))
		score *= 0.5 + aggression

		if score > best_score:
			best_score = score
			best = info

	return best

func _blackboard_has_threat() -> bool:
	var threats: Array = blackboard.get("threat_targets", [])
	return not threats.is_empty()

func _wants_to_engage() -> bool:
	var aggression: float = float(_personality.get("aggression", 0.5))
	var bravery: float = float(_personality.get("bravery", 0.5))
	var threshold: float = 0.4
	var desire: float = (aggression + bravery) * 0.5
	return desire > threshold and morale > 0.3

func _should_flee() -> bool:
	var caution: float = float(_personality.get("caution", 0.5))
	var flee_threshold_hull: float = float(_role_config.get("flee_threshold_hull", 0.3))
	var flee_threshold_morale: float = float(_role_config.get("flee_threshold_morale", 0.3))

	var hull_ratio: float = 1.0
	if owner != null and "get_hull_ratio" in owner:
		hull_ratio = owner.get_hull_ratio()

	var hull_low := hull_ratio < flee_threshold_hull
	var morale_low := morale < flee_threshold_morale

	var should_flee := false
	if hull_low:
		should_flee = true
	elif morale_low and caution > 0.5:
		should_flee = true

	return should_flee

func _emit_debug() -> void:
	if _event_bus == null:
		return
	if not _event_bus.has_signal("ai_debug_state"):
		return

	var owner_node := owner
	var pos := Vector2.ZERO
	if owner_node != null and owner_node is Node2D:
		pos = owner_node.global_position

	var payload := {
		"agent": self,
		"role_id": role_id,
		"faction_id": faction_id,
		"state": current_state,
		"position": pos,
		"morale": morale
	}
	_event_bus.emit_signal("ai_debug_state", payload)

# --------- Optional external hooks ---------

func apply_damage(amount: float) -> void:
	# Called by combat system when this ship is damaged.
	var drop := amount * 0.01
	morale = clamp(morale - drop, 0.0, 1.0)

func apply_morale_boost(amount: float) -> void:
	morale = clamp(morale + amount, 0.0, 1.0)

func set_route_target(point: Vector2) -> void:
	blackboard["route_target_point"] = point

func set_patrol_points(points: Array) -> void:
	blackboard["patrol_points"] = points
	blackboard["patrol_index"] = 0

func set_guard_target(target: Node2D) -> void:
	blackboard["guard_target"] = target

func set_hunt_point(point: Vector2) -> void:
	blackboard["hunt_point"] = point

func set_anomaly_target(node: Node2D) -> void:
	blackboard["anomaly_target"] = node
