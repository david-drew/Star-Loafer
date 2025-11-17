# res://scripts/systems/components/ShipComponentSystem.gd
#
# Per-ship runtime system for components:
#   - Tracks installed components.
#   - Enforces component_space and hardpoint constraints.
#   - Computes effective stats (hull + components + crew + damage + power).
#   - Handles on/off, throttle, priorities, and basic power-shedding.
#
# All component IDs are expected to be in canonical form "type__local_name",
# but this class always goes through ComponentDB._canonicalize_id(), so it
# will also accept legacy formats like "reactor_fission_mk1" transparently.

extends Node
class_name ShipComponentSystem

var hull: Dictionary = {}                         # Raw hull data
var installed: Array[Dictionary] = []             # [{ id, state, throttle, priority, condition_hp }]
var crew_assignments: Dictionary = {}             # station -> { staffed: bool, skill: String }

var db: ComponentDB = null
var ship_db: ShipTypeDB = null

var ai_fallback_efficiency: float = 0.6
var staffed_efficiency: float = 0.9
var skilled_efficiency: float = 1.0
var expert_efficiency: float = 1.1

var diminishing_returns: Dictionary = {
	"armor": 0.7,
	"speed": 0.8,
	"ecm": 0.6
}

var retrofit_hardpoint_caps: Dictionary = {
	"total": 2,
	"per_class": 1
}

var turn_inertia_factor: float = 0.5		# TODO: DEBUG: 1.0

var _current_stats: Dictionary = {}


func setup(db_ref: ComponentDB, hull_data: Dictionary, ship_db_ref: ShipTypeDB = null) -> void:
	db = db_ref
	ship_db = ship_db_ref
	hull = hull_data.duplicate(true)
	installed.clear()
	_current_stats.clear()

	if db != null and not db.defaults.is_empty():
		if db.defaults.has("ai_fallback_efficiency"):
			ai_fallback_efficiency = float(db.defaults["ai_fallback_efficiency"])
		if db.defaults.has("staffed_efficiency"):
			staffed_efficiency = float(db.defaults["staffed_efficiency"])
		if db.defaults.has("skilled_efficiency"):
			skilled_efficiency = float(db.defaults["skilled_efficiency"])
		if db.defaults.has("expert_efficiency"):
			expert_efficiency = float(db.defaults["expert_efficiency"])
		if db.defaults.has("diminishing_returns"):
			diminishing_returns = db.defaults["diminishing_returns"]
		if db.defaults.has("retrofit_hardpoint_caps"):
			retrofit_hardpoint_caps = db.defaults["retrofit_hardpoint_caps"]
		if db.defaults.has("turn_inertia_factor"):
			turn_inertia_factor = float(db.defaults["turn_inertia_factor"])


func init_from_ship_type(ship_type_id: String, db_ref: ComponentDB = null, ship_db_ref: ShipTypeDB = null) -> bool:
	# Initialize the ship from a ship type definition.
	# Loads hull data and installs stock components.
	# Returns true on success, false on failure.
	
	if db_ref != null:
		db = db_ref
	if ship_db_ref != null:
		ship_db = ship_db_ref
	
	# Auto-get references if not provided and autoloads exist
	if db == null and has_node("/root/ComponentDB"):
		db = get_node("/root/ComponentDB")
	if ship_db == null and has_node("/root/ShipTypeDB"):
		ship_db = get_node("/root/ShipTypeDB")
	
	if db == null:
		push_error("ShipComponentSystem.init_from_ship_type: ComponentDB not available")
		return false
	
	if ship_db == null:
		push_error("ShipComponentSystem.init_from_ship_type: ShipTypeDB not available")
		return false
	
	var ship_def:Dictionary = ship_db.get_ship_def(ship_type_id)
	if ship_def.is_empty():
		push_error("ShipComponentSystem.init_from_ship_type: unknown ship type '%s'" % ship_type_id)
		return false
	
	# Setup with hull data
	setup(db, ship_def, ship_db)
	
	# Install stock components
	if ship_def.has("stock_components") and typeof(ship_def["stock_components"]) == TYPE_ARRAY:
		var stock_comps: Array = ship_def["stock_components"]
		print("ShipComponentSystem: Installing %d stock components for %s" % [stock_comps.size(), ship_type_id])
		
		for comp_id in stock_comps:
			var id_str := str(comp_id)
			if not install(id_str):
				push_warning("ShipComponentSystem: Failed to install stock component '%s' on ship '%s'" % [id_str, ship_type_id])
	
	print("ShipComponentSystem: Initialized ship '%s' (%s)" % [ship_def.get("name", "Unknown"), ship_type_id])
	return true


