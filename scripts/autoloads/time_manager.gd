# TimeManager.gd

# Autoload singleton responsible for global game time, calendar, and sim ticks.
# Uses res://config/time_scale.json for configuration.
# Emits time-related signals via EventBus (another autoload).

extends Node
#class_name TimeManager

const CONFIG_PATH: String = "res://data/sim/time_scale.json"

# -------------------------------------------------------------------
# Config-backed constants (initialized from JSON or defaults)
# -------------------------------------------------------------------

var HOURS_PER_DAY: int = 24
var DAYS_PER_YEAR: int = 360

var BASE_HOURS_PER_REAL_SECOND: float = 0.02
var SIM_TICK_INTERVAL_HOURS: float = 6.0

var _mode_scales: Dictionary = {
	"FLIGHT": 1.0,
	"AWAY_TEAM": 0.1,
	"DIALOGUE": 0.0,
	"COMBAT": 0.05,
	"TRAVEL": 2.0,
	"PAUSED": 0.0,
}

# -------------------------------------------------------------------
# Runtime state
# -------------------------------------------------------------------
var game_tick:int = 0		# May be unnecessary duplicate, see EconManager spec
var game_hours_since_start: float = 0.0
var hours_since_last_tick: float = 0.0
var current_mode: String = "FLIGHT"

# Optional stack of temporary time modifiers.
# Maps id -> multiplier (float).
var _time_modifiers: Dictionary = {}
var _last_total_days: int = 0			# Cached day count to detect day changes.
var _config_loaded: bool = false

# -------------------------------------------------------------------
# Lifecycle
# -------------------------------------------------------------------

func _ready() -> void:
	_load_config()
	_last_total_days = _get_total_days()
	set_process(true)


func _process(delta: float) -> void:
	# No time advancement if fully paused.
	var scale := _get_effective_scale()
	if scale == 0.0:
		return

	var hours_delta := delta * BASE_HOURS_PER_REAL_SECOND * scale
	if hours_delta <= 0.0:
		return

	# Advance absolute time.
	game_hours_since_start += hours_delta
	hours_since_last_tick += hours_delta

	# Emit sim ticks if enough time has accumulated.
	if hours_since_last_tick >= SIM_TICK_INTERVAL_HOURS:
		var ticks := int(floor(hours_since_last_tick / SIM_TICK_INTERVAL_HOURS))
		if ticks > 0:
			game_tick += ticks
			var hours_for_ticks: float = float(ticks) * SIM_TICK_INTERVAL_HOURS
			EconomyManager.on_game_tick(game_tick)
			_emit_sim_tick(hours_for_ticks, ticks)
			hours_since_last_tick -= hours_for_ticks

	# Detect day change.
	_check_day_changed()

# -------------------------------------------------------------------
# Config loading
# -------------------------------------------------------------------

func _load_config() -> void:
	_config_loaded = false

	if not FileAccess.file_exists(CONFIG_PATH):
		push_warning("TimeManager: Config file not found at %s, using defaults." % CONFIG_PATH)
		_config_loaded = true
		return

	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("TimeManager: Failed to open config file at %s, using defaults." % CONFIG_PATH)
		_config_loaded = true
		return

	var text := file.get_as_text()
	file.close()

	var data:Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("TimeManager: Failed to parse JSON config, using defaults.")
		_config_loaded = true
		return

	var dict: Dictionary = data

	if dict.has("time_constants"):
		var tc: Dictionary = dict["time_constants"]
		if tc.has("HOURS_PER_DAY"):
			HOURS_PER_DAY = int(tc["HOURS_PER_DAY"])
		if tc.has("DAYS_PER_YEAR"):
			DAYS_PER_YEAR = int(tc["DAYS_PER_YEAR"])

	if dict.has("base_speed"):
		var bs: Dictionary = dict["base_speed"]
		if bs.has("BASE_HOURS_PER_REAL_SECOND"):
			BASE_HOURS_PER_REAL_SECOND = float(bs["BASE_HOURS_PER_REAL_SECOND"])

	if dict.has("tick_settings"):
		var ts: Dictionary = dict["tick_settings"]
		if ts.has("SIM_TICK_INTERVAL_HOURS"):
			SIM_TICK_INTERVAL_HOURS = float(ts["SIM_TICK_INTERVAL_HOURS"])

	if dict.has("mode_scales"):
		var ms: Dictionary = dict["mode_scales"]
		# Merge into defaults so missing keys are okay.
		for key in ms.keys():
			_mode_scales[str(key)] = float(ms[key])

	_config_loaded = true

