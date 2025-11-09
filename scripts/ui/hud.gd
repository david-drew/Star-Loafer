extends Control

@onready var flight_widgets = $FlightMode
@onready var onfoot_widgets = $OnFootMode

func _ready() -> void:
	#EventBus.hud_mode_changed.connect(_on_mode_changed)
	set_mode("flight")  # default

func set_mode(mode: String) -> void:
	if mode == "flight":
		flight_widgets.visible = true
	elif mode == "onfoot":
		onfoot_widgets.visible = true
	else:
		print("[Error] HUD unable to determine current mode.")

func _on_mode_changed(mode: String) -> void:
	set_mode(mode)

func update_speed(speed: float) -> void:
	$FlightWidgets/SpeedIndicator.text = "%.1f m/s" % speed

func update_fuel(current: float, max_fuel: float) -> void:
	$FlightWidgets/FuelGauge.value = (current / max_fuel) * 100

func set_autopilot_status(enabled: bool, compression: int) -> void:
	$FlightWidgets/AutopilotStatus/AutopilotIcon.modulate = Color.GREEN if enabled else Color.GRAY
	if enabled and compression > 1:
		$FlightWidgets/AutopilotStatus/TimeCompressionLabel.text = "%dx" % compression
	else:
		$FlightWidgets/AutopilotStatus/TimeCompressionLabel.text = ""
