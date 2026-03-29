extends TextureButton

func _ready():
	button_down.connect(_on_pressed)

func _on_pressed():
	material.set_shader_parameter("pressed", true)
	await get_tree().create_timer(0.05).timeout
	material.set_shader_parameter("pressed", false)
