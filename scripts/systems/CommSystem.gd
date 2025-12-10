extends Node
class_name CommSystem

## Core communication system managing hails, responses, broadcasts, and context evaluation

# Loaded data
var message_templates: Dictionary = {}
var ai_profiles: Dictionary = {}

# Active conversations
var active_conversations: Array[Dictionary] = []  # {id, initiator, recipient, context, status, timeout, time_elapsed, hail_type, initial_category}
var conversation_queue: Array[Dictionary] = []
var recent_hails: Dictionary = {}  # npc_id: timestamp (for cooldown tracking)
var last_auto_hail_time: Dictionary = {}  # entity_id: msec

# Configuration
const BASE_BROADCAST_RANGE_AU = 7.0
const MAX_ACTIVE_CONVERSATIONS = 5  # Queue additional hails to avoid spam
const AUTO_HAIL_RANGE = 6000.0
const AUTO_HAIL_INTERVAL = 1.5
const AUTO_HAIL_COOLDOWN = 20.0

# Hail timeout durations by entity type (seconds)
const HAIL_TIMEOUTS = {
	"station": 120.0,
	"trader": 60.0,
	"pirate": 30.0,
	"police": 15.0,
	"military": 10.0,
	"science": 90.0,
	"default": 45.0
}

# Personality trait definitions for dynamic generation
const DEFAULT_PERSONALITY = {
	"aggression": 0.5,
	"chattiness": 0.5,
	"greed": 0.5,
	"lawfulness": 0.5,
	"paranoia": 0.5,
	"helpfulness": 0.5
}

# Signals (kept for compatibility)
signal hail_received(initiator: Node, recipient: Node, context: Dictionary)
signal hail_accepted(conversation_id: int)
signal hail_ignored(initiator: Node, recipient: Node, reason: String)
signal hail_timeout(initiator: Node, recipient: Node)
signal response_generated(conversation_id: int, message: Dictionary)
signal broadcast_sent(source: Node, message: Dictionary, range_au: float)
signal conversation_ended(conversation_id: int, reason: String)

var _next_conversation_id: int = 0
var _auto_hail_timer: float = 0.0


func _ready() -> void:
	# DEBUG: startup log and player detection # DEBUG
	var p = get_tree().get_first_node_in_group("player")
	print("[COMM DEBUG] CommSystem ready. player_present=%s" % (p != null))
	_load_data_files()
	set_process(true)

	if Engine.is_editor_hint():
		return

	_connect_event_bus()


func _connect_event_bus() -> void:
	if not EventBus.docking_approved.is_connected(_on_docking_approved):
		EventBus.docking_approved.connect(_on_docking_approved)
	if not EventBus.docking_denied.is_connected(_on_docking_denied):
		EventBus.docking_denied.connect(_on_docking_denied)
	if not EventBus.comm_response_chosen.is_connected(_on_comm_response_chosen):
		EventBus.comm_response_chosen.connect(_on_comm_response_chosen)
	if not EventBus.comm_hail_accepted.is_connected(_on_hail_accepted):
		EventBus.comm_hail_accepted.connect(_on_hail_accepted)
	if not EventBus.comm_hail_ignored.is_connected(_on_hail_ignored):
		EventBus.comm_hail_ignored.connect(_on_hail_ignored)


func _process(delta: float) -> void:
	_check_hail_timeouts(delta)
	_process_conversation_queue()
	_auto_hail_timer += delta
	if _auto_hail_timer >= AUTO_HAIL_INTERVAL:
		_auto_hail_timer = 0.0
		_auto_initiate_hails()

func _load_data_files() -> void:
	# Load message templates
	var templates_path = "res://data/dialogue/comm_message_templates.json"
	if FileAccess.file_exists(templates_path):
		var file = FileAccess.open(templates_path, FileAccess.READ)
		if file:
			var json = JSON.new()
			var parse_result = json.parse(file.get_as_text())
			if parse_result == OK:
				message_templates = json.data
				print("CommSystem: Loaded %d message template categories" % message_templates.get("templates", {}).size())
			else:
				push_error("CommSystem: Failed to parse message templates JSON")
			file.close()
	else:
		push_warning("CommSystem: Message templates file not found at %s" % templates_path)
	
	# Load AI profiles
	var profiles_path = "res://data/dialogue/comm_ai_profiles.json"
	if FileAccess.file_exists(profiles_path):
		var file = FileAccess.open(profiles_path, FileAccess.READ)
		if file:
			var json = JSON.new()
			var parse_result = json.parse(file.get_as_text())
			if parse_result == OK:
				var data = json.data
				ai_profiles = {}
				for profile in data.get("profiles", []):
					ai_profiles[profile.id] = profile
				print("CommSystem: Loaded %d AI profiles" % ai_profiles.size())
			else:
				push_error("CommSystem: Failed to parse AI profiles JSON")
			file.close()
	else:
		push_warning("CommSystem: AI profiles file not found at %s" % profiles_path)