# -------------------------------------------------------------------
# Installation / removal / toggles
# -------------------------------------------------------------------

func install(id_in: String) -> bool:
	if db == null:
		push_warning("ShipComponentSystem.install: db is null")
		return false

	var def:Dictionary = db.get_def(id_in)
	if def.is_empty():
		push_warning("ShipComponentSystem.install: unknown component '%s'" % id_in)
		return false

	# Component space check
	var space_needed := int(def.get("space_cost", 0))
	if get_component_space_free() < space_needed:
		push_warning("ShipComponentSystem.install: not enough component space")
		return false

	# Hardpoint check (for weapons)
	var ctype := str(def.get("type", ""))
	if ctype == "weapon":
		var size := str(def.get("hardpoint_size", "light"))
		var slot_cost := int(def.get("slot_cost", 1))
		if get_hardpoints_free(size) < slot_cost:
			push_warning("ShipComponentSystem.install: not enough %s hardpoints" % size)
			return false

	# Initial condition HP from damage block
	var max_hp := 100
	if def.has("damage") and typeof(def["damage"]) == TYPE_DICTIONARY:
		max_hp = int(def["damage"].get("condition_hp_max", 100))

	var entry: Dictionary = {
		"id": str(def["id"]),     # assumed canonical
		"state": "operational",   # "operational" | "offline" | "damaged" | ...
		"throttle": 100,          # percent
		"priority": 2,            # 1 = high, 2 = normal, 3 = low (shed first)
		"condition_hp": max_hp
	}
	installed.append(entry)
	_recompute()
	return true


func remove(id_in: String) -> bool:
	var idx := _find_first_by_id(id_in)
	if idx == -1:
		return false
	installed.remove_at(idx)
	_recompute()
	return true


func toggle(id_in: String, on: bool) -> bool:
	var idx := _find_first_by_id(id_in)
	if idx == -1:
		return false

	if on:
		installed[idx]["state"] = "operational"
	else:
		installed[idx]["state"] = "offline"

	_recompute()
	return true


func set_throttle(id_in: String, pct: int) -> bool:
	var idx := _find_first_by_id(id_in)
	if idx == -1:
		return false
	installed[idx]["throttle"] = clamp(pct, 0, 100)
	_recompute()
	return true


func set_priority(id_in: String, level: int) -> bool:
	var idx := _find_first_by_id(id_in)
	if idx == -1:
		return false
	installed[idx]["priority"] = clamp(level, 1, 3)
	_recompute()
	return true


func get_current_stats() -> Dictionary:
	return _current_stats.duplicate(true)


func get_installed_components() -> Array:
	# Returns array of installed component entries with their runtime state
	return installed.duplicate(true)


func get_installed_component_ids() -> Array:
	# Returns just the component IDs
	var result: Array = []
	for e in installed:
		result.append(str(e["id"]))
	return result


func get_components_by_type(type: String) -> Array:
	# Returns installed components of a specific type
	var result: Array = []
	for e in installed:
		var def:Dictionary = db.get_def(e["id"])
		if def.is_empty():
			continue
		if str(def.get("type", "")) == type:
			result.append(e.duplicate(true))
	return result


