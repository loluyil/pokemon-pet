extends Control

# ─── Node References ─────────────────────────────────────────────────────────
@onready var background: TextureRect = $Background
@onready var grid: GridContainer = $Background/VBoxContainer
@onready var back_btn: TextureButton = $Background/BackButton

@onready var action_btns: Control = $"../ActionMenu/Buttons"
@onready var fight_btn: TextureButton = $"../ActionMenu/FightButton"
@onready var battle_sim: Node = $"../../PokemonData"
@onready var battle_ui: Node = $"../.."

@onready var _sfx_player: AudioStreamPlayer = $"../BattleSFX"
var _sfx_select = preload("res://sounds/select-button.wav")
var _sfx_back = preload("res://sounds/back-button.wav")

const TYPE_ICON_PATH := "res://images/battle/types/"
const STATUS_ICON_PATH := "res://images/battle/status/"
const SPRITE_PATH := "res://sprites/pokemon/menu_sprites/"

var _tex_panel_normal: Texture2D = preload("res://images/battle/party/panel_rect.png")
var _tex_panel_hover: Texture2D = preload("res://images/battle/party/panel_rect_sel.png")
var _tex_panel_faint: Texture2D = preload("res://images/battle/party/panel_rect_faint.png")
var _tex_panel_faint_hover: Texture2D = preload("res://images/battle/party/panel_rect_faint_sel.png")

# ─── Summary Menu (scene nodes) ─────────────────────────────────────────────
@onready var summary_menu: Control = $Background/SummaryMenu
@onready var summary_name: Label = $Background/SummaryMenu/SummaryMoves/PokemonName
@onready var summary_level: Label = $Background/SummaryMenu/Level
@onready var summary_item: Label = $Background/SummaryMenu/SummaryMoves/Item
@onready var summary_pokemon_sprite: AnimatedSprite2D = $Background/SummaryMenu/SummaryMoves/Pokemon

@onready var hover_tween: Button = $Background/HoverTween
@onready var summary_moves_vbox: VBoxContainer = $Background/SummaryMenu/SummaryMoves/VBoxContainer
@onready var summary_move1_name: Label = $Background/SummaryMenu/SummaryMoves/VBoxContainer/Move1/NameLabel
@onready var summary_move1_pp: Label = $Background/SummaryMenu/SummaryMoves/VBoxContainer/Move1/PPLabel
@onready var summary_move1_type: TextureRect = $Background/SummaryMenu/SummaryMoves/VBoxContainer/Move1/Type
@onready var summary_move2_name: Label = $Background/SummaryMenu/SummaryMoves/VBoxContainer/Move2/NameLabel
@onready var summary_move2_pp: Label = $Background/SummaryMenu/SummaryMoves/VBoxContainer/Move2/PPLabel
@onready var summary_move2_type: TextureRect = $Background/SummaryMenu/SummaryMoves/VBoxContainer/Move2/Type
@onready var summary_move3_name: Label = $Background/SummaryMenu/SummaryMoves/VBoxContainer/Move3/NameLabel
@onready var summary_move3_pp: Label = $Background/SummaryMenu/SummaryMoves/VBoxContainer/Move3/PPLabel
@onready var summary_move3_type: TextureRect = $Background/SummaryMenu/SummaryMoves/VBoxContainer/Move3/Type
@onready var summary_move4_name: Label = $Background/SummaryMenu/SummaryMoves/VBoxContainer/Move4/NameLabel
@onready var summary_move4_pp: Label = $Background/SummaryMenu/SummaryMoves/VBoxContainer/Move4/PPLabel
@onready var summary_move4_type: TextureRect = $Background/SummaryMenu/SummaryMoves/VBoxContainer/Move4/Type

# ─── Animation state ─────────────────────────────────────────────────────────
var _grid_original_x: float
var _grid_original_h_sep: int
var _anim_tween: Tween
var _hovered_index := -1

# ─── Black fade overlay ─────────────────────────────────────────────────────
var _fade_rect: ColorRect
var _uturn_mode := false
var _faint_mode := false

