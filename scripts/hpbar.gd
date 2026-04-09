extends TextureProgressBar

@export var green_bar: Texture2D
@export var yellow_bar: Texture2D
@export var red_bar: Texture2D

const TWEEN_DURATION := 0.35
const FLASH_DURATION := 0.7
const FLASH_CYCLE    := 0.09

var damage_flash: ColorRect
var _bar_tween:   Tween
var _flash_tween: Tween

func _ready():
	value_changed.connect(_on_value_changed)
	damage_flash = ColorRect.new()
	damage_flash.color        = Color(0.08, 0.08, 0.08, 1.0)
	damage_flash.modulate.a   = 0.0
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(damage_flash)

func _on_value_changed(_v: float):
	_update_color()

func _update_color():
	var pct = value / max_value * 100.0
	if pct > 50.0:
		texture_progress = green_bar
	elif pct > 20.0:
		texture_progress = yellow_bar
	else:
		texture_progress = red_bar

func update_hp(current_hp: int, max_hp: int):
	var old_hp := value
	max_value   = max_hp
	if _bar_tween:
		_bar_tween.kill()
	if _flash_tween:
		_flash_tween.kill()
	damage_flash.modulate.a = 0.0
	_bar_tween = create_tween()
	_bar_tween.tween_property(self, "value", float(current_hp), TWEEN_DURATION)
	if current_hp < old_hp:
		_bar_tween.tween_callback(_start_flash.bind(current_hp, old_hp, max_hp))

func set_hp_instant(current_hp: int, max_hp: int):
	if _bar_tween:
		_bar_tween.kill()
	if _flash_tween:
		_flash_tween.kill()
	max_value           = max_hp
	value               = current_hp
	damage_flash.modulate.a = 0.0

func _start_flash(current_hp: int, old_hp: int, max_hp: int):
	var bar_w := size.x
	var bar_h := size.y
	damage_flash.offset_left   = (current_hp / float(max_hp)) * bar_w
	damage_flash.offset_right  = (old_hp     / float(max_hp)) * bar_w
	damage_flash.offset_top    = 0.0
	damage_flash.offset_bottom = bar_h
	damage_flash.modulate.a    = 1.0

	_flash_tween = create_tween()
	var cycles := int(FLASH_DURATION / FLASH_CYCLE)
	var half   := FLASH_CYCLE * 0.5
	for _i in cycles:
		_flash_tween.tween_property(damage_flash, "modulate:a", 0.0, half)
		_flash_tween.tween_property(damage_flash, "modulate:a", 1.0, half)
	_flash_tween.tween_property(damage_flash, "modulate:a", 0.0, half)
