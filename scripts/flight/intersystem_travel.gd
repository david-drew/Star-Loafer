extends Node2D

@onready var progress_bar = $UI/TravelHUD/ProgressBar
@onready var eta_label = $UI/TravelHUD/ETALabel
@onready var autopilot_button = $UI/TravelHUD/AutopilotButton

var travel_duration: float = 0.0
var elapsed_time: float = 0.0
var autopilot_enabled: bool = false
var time_compression: int = 1

func _ready() -> void:
	autopilot_button.pressed.connect(_on_autopilot_toggle)
	
	# Calculate travel time
	var from_system = GameState.transit_from
	var to_system = GameState.transit_to
	var distance = _get_route_distance(from_system, to_system)
	travel_duration = 5.0 + (distance * 15.0)  # 5-20 minutes (in seconds for testing)
	
	print("Inter-system travel: %s → %s (%.1f units, %.1f sec)" % [from_system, to_system, distance, travel_duration])

func _process(delta: float) -> void:
	var effective_delta = delta * time_compression
	elapsed_time += effective_delta
	
	progress_bar.value = (elapsed_time / travel_duration) * 100
	var remaining = travel_duration - elapsed_time
	eta_label.text = "ETA: %.0f sec" % remaining
	
	if elapsed_time >= travel_duration:
		_complete_travel()

func _on_autopilot_toggle() -> void:
	autopilot_enabled = !autopilot_enabled
	
	if autopilot_enabled:
		time_compression = 4
		autopilot_button.text = "Autopilot: ON (4x)"
	else:
		time_compression = 1
		autopilot_button.text = "Autopilot: OFF"
	
	EventBus.autopilot_toggled.emit(autopilot_enabled)
	EventBus.time_compression_changed.emit(time_compression)

func _complete_travel() -> void:
	GameState.current_system_id = GameState.transit_to
	GameState.mark_discovered("galaxy", GameState.transit_to)
	GameState.in_transit = false
	
	EventBus.travel_completed.emit()
	
	# Load SystemExploration at new system
	SceneManager.transition_to_mode("res://scenes/modes/SystemExploration.tscn")

func _get_route_distance(from_id: String, to_id: String) -> float:
	for route in GameState.galaxy_data["routes"]:
		if (route["a"] == from_id and route["b"] == to_id) or \
		   (route["b"] == from_id and route["a"] == to_id):
			return route["dist"]
	return 0.1  # Fallback
