extends Node

# ─── HP Bar & Label References ──────────────────────────────────────────────────
@onready var your_hp_bar: TextureProgressBar = $VBoxContainer/TrainerHPContainer/YourHPBar
@onready var your_name_label: Label  = $VBoxContainer/TrainerHPContainer/Name
@onready var your_lvl_label: Label   = $VBoxContainer/TrainerHPContainer/Level
@onready var current_hp_label: Label = $VBoxContainer/TrainerHPContainer/CurrentHP
@onready var max_hp_label: Label     = $VBoxContainer/TrainerHPContainer/MaxHP

@onready var opp_hp_bar: TextureProgressBar = $VBoxContainer/OpponentHPContainer/OpponentHPBar
@onready var opp_name_label: Label = $VBoxContainer/OpponentHPContainer/Name
@onready var opp_lvl_label: Label  = $VBoxContainer/OpponentHPContainer/Level

# ─── Status Icon References ──────────────────────────────────────────────────────
@onready var your_status_icon: TextureRect = $VBoxContainer/TrainerHPContainer/Status
@onready var opp_status_icon: TextureRect  = $VBoxContainer/OpponentHPContainer/Status

const STATUS_ICON_PATH := "res://images/battle/status/"

# ─── Battle Text Box ─────────────────────────────────────────────────────────────
@onready var _text_panel: Control = $VBoxContainer/BattleText
@onready var _msg_label: Label    = $VBoxContainer/BattleText/Label

# ─── Sprite References ───────────────────────────────────────────────────────────
@onready var your_pokemon_sprite: AnimatedSprite3D = $VBoxContainer/SubViewportContainer/SubViewport/BattleEntry/YourPokemon
@onready var opp_pokemon_sprite: AnimatedSprite3D  = $VBoxContainer/SubViewportContainer/SubViewport/BattleEntry/OpponentPokemon

# ─── Menu References ─────────────────────────────────────────────────────────────
@onready var battle_sim: Node = $PokemonData
@onready var _fight_btn       = $Control/ActionMenu/FightButton
@onready var _action_buttons  = $Control/ActionMenu/Buttons

# ─── Sound Effects ───────────────────────────────────────────────────────────────
@onready var _sfx_player: AudioStreamPlayer = $Control/BattleSFX
var _sfx_effective       = preload("res://sounds/effective.wav")
var _sfx_super_effective = preload("res://sounds/super-effective.wav")
var _sfx_not_effective   = preload("res://sounds/not-very-effective.wav")

# ─── Unified Event Queue ─────────────────────────────────────────────────────────
# Events are dicts: {type:"msg", text:""} or {type:"hp", is_yours:bool, hp:int, max:int}
var _event_queue: Array        = []
var _displaying: bool          = false

# ─── Typewriter / Input State ────────────────────────────────────────────────────
var _typing: bool              = false
var _awaiting_input: bool      = false
var _auto_timer: float         = 0.0
var _typewriter_tween: Tween   = null

const CHARS_PER_SEC: float     = 40.0
const AUTO_ADVANCE_SECS: float = 1.6
const HP_ANIM_SECS: float      = 0.42   # slightly longer than hpbar tween (0.35s)

# ─── Ready ───────────────────────────────────────────────────────────────────────
func _ready():
	battle_sim.hp_changed.connect(_on_hp_changed)
	battle_sim.pokemon_sent_out.connect(_on_pokemon_sent_out)
	battle_sim.battle_message.connect(_on_battle_message)
	battle_sim.pokemon_fainted.connect(_on_pokemon_fainted)
	battle_sim.battle_ended.connect(_on_battle_ended)
	battle_sim.attack_effectiveness.connect(_on_attack_effectiveness)
	battle_sim.status_changed.connect(_on_status_changed)

	_text_panel.visible = false
	_init_display()

