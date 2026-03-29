extends CharacterBody2D

@onready var animations = $TrainerSprite/TrainerAnimation
@onready var window_controller = get_parent() # Grabs parent script
@onready var bump_sound: AudioStreamPlayer2D = $"../CollisionBump"

var last_direction: String = "down"

func _physics_process(_delta):
	update_direction()
	update_animation()


func update_direction():
	var move_direction = window_controller.current_direction
	
	if move_direction.x > 0:
		last_direction = "right"
	elif move_direction.x < 0:
		last_direction = "left"
	elif move_direction.y > 0:
		last_direction = "down"
	elif move_direction.y < 0:
		last_direction = "up"


func update_animation():
	var move_direction = window_controller.current_direction
	var new_animation: String

	if move_direction == Vector2.ZERO:
		new_animation = "idle-%s" % last_direction
		bump_sound.stop()
	else:
		if window_controller.is_colliding:
			animations.speed_scale = 0.37
			new_animation = "walk-%s" % last_direction
			if not bump_sound.playing:
				bump_sound.play()
		else:
			bump_sound.stop()
			if Input.is_key_pressed(KEY_SHIFT):
				animations.speed_scale = 1.0
				new_animation = "running-%s" % last_direction
			else:
				animations.speed_scale = 0.75
				new_animation = "walk-%s" % last_direction

	if animations.current_animation != new_animation:
		animations.play(new_animation)
