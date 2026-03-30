extends Node

signal hp_changed(is_yours: bool, current_hp: int, max_hp: int)
signal pokemon_sent_out(is_yours: bool, current_hp: int, max_hp: int, mon_name: String, level: int)
signal battle_message(text: String)
signal pokemon_fainted(is_yours: bool, mon_name: String)
signal battle_ended(you_won: bool)

@export var team_gen_path: NodePath
var team_gen: Node

var your_team: Array = []
var opponent_team: Array = []
var your_active: int = 0
var opponent_active: int = 0
var battle_over: bool = false
var turn_count: int = 0

# Tracks a pending Wish heal for each side (stores HP amount, 0 = none pending)
var wish_pending := {"yours": 0, "opp": 0}

# Protect-class moves that block incoming damage for one turn
const PROTECT_MOVES = ["protect", "detect", "king-s-shield", "spiky-shield", "baneful-bunker"]

# Healing moves: move name → percent of max HP healed
const HEALING_MOVES = {
	"recover": 50, "slack-off": 50, "roost": 50, "milk-drink": 50,
	"softboiled": 50, "heal-order": 50, "morning-sun": 50,
	"synthesis": 50, "moonlight": 50, "swallow": 50,
}

# Pure status-inflicting moves: name → {status, immune_types, powder?}
const STATUS_MOVE_EFFECTS = {
	"toxic":         {"status": "toxic",   "immune_types": ["poison", "steel"]},
	"thunder-wave":  {"status": "paralyze","immune_types": ["electric", "ground"]},
	"will-o-wisp":   {"status": "burn",    "immune_types": ["fire"]},
	"sleep-powder":  {"status": "sleep",   "immune_types": [], "powder": true},
	"spore":         {"status": "sleep",   "immune_types": [], "powder": true},
	"hypnosis":      {"status": "sleep",   "immune_types": []},
	"lovely-kiss":   {"status": "sleep",   "immune_types": []},
	"sing":          {"status": "sleep",   "immune_types": []},
	"poison-powder": {"status": "poison",  "immune_types": ["poison", "steel"], "powder": true},
	"stun-spore":    {"status": "paralyze","immune_types": ["electric"], "powder": true},
	"glare":         {"status": "paralyze","immune_types": []},
	"nuzzle":        {"status": "paralyze","immune_types": ["electric"]},
	"dark-void":     {"status": "sleep",   "immune_types": []},
}

# Status moves that boost the user's own stats
const SELF_STAGE_MOVES = {
	"swords-dance": {"atk_stage": 2},
	"nasty-plot":   {"spa_stage": 2},
	"calm-mind":    {"spa_stage": 1, "spd_stage": 1},
	"bulk-up":      {"atk_stage": 1, "def_stage": 1},
	"dragon-dance": {"atk_stage": 1, "spe_stage": 1},
	"quiver-dance": {"spa_stage": 1, "spd_stage": 1, "spe_stage": 1},
	"shell-smash":  {"atk_stage": 2, "spa_stage": 2, "spe_stage": 2, "def_stage": -1, "spd_stage": -1},
	"agility":      {"spe_stage": 2},
	"rock-polish":  {"spe_stage": 2},
	"amnesia":      {"spd_stage": 2},
	"barrier":      {"def_stage": 2},
	"iron-defense": {"def_stage": 2},
	"cosmic-power": {"def_stage": 1, "spd_stage": 1},
	"work-up":      {"atk_stage": 1, "spa_stage": 1},
	"coil":         {"atk_stage": 1, "def_stage": 1},
	"hone-claws":   {"atk_stage": 1},
	"meditate":     {"atk_stage": 1},
	"sharpen":      {"atk_stage": 1},
	"growth":       {"atk_stage": 1, "spa_stage": 1},
	"minimize":     {"evasion_stage": 2},
	"double-team":  {"evasion_stage": 1},
	"charge":       {"spd_stage": 1},
	"stockpile":    {"def_stage": 1, "spd_stage": 1},
	"defend-order": {"def_stage": 1, "spd_stage": 1},
	"attack-order": {"atk_stage": 1},
}

