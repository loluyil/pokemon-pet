extends Control

@onready var background: TextureRect = $Background
@onready var grid: GridContainer = $Background/VBoxContainer
@onready var back_btn: TextureButton = $Background/BackButton
@onready var summary_menu: Control = $Background/SummaryMenu
@onready var hover_tween: Button = $Background/HoverTween

@onready var action_btns: Control = $"../ActionMenu/Buttons"
@onready var fight_btn: TextureButton = $"../ActionMenu/FightButton"
@onready var battle_sim: Node = $"../../PokemonData"
@onready var battle_ui: Node = $"../.."

@onready var _sfx_player: AudioStreamPlayer = $"../BattleSFX"
@onready var _context_label: Label = $"../ContextLabel"

var _sfx_select = preload("res://sounds/select-button.wav")
var _sfx_back = preload("res://sounds/back-button.wav")

const TYPE_ICON_PATH := "res://images/battle/types/"
const STATUS_ICON_PATH := "res://images/battle/status/"
const SPRITE_PATH := "res://sprites/pokemon/menu_sprites/"
const SUMMARY_SPRITE_PATH := "res://sprites/pokemon/sprites/"
const PARTY_ICON_PATH := "res://images/battle/party/"
const SWITCH_CHARS_PER_SEC := 150.0
const SUMMARY_STAT_KEYS := ["atk", "def", "spa", "spd", "spe"]
const SUMMARY_BATTLE_STAT_KEYS := ["attack", "defense", "sp_atk", "sp_def", "speed"]

var _tex_panel_normal: Texture2D = preload("res://images/battle/party/panel_rect.png")
var _tex_panel_hover: Texture2D = preload("res://images/battle/party/panel_rect_sel.png")
var _tex_panel_faint: Texture2D = preload("res://images/battle/party/panel_rect_faint.png")
var _tex_panel_faint_hover: Texture2D = preload("res://images/battle/party/panel_rect_faint_sel.png")

var _grid_original_x: float
var _grid_original_h_sep: int
var _anim_tween: Tween
var _hovered_index: int = -1
var _mouse_in_zone: bool = false
var _uturn_mode: bool = false
var _faint_mode: bool = false
var _summary_page_index: int = 0

var _fade_rect: ColorRect
var _switch_tween: Tween

var _slots: Array[TextureButton] = []
var _move_names: Array[Label] = []
var _move_pps: Array[Label] = []
var _move_types: Array[TextureRect] = []
var _summary_pages: Array[CanvasItem] = []

var _summary_moves_panel: CanvasItem
var _summary_stats_panel: CanvasItem

var _summary_sprite_nodes: Array[AnimatedSprite2D] = []
var _summary_type_containers: Array[Node] = []

var _summary_name_label: Label
var _summary_level: Label
var _summary_item_label: Label
var _summary_gender_icon: TextureRect
var _stats_hp_bar: TextureProgressBar
var _stats_hp_current: Label
var _stats_hp_divider: Label
var _stats_hp_max: Label
var _stats_stat_labels: Array[Label] = []
var _stats_ev_labels: Array[Label] = []
var _stats_iv_labels: Array[Label] = []
var _ability_name_label: Label
var _ability_desc_label: Label
var _current_ability_desc: String = ""

func _ready():
	visible = false
	_cache_slots()
	_cache_summary_nodes()
	_grid_original_x = grid.position.x
	_grid_original_h_sep = grid.get_theme_constant("h_separation")

	back_btn.pressed.connect(_on_back)
	hover_tween.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for i in _slots.size():
		_slots[i].mouse_entered.connect(_on_slot_hover.bind(i))
		_slots[i].mouse_exited.connect(_on_slot_unhover.bind(i))
		_slots[i].pressed.connect(_on_slot_pressed.bind(i))

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.add_child(_fade_rect)

	_context_label.visible = false
	_apply_summary_page_visibility()

func _cache_slots():
	for i in range(1, 7):
		var slot: TextureButton = grid.get_node_or_null("Pokemon" + str(i))
		if slot:
			_slots.append(slot)