func get_component_count_by_type(type: String) -> int:
	# Returns count of installed components of a specific type
	var count := 0
	for e in installed:
		var def:Dictionary = db.get_def(e["id"])
		if def.is_empty():
			continue
		if str(def.get("type", "")) == type:
			count += 1
	return count


# -------------------------------------------------------------------
# Capacity / hardpoints
# -------------------------------------------------------------------

func get_component_space_free() -> int:
	var base_space := int(hull.get("component_space", 0))
	var used: int = 0
	var bonus_pct: float = 0.0

	for e in installed:
		var d:Dictionary = db.get_def(e["id"])
		if d.is_empty():
			continue
		used += int(d.get("space_cost", 0))
		bonus_pct += float(d.get("component_space_bonus_pct", 0.0))

	# Cap at +25% extended space
	if bonus_pct > 0.25:
		bonus_pct = 0.25

	var total := int(round(float(base_space) * (1.0 + bonus_pct)))
	var free_space := total - used
	if free_space < 0:
		free_space = 0
	return free_space


func get_hardpoints_free(size: String) -> int:
	var hp:Variant = hull.get("hardpoints", {})
	var base := 0
	if typeof(hp) == TYPE_DICTIONARY:
		base = int(hp.get(size, 0))

	# Additional hardpoints from utility components
	var added: int = 0
	for e in installed:
		var d:Dictionary = db.get_def(e["id"])
		if d.is_empty():
			continue
		if d.has("add_hardpoints") and typeof(d["add_hardpoints"]) == TYPE_DICTIONARY:
			var add_hp: Dictionary = d["add_hardpoints"]
			if add_hp.has(size):
				added += int(add_hp[size])

	var per_class_cap := int(retrofit_hardpoint_caps.get("per_class", 1))
	if added > per_class_cap:
		added = per_class_cap

	var total := base + added

	# Used hardpoints from weapons
	var used: int = 0
	for e in installed:
		var d2:Dictionary = db.get_def(e["id"])
		if d2.is_empty():
			continue
		if str(d2.get("type", "")) != "weapon":
			continue
		if str(d2.get("hardpoint_size", "")) != size:
			continue
		used += int(d2.get("slot_cost", 1))

	var free := total - used
	if free < 0:
		free = 0
	return free


# -------------------------------------------------------------------
# Internals
# -------------------------------------------------------------------

func _find_first_by_id(id_in: String) -> int:
	if db == null:
		return -1
	var canon:String = ComponentDB._canonicalize_id(id_in)
	for i in range(installed.size()):
		var eid:String = ComponentDB._canonicalize_id(str(installed[i]["id"]))
		if eid == canon:
			return i
	return -1


func _crew_efficiency_for(def: Dictionary) -> float:
	var req:Variant = def.get("requires_stations", {})
	if typeof(req) != TYPE_DICTIONARY or req.size() == 0:
		return 1.0

	var has_ai := bool(def.get("ai_core", false))
	var best := 1.0

	for station in req.keys():
		var info:Dictionary = crew_assignments.get(station, {})
		var staffed := bool(info.get("staffed", false))
		var skill := str(info.get("skill", "none"))

		var eff := ai_fallback_efficiency

		if staffed:
			if skill == "expert":
				eff = expert_efficiency
			elif skill == "skilled":
				eff = skilled_efficiency
			else:
				eff = staffed_efficiency
		else:
			if has_ai:
				eff = ai_fallback_efficiency
			else:
				eff = 0.3

		if eff < best:
			best = eff

	return best