# -------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------

func get_game_hours() -> float:
	return game_hours_since_start


func get_mode() -> String:
	return current_mode


func set_mode(mode: String) -> void:
	if not _mode_scales.has(mode):
		push_warning("TimeManager: set_mode called with unknown mode '%s'." % mode)
		return

	if current_mode == mode:
		return

	var old_mode := current_mode
	current_mode = mode
	_emit_mode_changed(old_mode, current_mode)


func push_time_modifier(id: String, multiplier: float) -> void:
	if multiplier <= 0.0:
		push_warning("TimeManager: push_time_modifier called with non-positive multiplier.")
		return
	_time_modifiers[id] = multiplier


func pop_time_modifier(id: String) -> void:
	if _time_modifiers.has(id):
		_time_modifiers.erase(id)


func get_effective_scale() -> float:
	return _get_effective_scale()


func advance_time_hours(jump_hours: float, source: String = "") -> void:
	if jump_hours <= 0.0:
		return

	game_hours_since_start += jump_hours
	hours_since_last_tick += jump_hours

	# Emit batched sim tick(s) if necessary.
	if hours_since_last_tick >= SIM_TICK_INTERVAL_HOURS:
		var ticks := int(floor(hours_since_last_tick / SIM_TICK_INTERVAL_HOURS))
		if ticks > 0:
			var hours_for_ticks: float = float(ticks) * SIM_TICK_INTERVAL_HOURS
			_emit_sim_tick(hours_for_ticks, ticks)
			hours_since_last_tick -= hours_for_ticks

	# Notify listeners that a big jump occurred.
	_emit_big_jump(jump_hours, source)

	# Day change may have occurred.
	_check_day_changed()


func get_calendar_time() -> Dictionary:
	# Returns a dictionary with:
	# year, day_of_year (1-based), hour, minute, total_days, total_hours
	var total_hours: float = game_hours_since_start
	var total_days_exact: float = total_hours / float(HOURS_PER_DAY)
	var total_days: int = int(floor(total_days_exact))

	var year: int = total_days / DAYS_PER_YEAR
	var day_of_year_zero_based: int = total_days % DAYS_PER_YEAR
	var day_of_year: int = day_of_year_zero_based + 1

	var hour_float: float = total_hours - float(total_days) * float(HOURS_PER_DAY)
	var hour: int = int(floor(hour_float))
	var minute_float: float = (hour_float - float(hour)) * 60.0
	var minute: int = int(floor(minute_float))

	return {
		"year": year,
		"day_of_year": day_of_year,
		"hour": hour,
		"minute": minute,
		"total_days": total_days,
		"total_hours": total_hours,
	}


func format_calendar_time() -> String:
	var ct := get_calendar_time()
	var year: int = ct["year"]
	var day_of_year: int = ct["day_of_year"]
	var hour: int = ct["hour"]
	var minute: int = ct["minute"]

	# Year 12, Day 182, 16:05
	return "Year %d, Day %d, %02d:%02d" % [year, day_of_year, hour, minute]


func hours_until(target_hours: float) -> float:
	return target_hours - game_hours_since_start


func is_past(target_hours: float) -> bool:
	return game_hours_since_start >= target_hours


func serialize_state() -> Dictionary:
	# For SaveSystem: capture minimal state.
	return {
		"game_hours_since_start": game_hours_since_start,
		"hours_since_last_tick": hours_since_last_tick,
		"current_mode": current_mode,
		"time_modifiers": _time_modifiers.duplicate(true),
		"last_total_days": _last_total_days,
	}


