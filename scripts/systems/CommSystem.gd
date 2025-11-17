extends Node
class_name CommSystem

## Core communication system managing hails, responses, broadcasts, and context evaluation

# Loaded data
var message_templates: Dictionary = {}
var ai_profiles: Dictionary = {}

# Active conversations
var active_conversations: Array[Dictionary] = []  # {initiator, recipient, context, timestamp, timeout}
var conversation_queue: Array[Dictionary] = []
var recent_hails: Dictionary = {}  # npc_id: timestamp (for cooldown tracking)

# Configuration
const BASE_BROADCAST_RANGE_AU = 7.0
const MAX_ACTIVE_CONVERSATIONS = 5  # Queue additional hails to avoid spam

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

# Signals
signal hail_received(initiator: Node, recipient: Node, context: Dictionary)
signal hail_accepted(conversation_id: int)
signal hail_ignored(initiator: Node, recipient: Node, reason: String)
signal hail_timeout(initiator: Node, recipient: Node)
signal response_generated(conversation_id: int, message: Dictionary)
signal broadcast_sent(source: Node, message: Dictionary, range_au: float)
signal conversation_ended(conversation_id: int, reason: String)

var _next_conversation_id: int = 0


func _ready() -> void:
	_load_data_files()
	set_process(true)

	if Engine.is_editor_hint():
		return

	# Listen for docking events so we can speak when docking is approved/denied.
	if EventBus.docking_approved.is_connected(_on_docking_approved) == false:
		EventBus.docking_approved.connect(_on_docking_approved)
	if EventBus.docking_denied.is_connected(_on_docking_denied) == false:
		EventBus.docking_denied.connect(_on_docking_denied)

	# Listen for player dialogue choices.
	if EventBus.comm_response_chosen.is_connected(_on_comm_response_chosen) == false:
		EventBus.comm_response_chosen.connect(_on_comm_response_chosen)

func _process(delta: float) -> void:
	_check_hail_timeouts(delta)
	_process_conversation_queue()


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
	# Check if initiator can hail (cooldown check)
	if not _can_initiate_hail(initiator):
		return -1

	# Check if recipient can accept
	if not _can_accept_hail(recipient):
		_queue_hail(initiator, recipient, hail_type)
		return -1

	# Build context
	var context: Dictionary = build_comm_context(initiator, recipient)
	context["hail_type"] = hail_type

	# Create conversation
	var conversation_id = _create_conversation(initiator, recipient, context)
	context["conversation_id"] = conversation_id
	context["turn_index"] = 0

	# Update cooldown
	var initiator_id = _get_entity_id(initiator)
	recent_hails[initiator_id] = Time.get_ticks_msec()

	# Emit hail signal (gameplay can react if needed)
	hail_received.emit(initiator, recipient, context)

	# Auto-generate an initial greeting from the recipient
	var response_type: String = ""
	var recipient_type: String = _get_entity_type(recipient)

	if recipient_type == "station":
		response_type = "station_greeting"
	elif recipient_type == "player":
		response_type = ""
	else:
		# Ships, NPCs, etc.
		response_type = "npc_greeting"

	if response_type != "":
		var template: Dictionary = generate_response(recipient, context, response_type)
		_emit_comm_message(
			recipient,
			initiator,
			context,
			template,
			response_type,
			conversation_id,
			response_type,
			"hail"
		)

	return conversation_id