# Status moves that lower the opponent's stats
const OPP_STAGE_MOVES = {
	"growl":          {"atk_stage": -1},
	"tail-whip":      {"def_stage": -1},
	"leer":           {"def_stage": -1},
	"screech":        {"def_stage": -2},
	"metal-sound":    {"spd_stage": -2},
	"charm":          {"atk_stage": -2},
	"feather-dance":  {"atk_stage": -2},
	"fake-tears":     {"spd_stage": -2},
	"sand-attack":    {"accuracy_stage": -1},
	"smokescreen":    {"accuracy_stage": -1},
	"flash":          {"accuracy_stage": -1},
	"sweet-scent":    {"evasion_stage": -1},
	"tickle":         {"atk_stage": -1, "def_stage": -1},
	"memento":        {"atk_stage": -2, "spa_stage": -2},
}

# Recoil moves: fraction of damage dealt taken back by attacker
const RECOIL_FRACTION = {
	"double-edge": 0.333,
	"flare-blitz": 0.333,
	"brave-bird":  0.333,
	"wood-hammer": 0.333,
	"head-smash":  0.5,
	"volt-tackle": 0.333,
	"take-down":   0.25,
	"submission":  0.25,
	"wild-charge": 0.25,
}

# Moves with elevated critical hit ratio (stage 1 = 1/8 chance instead of 1/24)
const HIGH_CRIT_MOVES = [
	"slash", "cross-chop", "stone-edge", "shadow-claw", "night-slash",
	"psycho-cut", "razor-leaf", "air-cutter", "crabhammer", "karate-chop",
	"blaze-kick", "drill-run", "leaf-blade", "spacial-rend",
]

# Stat drops applied to the attacker after using these moves
const USER_STAGE_AFTER = {
	"close-combat": {"def_stage": -1, "spd_stage": -1},
	"superpower":   {"atk_stage": -1, "def_stage": -1},
	"overheat":     {"spa_stage": -2},
	"draco-meteor": {"spa_stage": -2},
	"leaf-storm":   {"spa_stage": -2},
	"psycho-boost": {"spa_stage": -2},
	"v-create":     {"def_stage": -1, "spd_stage": -1, "spe_stage": -1},
}

func _ready():
	team_gen = get_node(team_gen_path)
	start_battle()

func start_battle():
	var raw_your_team = team_gen.random_team()
	var raw_opponent_team = team_gen.random_team()

	your_team = []
	for raw_mon in raw_your_team:
		your_team.append(build_battle_pokemon(raw_mon))

	opponent_team = []
	for raw_mon in raw_opponent_team:
		opponent_team.append(build_battle_pokemon(raw_mon))

	your_active = 0
	opponent_active = 0
	battle_over = false
	turn_count = 0
	wish_pending = {"yours": 0, "opp": 0}

	var your_mon = your_team[your_active]
	var opp_mon = opponent_team[opponent_active]
	pokemon_sent_out.emit(true,  your_mon["current_hp"], your_mon["max_hp"], your_mon["display_name"], your_mon["level"])
	pokemon_sent_out.emit(false, opp_mon["current_hp"],  opp_mon["max_hp"],  opp_mon["display_name"],  opp_mon["level"])

	print_teams()

func calc_hp(base: int, iv: int, ev: int, level: int) -> int:
	return int(floor((2.0 * base + iv + floor(ev / 4.0)) * level / 100.0) + level + 10)

func calc_stat(base: int, iv: int, ev: int, level: int) -> int:
	return int(floor((floor((2.0 * base + iv + floor(ev / 4.0)) * level / 100.0) + 5) * 1.0))

func build_battle_pokemon(raw: Dictionary) -> Dictionary:
	var ivs = raw["ivs"]
	var evs = raw["evs"]
	var level = raw["level"]

	var hp = calc_hp(raw["base_hp"], ivs["hp"], evs["hp"], level)
	if raw["name"] == "shedinja":
		hp = 1

	return {
		"name": raw["name"],
		"display_name": _format_name(raw["name"]),
		"level": level,
		"types": raw["types"],
		"ability": raw["ability"],
		"item": raw["item"],
		"role": raw["role"],
		"moveset": raw["moveset"],
		"move_names": raw["move_names"],
		"max_hp": hp,
		"current_hp": hp,
		"attack":  calc_stat(raw["base_attack"],  ivs["atk"], evs["atk"], level),
		"defense": calc_stat(raw["base_defense"], ivs["def"], evs["def"], level),
		"sp_atk":  calc_stat(raw["base_sp_atk"],  ivs["spa"], evs["spa"], level),
		"sp_def":  calc_stat(raw["base_sp_def"],  ivs["spd"], evs["spd"], level),
		"speed":   calc_stat(raw["base_speed"],   ivs["spe"], evs["spe"], level),
		"atk_stage": 0,
		"def_stage": 0,
		"spa_stage": 0,
		"spd_stage": 0,
		"spe_stage": 0,
		"accuracy_stage": 0,
		"evasion_stage": 0,
		"status": "",
		"toxic_counter": 0,
		"is_fainted": false,
		"is_protected": false,
		"protect_consecutive": 0,
		"last_move_used": "",
		"sleep_turns": 0,
	}

