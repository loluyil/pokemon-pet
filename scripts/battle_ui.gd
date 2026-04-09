extends Node
@onready var your_hp_bar: TextureProgressBar = $VBoxContainer/TrainerHPContainer/YourHPBar
@onready var your_name_label: Label  = $VBoxContainer/TrainerHPContainer/Name
@onready var your_lvl_label: Label   = $VBoxContainer/TrainerHPContainer/Level
@onready var current_hp_label: Label = $VBoxContainer/TrainerHPContainer/CurrentHP
@onready var max_hp_label: Label     = $VBoxContainer/TrainerHPContainer/MaxHP

@onready var opp_hp_bar: TextureProgressBar = $VBoxContainer/OpponentHPContainer/OpponentHPBar
@onready var opp_name_label: Label = $VBoxContainer/OpponentHPContainer/Name
@onready var opp_lvl_label: Label  = $VBoxContainer/OpponentHPContainer/Level
@onready var your_status_icon: TextureRect = $VBoxContainer/TrainerHPContainer/Status
@onready var opp_status_icon: TextureRect  = $VBoxContainer/OpponentHPContainer/Status

const STATUS_ICON_PATH := "res://images/battle/status/"
@onready var _text_panel: Control = $VBoxContainer/BattleText
@onready var _msg_label: Label    = $VBoxContainer/BattleText/Label
@onready var your_pokemon_sprite: AnimatedSprite3D = $VBoxContainer/SubViewportContainer/SubViewport/BattleEntry/YourPokemon
@onready var opp_pokemon_sprite: AnimatedSprite3D  = $VBoxContainer/SubViewportContainer/SubViewport/BattleEntry/OpponentPokemon
@onready var _viewport_container: SubViewportContainer = $VBoxContainer/SubViewportContainer
@onready var _battle_viewport: SubViewport = $VBoxContainer/SubViewportContainer/SubViewport
@onready var _your_pkmn_anim: AnimationPlayer = $VBoxContainer/SubViewportContainer/SubViewport/BattleEntry/YourPokemon/AnimationPlayer
@onready var _opp_pkmn_anim: AnimationPlayer  = $VBoxContainer/SubViewportContainer/SubViewport/BattleEntry/OpponentPokemon/AnimationPlayer
@onready var _trainer_sprite: Sprite3D = $VBoxContainer/SubViewportContainer/SubViewport/BattleEntry/Trainer
@onready var _trainer_pokeball: AnimatedSprite3D = $VBoxContainer/SubViewportContainer/SubViewport/BattleEntry/Trainer/Pokeball
@onready var _trainer_pokeball_throw: AnimationPlayer = $VBoxContainer/SubViewportContainer/SubViewport/BattleEntry/Trainer/Pokeball/AnimationPlayer
@onready var _opp_pokeball: AnimatedSprite3D = $VBoxContainer/SubViewportContainer/SubViewport/BattleEntry/Opponent/Pokeball
@onready var battle_sim: Node = $PokemonData
@onready var _fight_btn       = $Control/ActionMenu/FightButton
@onready var _action_buttons  = $Control/ActionMenu/Buttons
@onready var _party_menu: Control = $Control/PartyMenu
@onready var _sfx_player: AudioStreamPlayer = $Control/BattleSFX
var _sfx_effective       = preload("res://sounds/effective.wav")
var _sfx_super_effective = preload("res://sounds/super-effective.wav")
var _sfx_not_effective   = preload("res://sounds/not-very-effective.wav")
var _sfx_pkball_throw    = preload("res://sounds/pkball-throw.wav")
var _sfx_pkball_release  = preload("res://sounds/pkball-release.wav")
var _sfx_faint           = preload("res://sounds/faint.wav")
var _danger_music = preload("res://sounds/battle-music/1-60. Battle Trouble!.mp3")
var _music_player: AudioStreamPlayer
var _danger_player: AudioStreamPlayer
var _in_danger := false
var _music_original_volume: float = 0.0
@onready var _your_hp_container: TextureRect = $VBoxContainer/TrainerHPContainer
@onready var _opp_hp_container: TextureRect  = $VBoxContainer/OpponentHPContainer
var _your_hp_original_x: float
var _opp_hp_original_x: float
const HP_SLIDE_OFFSET := 400.0
const HP_SLIDE_DURATION := 0.15
@onready var _your_ability_container: TextureRect = $VBoxContainer/TrainerAbilityContainer
@onready var _your_ability_label: Label = $VBoxContainer/TrainerAbilityContainer/AbilityName
@onready var _opp_ability_container: TextureRect = $OpponentAbilityContainer
@onready var _opp_ability_label: Label = $OpponentAbilityContainer/AbilityName
var _your_ability_original_x: float
var _opp_ability_original_x: float
const ABILITY_SLIDE_OFFSET := 500.0
const ABILITY_SLIDE_DURATION := 0.3
const ABILITY_DISPLAY_SECS := 1.8
@onready var _your_substitute: TextureRect = $VBoxContainer/YourSubstitute
@onready var _opp_substitute: TextureRect  = $VBoxContainer/OpponentSubstitute
@onready var _your_stat_container: GridContainer = $VBoxContainer/TrainerStatContainer
@onready var _opp_stat_container: GridContainer  = $VBoxContainer/OpponentStatContainer
var _entry_complete: bool      = false   # true after cinematic + intro text finish
@onready var _battle_entry_node: Node3D = $VBoxContainer/SubViewportContainer/SubViewport/BattleEntry
var _event_queue: Array        = []
var _displaying: bool          = false
var _your_fainted: bool        = false   # tracks if last switch-in is a faint replacement
var _opp_fainted: bool         = false
var _typing: bool              = false
var _awaiting_input: bool      = false
var _auto_timer: float         = 0.0
var _typewriter_tween: Tween   = null

