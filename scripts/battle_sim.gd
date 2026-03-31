extends Node

signal hp_changed(is_yours: bool, current_hp: int, max_hp: int)
signal pokemon_sent_out(is_yours: bool, current_hp: int, max_hp: int, mon_name: String, level: int, raw_name: String)
signal battle_message(text: String)
signal pokemon_fainted(is_yours: bool, mon_name: String)
signal battle_ended(you_won: bool)
signal attack_effectiveness(effectiveness: float)
signal status_changed(is_yours: bool, status: String)

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

# Entry hazards on each side
var field_hazards := {
	"yours": {"stealth_rock": false, "spikes": 0, "toxic_spikes": 0},
	"opp":   {"stealth_rock": false, "spikes": 0, "toxic_spikes": 0},
}

# Set by execute_move when a U-turn/Volt Switch hits — checked in execute_turn
var _pending_uturn := {"yours": false, "opp": false}

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

# Moves that deal damage then switch the attacker out
const UTURN_MOVES = ["u-turn", "volt-switch", "flip-turn", "baton-pass"]

# Status-category moves that force the opponent to switch
const PHAZING_MOVES = ["whirlwind", "roar"]

# Damaging moves that force the TARGET to switch after being hit
const PHAZING_DAMAGE_MOVES = ["dragon-tail", "circle-throw"]

# Entry-hazard setup moves  →  field key
const HAZARD_SETUP = {
	"stealth-rock": "stealth_rock",
	"spikes":       "spikes",
	"toxic-spikes": "toxic_spikes",
}

# Secondary effects on damaging moves: status / stat-drop / flinch
# "target" true = affects defender (default), false = affects attacker
const SECONDARY_EFFECTS: Dictionary = {
	# ── Freeze ──────────────────────────────────────────────────
	"ice-beam":       {"status":"freeze",   "chance":10},
	"blizzard":       {"status":"freeze",   "chance":10},
	"ice-punch":      {"status":"freeze",   "chance":10},
	"powder-snow":    {"status":"freeze",   "chance":10},
	"aurora-beam":    {"stat":"atk_stage",  "change":-1, "chance":10},
	# ── Burn ────────────────────────────────────────────────────
	"flamethrower":   {"status":"burn",     "chance":10},
	"fire-blast":     {"status":"burn",     "chance":10},
	"fire-punch":     {"status":"burn",     "chance":10},
	"ember":          {"status":"burn",     "chance":10},
	"lava-plume":     {"status":"burn",     "chance":30},
	"scald":          {"status":"burn",     "chance":30},
	"heat-wave":      {"status":"burn",     "chance":10},
	"flame-wheel":    {"status":"burn",     "chance":10},
	# ── Paralysis ───────────────────────────────────────────────
	"thunder":        {"status":"paralyze", "chance":30},
	"thunderbolt":    {"status":"paralyze", "chance":10},
	"thunder-punch":  {"status":"paralyze", "chance":10},
	"body-slam":      {"status":"paralyze", "chance":30},
	"discharge":      {"status":"paralyze", "chance":30},
	"spark":          {"status":"paralyze", "chance":30},
	"zap-cannon":     {"status":"paralyze", "chance":100},
	"force-palm":     {"status":"paralyze", "chance":30},
	# ── Defender stat drops ─────────────────────────────────────
	"psychic":        {"stat":"spd_stage",      "change":-1, "chance":10},
	"shadow-ball":    {"stat":"spd_stage",      "change":-1, "chance":20},
	"crunch":         {"stat":"def_stage",       "change":-1, "chance":20},
	"bite":           {"stat":"def_stage",       "change":-1, "chance":20},
	"rock-smash":     {"stat":"def_stage",       "change":-1, "chance":50},
	"muddy-water":    {"stat":"accuracy_stage",  "change":-1, "chance":30},
	"mud-slap":       {"stat":"accuracy_stage",  "change":-1, "chance":100},
	"icy-wind":       {"stat":"spe_stage",       "change":-1, "chance":100},
	"electroweb":     {"stat":"spe_stage",       "change":-1, "chance":100},
	"bulldoze":       {"stat":"spe_stage",       "change":-1, "chance":100},
	"rock-tomb":      {"stat":"spe_stage",       "change":-1, "chance":100},
	"bubble-beam":    {"stat":"spe_stage",       "change":-1, "chance":10},
	"constrict":      {"stat":"spe_stage",       "change":-1, "chance":10},
	"low-sweep":      {"stat":"spe_stage",       "change":-1, "chance":100},
	"octazooka":      {"stat":"accuracy_stage",  "change":-1, "chance":50},
	"mud-bomb":       {"stat":"accuracy_stage",  "change":-1, "chance":30},
	# ── Attacker stat rises ─────────────────────────────────────
	"charge-beam":    {"stat_self":"spa_stage", "change":1, "chance":70},
	"metal-claw":     {"stat_self":"atk_stage", "change":1, "chance":10},
	"steel-wing":     {"stat_self":"def_stage", "change":1, "chance":10},
	"flame-charge":   {"stat_self":"spe_stage", "change":1, "chance":100},
	# ── All-stat rise (ancientpower family) ─────────────────────
	"ancientpower":   {"all_self":1, "chance":10},
	"ominous-wind":   {"all_self":1, "chance":10},
	"silver-wind":    {"all_self":1, "chance":10},
	# ── Flinch ──────────────────────────────────────────────────
	"iron-head":      {"flinch":true, "chance":30},
	"air-slash":      {"flinch":true, "chance":30},
	"rock-slide":     {"flinch":true, "chance":30},
	"waterfall":      {"flinch":true, "chance":20},
	"headbutt":       {"flinch":true, "chance":30},
	"zen-headbutt":   {"flinch":true, "chance":20},
	"extrasensory":   {"flinch":true, "chance":10},
	"dark-pulse":     {"flinch":true, "chance":20},
	"stomp":          {"flinch":true, "chance":30},
	"snore":          {"flinch":true, "chance":30},
	"twister":        {"flinch":true, "chance":20},
	"needle-arm":     {"flinch":true, "chance":30},
}

