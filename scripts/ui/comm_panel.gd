extends Control

var current_message: Dictionary = {}
var current_conversation_id = -1

@onready var panel: Panel = $Panel
@onready var from_label: Label = $Panel/VBox/HeaderBar/FromLabel
@onready var channel_label: Label = $Panel/VBox/HeaderBar/ChannelLabel
@onready var close_button: Button = $Panel/VBox/HeaderBar/CloseButton
@onready var message_text: RichTextLabel = $Panel/VBox/MessageText
@onready var responses_container: VBoxContainer = $Panel/VBox/ResponsesContainer
@onready var debug_label: Label = $Panel/VBox/DebugLabel


func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close_pressed)

	EventBus.comm_message_received.connect(_on_comm_message_received)


func _on_comm_message_received(message_data: Dictionary) -> void:
	print("\t....................COMM: MSG Received..............")
	current_message = message_data
	current_conversation_id = message_data.get("conversation_id", -1)

	# DEBUG: log incoming message
	print("[COMM DEBUG] comm_panel: message type=%s template=%s conv=%s" % [
		message_data.get("message_type", ""),
		message_data.get("template_id", ""),
		str(current_conversation_id)
	])

	# Update header
	var from_name: String = message_data.get("from_label", "Unknown")
	var channel: String = message_data.get("channel", "hail")

	from_label.text = from_name
	channel_label.text = "(" + channel + ")"

	# Update body text
	message_text.text = message_data.get("text", "...")

	# Debug info (optional)
	var msg_type: String = message_data.get("message_type", "")
	var template_id: String = message_data.get("template_id", "")
	debug_label.text = "Type: %s  Template: %s  Conv: %s" % [
		msg_type,
		template_id,
		str(current_conversation_id)
	]

	# Build response buttons
	_rebuild_responses()

	# Show the panel
	visible = true


func _rebuild_responses() -> void:
	for child in responses_container.get_children():
		child.queue_free()

	_add_trade_actions()

	var options: Array = current_message.get("response_options", [])
	if options.is_empty():
		return

	var index: int = 0
	for opt in options:
		if typeof(opt) != TYPE_DICTIONARY:
			continue

		var btn := Button.new()
		btn.text = str(opt.get("text", "…"))
		btn.focus_mode = Control.FOCUS_ALL
		btn.pressed.connect(_on_response_pressed.bind(index, opt))
		responses_container.add_child(btn)
		index += 1


func _add_trade_actions() -> void:
	var trade_available: bool = current_message.get("trade_available", false)
	if not trade_available or current_conversation_id == -1:
		return

	var docking_manager = _get_docking_manager()
	var player_ship = _get_player_ship()
	var in_trade := false
	if docking_manager and player_ship:
		in_trade = docking_manager.is_in_trade_orbit(player_ship)

	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Trade"
	row.add_child(label)

	var btn := Button.new()
	btn.text = "Exit Orbit" if in_trade else "Enter Trade"
	if in_trade:
		btn.pressed.connect(_on_exit_trade_pressed)
	else:
		btn.pressed.connect(_on_enter_trade_pressed)
	row.add_child(btn)

	responses_container.add_child(row)


func _on_response_pressed(index: int, response: Dictionary) -> void:
	# Emit event so CommSystem (or others) can react
	EventBus.comm_response_chosen.emit(current_conversation_id, index, response)

	# Basic behavior: close if response wants to close, or if no follow-up is defined
	var should_close: bool = false
	if response.has("close_after") and bool(response["close_after"]):
		should_close = true
	elif not response.has("leads_to_category") and not response.has("leads_to_template_id"):
		# No follow-up, safe to close
		should_close = true

	if should_close:
		visible = false


func _on_close_pressed() -> void:
	visible = false


func _on_enter_trade_pressed() -> void:
	var comm_system = _get_comm_system()
	if comm_system:
		var started = comm_system.start_trade_mode(current_conversation_id)
		if started:
			_rebuild_responses()


func _on_exit_trade_pressed() -> void:
	var comm_system = _get_comm_system()
	if comm_system:
		comm_system.exit_trade_mode()
	visible = false


func _get_comm_system() -> Node:
	return get_node_or_null("/root/GameRoot/Systems/CommSystem")


func _get_docking_manager() -> Node:
	return get_node_or_null("/root/GameRoot/Systems/DockingManager")


func _get_player_ship() -> Node:
	return get_tree().get_first_node_in_group("player")
