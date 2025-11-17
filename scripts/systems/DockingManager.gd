extends Node
class_name DockingManager

## Manages docking sequences for player and NPCs
## Handles movement override, approach trajectories, and docking completion

# Active docking operations
var active_dockings: Dictionary = {}  # ship_id: docking_data

# Configuration
const APPROACH_SPEED = 200.0  # Pixels per second during autodock
const DOCKING_DISTANCE = 150.0  # Distance at which docking completes (pixels)
const ROTATION_ALIGN_SPEED = 2.0  # Radians per second for alignment

# Signals
signal docking_requested(ship: Node, station: Node)
signal docking_approved(station: Node, ship: Node, bay_id: int)
signal docking_denied(station: Node, ship: Node, reason: String)
signal docking_started(ship: Node, station: Node)
signal docking_complete(ship: Node, station: Node)
signal docking_cancelled(ship: Node, station: Node, reason: String)
signal undocking_started(ship: Node, station: Node)
signal undocking_complete(ship: Node, station: Node)



func _ready() -> void:
	EventBus.connect("docking_approved", _on_docking_approved)
	set_process(true)


func _process(delta: float) -> void:
	_update_active_dockings(delta)


## Request docking at a station
func request_docking(ship: Node, station: Node) -> void:
	if not is_instance_valid(ship) or not is_instance_valid(station):
		push_error("DockingManager: Invalid ship or station for docking request")
		return
	
	# Check if already docking
	var ship_id = _get_ship_id(ship)
	if active_dockings.has(ship_id):
		push_warning("DockingManager: Ship %s already in docking sequence" % ship_id)
		return
	
	# Emit request (station will evaluate and respond via CommSystem)
	docking_requested.emit(ship, station)
	
	# If this is player, station should respond via CommSystem
	# If this is NPC, station can auto-approve/deny
	if not ship.is_in_group("player"):
		_auto_evaluate_npc_docking(ship, station)


## Auto-evaluate NPC docking request (for non-player ships)
func _auto_evaluate_npc_docking(ship: Node, station: Node) -> void:
	# Simple evaluation for NPCs
	var should_approve = true
	var denial_reason = ""
	
	# Check faction relations
	if ship.has("faction_id") and station.has("faction_id"):
		var faction_relations = get_node_or_null("/root/GameRoot/Systems/FactionRelations")
		if faction_relations:
			var rep_tier = faction_relations.get_reputation_tier(ship.faction_id)
			if rep_tier == "Hostile":
				should_approve = false
				denial_reason = "hostile_faction"
	
	# Check station lockdown state
	if station.has("is_locked_down") and station.is_locked_down:
		should_approve = false
		denial_reason = "lockdown"
	
	if should_approve:
		var bay_id = _assign_docking_bay(station)
		approve_docking(ship, station, bay_id)
	else:
		deny_docking(ship, station, denial_reason)


## Approve a docking request and start docking sequence
func approve_docking(ship: Node, station: Node, bay_id: int = 0) -> void:
	var ship_id = _get_ship_id(ship)
	
	# Calculate docking point (for now, just station position)
	var dock_point = station.global_position
	if station.has_method("get_docking_point"):
		dock_point = station.get_docking_point(bay_id)
	
	# Create docking data
	var docking_data = {
		"ship": ship,
		"station": station,
		"bay_id": bay_id,
		"dock_point": dock_point,
		"phase": "approaching",  # approaching, aligning, completing
		"start_time": Time.get_ticks_msec(),
		"original_ship_control": true  # Remember if ship had control
	}
	
	active_dockings[ship_id] = docking_data
	
	# Take control of ship movement
	if ship.is_in_group("player"):
		_override_player_control(ship, true)
	
	docking_approved.emit(ship, station, bay_id)
	docking_started.emit(ship, station)
	
	print("DockingManager: Docking approved for %s at %s (bay %d)" % [ship_id, _get_station_name(station), bay_id])


## Deny a docking request
func deny_docking(ship: Node, station: Node, reason: String) -> void:
	docking_denied.emit(ship, station, reason)
	print("DockingManager: Docking denied for %s at %s (reason: %s)" % [_get_ship_id(ship), _get_station_name(station), reason])


## Cancel an active docking sequence
func cancel_docking(ship: Node, reason: String = "user_cancelled") -> void:
	var ship_id = _get_ship_id(ship)
	
	if not active_dockings.has(ship_id):
		return
	
	var docking_data = active_dockings[ship_id]
	var station = docking_data.station
	
	# Restore ship control
	if ship.is_in_group("player"):
		_override_player_control(ship, false)
	
	active_dockings.erase(ship_id)
	
	docking_cancelled.emit(ship, station, reason)
	print("DockingManager: Docking cancelled for %s (reason: %s)" % [ship_id, reason])


## Complete docking (ship has reached station)
func complete_docking(ship: Node, station: Node) -> void:
	var ship_id = _get_ship_id(ship)
	
	if not active_dockings.has(ship_id):
		push_warning("DockingManager: complete_docking called but ship not in active dockings")
		return
	
	active_dockings.erase(ship_id)
	
	# Set ship state
	if ship.has("is_docked"):
		ship.is_docked = true
		ship.docked_at = station
	
	docking_complete.emit(ship, station)
	
	print("DockingManager: Docking complete for %s at %s" % [ship_id, _get_station_name(station)])
	
	# For player, this should trigger UI to show station services
	if ship.is_in_group("player"):
		EventBus.emit_signal("player_docked_at_station", station)