func _ready():
	randomize()
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
	wish_pending     = {"yours": 0, "opp": 0}
	field_hazards    = {
		"yours": {"stealth_rock": false, "spikes": 0, "toxic_spikes": 0},
		"opp":   {"stealth_rock": false, "spikes": 0, "toxic_spikes": 0},
	}
	_pending_uturn = {"yours": false, "opp": false}

	var your_mon = your_team[your_active]
	var opp_mon = opponent_team[opponent_active]
	pokemon_sent_out.emit(true,  your_mon["current_hp"], your_mon["max_hp"], your_mon["display_name"], your_mon["level"], your_mon["name"])
	pokemon_sent_out.emit(false, opp_mon["current_hp"],  opp_mon["max_hp"],  opp_mon["display_name"],  opp_mon["level"], opp_mon["name"])

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
		"substitute_hp": 0,
		"friendship": 255,
		"is_flinched": false,
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

	# Return: power scales with friendship (max 102 at 255 friendship)
	if move["name"] == "return":
		power = max(1, int(attacker.get("friendship", 255) * 2 / 5))
	elif move["name"] == "frustration":
		power = max(1, int((255 - attacker.get("friendship", 255)) * 2 / 5))
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

	# Reset per-turn flags
	your_mon["is_flinched"] = false
	opp_mon["is_flinched"]  = false
	_pending_uturn          = {"yours": false, "opp": false}

	if you_go_first:
		execute_move(your_mon, opp_mon, your_move, true)
		if _pending_uturn["yours"]:
			_do_uturn_switch(true)
		var opp_after_first = opponent_team[opponent_active]
		if not opp_after_first["is_fainted"] and not opp_after_first["is_flinched"]:
			execute_move(opp_after_first, your_team[your_active], opp_move, false)
			if _pending_uturn["opp"]:
				_do_uturn_switch(false)
	else:
		execute_move(opp_mon, your_mon, opp_move, false)
		if _pending_uturn["opp"]:
			_do_uturn_switch(false)
		if not your_mon["is_fainted"] and not your_mon["is_flinched"]:
			execute_move(your_team[your_active], opponent_team[opponent_active], your_move, true)
			if _pending_uturn["yours"]:
				_do_uturn_switch(true)

	apply_end_of_turn(your_team[your_active], true)
	apply_end_of_turn(opponent_team[opponent_active], false)

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
			status_changed.emit(is_yours, "")
			battle_message.emit(attacker["display_name"] + " woke up!")
		else:
			attacker["last_move_used"] = ""
			battle_message.emit(attacker["display_name"] + " is fast asleep!")
			return

	if attacker["status"] == "freeze":
		if randi() % 5 == 0:
			attacker["status"] = ""
			status_changed.emit(is_yours, "")
			battle_message.emit(attacker["display_name"] + " thawed out!")
		else:
			attacker["last_move_used"] = ""
			battle_message.emit(attacker["display_name"] + " is frozen solid!")
			return

	attacker["last_move_used"] = move["name"]
	if move.has("current_pp"):
		move["current_pp"] = max(0, move["current_pp"] - 1)
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

	var move_name  = move["name"]
	var result     = calculate_damage(attacker, defender, move)
	var damage     = result["damage"]
	var effectiveness = get_type_effectiveness(move["type"], defender["types"])

	if effectiveness == 0.0:
		battle_message.emit("It had no effect!")
		return

	attack_effectiveness.emit(effectiveness)

	# --- Rapid Spin: remove hazards from attacker's side ---
	if move_name == "rapid-spin":
		var hkey = "yours" if is_yours else "opp"
		var h    = field_hazards[hkey]
		var cleared = false
		if h["stealth_rock"]:
			h["stealth_rock"] = false
			cleared = true
		if h["spikes"] > 0:
			h["spikes"] = 0
			cleared = true
		if h["toxic_spikes"] > 0:
			h["toxic_spikes"] = 0
			cleared = true
		if cleared:
			battle_message.emit(attacker["display_name"] + " blew away the hazards!")

	# --- Substitute absorbs damage ---
	if defender["substitute_hp"] > 0:
		defender["substitute_hp"] = max(defender["substitute_hp"] - damage, 0)
		if result["crit"]:
			battle_message.emit("A critical hit!")
		if defender["substitute_hp"] <= 0:
			battle_message.emit(defender["display_name"] + "'s substitute broke!")
		else:
			battle_message.emit("The substitute took the hit!")
	else:
		# Normal HP damage
		defender["current_hp"] = max(defender["current_hp"] - damage, 0)
		hp_changed.emit(not is_yours, defender["current_hp"], defender["max_hp"])

		if result["crit"]:
			battle_message.emit("A critical hit!")
		if effectiveness > 1.0:
			battle_message.emit("It's super effective!")
		elif effectiveness < 1.0:
			battle_message.emit("It's not very effective...")

	# --- Secondary effects ---
	if SECONDARY_EFFECTS.has(move_name) and not defender["is_fainted"] and effectiveness > 0.0:
		_apply_secondary(attacker, defender, SECONDARY_EFFECTS[move_name], is_yours)

	# --- Phazing damage moves (Dragon Tail, Circle Throw) ---
	if move_name in PHAZING_DAMAGE_MOVES and not defender["is_fainted"]:
		var next_idx = _random_alive_not_active(not is_yours)
		if next_idx != -1:
			battle_message.emit(defender["display_name"] + " was dragged out!")
			_force_switch(not is_yours, next_idx)
		else:
			battle_message.emit("But it failed!")

	# --- Recoil (rock-head / magic-guard negate) ---
	if RECOIL_FRACTION.has(move_name) \
			and attacker["ability"] != "rock-head" \
			and attacker["ability"] != "magic-guard":
		var recoil = max(int(damage * RECOIL_FRACTION[move_name]), 1)
		attacker["current_hp"] = max(attacker["current_hp"] - recoil, 0)
		hp_changed.emit(is_yours, attacker["current_hp"], attacker["max_hp"])
		battle_message.emit(attacker["display_name"] + " was hurt by recoil!")

	# --- Life Orb recoil ---
	if attacker["item"] == "Life Orb" and attacker["ability"] != "magic-guard":
		var lo_recoil = max(int(attacker["max_hp"] / 10), 1)
		attacker["current_hp"] = max(attacker["current_hp"] - lo_recoil, 0)
		hp_changed.emit(is_yours, attacker["current_hp"], attacker["max_hp"])
		battle_message.emit(attacker["display_name"] + " lost HP to Life Orb!")

	# --- Post-hit self stat drops ---
	if USER_STAGE_AFTER.has(move_name):
		apply_stages(attacker, USER_STAGE_AFTER[move_name], is_yours)

	# --- Faint checks ---
	if defender["current_hp"] <= 0:
		defender["is_fainted"] = true
		battle_message.emit(defender["display_name"] + " fainted!")
		pokemon_fainted.emit(not is_yours, defender["name"])

	if attacker["current_hp"] <= 0 and not attacker["is_fainted"]:
		attacker["is_fainted"] = true
		battle_message.emit(attacker["display_name"] + " fainted!")
		pokemon_fainted.emit(is_yours, attacker["name"])

	# --- U-turn / Volt Switch: flag a switch after this move resolves ---
	if move_name in UTURN_MOVES and not attacker["is_fainted"]:
		if _random_alive_not_active(is_yours) != -1:
			_pending_uturn["yours" if is_yours else "opp"] = true

