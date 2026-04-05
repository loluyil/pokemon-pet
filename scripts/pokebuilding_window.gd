extends Window

var _gender_window_open := false

func _input(event):
	if not (event is InputEventMouseButton and event.pressed):
		return

	# Check if click is within the building window
	var mouse_pos = get_mouse_position()
	var window_rect = Rect2(Vector2.ZERO, Vector2(size))
	if not window_rect.has_point(mouse_pos):
		return

	var main = get_parent()
	if not main:
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		main.toggle_gender()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_open_gender_choice(main)

func _open_gender_choice(main):
	if _gender_window_open:
		return
	_gender_window_open = true

	var choice_scene = preload("res://scenes/gender_choice.tscn").instantiate()
	main.add_child(choice_scene)
	await choice_scene.choice_complete
	main.set_gender(choice_scene.gender_choice)
	choice_scene.queue_free()
	_gender_window_open = false