## Build comprehensive context for a comm interaction
func build_comm_context(initiator: Node, recipient: Node) -> Dictionary:
	var context = {
		"initiator_id": _get_entity_id(initiator),
		"recipient_id": _get_entity_id(recipient),
		"initiator_type": _get_entity_type(initiator),
		"recipient_type": _get_entity_type(recipient),
		"timestamp": Time.get_ticks_msec()
	}
	
	# Get player reference
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return context
	
	# If player is involved in the conversation
	var player_is_recipient = (recipient == player)
	var player_is_initiator = (initiator == player)
	var other_entity = player if player_is_initiator else (initiator if player_is_recipient else null)
	
	if player_is_recipient or player_is_initiator:
		# Player stats
		if player.has("current_hull") and player.has("max_hull"):
			context.player_hull_percent = player.current_hull / float(player.max_hull)
		
		if player.has("current_shields") and player.has("max_shields"):
			context.player_shield_percent = player.current_shields / float(player.max_shields)
		
		if player.has("cargo"):
			context.player_cargo_capacity_used = player.cargo.size()
		
		# Estimate if player has valuable cargo (from NPC perspective)
		if other_entity and other_entity != player:
			context.estimated_cargo_valuable = _estimate_cargo_value(player, other_entity)
	
	# Faction context
	if initiator.has("faction_id") and initiator.faction_id:
		var faction_relations = get_node_or_null("/root/GameRoot/Systems/FactionRelations")
		if faction_relations:
			context.faction_standing = faction_relations.get_reputation_tier(initiator.faction_id)
			context.faction_id = initiator.faction_id
			context.faction_reputation = faction_relations.get_reputation(initiator.faction_id)
	
	# NPC state
	if initiator.has("current_state"):
		context.npc_state = _ai_state_to_string(initiator.current_state)
	
	# Spatial context
	if initiator.has("global_position") and recipient.has("global_position"):
		var distance_px = initiator.global_position.distance_to(recipient.global_position)
		context.distance_au = distance_px / GameState.AU_TO_PIXELS
	
	return context


## Generate a response based on profile, templates, and context
func generate_response(
	responder: Node,
	context: Dictionary,
	response_type: String = "general_acknowledgment"
) -> Dictionary:
	
	# Get responder's personality
	var personality = _get_or_generate_personality(responder)
	
	# Get appropriate template category
	var template_category = message_templates.get("templates", {}).get(response_type, [])
	if template_category.is_empty():
		push_warning("CommSystem: No templates found for response_type '%s'" % response_type)
		return _generate_fallback_response(response_type)
	
	# Select weighted template
	var selected_template = _select_weighted_template(template_category, context, personality)
	
	if selected_template.is_empty():
		return _generate_fallback_response(response_type)
	
	# Build response message
	var response = {
		"text": selected_template.get("text", "..."),
		"template_id": selected_template.get("id", ""),
		"response_type": response_type,
		"options": selected_template.get("response_options", []),
		"context": context
	}
	
	return response


## Select a template using weighted random selection based on personality and context
func _select_weighted_template(
	templates: Array,
	context: Dictionary,
	personality: Dictionary
) -> Dictionary:
	
	var weighted_options = []
	
	for template in templates:
		# Check context requirements
		if template.has("context_requirements"):
			if not _context_matches(template.context_requirements, context):
				continue
		
		# Calculate weight
		var weight = template.get("base_weight", 1.0)
		
		# Apply personality modifiers
		if template.has("personality_modifiers"):
			for trate in template.personality_modifiers:
				if personality.has(trate):
					var modifier = template.personality_modifiers[trate]
					weight *= (1.0 + personality[trate] * modifier)
		
		# Apply reputation modifiers
		if template.has("reputation_modifiers") and context.has("faction_standing"):
			var rep_mod = template.reputation_modifiers.get(context.faction_standing, 0)
			weight *= (1.0 + rep_mod)
		
		if weight > 0:
			weighted_options.append({"template": template, "weight": weight})
	
	# Weighted random selection
	if weighted_options.is_empty():
		return {}
	
	return _weighted_random_choice(weighted_options)


## Check if context requirements are met
func _context_matches(requirements: Dictionary, context: Dictionary) -> bool:
	for key in requirements:
		var required_value = requirements[key]
		var actual_value = context.get(key)
		
		# Handle different comparison types
		if required_value is bool:
			if actual_value != required_value:
				return false
		elif required_value is String:
			if actual_value != required_value:
				return false
		elif required_value is float or required_value is int:
			# Assume numeric requirements are minimums
			if actual_value == null or actual_value < required_value:
				return false
	
	return true


## Weighted random selection from array of {template, weight} dictionaries
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
	
	# Fallback to first option
	return options[0].template