# Handles all category=="status" moves: healing, status infliction, and stat changes.
func _apply_status_move(attacker: Dictionary, defender: Dictionary, move: Dictionary, is_yours: bool):
	var move_name = move["name"]

	# --- Entry hazard setup (Stealth Rock, Spikes, Toxic Spikes) ---
	if HAZARD_SETUP.has(move_name):
		var hkey    = "yours" if is_yours else "opp"
		var fkey    = HAZARD_SETUP[move_name]
		var hazards = field_hazards[hkey]
		if fkey == "stealth_rock":
			if hazards["stealth_rock"]:
				battle_message.emit("But it failed!")
			else:
				hazards["stealth_rock"] = true
				battle_message.emit("Pointed stones float in the air!")
		elif fkey == "spikes":
			if hazards["spikes"] >= 3:
				battle_message.emit("But it failed!")
			else:
				hazards["spikes"] += 1
				battle_message.emit("Spikes were scattered on the ground!")
		elif fkey == "toxic_spikes":
			if hazards["toxic_spikes"] >= 2:
				battle_message.emit("But it failed!")
			else:
				hazards["toxic_spikes"] += 1
				battle_message.emit("Poison spikes were scattered on the ground!")
		return

	# --- Substitute ---
	if move_name == "substitute":
		if attacker["substitute_hp"] > 0:
			battle_message.emit(attacker["display_name"] + " already has a substitute!")
			return
		var cost = max(int(attacker["max_hp"] / 4), 1)
		if attacker["current_hp"] <= cost:
			battle_message.emit(attacker["display_name"] + " doesn't have enough HP!")
			return
		attacker["current_hp"] -= cost
		attacker["substitute_hp"] = cost
		hp_changed.emit(is_yours, attacker["current_hp"], attacker["max_hp"])
		battle_message.emit(attacker["display_name"] + " made a substitute!")
		return

	# --- Whirlwind / Roar: force opponent to switch ---
	if move_name in PHAZING_MOVES:
		var next_idx = _random_alive_not_active(not is_yours)
		if next_idx == -1:
			battle_message.emit("But it failed!")
			return
		battle_message.emit(defender["display_name"] + " was blown away!")
		_force_switch(not is_yours, next_idx)
		return

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
		status_changed.emit(is_yours, "sleep")
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
		status_changed.emit(not is_yours, new_status)
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
	pokemon_sent_out.emit(is_yours, mon["current_hp"], mon["max_hp"], mon["display_name"], mon["level"], mon["name"])
	battle_message.emit(mon["display_name"] + " was sent out!")
	apply_entry_hazards(mon, is_yours)

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

	pokemon_sent_out.emit(is_yours, mon["current_hp"], mon["max_hp"], mon["display_name"], mon["level"], mon["name"])
	battle_message.emit(mon["display_name"] + " was sent out!")