func _cache_summary_nodes():
	_summary_moves_panel = summary_menu.find_child("SummaryMoves*", true, false) as CanvasItem
	_summary_stats_panel = summary_menu.find_child("SummaryStats*", true, false) as CanvasItem

	_summary_pages.clear()
	if _summary_moves_panel:
		_summary_pages.append(_summary_moves_panel)
	if _summary_stats_panel:
		_summary_pages.append(_summary_stats_panel)

	_summary_name_label = summary_menu.get_node_or_null("PokemonName")
	_summary_level = summary_menu.get_node_or_null("Level")
	_summary_item_label = summary_menu.get_node_or_null("Item")
	_summary_gender_icon = summary_menu.find_child("Gender", true, false) as TextureRect

	if _summary_moves_panel:
		_summary_sprite_nodes.append(_summary_moves_panel.get_node_or_null("Pokemon"))
		_summary_type_containers.append(_summary_moves_panel.get_node_or_null("TypeContainer"))
		var move_box: Node = _summary_moves_panel.get_node_or_null("VBoxContainer")
		if move_box:
			for i in range(1, 5):
				var move_root: Node = move_box.get_node_or_null("Move" + str(i))
				if move_root:
					_move_names.append(move_root.get_node_or_null("NameLabel"))
					_move_pps.append(move_root.get_node_or_null("PPLabel"))
					_move_types.append(move_root.get_node_or_null("Type"))

	if _summary_stats_panel:
		_summary_sprite_nodes.append(_summary_stats_panel.get_node_or_null("Pokemon"))
		_summary_type_containers.append(_summary_stats_panel.get_node_or_null("TypeContainer"))

		_stats_hp_bar = _summary_stats_panel.get_node_or_null("YourHPBar")
		var hp_container: Node = _summary_stats_panel.get_node_or_null("HPContainer")
		if hp_container:
			_stats_hp_current = hp_container.get_node_or_null("Attack")
			_stats_hp_divider = hp_container.get_node_or_null("Attack2")
			_stats_hp_max = hp_container.get_node_or_null("Attack3")
		_stats_stat_labels = _collect_stat_labels(_summary_stats_panel.get_node_or_null("StatsContainer"))
		_stats_ev_labels = _collect_stat_labels(_summary_stats_panel.get_node_or_null("EVsContainer"))
		_stats_iv_labels = _collect_stat_labels(_summary_stats_panel.get_node_or_null("IVsContainer"))
		var ability_container: Node = _summary_stats_panel.get_node_or_null("AbilityContainer")
		if ability_container:
			_ability_name_label = ability_container.get_node_or_null("AbilityName")
			_ability_desc_label = ability_container.get_node_or_null("AbilityDesc")

func _collect_stat_labels(container: Node) -> Array[Label]:
	var labels: Array[Label] = []
	if container == null:
		return labels
	for node_name in ["Attack", "Defend", "SpAtk", "SpDef", "Speed"]:
		var label: Label = container.get_node_or_null(node_name)
		labels.append(label)
	return labels

func open():
	_uturn_mode = false
	_faint_mode = false
	_populate()
	summary_menu.visible = false
	_context_label.visible = false
	visible = true
	_fade_in()

func open_for_faint():
	_faint_mode = true
	_uturn_mode = false
	_populate()
	summary_menu.visible = false
	_context_label.visible = false
	visible = true
	_fade_in()

func open_for_uturn():
	_uturn_mode = true
	_faint_mode = false
	_populate()
	summary_menu.visible = false
	_context_label.visible = false
	visible = true
	_fade_in()

func _fade_in():
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.visible = true
	var tween: Tween = create_tween()
	tween.tween_property(_fade_rect, "color:a", 0.0, 0.3).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): _fade_rect.visible = false)

func _on_back():
	if _uturn_mode or _faint_mode:
		return
	_sfx_player.stream = _sfx_back
	_sfx_player.play()
	_hide_summary_instant()
	_hide_context_label()
	visible = false
	action_btns.visible = true
	fight_btn.disabled = false

func _input(event):
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if summary_menu.visible and _summary_pages.size() > 1:
			var hover_rect := Rect2(hover_tween.global_position, hover_tween.size)
			if hover_rect.has_point(event.position):
				_cycle_summary_page(1)

func _process(_delta: float):
	if not visible:
		return
	var mouse_pos: Vector2 = hover_tween.get_local_mouse_position()
	var in_zone: bool = Rect2(Vector2.ZERO, hover_tween.size).has_point(mouse_pos)
	if in_zone and not _mouse_in_zone:
		_mouse_in_zone = true
		_populate_summary(battle_sim.your_active)
		_hovered_index = battle_sim.your_active
		_show_summary()
	elif not in_zone and _mouse_in_zone:
		_mouse_in_zone = false
		if _hovered_index != -1:
			_hovered_index = -1
			_hide_summary()

