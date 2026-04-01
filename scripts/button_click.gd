extends TextureButton

var target_material

func _ready():
	button_down.connect(_on_pressed)

	var bg = get_node_or_null("Background")
	if bg and bg.material:
		target_material = bg.material.duplicate()
		bg.material = target_material
	else:
		target_material = material.duplicate()
		material = target_material

func _on_pressed():
	if target_material:
		target_material.set_shader_parameter("pressed", true)
		await get_tree().create_timer(0.05).timeout
		target_material.set_shader_parameter("pressed", false)