func initiate_hail(initiator: Node, recipient: Node, hail_type: String = "general") -> int:
	# DEBUG: log hail attempts for troubleshooting
	print("[COMM DEBUG] initiate_hail: from=%s to=%s type=%s" % [_get_entity_name(initiator), _get_entity_name(recipient), hail_type])
	if not _can_initiate_hail(initiator):
		# DEBUG: cooldown prevents hail
		print("[COMM DEBUG] initiate_hail blocked by cooldown for %s" % _get_entity_id(initiator))
		return -1

	if not _can_accept_hail(recipient):
		# DEBUG: recipient busy, queue hail
		print("[COMM DEBUG] recipient busy, queuing hail from %s to %s" % [_get_entity_name(initiator), _get_entity_name(recipient)])
		_queue_hail(initiator, recipient, hail_type)
		return -1

	var context: Dictionary = build_comm_context(initiator, recipient)
	context["hail_type"] = hail_type
	# Decide who speaks first: the hailed party responds unless player was hailed
	var responder: Node = initiator
	if _is_player(initiator):
		responder = recipient
	var initial_category := _determine_initial_category(responder, hail_type)

	var conversation_id = _create_conversation(initiator, recipient, context, hail_type, initial_category)
	context["conversation_id"] = conversation_id
	context["turn_index"] = 0

	var initiator_id = _get_entity_id(initiator)
	recent_hails[initiator_id] = Time.get_ticks_msec()

	hail_received.emit(initiator, recipient, context)
	# Bridge to global EventBus so UI receives hail popups
	EventBus.hail_received.emit(initiator, recipient, context)
	# DEBUG: emitted hail_received signal
	print("[COMM DEBUG] emitted hail_received for conv=%s" % conversation_id)

	var player_is_recipient := _is_player(recipient)
	var player_is_initiator := _is_player(initiator)

	if player_is_initiator or not player_is_recipient:
		EventBus.comm_session_started.emit(conversation_id, context)
		_begin_conversation(conversation_id)
	else:
		# DEBUG: waiting on player acceptance
		print("[COMM DEBUG] pending hail awaiting player accept conv=%s" % conversation_id)

	return conversation_id


func accept_hail(conversation_id: int) -> void:
	var conv := _get_conversation_by_id(conversation_id)
	if conv.is_empty():
		return
	if conv.get("status", "pending") != "pending":
		return

	conv["status"] = "active"
	conv["context"]["turn_index"] = 0
	conv["context"]["conversation_id"] = conversation_id
	_update_conversation(conv)

	EventBus.comm_session_started.emit(conversation_id, conv["context"])
	_begin_conversation(conversation_id)


func ignore_hail(conversation_id: int, reason: String = "ignored") -> void:
	var conv := _get_conversation_by_id(conversation_id)
	if conv.is_empty():
		return
	_end_conversation(conversation_id, reason)
	EventBus.comm_session_ended.emit(conversation_id, reason)


func _begin_conversation(conversation_id: int) -> void:
	var conv := _get_conversation_by_id(conversation_id)
	if conv.is_empty():
		return

	conv["status"] = "active"
	conv["context"]["conversation_id"] = conversation_id
	if not conv["context"].has("turn_index"):
		conv["context"]["turn_index"] = 0
	_update_conversation(conv)

	var response_type:Variant = conv.get("initial_category", "")
	if response_type == "":
		return

	var responder: Node = conv.get("recipient", null)
	var caller: Node = conv.get("initiator", null)
	if responder == null or caller == null:
		return

	var template: Dictionary = generate_response(responder, conv["context"], response_type)
	_emit_comm_message(
		responder,
		caller,
		conv["context"],
		template,
		response_type,
		conversation_id,
		response_type,
        "hail"
	)

