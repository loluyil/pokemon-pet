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

func _ready() -> void:
	# Opponent Entrance
	camera.play("opponent_entry")
	await camera.animation_finished
	
	oppo_sprite.play("battle_entry")
	await oppo_sprite.animation_finished
	oppo_sprite.play("battle_exit")
	
	# Throws out pokemon
	oppo_pokeball.visible = true
	oppo_pokeball.play("throw")
	await get_tree().create_timer(.75).timeout
	oppo_pokeball.visible = false
	oppo_pkmn.visible = true
	await get_tree().create_timer(.2).timeout
	oppo_pkmn_drop.play("pkmn_entry")
	await oppo_pkmn_drop.animation_finished
	oppo_pkmn.play("default")
	await get_tree().create_timer(.5).timeout
	
	# Trainer Entrance
	camera.play("player_entry")
	await camera.animation_finished
	trainer_sprite.play("battle_entry")
	await get_tree().create_timer(1).timeout
	
	# Throws out pokemon
	trainer_pokeball_throw.play("trainer_throw")
	trainer_pokeball.visible = true
	trainer_pokeball.flip_v = true
	trainer_pokeball.play("throw")
	await trainer_sprite.animation_finished
	
	trainer_pkmn.visible = true
	await get_tree().create_timer(.2).timeout
	trainer_pkmn_drop.play("pkmn_entry")
	await trainer_pkmn_drop.animation_finished
	trainer_pkmn.play("default")
	camera.play("default")
	
	
	
