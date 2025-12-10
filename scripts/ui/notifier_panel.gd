extends Control

@onready var notices_vbox: VBoxContainer = $NoticesVBox
@onready var notice_template: HBoxContainer = $NoticeTemplate if has_node("NoticeTemplate") else null  # Prebuilt row; must exist in scene

# Track notices by conversation id, so we can remove or update them.
var active_notices := {}   # conversation_id -> HBoxContainer (or Notice node)

func _ready() -> void:
	visible = true

	# listen for incoming hails
	if not EventBus.hail_received.is_connected(_on_hail_received):
		EventBus.hail_received.connect(_on_hail_received)

	# listen for new comm messages (conversation opened / continued)
	if not EventBus.comm_message_received.is_connected(_on_comm_message_received):
		EventBus.comm_message_received.connect(_on_comm_message_received)
	if not EventBus.comm_hail_timed_out.is_connected(_on_hail_timed_out):
		EventBus.comm_hail_timed_out.connect(_on_hail_timed_out)
	if not EventBus.comm_session_started.is_connected(_on_session_started):
		EventBus.comm_session_started.connect(_on_session_started)
	if not EventBus.comm_session_ended.is_connected(_on_session_ended):
		EventBus.comm_session_ended.connect(_on_session_ended)


func _on_hail_received(initiator: Node, recipient: Node, context: Dictionary) -> void:
	# Player must be the recipient
	var recipient_type:String = context.get("recipient_type", "unknown")
	if recipient_type != "player":
		return

	var conversation_id:int = context.get("conversation_id", -1)
	if conversation_id == -1:
		return

	# DEBUG: hail popup creation
	print("[COMM DEBUG] notifier: creating hail notice conv=%d from=%s" % [conversation_id, initiator.name])
	_create_hail_notice(conversation_id, initiator, context)


func _create_hail_notice(conversation_id: int, sender: Node, context: Dictionary) -> void:
	# Prevent duplicate notices
	if active_notices.has(conversation_id):
		return
	if notice_template == null:
		# Fallback: build a simple row if the template is missing (remove when template restored) # DEBUG
		var fallback := HBoxContainer.new()
		fallback.name = "HailNotice_%d" % conversation_id
		var lbl := Label.new()
		lbl.name = "Label"
		lbl.text = "Incoming hail from: %s" % sender.name
		fallback.add_child(lbl)
		fallback.add_spacer(false)
		var btn_o := Button.new()
		btn_o.name = "OpenButton"
		btn_o.text = "Open Comms"
		btn_o.pressed.connect(_on_open_pressed.bind(conversation_id))
		fallback.add_child(btn_o)
		var btn_i := Button.new()
		btn_i.name = "IgnoreButton"
		btn_i.text = "Ignore"
		btn_i.pressed.connect(_on_ignore_pressed.bind(conversation_id))
		fallback.add_child(btn_i)
		notices_vbox.add_child(fallback)
		active_notices[conversation_id] = fallback
		return
	var notice: HBoxContainer = notice_template.duplicate()
	notice.visible = true
	notice.name = "HailNotice_%d" % conversation_id

	var label: Label = notice.get_node("Label")
	label.text = "Incoming hail from: %s" % sender.name

	var btn_open: Button = notice.get_node("OpenButton")
	btn_open.pressed.connect(_on_open_pressed.bind(conversation_id))

	var btn_ignore: Button = notice.get_node("IgnoreButton")
	btn_ignore.pressed.connect(_on_ignore_pressed.bind(conversation_id))

	notices_vbox.add_child(notice)
	active_notices[conversation_id] = notice


func _on_open_pressed(conversation_id: int) -> void:
	# opening comms will cause CommPanel to display next message
	# we just remove the notice
	_remove_notice(conversation_id)

	# Ensure CommSystem processes the acceptance directly (in addition to event) # DEBUG
	var comm_system = get_node_or_null("/root/GameRoot/Systems/CommSystem")
	if comm_system and comm_system.has_method("accept_hail"):
		comm_system.accept_hail(conversation_id)

	EventBus.comm_hail_accepted.emit(conversation_id, {"conversation_id": conversation_id})

	# CommPanel shows next message automatically because CommSystem emits
	# comm_message_received for the greeting.

	# (Optionally we can "ping" CommSystem to re-emit most recent message,
	# but for now it is not necessary.)


func _on_ignore_pressed(conversation_id: int) -> void:
	_remove_notice(conversation_id)
	EventBus.comm_hail_ignored.emit(conversation_id, {"conversation_id": conversation_id}, "player_dismissed")


func _remove_notice(conversation_id: int) -> void:
	if not active_notices.has(conversation_id):
		return

	var notice:HBoxContainer  = active_notices[conversation_id]
	notice.queue_free()
	active_notices.erase(conversation_id)


# If a new comm message arrives from the same conversation,
# we remove the hail notice since the player has engaged with it.
func _on_comm_message_received(message_data: Dictionary) -> void:
	var conversation_id:int = message_data.get("conversation_id", -1)
	if conversation_id == -1:
		return

	_remove_notice(conversation_id)


func _on_hail_timed_out(conversation_id, _context: Dictionary) -> void:
	_remove_notice(int(conversation_id))


func _on_session_started(conversation_id, _context: Dictionary) -> void:
	_remove_notice(int(conversation_id))


func _on_session_ended(conversation_id, _reason: String) -> void:
	_remove_notice(int(conversation_id))
