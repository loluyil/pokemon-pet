extends Control

# ─── Node References ─────────────────────────────────────────────────────────
@onready var background: TextureRect = $Background
@onready var grid: GridContainer = $Background/VBoxContainer
@onready var back_btn: TextureButton = $Background/BackButton

@onready var action_btns: Control = $"../ActionMenu/Buttons"
@onready var fight_btn: TextureButton = $"../ActionMenu/FightButton"
@onready var battle_sim: Node = $"../../PokemonData"

@onready var _sfx_player: AudioStreamPlayer = $"../BattleSFX"
var _sfx_select = preload("res://sounds/select-button.wav")
var _sfx_back = preload("res://sounds/back-button.wav")

const TYPE_ICON_PATH := "res://sprites/battle/types/"
const STATUS_ICON_PATH := "res://images/battle/status/"
const SPRITE_PATH := "res://sprites/pokemon/menu_sprites/"

# ─── Summary UI (built at runtime) ──────────────────────────────────────────
var _summary_panel: PanelContainer
var _summary_move_btns: Array[TextureRect] = []
var _summary_move_names: Array[Label] = []
var _summary_move_pps: Array[Label] = []
var _summary_level_label: Label
var _summary_item_label: Label
var _summary_built := false

# ─── Animation state ─────────────────────────────────────────────────────────
var _grid_original_x: float
var _summary_hidden_x: float
var _summary_shown_x: float
var _anim_tween: Tween
var _hovered_index := -1

# ─── Slot cache ──────────────────────────────────────────────────────────────
var _slots: Array[TextureButton] = []

# ─── Ready ───────────────────────────────────────────────────────────────────
func _ready():
	visible = false
	_cache_slots()
	back_btn.pressed.connect(_on_back)

	for i in _slots.size():
		_slots[i].mouse_entered.connect(_on_slot_hover.bind(i))
		_slots[i].mouse_exited.connect(_on_slot_unhover.bind(i))

func _cache_slots():
	for i in range(1, 7):
		var slot = grid.get_node_or_null("Pokemon" + str(i))
		if slot:
			_slots.append(slot)

# ─── Open / Close ────────────────────────────────────────────────────────────
func open():
	_populate()
	visible = true
	_tween_slots_in()

func _on_back():
	_sfx_player.stream = _sfx_back
	_sfx_player.play()
	_hide_summary_instant()
	visible = false
	action_btns.visible = true
	fight_btn.disabled = false

func _input(event):
	if event.is_action_pressed("ui_cancel") and visible:
		_on_back()

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

	# Status icon
	var status_icon: TextureRect = slot.get_node_or_null("Status")
	if status_icon:
		var status_str: String = mon.get("status", "")
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
		"sleep": return "fainted"  # no sleep icon — use fainted as fallback
		_: return status

# ─── Tween slots in ──────────────────────────────────────────────────────────
func _tween_slots_in():
	var tween := create_tween().set_parallel(true)
	for i in _slots.size():
		if not _slots[i].visible:
			continue
		_slots[i].scale = Vector2.ZERO
		_slots[i].pivot_offset = _slots[i].size / 2.0
		tween.tween_property(_slots[i], "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_OUT) \
			.set_delay(i * 0.04)

# ─── Summary Panel (built once) ─────────────────────────────────────────────
func _build_summary():
	if _summary_built:
		return
	_summary_built = true

	_summary_panel = PanelContainer.new()
	_summary_panel.name = "SummaryMenu"

	# Style: semi-transparent dark panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.18, 0.92)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_summary_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_summary_panel.add_child(vbox)

	# Level label
	_summary_level_label = Label.new()
	_summary_level_label.add_theme_font_size_override("font_size", 20)
	_summary_level_label.add_theme_color_override("font_color", Color(1, 1, 1))
	vbox.add_child(_summary_level_label)

	# Separator
	vbox.add_child(HSeparator.new())

	# Moves heading
	var moves_heading := Label.new()
	moves_heading.text = "MOVES"
	moves_heading.add_theme_font_size_override("font_size", 16)
	moves_heading.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6))
	vbox.add_child(moves_heading)

	# 4 move rows
	for i in 4:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		vbox.add_child(hbox)

		# Type icon
		var type_icon := TextureRect.new()
		type_icon.custom_minimum_size = Vector2(48, 20)
		type_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		type_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		hbox.add_child(type_icon)
		_summary_move_btns.append(type_icon)

		var info_vbox := VBoxContainer.new()
		info_vbox.add_theme_constant_override("separation", 0)
		hbox.add_child(info_vbox)

		# Move name
		var name_lbl := Label.new()
		name_lbl.add_theme_font_size_override("font_size", 18)
		name_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		info_vbox.add_child(name_lbl)
		_summary_move_names.append(name_lbl)

		# PP label
		var pp_lbl := Label.new()
		pp_lbl.add_theme_font_size_override("font_size", 14)
		pp_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		info_vbox.add_child(pp_lbl)
		_summary_move_pps.append(pp_lbl)

	# Separator before item
	vbox.add_child(HSeparator.new())

	# Item label
	_summary_item_label = Label.new()
	_summary_item_label.add_theme_font_size_override("font_size", 18)
	_summary_item_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	vbox.add_child(_summary_item_label)

	# Add to Background so it's positioned relative to the party menu
	background.add_child(_summary_panel)

	# Position to the left of the grid, hidden offscreen initially
	_summary_panel.position = Vector2(grid.position.x - 260, grid.position.y)
	_summary_panel.visible = false

	# Store positions for animation
	_grid_original_x = grid.position.x
	_summary_hidden_x = _grid_original_x - 260
	_summary_shown_x = 10.0

