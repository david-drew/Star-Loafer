# File: res://scripts/comms/CommsManager.gd
# Autoload this as "CommsManager"

extends Node

# -----------------
# Signals
# -----------------

signal comm_hail_created(hail_id: String, data: Dictionary)
signal comm_hail_presented_to_player(hail_id: String, data: Dictionary)
signal comm_hail_accepted(hail_id: String, data: Dictionary)
signal comm_hail_ignored(hail_id: String, data: Dictionary)
signal comm_hail_timed_out(hail_id: String, data: Dictionary)
signal comm_hail_ignored_by_target(data: Dictionary)

signal comm_session_started(session_id: String, data: Dictionary)
signal comm_session_ended(session_id: String, data: Dictionary)

signal comm_broadcast_published(data: Dictionary)
signal comm_news_item_added(data: Dictionary)
signal comm_rumor_added(data: Dictionary)

# -----------------
# Editor-configurable paths
# -----------------

@export var channels_config_path: String = "res://data/comms/comm_channels.json"
@export var templates_config_path: String = "res://data/comms/comm_message_templates.json"
@export var ai_profiles_config_path: String = "res://data/comms/comm_ai_profiles.json"

@export var use_event_bus: bool = true
@export var event_bus_path: NodePath = NodePath("/root/EventBus")

# If true, CommsManager will check hail TTLs in _process()
@export var enable_hail_timeouts: bool = true

# -----------------
# Internal state
# -----------------

var _event_bus: Node = null

var _channels: Dictionary = {}              # channel_id -> Dictionary
var _templates_by_id: Dictionary = {}       # template_id -> Dictionary
var _ai_profiles_by_id: Dictionary = {}     # profile_id -> Dictionary

var _endpoints: Dictionary = {}             # endpoint_id -> Dictionary
var _pending_hails: Dictionary = {}         # hail_id -> Dictionary (includes expires_at)
var _hail_id_counter: int = 1

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_init_event_bus()
	_load_channels()
	_load_templates()
	_load_ai_profiles()


func _process(delta: float) -> void:
	if not enable_hail_timeouts:
		return

	if _pending_hails.size() == 0:
		return

	var now: float = Time.get_ticks_msec() / 1000.0
	var expired: Array = []

	for hail_id in _pending_hails.keys():
		var data: Dictionary = _pending_hails[hail_id]
		if data.has("expires_at"):
			var expires_at: float = float(data["expires_at"])
			if now >= expires_at:
				expired.append(hail_id)

	for hail_id in expired:
		var hail_data: Dictionary = _pending_hails[hail_id]
		_pending_hails.erase(hail_id)

		var payload: Dictionary = {
			"hail_id": hail_id,
			"from_id": hail_data.get("from_id", ""),
			"to_id": hail_data.get("to_id", ""),
			"template_id": hail_data.get("template_id", "")
		}

		emit_signal("comm_hail_timed_out", hail_id, payload)
		_emit_bus_event("COMM_HAIL_TIMED_OUT", payload)

		# Fire template-defined on_timeout hooks if present
		if hail_data.has("template") and hail_data["template"].has("on_timeout"):
			_fire_template_events(hail_data["template"]["on_timeout"], payload)


# =========================
# Public API: Endpoints
# =========================

func register_endpoint(endpoint: Dictionary) -> void:
	# Expected fields: id, type, faction_id, channels, capabilities, ai_profile_id, etc.
	if not endpoint.has("id"):
		push_warning("[CommsManager] register_endpoint called without 'id'")
		return

	var eid: String = str(endpoint["id"])
	_endpoints[eid] = endpoint


func unregister_endpoint(endpoint_id: String) -> void:
	if _endpoints.has(endpoint_id):
		_endpoints.erase(endpoint_id)


func get_endpoint(endpoint_id: String) -> Dictionary:
	if _endpoints.has(endpoint_id):
		return _endpoints[endpoint_id]
	return {}


# =========================
# Public API: Narrative / Broadcast
# =========================

func publish_broadcast(packet: Dictionary) -> void:
	# Generic entry point for system_broadcast, trade_news, etc.
	emit_signal("comm_broadcast_published", packet)
	_emit_bus_event("COMM_BROADCAST_PUBLISHED", packet)