# ─── "Want to switch?" typewriter label ──────────────────────────────────────
@onready var _switch_label: Label = $"../WantToSwitch?"
var _switch_tween: Tween
const SWITCH_CHARS_PER_SEC := 150.0

# ─── Slot & move arrays (filled in _ready) ──────────────────────────────────
var _slots: Array[TextureButton] = []
var _move_names: Array[Label] = []
var _move_pps: Array[Label] = []
var _move_types: Array[TextureRect] = []

# ─── Ready ───────────────────────────────────────────────────────────────────
func _ready():
	visible = false
	_cache_slots()
	_grid_original_x = grid.position.x
	_grid_original_h_sep = grid.get_theme_constant("h_separation")

	_move_names = [summary_move1_name, summary_move2_name, summary_move3_name, summary_move4_name]
	_move_pps = [summary_move1_pp, summary_move2_pp, summary_move3_pp, summary_move4_pp]
	_move_types = [summary_move1_type, summary_move2_type, summary_move3_type, summary_move4_type]

	back_btn.pressed.connect(_on_back)

	# HoverTween is invisible to the mouse — we poll its rect manually in _process
	# so it never blocks clicks on the Pokemon buttons underneath.
	hover_tween.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Individual slots update which pokemon the summary displays + handle switching
	for i in _slots.size():
		_slots[i].mouse_entered.connect(_on_slot_hover.bind(i))
		_slots[i].pressed.connect(_on_slot_pressed.bind(i))

	# Create black fade overlay
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.add_child(_fade_rect)

	_switch_label.visible = false

func _cache_slots():
	for i in range(1, 7):
		var slot = grid.get_node_or_null("Pokemon" + str(i))
		if slot:
			_slots.append(slot)

# ─── Open / Close ────────────────────────────────────────────────────────────
func open():
	_uturn_mode = false
	_faint_mode = false
	_populate()
	summary_menu.visible = false
	_switch_label.visible = false
	visible = true
	_fade_in()

func open_for_faint():
	_faint_mode = true
	_uturn_mode = false
	_populate()
	summary_menu.visible = false
	_switch_label.visible = false
	visible = true
	_fade_in()

func open_for_uturn():
	_uturn_mode = true
	_faint_mode = false
	_populate()
	summary_menu.visible = false
	_switch_label.visible = false
	visible = true
	_fade_in()

func _fade_in():
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.visible = true
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 0.0, 0.3).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): _fade_rect.visible = false)

func _on_back():
	if _uturn_mode or _faint_mode:
		return  # Must pick a pokemon
	_sfx_player.stream = _sfx_back
	_sfx_player.play()
	_hide_summary_instant()
	_hide_switch_label()
	visible = false
	action_btns.visible = true
	fight_btn.disabled = false

func _input(event):
	if event.is_action_pressed("ui_cancel") and visible:
		_on_back()

# ─── Slot pressed — switch immediately ──────────────────────────────────────
func _on_slot_pressed(index: int):
	if not visible:
		return
	var team: Array = battle_sim.your_team
	if index >= team.size():
		return
	if index == battle_sim.your_active:
		return
	if team[index].get("is_fainted", false):
		return

	_sfx_player.stream = _sfx_select
	_sfx_player.play()
	_hide_summary_instant()
	_hide_switch_label()
	visible = false

	if _uturn_mode:
		_uturn_mode = false
		battle_ui._on_uturn_switch_picked(index)
	elif _faint_mode:
		_faint_mode = false
		battle_ui._on_faint_switch_picked(index)
	else:
		fight_btn.disabled = true
		battle_sim.execute_switch_turn(index)

# ─── Populate all slots from team data ───────────────────────────────────────
func _populate():
	var team: Array = battle_sim.your_team
	for i in _slots.size():
		var slot := _slots[i]
		if i < team.size():
			_populate_slot(slot, team[i])
			slot.visible = true
		else:
			slot.visible = false

