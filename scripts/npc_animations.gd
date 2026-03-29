extends CharacterBody2D

# Script will grab direction variable from parent
# States will be randomized
# Animation script will communicate and play appropriate animation

@onready var animator = $NPCSprite/NPCAnimator
@onready var window_controller = get_parent()

func _process(_delta):
	update_animation()

func update_animation():

	var dir = window_controller.npc_last_direction

	if window_controller._current_direction == Vector2.ZERO:
		animator.play("idle_%s" % dir)
	else:
		animator.play("walk_%s" % dir)
