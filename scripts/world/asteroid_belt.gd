extends Node2D
class_name AsteroidBelt

@export var base_pool_size: int = 200
@export var default_radius: float = 2000.0
@export var default_width: float = 300.0

@export var respawn_radius: float = 4000.0
@export var use_camera_arc_mode: bool = true

const ASTEROID_SCENE_PATH: String = "res://scenes/asteroid.tscn"

var radius: float
var width: float
var density: float = 1.0
var pool_size: int

var archetype: StringName = &""
var visual_sets: Array[StringName] = []
var hazards: Array[StringName] = []

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _asteroid_scene: PackedScene
var _asteroids: Array[Node2D] = []

var _asteroid_textures: Array[Texture2D] = []
var _scale_min: float = 0.5
var _scale_max: float = 1.5

@onready var hidden_center: Node2D = $HiddenCenter
@onready var container: Node2D = $AsteroidContainer


func setup(def: Dictionary) -> void:
	# Core scalar config
	radius = def.get("radius", default_radius)
	width = def.get("width", default_width)
	density = def.get("density", 1.0)

	if density < 0.1:
		density = 0.1
	if density > 3.0:
		density = 3.0

	pool_size = int(round(float(base_pool_size) * density))
	if pool_size < 20:
		pool_size = 20

	# Center offset
	if def.has("center_offset"):
		var co = def["center_offset"]
		if typeof(co) == TYPE_ARRAY and co.size() >= 2:
			hidden_center.position = Vector2(float(co[0]), float(co[1]))

	# Seed
	var seed_value: int = int(def.get("seed", 0))
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()

	# Archetype
	if def.has("archetype") and typeof(def["archetype"]) == TYPE_STRING:
		archetype = StringName(def["archetype"])

	# Visual sets
	if def.has("visual_set"):
		var vs = def["visual_set"]
		if typeof(vs) == TYPE_STRING:
			visual_sets.append(StringName(vs))
		elif typeof(vs) == TYPE_ARRAY:
			for v in vs:
				if typeof(v) == TYPE_STRING:
					visual_sets.append(StringName(v))

	_load_asteroid_visual_config()

	# Hazards
	if def.has("hazards") and typeof(def["hazards"]) == TYPE_ARRAY:
		for h in def["hazards"]:
			if typeof(h) == TYPE_STRING:
				hazards.append(StringName(h))

	# Load asteroid scene
	_asteroid_scene = load(ASTEROID_SCENE_PATH)
	if _asteroid_scene == null:
		push_error("AsteroidBelt: Missing asteroid scene at %s" % ASTEROID_SCENE_PATH)
		return

	_create_pool()
	_scatter_initial()


func _create_pool() -> void:
	_asteroids.clear()

	var i: int = 0
	while i < pool_size:
		var inst: Node = _asteroid_scene.instantiate()
		var asteroid := inst as Node2D
		if asteroid != null:
			container.add_child(asteroid)
			_asteroids.append(asteroid)
		i += 1


func _scatter_initial() -> void:
	for asteroid in _asteroids:
		_place_asteroid_random_on_ring(asteroid)


func _place_asteroid_random_on_ring(asteroid: Node2D) -> void:
	var angle: float = _rng.randf_range(0.0, TAU)
	var radial_offset: float = _rng.randf_range(-width * 0.5, width * 0.5)
	var r: float = radius + radial_offset

	var local_pos := Vector2(
		cos(angle) * r,
		sin(angle) * r
	)

	asteroid.global_position = hidden_center.global_position + local_pos

	var sprite := asteroid.get_node_or_null("Sprite2D")
	if sprite == null:
		return

	if _asteroid_textures.size() > 0:
		var idx: int = _rng.randi_range(0, _asteroid_textures.size() - 1)
		sprite.texture = _asteroid_textures[idx]

	# Random rotation
	asteroid.rotation = _rng.randf() * TAU

	var scale_val: float = _rng.randf_range(_scale_min, _scale_max)
	asteroid.scale = Vector2(scale_val, scale_val)

	# If you have visual_sets, you can select textures here
	# via a helper that maps visual_sets/archetype to sprites.


func _process(delta: float) -> void:
	if not use_camera_arc_mode:
		return

	var cam := _get_camera()
	if cam == null:
		return

	var cam_pos: Vector2 = cam.global_position

	for asteroid in _asteroids:
		var to_cam: Vector2 = asteroid.global_position - cam_pos
		var dist: float = to_cam.length()
		if dist > respawn_radius:
			_reposition_near_camera_on_ring(asteroid, cam_pos)


func _reposition_near_camera_on_ring(asteroid: Node2D, cam_pos: Vector2) -> void:
	var center_pos: Vector2 = hidden_center.global_position
	var dir_vec: Vector2 = cam_pos - center_pos
	if dir_vec == Vector2.ZERO:
		dir_vec = Vector2(1.0, 0.0)
	dir_vec = dir_vec.normalized()

	var base_angle: float = atan2(dir_vec.y, dir_vec.x)
	var spread: float = 0.8
	var angle: float = base_angle + _rng.randf_range(-spread, spread)

	var radial_offset: float = _rng.randf_range(-width * 0.5, width * 0.5)
	var r: float = radius + radial_offset

	var local_pos := Vector2(
		cos(angle) * r,
		sin(angle) * r
	)

	asteroid.global_position = center_pos + local_pos

	asteroid.rotation = _rng.randf() * TAU
	var scale_val: float = _rng.randf_range(0.6, 1.4)
	asteroid.scale = Vector2(scale_val, scale_val)

func _get_camera() -> Camera2D:
	var viewport := get_viewport()
	if viewport == null:
		return null
	return viewport.get_camera_2d()


func _load_asteroid_visual_config() -> void:
	var path := "res://data/procgen/asteroid_types.json"
	if not FileAccess.file_exists(path):
		return

	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return

	var variants: int = int(data.get("variants", 0))
	var pattern: String = str(data.get("asset_pattern", ""))
	var scale_arr = data.get("scale_range", [0.5, 1.5])

	if typeof(scale_arr) == TYPE_ARRAY and scale_arr.size() >= 2:
		_scale_min = float(scale_arr[0])
		_scale_max = float(scale_arr[1])

	var i: int = 1
	while i <= variants:
		var nn := "%02d" % i
		var path_i := pattern.replace("{nn}", nn)
		if FileAccess.file_exists(path_i):
			var tex := load(path_i)
			if tex is Texture2D:
				_asteroid_textures.append(tex)
		i += 1