func _cycle_summary_page(direction: int):
	if _summary_pages.size() <= 1:
		return
	_summary_page_index = posmod(_summary_page_index + direction, _summary_pages.size())
	_apply_summary_page_visibility()

func _apply_summary_page_visibility():
	if _summary_pages.is_empty():
		return
	for i in _summary_pages.size():
		if _summary_pages[i]:
			_summary_pages[i].visible = i == _summary_page_index
	_refresh_context_label()

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
	_hide_context_label()
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

func _populate():
	var team: Array = battle_sim.your_team
	for i in _slots.size():
		var slot: TextureButton = _slots[i]
		if i < team.size():
			_populate_slot(slot, team[i])
			slot.visible = true
		else:
			slot.visible = false

func _populate_slot(slot: TextureButton, mon: Dictionary):
	if mon.get("is_fainted", false):
		slot.texture_normal = _tex_panel_faint
		slot.texture_hover = _tex_panel_faint_hover
		slot.texture_pressed = null
	else:
		slot.texture_normal = _tex_panel_normal
		slot.texture_hover = _tex_panel_hover

	var name_lbl: Label = slot.get_node_or_null("Name")
	if name_lbl:
		name_lbl.text = mon["display_name"]

	var lvl_lbl: Label = slot.get_node_or_null("Level")
	if lvl_lbl:
		lvl_lbl.text = str(int(mon["level"]))

	var hp_lbl: Label = slot.get_node_or_null("HP")
	if hp_lbl:
		hp_lbl.text = str(int(mon["current_hp"])) + " / " + str(int(mon["max_hp"]))

	var hp_bar: TextureProgressBar = slot.get_node_or_null("YourHPBar")
	if hp_bar:
		hp_bar.set_hp_instant(mon["current_hp"], mon["max_hp"])

	var sprite: Sprite2D = slot.get_node_or_null("Pokemon")
	if sprite:
		var tex_path: String = SPRITE_PATH + mon["name"] + ".png"
		if ResourceLoader.exists(tex_path):
			sprite.texture = load(tex_path)

	var item_icon: TextureRect = slot.get_node_or_null("hasItem?")
	if item_icon:
		item_icon.visible = _has_item(mon)

	var gender_icon: TextureRect = slot.get_node_or_null("Gender")
	_set_gender_icon(gender_icon, mon)

	var status_icon: TextureRect = slot.get_node_or_null("Status")
	if status_icon:
		var status_str = "fainted" if mon.get("is_fainted", false) else mon.get("status", "")
		if status_str == "":
			status_icon.visible = false
		else:
			var status_path: String = STATUS_ICON_PATH + _status_to_filename(status_str) + ".png"
			if ResourceLoader.exists(status_path):
				status_icon.texture = load(status_path)
				status_icon.visible = true
			else:
				status_icon.visible = false

func _play_slot_idle(slot: TextureButton):
	if slot == null:
		return
	var anim_player: AnimationPlayer = slot.get_node_or_null("Pokemon/AnimationPlayer")
	if anim_player and anim_player.has_animation("idle"):
		anim_player.play("idle")

func _stop_slot_idle(slot: TextureButton):
	if slot == null:
		return
	var anim_player: AnimationPlayer = slot.get_node_or_null("Pokemon/AnimationPlayer")
	if anim_player:
		anim_player.stop()

func _status_to_filename(status: String) -> String:
	match status:
		"burn":
			return "burn"
		"paralyze":
			return "paralyze"
		"poison", "toxic":
			return "poison"
		"freeze":
			return "frozen"
		"fainted", "sleep":
			return "fainted"
		_:
			return status

func _populate_summary(mon_index: int):
	var team: Array = battle_sim.your_team
	if mon_index < 0 or mon_index >= team.size():
		return

	var mon: Dictionary = team[mon_index]
	_hovered_index = mon_index
	if _summary_name_label:
		_summary_name_label.text = mon["display_name"]
	if _summary_level:
		_summary_level.text = str(int(mon["level"]))

	var item_text: String = "No item"
	if _has_item(mon):
		item_text = mon["item"]
	if _summary_item_label:
		_summary_item_label.text = item_text
	_set_gender_icon(_summary_gender_icon, mon)

	for sprite in _summary_sprite_nodes:
		_set_summary_sprite(sprite, mon["name"])

	for container in _summary_type_containers:
		_populate_type_icons(container, mon.get("types", []))

	_populate_move_summary(mon)
	_populate_stats_summary(mon)
	_refresh_context_label()

