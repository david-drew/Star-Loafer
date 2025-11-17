extends Node
class_name NPCSpawner

# Service for spawning NPC ships in star systems
# Manages NPC lifecycle and coordinates with FactionManager

# Scene references
var npc_ship_scene = preload("res://scenes/actors/npc_ship.tscn")

# Service references
var faction_manager: FactionManager = null

# Container for spawned NPCs
var npc_container: Node2D = null

# Tracking
var spawned_npcs: Array = []
var npc_name_counter: Dictionary = {}  # Track ship name numbers per faction

func _ready() -> void:
	print("NPCSpawner: Ready")
	
	# Try to find FactionManager automatically if not set
	if faction_manager == null:
		_auto_find_faction_manager()

func _auto_find_faction_manager() -> void:
	"""Automatically find FactionManager in the scene tree"""
	# Try to find in parent Systems node
	if get_parent() != null:
		var fm = get_parent().get_node_or_null("FactionManager")
		if fm != null:
			faction_manager = fm
			print("NPCSpawner: Auto-found FactionManager")
			return
	
	# Try autoload
	if Engine.has_singleton("FactionManager"):
		faction_manager = Engine.get_singleton("FactionManager")
		print("NPCSpawner: Using FactionManager autoload")
		return
	
	# Try via get_node
	var fm = get_node_or_null("/root/GameRoot/Systems/FactionManager")
	if fm != null:
		faction_manager = fm
		print("NPCSpawner: Found FactionManager at /root/GameRoot/Systems/FactionManager")
		return
	
	push_warning("NPCSpawner: Could not auto-find FactionManager. Set it manually.")

func set_faction_manager(fm: FactionManager) -> void:
	"""Manually set the FactionManager reference"""
	faction_manager = fm
	print("NPCSpawner: FactionManager set manually")

func set_npc_container(container: Node2D) -> void:
	"""Set the parent node for spawned NPCs"""
	npc_container = container

func spawn_npcs_for_system(system_data: Dictionary, system_seed: int) -> void:
	"""
	Spawn NPC ships appropriate for this system
	
	system_data should include:
	- faction_id
	- pop_level
	- tech_level
	- faction_influence
	"""
	if npc_container == null:
		push_error("NPCSpawner: No NPC container set!")
		return
	
	if faction_manager == null:
		push_error("NPCSpawner: No FactionManager set!")
		return
	
	# Clear existing NPCs
	clear_all_npcs()
	
	var faction_id = system_data.get("faction_id", "")
	if faction_id == ""  or faction_id == "independent":
		faction_id = "independent"  # Treat empty as independent
		print("NPCSpawner: Spawning independent ships in neutral system")
	
	var pop_level = system_data.get("pop_level", 5)
	var tech_level = system_data.get("tech_level", 5)
	var faction_influence = system_data.get("faction_influence", 100)
	
	# Determine how many NPCs to spawn
	var npc_count = faction_manager.get_npc_ship_count(faction_id, pop_level, tech_level)
	
	# Reduce count if faction has low influence (contested system)
	if faction_influence < 50:
		npc_count = max(1, npc_count / 2)
	
	print("NPCSpawner: Spawning %d NPC ships for %s" % [npc_count, faction_manager.get_faction_name(faction_id)])
	
	# Create RNG for consistent spawn positions
	var rng = RandomNumberGenerator.new()
	rng.seed = system_seed ^ hash(faction_id)
	
	# Get ship types for this faction
	var ship_types = faction_manager.get_npc_ship_types(faction_id)
	
	# Spawn NPCs
	for i in range(npc_count):
		_spawn_single_npc(faction_id, ship_types, rng, i)