## Build comprehensive context for a comm interaction
func build_comm_context(initiator: Node, recipient: Node) -> Dictionary:
	var context = {
		"initiator_id": _get_entity_id(initiator),
		"recipient_id": _get_entity_id(recipient),
		"initiator_type": _get_entity_type(initiator),
		"recipient_type": _get_entity_type(recipient),
		"timestamp": Time.get_ticks_msec()
	}
	
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		# DEBUG: no player found; comm context minimal # DEBUG
		print("[COMM DEBUG] build_comm_context: player not found, initiator=%s recipient=%s" % [_get_entity_name(initiator), _get_entity_name(recipient)])
		return context
	
	var player_is_recipient = (recipient == player)
	var player_is_initiator = (initiator == player)
	var other_entity = player if player_is_initiator else (initiator if player_is_recipient else null)
	
	if player_is_recipient or player_is_initiator:
		if "current_hull" in player and "max_hull" in player:
			context.player_hull_percent = player.current_hull / float(player.max_hull)
		
		if "current_shields" in player and "max_shields" in player:
			context.player_shield_percent = player.current_shields / float(player.max_shields)
		
		if "cargo" in player and player.cargo != null:
			context.player_cargo_capacity_used = player.cargo.size()
		
		if other_entity and other_entity != player:
			context.estimated_cargo_valuable = _estimate_cargo_value(player, other_entity)
	
	if "faction_id" in initiator and initiator.faction_id:
		var faction_relations = get_node_or_null("/root/GameRoot/Systems/FactionRelations")
		if faction_relations:
			context.faction_standing = faction_relations.get_reputation_tier(initiator.faction_id)
			context.faction_id = initiator.faction_id
			context.faction_reputation = faction_relations.get_reputation(initiator.faction_id)
	
	if "current_state" in initiator:
		context.npc_state = _ai_state_to_string(initiator.current_state)
	
	if "global_position" in initiator and "global_position" in recipient:
		var distance_px = initiator.global_position.distance_to(recipient.global_position)
		context.distance_au = distance_px / GameState.AU_TO_PIXELS

	if "faction_id" in initiator:
		context["sender_faction_id"] = initiator.faction_id
	if "faction_id" in recipient:
		context["recipient_faction_id"] = recipient.faction_id
	
	return context


func generate_response(
	responder: Node,
	context: Dictionary,
	response_type: String = "general_acknowledgment"
) -> Dictionary:
	var personality = _get_or_generate_personality(responder)
	var template_category = message_templates.get("templates", {}).get(response_type, [])
	if template_category.is_empty():
		push_warning("CommSystem: No templates found for response_type '%s'" % response_type)
		return _generate_fallback_response(response_type)
	
	var selected_template = _select_weighted_template(template_category, context, personality)
	
	if selected_template.is_empty():
		return _generate_fallback_response(response_type)
	
	var response = {
		"text": selected_template.get("text", "..."),
		"template_id": selected_template.get("id", ""),
		"response_type": response_type,
		"options": selected_template.get("response_options", []),
		"context": context
	}
	
	return response


func _select_weighted_template(
	templates: Array,
	context: Dictionary,
	personality: Dictionary
) -> Dictionary:
	var weighted_options = []
	
	for template in templates:
		if template.has("context_requirements"):
			if not _context_matches(template.context_requirements, context):
				continue
		
		var weight = template.get("base_weight", 1.0)
		
		if template.has("personality_modifiers"):
			for trate in template.personality_modifiers:
				if personality.has(trate):
					var modifier = template.personality_modifiers[trate]
					weight *= (1.0 + personality[trate] * modifier)
		
		if template.has("reputation_modifiers") and context.has("faction_standing"):
			var rep_mod = template.reputation_modifiers.get(context.faction_standing, 0)
			weight *= (1.0 + rep_mod)
		
		if weight > 0:
			weighted_options.append({"template": template, "weight": weight})
	
	if weighted_options.is_empty():
		return {}

	return _weighted_random_choice(weighted_options)

func _context_matches(requirements: Dictionary, context: Dictionary) -> bool:
	for key in requirements:
		var required_value = requirements[key]
		var actual_value = context.get(key)
		
		if required_value is bool:
			if actual_value != required_value:
				return false
		elif required_value is String:
			if actual_value != required_value:
				return false
		elif required_value is float or required_value is int:
			if actual_value == null or actual_value < required_value:
				return false
	
	return true


func _weighted_random_choice(options: Array) -> Dictionary:
	if options.is_empty():
		return {}
	
	var total_weight = 0.0
	for option in options:
		total_weight += option.weight
	
	var rand_value = randf() * total_weight
	var cumulative = 0.0
	
	for option in options:
		cumulative += option.weight
		if rand_value <= cumulative:
			return option.template
	
	return options[0].template


