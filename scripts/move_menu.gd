extends Control

@onready var move1 = $Move1
@onready var move2 = $Move2
@onready var move3 = $Move3
@onready var move4 = $Move4
@onready var back_btn = $BackButton

@onready var action_menu = $"../ActionMenu"
@onready var fight_btn = $"../ActionMenu/FightButton"
@onready var background_close = $"../ActionMenu/FightButton/Background/AnimationPlayer"
@onready var buttons = $"../ActionMenu/Buttons"

@onready var battle_sim: Node = $"../../PokemonData"

func _ready():
	move1.pressed.connect(_on_move_selected.bind(0))
	move2.pressed.connect(_on_move_selected.bind(1))
	move3.pressed.connect(_on_move_selected.bind(2))
	move4.pressed.connect(_on_move_selected.bind(3))
	
	if back_btn:
		back_btn.pressed.connect(_on_back)

func populate_moves():
	var mon = battle_sim.your_team[battle_sim.your_active]
	var moveset = mon["moveset"]
	var buttons = [move1, move2, move3, move4]
	
	for i in 4:
		if i < moveset.size():
			var move = moveset[i]
			buttons[i].visible = true
			buttons[i].text = move["name"].replace("-", " ").capitalize()
		else:
			buttons[i].visible = false

func _on_move_selected(index: int):
	var opp_move = battle_sim.get_opponent_move()
	battle_sim.execute_turn(index, opp_move)
	
	await get_tree().create_timer(0.05).timeout
	visible = false
	buttons.visible = true
	background_close.play_backwards("open")
	fight_btn.disabled = false

func _on_back():
	visible = false
	buttons.visible = true
	background_close.play_backwards("open")
	fight_btn.disabled = false

func _input(event):
	if event.is_action_pressed("ui_cancel") and visible:
		_on_back()