func _spawn_single_npc(faction_id: String, ship_types: Array, rng: RandomNumberGenerator, index: int) -> void:
	"""Spawn a single NPC ship"""

	# Select random ship type
	var ship_type = ship_types[rng.randi_range(0, ship_types.size() - 1)]

	# Generate spawn position (random orbit around center)
	var spawn_position = _generate_spawn_position(rng)

	# Generate patrol route
	var patrol_route = _generate_patrol_route(spawn_position, rng)

	# Generate ship name
	var ship_name = _generate_ship_name(faction_id, ship_type, index)

	# Determine AI behavior
	var ai_behavior = _determine_ai_behavior(faction_id, ship_type, rng)

	# Resolve sprite info via ContentDb + hull_visuals
	var sprite_type:String = ship_type
	var sprite_variant := 1
	var sprite_path := ""

	var content_db := _get_content_db()
	if content_db != null and content_db.has_method("get_ship_sprite_info"):
		var info: Dictionary = content_db.get_ship_sprite_info(ship_type, -1)
		sprite_type = str(info.get("sprite_type", ship_type))
		sprite_variant = int(info.get("variant", 1))
		sprite_path = str(info.get("path", ""))
	else:
		# Fallback: simple pattern with default variant
		sprite_variant = rng.randi_range(1, 3)

	if sprite_variant < 1:
		sprite_variant = 1

	if sprite_path == "":
		var vars = {
			"type": sprite_type,
			"variant": "%02d" % sprite_variant,
		}
		sprite_path = "res://assets/images/actors/ships/{type}_{variant}.png".format(vars)

	# Create ship data
	var ship_data = {
		"id": "npc:%s:%d" % [faction_id, index],
		"type": ship_type,
		"faction_id": faction_id,
		"name": ship_name,
		"spawn_position": spawn_position,
		"patrol_route": patrol_route,
		"ai_behavior": ai_behavior,
		"sprite_type": sprite_type,
		"sprite_variant": sprite_variant,
		"sprite_path": sprite_path,
	}

	# Instance and initialize ship
	var npc_ship = npc_ship_scene.instantiate()
	npc_container.add_child(npc_ship)
	npc_ship.initialize(ship_data)

	spawned_npcs.append(npc_ship)


func _generate_spawn_position(rng: RandomNumberGenerator) -> Vector2:
	"""Generate a random spawn position in the system"""
	# Spawn in a ring around the center (avoid spawning on top of star/player)
	var min_radius = 3000.0  # ~0.75 AU
	var max_radius = 12000.0  # ~3 AU
	
	var angle = rng.randf() * TAU
	var radius = rng.randf_range(min_radius, max_radius)
	
	return Vector2(cos(angle), sin(angle)) * radius

func _generate_patrol_route(spawn_pos: Vector2, rng: RandomNumberGenerator) -> Array:
	"""Generate a patrol route for the NPC"""
	var waypoints = []
	var num_waypoints = rng.randi_range(3, 6)
	var patrol_radius = rng.randf_range(1500.0, 3000.0)
	
	# Create waypoints in a rough circle around spawn point
	for i in range(num_waypoints):
		var angle = (TAU / num_waypoints) * i + rng.randf_range(-0.3, 0.3)
		var distance = patrol_radius + rng.randf_range(-500.0, 500.0)
		var waypoint = spawn_pos + Vector2(cos(angle), sin(angle)) * distance
		waypoints.append(waypoint)
	
	return waypoints

func _generate_ship_name(faction_id: String, ship_type: String, index: int) -> String:
	"""Generate a ship name based on faction naming conventions"""
	
	# Initialize counter for this faction if needed
	if faction_id not in npc_name_counter:
		npc_name_counter[faction_id] = 1
	else:
		npc_name_counter[faction_id] += 1
	
	var number = npc_name_counter[faction_id]
	
	# Faction-specific naming conventions
	match faction_id:
		"independent", "":
			var names = ["Freelancer", "Wanderer", "Pathfinder", "Seeker", "Nomad", "Drifter"]
			return "IV %s-%d" % [names[randi() % names.size()], number]  # IV = Independent Vessel
		
		"imperial_meridian":
			return "INS %s-%d" % [_get_imperial_ship_name(), number]
		"spindle_cartel":
			return "SC %s" % _get_corporate_ship_name()
		"free_hab_league":
			return "FHL %s" % _get_workers_ship_name()
		"nomad_clans":
			return "%s" % _get_nomad_ship_name()
		"covenant_quiet_suns":
			return "Covenant %s" % _get_religious_ship_name()
		"black_exchange", "ashen_crown":
			return "Black %s" % _get_pirate_ship_name()
		"artilect_custodians":
			return "AC-Unit-%03d" % number
		"iron_wakes":
			return "IW-%s" % _get_merc_ship_name()
		"drift_cartographers":
			return "Survey-%03d" % number
		"radiant_communion":
			return "Radiant %s" % _get_zealot_ship_name()
		_:
			return "Ship-%03d" % number