func _get_or_generate_personality(npc: Node) -> Dictionary:
	if "personality" in npc and npc.personality is Dictionary:
		return npc.personality
	
	var profile_id = npc.get("comm_profile_id") if "comm_profile_id" in npc else "default"
	var profile = ai_profiles.get(profile_id, {})
	
	var personality = DEFAULT_PERSONALITY.duplicate()
	
	if profile.has("personality_traits"):
		for trate in profile.personality_traits:
			personality[trate] = profile.personality_traits[trate]
	
	if "ship_data" in npc:
		personality = _apply_ship_personality_modifiers(personality, npc.ship_data)
	
	for trate in personality:
		personality[trate] = clamp(personality[trate] + randf_range(-0.1, 0.1), 0.0, 1.0)
	
	if "personality" in npc:
		npc.personality = personality
	else:
		npc.set_meta("personality", personality)
	
	return personality


func _apply_ship_personality_modifiers(personality: Dictionary, ship_data: Dictionary) -> Dictionary:
	var modified = personality.duplicate()
	
	var category = ship_data.get("category", "")
	match category:
		"Courier":
			modified.chattiness = clamp(modified.chattiness + 0.2, 0, 1)
		"Corvette", "Frigate", "Destroyer":
			modified.lawfulness = clamp(modified.lawfulness + 0.3, 0, 1)
			modified.aggression = clamp(modified.aggression + 0.2, 0, 1)
		"Freighter", "Hauler":
			modified.greed = clamp(modified.greed + 0.2, 0, 1)
			modified.paranoia = clamp(modified.paranoia + 0.1, 0, 1)
		"Scout", "Explorer":
			modified.chattiness = clamp(modified.chattiness + 0.15, 0, 1)
			modified.helpfulness = clamp(modified.helpfulness + 0.1, 0, 1)
	
	var tags = ship_data.get("tags", [])
	if "diplomatic" in tags:
		modified.helpfulness = clamp(modified.helpfulness + 0.3, 0, 1)
		modified.lawfulness = clamp(modified.lawfulness + 0.2, 0, 1)
	if "combat" in tags or "military" in tags:
		modified.aggression = clamp(modified.aggression + 0.15, 0, 1)
		modified.lawfulness = clamp(modified.lawfulness + 0.1, 0, 1)
	if "pirate" in tags:
		modified.greed = clamp(modified.greed + 0.4, 0, 1)
		modified.lawfulness = clamp(modified.lawfulness - 0.3, 0, 1)
	
	return modified

func _estimate_cargo_value(player: Node, npc: Node) -> bool:
	var confidence = 0.0
	
	if "ship_class" in player:
		var ship_class = player.ship_class
		if ship_class in ["freighter", "transport", "hauler"]:
			confidence += 0.4
		elif ship_class in ["courier"]:
			confidence += 0.2
	
	if "current_mass" in player and "base_mass" in player:
		if player.current_mass > player.base_mass * 1.5:
			confidence += 0.2
	
	if "faction_id" in npc and npc.faction_id:
		var faction_relations = get_node_or_null("/root/GameRoot/Systems/FactionRelations")
		if faction_relations:
			var history = faction_relations.get_faction_history(npc.faction_id, 5)
			for entry in history:
				if entry.get("reason") == "completed_trade":
					confidence += 0.3
					break
	
	var personality = _get_or_generate_personality(npc)
	confidence += personality.get("greed", 0.5) * 0.3
	
	return randf() < clamp(confidence, 0.0, 0.95)


func broadcast_message(
	source: Node,
	message_text: String,
	subtype: String = "general",
	priority: String = "normal",
	tech_level: int = 1
) -> void:
	var tech_multiplier = 1.0 + (tech_level * 0.2)
	var importance_multiplier = {
		"low": 0.8,
		"normal": 1.0,
		"high": 1.5,
		"emergency": 2.0
	}.get(priority, 1.0)
	
	var effective_range = BASE_BROADCAST_RANGE_AU * tech_multiplier * importance_multiplier
	
	var broadcast_data = {
		"type": "broadcast",
		"subtype": subtype,
		"source_id": _get_entity_id(source),
		"source_name": _get_entity_name(source),
		"text": message_text,
		"priority": priority,
		"tech_level": tech_level,
		"timestamp": Time.get_ticks_msec(),
		"range_au": effective_range
	}
	
	broadcast_sent.emit(source, broadcast_data, effective_range)
	
	print("CommSystem: Broadcast from %s (range: %.1f AU): %s" % [broadcast_data.source_name, effective_range, message_text])


