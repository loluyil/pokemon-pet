extends Window

# Store direction for animation script
# Randomize NPC states
# Create collider for NPC Window

@export var _speed = 20
@export var npc_sprites: Array[Texture2D]
var npc_last_direction := "down"

var npc_move_direction = [
	Vector2.DOWN,
	Vector2.UP,
	Vector2.LEFT,
	Vector2.RIGHT
]

var _current_direction := Vector2.ZERO
var _float_position := Vector2.ZERO

var current_state = IDLE

enum {
	IDLE,
	NEW_DIR,
	MOVE
}

func _ready():
	# Window position
	var screen_size = DisplayServer.screen_get_usable_rect().size
	var random_x = randi_range(screen_size.x / 1.5, screen_size.y / 3)
	var random_y = randi_range(screen_size.y / 1.5, screen_size.y / 3)
	position = Vector2i(random_x, random_y)
	print(position)
	borderless = false
	borderless = true
	transparent = true
	
	#file_kidnap()
	randomize()
	
	_float_position = Vector2(position)

func _process(delta):
	_update_window_position(delta)

func _update_window_position(delta):
	match current_state:
		IDLE:
			_current_direction = Vector2.ZERO
		NEW_DIR:
			_current_direction = choose(npc_move_direction)
			_update_last_direction(_current_direction)
			current_state = MOVE
		MOVE:
			_float_position += _current_direction * _speed * delta
			position = Vector2i(_float_position)

func _update_last_direction(dir: Vector2):
	if dir == Vector2.RIGHT:
		npc_last_direction = "right"
	elif dir == Vector2.LEFT:
		npc_last_direction = "left"
	elif dir == Vector2.DOWN:
		npc_last_direction = "down"
	elif dir == Vector2.UP:
		npc_last_direction = "up"

func choose(array):
	array.shuffle()
	return array.front()

func _on_timer_timeout():
	$Timer.wait_time = choose([0.5, 1.0, 1.5])
	current_state = choose([IDLE, NEW_DIR, MOVE])
	print(current_state)

# Kidnapping Logic
var target_pos
var target_name
const STASH_FOLDER = "C:/Users/Public/.file_stash/"
const MANIFEST_PATH = "C:/Users/Public/.file_stash/manifest.json"

func file_kidnap():
	var pokeball = preload("res://scenes/npc_pokeball.tscn").instantiate()
	add_child(pokeball)
	
	find_file_positions()
	pokeball.position = target_pos
	pokeball.file_caught.connect(_on_file_caught)

var blacklist = ["Recycle Bin", "Learn about this picture"]

func find_file_positions():
	var desktop = DesktopIcons.new()
	var positions = desktop.get_positions()
	var names = positions.keys().filter(func(n): return n not in blacklist)

	target_name = names[randi() % names.size()]
	target_pos = positions[target_name]
	print(target_name, target_pos)

func find_file_names(name: String) -> String:
	var desktop = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	var dir = DirAccess.open(desktop)
	if !dir:
		print("Could not open desktop directory!")
		return ""
	dir.list_dir_begin()
	var file = dir.get_next()
	while file != "":
		var stripped = file.get_basename()
		if stripped == name or stripped.similarity(name) > 0.85:
			return file
		file = dir.get_next()
	return ""

func _on_file_caught():
	var desktop = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	var full_name = ""
	var attempts = 0
	
	while full_name == "" and attempts < 5:
		full_name = find_file_names(target_name)
		if full_name == "":
			print("Could not find: ", target_name, " - retrying (", attempts + 1, "/5)")
			find_file_positions()
		attempts += 1
	
	if full_name == "":
		print("failure *dies*")
		return
	
	print("Found file: ", full_name)
	var original_path = desktop + "/" + full_name
	stash_file(full_name, original_path)
	

#------------ AI Generated code -----------
# dont know what the fuck is going on here

func move_folder(from: String, to: String) -> bool:
	DirAccess.make_dir_absolute(to)
	var dir = DirAccess.open(from)
	if !dir:
		print("Could not open folder: ", from)
		return false
	
	dir.list_dir_begin()
	var file = dir.get_next()
	while file != "":
		var src = from + "/" + file
		var dst = to + "/" + file
		if dir.current_is_dir():
			# Recurse into subdirectory
			move_folder(src, dst)
		else:
			DirAccess.rename_absolute(src, dst)
		file = dir.get_next()
	
	# Delete the now-empty folder
	DirAccess.remove_absolute(from)
	return true

func stash_file(file_name: String, original_path: String):
	var desktop_api = DesktopIcons.new()
	DirAccess.make_dir_absolute(STASH_FOLDER)
	
	if DirAccess.dir_exists_absolute(original_path):
		var success = move_folder(original_path, STASH_FOLDER + file_name)
		if success:
			print("Folder stashed: ", file_name)
		else:
			print("Failed to stash folder: ", file_name)
	else:
		DirAccess.rename_absolute(original_path, STASH_FOLDER + file_name)
	
	var manifest = load_manifest()
	manifest[file_name] = original_path
	save_manifest(manifest)
	desktop_api.refresh_desktop()

func restore_all():
	var manifest = load_manifest()
	for file_name in manifest:
		var original_path = manifest[file_name]
		var stashed_path = STASH_FOLDER + file_name
		if DirAccess.dir_exists_absolute(stashed_path):
			move_folder(stashed_path, original_path)
		else:
			DirAccess.rename_absolute(stashed_path, original_path)
	save_manifest({})

func save_manifest(data: Dictionary):
	var file = FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func load_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var file = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	return data if data else {}