func _populate_slot(slot: TextureButton, mon: Dictionary):
	# Fainted panel swap
	if mon.get("is_fainted", false):
		slot.texture_normal = _tex_panel_faint
		slot.texture_hover = _tex_panel_faint_hover
		slot.texture_pressed = null
	else:
		slot.texture_normal = _tex_panel_normal
		slot.texture_hover = _tex_panel_hover

	# Name
	var name_lbl: Label = slot.get_node_or_null("Name")
	if name_lbl:
		name_lbl.text = mon["display_name"]

	# Level
	var lvl_lbl: Label = slot.get_node_or_null("Level")
	if lvl_lbl:
		lvl_lbl.text = str(int(mon["level"]))

	# HP label  "current / max"
	var hp_lbl: Label = slot.get_node_or_null("HP")
	if hp_lbl:
		hp_lbl.text = str(int(mon["current_hp"])) + " / " + str(int(mon["max_hp"]))

	# HP bar (uses hpbar.gd)
	var hp_bar: TextureProgressBar = slot.get_node_or_null("YourHPBar")
	if hp_bar:
		hp_bar.set_hp_instant(mon["current_hp"], mon["max_hp"])

	# Pokemon sprite
	var sprite: Sprite2D = slot.get_node_or_null("Pokemon")
	if sprite:
		var tex_path: String = SPRITE_PATH + mon["name"] + ".png"
		if ResourceLoader.exists(tex_path):
			sprite.texture = load(tex_path)

	# Item icon — visible only when holding an item
	var item_icon: TextureRect = slot.get_node_or_null("hasItem?")
	if item_icon:
		var has_item: bool = mon.get("item", "") != "" and mon.get("item", "") != "None"
		item_icon.visible = has_item

	# Status icon (fainted overrides other statuses)
	var status_icon: TextureRect = slot.get_node_or_null("Status")
	if status_icon:
		var status_str: String
		if mon.get("is_fainted", false):
			status_str = "fainted"
		else:
			status_str = mon.get("status", "")
		if status_str == "":
			status_icon.visible = false
		else:
			var status_tex_name := _status_to_filename(status_str)
			var status_path := STATUS_ICON_PATH + status_tex_name + ".png"
			if ResourceLoader.exists(status_path):
				status_icon.texture = load(status_path)
				status_icon.visible = true
			else:
				status_icon.visible = false

func _status_to_filename(status: String) -> String:
	match status:
		"burn": return "burn"
		"paralyze": return "paralyze"
		"poison", "toxic": return "poison"
		"freeze": return "frozen"
		"fainted": return "fainted"
		"sleep": return "fainted"  # no sleep icon — use fainted as fallback
		_: return status

# ─── Summary Population ─────────────────────────────────────────────────────
func _populate_summary(mon_index: int):
	var team: Array = battle_sim.your_team
	if mon_index >= team.size():
		return

	var mon: Dictionary = team[mon_index]
	var moveset: Array = mon["moveset"]

	# Name & Level
	summary_name.text = mon["display_name"]
	summary_level.text = str(int(mon["level"]))

	# Front sprite animation
	_set_summary_sprite(mon["name"])

	# Moves 1-4
	for i in 4:
		if i < moveset.size():
			var move: Dictionary = moveset[i]
			_move_names[i].text = move["name"].replace("-", " ").capitalize()
			var cur_pp: int = move.get("current_pp", move.get("max_pp", 35))
			var max_pp: int = move.get("max_pp", 35)
			_move_pps[i].text = "PP " + str(cur_pp) + "/" + str(max_pp)
			var type_name: String = (move.get("type", "normal") as String).to_lower()
			var icon_path := TYPE_ICON_PATH + type_name + ".png"
			if ResourceLoader.exists(icon_path):
				_move_types[i].texture = load(icon_path)
			_move_names[i].visible = true
			_move_pps[i].visible = true
			_move_types[i].visible = true
		else:
			_move_names[i].visible = false
			_move_pps[i].visible = false
			_move_types[i].visible = false

	# Item
	var item_str: String = mon.get("item", "")
	if item_str == "" or item_str == "None":
		summary_item.text = "No item"
	else:
		summary_item.text = item_str

