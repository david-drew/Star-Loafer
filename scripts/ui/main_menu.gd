extends Control

@onready var new_game_dialog = $LaunchUI/Panel/NewGameDialog
@onready var seed_input: LineEdit    = $LaunchUI/Panel/NewGameDialog/HBoxContainer/SeedInput
@onready var size_btn: OptionButton  = $LaunchUI/Panel/NewGameDialog/HBoxContainer2/SizeOption
@onready var menu_box: VBoxContainer = $LaunchUI/Panel/MenuVbox

func _ready() -> void:
	$LaunchUI/Panel/MenuVbox/NewGame.pressed.connect(_on_new_game)
	$LaunchUI/Panel/MenuVbox/LoadGame.pressed.connect(_on_load_game)
	$LaunchUI/Panel/MenuVbox/Quit.pressed.connect(_on_quit)
	new_game_dialog.hide()

func _on_new_game() -> void:
	new_game_dialog.show()
	menu_box.hide()
	seed_input.text = str(randi())
	$LaunchUI/Panel/NewGameDialog/Start.pressed.connect(_on_start_new_game)

func _on_start_new_game() -> void:
	var seed = int(seed_input.text)
	var size = size_btn.get_item_text(
		size_btn.selected
	).to_lower()
	
	SceneManager.start_fresh_game({
		"seed": seed,
		"size": size
	})

func _on_load_game() -> void:
	# TODO: Show save slot selection dialog
	pass

func _on_quit() -> void:
	get_tree().quit()