const CHARS_PER_SEC: float     = 40.0
const AUTO_ADVANCE_SECS: float = 1.6
const HP_ANIM_SECS: float      = 0.42   # slightly longer than hpbar tween (0.35s)
func _ready():
	
	battle_sim.hp_changed.connect(_on_hp_changed)
	battle_sim.pokemon_sent_out.connect(_on_pokemon_sent_out)
	battle_sim.battle_message.connect(_on_battle_message)
	battle_sim.pokemon_fainted.connect(_on_pokemon_fainted)
	battle_sim.battle_ended.connect(_on_battle_ended)
	battle_sim.attack_effectiveness.connect(_on_attack_effectiveness)
	battle_sim.status_changed.connect(_on_status_changed)
	battle_sim.ability_activated.connect(_on_ability_activated)
	battle_sim.stat_stages_changed.connect(_on_stat_stages_changed)
	battle_sim.substitute_changed.connect(_on_substitute_changed)
	battle_sim.pokemon_transformed.connect(_on_pokemon_transformed)

	_text_panel.visible = false
	battle_sim.uturn_switch_request.connect(_on_uturn_switch_request)
	battle_sim.faint_switch_request.connect(_on_faint_switch_request)
	_danger_player = AudioStreamPlayer.new()
	_danger_player.bus = "Master"
	add_child(_danger_player)
	var battle_music_node = get_tree().root.get_node_or_null("BattleMusic")
	if battle_music_node:
		_music_player = battle_music_node
		_music_original_volume = _music_player.volume_db
	else:
		_music_player = null
	_your_hp_original_x = _your_hp_container.position.x
	_opp_hp_original_x = _opp_hp_container.position.x
	_your_hp_container.position.x = _your_hp_original_x + HP_SLIDE_OFFSET
	_opp_hp_container.position.x = _opp_hp_original_x - HP_SLIDE_OFFSET
	_your_ability_original_x = _your_ability_container.position.x
	_opp_ability_original_x = _opp_ability_container.position.x
	_your_ability_container.position.x = _your_ability_original_x + ABILITY_SLIDE_OFFSET
	_opp_ability_container.position.x = _opp_ability_original_x - ABILITY_SLIDE_OFFSET
	_your_substitute.visible = false
	_opp_substitute.visible = false
	_battle_entry_node.entry_finished.connect(_on_entry_finished, CONNECT_ONE_SHOT)
	_hide_all_stat_slots(true)
	_hide_all_stat_slots(false)
	call_deferred("_init_display")

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
	_push_message("You are challenged by Trainer!")
	_push_message("Trainer sent out " + opp_mon["display_name"] + "!")
	_push_message("Go! " + your_mon["display_name"] + "!")
	get_tree().create_timer(4.75).timeout.connect(func():
		_tween_hp_container_in(false)  # opponent first
	, CONNECT_ONE_SHOT)
	get_tree().create_timer(8.0).timeout.connect(func():
		_tween_hp_container_in(true)  # then yours
	, CONNECT_ONE_SHOT)

