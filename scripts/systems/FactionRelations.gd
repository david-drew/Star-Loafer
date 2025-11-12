extends Node
class_name FactionRelations

## Tracks player reputation with each faction and manages interaction memory
## Determines when interactions are "worth reporting" to affect faction standing

# Player reputation with each faction (-100 to 100 scale for easier math)
var player_reputation: Dictionary = {}  # faction_id: int

# Recent interactions for memory (rolling window)
var interaction_history: Array[Dictionary] = []
const MAX_HISTORY_SIZE: int = 100

# Reputation tiers (for template matching and context)
const REP_TIERS = {
	"Hostile": -60,
	"Unfriendly": -30,
	"Neutral": 0,
	"Friendly": 30,
	"Allied": 60
}

# Base probabilities that an interaction type gets reported to faction
const INTERACTION_REPORT_BASE_CHANCES = {
	"ignored_hail": 0.05,
	"rude_response": 0.15,
	"refused_scan": 0.40,
	"refused_request": 0.25,
	"smuggling_caught": 0.95,
	"fled_authority": 0.85,
	"attacked_npc": 1.0,
	"destroyed_npc": 1.0,
	"assisted_npc": 0.70,
	"completed_trade": 0.30,
	"completed_mission": 0.90
}

# Severity multipliers for reputation impact
enum Severity {
	MINOR = 0,      # -1 to -3 rep
	MODERATE = 1,   # -5 to -10 rep
	MAJOR = 2,      # -15 to -25 rep
	CRITICAL = 3    # -30 to -50 rep
}

const SEVERITY_REP_RANGES = {
	Severity.MINOR: Vector2(-3, -1),
	Severity.MODERATE: Vector2(-10, -5),
	Severity.MAJOR: Vector2(-25, -15),
	Severity.CRITICAL: Vector2(-50, -30)
}

# For positive interactions
const POSITIVE_REP_RANGES = {
	Severity.MINOR: Vector2(1, 3),
	Severity.MODERATE: Vector2(5, 10),
	Severity.MAJOR: Vector2(15, 25),
	Severity.CRITICAL: Vector2(30, 50)
}

signal reputation_changed(faction_id: String, old_rep: int, new_rep: int, tier_changed: bool)
signal reputation_tier_changed(faction_id: String, old_tier: String, new_tier: String)


func _ready() -> void:
	_initialize_factions()
	

func _initialize_factions() -> void:
	# Wait a frame for FactionManager to be ready
	await get_tree().process_frame
	
	var faction_manager = get_node_or_null("/root/GameRoot/Systems/FactionManager")
	if not faction_manager:
		push_warning("FactionRelations: FactionManager not found, cannot initialize")
		return
	
	# Initialize reputation for all factions at neutral
	if faction_manager.has_method("get_all_faction_ids"):
		var faction_ids = faction_manager.get_all_faction_ids()
		for faction_id in faction_ids:
			if not player_reputation.has(faction_id):
				player_reputation[faction_id] = 0
	
	# If FactionManager doesn't have that method, we'll populate dynamically as we encounter factions
	print("FactionRelations: Initialized with %d factions" % player_reputation.size())


## Get player's current reputation value with a faction
func get_reputation(faction_id: String) -> int:
	return player_reputation.get(faction_id, 0)


## Get player's reputation tier with a faction
func get_reputation_tier(faction_id: String) -> String:
	var rep = get_reputation(faction_id)
	
	if rep >= REP_TIERS.Allied:
		return "Allied"
	elif rep >= REP_TIERS.Friendly:
		return "Friendly"
	elif rep >= REP_TIERS.Neutral:
		return "Neutral"
	elif rep >= REP_TIERS.Unfriendly:
		return "Unfriendly"
	else:
		return "Hostile"


## Adjust reputation with a faction
func adjust_reputation(faction_id: String, delta: int, reason: String = "") -> void:
	if not player_reputation.has(faction_id):
		player_reputation[faction_id] = 0
	
	var old_rep = player_reputation[faction_id]
	var old_tier = get_reputation_tier(faction_id)
	
	player_reputation[faction_id] = clamp(old_rep + delta, -100, 100)
	var new_rep = player_reputation[faction_id]
	var new_tier = get_reputation_tier(faction_id)
	
	var tier_changed = (old_tier != new_tier)
	
	# Add to history
	_add_to_history({
		"faction_id": faction_id,
		"delta": delta,
		"reason": reason,
		"old_rep": old_rep,
		"new_rep": new_rep,
		"timestamp": Time.get_ticks_msec()
	})
	
	# Emit signals
	reputation_changed.emit(faction_id, old_rep, new_rep, tier_changed)
	
	if tier_changed:
		reputation_tier_changed.emit(faction_id, old_tier, new_tier)
		print("FactionRelations: %s reputation tier changed: %s -> %s (rep: %d)" % [faction_id, old_tier, new_tier, new_rep])