func _get_imperial_ship_name() -> String:
	var names = ["Vigilant", "Guardian", "Sentinel", "Justicar", "Exemplar", "Ardent", "Stalwart"]
	return names[randi() % names.size()]

func _get_corporate_ship_name() -> String:
	var names = ["Profit", "Dividend", "Merger", "Asset", "Leverage", "Equity", "Capital"]
	return names[randi() % names.size()]

func _get_workers_ship_name() -> String:
	var names = ["Solidarity", "Unity", "Striker", "Union", "Collective", "Labor", "Commons"]
	return names[randi() % names.size()]

func _get_nomad_ship_name() -> String:
	var names = ["Wanderer's Rest", "Sky Song", "Drift Wind", "Star Path", "Void Walker", "Far Seeker"]
	return names[randi() % names.size()]

func _get_religious_ship_name() -> String:
	var names = ["Mercy", "Sanctuary", "Vigil", "Quietude", "Grace", "Benediction", "Repose"]
	return names[randi() % names.size()]

func _get_pirate_ship_name() -> String:
	var names = ["Reaver", "Raider", "Corsair", "Scourge", "Cutlass", "Marauder", "Vengeance"]
	return names[randi() % names.size()]

func _get_merc_ship_name() -> String:
	var names = ["Hammer", "Blade", "Iron", "Steel", "Wardog", "Talon", "Fang"]
	return names[randi() % names.size()]

func _get_zealot_ship_name() -> String:
	var names = ["Flame", "Pyre", "Blaze", "Crucible", "Inferno", "Ember", "Kindle"]
	return names[randi() % names.size()]

func _determine_ai_behavior(faction_id: String, ship_type: String, rng: RandomNumberGenerator) -> String:
	"""Determine AI behavior based on faction and ship type"""
	
	var faction_type = faction_manager.get_faction_type(faction_id)
	
	# Pirates and criminals are aggressive
	if faction_type in ["smuggler_network", "pirate_confederacy"]:
		return "aggressive" if rng.randf() < 0.7 else "patrol"
	
	# Military ships patrol
	if ship_type.contains("military") or ship_type.contains("patrol"):
		return "patrol"
	
	# Freighters and haulers trade
	if ship_type.contains("freighter") or ship_type.contains("hauler"):
		return "trade"
	
	# Default to patrol
	return "patrol"

func clear_all_npcs() -> void:
	"""Remove all spawned NPCs"""
	for npc in spawned_npcs:
		if is_instance_valid(npc):
			npc.queue_free()
	
	spawned_npcs.clear()
	print("NPCSpawner: Cleared all NPCs")

func get_npcs_in_range(position: Vector2, range_radius: float) -> Array:
	"""Get all NPCs within range of a position"""
	var npcs_in_range = []
	
	for npc in spawned_npcs:
		if !is_instance_valid(npc):
			continue
		
		if npc.global_position.distance_to(position) <= range_radius:
			npcs_in_range.append(npc)
	
	return npcs_in_range

func get_hostile_npcs_in_range(position: Vector2, range_radius: float) -> Array:
	"""Get hostile NPCs within range"""
	var hostile_npcs = []
	
	for npc in get_npcs_in_range(position, range_radius):
		if npc.is_hostile_to_player():
			hostile_npcs.append(npc)
	
	return hostile_npcs

func get_npc_count() -> int:
	"""Get number of active NPCs"""
	# Filter out invalid references
	spawned_npcs = spawned_npcs.filter(func(npc): return is_instance_valid(npc))
	return spawned_npcs.size()

func get_npcs_by_faction(faction_id: String) -> Array:
	"""Get all NPCs belonging to a specific faction"""
	var faction_npcs = []
	
	for npc in spawned_npcs:
		if !is_instance_valid(npc):
			continue
		
		if npc.get_faction_id() == faction_id:
			faction_npcs.append(npc)
	
	return faction_npcs

func _get_content_db() -> Node:
	if has_node("/root/ContentDb"):
		return get_node("/root/ContentDb")
	if has_node("/root/ContentDB"):
		return get_node("/root/ContentDB")
	return null