## Get or generate personality for an NPC
func _get_or_generate_personality(npc: Node) -> Dictionary:
	# Check if NPC already has personality
	if npc.has("personality") and npc.personality is Dictionary:
		return npc.personality
	
	# Generate personality based on profile and ship data
	var profile_id = npc.get("comm_profile_id") if npc.has("comm_profile_id") else "default"
	var profile = ai_profiles.get(profile_id, {})
	
	var personality = DEFAULT_PERSONALITY.duplicate()
	
	# Start with profile base personality if it exists
	if profile.has("personality_traits"):
		for trate in profile.personality_traits:
			personality[trate] = profile.personality_traits[trate]
	
	# Modify based on ship data if available
	if npc.has("ship_data"):
		personality = _apply_ship_personality_modifiers(personality, npc.ship_data)
	
	# Add random variation (±10%)
	for trate in personality:
		personality[trate] = clamp(personality[trate] + randf_range(-0.1, 0.1), 0.0, 1.0)
	
	# Cache it on the NPC
	if npc.has("personality"):
		npc.personality = personality
	else:
		npc.set_meta("personality", personality)
	
	return personality


## Apply ship-based personality modifiers
func _apply_ship_personality_modifiers(personality: Dictionary, ship_data: Dictionary) -> Dictionary:
	var modified = personality.duplicate()
	
	# Ship category influences
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
	
	# Tags influence
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


## Estimate if player has valuable cargo (probabilistic from NPC perspective)
func _estimate_cargo_value(player: Node, npc: Node) -> bool:
	var confidence = 0.0
	
	# Ship type hints (if we know player's ship class)
	if player.has("ship_class"):
		var ship_class = player.ship_class
		if ship_class in ["freighter", "transport", "hauler"]:
			confidence += 0.4
		elif ship_class in ["courier"]:
			confidence += 0.2
	
	# Ship signature/mass (heavily loaded ships)
	if player.has("current_mass") and player.has("base_mass"):
		if player.current_mass > player.base_mass * 1.5:
			confidence += 0.2
	
	# Faction knowledge (if player has trading history with this faction)
	if npc.has("faction_id") and npc.faction_id:
		var faction_relations = get_node_or_null("/root/GameRoot/Systems/FactionRelations")
		if faction_relations:
			var history = faction_relations.get_faction_history(npc.faction_id, 5)
			for entry in history:
				if entry.get("reason") == "completed_trade":
					confidence += 0.3
					break
	
	# NPC personality: greedy NPCs assume everyone has goods
	var personality = _get_or_generate_personality(npc)
	confidence += personality.get("greed", 0.5) * 0.3
	
	return randf() < clamp(confidence, 0.0, 0.95)


## Broadcast a message to all entities in range
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
	
	# Emit signal (UI or other systems can handle delivery)
	broadcast_sent.emit(source, broadcast_data, effective_range)
	
	print("CommSystem: Broadcast from %s (range: %.1f AU): %s" % [broadcast_data.source_name, effective_range, message_text])


## Create a new conversation
func _create_conversation(initiator: Node, recipient: Node, context: Dictionary) -> int:
	var conversation_id = _next_conversation_id
	_next_conversation_id += 1
	
	var timeout_duration = _get_timeout_duration(initiator)
	
	var conversation = {
		"id": conversation_id,
		"initiator": initiator,
		"recipient": recipient,
		"context": context,
		"timestamp": Time.get_ticks_msec(),
		"timeout": timeout_duration,
		"time_elapsed": 0.0
	}
	
	active_conversations.append(conversation)
	
	return conversation_id


## Check if an entity can initiate a hail (cooldown check)
func _can_initiate_hail(initiator: Node) -> bool:
	var entity_id = _get_entity_id(initiator)
	
	if not recent_hails.has(entity_id):
		return true
	
	# Get profile-based cooldown
	var profile_id = initiator.get("comm_profile_id") if initiator.has("comm_profile_id") else ""
	var profile = ai_profiles.get(profile_id, {})
	var max_hails_per_min = profile.get("outgoing_hail_behavior", {}).get("max_hail_frequency_per_min", 3)
	var cooldown_ms = (60.0 / max_hails_per_min) * 1000.0
	
	var time_since_last = Time.get_ticks_msec() - recent_hails[entity_id]
	
	return time_since_last >= cooldown_ms