func get_stat_multiplier(stage: int) -> float:
	if stage >= 0:
		return (2.0 + stage) / 2.0
	else:
		return 2.0 / (2.0 - stage)

func get_effective_stat(mon: Dictionary, stat_name: String) -> int:
	var base_val = mon[stat_name]
	var stage_key = ""
	match stat_name:
		"attack":  stage_key = "atk_stage"
		"defense": stage_key = "def_stage"
		"sp_atk":  stage_key = "spa_stage"
		"sp_def":  stage_key = "spd_stage"
		"speed":   stage_key = "spe_stage"

	if stage_key == "":
		return base_val

	return int(base_val * get_stat_multiplier(mon[stage_key]))

# Apply stat stage changes to a Pokemon, clamped to [-6, 6], with battle messages.
func apply_stages(mon: Dictionary, stages: Dictionary, is_yours: bool):
	for stat_key in stages:
		var change = stages[stat_key]
		var old_stage = mon[stat_key]
		mon[stat_key] = clampi(mon[stat_key] + change, -6, 6)
		var actual = mon[stat_key] - old_stage
		if actual == 0:
			battle_message.emit(mon["display_name"] + "'s stats won't go any further!")
			continue
		var stat_display = stat_key.replace("_stage", "").to_upper()
		var direction = "rose" if actual > 0 else "fell"
		var magnitude = ""
		match abs(actual):
			2: magnitude = " sharply"
			3: magnitude = " drastically"
		battle_message.emit(mon["display_name"] + "'s " + stat_display + magnitude + " " + direction + "!")

func is_critical_hit(move: Dictionary) -> bool:
	# Stage 0 = 1/24, Stage 1 (high-crit moves) = 1/8
	var threshold = 8 if move["name"] in HIGH_CRIT_MOVES else 24
	return randi() % threshold == 0

func calculate_damage(attacker: Dictionary, defender: Dictionary, move: Dictionary) -> Dictionary:
	if move["category"] == "status" or move["power"] == 0:
		return {"damage": 0, "crit": false}

	var level = attacker["level"]
	var power = move["power"]
	var crit = is_critical_hit(move)

	var atk: float
	var def_stat: float
	if move["category"] == "physical":
		atk = get_effective_stat(attacker, "attack")
		def_stat = get_effective_stat(defender, "defense")
		# Burn halves attack, but not on a crit (crits ignore negative stat changes,
		# but burn is a condition — in Gen 6+ burn still applies on crits)
		if attacker["status"] == "burn":
			atk *= 0.5
	else:
		atk = get_effective_stat(attacker, "sp_atk")
		def_stat = get_effective_stat(defender, "sp_def")

	# Crits use attacker's stat ignoring negative stages, defender's ignoring positive stages
	if crit:
		if move["category"] == "physical":
			atk = max(attacker["attack"] * (0.5 if attacker["status"] == "burn" else 1.0),
				get_effective_stat(attacker, "attack") * (0.5 if attacker["status"] == "burn" else 1.0))
			def_stat = min(float(defender["defense"]), get_effective_stat(defender, "defense"))
		else:
			atk = max(float(attacker["sp_atk"]), get_effective_stat(attacker, "sp_atk"))
			def_stat = min(float(defender["sp_def"]), get_effective_stat(defender, "sp_def"))

	var base_damage = ((2.0 * level / 5.0 + 2.0) * power * atk / def_stat) / 50.0 + 2.0

	var stab = 1.0
	if move["type"] in attacker["types"]:
		stab = 1.5
		if attacker["ability"] == "adaptability":
			stab = 2.0

	var effectiveness = get_type_effectiveness(move["type"], defender["types"])
	var random_roll = randf_range(0.85, 1.0)
	var crit_mod = 1.5 if crit else 1.0

	var item_mod = 1.0
	match attacker["item"]:
		"Life Orb":
			item_mod = 1.3
		"Expert Belt":
			if effectiveness > 1.0:
				item_mod = 1.2
		"Choice Band":
			if move["category"] == "physical":
				item_mod = 1.5
		"Choice Specs":
			if move["category"] == "special":
				item_mod = 1.5

	var final_damage = int(base_damage * stab * effectiveness * random_roll * crit_mod * item_mod)
	return {"damage": max(final_damage, 1), "crit": crit}

