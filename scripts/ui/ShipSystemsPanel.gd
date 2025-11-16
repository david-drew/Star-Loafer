# res://scripts/ui/ShipSystemsPanel.gd
extends Control

var current_ship: Node = null
var current_stats: Dictionary = {}
var current_loadout: Array = []
var current_candidates: Array = []

var selected_component_id: String = ""
var selected_source: String = ""  # "installed" or "candidate"

var filter_category: String = "all"
var filter_show_offline_only: bool = false

@onready var ship_name_label: Label = $Frame/TopBar/ShipNameLabel
@onready var mode_context_label: Label = $Frame/TopBar/ModeContextLabel
@onready var close_button: Button = $Frame/TopBar/CloseButton

@onready var ship_summary_panel: Control = $Frame/MainContent/LeftColumn/ShipSummaryPanel
@onready var installed_list: VBoxContainer = $Frame/MainContent/CenterColumn/CenterVBox/InstalledHeader/InstalledListContainer/InstalledList
@onready var candidates_list: VBoxContainer = $Frame/MainContent/RightColumn/CandidatesPanel/CandidatesHeader/CandidatesListContainer/CandidatesList
@onready var detail_name_label: Label = $Frame/MainContent/RightColumn/DetailPanel/DetailNameLabel
@onready var detail_stats_container: VBoxContainer = $Frame/MainContent/RightColumn/DetailPanel/DetailStatsContainer
@onready var detail_description_label: Label = $Frame/MainContent/RightColumn/DetailPanel/DetailDescriptionLabel
@onready var detail_actions_container: VBoxContainer = $Frame/MainContent/RightColumn/DetailPanel/DetailActionsContainer

@onready var component_db: Node = get_node_or_null("/root/ComponentDB")
@onready var category_filter: OptionButton = $Frame/MainContent/LeftColumn/FilterPanel/VBoxContainer/CategoryFilter
@onready var offline_only_check: CheckBox =  $Frame/MainContent/LeftColumn/FilterPanel/VBoxContainer/OfflineOnlyCheck


func _ready() -> void:
	visible = false
	_setup_filters()

	close_button.pressed.connect(_on_close_pressed)
	
	EventBus.player_ship_registered.connect(_on_player_ship_registered)
	EventBus.ship_screen_toggled.connect(_on_ship_screen_toggled)
	EventBus.ship_stats_updated.connect(_on_ship_stats_updated)
	EventBus.ship_loadout_updated.connect(_on_ship_loadout_updated)
	EventBus.ship_component_candidates_updated.connect(_on_ship_component_candidates_updated)
	EventBus.ship_component_action_failed.connect(_on_ship_component_action_failed)


func _on_player_ship_registered(ship: Node) -> void:
	# First registered player ship becomes our current ship.
	if current_ship == null:
		current_ship = ship
		_update_ship_name()


func _on_ship_screen_toggled(ship: Node, should_open: bool) -> void:
	if ship != current_ship:
		return
	
	visible = should_open
	
	if visible:
		# Clear selection when opening
		selected_component_id = ""
		selected_source = ""
		_update_ship_name()
	else:
		# Optionally clear state on close
		pass


func _on_ship_stats_updated(ship: Node, stats: Dictionary) -> void:
	print("Panel Stats Update Running")
	if ship != current_ship:
		print("Stats Panel early exit")
		return
	
	current_stats = stats
	_update_ship_summary()
	_update_topbar_status()


func _on_ship_loadout_updated(ship: Node, loadout: Array) -> void:
	if ship != current_ship:
		return
	
	current_loadout = loadout
	_rebuild_installed_list()


func _on_ship_component_candidates_updated(ship: Node, candidates: Array) -> void:
	if ship != current_ship:
		return
	
	current_candidates = candidates
	_rebuild_candidates_list()


func _on_ship_component_action_failed(ship: Node, action: String, reason: String, data: Dictionary) -> void:
	if ship != current_ship:
		return
	
	var component_id: String = ""
	if data.has("component_id"):
		component_id = str(data["component_id"])
	
	var msg: String = "Component action failed: %s (%s)" % [action, reason]
	if component_id != "":
		msg = "Component %s: %s (%s)" % [component_id, action, reason]
	
	# Simple inline error. Replace with your toast/notification later.
	detail_description_label.text = msg


