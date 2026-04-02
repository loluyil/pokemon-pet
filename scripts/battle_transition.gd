extends Window

signal transition_finished

@onready var rect: ColorRect = $ColorRect
@onready var music_player: AudioStreamPlayer = $Master

var _battle_tracks: Array = [
	preload("res://sounds/battle-music/1-26. Battle! Trainer.mp3"),
	preload("res://sounds/battle-music/1-44. Battle! Gym Leader.mp3"),
]

# The track chosen for this battle, so battle_ui can continue it
var chosen_track: AudioStream

func _ready():
	var screen := DisplayServer.screen_get_usable_rect()
	size = screen.size

	rect.material.set_shader_parameter("progress", 0.0)
	rect.material.set_shader_parameter("flash_intensity", 0.0)

	# Wait one frame so the OS window fully applies borderless/transparent
	await get_tree().process_frame
	position = screen.position

func play_transition():
	var mat = rect.material

	chosen_track = _battle_tracks.pick_random()
	music_player.stream = chosen_track
	music_player.play()

	var flash_tween := create_tween()
	for i in 3:
		flash_tween.tween_property(mat, "shader_parameter/flash_intensity", 0.9, 0.04)
		flash_tween.tween_property(mat, "shader_parameter/flash_intensity", 0.0, 0.06)
	await flash_tween.finished

	var sweep_tween := create_tween().set_parallel(true)
	sweep_tween.tween_property(mat, "shader_parameter/progress", 1.0, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var flash2 := create_tween()
	flash2.tween_interval(0.15)
	flash2.tween_property(mat, "shader_parameter/flash_intensity", 0.7, 0.03)
	flash2.tween_property(mat, "shader_parameter/flash_intensity", 0.0, 0.08)
	await sweep_tween.finished

	await get_tree().create_timer(.5).timeout
	transition_finished.emit()