func get_type_effectiveness(move_type: String, defender_types: Array) -> float:
	var type_chart = team_gen.type_chart
	var multiplier = 1.0
	for def_type in defender_types:
		if type_chart.has(move_type) and type_chart[move_type].has(def_type):
			multiplier *= type_chart[move_type][def_type]
	return multiplier

func accuracy_check(attacker: Dictionary, defender: Dictionary, move: Dictionary) -> bool:
	if move["accuracy"] == 0:
		return true

	var accuracy = move["accuracy"]
	var stage_diff = attacker["accuracy_stage"] - defender["evasion_stage"]
	var stage_mod = get_stat_multiplier(clampi(stage_diff, -6, 6))

	var final_accuracy = int(accuracy * stage_mod)
	return randi() % 100 < final_accuracy

func execute_turn(your_move_index: int, opponent_move_index: int):
	if battle_over:
		return

	turn_count += 1
	var your_mon = your_team[your_active]
	var opp_mon = opponent_team[opponent_active]

	# Drop protection from the previous turn and reset consecutive counter
	# if the Pokemon didn't use a protect-class move last turn.
	your_mon["is_protected"] = false
	opp_mon["is_protected"]  = false
	if your_mon["last_move_used"] not in PROTECT_MOVES:
		your_mon["protect_consecutive"] = 0
	if opp_mon["last_move_used"] not in PROTECT_MOVES:
		opp_mon["protect_consecutive"] = 0

	var your_move = your_mon["moveset"][your_move_index]
	var opp_move = opp_mon["moveset"][opponent_move_index]

	var your_priority = your_move["priority"]
	var opp_priority = opp_move["priority"]

	var your_speed = get_effective_stat(your_mon, "speed")
	var opp_speed = get_effective_stat(opp_mon, "speed")

	if your_mon["status"] == "paralyze":
		your_speed = int(your_speed * 0.25)
	if opp_mon["status"] == "paralyze":
		opp_speed = int(opp_speed * 0.25)

	if your_mon["item"] == "Choice Scarf":
		your_speed = int(your_speed * 1.5)
	if opp_mon["item"] == "Choice Scarf":
		opp_speed = int(opp_speed * 1.5)

	var you_go_first: bool
	if your_priority != opp_priority:
		you_go_first = your_priority > opp_priority
	elif your_speed != opp_speed:
		you_go_first = your_speed > opp_speed
	else:
		you_go_first = randi() % 2 == 0

	if you_go_first:
		execute_move(your_mon, opp_mon, your_move, true)
		if not opp_mon["is_fainted"]:
			execute_move(opp_mon, your_mon, opp_move, false)
	else:
		execute_move(opp_mon, your_mon, opp_move, false)
		if not your_mon["is_fainted"]:
			execute_move(your_mon, opp_mon, your_move, true)

	apply_end_of_turn(your_mon, true)
	apply_end_of_turn(opp_mon, false)

	check_faint(true)
	check_faint(false)