# ─── Entry hazards ────────────────────────────────────────────────────────────

func apply_entry_hazards(mon: Dictionary, is_yours: bool):
	if mon["is_fainted"] or mon["ability"] == "magic-guard":
		return
	var hkey    = "yours" if is_yours else "opp"
	var hazards = field_hazards[hkey]
	var is_grounded = "flying" not in mon["types"] and mon["ability"] != "levitate"

	# Toxic Spikes: absorbed by incoming Poison-type, otherwise poison/badly poison
	if hazards["toxic_spikes"] > 0 and is_grounded:
		if "poison" in mon["types"]:
			hazards["toxic_spikes"] = 0
			battle_message.emit(mon["display_name"] + " absorbed the toxic spikes!")
		elif mon["status"] == "":
			if hazards["toxic_spikes"] >= 2:
				mon["status"] = "toxic"
				status_changed.emit(is_yours, "toxic")
				battle_message.emit(mon["display_name"] + " was badly poisoned by the spikes!")
			else:
				mon["status"] = "poison"
				status_changed.emit(is_yours, "poison")
				battle_message.emit(mon["display_name"] + " was poisoned by the spikes!")

	# Spikes: 1/8, 1/6, 1/4 HP based on layers
	if hazards["spikes"] > 0 and is_grounded:
		var fracs = [0.125, 0.1666, 0.25]
		var dmg = max(int(mon["max_hp"] * fracs[hazards["spikes"] - 1]), 1)
		mon["current_hp"] = max(mon["current_hp"] - dmg, 0)
		hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
		battle_message.emit(mon["display_name"] + " was hurt by the spikes!")

	# Stealth Rock: Rock-type effectiveness damage
	if hazards["stealth_rock"]:
		var eff = get_type_effectiveness("rock", mon["types"])
		var dmg = max(int(mon["max_hp"] * 0.125 * eff), 1)
		mon["current_hp"] = max(mon["current_hp"] - dmg, 0)
		hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
		battle_message.emit(mon["display_name"] + " was hurt by the stealth rocks!")

	if mon["current_hp"] <= 0 and not mon["is_fainted"]:
		mon["is_fainted"] = true
		battle_message.emit(mon["display_name"] + " fainted!")
		pokemon_fainted.emit(is_yours, mon["name"])

