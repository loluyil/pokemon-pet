extends Control
@onready var fight_btn = $FightButton
@onready var menu = $"../MoveMenu"
@onready var open_background = $FightButton/Background/AnimationPlayer
@onready var buttons = $Buttons

func _ready() -> void:
	fight_btn.pressed.connect(_on_fight)

func _on_fight():
	await get_tree().create_timer(0.05).timeout
	buttons.visible = false
	open_background.play("open")
	menu.visible = true
	menu.populate_moves()
	fight_btn.disabled = true