func execute_move(attacker: Dictionary, defender: Dictionary, move: Dictionary, is_yours: bool):
	if attacker["is_fainted"]:
		return

	# Status immobilization checks — clear last_move_used so protect resets
	if attacker["status"] == "paralyze" and randi() % 4 == 0:
		attacker["last_move_used"] = ""
		battle_message.emit(attacker["display_name"] + " is fully paralyzed!")
		return

	if attacker["status"] == "sleep":
		attacker["sleep_turns"] -= 1
		if attacker["sleep_turns"] <= 0:
			attacker["status"] = ""
			attacker["sleep_turns"] = 0
			battle_message.emit(attacker["display_name"] + " woke up!")
		else:
			attacker["last_move_used"] = ""
			battle_message.emit(attacker["display_name"] + " is fast asleep!")
			return

	if attacker["status"] == "freeze":
		if randi() % 5 == 0:
			attacker["status"] = ""
			battle_message.emit(attacker["display_name"] + " thawed out!")
		else:
			attacker["last_move_used"] = ""
			battle_message.emit(attacker["display_name"] + " is frozen solid!")
			return

	attacker["last_move_used"] = move["name"]
	battle_message.emit(attacker["display_name"] + " used " + _format_name(move["name"]) + "!")

	if not accuracy_check(attacker, defender, move):
		battle_message.emit("It missed!")
		return

	# --- Status / effect-only moves ---
	if move["category"] == "status":
		_apply_status_move(attacker, defender, move, is_yours)
		return

	# --- Damaging moves ---
	if defender["is_protected"]:
		battle_message.emit(defender["display_name"] + " protected itself!")
		return

	var result = calculate_damage(attacker, defender, move)
	var damage = result["damage"]
	var effectiveness = get_type_effectiveness(move["type"], defender["types"])

	defender["current_hp"] = max(defender["current_hp"] - damage, 0)
	hp_changed.emit(not is_yours, defender["current_hp"], defender["max_hp"])

	if result["crit"]:
		battle_message.emit("A critical hit!")
	if effectiveness > 1.0:
		battle_message.emit("It's super effective!")
	elif effectiveness > 0.0 and effectiveness < 1.0:
		battle_message.emit("It's not very effective...")
	elif effectiveness == 0.0:
		battle_message.emit("It had no effect!")

	# Move recoil (rock-head / magic-guard abilities negate it)
	var move_name = move["name"]
	if RECOIL_FRACTION.has(move_name) \
			and attacker["ability"] != "rock-head" \
			and attacker["ability"] != "magic-guard":
		var recoil = max(int(damage * RECOIL_FRACTION[move_name]), 1)
		attacker["current_hp"] = max(attacker["current_hp"] - recoil, 0)
		hp_changed.emit(is_yours, attacker["current_hp"], attacker["max_hp"])
		battle_message.emit(attacker["display_name"] + " was hurt by recoil!")

	# Life Orb recoil
	if attacker["item"] == "Life Orb" and attacker["ability"] != "magic-guard":
		var lo_recoil = max(int(attacker["max_hp"] / 10), 1)
		attacker["current_hp"] = max(attacker["current_hp"] - lo_recoil, 0)
		hp_changed.emit(is_yours, attacker["current_hp"], attacker["max_hp"])
		battle_message.emit(attacker["display_name"] + " lost HP to Life Orb!")

	# Post-hit stat drops on the attacker (close-combat, draco-meteor, etc.)
	if USER_STAGE_AFTER.has(move_name):
		apply_stages(attacker, USER_STAGE_AFTER[move_name], is_yours)

	if defender["current_hp"] <= 0:
		defender["is_fainted"] = true
		battle_message.emit(defender["display_name"] + " fainted!")
		pokemon_fainted.emit(not is_yours, defender["name"])

	# Attacker may have fainted from recoil
	if attacker["current_hp"] <= 0 and not attacker["is_fainted"]:
		attacker["is_fainted"] = true
		battle_message.emit(attacker["display_name"] + " fainted!")
		pokemon_fainted.emit(is_yours, attacker["name"])