func _create_conversation(
	initiator: Node,
	recipient: Node,
	context: Dictionary,
	hail_type: String,
	initial_category: String
) -> int:
	var conversation_id = _next_conversation_id
	_next_conversation_id += 1

	var timeout_duration = _get_timeout_duration(initiator)
	var status := "pending" if _is_player(recipient) else "active"

	var conversation: Dictionary = {
		"id": conversation_id,
		"initiator": initiator,
		"recipient": recipient,
		"context": context,
		"timestamp": Time.get_ticks_msec(),
		"timeout": timeout_duration,
		"time_elapsed": 0.0,
		"hail_type": hail_type,
		"initial_category": initial_category,
		"status": status
	}

	active_conversations.append(conversation)
	return conversation_id


func _can_initiate_hail(initiator: Node) -> bool:
	var entity_id = _get_entity_id(initiator)
	
	if not recent_hails.has(entity_id):
		return true
	
	var profile_id = initiator.get("comm_profile_id") if "comm_profile_id" in initiator else ""
	var profile = ai_profiles.get(profile_id, {})
	var max_hails_per_min = profile.get("outgoing_hail_behavior", {}).get("max_hail_frequency_per_min", 3)
	var cooldown_ms = (60.0 / max_hails_per_min) * 1000.0
	
	var time_since_last = Time.get_ticks_msec() - recent_hails[entity_id]
	
	return time_since_last >= cooldown_ms


func _can_accept_hail(recipient: Node) -> bool:
	var recipient_conversation_count = 0
	for conv in active_conversations:
		if conv.get("recipient", null) == recipient:
			recipient_conversation_count += 1
	
	if recipient_conversation_count >= MAX_ACTIVE_CONVERSATIONS:
		return false
	
	if recipient.has_method("can_accept_hail"):
		return recipient.can_accept_hail()
	
	return true


func _queue_hail(initiator: Node, recipient: Node, hail_type: String) -> void:
	conversation_queue.append({
		"initiator": initiator,
		"recipient": recipient,
		"hail_type": hail_type,
		"queued_at": Time.get_ticks_msec()
	})
func _process_conversation_queue() -> void:
	if conversation_queue.is_empty():
		return
	
	var to_remove = []
	
	for i in range(conversation_queue.size()):
		var queued: Dictionary = conversation_queue[i]
		
		var initiator: Node = queued.get("initiator", null)
		var recipient: Node = queued.get("recipient", null)
		
		if not is_instance_valid(initiator) or not is_instance_valid(recipient):
			to_remove.append(i)
			continue
		
		if _can_accept_hail(recipient):
			# DEBUG: processing queued hail
			print("[COMM DEBUG] dequeuing hail from %s to %s" % [_get_entity_name(initiator), _get_entity_name(recipient)])
			initiate_hail(initiator, recipient, queued.get("hail_type", "general"))
			to_remove.append(i)
	
	for i in range(to_remove.size() - 1, -1, -1):
		conversation_queue.remove_at(to_remove[i])


func _auto_initiate_hails() -> void:
	var player = _get_player_ship()
	if player == null:
		return

	var endpoints: Array = []
	endpoints.append_array(get_tree().get_nodes_in_group("npc_ship"))
	endpoints.append_array(get_tree().get_nodes_in_group("station"))
	endpoints.append_array(get_tree().get_nodes_in_group("inhabited_body"))

	for endpoint in endpoints:
		if not is_instance_valid(endpoint):
			continue
		if endpoint == player:
			continue
		if not "global_position" in endpoint or not "global_position" in player:
			continue

		var dist = player.global_position.distance_to(endpoint.global_position)
		if dist > AUTO_HAIL_RANGE:
			continue

		var entity_id = _get_entity_id(endpoint)
		var now_ms = Time.get_ticks_msec()
		var last_ms = last_auto_hail_time.get(entity_id, -1)
		if last_ms >= 0 and (now_ms - last_ms) < AUTO_HAIL_COOLDOWN * 1000.0:
			continue

		var chance := 0.7
		if _has_market_or_trade(endpoint):
			chance = 1.0

		# DEBUG: log auto hail decision # DEBUG
		print("[COMM DEBUG] auto hail candidate=%s dist=%.0f chance=%.2f" % [_get_entity_name(endpoint), dist, chance])

		last_auto_hail_time[entity_id] = now_ms
		if randf() <= chance:
			var conv_id = initiate_hail(endpoint, player, "auto_proximity")
			print("[COMM DEBUG] auto hail fired from %s conv=%s" % [_get_entity_name(endpoint), str(conv_id)])


