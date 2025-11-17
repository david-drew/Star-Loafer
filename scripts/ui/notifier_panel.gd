extends Control

@onready var notices_vbox: VBoxContainer = $NoticesVBox

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


func _on_hail_received(initiator: Node, recipient: Node, context: Dictionary) -> void:
	# Player must be the recipient
	var recipient_type:String = context.get("recipient_type", "unknown")
	if recipient_type != "player":
		return

	var conversation_id:int = context.get("conversation_id", -1)
	if conversation_id == -1:
		return

	_create_hail_notice(conversation_id, initiator, context)


func _create_hail_notice(conversation_id: int, sender: Node, context: Dictionary) -> void:
	# Prevent duplicate notices
	if active_notices.has(conversation_id):
		return

	var notice := HBoxContainer.new()
	notice.name = "HailNotice_%d" % conversation_id

	# Icon / label
	var label := Label.new()
	label.text = "Incoming hail from: %s" % sender.name
	notice.add_child(label)

	notice.add_spacer(false)

	# OPEN button
	var btn_open := Button.new()
	btn_open.text = "Open Comms"
	btn_open.pressed.connect(_on_open_pressed.bind(conversation_id))
	notice.add_child(btn_open)

	# IGNORE button
	var btn_ignore := Button.new()
	btn_ignore.text = "Ignore"
	btn_ignore.pressed.connect(_on_ignore_pressed.bind(conversation_id))
	notice.add_child(btn_ignore)

	notices_vbox.add_child(notice)
	active_notices[conversation_id] = notice


func _on_open_pressed(conversation_id: int) -> void:
	# opening comms will cause CommPanel to display next message
	# we just remove the notice
	_remove_notice(conversation_id)

	# CommPanel shows next message automatically because CommSystem emits
	# comm_message_received for the greeting.

	# (Optionally we can "ping" CommSystem to re-emit most recent message,
	# but for now it is not necessary.)


func _on_ignore_pressed(conversation_id: int) -> void:
	_remove_notice(conversation_id)
	# We do NOT auto-send a comm_response here.
	# CommSystem may add ignore consequences later.


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