func _init_display():
	var your_mon = battle_sim.your_team[battle_sim.your_active]
	var opp_mon  = battle_sim.opponent_team[battle_sim.opponent_active]

	your_hp_bar.set_hp_instant(your_mon["current_hp"], your_mon["max_hp"])
	your_name_label.text  = your_mon["display_name"]
	your_lvl_label.text   = str(int(your_mon["level"]))
	current_hp_label.text = str(int(your_mon["current_hp"]))
	max_hp_label.text     = str(int(your_mon["max_hp"]))

	opp_hp_bar.set_hp_instant(opp_mon["current_hp"], opp_mon["max_hp"])
	opp_name_label.text = opp_mon["display_name"]
	opp_lvl_label.text  = str(int(opp_mon["level"]))

	_set_pokemon_sprite(your_pokemon_sprite, your_mon["name"], true)
	_set_pokemon_sprite(opp_pokemon_sprite,  opp_mon["name"],  false)

	_refresh_status_icons()

	# Intro sequence queued manually because start_battle() fires before
	# this script connects its signals (battle_sim._ready runs first).
	_push_message("You are challenged by Trainer!")
	_push_message("Trainer sent out " + opp_mon["display_name"] + "!")
	_push_message("Go! " + your_mon["display_name"] + "!")

func _refresh_status_icons():
	var your_mon = battle_sim.your_team[battle_sim.your_active]
	var opp_mon  = battle_sim.opponent_team[battle_sim.opponent_active]
	_set_status_icon(your_status_icon, your_mon["status"])
	_set_status_icon(opp_status_icon, opp_mon["status"])

func _set_status_icon(icon: TextureRect, status: String):
	if status == "":
		icon.visible = false
		return
	var filename: String
	match status:
		"burn": filename = "burn"
		"paralyze": filename = "paralyze"
		"poison", "toxic": filename = "poison"
		"freeze": filename = "frozen"
		"sleep": filename = "fainted"
		_: filename = status
	var path := STATUS_ICON_PATH + filename + ".png"
	if ResourceLoader.exists(path):
		icon.texture = load(path)
		icon.visible = true
	else:
		icon.visible = false

func _format_name(mon_name: String) -> String:
	return mon_name.replace("-", " ").capitalize()

func _set_pokemon_sprite(sprite: AnimatedSprite3D, mon_name: String, is_back: bool):
	var tres_path := "res://sprites/pokemon/sprites/" + mon_name + "/" + mon_name + "_anim.tres"
	if not ResourceLoader.exists(tres_path):
		return
	sprite.sprite_frames = load(tres_path)
	sprite.play("back" if is_back else "front")

# ─── Signal Handlers ─────────────────────────────────────────────────────────────

func _on_battle_message(text: String):
	_push_message(text)

func _on_status_changed(is_yours: bool, status: String):
	_event_queue.append({"type": "status", "is_yours": is_yours, "status": status})
	if not _displaying:
		_start_display()

func _on_hp_changed(is_yours: bool, current_hp: int, max_hp: int):
	# Deferred: HP animation is sequenced through the event queue so that
	# the first Pokemon's bar finishes before the second move plays out.
	_push_hp(is_yours, current_hp, max_hp)

func _on_pokemon_sent_out(is_yours: bool, current_hp: int, max_hp: int, mon_name: String, level: int, raw_name: String):
	# Queued so it processes after faint messages, preventing the new pokemon's
	# HP bar from being overwritten by the previous pokemon's pending damage events.
	_event_queue.append({"type": "sent_out", "is_yours": is_yours,
		"hp": current_hp, "max": max_hp, "name": mon_name, "level": level, "mon_name": raw_name})
	if not _displaying:
		_start_display()

func _on_pokemon_fainted(_is_yours: bool, _mon_name: String):
	pass  # Faint message queued via battle_message in battle_sim

func _on_battle_ended(_you_won: bool):
	pass  # Win/lose messages queued via battle_message in battle_sim

func _on_attack_effectiveness(effectiveness: float):
	_event_queue.append({"type": "sfx", "effectiveness": effectiveness})
	if not _displaying:
		_start_display()

# ─── Event Queue ─────────────────────────────────────────────────────────────────

func _push_message(text: String):
	_event_queue.append({"type": "msg", "text": text})
	if not _displaying:
		_start_display()

func _push_hp(is_yours: bool, hp: int, max_hp: int):
	_event_queue.append({"type": "hp", "is_yours": is_yours, "hp": hp, "max": max_hp})
	if not _displaying:
		_start_display()

func _start_display():
	_displaying = true
	_action_buttons.visible = false
	_fight_btn.disabled     = true
	_text_panel.visible     = true
	_process_next()