func _check_hail_timeouts(delta: float) -> void:
	var to_remove = []
	
	for i in range(active_conversations.size()):
		var conv = active_conversations[i]
		if conv.get("status", "pending") != "pending":
			continue

		conv["time_elapsed"] += delta
		
		if conv["time_elapsed"] >= conv["timeout"]:
			if is_instance_valid(conv.get("initiator", null)) and is_instance_valid(conv.get("recipient", null)):
				hail_timeout.emit(conv["initiator"], conv["recipient"])
				_handle_timeout(conv)
				# DEBUG: timeout logged
				print("[COMM DEBUG] pending hail timed out conv=%s" % conv.get("id", -1))
			to_remove.append(i)
	
	for i in range(to_remove.size() - 1, -1, -1):
		active_conversations.remove_at(to_remove[i])


func _handle_timeout(conversation: Dictionary) -> void:
	var initiator = conversation.get("initiator", null)
	var recipient = conversation.get("recipient", null)
	
	if initiator and "faction_id" in initiator and initiator.faction_id:
		var faction_relations = get_node_or_null("/root/GameRoot/Systems/FactionRelations")
		if faction_relations:
			faction_relations.process_interaction(
				initiator,
				"ignored_hail",
				FactionRelations.Severity.MINOR,
				false,
				conversation.get("context", {})
			)
	
	EventBus.comm_hail_timed_out.emit(conversation.get("id", -1), conversation.get("context", {}))
	print("CommSystem: Hail from %s to %s timed out" % [_get_entity_name(initiator), _get_entity_name(recipient)])


func _get_timeout_duration(entity: Node) -> float:
	var entity_type = _get_entity_type(entity)
	return HAIL_TIMEOUTS.get(entity_type, HAIL_TIMEOUTS.default)


func end_conversation(conversation_id: int, reason: String = "completed") -> void:
	_end_conversation(conversation_id, reason)
	conversation_ended.emit(conversation_id, reason)


func _end_conversation(conversation_id: int, _reason: String) -> void:
	for i in range(active_conversations.size()):
		if active_conversations[i].get("id", -1) == conversation_id:
			active_conversations.remove_at(i)
			return


func _get_entity_id(entity: Node) -> String:
	if "entity_id" in entity:
		return entity.entity_id
	return entity.name


func _get_entity_type(entity: Node) -> String:
	if entity.is_in_group("station"):
		return "station"
	elif "comm_profile_id" in entity:
		return entity.comm_profile_id
	elif entity.is_in_group("player"):
		return "player"
	return "default"


func _get_entity_name(entity: Node) -> String:
	if entity == null:
		return "Unknown"
	if "entity_name" in entity:
		return entity.entity_name
	elif "station_name" in entity:
		return entity.station_name
	return entity.name


func _ai_state_to_string(state: int) -> String:
	match state:
		0: return "idle"
		1: return "patrol"
		2: return "trade"
		3: return "flee"
		4: return "attack"
		_: return "unknown"
func _generate_fallback_response(response_type: String) -> Dictionary:
	return {
		"text": "...",
		"template_id": "fallback",
		"response_type": response_type,
		"options": [],
		"context": {}
	}


func _build_message_data(
	sender: Node,
	recipient: Node,
	context: Dictionary,
	template: Dictionary,
	template_category: String,
	conversation_id,
	message_type: String,
	channel: String
) -> Dictionary:
	var msg: Dictionary = {}

	msg["conversation_id"] = conversation_id
	msg["turn_index"] = context.get("turn_index", 0)

	msg["from_label"] = _get_entity_name(sender)
	msg["from_type"] = _get_entity_type(sender)
	msg["from_id"] = _get_entity_id(sender)
	msg["from_faction_id"] = context.get("sender_faction_id", "")

	msg["to_label"] = _get_entity_name(recipient)
	msg["to_type"] = _get_entity_type(recipient)
	msg["to_id"] = _get_entity_id(recipient)
	msg["to_faction_id"] = context.get("recipient_faction_id", "")

	msg["channel"] = channel
	msg["message_type"] = message_type

	msg["template_id"] = template.get("id", "")
	msg["template_category"] = template_category

	msg["text"] = template.get("text", "...")
	msg["response_options"] = template.get("response_options", [])

	msg["icon_hint"] = context.get("icon_hint", msg["from_type"])
	msg["importance"] = context.get("importance", "info")

	msg["timeout_seconds"] = template.get("timeout_seconds", 0.0)
	msg["can_be_ignored"] = template.get("can_be_ignored", true)
	msg["ignore_consequences"] = template.get("ignore_consequences", {})

	msg["context"] = context.duplicate(true)

	msg["trade_available"] = _is_trade_available(sender, recipient)
	msg["in_trade_mode"] = _player_in_trade_mode()

	return msg