## Begin undocking sequence
func undock(ship: Node) -> void:
	if not ship.has("is_docked") or not ship.is_docked:
		push_warning("DockingManager: undock called but ship not docked")
		return
	
	var station = ship.get("docked_at")
	if not is_instance_valid(station):
		push_error("DockingManager: Cannot undock - station invalid")
		return
	
	undocking_started.emit(ship, station)
	
	# Clear docked state
	ship.is_docked = false
	ship.docked_at = null
	
	# Move ship away from station (simple offset for now)
	if ship.is_in_group("player"):
		var offset = Vector2(300, 0).rotated(randf() * TAU)
		ship.global_position = station.global_position + offset
		_override_player_control(ship, false)
	
	undocking_complete.emit(ship, station)
	
	print("DockingManager: Undocking complete for %s" % _get_ship_id(ship))
	
	if ship.is_in_group("player"):
		EventBus.emit_signal("player_undocked")


## Update all active docking sequences
func _update_active_dockings(delta: float) -> void:
	var to_complete = []
	
	for ship_id in active_dockings:
		var docking_data = active_dockings[ship_id]
		var ship = docking_data.ship
		var station = docking_data.station
		
		# Validate
		if not is_instance_valid(ship) or not is_instance_valid(station):
			to_complete.append(ship_id)
			continue
		
		# Update docking phase
		match docking_data.phase:
			"approaching":
				_update_approach_phase(ship, docking_data, delta)
			"aligning":
				_update_alignment_phase(ship, docking_data, delta)
			"completing":
				to_complete.append(ship_id)
	
	# Complete dockings
	for ship_id in to_complete:
		if active_dockings.has(ship_id):
			var docking_data = active_dockings[ship_id]
			complete_docking(docking_data.ship, docking_data.station)


## Update approach phase - move ship toward dock point
func _update_approach_phase(ship: Node, docking_data: Dictionary, delta: float) -> void:
	var dock_point = docking_data.dock_point
	var distance = ship.global_position.distance_to(dock_point)
	
	if distance < DOCKING_DISTANCE:
		# Move to alignment phase
		docking_data.phase = "aligning"
		return
	
	# Move toward dock point
	var direction = (dock_point - ship.global_position).normalized()
	
	if ship.is_in_group("player"):
		# Override player velocity
		ship.velocity = direction * APPROACH_SPEED
	else:
		# For NPCs, move directly
		ship.global_position += direction * APPROACH_SPEED * delta


## Update alignment phase - rotate to match station
func _update_alignment_phase(ship: Node, docking_data: Dictionary, delta: float) -> void:
	var station = docking_data.station
	
	# Simple alignment - face the station
	var target_angle = ship.global_position.angle_to_point(station.global_position)
	var angle_diff = angle_difference(ship.rotation, target_angle)
	
	if abs(angle_diff) < 0.1:
		# Aligned, move to completing
		docking_data.phase = "completing"
		return
	
	# Rotate toward target
	var rotation_step = sign(angle_diff) * ROTATION_ALIGN_SPEED * delta
	if abs(rotation_step) > abs(angle_diff):
		ship.rotation = target_angle
	else:
		ship.rotation += rotation_step


## Override or restore player control
func _override_player_control(player: Node, override: bool) -> void:
	if not player.has("docking_autopilot"):
		player.set_meta("docking_autopilot", override)
	else:
		player.docking_autopilot = override
	
	if override:
		print("DockingManager: Player control overridden for docking")
	else:
		print("DockingManager: Player control restored")


## Assign a docking bay (for now, just return 0)
func _assign_docking_bay(station: Node) -> int:
	# Future: Track bay occupancy
	return 0


## Handle docking approval signal from EventBus/CommSystem
func _on_docking_approved(station: Node, ship: Node, bay_id: int) -> void:
	approve_docking(ship, station, bay_id)


## Utility: Get ship ID
func _get_ship_id(ship: Node) -> String:
	if ship.has("entity_id"):
		return ship.entity_id
	return ship.name


## Utility: Get station name
func _get_station_name(station: Node) -> String:
	if station.has("station_name"):
		return station.station_name
	return station.name


## Check if a ship is currently docking
func is_docking(ship: Node) -> bool:
	return active_dockings.has(_get_ship_id(ship))


## Get docking progress (0.0 to 1.0)
func get_docking_progress(ship: Node) -> float:
	var ship_id = _get_ship_id(ship)
	if not active_dockings.has(ship_id):
		return 0.0
	
	var docking_data = active_dockings[ship_id]
	var dock_point = docking_data.dock_point
	
	# Calculate based on distance
	var start_distance = 1000.0  # Assume starting distance
	var current_distance = ship.global_position.distance_to(dock_point)
	
	return clamp(1.0 - (current_distance / start_distance), 0.0, 1.0)
