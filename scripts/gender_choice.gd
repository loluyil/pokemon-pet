extends Window

@export var sprite_scale:= Vector2(2, 2)

@onready var male: TextureRect = $AreYouMale
@onready var female: TextureRect = $AreYouFemale
var screen = DisplayServer.screen_get_usable_rect()
var gender_choice: String
var hovering_male := false
var hovering_female := false

signal choice_complete

func _ready() -> void:
	size = screen.size
	borderless = false
	borderless = true

	male.scale = sprite_scale
	male.pivot_offset.y = 370
	female.scale = sprite_scale
	female.pivot_offset.y = 370
	
	position_sprites()
	
	male.mouse_entered.connect(func(): hovering_male = true)
	male.mouse_exited.connect(func(): hovering_male = false)
	female.mouse_entered.connect(func(): hovering_female = true)
	female.mouse_exited.connect(func(): hovering_female = false)

func position_sprites():
	var screen_size = size
	
	# Left side
	male.position = Vector2(0, screen_size.y / 2)
	print(male.position)
	print(male.pivot_offset.y)
	
	# Right side
	female.position = Vector2(screen_size.x - 500, screen_size.y / 2)
	print(female.position)

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		if hovering_male:
			gender_choice = "male"
			print("clicked male")
			emit_signal("choice_complete")
		if hovering_female:
			gender_choice = "female"
			print("clicked female")
			emit_signal("choice_complete")