func publish_news(packet: Dictionary) -> void:
	emit_signal("comm_news_item_added", packet)
	_emit_bus_event("COMM_NEWS_ITEM_ADDED", packet)


func publish_rumor(packet: Dictionary) -> void:
	emit_signal("comm_rumor_added", packet)
	_emit_bus_event("COMM_RUMOR_ADDED", packet)


# =========================
# Public API: Hails (system / NPC initiated)
# =========================

func request_hail(from_id: String, to_id: String, template_id: String) -> void:
	# Used by AI / narrative systems when they know which template to use.
	if not _endpoints.has(from_id):
		push_warning("[CommsManager] request_hail: unknown from_id: " + from_id)
		return
	if not _endpoints.has(to_id):
		push_warning("[CommsManager] request_hail: unknown to_id: " + to_id)
		return

	var template: Dictionary = _get_template(template_id)
	if template.is_empty():
		push_warning("[CommsManager] request_hail: unknown template_id: " + template_id)
		return

	if not _validate_channel_for_endpoints(template, from_id, to_id):
		push_warning("[CommsManager] request_hail: channel not valid for endpoints")
		return

	_create_pending_hail(from_id, to_id, template)


# =========================
# Public API: Player → NPC hails with AI ignore support
# =========================

func request_player_hail(target_id: String, context: Dictionary = {}) -> void:
	# Lightweight helper: player tries to hail a target.
	# AI profile decides whether to ignore or respond.
	if not _endpoints.has("ship_player"):
		push_warning("[CommsManager] request_player_hail: missing 'ship_player' endpoint")
		return
	if not _endpoints.has(target_id):
		push_warning("[CommsManager] request_player_hail: unknown target_id: " + target_id)
		return

	var target_endpoint: Dictionary = _endpoints[target_id]
	var profile_id: String = str(target_endpoint.get("ai_profile_id", ""))
	if profile_id == "" or not _ai_profiles_by_id.has(profile_id):
		# No profile: assume cooperative, emit an event so other systems can respond.
		var payload_no_profile: Dictionary = {
			"from_id": "ship_player",
			"to_id": target_id,
			"context": context
		}
		_emit_bus_event("COMM_OUTGOING_HAIL_REQUESTED", payload_no_profile)
		return

	var profile: Dictionary = _ai_profiles_by_id[profile_id]
	var accepts: bool = _evaluate_ai_incoming_player_hail(profile, context)

	if not accepts:
		var ignore_payload: Dictionary = {
			"from_id": "ship_player",
			"to_id": target_id,
			"reason": "ai_profile_ignore",
			"context": context
		}
		emit_signal("comm_hail_ignored_by_target", ignore_payload)
		_emit_bus_event("COMM_HAIL_IGNORED_BY_TARGET", ignore_payload)
		return

	# If accepted, notify listeners that target is open to respond.
	var payload_accept: Dictionary = {
		"from_id": "ship_player",
		"to_id": target_id,
		"context": context
	}
	_emit_bus_event("COMM_OUTGOING_HAIL_REQUESTED", payload_accept)
	# External systems (dialogue, narrative, etc.) should now pick a template and call request_hail().


# =========================
# Public API: Hail resolution
# =========================

func accept_hail(hail_id: String) -> void:
	if not _pending_hails.has(hail_id):
		push_warning("[CommsManager] accept_hail: unknown hail_id: " + hail_id)
		return

	var hail_data: Dictionary = _pending_hails[hail_id]
	_pending_hails.erase(hail_id)

	var payload: Dictionary = {
		"hail_id": hail_id,
		"from_id": hail_data.get("from_id", ""),
		"to_id": hail_data.get("to_id", ""),
		"template_id": hail_data.get("template_id", "")
	}

	emit_signal("comm_hail_accepted", hail_id, payload)
	_emit_bus_event("COMM_HAIL_ACCEPTED", payload)

	# Fire template-defined on_accept hooks
	if hail_data.has("template") and hail_data["template"].has("on_accept"):
		_fire_template_events(hail_data["template"]["on_accept"], payload)

	# Consumers can create a CommSession based on template.session_type if present.