func _on_close_pressed() -> void:
	if current_ship != null:
		EventBus.ship_screen_toggled.emit(current_ship, false)


# --- UI updates -----------------------------------------------------

func _update_ship_name() -> void:
	if current_ship == null:
		ship_name_label.text = "No ship"
		return
	
	ship_name_label.text = current_ship.name


func _update_topbar_status() -> void:
	# For now, just show a simple context line from stats if available.
	# You can expand this to include hull/shield/power snapshots.
	var context_parts: Array = []
	if current_stats.has("hull_points"):
		context_parts.append("Hull: %d" % int(current_stats["hull_points"]))
	if current_stats.has("shield_strength"):
		context_parts.append("Shields: %d" % int(current_stats["shield_strength"]))
	if current_stats.has("power_margin"):
		context_parts.append("Power Δ: %d" % int(current_stats["power_margin"]))
	
	if context_parts.size() > 0:
		mode_context_label.text = String(", ").join(context_parts)
	else:
		mode_context_label.text = ""


func _update_ship_summary() -> void:
	# TODO: Fill out ShipSummaryPanel with labels/bars.
	# For now, you can just dump a few key stats into a child Label.
	var summary_label:Label = $Frame/MainContent/LeftColumn/ShipSummaryPanel/SummaryLabel
	
	if summary_label == null:
		print("\tSum Label ERRROR")
		return
		
	print("\n----------------------------Past Summary Label-------------------------------\n")
	
	var lines: Array = []
	if current_stats.has("hull_points"):
		lines.append("Hull: %d" % int(current_stats["hull_points"]))
	if current_stats.has("shield_strength"):
		lines.append("Shields: %d" % int(current_stats["shield_strength"]))
	if current_stats.has("max_speed"):
		lines.append("Max speed: %d" % int(current_stats["max_speed"]))
	if current_stats.has("acceleration"):
		lines.append("Accel: %d" % int(current_stats["acceleration"]))
	if current_stats.has("turn_rate"):
		lines.append("Turn rate: %.2f" % float(current_stats["turn_rate"]))
	
	summary_label.text = "\n".join(lines)


func _rebuild_installed_list() -> void:
	for child in installed_list.get_children():
		child.queue_free()
	
	for entry in current_loadout:
		if not entry.has("component_id"):
			continue
		
		var component_id: String = str(entry["component_id"])
		var enabled: bool = true
		if entry.has("enabled"):
			enabled = bool(entry["enabled"])
		
		# Category filtering
		if filter_category != "all":
			var category: String = _get_component_category(component_id)
			if category != filter_category:
				continue
		
		# Offline filter
		if filter_show_offline_only and enabled:
			continue
		
		var row: HBoxContainer = HBoxContainer.new()
		
		var name_label: Label = Label.new()
		name_label.text = _get_component_display_name(component_id)
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		
		var toggle: CheckBox = CheckBox.new()
		toggle.text = ""
		toggle.button_pressed = enabled
		toggle.toggled.connect(_on_installed_toggle_toggled.bind(component_id))
		
		var remove_button: Button = Button.new()
		remove_button.text = "Remove"
		remove_button.pressed.connect(_on_installed_remove_pressed.bind(component_id))
		
		row.add_child(name_label)
		row.add_spacer(true)
		row.add_child(toggle)
		row.add_child(remove_button)
		
		# Selection handling
		row.gui_input.connect(_on_installed_row_gui_input.bind(component_id))
		
		installed_list.add_child(row)


func _rebuild_candidates_list() -> void:
	for child in candidates_list.get_children():
		child.queue_free()
	
	for entry in current_candidates:
		if not entry.has("component_id"):
			continue
		
		var component_id: String = str(entry["component_id"])
		var count_value: int = 0
		if entry.has("count"):
			count_value = int(entry["count"])
		
		if count_value <= 0:
			continue
		
		var row: HBoxContainer = HBoxContainer.new()
		
		var name_label: Label = Label.new()
		name_label.text = "%s (x%d)" % [_get_component_display_name(component_id), count_value]
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		
		var install_button: Button = Button.new()
		install_button.text = "Install"
		install_button.pressed.connect(_on_candidate_install_pressed.bind(component_id))
		
		row.add_child(name_label)
		row.add_spacer(true)
		row.add_child(install_button)
		
		row.gui_input.connect(_on_candidate_row_gui_input.bind(component_id))
		
		candidates_list.add_child(row)