func _process_next():
	if _event_queue.is_empty():
		_end_display()
		return

	var ev: Dictionary = _event_queue.pop_front()
	match ev["type"]:
		"msg":      _do_message(ev["text"])
		"hp":       _do_hp(ev)
		"sent_out": _do_sent_out(ev)
		"sfx":      _do_sfx(ev)
		"status":   _do_status(ev)

func _end_display():
	_displaying     = false
	_awaiting_input = false
	_typing         = false
	_text_panel.visible = false
	_refresh_status_icons()
	if not battle_sim.battle_over:
		_action_buttons.visible = true
		_fight_btn.disabled     = false

# ─── Message Event ────────────────────────────────────────────────────────────────

func _do_message(text: String):
	_msg_label.text          = text
	_msg_label.visible_ratio = 0.0
	_typing                  = true
	_awaiting_input          = false
	_auto_timer              = 0.0

	var duration: float = max(text.length() / CHARS_PER_SEC, 0.2)
	if _typewriter_tween:
		_typewriter_tween.kill()
	_typewriter_tween = create_tween()
	_typewriter_tween.tween_property(_msg_label, "visible_ratio", 1.0, duration)
	_typewriter_tween.tween_callback(_on_typewriter_done)

func _on_typewriter_done():
	_typing         = false
	_awaiting_input = true
	_auto_timer     = 0.0

# ─── HP Event (auto-advances after animation) ─────────────────────────────────────

func _do_hp(ev: Dictionary):
	if ev["is_yours"]:
		your_hp_bar.update_hp(ev["hp"], ev["max"])
		current_hp_label.text = str(int(ev["hp"]))
	else:
		opp_hp_bar.update_hp(ev["hp"], ev["max"])
	# Wait for the HP bar tween to finish, then move on automatically.
	get_tree().create_timer(HP_ANIM_SECS).timeout.connect(_process_next, CONNECT_ONE_SHOT)

# ─── Sent-Out Event (instant update, no wait) ────────────────────────────────

func _do_sent_out(ev: Dictionary):
	if ev["is_yours"]:
		your_hp_bar.set_hp_instant(ev["hp"], ev["max"])
		your_name_label.text  = ev["name"]
		your_lvl_label.text   = str(int(ev["level"]))
		current_hp_label.text = str(int(ev["hp"]))
		max_hp_label.text     = str(int(ev["max"]))
		_set_pokemon_sprite(your_pokemon_sprite, ev["mon_name"], true)
	else:
		opp_hp_bar.set_hp_instant(ev["hp"], ev["max"])
		opp_name_label.text = ev["name"]
		opp_lvl_label.text  = str(int(ev["level"]))
		_set_pokemon_sprite(opp_pokemon_sprite, ev["mon_name"], false)
	_refresh_status_icons()
	_process_next()

# ─── SFX Event (plays sound, immediately advances) ──────────────────────────────

func _do_sfx(ev: Dictionary):
	var eff: float = ev["effectiveness"]
	if eff > 1.0:
		_sfx_player.stream = _sfx_super_effective
	elif eff < 1.0:
		_sfx_player.stream = _sfx_not_effective
	else:
		_sfx_player.stream = _sfx_effective
	_sfx_player.play()
	_process_next()

# ─── Status Event (instant update, then advance) ────────────────────────────────

func _do_status(ev: Dictionary):
	var icon: TextureRect = your_status_icon if ev["is_yours"] else opp_status_icon
	_set_status_icon(icon, ev["status"])
	_process_next()

# ─── Advance Logic ────────────────────────────────────────────────────────────────

func _advance():
	if _typing:
		# First press: complete the typewriter instantly
		if _typewriter_tween:
			_typewriter_tween.kill()
		_msg_label.visible_ratio = 1.0
		_typing         = false
		_awaiting_input = true
		_auto_timer     = 0.0
	else:
		_awaiting_input = false
		_auto_timer     = 0.0
		_process_next()

func _process(delta: float):
	if not _awaiting_input:
		return
	_auto_timer += delta
	if _auto_timer >= AUTO_ADVANCE_SECS:
		_advance()

func _input(event: InputEvent):
	if not (_typing or _awaiting_input):
		return
	var pressed: bool = event.is_action_pressed("ui_accept") \
		or (event is InputEventKey         and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT)
	if pressed:
		get_viewport().set_input_as_handled()
		_advance()