# Handles all category=="status" moves: healing, status infliction, and stat changes.
func _apply_status_move(attacker: Dictionary, defender: Dictionary, move: Dictionary, is_yours: bool):
	var move_name = move["name"]

	# --- Protect / Detect / King's Shield etc. ---
	if move_name in PROTECT_MOVES:
		var consecutive = attacker["protect_consecutive"]
		# Success probability: 100% first use, ×(1/3) each consecutive use
		var success = consecutive == 0 or randf() < pow(1.0 / 3.0, consecutive)
		if success:
			attacker["is_protected"]        = true
			attacker["protect_consecutive"] += 1
			battle_message.emit(attacker["display_name"] + " protected itself!")
		else:
			attacker["protect_consecutive"] = 0
			battle_message.emit("But it failed!")
		return

	# --- Rest: full heal + inflict sleep ---
	if move_name == "rest":
		if attacker["current_hp"] >= attacker["max_hp"] and attacker["status"] == "":
			battle_message.emit("But it failed!")
			return
		attacker["status"] = "sleep"
		attacker["sleep_turns"] = 3
		attacker["current_hp"] = attacker["max_hp"]
		hp_changed.emit(is_yours, attacker["current_hp"], attacker["max_hp"])
		battle_message.emit(attacker["display_name"] + " went to sleep and restored HP!")
		return

	# --- Wish: delayed 50% heal, applied next end-of-turn ---
	if move_name == "wish":
		var wish_key = "yours" if is_yours else "opp"
		if wish_pending[wish_key] > 0:
			battle_message.emit("But it failed!")
			return
		wish_pending[wish_key] = max(int(attacker["max_hp"] / 2), 1)
		battle_message.emit(attacker["display_name"] + " made a wish!")
		return

	# --- Other healing moves (50% max HP) ---
	if HEALING_MOVES.has(move_name):
		if attacker["current_hp"] >= attacker["max_hp"]:
			battle_message.emit(attacker["display_name"] + "'s HP is full!")
			return
		var heal = max(int(attacker["max_hp"] * HEALING_MOVES[move_name] / 100.0), 1)
		attacker["current_hp"] = min(attacker["current_hp"] + heal, attacker["max_hp"])
		hp_changed.emit(is_yours, attacker["current_hp"], attacker["max_hp"])
		battle_message.emit(attacker["display_name"] + " restored HP!")
		return

	# --- Status-inflicting moves ---
	if STATUS_MOVE_EFFECTS.has(move_name):
		var effect = STATUS_MOVE_EFFECTS[move_name]
		var new_status = effect["status"]

		if defender["status"] != "":
			battle_message.emit(defender["display_name"] + " already has a status condition!")
			return

		# Type immunity
		for immune_type in effect.get("immune_types", []):
			if immune_type in defender["types"]:
				battle_message.emit(defender["display_name"] + " is immune!")
				return

		# Powder moves are blocked by Grass types
		if effect.get("powder", false) and "grass" in defender["types"]:
			battle_message.emit(defender["display_name"] + " is immune!")
			return

		defender["status"] = new_status
		match new_status:
			"toxic":   battle_message.emit(defender["display_name"] + " was badly poisoned!")
			"poison":  battle_message.emit(defender["display_name"] + " was poisoned!")
			"paralyze":battle_message.emit(defender["display_name"] + " was paralyzed!")
			"burn":    battle_message.emit(defender["display_name"] + " was burned!")
			"sleep":
				defender["sleep_turns"] = randi_range(2, 5)
				battle_message.emit(defender["display_name"] + " fell asleep!")
		return

	# --- Self-boosting moves ---
	if SELF_STAGE_MOVES.has(move_name):
		apply_stages(attacker, SELF_STAGE_MOVES[move_name], is_yours)
		return

	# --- Opponent-debuffing moves ---
	if OPP_STAGE_MOVES.has(move_name):
		# Memento: user faints after using it
		if move_name == "memento":
			apply_stages(defender, OPP_STAGE_MOVES[move_name], not is_yours)
			attacker["current_hp"] = 0
			attacker["is_fainted"] = true
			hp_changed.emit(is_yours, 0, attacker["max_hp"])
			battle_message.emit(attacker["display_name"] + " fainted!")
			pokemon_fainted.emit(is_yours, attacker["name"])
			return
		apply_stages(defender, OPP_STAGE_MOVES[move_name], not is_yours)
		return

	# Fallback for unimplemented status moves
	battle_message.emit("But nothing happened!")