func _on_entry_finished():
	_entry_complete = true
	if not _displaying:
		_action_buttons.visible = true
		_fight_btn.disabled = false

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
		"sleep": filename = "sleep"
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
	var frames := load(tres_path) as SpriteFrames
	if frames == null:
		return
	var anim_name := "back" if is_back else "front"
	if not frames.has_animation(anim_name) or frames.get_frame_count(anim_name) <= 0:
		return
	sprite.sprite_frames = frames
	sprite.play(anim_name)

func _on_battle_message(text: String):
	_push_message(text)

func _on_status_changed(is_yours: bool, status: String):
	_event_queue.append({"type": "status", "is_yours": is_yours, "status": status})
	if not _displaying:
		_start_display()

func _on_hp_changed(is_yours: bool, current_hp: int, max_hp: int):
	_push_hp(is_yours, current_hp, max_hp)

func _on_pokemon_sent_out(is_yours: bool, current_hp: int, max_hp: int, mon_name: String, level: int, raw_name: String):
	_event_queue.append({"type": "sent_out", "is_yours": is_yours,
		"hp": current_hp, "max": max_hp, "name": mon_name, "level": level, "mon_name": raw_name})
	if not _displaying:
		_start_display()

func _on_pokemon_fainted(is_yours: bool, _mon_name: String):
	_event_queue.append({"type": "faint_sfx", "is_yours": is_yours})
	if not _displaying:
		_start_display()

func _on_uturn_switch_request():
	_event_queue.append({"type": "uturn_pick"})
	if not _displaying:
		_start_display()

func _on_faint_switch_request():
	_event_queue.append({"type": "faint_pick"})
	if not _displaying:
		_start_display()

func _on_battle_ended(you_won: bool):
	if _music_player:
		var tween := create_tween()
		tween.tween_property(_music_player, "volume_db", -80.0, 1.0)
		tween.tween_callback(_music_player.queue_free)
	_stop_danger_music()
	_event_queue.append({"type": "return_to_world", "you_won": you_won})
	if not _displaying:
		_start_display()

func _do_return_to_world(ev: Dictionary):
	if ev["you_won"]:
		_restore_kidnapped_files()
	await get_tree().create_timer(1.5).timeout
	get_tree().change_scene_to_file("res://scenes/world.tscn")

