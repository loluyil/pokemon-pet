extends Control
@onready var fight_btn = $FightButton
@onready var menu = $"../MoveMenu"
@onready var open_background = $FightButton/Background/AnimationPlayer
@onready var buttons = $Buttons
@onready var pokemon_btn: TextureButton = $Buttons/PokemonButton
@onready var party_menu: Control = $"../PartyMenu"

@onready var _sfx_player: AudioStreamPlayer = $"../BattleSFX"
var _sfx_select = preload("res://sounds/select-button.wav")


func _ready() -> void:
	fight_btn.pressed.connect(_on_fight)
	pokemon_btn.pressed.connect(_on_pokemon)

func _on_fight():
	_sfx_player.stream = _sfx_select
	_sfx_player.play()
	await get_tree().create_timer(0.05).timeout
	buttons.visible = false
	open_background.play("open")
	menu.visible = true
	menu.populate_moves()
	fight_btn.disabled = true

func _on_pokemon():
	_sfx_player.stream = _sfx_select
	_sfx_player.play()
	await get_tree().create_timer(0.05).timeout
	buttons.visible = false
	fight_btn.disabled = true
	party_menu.open()
