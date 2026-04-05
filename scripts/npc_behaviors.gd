extends Window

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
	MOVE,
	WALK_TO_FILE,
	KIDNAPPING,
	COOLDOWN
}

# ─── Kidnapping State ────────────────────────────────────────────────────────────
var _kidnap_enabled := true
var _kidnap_target_screen_pos := Vector2.ZERO
const KIDNAP_ARRIVE_DIST := 30.0
const KIDNAP_COOLDOWN_SEC := 15.0

func _ready():
	# Window position
	var screen_size = DisplayServer.screen_get_usable_rect().size
	var random_x = randi_range(screen_size.x / 1.5, screen_size.y / 3)
	var random_y = randi_range(screen_size.y / 1.5, screen_size.y / 3)
	position = Vector2i(random_x, random_y)
	borderless = false
	borderless = true
	transparent = true

	randomize()
	_float_position = Vector2(position)

	# Start the kidnap cycle after a short initial delay
	if _kidnap_enabled:
		get_tree().create_timer(3.0).timeout.connect(_begin_kidnap, CONNECT_ONE_SHOT)

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
			var next_float = _float_position + _current_direction * _speed * delta
			var next_pos   = Vector2i(next_float)
			if _would_collide(next_pos):
				current_state = NEW_DIR
				return
			_float_position = next_float
			position        = next_pos
		WALK_TO_FILE:
			_walk_toward_target(delta)
		KIDNAPPING, COOLDOWN:
			_current_direction = Vector2.ZERO

func _walk_toward_target(delta: float):
	var diff := _kidnap_target_screen_pos - _float_position
	# Grid movement: move along one axis at a time (horizontal first, then vertical)
	var dir := Vector2.ZERO
	if abs(diff.x) > KIDNAP_ARRIVE_DIST:
		dir = Vector2(sign(diff.x), 0)
	elif abs(diff.y) > KIDNAP_ARRIVE_DIST:
		dir = Vector2(0, sign(diff.y))
	else:
		_arrive_at_file()
		return
	_current_direction = dir
	_update_last_direction(dir)
	var next_float = _float_position + dir * _speed * 1.5 * delta
	var next_pos = Vector2i(next_float)
	# Skip building collision when walking to file — NPC is determined
	var screen := DisplayServer.screen_get_usable_rect()
	var npc_rect := Rect2i(next_pos, size)
	if not screen.encloses(npc_rect):
		# Target is offscreen, abort and pick a new one
		_begin_kidnap()
		return
	_float_position = next_float
	position = next_pos
	if _float_position.distance_to(_kidnap_target_screen_pos) < KIDNAP_ARRIVE_DIST:
		_arrive_at_file()

func _update_last_direction(dir: Vector2):
	if abs(dir.x) > abs(dir.y):
		npc_last_direction = "right" if dir.x > 0 else "left"
	else:
		npc_last_direction = "down" if dir.y > 0 else "up"

func _would_collide(next_pos: Vector2i) -> bool:
	var npc_rect := Rect2i(next_pos, size)
	# Keep NPC on-screen
	var screen := DisplayServer.screen_get_usable_rect()
	if not screen.encloses(npc_rect):
		return true
	# Collide with building window
	var main := get_parent()
	if main and main.has_node("Window"):
		var bw: Window = main.get_node("Window")
		var building_rect := Rect2i(bw.position, bw.size)
		if npc_rect.intersects(building_rect):
			return true
	return false

func choose(array):
	array.shuffle()
	return array.front()

func _on_timer_timeout():
	# Only use random wander when not in kidnap states
	if current_state in [WALK_TO_FILE, KIDNAPPING, COOLDOWN]:
		return
	$Timer.wait_time = choose([0.5, 1.0, 1.5])
	current_state = choose([IDLE, NEW_DIR, MOVE])

# ─── Kidnapping Logic ────────────────────────────────────────────────────────────
var target_pos
var target_name
const STASH_FOLDER = "C:/Users/Public/.file_stash/"
const MANIFEST_PATH = "C:/Users/Public/.file_stash/manifest.json"

func _begin_kidnap():
	if not _kidnap_enabled:
		return
	if not find_file_positions():
		# No valid files found, retry later
		get_tree().create_timer(5.0).timeout.connect(_begin_kidnap, CONNECT_ONE_SHOT)
		return
	# target_pos from DesktopIcons is in screen coordinates
	_kidnap_target_screen_pos = Vector2(target_pos)
	current_state = WALK_TO_FILE

func _arrive_at_file():
	current_state = KIDNAPPING
	_do_file_kidnap()

func _do_file_kidnap():
	var desktop = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	var full_name = ""
	var attempts = 0

	while full_name == "" and attempts < 5:
		full_name = find_file_names(target_name)
		if full_name == "":
			attempts += 1

	if full_name == "":
		# Couldn't find the file, go back to wandering after cooldown
		_start_cooldown()
		return

	var original_path = desktop + "/" + full_name
	stash_file(full_name, original_path)
	_start_cooldown()

func _start_cooldown():
	current_state = COOLDOWN
	get_tree().create_timer(KIDNAP_COOLDOWN_SEC).timeout.connect(func():
		current_state = IDLE
		# Start looking for the next file
		if _kidnap_enabled:
			get_tree().create_timer(2.0).timeout.connect(_begin_kidnap, CONNECT_ONE_SHOT)
	, CONNECT_ONE_SHOT)

var blacklist = ["Recycle Bin", "Learn about this picture"]

func find_file_positions() -> bool:
	var desktop = DesktopIcons.new()
	var positions = desktop.get_positions()
	var names = positions.keys().filter(func(n): return n not in blacklist)
	if names.is_empty():
		return false
	target_name = names[randi() % names.size()]
	target_pos = positions[target_name]
	return true

func find_file_names(name: String) -> String:
	var desktop = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	var dir = DirAccess.open(desktop)
	if !dir:
		return ""
	dir.list_dir_begin()
	var file = dir.get_next()
	while file != "":
		var stripped = file.get_basename()
		if stripped == name or stripped.similarity(name) > 0.85:
			return file
		file = dir.get_next()
	return ""

# ─── File Storage ────────────────────────────────────────────────────────────────

func move_folder(from: String, to: String) -> bool:
	DirAccess.make_dir_absolute(to)
	var dir = DirAccess.open(from)
	if !dir:
		return false

	dir.list_dir_begin()
	var file = dir.get_next()
	while file != "":
		var src = from + "/" + file
		var dst = to + "/" + file
		if dir.current_is_dir():
			move_folder(src, dst)
		else:
			DirAccess.rename_absolute(src, dst)
		file = dir.get_next()

	DirAccess.remove_absolute(from)
	return true

func stash_file(file_name: String, original_path: String):
	var desktop_api = DesktopIcons.new()
	DirAccess.make_dir_absolute(STASH_FOLDER)

	if DirAccess.dir_exists_absolute(original_path):
		move_folder(original_path, STASH_FOLDER + file_name)
	else:
		DirAccess.rename_absolute(original_path, STASH_FOLDER + file_name)

	var manifest = load_manifest()
	manifest[file_name] = original_path
	save_manifest(manifest)
	desktop_api.refresh_desktop()

func restore_all():
	var desktop_api = DesktopIcons.new()
	var manifest = load_manifest()
	for file_name in manifest:
		var original_path = manifest[file_name]
		var stashed_path = STASH_FOLDER + file_name
		if DirAccess.dir_exists_absolute(stashed_path):
			move_folder(stashed_path, original_path)
		else:
			DirAccess.rename_absolute(stashed_path, original_path)
	save_manifest({})
	desktop_api.refresh_desktop()

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
