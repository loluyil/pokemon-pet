extends Window

signal file_caught

func _ready() -> void:
	size = Vector2i(80, 80)
	transparent = true
	borderless = false
	borderless = true

	await get_tree().create_timer(2.0).timeout
	_on_catch_completed()

func _on_catch_completed():
	print("signal")
	emit_signal("file_caught")
