extends CanvasLayer

func _ready() -> void:
	hide()
	$Panel/ButtonsVBox/ResumeButton.pressed.connect(_on_resume)
	$Panel/ButtonsVBox/SaveButton.pressed.connect(_on_save)
	$Panel/ButtonsVBox/LoadButton.pressed.connect(_on_load)
	$Panel/ButtonsVBox/MainMenuButton.pressed.connect(_on_main_menu)
	$Panel/ButtonsVBox/QuitButton.pressed.connect(_on_quit)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle_pause()

func toggle_pause() -> void:
	visible = !visible
	get_tree().paused = visible

func _on_resume() -> void:
	toggle_pause()

func _on_save() -> void:
	$Panel/SaveLoadDialog.show()
	$Panel/SaveLoadDialog.set_mode("save")

func _on_load() -> void:
	$Panel/SaveLoadDialog.show()
	$Panel/SaveLoadDialog.set_mode("load")

func _on_main_menu() -> void:
	SceneManager.return_to_main_menu()

func _on_quit() -> void:
	get_tree().quit()