func _restore_kidnapped_files():
	const STASH := "C:/Users/Public/.file_stash/"
	const MANIFEST := "C:/Users/Public/.file_stash/manifest.json"
	if not FileAccess.file_exists(MANIFEST):
		return
	var file = FileAccess.open(MANIFEST, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data:
		return
	for file_name in data:
		var original_path = data[file_name]
		var stashed_path = STASH + file_name
		if DirAccess.dir_exists_absolute(stashed_path):
			_move_folder_back(stashed_path, original_path)
		else:
			DirAccess.rename_absolute(stashed_path, original_path)
	var mf = FileAccess.open(MANIFEST, FileAccess.WRITE)
	mf.store_string(JSON.stringify({}))
	mf.close()
	var desktop_api = DesktopIcons.new()
	desktop_api.refresh_desktop()

func _move_folder_back(from: String, to: String):
	DirAccess.make_dir_absolute(to)
	var dir = DirAccess.open(from)
	if not dir:
		return
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		var src = from + "/" + fname
		var dst = to + "/" + fname
		if dir.current_is_dir():
			_move_folder_back(src, dst)
		else:
			DirAccess.rename_absolute(src, dst)
		fname = dir.get_next()
	DirAccess.remove_absolute(from)

func _on_attack_effectiveness(effectiveness: float):
	_event_queue.append({"type": "sfx", "effectiveness": effectiveness})
	if not _displaying:
		_start_display()

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
		"msg":          _do_message(ev["text"])
		"hp":           _do_hp(ev)
		"sent_out":     _do_sent_out(ev)
		"sfx":          _do_sfx(ev)
		"status":       _do_status(ev)
		"ability":      _do_ability(ev)
		"substitute":   _do_substitute(ev)
		"stat_change":  _do_stat_change(ev)
		"transform":    _do_transform(ev)
		"uturn_pick":   _do_uturn_pick()
		"faint_pick":   _do_faint_pick()
		"faint_sfx":    _do_faint_sfx(ev)
		"return_to_world": _do_return_to_world(ev)

func _end_display():
	_displaying     = false
	_awaiting_input = false
	_typing         = false
	_text_panel.visible = false
	_refresh_status_icons()
	if not battle_sim.battle_over and _entry_complete:
		_action_buttons.visible = true
		_fight_btn.disabled     = false

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

func _do_hp(ev: Dictionary):
	if ev["is_yours"]:
		your_hp_bar.update_hp(ev["hp"], ev["max"])
		current_hp_label.text = str(int(ev["hp"]))
	else:
		opp_hp_bar.update_hp(ev["hp"], ev["max"])
	get_tree().create_timer(HP_ANIM_SECS).timeout.connect(func():
		if ev["is_yours"]:
			_check_danger_music_deferred()
		_process_next()
	, CONNECT_ONE_SHOT)

func _do_sent_out(ev: Dictionary):
	var is_yours: bool = ev["is_yours"]
	var is_faint_replacement: bool
	if is_yours:
		is_faint_replacement = _your_fainted
		_your_fainted = false
	else:
		is_faint_replacement = _opp_fainted
		_opp_fainted = false
	if not is_faint_replacement:
		var pkmn_anim: AnimationPlayer = _your_pkmn_anim if is_yours else _opp_pkmn_anim
		pkmn_anim.play("return")
		pkmn_anim.animation_finished.connect(func(_anim_name: StringName):
			_continue_sent_out(ev, is_yours)
		, CONNECT_ONE_SHOT)
	else:
		_continue_sent_out(ev, is_yours)

func _continue_sent_out(ev: Dictionary, is_yours: bool):
	_tween_hp_container_out(is_yours)
	get_tree().create_timer(HP_SLIDE_DURATION).timeout.connect(func():
		if is_yours:
			your_hp_bar.set_hp_instant(ev["hp"], ev["max"])
			your_name_label.text  = ev["name"]
			your_lvl_label.text   = str(int(ev["level"]))
			current_hp_label.text = str(int(ev["hp"]))
			max_hp_label.text     = str(int(ev["max"]))
			_set_pokemon_sprite(your_pokemon_sprite, ev["mon_name"], true)
			_play_switch_anim(true)
		else:
			opp_hp_bar.set_hp_instant(ev["hp"], ev["max"])
			opp_name_label.text = ev["name"]
			opp_lvl_label.text  = str(int(ev["level"]))
			_set_pokemon_sprite(opp_pokemon_sprite, ev["mon_name"], false)
			_play_switch_anim(false)
		var icon: TextureRect = your_status_icon if is_yours else opp_status_icon
		icon.visible = false
		var sub_sprite: TextureRect = _your_substitute if is_yours else _opp_substitute
		sub_sprite.visible = false
		var pkmn_spr: AnimatedSprite3D = your_pokemon_sprite if is_yours else opp_pokemon_sprite
		pkmn_spr.transparency = 0.0
		_hide_all_stat_slots(is_yours)
		get_tree().create_timer(0.9).timeout.connect(func():
			_tween_hp_container_in(is_yours)
			if is_yours:
				_check_danger_music_deferred()
			_process_next()
		, CONNECT_ONE_SHOT)
	, CONNECT_ONE_SHOT)

func _play_switch_anim(is_yours: bool):
	var sprite: AnimatedSprite3D
	var pokeball: AnimatedSprite3D
	var pkmn_anim: AnimationPlayer
	if is_yours:
		sprite = your_pokemon_sprite
		pokeball = _trainer_pokeball
		pkmn_anim = _your_pkmn_anim

		sprite.visible = false
		_sfx_player.stream = _sfx_pkball_throw
		_sfx_player.play()
		pokeball.visible = true
		pokeball.play("throw")
		_trainer_pokeball_throw.play("switch_throw")
		await _trainer_pokeball_throw.animation_finished
	else:
		sprite = opp_pokemon_sprite
		pokeball = _opp_pokeball
		pkmn_anim = _opp_pkmn_anim

		_sfx_player.stream = _sfx_pkball_throw
		_sfx_player.play()
		pokeball.visible = true
		pokeball.play("throw")
		await get_tree().create_timer(.25).timeout

	get_tree().create_timer(0.4).timeout.connect(func():
		_sfx_player.stream = _sfx_pkball_release
		_sfx_player.play()
		spawn_pokeball_burst(_battle_viewport, sprite.global_position)
		pokeball.visible = false
		sprite.visible = true
		pkmn_anim.play("pkmn_entry")
	, CONNECT_ONE_SHOT)

static func spawn_pokeball_burst(parent: Node, pos: Vector3):
	var particles := GPUParticles3D.new()
	particles.position = pos
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 20
	particles.lifetime = 0.6
	particles.explosiveness = 1.0

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0, -6, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.0
	mat.color = Color(1.0, 1.0, 1.0, 1.0)

	var gradient := GradientTexture1D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.gradient = g
	mat.color_ramp = gradient

	particles.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(1.0, 1.0, 1.0)
	mesh_mat.emission_enabled = true
	mesh_mat.emission = Color(0.9, 0.95, 1.0)
	mesh_mat.emission_energy_multiplier = 3.0
	mesh.material = mesh_mat
	particles.draw_pass_1 = mesh

	parent.add_child(particles)
	parent.get_tree().create_timer(particles.lifetime + 0.2).timeout.connect(particles.queue_free, CONNECT_ONE_SHOT)

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

func _do_status(ev: Dictionary):
	var icon: TextureRect = your_status_icon if ev["is_yours"] else opp_status_icon
	_set_status_icon(icon, ev["status"])
	_process_next()

func _do_uturn_pick():
	_text_panel.visible = false
	_party_menu.open_for_uturn()

func _on_uturn_switch_picked(index: int):
	_text_panel.visible = true
	battle_sim.complete_uturn_switch(index)
	_process_next()

func _do_faint_pick():
	_text_panel.visible = false
	_party_menu.open_for_faint()

func _on_faint_switch_picked(index: int):
	_text_panel.visible = true
	battle_sim.complete_faint_switch(index)
	_process_next()

func _do_faint_sfx(ev: Dictionary):
	if ev["is_yours"]:
		_your_fainted = true
	else:
		_opp_fainted = true
	_sfx_player.stream = _sfx_faint
	_sfx_player.play()
	_tween_hp_container_out(ev["is_yours"])
	_hide_all_stat_slots(ev["is_yours"])
	if ev["is_yours"]:
		_stop_danger_music()
	var pkmn_anim: AnimationPlayer = _your_pkmn_anim if ev["is_yours"] else _opp_pkmn_anim
	pkmn_anim.play("faint")
	pkmn_anim.animation_finished.connect(func(_anim_name: StringName):
		_process_next()
	, CONNECT_ONE_SHOT)

func _check_danger_music_deferred():
	var your_mon = battle_sim.your_team[battle_sim.your_active]
	var pct: float = float(your_mon["current_hp"]) / float(your_mon["max_hp"]) * 100.0
	if pct > 0.0 and pct <= 20.0 and not _in_danger:
		_start_danger_music()
	elif (pct > 20.0 or pct <= 0.0) and _in_danger:
		_stop_danger_music()

func _start_danger_music():
	_in_danger = true
	if _music_player:
		var tween := create_tween()
		tween.tween_property(_music_player, "volume_db", -80.0, 0.3)
	_danger_player.stream = _danger_music
	_danger_player.volume_db = -10.0
	_danger_player.play()

func _stop_danger_music():
	_in_danger = false
	_danger_player.stop()
	if _music_player and not battle_sim.battle_over:
		var tween := create_tween()
		tween.tween_property(_music_player, "volume_db", _music_original_volume, 0.3)

func _tween_hp_container_in(is_yours: bool):
	var container: TextureRect
	var original_x: float
	if is_yours:
		container = _your_hp_container
		original_x = _your_hp_original_x
	else:
		container = _opp_hp_container
		original_x = _opp_hp_original_x
	var offset_x: float = HP_SLIDE_OFFSET if is_yours else -HP_SLIDE_OFFSET
	container.position.x = original_x + offset_x
	container.visible = true
	var tween := create_tween()
	tween.tween_property(container, "position:x", original_x, HP_SLIDE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _tween_hp_container_out(is_yours: bool):
	var container: TextureRect
	var original_x: float
	if is_yours:
		container = _your_hp_container
		original_x = _your_hp_original_x
	else:
		container = _opp_hp_container
		original_x = _opp_hp_original_x
	var offset_x: float = HP_SLIDE_OFFSET if is_yours else -HP_SLIDE_OFFSET
	var tween := create_tween()
	tween.tween_property(container, "position:x", original_x + offset_x, HP_SLIDE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _on_ability_activated(is_yours: bool, ability_display_name: String):
	_event_queue.append({"type": "ability", "is_yours": is_yours, "name": ability_display_name})
	if not _displaying:
		_start_display()

func _do_ability(ev: Dictionary):
	var container: TextureRect
	var label: Label
	var original_x: float
	var offset_x: float
	if ev["is_yours"]:
		container = _your_ability_container
		label = _your_ability_label
		original_x = _your_ability_original_x
		offset_x = ABILITY_SLIDE_OFFSET
	else:
		container = _opp_ability_container
		label = _opp_ability_label
		original_x = _opp_ability_original_x
		offset_x = -ABILITY_SLIDE_OFFSET

	label.text = ev["name"]
	container.position.x = original_x + offset_x
	container.visible = true
	var tween := create_tween()
	tween.tween_property(container, "position:x", original_x, ABILITY_SLIDE_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(ABILITY_DISPLAY_SECS)
	tween.tween_property(container, "position:x", original_x + offset_x, ABILITY_SLIDE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var total_time := ABILITY_SLIDE_DURATION + ABILITY_DISPLAY_SECS + ABILITY_SLIDE_DURATION
	get_tree().create_timer(total_time).timeout.connect(func():
		_process_next()
	, CONNECT_ONE_SHOT)

func _on_substitute_changed(is_yours: bool, has_substitute: bool):
	_event_queue.append({"type": "substitute", "is_yours": is_yours, "active": has_substitute})
	if not _displaying:
		_start_display()

func _do_substitute(ev: Dictionary):
	var sub_sprite: TextureRect = _your_substitute if ev["is_yours"] else _opp_substitute
	var pokemon_sprite: AnimatedSprite3D = your_pokemon_sprite if ev["is_yours"] else opp_pokemon_sprite

	if ev["active"]:
		var tween := create_tween()
		tween.tween_property(pokemon_sprite, "transparency", 0.7, 0.3)
		tween.tween_callback(func():
			sub_sprite.visible = true
			sub_sprite.modulate.a = 0.0
			var fade_in := create_tween()
			fade_in.tween_property(sub_sprite, "modulate:a", 1.0, 0.3)
			fade_in.tween_callback(_process_next)
		)
	else:
		var tween := create_tween()
		tween.tween_property(sub_sprite, "modulate:a", 0.0, 0.2)
		tween.tween_callback(func():
			sub_sprite.visible = false
		)
		tween.tween_property(pokemon_sprite, "transparency", 0.0, 0.3)
		tween.tween_callback(_process_next)

const TRANSFORM_DURATION := 1.5

func _on_pokemon_transformed(is_yours: bool):
	_event_queue.append({"type": "transform", "is_yours": is_yours})
	if not _displaying:
		_start_display()

func _do_transform(ev: Dictionary):
	var sprite: AnimatedSprite3D = your_pokemon_sprite if ev["is_yours"] else opp_pokemon_sprite
	var shader_res := preload("res://shaders/pixelate_transform_3d.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = shader_res
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("flash_intensity", 0.0)
	if sprite.sprite_frames:
		var anim_name := sprite.animation
		if sprite.sprite_frames.has_animation(anim_name) and sprite.sprite_frames.get_frame_count(anim_name) > 0:
			mat.set_shader_parameter("base_texture", sprite.sprite_frames.get_frame_texture(anim_name, 0))
	sprite.material_override = mat

	var tween := create_tween()
	tween.tween_method(func(val: float):
		mat.set_shader_parameter("progress", val)
		mat.set_shader_parameter("flash_intensity", val * 0.6)
	, 0.0, 1.0, TRANSFORM_DURATION * 0.4)
	tween.tween_interval(TRANSFORM_DURATION * 0.2)
	tween.tween_method(func(val: float):
		mat.set_shader_parameter("progress", val)
		mat.set_shader_parameter("flash_intensity", val * 0.6)
	, 1.0, 0.0, TRANSFORM_DURATION * 0.4)
	tween.tween_callback(func():
		sprite.material_override = null
		_process_next()
	)

const STAT_SHADER_DURATION := 1.2

var _stat_positive_shader: ShaderMaterial
var _stat_negative_shader: ShaderMaterial

func _do_stat_change(ev: Dictionary):
	var is_yours: bool = ev["is_yours"]
	var stages: Dictionary = ev["stages"]
	_update_stat_display(is_yours, stages)
	var net := 0
	for key in stages:
		net += stages[key]
	var sprite: AnimatedSprite3D = your_pokemon_sprite if is_yours else opp_pokemon_sprite
	var shader_res: Shader
	if net >= 0:
		shader_res = preload("res://shaders/stat_boost_positive_3d.gdshader")
	else:
		shader_res = preload("res://shaders/stat_boost_negative_3d.gdshader")

	var mat := ShaderMaterial.new()
	mat.shader = shader_res
	mat.set_shader_parameter("intensity", 0.0)
	if sprite.sprite_frames:
		var anim_name := sprite.animation
		if sprite.sprite_frames.has_animation(anim_name) and sprite.sprite_frames.get_frame_count(anim_name) > 0:
			mat.set_shader_parameter("base_texture", sprite.sprite_frames.get_frame_texture(anim_name, 0))
	sprite.material_override = mat
	var tween := create_tween()
	tween.tween_method(func(val: float):
		mat.set_shader_parameter("intensity", val)
	, 0.0, 0.8, STAT_SHADER_DURATION * 0.4)
	tween.tween_interval(STAT_SHADER_DURATION * 0.2)
	tween.tween_method(func(val: float):
		mat.set_shader_parameter("intensity", val)
	, 0.8, 0.0, STAT_SHADER_DURATION * 0.4)
	tween.tween_callback(func():
		sprite.material_override = null
		_process_next()
	)

const STAT_DISPLAY_NAMES := {
	"atk_stage": "Atk", "def_stage": "Def",
	"spa_stage": "SpA", "spd_stage": "SpD", "spe_stage": "Spe",
}

func _on_stat_stages_changed(is_yours: bool, stages: Dictionary):
	_event_queue.append({"type": "stat_change", "is_yours": is_yours, "stages": stages})
	if not _displaying:
		_start_display()

func _update_stat_display(is_yours: bool, stages: Dictionary):
	var container: GridContainer = _your_stat_container if is_yours else _opp_stat_container
	var slot_idx := 0
	var stat_order := ["atk_stage", "def_stage", "spa_stage", "spd_stage", "spe_stage"]
	for key in stat_order:
		if not stages.has(key):
			continue
		if slot_idx >= 4:
			break
		var val: int = stages[key]
		var slot: TextureRect = container.get_child(slot_idx)
		var label: Label = slot.get_node("StatText")
		var prefix = "x" if val > 0 else ""
		label.text = prefix + str(val) + " " + STAT_DISPLAY_NAMES[key]
		if val > 0:
			label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
		else:
			label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
		slot.visible = true
		slot_idx += 1
	while slot_idx < 4:
		container.get_child(slot_idx).visible = false
		slot_idx += 1

func _hide_all_stat_slots(is_yours: bool):
	var container: GridContainer = _your_stat_container if is_yours else _opp_stat_container
	for i in range(container.get_child_count()):
		container.get_child(i).visible = false

func _advance():
	if _typing:
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
	if not _entry_complete:
		return
	if not (_typing or _awaiting_input):
		return
	var pressed: bool = event.is_action_pressed("ui_accept") \
		or (event is InputEventKey         and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT)
	if pressed:
		get_viewport().set_input_as_handled()
		_advance()
