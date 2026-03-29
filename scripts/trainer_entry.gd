extends Sprite3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$AnimationPlayer.play("battle_entry")
	await get_tree().create_timer(1.0).timeout
	$AnimationPlayer.play("battle_exit")
	
