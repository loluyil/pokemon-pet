extends Node3D

# Battle Cinematic Scene

@onready var trainer_pokeball = $Trainer/Pokeball
@onready var trainer_sprite = $Trainer/AnimationPlayer
@onready var trainer_pkmn = $YourPokemon
@onready var trainer_pokeball_throw = $Trainer/Pokeball/AnimationPlayer
@onready var trainer_pkmn_drop = $YourPokemon/AnimationPlayer

@onready var oppo_pokeball = $Opponent/Pokeball
@onready var oppo_sprite = $Opponent/AnimationPlayer
@onready var oppo_pkmn = $OpponentPokemon
@onready var oppo_pkmn_drop = $OpponentPokemon/AnimationPlayer

@onready var camera = $Camera3D/AnimationPlayer

var _sfx_player: AudioStreamPlayer
var _sfx_pkball_throw  = preload("res://sounds/pkball-throw.wav")
var _sfx_pkball_release = preload("res://sounds/pkball-release.wav")

func _ready() -> void:
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.volume_db = -10.0
	add_child(_sfx_player)

	# Opponent Entrance
	camera.play("opponent_entry")
	await camera.animation_finished

	oppo_sprite.play("battle_entry")
	await oppo_sprite.animation_finished
	await get_tree().create_timer(.25).timeout
	oppo_sprite.play("battle_exit")

	# Throws out pokemon
	_sfx_player.stream = _sfx_pkball_throw
	_sfx_player.play()
	oppo_pokeball.visible = true
	oppo_pokeball.play("throw")
	await get_tree().create_timer(.75).timeout
	_sfx_player.stream = _sfx_pkball_release
	_sfx_player.play()
	var BattleUI = preload("res://scripts/battle_ui.gd")
	BattleUI.spawn_pokeball_burst(self, oppo_pkmn.global_position)
	oppo_pokeball.visible = false
	oppo_pkmn.visible = true
	await get_tree().create_timer(.2).timeout
	oppo_pkmn_drop.play("pkmn_entry")
	await oppo_pkmn_drop.animation_finished
	await get_tree().create_timer(.5).timeout

	# Trainer Entrance
	camera.play("player_entry")
	await camera.animation_finished
	trainer_sprite.play("battle_entry")
	await get_tree().create_timer(1).timeout

	# Throws out pokemon
	_sfx_player.stream = _sfx_pkball_throw
	_sfx_player.play()
	trainer_pokeball_throw.play("trainer_throw")
	trainer_pokeball.visible = true
	trainer_pokeball.flip_v = true
	trainer_pokeball.play("throw")
	await trainer_sprite.animation_finished

	_sfx_player.stream = _sfx_pkball_release
	_sfx_player.play()
	BattleUI.spawn_pokeball_burst(self, trainer_pkmn.global_position)
	trainer_pokeball.visible = false
	trainer_pkmn.visible = true
	await get_tree().create_timer(.2).timeout
	trainer_pkmn_drop.play("pkmn_entry")
	await trainer_pkmn_drop.animation_finished
	camera.play("default")
