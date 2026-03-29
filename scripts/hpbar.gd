extends TextureProgressBar

@export var green_bar: Texture2D
@export var yellow_bar: Texture2D
@export var red_bar: Texture2D

const TWEEN_DURATION := 0.35
const FLASH_DURATION := 0.8 
const FLASH_CYCLE := 0.10

var damage_flash: ColorRect
var _active_tween: Tween

func _ready():
	value_changed.connect(_on_value_changed)
	damage_flash = ColorRect.new()
	damage_flash.color = Color(0.12, 0.12, 0.12, 1.0)
	damage_flash.modulate.a = 0.0
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(damage_flash)

func _on_value_changed(_new_value: float):
	_update_color()

func _update_color():
	var percent = value / max_value * 100.0
	if percent > 50.0:
		texture_progress = green_bar
	elif percent > 20.0:
		texture_progress = yellow_bar
	else:
		texture_progress = red_bar

func update_hp(current_hp: int, max_hp: int):
	var old_hp = value
	max_value = max_hp

	if _active_tween:
		_active_tween.kill()

	_active_tween = create_tween()
	_active_tween.tween_property(self, "value", current_hp, TWEEN_DURATION)

	if current_hp < old_hp:
		# Position flash overlay over the section of bar being lost
		var bar_w = size.x
		var bar_h = size.y
		damage_flash.offset_left   = (current_hp / float(max_hp)) * bar_w
		damage_flash.offset_right  = (old_hp     / float(max_hp)) * bar_w
		damage_flash.offset_top    = 0.0
		damage_flash.offset_bottom = bar_h
		damage_flash.color         = Color(0.12, 0.12, 0.12, 1.0)
		damage_flash.modulate.a    = 1.0

		var cycles = int(FLASH_DURATION / FLASH_CYCLE)
		var half   = FLASH_CYCLE * 0.5
		for _i in cycles:
			_active_tween.tween_property(damage_flash, "modulate:a", 0.0, half)
			_active_tween.tween_property(damage_flash, "modulate:a", 1.0, half)
		_active_tween.tween_property(damage_flash, "modulate:a", 0.0, half)

func set_hp_instant(current_hp: int, max_hp: int):
	if _active_tween:
		_active_tween.kill()
	max_value = max_hp
	value = current_hp
	damage_flash.modulate.a = 0.0