## Check if an entity can accept a hail
func _can_accept_hail(recipient: Node) -> bool:
	# Check if already in too many conversations
	var recipient_conversation_count = 0
	for conv in active_conversations:
		if conv.recipient == recipient:
			recipient_conversation_count += 1
	
	if recipient_conversation_count >= MAX_ACTIVE_CONVERSATIONS:
		return false
	
	# Check recipient-specific acceptance logic
	if recipient.has_method("can_accept_hail"):
		return recipient.can_accept_hail()
	
	return true


## Queue a hail for later processing
func _queue_hail(initiator: Node, recipient: Node, hail_type: String) -> void:
	conversation_queue.append({
		"initiator": initiator,
		"recipient": recipient,
		"hail_type": hail_type,
		"queued_at": Time.get_ticks_msec()
	})


## Process queued hails
func _process_conversation_queue() -> void:
	if conversation_queue.is_empty():
		return
	
	var to_remove = []
	
	for i in range(conversation_queue.size()):
		var queued = conversation_queue[i]
		
		# Check if still valid
		if not is_instance_valid(queued.initiator) or not is_instance_valid(queued.recipient):
			to_remove.append(i)
			continue
		
		# Try to initiate
		if _can_accept_hail(queued.recipient):
			initiate_hail(queued.initiator, queued.recipient, queued.hail_type)
			to_remove.append(i)
	
	# Remove processed items
	for i in range(to_remove.size() - 1, -1, -1):
		conversation_queue.remove_at(to_remove[i])


## Check for hail timeouts
func _check_hail_timeouts(delta: float) -> void:
	var to_remove = []
	
	for i in range(active_conversations.size()):
		var conv = active_conversations[i]
		conv.time_elapsed += delta
		
		if conv.time_elapsed >= conv.timeout:
			# Timeout occurred
			if is_instance_valid(conv.initiator) and is_instance_valid(conv.recipient):
				hail_timeout.emit(conv.initiator, conv.recipient)
				_handle_timeout(conv)
			to_remove.append(i)
	
	# Remove timed out conversations
	for i in range(to_remove.size() - 1, -1, -1):
		active_conversations.remove_at(to_remove[i])


## Handle hail timeout consequences
func _handle_timeout(conversation: Dictionary) -> void:
	var initiator = conversation.initiator
	var recipient = conversation.recipient
	
	# If initiator has faction, potentially affect reputation
	if initiator.has("faction_id") and initiator.faction_id:
		var faction_relations = get_node_or_null("/root/GameRoot/Systems/FactionRelations")
		if faction_relations:
			faction_relations.process_interaction(
				initiator,
				"ignored_hail",
				FactionRelations.Severity.MINOR,
				false,
				conversation.context
			)
	
	print("CommSystem: Hail from %s to %s timed out" % [_get_entity_name(initiator), _get_entity_name(recipient)])


## Get timeout duration for an entity
func _get_timeout_duration(entity: Node) -> float:
	var entity_type = _get_entity_type(entity)
	return HAIL_TIMEOUTS.get(entity_type, HAIL_TIMEOUTS.default)


## End a conversation
func end_conversation(conversation_id: int, reason: String = "completed") -> void:
	for i in range(active_conversations.size()):
		if active_conversations[i].id == conversation_id:
			conversation_ended.emit(conversation_id, reason)
			active_conversations.remove_at(i)
			return


## Utility: Get entity ID
func _get_entity_id(entity: Node) -> String:
	if entity.has("entity_id"):
		return entity.entity_id
	return entity.name


## Utility: Get entity type
func _get_entity_type(entity: Node) -> String:
	if entity.is_in_group("station"):
		return "station"
	elif entity.has("comm_profile_id"):
		return entity.comm_profile_id
	elif entity.is_in_group("player"):
		return "player"
	return "default"


