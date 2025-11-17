extends Node2D
class_name ShipSensors

signal targets_updated

@export var detection_radius: float = 2000.0
@export var update_interval: float = 0.25

var visible_ships: Array = []  # Array of dictionaries: { "node": Node2D, "distance": float, "faction_id": String, "is_player": bool }

var _time_accum: float = 0.0
var _faction_manager: Node = null

func _ready() -> void:
	_faction_manager = get_node_or_null("/root/FactionManager")

func _physics_process(delta: float) -> void:
	_time_accum += delta
	if _time_accum < update_interval:
		return

	_time_accum = 0.0
	_update_targets()

func _update_targets() -> void:
	var owner_node := owner
	if owner_node == null:
		return

	var ships := get_tree().get_nodes_in_group("ships")
	var new_list: Array = []

	for ship in ships:
		if ship == owner_node:
			continue

		if not ship is Node2D:
			continue

		var pos: Vector2 = ship.global_position
		var distance:float = owner_node.global_position.distance_to(pos)
		if distance > detection_radius:
			continue

		var info: Dictionary = {}
		info["node"] = ship
		info["distance"] = distance

		# Try to read faction and player flags; adapt these property names to your project.
		var faction_id := ""
		if "faction_id" in ship:
			faction_id = ship.faction_id
		info["faction_id"] = faction_id

		var is_player := false
		if "is_player_controlled" in ship:
			is_player = ship.is_player_controlled
		info["is_player"] = is_player

		new_list.append(info)

	visible_ships = new_list
	emit_signal("targets_updated")