func _has_item(mon: Dictionary) -> bool:
	var item_name: String = mon.get("item", "")
	return item_name != "" and item_name != "None"

func _populate_move_summary(mon: Dictionary):
	var moveset: Array = mon.get("moveset", [])
	for i in 4:
		if i < _move_names.size() and i < _move_pps.size() and i < _move_types.size():
			var name_label = _move_names[i]
			var pp_label = _move_pps[i]
			var type_icon = _move_types[i]
			if i < moveset.size():
				var move: Dictionary = moveset[i]
				if name_label:
					name_label.text = _format_display_name(move["name"])
					name_label.visible = true
				if pp_label:
					var cur_pp: int = move.get("current_pp", move.get("max_pp", 35))
					var max_pp: int = move.get("max_pp", 35)
					pp_label.text = "PP " + str(cur_pp) + "/" + str(max_pp)
					pp_label.visible = true
				if type_icon:
					_set_type_icon(type_icon, move.get("type", "normal"))
					type_icon.visible = true
			else:
				if name_label:
					name_label.visible = false
				if pp_label:
					pp_label.visible = false
				if type_icon:
					type_icon.visible = false

func _populate_stats_summary(mon: Dictionary):
	if _stats_hp_bar:
		_stats_hp_bar.set_hp_instant(mon["current_hp"], mon["max_hp"])
	if _stats_hp_current:
		_stats_hp_current.text = str(int(mon["current_hp"]))
	if _stats_hp_divider:
		_stats_hp_divider.text = "/"
	if _stats_hp_max:
		_stats_hp_max.text = str(int(mon["max_hp"]))

	for i in min(_stats_stat_labels.size(), SUMMARY_BATTLE_STAT_KEYS.size()):
		if _stats_stat_labels[i]:
			_stats_stat_labels[i].text = str(int(mon.get(SUMMARY_BATTLE_STAT_KEYS[i], 0)))

	var evs: Dictionary = mon.get("evs", {})
	for i in min(_stats_ev_labels.size(), SUMMARY_STAT_KEYS.size()):
		if _stats_ev_labels[i]:
			_stats_ev_labels[i].text = str(int(evs.get(SUMMARY_STAT_KEYS[i], 0)))

	var ivs: Dictionary = mon.get("ivs", {})
	for i in min(_stats_iv_labels.size(), SUMMARY_STAT_KEYS.size()):
		if _stats_iv_labels[i]:
			_stats_iv_labels[i].text = str(int(ivs.get(SUMMARY_STAT_KEYS[i], 0)))

	var ability_key: String = mon.get("ability", "")
	var ability_entry: Dictionary = {}
	if battle_sim.get("team_gen") != null:
		ability_entry = battle_sim.team_gen.ability_data.get(ability_key, {})
	_current_ability_desc = ability_entry.get("short_effect", "")
	if _ability_name_label:
		_ability_name_label.text = ability_entry.get("display_name", _format_display_name(ability_key))
	if _ability_desc_label:
		_ability_desc_label.text = _current_ability_desc

func _set_gender_icon(icon: TextureRect, mon: Dictionary):
	if icon == null:
		return
	var gender_value: String = String(mon.get("gender", ""))
	var icon_file: String = ""
	if gender_value == "M":
		icon_file = "boy.png"
	elif gender_value == "F":
		icon_file = "girl.png"
	if icon_file == "":
		icon.visible = false
		return
	var icon_path: String = PARTY_ICON_PATH + icon_file
	if ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
		icon.visible = true
	else:
		icon.visible = false

func _set_summary_sprite(sprite: AnimatedSprite2D, mon_name: String):
	if sprite == null:
		return
	var tres_path: String = SUMMARY_SPRITE_PATH + mon_name + "/" + mon_name + "_anim.tres"
	if not ResourceLoader.exists(tres_path):
		sprite.visible = false
		return
	var frames := load(tres_path) as SpriteFrames
	if frames == null or not frames.has_animation("front") or frames.get_frame_count("front") <= 0:
		sprite.visible = false
		return
	var tex := frames.get_frame_texture("front", 0)
	if tex == null or tex.get_width() <= 0:
		sprite.visible = false
		return
	sprite.sprite_frames = frames
	sprite.play("front")
	sprite.visible = true