func _emit_comm_message(
	sender: Node,
	recipient: Node,
	context: Dictionary,
	template: Dictionary,
	template_category: String,
	conversation_id,
	message_type: String,
	channel: String
) -> void:
	if template.is_empty():
		return

	var message_data := _build_message_data(
		sender,
		recipient,
		context,
		template,
		template_category,
		conversation_id,
		message_type,
		channel
	)

	EventBus.comm_message_received.emit(message_data)

	if has_signal("response_generated"):
		response_generated.emit(conversation_id, message_data)


func _on_docking_approved(station: Node, ship: Node, bay_id) -> void:
	var context: Dictionary = build_comm_context(station, ship)
	context["docking_result"] = "approved"
	context["docking_bay_id"] = bay_id
	context["conversation_id"] = -1
	context["turn_index"] = 0

	var category := "docking_approved"
	var template: Dictionary = generate_response(station, context, category)

	_emit_comm_message(
		station,
		ship,
		context,
		template,
		category,
		-1,
		category,
        "docking"
	)


func _on_docking_denied(station: Node, ship: Node, reason: String) -> void:
	var context: Dictionary = build_comm_context(station, ship)
	context["docking_result"] = "denied"
	context["docking_denial_reason"] = reason
	context["conversation_id"] = -1
	context["turn_index"] = 0

	var category := "docking_denied"
	var template: Dictionary = generate_response(station, context, category)

	_emit_comm_message(
		station,
		ship,
		context,
		template,
		category,
		-1,
		category,
        "docking"
	)
func _get_conversation_by_id(conversation_id: int) -> Dictionary:
	for conv in active_conversations:
		if conv.get("id", -1) == conversation_id:
			return conv
	return {}


func _on_comm_response_chosen(conversation_id, response_index: int, response: Dictionary) -> void:
	if not response.has("leads_to_category") and not response.has("leads_to_template_id") and not response.has("action"):
		return

	if typeof(conversation_id) != TYPE_INT:
		conversation_id = int(conversation_id)

	if conversation_id < 0:
		return

	var conv: Dictionary = _get_conversation_by_id(conversation_id)
	if conv.is_empty():
		return
	if conv.get("status", "pending") != "active":
		return

	var initiator: Node = conv.get("initiator", null)
	var recipient: Node = conv.get("recipient", null)
	var context: Dictionary = conv.get("context", {})

	var turn_index: int = 0
	if context.has("turn_index"):
		turn_index = int(context["turn_index"])
	context["turn_index"] = turn_index + 1
	context["conversation_id"] = conversation_id

	if response.get("action", "") == "enter_trade":
		start_trade_mode(conversation_id)
		return
	if response.get("action", "") == "exit_trade":
		exit_trade_mode()
		return
	if response.get("action", "") == "end_conversation":
		_end_conversation(conversation_id, "closed")
		EventBus.comm_session_ended.emit(conversation_id, "closed")
		return

	var follow_category: String = ""
	if response.has("leads_to_category"):
		follow_category = str(response["leads_to_category"])

	if follow_category == "":
		return

	var template: Dictionary = generate_response(recipient, context, follow_category)

	_emit_comm_message(
		recipient,
		initiator,
		context,
		template,
		follow_category,
		conversation_id,
		follow_category,
        "hail"
	)

	for i in range(active_conversations.size()):
		if active_conversations[i].get("id", -1) == conversation_id:
			active_conversations[i]["context"] = context
			break


func _determine_initial_category(responder: Node, _hail_type: String) -> String:
	var responder_type: String = _get_entity_type(responder)
	if responder_type == "station":
		return "station_greeting"
	if responder_type == "player":
		return "npc_greeting"  # player hailed an NPC; let player speak if needed
	return "npc_greeting"


func _update_conversation(conv: Dictionary) -> void:
	for i in range(active_conversations.size()):
		if active_conversations[i].get("id", -1) == conv.get("id", -1):
			active_conversations[i] = conv
			return