func restore_state(state: Dictionary) -> void:
	if state.has("game_hours_since_start"):
		game_hours_since_start = float(state["game_hours_since_start"])
	if state.has("hours_since_last_tick"):
		hours_since_last_tick = float(state["hours_since_last_tick"])
	if state.has("current_mode"):
		current_mode = String(state["current_mode"])
	if state.has("time_modifiers"):
		_time_modifiers = state["time_modifiers"].duplicate(true)
	if state.has("last_total_days"):
		_last_total_days = int(state["last_total_days"])

# -------------------------------------------------------------------
# Internal helpers
# -------------------------------------------------------------------

func _get_effective_scale() -> float:
	var mode_scale: float = 1.0
	if _mode_scales.has(current_mode):
		mode_scale = float(_mode_scales[current_mode])

	var modifier_product: float = 1.0
	for id in _time_modifiers.keys():
		var m: float = float(_time_modifiers[id])
		modifier_product *= m

	return mode_scale * modifier_product


func _get_total_days() -> int:
	var total_hours: float = game_hours_since_start
	var total_days_exact: float = total_hours / float(HOURS_PER_DAY)
	return int(floor(total_days_exact))


func _check_day_changed() -> void:
	var total_days := _get_total_days()
	if total_days != _last_total_days:
		_last_total_days = total_days
		var ct := get_calendar_time()
		var year: int = ct["year"]
		var day_of_year: int = ct["day_of_year"]
		_emit_day_changed(year, day_of_year)


# -------------------------------------------------------------------
# EventBus integration
# -------------------------------------------------------------------
# This assumes there is an EventBus autoload with these signals defined:
#   signal time_sim_tick(hours_elapsed: float, ticks: int)
#   signal time_big_jump(jump_hours: float, source: String)
#   signal time_mode_changed(old_mode: String, new_mode: String)
#   signal time_day_changed(year: int, day_of_year: int)

func _emit_sim_tick(hours_elapsed: float, ticks: int) -> void:
	if Engine.has_singleton("EventBus"):
		# This path is for native singletons; usually EventBus is a script autoload.
		pass
	# For typical script autoload:
	if typeof(EventBus) == TYPE_OBJECT:
		if EventBus.has_signal("time_sim_tick"):
			EventBus.emit_signal("time_sim_tick", hours_elapsed, ticks)
		else:
			# Fallback: generic emit if you have a custom API.
			# EventBus.emit("time_sim_tick", {"hours_elapsed": hours_elapsed, "ticks": ticks})
			pass
	else:
		push_warning("TimeManager: EventBus not found or not an Object when emitting time_sim_tick.")


func _emit_big_jump(jump_hours: float, source: String) -> void:
	if typeof(EventBus) == TYPE_OBJECT:
		if EventBus.has_signal("time_big_jump"):
			EventBus.emit_signal("time_big_jump", jump_hours, source)
			game_tick += int(jump_hours / SIM_TICK_INTERVAL_HOURS) 
			EconomyManager.on_game_tick(game_tick)
		else:
			pass
	else:
		push_warning("TimeManager: EventBus not found or not an Object when emitting time_big_jump.")


func _emit_mode_changed(old_mode: String, new_mode: String) -> void:
	if typeof(EventBus) == TYPE_OBJECT:
		if EventBus.has_signal("time_mode_changed"):
			EventBus.emit_signal("time_mode_changed", old_mode, new_mode)
		else:
			pass
	else:
		push_warning("TimeManager: EventBus not found or not an Object when emitting time_mode_changed.")


func _emit_day_changed(year: int, day_of_year: int) -> void:
	if typeof(EventBus) == TYPE_OBJECT:
		if EventBus.has_signal("time_day_changed"):
			EventBus.emit_signal("time_day_changed", year, day_of_year)
		else:
			pass
	else:
		push_warning("TimeManager: EventBus not found or not an Object when emitting time_day_changed.")
