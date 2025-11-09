extends Camera2D

signal screenshot

#@onready var zoom_lbl:Label = get_node("/root/Game/CanvasLayer/ZoomLabel")

var ZOOM_MAX:float = 2.0
var ZOOM_MIN:float = 0.2

var zoom_scale:float = 0.1
var new_zoom:float   = 0.0

#func _ready():
	#enabled = true
	#position_smoothing_enabled = true

func _unhandled_input(event):
	new_zoom = 0
	if event.is_action_pressed("zoom_in"):
		new_zoom = self.zoom.x + zoom_scale
		#self.zoom = Vector2( zoom.x + zoom_scale, zoom.y + zoom_scale)
	elif event.is_action_pressed("zoom_out"):
		new_zoom = self.zoom.x - zoom_scale
		#self.zoom = Vector2( zoom.x - zoom_scale, zoom.y - zoom_scale)
	elif event.is_action_pressed("reset_camera"):
		self.zoom = Vector2(1, 1)
	elif event.is_action_pressed("print_screen"):
			print_screen()

	if new_zoom > ZOOM_MIN and new_zoom < ZOOM_MAX:
		#print( str( "New Zoom: ", new_zoom ))
		camera_zoom()

func camera_zoom():
	self.zoom = Vector2(new_zoom, new_zoom)
	#zoom_lbl.text = str(self.zoom)

func print_screen():
	var datime = Time.get_datetime_dict_from_system()
	var img = get_viewport().get_texture().get_image()
	#img.flip_y
	#var tex = ImageTexture.create_from_image(img)
	
	# user:// is:
	#	Windows:  %APPDATA%\Godot\app_userdata\Project Name
	#   Linux:    $HOME/.godot/app_userdata/Project Name
	var err := img.save_png(
			"user://sl_{year}-{month}-{day}_{hour}.{minute}.{second}.png" \
			.format(datime)
	)

	if err == OK:
		screenshot.emit()
	else:
		print("Error: Couldn't save screenshot.")