func ignore_hail(hail_id: String, explicit: bool = true) -> void:
	if not _pending_hails.has(hail_id):
		return

	var hail_data: Dictionary = _pending_hails[hail_id]
	_pending_hails.erase(hail_id)

	var payload: Dictionary = {
		"hail_id": hail_id,
		"from_id": hail_data.get("from_id", ""),
		"to_id": hail_data.get("to_id", ""),
		"template_id": hail_data.get("template_id", ""),
		"explicit": explicit
	}

	emit_signal("comm_hail_ignored", hail_id, payload)
	_emit_bus_event("COMM_HAIL_IGNORED", payload)

	# Fire template-defined on_ignore hooks
	if hail_data.has("template") and hail_data["template"].has("on_ignore"):
		_fire_template_events(hail_data["template"]["on_ignore"], payload)


# =========================
# Internal: Hail creation
# =========================

func _create_pending_hail(from_id: String, to_id: String, template: Dictionary) -> void:
	var hail_id: String = _next_hail_id()
	var ttl: float = 10.0

	if template.has("ttl"):
		ttl = float(template["ttl"])

	var now: float = Time.get_ticks_msec() / 1000.0
	var expires_at: float = now + ttl

	var hail_data: Dictionary = {
		"hail_id": hail_id,
		"from_id": from_id,
		"to_id": to_id,
		"template_id": template.get("id", ""),
		"template": template,
		"expires_at": expires_at
	}

	_pending_hails[hail_id] = hail_data

	var ui_payload: Dictionary = {
		"hail_id": hail_id,
		"from_id": from_id,
		"to_id": to_id,
		"text": template.get("text", ""),
		"category": template.get("category", "hail"),
		"channel_id": template.get("channel_id", "direct"),
		"ttl": ttl
	}

	emit_signal("comm_hail_created", hail_id, ui_payload)
	emit_signal("comm_hail_presented_to_player", hail_id, ui_payload)

	_emit_bus_event("COMM_HAIL_CREATED", ui_payload)
	_emit_bus_event("COMM_HAIL_PRESENTED_TO_PLAYER", ui_payload)


func _next_hail_id() -> String:
	var id: int = _hail_id_counter
	_hail_id_counter += 1
	return "hail_" + str(id)


# =========================
# Internal: AI evaluation
# =========================

func _evaluate_ai_incoming_player_hail(profile: Dictionary, context: Dictionary) -> bool:
	# Reads profile["incoming_hail_response"]["from_player"].
	if not profile.has("incoming_hail_response"):
		return true

	var incoming: Dictionary = profile["incoming_hail_response"]
	if not incoming.has("from_player"):
		return true

	var from_player: Dictionary = incoming["from_player"]

	var base_accept: float = 1.0
	if from_player.has("base_accept_chance"):
		base_accept = float(from_player["base_accept_chance"])

	var chance: float = base_accept

	# Optional rep_modifiers: [{ "tier": "Allied", "delta": 0.2 }, ...]
	if from_player.has("rep_modifiers") and context.has("rep_tier"):
		var rep_tier: String = str(context["rep_tier"])
		for mod in from_player["rep_modifiers"]:
			var mod_tier: String = str(mod.get("tier", ""))
			if mod_tier == rep_tier:
				var delta: float = float(mod.get("delta", 0.0))
				chance += delta

	# Optional ignore_when: [{ "state": "in_combat", "chance": 0.8 }, ...]
	if from_player.has("ignore_when") and context.has("state"):
		var state: String = str(context["state"])
		for rule in from_player["ignore_when"]:
			var rule_state: String = str(rule.get("state", ""))
			if rule_state == state:
				var ignore_chance: float = float(rule.get("chance", 0.0))
				# If this rule fires, we reduce accept chance.
				chance -= ignore_chance

	# Clamp
	if chance < 0.0:
		chance = 0.0
	if chance > 1.0:
		chance = 1.0

	var roll: float = _rng.randf()
	if roll <= chance:
		return true

	return false


