extends Node

@onready var your_hp_bar: TextureProgressBar = $VBoxContainer/HPBarContainer/YourHPBar
@onready var opp_hp_bar: TextureProgressBar = $VBoxContainer/HPBarContainer2/OpponentHPBar
@onready var your_name_label: Label = $VBoxContainer/HPBarContainer/Label
@onready var opp_name_label: Label = $VBoxContainer/HPBarContainer2/Label
@onready var battle_sim: Node = $PokemonData
@onready var text_box: RichTextLabel            # set your path if you have one

func _ready():
	battle_sim.hp_changed.connect(_on_hp_changed)
	battle_sim.pokemon_sent_out.connect(_on_pokemon_sent_out)
	battle_sim.battle_message.connect(_on_battle_message)
	battle_sim.pokemon_fainted.connect(_on_pokemon_fainted)
	battle_sim.battle_ended.connect(_on_battle_ended)
	# battle_sim._ready() already ran start_battle() before this node's _ready,
	# so signals were missed — initialize display directly from current state
	_init_display()

func _init_display():
	var your_mon = battle_sim.your_team[battle_sim.your_active]
	var opp_mon  = battle_sim.opponent_team[battle_sim.opponent_active]
	your_hp_bar.set_hp_instant(your_mon["current_hp"], your_mon["max_hp"])
	your_name_label.text = _format_name(your_mon["name"])
	opp_hp_bar.set_hp_instant(opp_mon["current_hp"], opp_mon["max_hp"])
	opp_name_label.text = _format_name(opp_mon["name"])

func _format_name(mon_name: String) -> String:
	return mon_name.replace("-", " ").capitalize()

func _on_hp_changed(is_yours: bool, current_hp: int, max_hp: int):
	if is_yours:
		your_hp_bar.update_hp(current_hp, max_hp)
	else:
		opp_hp_bar.update_hp(current_hp, max_hp)

func _on_pokemon_sent_out(is_yours: bool, current_hp: int, max_hp: int, mon_name: String):
	if is_yours:
		your_hp_bar.set_hp_instant(current_hp, max_hp)
		your_name_label.text = _format_name(mon_name)
	else:
		opp_hp_bar.set_hp_instant(current_hp, max_hp)
		opp_name_label.text = _format_name(mon_name)

func _on_battle_message(text: String):
	print(text)
	# Later: display in your text box
	# if text_box:
	#     text_box.text = text

func _on_pokemon_fainted(is_yours: bool, mon_name: String):
	print(mon_name + " fainted!")

func _on_battle_ended(you_won: bool):
	if you_won:
		print("You win!")
	else:
		print("You lose!")
