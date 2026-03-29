extends TextureRect

var base_scale := Vector2(2, 2)
var hover_scale: Vector2
var base_pivot_y := 370
var hover_pivot_y := 330
var tween: Tween

func _ready():
	base_scale = scale
	hover_scale = scale * 1.25
	pivot_offset.y = base_pivot_y
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _on_mouse_entered():
	if tween:
		tween.kill()
	tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", hover_scale, 0.15)
	tween.tween_property(self, "pivot_offset:y", hover_pivot_y, 0.15)

func _on_mouse_exited():
	if tween:
		tween.kill()
	tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", base_scale, 0.1)
	tween.tween_property(self, "pivot_offset:y", base_pivot_y, 0.1)