# =========================
# Internal: Template loading / helpers
# =========================

func _get_template(template_id: String) -> Dictionary:
	if _templates_by_id.has(template_id):
		return _templates_by_id[template_id]
	return {}


func _load_channels() -> void:
	_channels.clear()
	if channels_config_path == "":
		return

	if not FileAccess.file_exists(channels_config_path):
		return

	var text: String = FileAccess.get_file_as_string(channels_config_path)
	if text == "":
		return

	var result = JSON.parse_string(text)
	if typeof(result) != TYPE_DICTIONARY:
		return

	if result.has("channels"):
		for ch in result["channels"]:
			if ch.has("id"):
				var cid: String = str(ch["id"])
				_channels[cid] = ch


func _load_templates() -> void:
	_templates_by_id.clear()
	if templates_config_path == "":
		return

	if not FileAccess.file_exists(templates_config_path):
		return

	var text: String = FileAccess.get_file_as_string(templates_config_path)
	if text == "":
		return

	var result = JSON.parse_string(text)
	if typeof(result) != TYPE_DICTIONARY:
		return

	if result.has("templates"):
		for tpl in result["templates"]:
			if tpl.has("id"):
				var tid: String = str(tpl["id"])
				_templates_by_id[tid] = tpl


func _load_ai_profiles() -> void:
	_ai_profiles_by_id.clear()
	if ai_profiles_config_path == "":
		return

	if not FileAccess.file_exists(ai_profiles_config_path):
		return

	var text: String = FileAccess.get_file_as_string(ai_profiles_config_path)
	if text == "":
		return

	var result = JSON.parse_string(text)
	if typeof(result) != TYPE_DICTIONARY:
		return

	if result.has("profiles"):
		for p in result["profiles"]:
			if p.has("id"):
				var pid: String = str(p["id"])
				_ai_profiles_by_id[pid] = p


# Validate that template channel is allowed for from/to endpoints (minimal)
func _validate_channel_for_endpoints(template: Dictionary, from_id: String, to_id: String) -> bool:
	if not template.has("channel_id"):
		return true

	var channel_id: String = str(template["channel_id"])
	if not _channels.has(channel_id):
		return true

	var from_ep: Dictionary = get_endpoint(from_id)
	var to_ep: Dictionary = get_endpoint(to_id)

	if from_ep.is_empty() or to_ep.is_empty():
		return false

	# Simple check: both must list this channel, if they declare channels.
	if from_ep.has("channels"):
		var from_channels: Array = from_ep["channels"]
		if not from_channels.has(channel_id):
			return false

	if to_ep.has("channels"):
		var to_channels: Array = to_ep["channels"]
		if not to_channels.has(channel_id):
			return false

	return true


# =========================
# Internal: Template event hooks
# =========================

func _fire_template_events(events: Array, base_payload: Dictionary) -> void:
	for e in events:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if not e.has("event"):
			continue

		var ev_name: String = str(e["event"])
		var payload: Dictionary = {}
		# Start with base payload so consumers know hail/template context.
		for k in base_payload.keys():
			payload[k] = base_payload[k]

		if e.has("payload"):
			var extra: Dictionary = e["payload"]
			for key in extra.keys():
				payload[key] = extra[key]

		_emit_bus_event(ev_name, payload)


# =========================
# Internal: EventBus bridge
# =========================

func _init_event_bus() -> void:
	_event_bus = null
	if not use_event_bus:
		return

	if str(event_bus_path) == "":
		return

	if has_node(event_bus_path):
		_event_bus = get_node(event_bus_path)


func _emit_bus_event(event_name: String, payload: Dictionary) -> void:
	if not use_event_bus:
		return
	if _event_bus == null:
		return

	# Adapt this to your actual EventBus API.
	# This is intentionally defensive and non-prescriptive.
	if _event_bus.has_method("emit_event"):
		_event_bus.call("emit_event", event_name, payload)
	elif _event_bus.has_method("publish"):
		_event_bus.call("publish", event_name, payload)
	elif _event_bus.has_signal("event"):
		_event_bus.emit_signal("event", event_name, payload)