func _recompute() -> void:
	var out: Dictionary = {}

	# Hull baselines
	var base_mass := float(hull.get("mass_base", 40.0))
	var base_component_space := int(hull.get("component_space", 0))
	var hardpoints:Dictionary = hull.get("hardpoints", {})

	var hull_points := int(hull.get("hull_points", 0))
	var shield_strength := int(hull.get("shield_strength", 0))
	var sensor_strength := float(hull.get("sensor_strength", 0.0))
	var cargo_capacity := int(hull.get("cargo_capacity", 0))
	var speed_rating := float(hull.get("speed_rating", 0.0))
	var maneuverability := float(hull.get("maneuverability", 5.0))  # Read maneuverability from hull
	var range_au := float(hull.get("range_au", 0.0))

	var signature := 0.0
	var heat_dissipation := 0.0
	var reliability := 1.0
	var crew_support := int(hull.get("crew_support", 0))
	var maintenance_load := 0.0

	var thrust := 0.0
	var torque := 0.0
	var net_power := 0.0
	var draw_power := 0.0

	var armor_stack_count := 0
	var speed_stack_count := 0
	var ecm_stack_count := 0

	var total_mass := base_mass

	# First pass: additive stats and simple stacking
	for e in installed:
		var def:Dictionary= db.get_def(e["id"])
		if def.is_empty():
			continue

		var state := str(e.get("state", "operational"))
		var throttle := float(e.get("throttle", 100)) / 100.0
		if state != "operational":
			throttle = 0.0

		var eff := _crew_efficiency_for(def)

		var health_mult := 1.0
		if def.has("damage") and typeof(def["damage"]) == TYPE_DICTIONARY:
			var dmg:Dictionary = def["damage"]
			var max_hp:int = int(dmg.get("condition_hp_max", 100))
			var cur_hp:int = int(e.get("condition_hp", max_hp))
			if max_hp > 0:
				health_mult = float(cur_hp) / float(max_hp)
				if health_mult < 0.0:
					health_mult = 0.0
				if health_mult > 1.0:
					health_mult = 1.0

		var mult := eff * health_mult * throttle

		net_power += float(def.get("power_output", 0.0)) * mult
		draw_power += float(def.get("power_draw", 0.0)) * mult

		hull_points += int(float(def.get("hull_points_bonus", 0)) * mult)
		shield_strength += int(float(def.get("shield_hp_bonus", 0)) * mult)
		sensor_strength += float(def.get("sensor_strength_bonus", 0.0)) * mult
		cargo_capacity += int(float(def.get("cargo_bonus", 0)) * mult)
		crew_support += int(float(def.get("crew_support", 0)) * mult)
		maintenance_load += float(def.get("maintenance_load", 0.0)) * mult

		signature += float(def.get("signature_flat", 0.0)) * mult
		heat_dissipation += float(def.get("heat_dissipation_bonus", 0.0)) * mult

		reliability *= pow(float(def.get("reliability", 1.0)), mult)

		thrust += float(def.get("thrust", 0.0)) * mult
		torque += float(def.get("turning_torque", 0.0)) * mult

		var speed_bonus := float(def.get("speed_bonus", 0.0))
		if speed_bonus != 0.0:
			var speed_mult := 1.0
			if speed_stack_count > 0:
				speed_mult = diminishing_returns.get("speed", 0.8)
			speed_rating += speed_bonus * mult * speed_mult
			speed_stack_count += 1

		var ctype := str(def.get("type", ""))

		if ctype == "armor":
			armor_stack_count += 1
			if armor_stack_count > 1:
				var dr_armor:float = diminishing_returns.get("armor", 0.7)
				hull_points += int(float(def.get("hull_points_bonus", 0)) * mult * pow(dr_armor, float(armor_stack_count - 1)))

		if ctype == "ecm":
			ecm_stack_count += 1

		total_mass += float(def.get("mass", 0.0))

	# ECM diminishing returns: reduce net signature impact by a multiplier
	if ecm_stack_count > 1:
		var dr_ecm:float = diminishing_returns.get("ecm", 0.6)
		signature *= pow(dr_ecm, float(ecm_stack_count - 1))

	# Second pass: multiplicative signature modifiers (signature_mult)
	for e2 in installed:
		var def2:Dictionary = db.get_def(e2["id"])
		if def2.is_empty():
			continue

		var state2 := str(e2.get("state", "operational"))
		var throttle2 := float(e2.get("throttle", 100)) / 100.0
		if state2 != "operational":
			throttle2 = 0.0

		var eff2 := _crew_efficiency_for(def2)
		var health_mult2 := 1.0
		if def2.has("damage") and typeof(def2["damage"]) == TYPE_DICTIONARY:
			var dmg2:Dictionary = def2["damage"]
			var max_hp2:int = int(dmg2.get("condition_hp_max", 100))
			var cur_hp2:int = int(e2.get("condition_hp", max_hp2))
			if max_hp2 > 0:
				health_mult2 = float(cur_hp2) / float(max_hp2)
				if health_mult2 < 0.0:
					health_mult2 = 0.0
				if health_mult2 > 1.0:
					health_mult2 = 1.0

		var mult2 := eff2 * health_mult2 * throttle2
		var sig_mult := float(def2.get("signature_mult", 1.0))
		if sig_mult != 1.0:
			signature *= pow(sig_mult, mult2)

	# Power margin and (simple) priority-based shedding
	var power_margin := net_power - draw_power

	if power_margin < 0.0:
		var changed := true
		while power_margin < 0.0 and changed:
			changed = false
			var best_idx := -1
			var best_pri := -1
			var best_draw := 0.0

			for i in range(installed.size()):
				var e3 := installed[i]
				var state3 := str(e3.get("state", "operational"))
				if state3 != "operational":
					continue

				var d3:Dictionary = db.get_def(e3["id"])
				if d3.is_empty():
					continue

				var pri := int(e3.get("priority", 2))
				var draw := float(d3.get("power_draw", 0.0)) * (float(e3.get("throttle", 100)) / 100.0)
				if draw <= 0.0:
					continue

				# Shed lowest priority first (3 > 2 > 1).
				if pri > best_pri:
					best_pri = pri
					best_idx = i
					best_draw = draw

			if best_idx != -1:
				installed[best_idx]["state"] = "offline"
				power_margin += best_draw
				changed = true

	# Derived motion stats
	var acceleration := 0.0
	if total_mass > 0.0:
		acceleration = thrust / total_mass

	var turn_rate := 0.0
	var inertia := turn_inertia_factor
	if inertia <= 0.0:
		inertia = 1.0
	if total_mass > 0.0:
		turn_rate = torque / (total_mass * inertia)
		# Apply maneuverability multiplier (normalized around 5.0)
		turn_rate *= (maneuverability / 5.0)
		# Safety clamp - ensure minimum playability
		if turn_rate < 0.4:
			turn_rate = 0.4

	# Signature / stealth
	if signature < 1.0:
		signature = 1.0
	var stealth_rating := int(round(1000.0 / signature))

	# Populate output dictionary
	out["mass_total"] = total_mass
	out["component_space_base"] = base_component_space
	out["component_space_free"] = get_component_space_free()
	out["hardpoints_base"] = hardpoints
	out["hardpoints_free"] = {
		"light": get_hardpoints_free("light"),
		"medium": get_hardpoints_free("medium"),
		"heavy": get_hardpoints_free("heavy"),
		"turret": get_hardpoints_free("turret")
	}

	out["hull_points"] = hull_points
	out["shield_strength"] = shield_strength
	out["sensor_strength"] = sensor_strength
	out["cargo_capacity"] = cargo_capacity
	out["speed_rating"] = speed_rating
	out["range_au"] = range_au

	out["signature"] = signature
	out["stealth_rating"] = stealth_rating
	out["heat_dissipation"] = heat_dissipation
	out["reliability"] = reliability
	out["crew_support"] = crew_support
	out["maintenance_load"] = maintenance_load

	out["thrust"] = thrust
	out["torque"] = torque
	out["acceleration"] = acceleration
	out["turn_rate"] = turn_rate

	out["net_power"] = net_power
	out["power_draw"] = draw_power
	out["power_margin"] = power_margin

	_current_stats = out