func _update_detail_for(component_id: String, source: String) -> void:
	selected_component_id = component_id
	selected_source = source
	
	if component_id == "":
		detail_name_label.text = ""
		detail_description_label.text = ""
		_clear_detail_stats()
		return
	
	var def: Dictionary = _get_component_def(component_id)
	if def.is_empty():
		detail_name_label.text = component_id
		detail_description_label.text = ""
		_clear_detail_stats()
		return
	
	detail_name_label.text = def.get("display_name", component_id)
	detail_description_label.text = def.get("description", "")
	
	_clear_detail_stats()
	
	var stats_keys: Array = ["type", "category", "space_cost", "power_output", "power_draw"]
	for key in stats_keys:
		if def.has(key):
			var line_label: Label = Label.new()
			line_label.text = "%s: %s" % [key, str(def[key])]
			detail_stats_container.add_child(line_label)
	
	_rebuild_detail_actions()


func _clear_detail_stats() -> void:
	for child in detail_stats_container.get_children():
		child.queue_free()


func _rebuild_detail_actions() -> void:
	for child in detail_actions_container.get_children():
		child.queue_free()
	
	if selected_component_id == "":
		return
	
	if selected_source == "installed":
		var remove_button: Button = Button.new()
		remove_button.text = "Remove"
		remove_button.pressed.connect(_on_installed_remove_pressed.bind(selected_component_id))
		detail_actions_container.add_child(remove_button)
	elif selected_source == "candidate":
		var install_button: Button = Button.new()
		install_button.text = "Install"
		install_button.pressed.connect(_on_candidate_install_pressed.bind(selected_component_id))
		detail_actions_container.add_child(install_button)


# --- Row interaction handlers --------------------------------------

func _on_installed_row_gui_input(event: InputEvent, component_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_update_detail_for(component_id, "installed")


func _on_candidate_row_gui_input(event: InputEvent, component_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_update_detail_for(component_id, "candidate")


func _on_installed_toggle_toggled(pressed: bool, component_id: String) -> void:
	if current_ship == null:
		return
	EventBus.ship_component_toggle_requested.emit(current_ship, component_id, pressed)


func _on_installed_remove_pressed(component_id: String) -> void:
	if current_ship == null:
		return
	EventBus.ship_component_remove_requested.emit(current_ship, component_id)


func _on_candidate_install_pressed(component_id: String) -> void:
	if current_ship == null:
		return
	EventBus.ship_component_install_requested.emit(current_ship, component_id)


# --- Component definition helpers ----------------------------------

func _get_component_def(component_id: String) -> Dictionary:
	if component_db == null:
		return {}
	if not component_db.has_method("get_def"):
		return {}
	return component_db.get_def(component_id)


func _get_component_display_name(component_id: String) -> String:
	var def: Dictionary = _get_component_def(component_id)
	if def.is_empty():
		return component_id
	return str(def.get("display_name", component_id))


func _get_component_category(component_id: String) -> String:
	var def: Dictionary = _get_component_def(component_id)
	if def.is_empty():
		return "unknown"
	if def.has("category"):
		return str(def["category"])
	if def.has("type"):
		return str(def["type"])
	return "unknown"

func _setup_filters() -> void:
	if category_filter != null:
		category_filter.clear()
		category_filter.add_item("All", 0)
		category_filter.add_item("Reactor", 1)
		category_filter.add_item("Drive", 2)
		category_filter.add_item("Shield", 3)
		category_filter.add_item("Weapon", 4)
		category_filter.add_item("Utility", 5)
		category_filter.item_selected.connect(_on_category_filter_changed)

	if offline_only_check != null:
		offline_only_check.toggled.connect(_on_offline_only_toggled)

func _on_category_filter_changed(index: int) -> void:
	var id := category_filter.get_item_id(index)
	match id:
		0:
			filter_category = "all"
		1:
			filter_category = "reactor"
		2:
			filter_category = "drive"
		3:
			filter_category = "shield"
		4:
			filter_category = "weapon"
		5:
			filter_category = "utility"
		_:
			filter_category = "all"

	_rebuild_installed_list()
	_rebuild_candidates_list()

func _on_offline_only_toggled(pressed: bool) -> void:
	filter_show_offline_only = pressed
	_rebuild_installed_list()
	_rebuild_candidates_list()