func _is_player(node: Node) -> bool:
	return node != null and node.is_in_group("player")


func _on_hail_accepted(conversation_id: int, _context: Dictionary) -> void:
	accept_hail(conversation_id)


func _on_hail_ignored(conversation_id: int, _context: Dictionary, reason: String) -> void:
	ignore_hail(conversation_id, reason)
func start_trade_mode(conversation_id: int) -> bool:
	var conv := _get_conversation_by_id(conversation_id)
	if conv.is_empty():
		return false

	var player_ship := _get_player_from_conversation(conv)
	var anchor := _get_trade_anchor(conv)
	if player_ship == null or anchor == null:
		return false

	var docking_manager = get_node_or_null("/root/GameRoot/Systems/DockingManager")
	if docking_manager == null:
		push_warning("CommSystem: DockingManager not found for trade mode")
		return false

	return docking_manager.enter_trade_orbit(player_ship, anchor)


func exit_trade_mode() -> void:
	var docking_manager = get_node_or_null("/root/GameRoot/Systems/DockingManager")
	if docking_manager == null:
		return

	var player_ship = _get_player_ship()
	if player_ship:
		docking_manager.exit_trade_orbit(player_ship)


func _get_player_from_conversation(conv: Dictionary) -> Node:
	var initiator: Node = conv.get("initiator", null)
	var recipient: Node = conv.get("recipient", null)
	if _is_player(initiator):
		return initiator
	if _is_player(recipient):
		return recipient
	return _get_player_ship()


func _get_trade_anchor(conv: Dictionary) -> Node:
	var initiator: Node = conv.get("initiator", null)
	var recipient: Node = conv.get("recipient", null)

	if initiator == null or recipient == null:
		return null

	if _is_player(initiator):
		return recipient
	if _is_player(recipient):
		return initiator
	return recipient


func _is_trade_available(sender: Node, recipient: Node) -> bool:
	var anchor: Node = null
	if _is_player(sender):
		anchor = recipient
	elif _is_player(recipient):
		anchor = sender
	else:
		return false

	if anchor == null:
		return false

	if anchor.has_method("can_dock"):
		return anchor.can_dock()
	if "can_dock" in anchor:
		return bool(anchor.can_dock)
	if anchor.has_meta("inhabitant_data"):
		var id_meta: Dictionary = anchor.get_meta("inhabitant_data")
		if id_meta.get("has_spaceport", false):
			return true
	if anchor.has_method("get"):
		if "inhabitant_data" in anchor:
			var idata: Dictionary = anchor.inhabitant_data
			if idata.get("has_spaceport", false):
				return true
			if int(idata.get("population_level", 0)) > 0:
				return true
		if "planet_data" in anchor:
			var pdata: Dictionary = anchor.planet_data
			return bool(pdata.get("inhabitant_data", {}).get("has_spaceport", false))

	return false


func _has_market_or_trade(node: Node) -> bool:
	if node == null:
		return false
	# Stations: docking/services/market tier imply trading
	if node.is_in_group("station"):
		if "market_tier" in node and int(node.market_tier) > 0:
			return true
		if "services" in node and (node.services is Array) and node.services.size() > 0:
			return true
		if "can_dock" in node and bool(node.can_dock):
			return true
	# Planets/moons: check inhabitant data / spaceport
	if node.is_in_group("inhabited_body"):
		if "planet_data" in node:
			var pdata: Dictionary = node.planet_data
			var inhab: Dictionary = pdata.get("inhabitant_data", {})
			if inhab.get("has_spaceport", false):
				return true
			if int(inhab.get("population_level", 0)) > 0:
				return true
		if "inhabitant_data" in node:
			var idata: Dictionary = node.inhabitant_data
			if idata.get("has_spaceport", false):
				return true
			if int(idata.get("population_level", 0)) > 0:
				return true
		if node.has_meta("inhabitant_data"):
			var meta_data: Dictionary = node.get_meta("inhabitant_data")
			if meta_data.get("has_spaceport", false):
				return true
			if int(meta_data.get("population_level", 0)) > 0:
				return true
	return false


func _player_in_trade_mode() -> bool:
	var docking_manager = get_node_or_null("/root/GameRoot/Systems/DockingManager")
	var player_ship = _get_player_ship()
	if docking_manager == null or player_ship == null:
		return false
	return docking_manager.is_in_trade_orbit(player_ship)


func _get_player_ship() -> Node:
	return get_tree().get_first_node_in_group("player")