func _set_summary_sprite(mon_name: String):
	var tres_path := "res://sprites/pokemon/sprites/" + mon_name + "/" + mon_name + "_anim.tres"
	if not ResourceLoader.exists(tres_path):
		summary_pokemon_sprite.visible = false
		return
	var frames := load(tres_path) as SpriteFrames
	if frames == null or not frames.has_animation("front") or frames.get_frame_count("front") <= 0:
		summary_pokemon_sprite.visible = false
		return
	var tex := frames.get_frame_texture("front", 0)
	if tex == null or tex.get_width() <= 0:
		summary_pokemon_sprite.visible = false
		return
	summary_pokemon_sprite.sprite_frames = frames
	summary_pokemon_sprite.play("front")
	summary_pokemon_sprite.visible = true

# ─── Hover (poll HoverTween rect, slots update summary content) ─────────────
var _mouse_in_zone := false

func _process(_delta: float):
	if not visible:
		return
	var mouse_pos := hover_tween.get_local_mouse_position()
	var in_zone := Rect2(Vector2.ZERO, hover_tween.size).has_point(mouse_pos)
	if in_zone and not _mouse_in_zone:
		_mouse_in_zone = true
		_populate_summary(battle_sim.your_active)
		_hovered_index = 0
		_show_summary()
	elif not in_zone and _mouse_in_zone:
		_mouse_in_zone = false
		if _hovered_index != -1:
			_hovered_index = -1
			_hide_summary()

func _on_slot_hover(index: int):
	if not visible or _hovered_index == -1:
		return
	_populate_summary(index)
	_show_switch_prompt(index)

# ─── "Want to switch?" typewriter prompt ─────────────────────────────────────
func _show_switch_prompt(index: int):
	var team: Array = battle_sim.your_team
	if index >= team.size():
		return
	# Don't prompt for active or fainted pokemon
	if index == battle_sim.your_active or team[index].get("is_fainted", false):
		_hide_switch_label()
		return

	var full_text: String = "Do you want to switch into " + team[index]["display_name"] + "?"
	_switch_label.text = full_text
	_switch_label.visible_ratio = 0.0
	_switch_label.visible = true

	if _switch_tween:
		_switch_tween.kill()
	var duration: float = max(full_text.length() / SWITCH_CHARS_PER_SEC, 0.2)
	_switch_tween = create_tween()
	_switch_tween.tween_property(_switch_label, "visible_ratio", 1.0, duration)

func _hide_switch_label():
	if _switch_tween:
		_switch_tween.kill()
		_switch_tween = null
	_switch_label.visible = false

func _show_summary():
	summary_menu.visible = true
	if _anim_tween:
		_anim_tween.kill()
	_anim_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Slide grid further right and compress h_separation so summary doesn't overlap
	_anim_tween.tween_property(grid, "position:x", _grid_original_x + 260.0, 0.25)
	_anim_tween.tween_method(_set_h_separation, _grid_original_h_sep, _grid_original_h_sep - 40, 0.25)
	# Fade in summary
	summary_menu.modulate.a = 0.0
	_anim_tween.tween_property(summary_menu, "modulate:a", 1.0, 0.2)

func _hide_summary():
	if not summary_menu.visible:
		return
	if _anim_tween:
		_anim_tween.kill()
	_anim_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	# Slide grid back and restore h_separation
	_anim_tween.tween_property(grid, "position:x", _grid_original_x, 0.2)
	_anim_tween.tween_method(_set_h_separation, _grid_original_h_sep - 40, _grid_original_h_sep, 0.2)
	# Fade out summary
	_anim_tween.tween_property(summary_menu, "modulate:a", 0.0, 0.15)
	_anim_tween.chain().tween_callback(func(): summary_menu.visible = false)

func _hide_summary_instant():
	summary_menu.visible = false
	summary_menu.modulate.a = 0.0
	grid.position.x = _grid_original_x
	grid.add_theme_constant_override("h_separation", _grid_original_h_sep)
	_hovered_index = -1
	_mouse_in_zone = false
	_hide_switch_label()

func _set_h_separation(value: int):
	grid.add_theme_constant_override("h_separation", value)