func apply_end_of_turn(mon: Dictionary, is_yours: bool):
	if mon["is_fainted"]:
		return

	# Wish heal arrives
	var wish_key = "yours" if is_yours else "opp"
	if wish_pending[wish_key] > 0:
		var wish_heal = wish_pending[wish_key]
		wish_pending[wish_key] = 0
		if mon["current_hp"] < mon["max_hp"]:
			mon["current_hp"] = min(mon["current_hp"] + wish_heal, mon["max_hp"])
			hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
			battle_message.emit(mon["display_name"] + "'s wish came true!")

	if mon["status"] == "burn":
		var burn_dmg = max(int(mon["max_hp"] / 8), 1)
		mon["current_hp"] = max(mon["current_hp"] - burn_dmg, 0)
		hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
		battle_message.emit(mon["display_name"] + " was hurt by its burn!")

	if mon["status"] == "poison":
		var poison_dmg = max(int(mon["max_hp"] / 8), 1)
		mon["current_hp"] = max(mon["current_hp"] - poison_dmg, 0)
		hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
		battle_message.emit(mon["display_name"] + " was hurt by poison!")

	if mon["status"] == "toxic":
		mon["toxic_counter"] += 1
		var toxic_dmg = max(int(mon["max_hp"] * mon["toxic_counter"] / 16), 1)
		mon["current_hp"] = max(mon["current_hp"] - toxic_dmg, 0)
		hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
		battle_message.emit(mon["display_name"] + " was badly hurt by poison!")

	if mon["item"] == "Leftovers" or mon["item"] == "Black Sludge":
		if mon["current_hp"] < mon["max_hp"]:
			var heal = max(int(mon["max_hp"] / 16), 1)
			mon["current_hp"] = min(mon["current_hp"] + heal, mon["max_hp"])
			hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
			battle_message.emit(mon["display_name"] + " restored HP with " + mon["item"] + "!")

	if mon["current_hp"] <= 0:
		mon["is_fainted"] = true
		battle_message.emit(mon["display_name"] + " fainted!")
		pokemon_fainted.emit(is_yours, mon["name"])

func check_faint(is_yours: bool):
	var team = your_team if is_yours else opponent_team
	var active = your_active if is_yours else opponent_active

	if not team[active]["is_fainted"]:
		return

	var next = find_next_alive(team)
	if next == -1:
		battle_over = true
		if is_yours:
			battle_message.emit("You are out of usable Pokemon!")
			battle_message.emit("You lose...")
		else:
			battle_message.emit("Opponent is out of usable Pokemon!")
			battle_message.emit("You win!")
		battle_ended.emit(not is_yours)
		return

	if is_yours:
		your_active = next
	else:
		opponent_active = next

	var mon = team[next]
	pokemon_sent_out.emit(is_yours, mon["current_hp"], mon["max_hp"], mon["display_name"], mon["level"])
	battle_message.emit(mon["display_name"] + " was sent out!")

func find_next_alive(team: Array) -> int:
	for i in team.size():
		if not team[i]["is_fainted"]:
			return i
	return -1

func switch_pokemon(is_yours: bool, index: int):
	var team = your_team if is_yours else opponent_team
	if index < 0 or index >= team.size():
		return
	if team[index]["is_fainted"]:
		return

	if is_yours:
		your_active = index
	else:
		opponent_active = index

	var mon = team[index]
	mon["atk_stage"] = 0
	mon["def_stage"] = 0
	mon["spa_stage"] = 0
	mon["spd_stage"] = 0
	mon["spe_stage"] = 0
	mon["accuracy_stage"] = 0
	mon["evasion_stage"] = 0
	mon["toxic_counter"] = 0
	mon["sleep_turns"] = 0

	pokemon_sent_out.emit(is_yours, mon["current_hp"], mon["max_hp"], mon["display_name"], mon["level"])
	battle_message.emit(mon["display_name"] + " was sent out!")

func _format_name(mon_name: String) -> String:
	return mon_name.replace("-", " ").capitalize()

func get_opponent_move() -> int:
	return randi() % opponent_team[opponent_active]["moveset"].size()

func print_teams():
	print("=== YOUR TEAM ===")
	for mon in your_team:
		print(mon["name"], " Lv", mon["level"], " | HP: ", mon["max_hp"],
			" | Atk: ", mon["attack"], " | Def: ", mon["defense"],
			" | SpA: ", mon["sp_atk"], " | SpD: ", mon["sp_def"],
			" | Spe: ", mon["speed"])
		print("  ", mon["ability"], " | ", mon["item"])
		var move_names = []
		for m in mon["moveset"]:
			move_names.append(m["name"])
		print("  Moves: ", move_names)

	print("\n=== OPPONENT TEAM ===")
	for mon in opponent_team:
		print(mon["name"], " Lv", mon["level"], " | HP: ", mon["max_hp"],
			" | Atk: ", mon["attack"], " | Def: ", mon["defense"],
			" | SpA: ", mon["sp_atk"], " | SpD: ", mon["sp_def"],
			" | Spe: ", mon["speed"])
		print("  ", mon["ability"], " | ", mon["item"])
		var move_names = []
		for m in mon["moveset"]:
			move_names.append(m["name"])
		print("  Moves: ", move_names)
