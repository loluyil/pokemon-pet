extends Node3D

@onready var gender_window: Window = $GenderReveal
@onready var are_you_male: TextureRect = $GenderReveal/AreYouMale
@onready var are_you_female: TextureRect = $GenderReveal/AreYouFemale

# Prevent error when trying to move before sprites are initialized
var game_ready = false
var _battle_triggered: bool = false

func _ready() -> void:
	var window = get_window()
	DisplayServer.window_set_size(Vector2i(80, 80))
	get_viewport().transparent_bg = true
	window.transparent = true
	window.borderless = true
	window.always_on_top = true
	window.unresizable = false
	
	choose_gender()

func _process(delta):
	if not game_ready:
		return
	_update_window_position(delta)
	_check_npc_overlap()

# Function is also in charge of loading the trainers, npcs, and buildings
func choose_gender():
	var window = get_window()
	var choice_scene = $GenderReveal
	await choice_scene.choice_complete
	choice_scene.queue_free()
	
	var town_music = preload("res://sounds/1-06. Kanoko Town.mp3")
	$BGmusic.stream = town_music
	$BGmusic.play()
	load_building()
	load_trainer()
	load_entities()

	# Brings trainer window to the front
	window.grab_focus()
	
	# Process delta will move now
	game_ready = true

# Movement Variables
@export var speed: int = 1
@export var run_mult: int = 2
var current_direction: Vector2 = Vector2.ZERO
var last_velocity: Vector2 = Vector2.ZERO
var is_colliding: bool = false
var remainder := Vector2.ZERO

# Movement
func _update_window_position(delta: float) -> void:
	var window = get_window()
	var move_direction = Input.get_vector("left", "right", "up", "down")
	
	# Only uses cardinal directions by remove diagonal movement
	# Saves last direction and move direction for animation
	
	if move_direction.x != 0 and move_direction.y != 0:
		if Input.is_action_just_pressed("left") or Input.is_action_just_pressed("right"):
			move_direction.y = 0
		elif Input.is_action_just_pressed("up") or Input.is_action_just_pressed("down"):
			move_direction.x = 0
		else:
			move_direction = last_velocity
	
	move_direction = move_direction.normalized()
	last_velocity = move_direction
	current_direction = move_direction
	
	var current_speed = speed * 60
	if Input.is_key_pressed(KEY_SHIFT):
		current_speed *= run_mult

	# If no movement, no need to check for anything else -- some optimzization
	if move_direction == Vector2.ZERO:
		return
		
	var move_vector = move_direction * current_speed * delta + remainder
	var move_vector_i = Vector2i(move_vector)
	var next_position = window.position + move_vector_i
	remainder = move_vector - Vector2(move_vector_i)
	
	# Doesn't get the sprite stuck whenever it collides with something
	is_colliding = collision_check(next_position)

	if not is_colliding:
		window.position = next_position

func load_trainer():
	# Preloads the male/female trainers
	# Grabs gender variable from mouse event in another script and sets the sprite to appropriate gender
	
	var trainer = preload("res://scenes/trainer/trainer.tscn").instantiate()
	var trainer_male = preload("res://sprites/spritesheet_male.png")
	var trainer_female = preload("res://sprites/spritesheet_female.png")
	
	add_child(trainer)
	
	var trainer_sprite = $Trainer/TrainerSprite
	if gender_window.gender_choice == "male":
		trainer_sprite.texture = trainer_male
	elif gender_window.gender_choice == "female":
		trainer_sprite.texture = trainer_female

# Window Spawn
func load_building():
	var building = preload("res://scenes/pokebuilding_window.tscn").instantiate()
	add_child(building)
	var building_window: Window = $Window
	var screen_size = DisplayServer.screen_get_usable_rect().size
	var screen_width = screen_size.x
	var window_size = building_window.get_viewport().get_visible_rect().size
	var window_width = window_size.x
	
	get_viewport().set_embedding_subwindows(false)
	building_window.set_position(Vector2i((screen_width - window_width) , 0))
	building_window.set_size(Vector2i(325, 330))
	building_window.transparent = true
	building_window.always_on_top = true
	# WHY THE FUCK DO I HAVE TO SET IT TO FALSE AND TRUE FOR IT TO LOAD XDDDDD
	building_window.borderless = false
	building_window.borderless = true

func load_entities():
	# Grab the spritesheets attached to NPCWindow
	# Grabs a random spritesheet from the Array
	# Attaches it to the texture
	
	var npc = preload("res://scenes/npcs/npc.tscn").instantiate()
	add_child(npc)
	
	var npc_window = $NPCWindow
	var npc_sprite = npc.get_node("NPC/NPCSprite") 
	
	# pick_random() doesnt output an index, it actually outputs the name
	npc_sprite.texture = npc_window.npc_sprites.pick_random()

func _check_npc_overlap() -> void:
	if _battle_triggered:
		return
	var npc_window: Window = get_node_or_null("NPCWindow")
	if not npc_window:
		return
	var trainer_window := get_window()
	var trainer_rect   := Rect2i(trainer_window.position, trainer_window.size)
	var npc_rect       := Rect2i(npc_window.position, npc_window.size)
	if trainer_rect.intersects(npc_rect):
		_trigger_battle()

func _trigger_battle() -> void:
	_battle_triggered = true
	# Stop all processing so animations/timers don't fire during transition
	set_process(false)
	var transition = preload("res://scenes/battle_transition.tscn").instantiate()
	add_child(transition)
	transition.play_transition()
	await transition.transition_finished
	get_tree().change_scene_to_file("res://scenes/battle_scene.tscn")

# Set Boundry
func collision_check(next_pos: Vector2i) -> bool:
	var window = get_window()
	var building_window: Window = $Window
	
	var building_pos = building_window.get_position_with_decorations()
	var building_size = building_window.size
	
	var player_size = window.size
	
	var player_rect = Rect2i(next_pos, player_size)
	var building_rect = Rect2i(building_pos, building_size)
	
	return player_rect.intersects(building_rect.grow_individual(-30, -15, -30, -30))
