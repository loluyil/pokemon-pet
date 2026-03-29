extends CharacterBody2D

# 1. Movement direction from input
# 2. Velocity = movement direction * speed
# 3. Move player

# @export = [SeralizeField]
@export var speed: int = 200
@export var run_mult: float = 1.75
@onready var animations: = $TrainerSprite/TrainerAnimation
var last_direction: String = "down"
var last_velocity: = Vector2.ZERO

func _ready() -> void:
	animations.play("idle-%s" % last_direction)
	print("Movement script working")

func _physics_process(_delta):
	update_velocity()
	move_and_slide()
	update_animation()

func update_velocity() -> void:
	# Directions are put in order (negX, posX, posY, negY)
	var move_direction = Input.get_vector("left", "right", "up", "down")
	
	if move_direction.x != 0 && move_direction.y != 0:
		if Input.is_action_just_pressed("left") || Input.is_action_just_pressed("right"):
			move_direction.y = 0
		elif Input.is_action_just_pressed("up") || Input.is_action_just_pressed("down"):
			move_direction.x = 0
		else:
			move_direction = last_velocity
	
	move_direction = move_direction.normalized()
	last_velocity = move_direction
	
	# Running
	if Input.is_key_pressed(KEY_SHIFT) == true:
		velocity = move_direction * (speed * run_mult)
	else:
		velocity = move_direction * speed
		
	if move_direction.x > 0:
		last_direction = "right"
	elif move_direction.x < 0:
		last_direction = "left"
	elif move_direction.y > 0:
		last_direction = "down"
	elif move_direction.y < 0:
		last_direction = "up"
	
func update_animation() -> void:
	if velocity != Vector2.ZERO && Input.is_key_pressed(KEY_SHIFT) == true:
		animations.play("running-%s" % last_direction)
	elif velocity != Vector2.ZERO && Input.is_key_pressed(KEY_SHIFT) == false:
		animations.play("walk-%s" % last_direction)
	else:
		animations.play("idle-%s" % last_direction)
