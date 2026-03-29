extends Control
@onready var fight_btn = $FightButton
@onready var menu = $"../MoveMenu"

func _ready() -> void:
	fight_btn.pressed.connect(_on_fight)

func _on_fight():
	await get_tree().create_timer(0.05).timeout
	visible = false
	menu.visible = true
	menu.populate_moves()