## Evaluate whether an interaction should affect faction reputation
## Returns true if the interaction is "worth reporting"
func should_report_interaction(
	npc_node: Node,
	interaction_type: String,
	severity: Severity,
	context: Dictionary = {}
) -> bool:
	
	# Get base chance from interaction type
	var base_chance = INTERACTION_REPORT_BASE_CHANCES.get(interaction_type, 0.5)
	
	# Get NPC personality if available
	var personality_mod = 0.0
	if npc_node.has_method("get_personality_trait"):
		# Lawful NPCs are more likely to report
		personality_mod += npc_node.get_personality_trait("lawfulness") * 0.2
		# Paranoid NPCs are more likely to report
		personality_mod += npc_node.get_personality_trait("paranoia") * 0.15
		# Helpful NPCs are less likely to report minor infractions
		if severity == Severity.MINOR:
			personality_mod -= npc_node.get_personality_trait("helpfulness") * 0.1
	
	# Severity modifier
	var severity_mod = float(severity) * 0.15  # Each severity level adds 15% chance
	
	# Calculate final chance
	var final_chance = base_chance + personality_mod + severity_mod
	
	# Random nudge (±5%)
	final_chance += randf_range(-0.05, 0.05)
	
	# Clamp and roll
	final_chance = clamp(final_chance, 0.0, 1.0)
	
	return randf() < final_chance


## Process an interaction and potentially adjust reputation
func process_interaction(
	npc_node: Node,
	interaction_type: String,
	severity: Severity,
	is_positive: bool = false,
	context: Dictionary = {}
) -> void:
	
	# Get NPC faction
	var faction_id: String = ""
	if npc_node.has("faction_id"):
		faction_id = npc_node.faction_id
	elif npc_node.has_method("get_faction_id"):
		faction_id = npc_node.get_faction_id()
	
	if faction_id.is_empty():
		return  # Independent NPC, no faction to report to
	
	# Check if this interaction should be reported
	if not should_report_interaction(npc_node, interaction_type, severity, context):
		return  # NPC chose not to report it
	
	# Calculate reputation delta
	var rep_range = POSITIVE_REP_RANGES[severity] if is_positive else SEVERITY_REP_RANGES[severity]
	var delta = roundi(randf_range(rep_range.x, rep_range.y))
	
	# Apply reputation change
	adjust_reputation(faction_id, delta, interaction_type)


## Get recent interactions with a specific faction
func get_faction_history(faction_id: String, limit: int = 10) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	
	for entry in interaction_history:
		if entry.get("faction_id") == faction_id:
			result.append(entry)
			if result.size() >= limit:
				break
	
	return result


## Check if player has hostile standing with any faction
func has_hostile_factions() -> bool:
	for faction_id in player_reputation:
		if get_reputation_tier(faction_id) == "Hostile":
			return true
	return false


## Get all factions at a specific tier
func get_factions_by_tier(tier: String) -> Array[String]:
	var result: Array[String] = []
	
	for faction_id in player_reputation:
		if get_reputation_tier(faction_id) == tier:
			result.append(faction_id)
	
	return result


func _add_to_history(entry: Dictionary) -> void:
	interaction_history.push_front(entry)
	
	# Trim to max size
	if interaction_history.size() > MAX_HISTORY_SIZE:
		interaction_history.resize(MAX_HISTORY_SIZE)


## Save/Load support
func get_save_data() -> Dictionary:
	return {
		"player_reputation": player_reputation.duplicate(),
		"interaction_history": interaction_history.duplicate()
	}


func load_save_data(data: Dictionary) -> void:
	if data.has("player_reputation"):
		player_reputation = data.player_reputation.duplicate()
	
	if data.has("interaction_history"):
		interaction_history = data.interaction_history.duplicate()
	
	print("FactionRelations: Loaded save data for %d factions" % player_reputation.size())