# ─── Switch helpers ───────────────────────────────────────────────────────────

func _random_alive_not_active(is_yours: bool) -> int:
	var team   = your_team if is_yours else opponent_team
	var active = your_active if is_yours else opponent_active
	var opts: Array = []
	for i in team.size():
		if i != active and not team[i]["is_fainted"]:
			opts.append(i)
	if opts.is_empty():
		return -1
	return opts[randi() % opts.size()]

func _do_uturn_switch(is_yours: bool):
	var idx = _random_alive_not_active(is_yours)
	if idx == -1:
		return
	var old_name = (your_team[your_active] if is_yours else opponent_team[opponent_active])["display_name"]
	battle_message.emit(old_name + " came back!")
	_force_switch(is_yours, idx)

func _force_switch(is_yours: bool, index: int):
	var team = your_team if is_yours else opponent_team
	var mon  = team[index]
	# Clear stat stages and volatile state on forced switch-in
	for stage_key in ["atk_stage","def_stage","spa_stage","spd_stage","spe_stage",
			"accuracy_stage","evasion_stage"]:
		mon[stage_key] = 0
	mon["toxic_counter"]  = 0
	mon["substitute_hp"]  = 0
	mon["is_protected"]   = false
	mon["protect_consecutive"] = 0
	if is_yours:
		your_active = index
	else:
		opponent_active = index
	pokemon_sent_out.emit(is_yours, mon["current_hp"], mon["max_hp"],
		mon["display_name"], mon["level"], mon["name"])
	battle_message.emit(mon["display_name"] + " was sent out!")
	apply_entry_hazards(mon, is_yours)

# ─── Secondary effect application ─────────────────────────────────────────────

func _apply_secondary(attacker: Dictionary, defender: Dictionary,
		effect: Dictionary, is_yours: bool):
	if randi() % 100 >= effect["chance"]:
		return

	# Status effect on defender
	if effect.has("status"):
		if defender["status"] != "":
			return
		var new_status: String = effect["status"]
		# Type immunities for freeze/burn/paralyze
		match new_status:
			"freeze":
				if "ice" in defender["types"]: return
			"burn":
				if "fire" in defender["types"]: return
			"paralyze":
				if "electric" in defender["types"]: return
		defender["status"] = new_status
		status_changed.emit(not is_yours, new_status)
		if new_status == "freeze":
			battle_message.emit(defender["display_name"] + " was frozen solid!")
		elif new_status == "burn":
			battle_message.emit(defender["display_name"] + " was burned!")
		elif new_status == "paralyze":
			battle_message.emit(defender["display_name"] + " was paralyzed!")
		return

	# Stat drop on defender
	if effect.has("stat"):
		apply_stages(defender, {effect["stat"]: effect["change"]}, not is_yours)
		return

	# Stat rise on attacker
	if effect.has("stat_self"):
		apply_stages(attacker, {effect["stat_self"]: effect["change"]}, is_yours)
		return

	# All-stat rise on attacker (Ancientpower family)
	if effect.has("all_self"):
		var v = effect["all_self"]
		apply_stages(attacker,
			{"atk_stage":v,"def_stage":v,"spa_stage":v,"spd_stage":v,"spe_stage":v},
			is_yours)
		return

	# Flinch (only useful if attacker moved first — checked in execute_turn)
	if effect.get("flinch", false):
		defender["is_flinched"] = true

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
