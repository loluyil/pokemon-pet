extends Control

# ─── Node References ─────────────────────────────────────────────────────────
@onready var move1: TextureButton = $GridContainer/Move1
@onready var move2: TextureButton = $GridContainer/Move2
@onready var move3: TextureButton = $GridContainer/Move3
@onready var move4: TextureButton = $GridContainer/Move4
@onready var back_btn = $BackButton

@onready var fight_btn:  TextureButton  = $"../ActionMenu/FightButton"
@onready var bg_anim:    AnimationPlayer = $"../ActionMenu/FightButton/Background/AnimationPlayer"
@onready var action_btns: Control       = $"../ActionMenu/Buttons"
@onready var battle_sim: Node           = $"../../PokemonData"

const TYPE_ICON_PATH := "res://sprites/battle/types/"

@onready var _sfx_player: AudioStreamPlayer = $"../BattleSFX"
var _sfx_select = preload("res://sounds/select-button.wav")
var _sfx_back   = preload("res://sounds/back-button.wav")


# ─── Ready ────────────────────────────────────────────────────────────────────
func _ready():
	move1.pressed.connect(_on_move_selected.bind(0))
	move2.pressed.connect(_on_move_selected.bind(1))
	move3.pressed.connect(_on_move_selected.bind(2))
	move4.pressed.connect(_on_move_selected.bind(3))
	if back_btn:
		back_btn.pressed.connect(_on_back)

# ─── Populate & Tween In ─────────────────────────────────────────────────────
# Called by action_menu.gd after making MoveMenu visible.
# Order: visible=true → populate_moves() → buttons scale 0→1 (pop tween)
func populate_moves():
	var mon     = battle_sim.your_team[battle_sim.your_active]
	var moveset = mon["moveset"]
	var btns    = [move1, move2, move3, move4]
	var choice_locked = mon.get("choice_lock", "")
	var has_choice = choice_locked != "" and battle_sim._is_choice_item(mon.get("item", "")) and battle_sim._can_use_held_item(mon)

	for i in 4:
		var btn: TextureButton = btns[i]
		if i < moveset.size():
			_setup_move_button(btn, moveset[i])
			btn.visible      = true
			btn.scale        = Vector2.ZERO
			btn.pivot_offset = btn.size / 2.0
			# Grey out moves that are locked out by choice item
			if has_choice and moveset[i]["name"] != choice_locked:
				btn.modulate = Color(0.4, 0.4, 0.4, 0.7)
				btn.disabled = true
			else:
				btn.modulate = Color(1, 1, 1, 1)
				btn.disabled = false
		else:
			btn.visible = false

	_tween_buttons_in(btns, moveset.size())

func _setup_move_button(btn: TextureButton, move: Dictionary) -> void:
	# Type PNG replaces the button's normal texture directly
	var type_name: String = (move.get("type", "normal") as String).to_lower()
	var icon_path := TYPE_ICON_PATH + type_name + ".png"
	btn.texture_normal = load(icon_path) if ResourceLoader.exists(icon_path) else null

	# "NameLabel" child Label → move name
	var name_lbl: Label = btn.get_node_or_null("NameLabel")
	if name_lbl:
		name_lbl.text = move["name"].replace("-", " ").capitalize()

	# "PPLabel" child Label → PP X/X
	var pp_lbl: Label = btn.get_node_or_null("PPLabel")
	if pp_lbl:
		var cur: int    = move.get("current_pp", move.get("max_pp", 35))
		var max_pp: int = move.get("max_pp", 35)
		pp_lbl.text = "PP %d/%d" % [cur, max_pp]

func _tween_buttons_in(btns: Array, count: int) -> void:
	# All buttons pop in at the same time
	var tween := create_tween().set_parallel(true)
	for i in count:
		tween.tween_property(btns[i], "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_OUT)

# ─── Move Selected — instant hide, no tween ───────────────────────────────────
func _on_move_selected(index: int):
	_sfx_player.stream = _sfx_select
	_sfx_player.play()
	var opp_move = battle_sim.get_opponent_move()
	battle_sim.execute_turn(index, opp_move)

	await get_tree().create_timer(0.05).timeout
	visible = false
	bg_anim.play_backwards("open")
	# battle_ui.gd re-enables the action menu once the event queue drains.

# ─── Back — instant hide, no tween ───────────────────────────────────────────
func _on_back():
	_sfx_player.stream = _sfx_back
	_sfx_player.play()
	visible = false
	action_btns.visible = true
	bg_anim.play_backwards("open")
	fight_btn.disabled = false

func _input(event):
	if event.is_action_pressed("ui_cancel") and visible:
		_on_back()