## Utility: Get entity name
func _get_entity_name(entity: Node) -> String:
	if entity.has("entity_name"):
		return entity.entity_name
	elif entity.has("station_name"):
		return entity.station_name
	return entity.name


## Utility: Convert AIState enum to string
func _ai_state_to_string(state: int) -> String:
	match state:
		0: return "idle"
		1: return "patrol"
		2: return "trade"
		3: return "flee"
		4: return "attack"
		_: return "unknown"


## Fallback response generator
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

	# Conversation/thread
	msg["conversation_id"] = conversation_id
	msg["turn_index"] = context.get("turn_index", 0)

	# Sender/recipient labels and ids
	msg["from_label"] = _get_entity_name(sender)
	msg["from_type"] = _get_entity_type(sender)
	msg["from_id"] = _get_entity_id(sender)
	msg["from_faction_id"] = context.get("sender_faction_id", "")

	msg["to_label"] = _get_entity_name(recipient)
	msg["to_type"] = _get_entity_type(recipient)
	msg["to_id"] = _get_entity_id(recipient)
	msg["to_faction_id"] = context.get("recipient_faction_id", "")

	# Message classification
	msg["channel"] = channel            # e.g. "hail", "docking", "threat", "broadcast"
	msg["message_type"] = message_type  # e.g. "npc_greeting", "docking_approved"

	msg["template_id"] = template.get("id", "")
	msg["template_category"] = template_category

	# Text & options
	msg["text"] = template.get("text", "...")
	msg["response_options"] = template.get("response_options", [])

	# Simple UI hints (optional)
	msg["icon_hint"] = context.get("icon_hint", msg["from_type"])
	msg["importance"] = context.get("importance", "info")

	# Timeout / ignore behavior (optional)
	msg["timeout_seconds"] = template.get("timeout_seconds", 0.0)
	msg["can_be_ignored"] = template.get("can_be_ignored", true)
	msg["ignore_consequences"] = template.get("ignore_consequences", {})

	# Attach context snapshot for debugging/future use
	msg["context"] = context.duplicate(true)

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

	# If you still use CommSystem's own signal, mirror it here.
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
		if conv.id == conversation_id:
			return conv
	return {}

func _on_comm_response_chosen(conversation_id, response_index: int, response: Dictionary) -> void:
	# If the response doesn't define any follow-up, there's nothing to do.
	if not response.has("leads_to_category") and not response.has("leads_to_template_id"):
		return

	# Normalize conversation_id to int if it's coming in as a string
	if typeof(conversation_id) != TYPE_INT:
		conversation_id = int(conversation_id)

	if conversation_id < 0:
		return

	# Look up the conversation in active_conversations
	var conv: Dictionary = _get_conversation_by_id(conversation_id)
	if conv.is_empty():
		return

	var initiator: Node = conv.initiator
	var recipient: Node = conv.recipient
	var context: Dictionary = conv.context

	# Bump turn index and keep it in context
	var turn_index: int = 0
	if context.has("turn_index"):
		turn_index = int(context["turn_index"])
	context["turn_index"] = turn_index + 1
	context["conversation_id"] = conversation_id

	# Decide what category/template to go to next
	var follow_category: String = ""
	if response.has("leads_to_category"):
		follow_category = str(response["leads_to_category"])

	# (Optional) direct template id support if you add that later:
	# if follow_category == "" and response.has("leads_to_template_id"):
	#     follow_category = str(response["leads_to_template_id"])

	if follow_category == "":
		return

	# Generate a follow-up from the same responder (recipient speaks again)
	var template: Dictionary = generate_response(recipient, context, follow_category)

	_emit_comm_message(
		recipient,
		initiator,
		context,
		template,
		follow_category,      # template_category
		conversation_id,
		follow_category,      # message_type
		"hail"                # channel
	)

	# Optional: write updated context back into the active_conversations array
	for i in range(active_conversations.size()):
		if active_conversations[i].id == conversation_id:
			active_conversations[i].context = context
			break