func _populate_summary(mon_index: int):
	var team: Array = battle_sim.your_team
	if mon_index >= team.size():
		return

	var mon: Dictionary = team[mon_index]
	var moveset: Array = mon["moveset"]

	_summary_level_label.text = "Lv. " + str(int(mon["level"]))

	for i in 4:
		if i < moveset.size():
			var move: Dictionary = moveset[i]

			# Move name
			_summary_move_names[i].text = move["name"].replace("-", " ").capitalize()
			_summary_move_names[i].visible = true

			# PP
			var cur_pp: int = move.get("current_pp", move.get("max_pp", 35))
			var max_pp: int = move.get("max_pp", 35)
			_summary_move_pps[i].text = "PP " + str(cur_pp) + "/" + str(max_pp)
			_summary_move_pps[i].visible = true

			# Type icon
			var type_name: String = (move.get("type", "normal") as String).to_lower()
			var icon_path := TYPE_ICON_PATH + type_name + ".png"
			if ResourceLoader.exists(icon_path):
				_summary_move_btns[i].texture = load(icon_path)
			else:
				_summary_move_btns[i].texture = null
			_summary_move_btns[i].visible = true
		else:
			_summary_move_names[i].visible = false
			_summary_move_pps[i].visible = false
			_summary_move_btns[i].visible = false

	# Item
	var item_str: String = mon.get("item", "")
	if item_str == "" or item_str == "None":
		_summary_item_label.text = "No item"
	else:
		_summary_item_label.text = item_str

# ─── Hover / Unhover ────────────────────────────────────────────────────────
func _on_slot_hover(index: int):
	if not visible:
		return
	_build_summary()
	_populate_summary(index)
	_hovered_index = index
	_show_summary()

func _on_slot_unhover(index: int):
	if _hovered_index == index:
		_hovered_index = -1
		_hide_summary()

func _show_summary():
	_summary_panel.visible = true
	if _anim_tween:
		_anim_tween.kill()
	_anim_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Slide grid to the right
	_anim_tween.tween_property(grid, "position:x", _grid_original_x + 180.0, 0.25)
	# Slide summary panel in from the left
	_summary_panel.modulate.a = 0.0
	_anim_tween.tween_property(_summary_panel, "modulate:a", 1.0, 0.2)
	_summary_panel.position.x = _summary_shown_x

func _hide_summary():
	if not _summary_built or not _summary_panel.visible:
		return
	if _anim_tween:
		_anim_tween.kill()
	_anim_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	# Slide grid back
	_anim_tween.tween_property(grid, "position:x", _grid_original_x, 0.2)
	# Fade out summary
	_anim_tween.tween_property(_summary_panel, "modulate:a", 0.0, 0.15)
	_anim_tween.chain().tween_callback(func(): _summary_panel.visible = false)

func _hide_summary_instant():
	if not _summary_built:
		return
	_summary_panel.visible = false
	_summary_panel.modulate.a = 0.0
	grid.position.x = _grid_original_x
	_hovered_index = -1