func _populate_type_icons(container: Node, mon_types: Array):
	if container == null:
		return
	var type1: TextureRect = container.get_node_or_null("Type1")
	var type2: TextureRect = container.get_node_or_null("Type2")
	if type1:
		if mon_types.size() > 0:
			_set_type_icon(type1, mon_types[0])
			type1.visible = true
		else:
			type1.visible = false
	if type2:
		if mon_types.size() > 1:
			_set_type_icon(type2, mon_types[1])
			type2.visible = true
		else:
			type2.visible = false

func _set_type_icon(icon: TextureRect, type_name: String):
	if icon == null:
		return
	var icon_path: String = TYPE_ICON_PATH + String(type_name).to_lower() + ".png"
	if ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)

func _format_display_name(raw_name: String) -> String:
	return raw_name.replace("-", " ").capitalize()

func _on_slot_hover(index: int):
	if not visible or _hovered_index == -1:
		return
	_play_slot_idle(_slots[index])
	_populate_summary(index)

func _on_slot_unhover(index: int):
	if index >= 0 and index < _slots.size():
		_stop_slot_idle(_slots[index])
	if summary_menu.visible:
		_refresh_context_label()

func _show_switch_prompt(index: int):
	var team: Array = battle_sim.your_team
	if index >= team.size():
		return
	if index == battle_sim.your_active or team[index].get("is_fainted", false):
		_hide_context_label()
		return

	var full_text: String = "Do you want to switch into " + team[index]["display_name"] + "?"
	_context_label.text = full_text
	_context_label.visible_ratio = 0.0
	_context_label.visible = true

	if _switch_tween:
		_switch_tween.kill()
	var duration: float = max(full_text.length() / SWITCH_CHARS_PER_SEC, 0.2)
	_switch_tween = create_tween()
	_switch_tween.tween_property(_context_label, "visible_ratio", 1.0, duration)

func _show_bottom_prompt(text: String):
	_context_label.text = text
	_context_label.visible_ratio = 0.0
	_context_label.visible = true

	if _switch_tween:
		_switch_tween.kill()
	var duration: float = max(text.length() / SWITCH_CHARS_PER_SEC, 0.2)
	_switch_tween = create_tween()
	_switch_tween.tween_property(_context_label, "visible_ratio", 1.0, duration)

func _refresh_context_label():
	if not summary_menu.visible or _hovered_index < 0:
		return
	if _summary_stats_panel and _summary_stats_panel.visible and _current_ability_desc != "":
		_show_bottom_prompt(_current_ability_desc)
	else:
		_show_switch_prompt(_hovered_index)

func _hide_context_label():
	if _switch_tween:
		_switch_tween.kill()
		_switch_tween = null
	_context_label.visible = false

func _show_summary():
	summary_menu.visible = true
	_apply_summary_page_visibility()
	if _anim_tween:
		_anim_tween.kill()
	_anim_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(grid, "position:x", _grid_original_x + 260.0, 0.25)
	_anim_tween.tween_method(_set_h_separation, _grid_original_h_sep, _grid_original_h_sep - 40, 0.25)
	summary_menu.modulate.a = 0.0
	_anim_tween.tween_property(summary_menu, "modulate:a", 1.0, 0.2)

func _hide_summary():
	if not summary_menu.visible:
		return
	if _anim_tween:
		_anim_tween.kill()
	_anim_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_anim_tween.tween_property(grid, "position:x", _grid_original_x, 0.2)
	_anim_tween.tween_method(_set_h_separation, _grid_original_h_sep - 40, _grid_original_h_sep, 0.2)
	_anim_tween.tween_property(summary_menu, "modulate:a", 0.0, 0.15)
	_anim_tween.chain().tween_callback(func(): summary_menu.visible = false)

func _hide_summary_instant():
	summary_menu.visible = false
	summary_menu.modulate.a = 0.0
	grid.position.x = _grid_original_x
	grid.add_theme_constant_override("h_separation", _grid_original_h_sep)
	_hovered_index = -1
	_mouse_in_zone = false
	_hide_context_label()

func _set_h_separation(value: int):
	grid.add_theme_constant_override("h_separation", value)
