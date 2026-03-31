extends Window

signal transition_finished

const TRANSITION_DURATION := 0.7
const HOLD_DURATION := 0.3

@onready var rect: ColorRect = $ColorRect

func _ready():
	# Cover the entire screen
	var screen := DisplayServer.screen_get_usable_rect()
	position = screen.position
	size = screen.size
	always_on_top = true
	unfocusable = true
	get_viewport().transparent_bg = true
	transparent = true
	# Windows borderless toggle hack (same as npc/building windows)
	borderless = false
	borderless = true

	rect.material.set_shader_parameter("progress", 0.0)

func play_transition():
	var tween := create_tween()
	tween.tween_property(rect.material, "shader_parameter/progress", 1.0, TRANSITION_DURATION)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_interval(HOLD_DURATION)
	tween.tween_callback(func(): transition_finished.emit())
