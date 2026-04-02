extends Node

signal hp_changed(is_yours: bool, current_hp: int, max_hp: int)
signal pokemon_sent_out(is_yours: bool, current_hp: int, max_hp: int, mon_name: String, level: int, raw_name: String)
signal battle_message(text: String)
signal pokemon_fainted(is_yours: bool, mon_name: String)
signal battle_ended(you_won: bool)
signal attack_effectiveness(effectiveness: float)
signal status_changed(is_yours: bool, status: String)
signal uturn_switch_request
signal faint_switch_request

@export var team_gen_path: NodePath
var team_gen: Node

var your_team: Array = []
var opponent_team: Array = []
var your_active: int = 0
var opponent_active: int = 0
var battle_over: bool = false
var turn_count: int = 0

# Tracks a pending Wish heal for each side.
# amount: HP to heal, turns: end-of-turn checks remaining before the heal lands.
var wish_pending := {
	"yours": {"amount": 0, "turns": 0},
	"opp":   {"amount": 0, "turns": 0},
}

# Entry hazards on each side
var field_hazards := {
	"yours": {"stealth_rock": false, "spikes": 0, "toxic_spikes": 0},
	"opp":   {"stealth_rock": false, "spikes": 0, "toxic_spikes": 0},
}

var weather := {"type": "", "turns": -1}

# Set by execute_move when a U-turn/Volt Switch hits — checked in execute_turn
var _pending_uturn := {"yours": false, "opp": false}

# Stores remainder of a turn when player U-turn requires a pick
var _deferred_turn: Dictionary = {}

# Each Pokemon's chosen move name this turn (used by Sucker Punch / Counter / Mirror Coat)
var _current_turn_moves := {"yours": "", "opp": ""}

# Last damaging hit received per side — for Counter / Mirror Coat
var _last_hit_received := {
	"yours": {"damage": 0, "category": ""},
	"opp":   {"damage": 0, "category": ""},
}

# Multi-hit moves: value is fixed int (always that many hits) or Array [min, max]
# 2-5 hit moves use the Gen5 distribution: 35% × 2, 35% × 3, 15% × 4, 15% × 5
const MULTI_HIT_MOVES: Dictionary = {
	# Fixed 2 hits
	"bonemerang":  2,
	"double-hit":  2,
	"double-kick": 2,
	"dual-chop":   2,
	"gear-grind":  2,
	"twineedle":   2,
	# Variable 2–5 hits (Skill Link → always 5)
	"arm-thrust":  [2, 5],
	"barrage":     [2, 5],
	"bullet-seed": [2, 5],
	"comet-punch": [2, 5],
	"double-slap": [2, 5],
	"fury-attack": [2, 5],
	"fury-swipes": [2, 5],
	"icicle-spear":[2, 5],
	"pin-missile": [2, 5],
	"rock-blast":  [2, 5],
	"spike-cannon":[2, 5],
	"tail-slap":   [2, 5],
}

# OHKO moves (always deal full damage if they hit; level-gated accuracy)
const OHKO_MOVES = ["fissure", "guillotine", "horn-drill", "sheer-cold"]

# Fixed-damage moves (bypass the stat-based damage formula)
const FIXED_DAMAGE_MOVES = [
	"seismic-toss", "night-shade", "dragon-rage", "sonic-boom",
	"super-fang", "endeavor", "final-gambit", "psywave",
	"counter", "mirror-coat",
]

# Protect-class moves that block incoming damage for one turn
const PROTECT_MOVES = ["protect", "detect", "king-s-shield", "spiky-shield", "baneful-bunker"]

# Healing moves: move name → percent of max HP healed
const HEALING_MOVES = {
	"recover": 50, "slack-off": 50, "roost": 50, "milk-drink": 50,
	"soft-boiled": 50, "heal-order": 50, "morning-sun": 50,
	"synthesis": 50, "moonlight": 50, "swallow": 50,
}

const DRAINING_MOVES = {
	"absorb": 0.5,
	"mega-drain": 0.5,
	"giga-drain": 0.5,
	"drain-punch": 0.5,
	"horn-leech": 0.5,
	"leech-life": 0.5,
	"dream-eater": 0.5,
}

const CONTACT_MOVES = {
	"acrobatics": true, "aqua-jet": true, "arm-thrust": true, "bite": true,
	"blaze-kick": true, "body-slam": true, "brick-break": true, "bullet-punch": true,
	"close-combat": true, "crunch": true, "cross-chop": true, "double-edge": true,
	"double-hit": true, "double-kick": true, "drain-punch": true, "dragon-claw": true,
	"dragon-tail": true, "dual-chop": true, "extreme-speed": true, "fake-out": true,
	"fire-punch": true, "flare-blitz": true, "force-palm": true, "frustration": true,
	"giga-impact": true, "hammer-arm": true, "headbutt": true, "high-jump-kick": true,
	"horn-leech": true, "ice-punch": true, "iron-head": true, "leaf-blade": true,
	"leech-life": true, "low-kick": true, "mach-punch": true, "mega-punch": true,
	"megahorn": true, "night-slash": true, "outrage": true, "payback": true,
	"poison-jab": true, "power-whip": true, "pursuit": true, "quick-attack": true,
	"return": true, "rock-climb": true, "rock-smash": true, "sacred-sword": true,
	"scratch": true, "seed-bomb": true, "shadow-claw": true, "sky-uppercut": true,
	"spark": true, "storm-throw": true, "submission": true, "sucker-punch": true,
	"superpower": true, "tackle": true, "take-down": true, "thunder-punch": true,
	"u-turn": true, "vacuum-wave": true, "volt-tackle": true, "waterfall": true,
	"wild-charge": true, "wood-hammer": true, "x-scissor": true, "zen-headbutt": true,
}

const SOUND_MOVES = {
	"bug-buzz": true, "chatter": true, "growl": true, "heal-bell": true,
	"hyper-voice": true, "metal-sound": true, "perish-song": true, "roar": true,
	"screech": true, "sing": true, "snore": true, "supersonic": true, "uproar": true,
}

const POWDER_MOVES = {
	"cotton-spore": true,
	"poison-powder": true,
	"sleep-powder": true,
	"spore": true,
	"stun-spore": true,
}

const PUNCHING_MOVES = {
	"bullet-punch": true, "comet-punch": true, "dizzy-punch": true, "drain-punch": true,
	"dynamic-punch": true, "fire-punch": true, "focus-punch": true, "hammer-arm": true,
	"ice-punch": true, "mach-punch": true, "mega-punch": true, "meteor-mash": true,
	"shadow-punch": true, "sky-uppercut": true, "thunder-punch": true,
}

const CONFUSION_SECONDARY_MOVES = {
	"chatter": 100,
	"confusion": 10,
	"dynamic-punch": 100,
	"psybeam": 10,
	"rock-climb": 20,
	"signal-beam": 10,
	"water-pulse": 20,
}

const GENDERLESS_POKEMON = {
	"arceus": true, "articuno": true, "azelf": true, "baltoy": true, "beldum": true,
	"bronzong": true, "bronzor": true, "celebi": true, "claydol": true, "cobalion": true,
	"cryogonal": true, "darkrai": true, "deoxys-attack": true, "deoxys-defense": true,
	"deoxys-normal": true, "deoxys-speed": true, "dialga": true, "ditto": true,
	"electrode": true, "genesect": true, "giratina-altered": true, "giratina-origin": true,
	"golett": true, "golurk": true, "groudon": true, "ho-oh": true,
	"jirachi": true, "keldeo-ordinary": true, "klink": true, "klang": true, "klinklang": true, "kyogre": true,
	"kyurem": true, "kyurem-black": true, "kyurem-white": true, "lugia": true,
	"lunatone": true, "magnemite": true, "magneton": true,
	"magnezone": true, "manaphy": true, "meloetta-aria": true, "mesprit": true,
	"metagross": true, "metang": true, "mew": true, "mewtwo": true, "moltres": true,
	"palkia": true, "phione": true, "porygon": true, "porygon-z": true, "porygon2": true,
	"rayquaza": true, "regice": true, "regigigas": true, "regirock": true,
	"registeel": true, "reshiram": true, "rotom": true, "rotom-fan": true,
	"rotom-frost": true, "rotom-heat": true, "rotom-mow": true, "rotom-wash": true,
	"shaymin-land": true, "shaymin-sky": true, "solrock": true, "starmie": true,
	"staryu": true, "suicune": true, "terrakion": true, "uxie": true, "victini": true,
	"virizion": true, "voltorb": true, "zapdos": true, "zekrom": true,
}

const ALWAYS_MALE_POKEMON = {
	"braviary": true, "gallade": true, "hitmonchan": true, "hitmonlee": true,
	"hitmontop": true, "landorus-incarnate": true, "landorus-therian": true, "latios": true,
	"nidoking": true, "nidoran-m": true, "sawk": true, "tauros": true,
	"throh": true, "thundurus-incarnate": true, "thundurus-therian": true,
	"tornadus-incarnate": true, "tornadus-therian": true, "volbeat": true,
}

const ALWAYS_FEMALE_POKEMON = {
	"blissey": true, "chansey": true, "cresselia": true, "froslass": true,
	"happiny": true, "illumise": true, "jynx": true, "kangaskhan": true,
	"latias": true, "miltank": true, "nidoqueen": true, "nidoran-f": true,
	"vespiquen": true,
}

const MOLD_BREAKER_ABILITIES = {
	"mold-breaker": true,
	"teravolt": true,
	"turboblaze": true,
}

const SOUND_IMMUNE_ABILITIES = {
	"soundproof": true,
}

const POWDER_IMMUNE_ABILITIES = {
	"overcoat": true,
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

# Moves that faint the user after dealing damage
const SELF_FAINT_MOVES = ["explosion", "self-destruct"]

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
	"ancient-power":  {"all_self":1, "chance":10},
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
	wish_pending     = {
		"yours": {"amount": 0, "turns": 0},
		"opp":   {"amount": 0, "turns": 0},
	}
	field_hazards    = {
		"yours": {"stealth_rock": false, "spikes": 0, "toxic_spikes": 0},
		"opp":   {"stealth_rock": false, "spikes": 0, "toxic_spikes": 0},
	}
	weather = {"type": "", "turns": -1}
	_pending_uturn = {"yours": false, "opp": false}

	var your_mon = your_team[your_active]
	var opp_mon = opponent_team[opponent_active]
	_apply_illusion(true)
	_apply_illusion(false)
	_emit_active_identity(true)
	_emit_active_identity(false)
	_handle_on_switch_in_ability(false)
	_handle_on_switch_in_ability(true)
	_refresh_active_ability_state()

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

	var attack_stat = calc_stat(raw["base_attack"], ivs["atk"], evs["atk"], level)
	var defense_stat = calc_stat(raw["base_defense"], ivs["def"], evs["def"], level)
	var sp_atk_stat = calc_stat(raw["base_sp_atk"], ivs["spa"], evs["spa"], level)
	var sp_def_stat = calc_stat(raw["base_sp_def"], ivs["spd"], evs["spd"], level)
	var speed_stat = calc_stat(raw["base_speed"], ivs["spe"], evs["spe"], level)
	return {
		"name": raw["name"],
		"true_display_name": _format_name(raw["name"]),
		"display_name": _format_name(raw["name"]),
		"appearance_name": raw["name"],
		"level": level,
		"types": raw["types"].duplicate(true),
		"base_types": raw["types"].duplicate(true),
		"ability": raw["ability"],
		"base_ability": raw["ability"],
		"item": raw["item"],
		"base_item": raw["item"],
		"last_consumed_item": "",
		"role": raw["role"],
		"ivs": raw.get("ivs", {}).duplicate(true),
		"evs": raw.get("evs", {}).duplicate(true),
		"moveset": raw["moveset"],
		"base_moveset": raw["moveset"].duplicate(true),
		"move_names": raw["move_names"],
		"base_move_names": raw["move_names"].duplicate(true),
		"max_hp": hp,
		"current_hp": hp,
		"attack":  attack_stat,
		"base_attack": attack_stat,
		"defense": defense_stat,
		"base_defense": defense_stat,
		"sp_atk":  sp_atk_stat,
		"base_sp_atk": sp_atk_stat,
		"sp_def":  sp_def_stat,
		"base_sp_def": sp_def_stat,
		"speed":   speed_stat,
		"base_speed": speed_stat,
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
		"is_confused": false,
		"confusion_turns": 0,
		"infatuated_with": "",
		"gender": _determine_gender(raw["name"]),
		"substitute_hp": 0,
		"leech_seed_source": "",
		"friendship": 255,
		"is_flinched": false,
		"destiny_bond": false,
		"perish_count": -1,
		"flash_fire_active": false,
		"slow_start_turns": 5 if raw["ability"] == "slow-start" else 0,
		"truant_loafing": false,
		"disabled_move": "",
		"disable_turns": 0,
		"analytic_active": false,
		"choice_lock": "",
		"air_balloon_active": raw["item"] == "Air Balloon",
		"unburden_active": false,
		"illusion_active": false,
		"transformed": false,
	}

func _get_base_species_name(mon_name: String) -> String:
	if mon_name.ends_with("-male"):
		return mon_name.trim_suffix("-male")
	if mon_name.ends_with("-female"):
		return mon_name.trim_suffix("-female")
	return mon_name

func _determine_gender(mon_name: String) -> String:
	if mon_name.ends_with("-male"):
		return "M"
	if mon_name.ends_with("-female"):
		return "F"
	var base_name = _get_base_species_name(mon_name)
	if GENDERLESS_POKEMON.get(mon_name, false) or GENDERLESS_POKEMON.get(base_name, false):
		return ""
	if ALWAYS_MALE_POKEMON.get(mon_name, false) or ALWAYS_MALE_POKEMON.get(base_name, false):
		return "M"
	if ALWAYS_FEMALE_POKEMON.get(mon_name, false) or ALWAYS_FEMALE_POKEMON.get(base_name, false):
		return "F"
	return "M" if randi() % 2 == 0 else "F"

func _update_mon_appearance(mon: Dictionary, visible_name: String, visible_display_name: String):
	mon["appearance_name"] = visible_name
	mon["display_name"] = visible_display_name

func _emit_active_identity(is_yours: bool):
	var mon = _get_active_mon(is_yours)
	pokemon_sent_out.emit(
		is_yours,
		mon["current_hp"],
		mon["max_hp"],
		mon["display_name"],
		mon["level"],
		mon.get("appearance_name", mon["name"])
	)

func _find_illusion_partner(is_yours: bool) -> Dictionary:
	var team = your_team if is_yours else opponent_team
	var active_index = your_active if is_yours else opponent_active
	for i in range(team.size() - 1, -1, -1):
		if i == active_index:
			continue
		if not team[i]["is_fainted"]:
			return team[i]
	return {}

func _apply_illusion(is_yours: bool):
	var mon = _get_active_mon(is_yours)
	_update_mon_appearance(mon, mon["name"], mon["true_display_name"])
	mon["illusion_active"] = false
	if not _has_ability(mon, "illusion"):
		return
	var partner = _find_illusion_partner(is_yours)
	if partner.is_empty():
		return
	_update_mon_appearance(mon, partner["name"], partner["true_display_name"])
	mon["illusion_active"] = true

func _break_illusion(mon: Dictionary, is_yours: bool):
	if not mon.get("illusion_active", false):
		return
	mon["illusion_active"] = false
	_update_mon_appearance(mon, mon["name"], mon["true_display_name"])
	battle_message.emit(mon["display_name"] + "'s Illusion wore off!")
	if not mon["is_fainted"]:
		_emit_active_identity(is_yours)

func _apply_confusion(mon: Dictionary, is_yours: bool) -> bool:
	if _has_ability(mon, "own-tempo"):
		battle_message.emit(mon["display_name"] + " cannot become confused!")
		return false
	if mon.get("is_confused", false):
		return false
	mon["is_confused"] = true
	mon["confusion_turns"] = randi_range(2, 5)
	battle_message.emit(mon["display_name"] + " became confused!")
	if not _berry_is_blocked(mon, is_yours) and mon.get("item", "") == "Persim Berry":
		mon["is_confused"] = false
		mon["confusion_turns"] = 0
		_consume_item(mon, is_yours, mon["display_name"] + " snapped out of confusion with Persim Berry!")
	return true

func _clear_infatuation(mon: Dictionary):
	mon["infatuated_with"] = ""

func _can_infatuate(source: Dictionary, target: Dictionary) -> bool:
	if source["gender"] == "" or target["gender"] == "":
		return false
	if source["gender"] == target["gender"]:
		return false
	if _has_ability(target, "oblivious"):
		return false
	return true

func _apply_infatuation(source: Dictionary, target: Dictionary, target_is_yours: bool) -> bool:
	if target.get("infatuated_with", "") != "":
		return false
	if not _can_infatuate(source, target):
		if _has_ability(target, "oblivious"):
			battle_message.emit(target["display_name"] + " is too oblivious to fall in love!")
		else:
			battle_message.emit("But it failed!")
		return false
	target["infatuated_with"] = _side_key(not target_is_yours)
	battle_message.emit(target["display_name"] + " fell in love!")
	if _can_use_held_item(target) and target.get("item", "") == "Mental Herb":
		_clear_infatuation(target)
		_consume_item(target, target_is_yours, target["display_name"] + " cured its infatuation with Mental Herb!")
	return true

func _apply_confusion_self_hit(mon: Dictionary, is_yours: bool):
	var atk = float(get_effective_stat(mon, "attack"))
	if mon["status"] == "burn" and not _has_ability(mon, "guts"):
		atk *= 0.5
	var def_stat = max(float(get_effective_stat(mon, "defense")), 1.0)
	var damage = int((((2.0 * mon["level"] / 5.0 + 2.0) * 40.0 * atk / def_stat) / 50.0) + 2.0)
	damage = max(damage, 1)
	_break_illusion(mon, is_yours)
	_damage_mon(mon, damage, is_yours, mon["display_name"] + " hurt itself in its confusion!")
	_resolve_faint_from_residual(mon, is_yours)

func _apply_transform(attacker: Dictionary, defender: Dictionary, is_yours: bool):
	attacker["types"] = defender["types"].duplicate(true)
	attacker["attack"] = defender["attack"]
	attacker["defense"] = defender["defense"]
	attacker["sp_atk"] = defender["sp_atk"]
	attacker["sp_def"] = defender["sp_def"]
	attacker["speed"] = defender["speed"]
	attacker["atk_stage"] = defender["atk_stage"]
	attacker["def_stage"] = defender["def_stage"]
	attacker["spa_stage"] = defender["spa_stage"]
	attacker["spd_stage"] = defender["spd_stage"]
	attacker["spe_stage"] = defender["spe_stage"]
	attacker["moveset"] = []
	for foe_move in defender["moveset"]:
		var copied_move = foe_move.duplicate(true)
		copied_move["current_pp"] = min(copied_move.get("max_pp", 5), 5)
		copied_move["max_pp"] = min(copied_move.get("max_pp", 5), 5)
		attacker["moveset"].append(copied_move)
	attacker["move_names"] = defender["move_names"].duplicate(true)
	attacker["transformed"] = true
	attacker["illusion_active"] = false
	_update_mon_appearance(attacker, defender.get("appearance_name", defender["name"]), defender["display_name"])
	if not attacker["is_fainted"]:
		_emit_active_identity(is_yours)
	battle_message.emit(attacker["true_display_name"] + " transformed into " + defender["display_name"] + "!")

func _side_key(is_yours: bool) -> String:
	return "yours" if is_yours else "opp"

func _opposing_side_key(is_yours: bool) -> String:
	return "opp" if is_yours else "yours"

func _get_active_mon(is_yours: bool) -> Dictionary:
	return your_team[your_active] if is_yours else opponent_team[opponent_active]

func _has_ability(mon: Dictionary, ability_name: String) -> bool:
	return mon.get("ability", "") == ability_name

func _is_mold_breaker_attack(attacker: Dictionary) -> bool:
	return MOLD_BREAKER_ABILITIES.has(attacker.get("ability", ""))

func _weather_is_suppressed() -> bool:
	var your_mon = _get_active_mon(true)
	var opp_mon = _get_active_mon(false)
	return (not your_mon["is_fainted"] and (_has_ability(your_mon, "air-lock") or _has_ability(your_mon, "cloud-nine"))) \
		or (not opp_mon["is_fainted"] and (_has_ability(opp_mon, "air-lock") or _has_ability(opp_mon, "cloud-nine")))

func _effective_weather() -> String:
	if _weather_is_suppressed():
		return ""
	return weather["type"]

func _set_weather(weather_type: String, source_name: String):
	if weather["type"] == weather_type:
		return
	weather["type"] = weather_type
	weather["turns"] = -1
	match weather_type:
		"rain":
			battle_message.emit(source_name + "'s Drizzle made it rain!")
		"sun":
			battle_message.emit(source_name + "'s Drought intensified the sunlight!")
		"sand":
			battle_message.emit(source_name + "'s Sand Stream whipped up a sandstorm!")
		"hail":
			battle_message.emit(source_name + "'s Snow Warning whipped up a hailstorm!")
	_refresh_active_ability_state()

func _heal_mon(mon: Dictionary, amount: int, is_yours: bool, message: String = ""):
	if amount <= 0 or mon["current_hp"] <= 0:
		return
	var old_hp = mon["current_hp"]
	mon["current_hp"] = min(mon["current_hp"] + amount, mon["max_hp"])
	if mon["current_hp"] != old_hp:
		hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
		if message != "":
			battle_message.emit(message)

func _damage_mon(mon: Dictionary, amount: int, is_yours: bool, message: String = ""):
	if amount <= 0 or mon["current_hp"] <= 0:
		return
	mon["current_hp"] = max(mon["current_hp"] - amount, 0)
	hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
	if message != "":
		battle_message.emit(message)
	if mon["current_hp"] > 0:
		_try_trigger_hp_item(mon, is_yours)

func _is_berry_item(item_name: String) -> bool:
	return item_name.ends_with("Berry")

func _can_use_held_item(mon: Dictionary) -> bool:
	return not _has_ability(mon, "klutz")

func _berry_is_blocked(mon: Dictionary, is_yours: bool) -> bool:
	if not _is_berry_item(mon.get("item", "")):
		return false
	if _can_use_held_item(mon) == false:
		return true
	var foe = _get_active_mon(not is_yours)
	return not foe["is_fainted"] and _has_ability(foe, "unnerve")

func _consume_item(mon: Dictionary, is_yours: bool, message: String = ""):
	var held_item = mon.get("item", "")
	if held_item == "" or held_item == "None":
		return
	mon["last_consumed_item"] = held_item
	mon["item"] = ""
	if held_item == "Air Balloon":
		mon["air_balloon_active"] = false
	if _has_ability(mon, "unburden"):
		mon["unburden_active"] = true
	if message != "":
		battle_message.emit(message)

func _try_trigger_status_cure_item(mon: Dictionary, is_yours: bool):
	if mon["status"] == "":
		return
	if _berry_is_blocked(mon, is_yours):
		return
	if mon["item"] == "Lum Berry":
		var held_item = mon["item"]
		mon["status"] = ""
		mon["sleep_turns"] = 0
		mon["toxic_counter"] = 0
		status_changed.emit(is_yours, "")
		_consume_item(mon, is_yours, mon["display_name"] + " cured its status with " + held_item + "!")
	elif mon["status"] == "sleep" and mon["item"] == "Chesto Berry":
		var held_item = mon["item"]
		mon["status"] = ""
		mon["sleep_turns"] = 0
		status_changed.emit(is_yours, "")
		_consume_item(mon, is_yours, mon["display_name"] + " woke up with " + held_item + "!")

func _try_trigger_hp_item(mon: Dictionary, is_yours: bool):
	if mon["current_hp"] <= 0:
		return
	if _berry_is_blocked(mon, is_yours):
		return
	if mon["item"] == "Sitrus Berry" and mon["current_hp"] <= int(mon["max_hp"] / 2):
		var heal_amount = max(int(mon["max_hp"] / 4), 1)
		var held_item = mon["item"]
		_consume_item(mon, is_yours, mon["display_name"] + " restored HP with " + held_item + "!")
		_heal_mon(mon, heal_amount, is_yours)

func _try_activate_orb(mon: Dictionary, is_yours: bool):
	if not _can_use_held_item(mon):
		return
	if mon["status"] != "":
		return
	if mon["item"] == "Flame Orb" and _can_receive_status(mon, "burn"):
		mon["status"] = "burn"
		status_changed.emit(is_yours, "burn")
		battle_message.emit(mon["display_name"] + " was burned by its Flame Orb!")
		_try_trigger_status_cure_item(mon, is_yours)
	elif mon["item"] == "Toxic Orb" and _can_receive_status(mon, "toxic"):
		mon["status"] = "toxic"
		mon["toxic_counter"] = 0
		status_changed.emit(is_yours, "toxic")
		battle_message.emit(mon["display_name"] + " was badly poisoned by its Toxic Orb!")
		_try_trigger_status_cure_item(mon, is_yours)

func _apply_white_herb(mon: Dictionary, is_yours: bool):
	if not _can_use_held_item(mon):
		return
	if mon["item"] != "White Herb":
		return
	var restored = false
	for stage_key in ["atk_stage", "def_stage", "spa_stage", "spd_stage", "spe_stage", "accuracy_stage", "evasion_stage"]:
		if mon[stage_key] < 0:
			mon[stage_key] = 0
			restored = true
	if restored:
		_consume_item(mon, is_yours, mon["display_name"] + " restored its lowered stats with White Herb!")

func _matching_gem_type(item_name: String) -> String:
	match item_name:
		"Flying Gem":
			return "flying"
		"Normal Gem":
			return "normal"
		"Fighting Gem":
			return "fighting"
	return ""

func _is_choice_item(item_name: String) -> bool:
	return item_name in ["Choice Band", "Choice Specs", "Choice Scarf"]

func _prepare_move_for_use(attacker: Dictionary, move: Dictionary) -> Dictionary:
	var prepared_move = move.duplicate(true)
	if _has_ability(attacker, "normalize"):
		prepared_move["type"] = "normal"
	var gem_type = _matching_gem_type(attacker.get("item", ""))
	prepared_move["gem_boost"] = gem_type != "" and gem_type == prepared_move.get("type", "")
	return prepared_move

func _resolve_choice_locked_move(mon: Dictionary, selected_move: Dictionary) -> Dictionary:
	if not _can_use_held_item(mon) or not _is_choice_item(mon.get("item", "")):
		return selected_move
	var locked_name = mon.get("choice_lock", "")
	if locked_name == "":
		return selected_move
	for move in mon["moveset"]:
		if move["name"] == locked_name:
			return move
	return selected_move

func _handle_on_hit_items(attacker: Dictionary, defender: Dictionary, move: Dictionary, is_yours: bool, hp_damage: int, hit_substitute: bool):
	if not hit_substitute and hp_damage > 0:
		if _can_use_held_item(defender) and defender.get("air_balloon_active", false) and defender.get("item", "") == "Air Balloon":
			_consume_item(defender, not is_yours, defender["display_name"] + "'s Air Balloon popped!")
		_try_trigger_hp_item(defender, not is_yours)

	if not hit_substitute and not defender["is_fainted"] and _is_contact_move(move["name"], move) and _can_use_held_item(defender) and defender.get("item", "") == "Rocky Helmet" and not attacker["is_fainted"]:
		_damage_mon(attacker, max(int(attacker["max_hp"] / 6), 1), is_yours, attacker["display_name"] + " was hurt by Rocky Helmet!")
		_try_trigger_hp_item(attacker, is_yours)

	if not hit_substitute and not defender["is_fainted"] and _is_contact_move(move["name"], move) and _has_ability(defender, "pickpocket") and defender.get("item", "") == "" and attacker.get("item", "") != "" and _can_use_held_item(attacker):
		defender["item"] = attacker["item"]
		attacker["item"] = ""
		battle_message.emit(defender["display_name"] + " picked the attacker's pocket!")
		if _has_ability(attacker, "unburden"):
			attacker["unburden_active"] = true

func _is_contact_move(move_name: String, move: Dictionary) -> bool:
	return CONTACT_MOVES.has(move_name)

func _is_sound_move(move_name: String) -> bool:
	return SOUND_MOVES.has(move_name)

func _is_powder_move(move_name: String) -> bool:
	return POWDER_MOVES.has(move_name)

func _move_has_secondary_effect(move_name: String) -> bool:
	return SECONDARY_EFFECTS.has(move_name) or CONFUSION_SECONDARY_MOVES.has(move_name)

func _can_receive_status(mon: Dictionary, status_name: String) -> bool:
	match status_name:
		"sleep":
			return not (_has_ability(mon, "insomnia") or _has_ability(mon, "vital-spirit") or (_has_ability(mon, "leaf-guard") and _effective_weather() == "sun"))
		"paralyze":
			return not (_has_ability(mon, "limber") or (_has_ability(mon, "leaf-guard") and _effective_weather() == "sun"))
		"poison", "toxic":
			return not (_has_ability(mon, "immunity") or (_has_ability(mon, "leaf-guard") and _effective_weather() == "sun")) and "poison" not in mon["types"] and "steel" not in mon["types"]
		"burn":
			return not (_has_ability(mon, "water-veil") or (_has_ability(mon, "leaf-guard") and _effective_weather() == "sun")) and "fire" not in mon["types"]
		"freeze":
			return not (_has_ability(mon, "magma-armor") or (_has_ability(mon, "leaf-guard") and _effective_weather() == "sun")) and "ice" not in mon["types"]
	return true

func _is_move_blocked_by_ability(attacker: Dictionary, defender: Dictionary, move: Dictionary, is_yours: bool) -> bool:
	var move_name = move["name"]
	var move_type = move["type"]
	var attacker_breaks = _is_mold_breaker_attack(attacker)

	if _is_sound_move(move_name) and SOUND_IMMUNE_ABILITIES.has(defender["ability"]) and not attacker_breaks:
		battle_message.emit(defender["display_name"] + " is immune to sound-based moves!")
		return true

	if _is_powder_move(move_name) and POWDER_IMMUNE_ABILITIES.has(defender["ability"]) and not attacker_breaks:
		battle_message.emit(defender["display_name"] + " is immune!")
		return true

	if move_type == "ground" and _has_ability(defender, "levitate") and not attacker_breaks:
		battle_message.emit(defender["display_name"] + " is immune thanks to Levitate!")
		return true
	if move_type == "ground" and _can_use_held_item(defender) and defender.get("air_balloon_active", false):
		battle_message.emit(defender["display_name"] + " is floating on its Air Balloon!")
		return true

	if move_type == "electric":
		if _has_ability(defender, "volt-absorb") and not attacker_breaks:
			_heal_mon(defender, max(int(defender["max_hp"] / 4), 1), not is_yours, defender["display_name"] + " restored HP with Volt Absorb!")
			return true
		if _has_ability(defender, "motor-drive") and not attacker_breaks:
			apply_stages(defender, {"spe_stage": 1}, not is_yours)
			return true
		if _has_ability(defender, "lightning-rod") and not attacker_breaks:
			apply_stages(defender, {"spa_stage": 1}, not is_yours)
			return true

	if move_type == "water":
		if _has_ability(defender, "water-absorb") and not attacker_breaks:
			_heal_mon(defender, max(int(defender["max_hp"] / 4), 1), not is_yours, defender["display_name"] + " restored HP with Water Absorb!")
			return true
		if _has_ability(defender, "dry-skin") and not attacker_breaks:
			_heal_mon(defender, max(int(defender["max_hp"] / 4), 1), not is_yours, defender["display_name"] + " restored HP with Dry Skin!")
			return true
		if _has_ability(defender, "storm-drain") and not attacker_breaks:
			apply_stages(defender, {"spa_stage": 1}, not is_yours)
			return true

	if move_type == "fire" and _has_ability(defender, "flash-fire") and not attacker_breaks:
		defender["flash_fire_active"] = true
		battle_message.emit(defender["display_name"] + " powered up with Flash Fire!")
		return true

	if move_type == "grass" and _has_ability(defender, "sap-sipper") and not attacker_breaks:
		apply_stages(defender, {"atk_stage": 1}, not is_yours)
		return true

	return false

func _handle_on_switch_in_ability(is_yours: bool):
	var mon = _get_active_mon(is_yours)
	match mon["ability"]:
		"drizzle":
			_set_weather("rain", mon["display_name"])
		"drought":
			_set_weather("sun", mon["display_name"])
		"sand-stream":
			_set_weather("sand", mon["display_name"])
		"snow-warning":
			_set_weather("hail", mon["display_name"])
		"intimidate":
			var foe = _get_active_mon(not is_yours)
			if not foe["is_fainted"]:
				apply_stages(foe, {"atk_stage": -1}, not is_yours, true)
		"download":
			var foe = _get_active_mon(not is_yours)
			if foe["defense"] <= foe["sp_def"]:
				apply_stages(mon, {"atk_stage": 1}, is_yours)
			else:
				apply_stages(mon, {"spa_stage": 1}, is_yours)
		"anticipation":
			var foe = _get_active_mon(not is_yours)
			for foe_move in foe["moveset"]:
				if foe_move["name"] in OHKO_MOVES or foe_move["name"] in ["explosion", "self-destruct"] \
						or (foe_move["category"] != "status" and get_move_effectiveness(foe, foe_move["type"], mon["types"]) > 1.0):
					battle_message.emit(mon["display_name"] + " shuddered with Anticipation!")
					break
		"frisk":
			var foe = _get_active_mon(not is_yours)
			if foe["item"] != "":
				battle_message.emit(mon["display_name"] + " frisked " + foe["display_name"] + " and found its " + foe["item"] + "!")
		"forewarn":
			var foe = _get_active_mon(not is_yours)
			var best_move_name := ""
			var best_power := -1
			for foe_move in foe["moveset"]:
				var candidate_power = int(foe_move.get("power", 0))
				if foe_move["name"] in OHKO_MOVES:
					candidate_power = 150
				elif foe_move["name"] in ["counter", "mirror-coat", "metal-burst"]:
					candidate_power = 120
				if candidate_power > best_power:
					best_power = candidate_power
					best_move_name = foe_move["name"]
			if best_move_name != "":
				battle_message.emit(mon["display_name"] + "'s Forewarn alerted it to " + _format_name(best_move_name) + "!")
		"trace":
			var foe = _get_active_mon(not is_yours)
			var traced = foe["ability"]
			if traced not in ["trace", "multitype", "illusion", "imposter"]:
				mon["ability"] = traced
				battle_message.emit(mon["display_name"] + " traced " + foe["display_name"] + "'s " + team_gen.ability_data.get(traced, {}).get("display_name", _format_name(traced)) + "!")
				if traced in ["drizzle", "drought", "sand-stream", "snow-warning", "intimidate", "download"]:
					_handle_on_switch_in_ability(is_yours)
		"imposter":
			var foe = _get_active_mon(not is_yours)
			_apply_transform(mon, foe, is_yours)

func _reset_switch_in_state(mon: Dictionary):
	mon["types"] = mon["base_types"].duplicate(true)
	mon["ability"] = mon["base_ability"]
	mon["moveset"] = mon["base_moveset"].duplicate(true)
	mon["move_names"] = mon["base_move_names"].duplicate(true)
	mon["display_name"] = mon["true_display_name"]
	mon["appearance_name"] = mon["name"]
	mon["attack"] = mon["base_attack"]
	mon["defense"] = mon["base_defense"]
	mon["sp_atk"] = mon["base_sp_atk"]
	mon["sp_def"] = mon["base_sp_def"]
	mon["speed"] = mon["base_speed"]
	for stage_key in ["atk_stage", "def_stage", "spa_stage", "spd_stage", "spe_stage",
			"accuracy_stage", "evasion_stage"]:
		mon[stage_key] = 0
	mon["toxic_counter"] = 0
	mon["is_confused"] = false
	mon["confusion_turns"] = 0
	mon["infatuated_with"] = ""
	mon["substitute_hp"] = 0
	mon["is_protected"] = false
	mon["protect_consecutive"] = 0
	mon["perish_count"] = -1
	mon["destiny_bond"] = false
	mon["is_flinched"] = false
	mon["disabled_move"] = ""
	mon["disable_turns"] = 0
	mon["analytic_active"] = false
	mon["choice_lock"] = ""
	mon["air_balloon_active"] = mon["item"] == "Air Balloon"
	mon["illusion_active"] = false
	mon["transformed"] = false
	if mon["ability"] == "slow-start":
		mon["slow_start_turns"] = 5
	else:
		mon["slow_start_turns"] = 0
	mon["truant_loafing"] = false

func _clear_switch_out_state(mon: Dictionary, is_yours: bool):
	if mon["ability"] == "natural-cure" and mon["status"] != "":
		mon["status"] = ""
		mon["sleep_turns"] = 0
		mon["toxic_counter"] = 0
	if mon["ability"] == "regenerator" and not mon["is_fainted"]:
		mon["current_hp"] = min(mon["current_hp"] + max(int(mon["max_hp"] / 3), 1), mon["max_hp"])
	mon["substitute_hp"] = 0
	mon["is_protected"] = false
	mon["protect_consecutive"] = 0
	mon["perish_count"] = -1
	mon["destiny_bond"] = false
	mon["is_flinched"] = false
	mon["is_confused"] = false
	mon["confusion_turns"] = 0
	mon["infatuated_with"] = ""
	mon["leech_seed_source"] = ""
	mon["flash_fire_active"] = false
	mon["truant_loafing"] = false
	mon["disabled_move"] = ""
	mon["disable_turns"] = 0
	mon["analytic_active"] = false
	mon["choice_lock"] = ""
	mon["air_balloon_active"] = mon["item"] == "Air Balloon"
	mon["unburden_active"] = false
	mon["illusion_active"] = false
	mon["transformed"] = false
	if mon["status"] == "toxic":
		mon["toxic_counter"] = 0
	var foe = _get_active_mon(not is_yours)
	if foe.get("infatuated_with", "") == _side_key(is_yours):
		foe["infatuated_with"] = ""

func _switch_in_pokemon(is_yours: bool, index: int, apply_hazards: bool = true):
	var team = your_team if is_yours else opponent_team
	_reset_switch_in_state(team[index])
	if is_yours:
		your_active = index
	else:
		opponent_active = index
	_apply_illusion(is_yours)
	var mon = _get_active_mon(is_yours)
	_emit_active_identity(is_yours)
	battle_message.emit(mon["display_name"] + " was sent out!")
	if apply_hazards:
		apply_entry_hazards(mon, is_yours)
	if not mon["is_fainted"]:
		_handle_on_switch_in_ability(is_yours)
	_refresh_active_ability_state()

func _apply_drain_heal(attacker: Dictionary, defender: Dictionary, move_name: String, damage_to_hp: int, is_yours: bool):
	if damage_to_hp <= 0:
		return
	var heal = max(int(damage_to_hp * DRAINING_MOVES.get(move_name, 0.0)), 1)
	if heal <= 0:
		return
	if defender["ability"] == "liquid-ooze":
		attacker["current_hp"] = max(attacker["current_hp"] - heal, 0)
		hp_changed.emit(is_yours, attacker["current_hp"], attacker["max_hp"])
		battle_message.emit(attacker["display_name"] + " sucked up the liquid ooze!")
		return
	if attacker["current_hp"] >= attacker["max_hp"]:
		return
	attacker["current_hp"] = min(attacker["current_hp"] + heal, attacker["max_hp"])
	hp_changed.emit(is_yours, attacker["current_hp"], attacker["max_hp"])
	battle_message.emit(attacker["display_name"] + " restored HP!")

func _resolve_faint_from_residual(mon: Dictionary, is_yours: bool, faint_message: String = "") -> bool:
	if mon["current_hp"] > 0 or mon["is_fainted"]:
		return false
	mon["is_fainted"] = true
	if faint_message != "":
		battle_message.emit(faint_message)
	else:
		battle_message.emit(mon["display_name"] + " fainted!")
	pokemon_fainted.emit(is_yours, mon["name"])
	return true

func _refresh_forecast_form(mon: Dictionary):
	if not _has_ability(mon, "forecast"):
		return
	match _effective_weather():
		"rain":
			mon["types"] = ["water"]
		"sun":
			mon["types"] = ["fire"]
		"hail":
			mon["types"] = ["ice"]
		_:
			mon["types"] = mon["base_types"].duplicate(true)

func _refresh_active_ability_state():
	if your_team.size() > 0:
		_refresh_forecast_form(_get_active_mon(true))
	if opponent_team.size() > 0:
		_refresh_forecast_form(_get_active_mon(false))

func get_move_effectiveness(attacker: Dictionary, move_type: String, defender_types: Array) -> float:
	var type_chart = team_gen.type_chart
	var multiplier = 1.0
	var scrappy_ignores_ghost = _has_ability(attacker, "scrappy") and move_type in ["normal", "fighting"]
	for def_type in defender_types:
		if scrappy_ignores_ghost and def_type == "ghost":
			continue
		if type_chart.has(move_type) and type_chart[move_type].has(def_type):
			multiplier *= type_chart[move_type][def_type]
	return multiplier

func _move_targets_opponent(move_name: String, move: Dictionary) -> bool:
	if move["category"] != "status":
		return true
	if move_name in HEALING_MOVES or move_name in SELF_STAGE_MOVES:
		return false
	if move_name in PROTECT_MOVES or move_name in ["rest", "wish", "substitute", "destiny-bond"]:
		return false
	return true

func _can_switch_out(is_yours: bool) -> bool:
	var active = _get_active_mon(is_yours)
	var foe = _get_active_mon(not is_yours)
	if (_can_use_held_item(active) and active["item"] == "Shed Shell") or "ghost" in active["types"]:
		return true
	if _has_ability(foe, "shadow-tag"):
		return false
	if _has_ability(foe, "arena-trap") and "flying" not in active["types"] and active["ability"] != "levitate":
		return false
	if _has_ability(foe, "magnet-pull") and "steel" in active["types"]:
		return false
	return true

func _handle_contact_abilities(attacker: Dictionary, defender: Dictionary, move_name: String, is_yours: bool):
	if not _is_contact_move(move_name, {}) or attacker["is_fainted"]:
		return
	if defender["is_fainted"] and _has_ability(defender, "aftermath"):
		_damage_mon(attacker, max(int(attacker["max_hp"] / 4), 1), is_yours, attacker["display_name"] + " was hurt by Aftermath!")
		return

	if _has_ability(defender, "rough-skin") or _has_ability(defender, "iron-barbs"):
		_damage_mon(attacker, max(int(attacker["max_hp"] / 8), 1), is_yours, attacker["display_name"] + " was hurt by " + team_gen.ability_data.get(defender["ability"], {}).get("display_name", _format_name(defender["ability"])) + "!")

	if attacker["status"] == "":
		if (_has_ability(defender, "static") or _has_ability(defender, "flame-body") or _has_ability(defender, "poison-point")) and randi() % 100 < 30:
			var contact_status = "paralyze" if _has_ability(defender, "static") else ("burn" if _has_ability(defender, "flame-body") else "poison")
			if _can_receive_status(attacker, contact_status):
				attacker["status"] = contact_status
				if contact_status == "toxic":
					attacker["toxic_counter"] = 0
				status_changed.emit(is_yours, contact_status)
				battle_message.emit(attacker["display_name"] + " was " + ("burned" if contact_status == "burn" else ("paralyzed" if contact_status == "paralyze" else "poisoned")) + "!")
				_try_synchronize(attacker, defender, contact_status, is_yours)
				_try_trigger_status_cure_item(attacker, is_yours)
		elif _has_ability(defender, "effect-spore") and randi() % 100 < 30:
			var roll = randi() % 3
			var spore_status = ["sleep", "poison", "paralyze"][roll]
			if _can_receive_status(attacker, spore_status):
				attacker["status"] = spore_status
				if spore_status == "sleep":
					attacker["sleep_turns"] = randi_range(2, 5)
				status_changed.emit(is_yours, spore_status)
				match spore_status:
					"sleep":
						battle_message.emit(attacker["display_name"] + " fell asleep!")
					"poison":
						battle_message.emit(attacker["display_name"] + " was poisoned!")
					"paralyze":
						battle_message.emit(attacker["display_name"] + " was paralyzed!")
				_try_synchronize(attacker, defender, spore_status, is_yours)
				_try_trigger_status_cure_item(attacker, is_yours)
	if _has_ability(defender, "cute-charm") and randi() % 100 < 30:
		_apply_infatuation(defender, attacker, is_yours)

	if _has_ability(defender, "mummy") and attacker["ability"] not in ["multitype", "illusion", "trace", "mummy"]:
		attacker["ability"] = "mummy"
		battle_message.emit(attacker["display_name"] + " was made into Mummy!")

func _apply_disable(attacker: Dictionary, move_name: String):
	if attacker.get("disable_turns", 0) > 0:
		return
	attacker["disabled_move"] = move_name
	attacker["disable_turns"] = 4
	battle_message.emit(attacker["display_name"] + "'s " + _format_name(move_name) + " was disabled!")

func _handle_on_hit_abilities(attacker: Dictionary, defender: Dictionary, move: Dictionary, is_yours: bool, hp_damage: int, hit_substitute: bool):
	if hit_substitute or hp_damage <= 0:
		return
	if move["category"] == "physical" and _has_ability(defender, "weak-armor"):
		apply_stages(defender, {"def_stage": -1, "spe_stage": 1}, not is_yours, true)
	if hp_damage > 0 and _has_ability(defender, "rattled") and move["type"] in ["dark", "ghost", "bug"]:
		apply_stages(defender, {"spe_stage": 1}, not is_yours)
	if _has_ability(attacker, "poison-touch") and _is_contact_move(move["name"], move) and defender["status"] == "" and _can_receive_status(defender, "poison") and randi() % 100 < 30:
		defender["status"] = "poison"
		status_changed.emit(not is_yours, "poison")
		battle_message.emit(defender["display_name"] + " was poisoned by Poison Touch!")
		_try_synchronize(defender, attacker, "poison", not is_yours)
		_try_trigger_status_cure_item(defender, not is_yours)
	if _has_ability(defender, "cursed-body") and move.get("current_pp", 1) > 0 and randi() % 100 < 30:
		_apply_disable(attacker, move["name"])

func _apply_sturdy(defender: Dictionary, attacker: Dictionary, damage: int) -> int:
	if damage < defender["current_hp"]:
		return damage
	if defender["current_hp"] != defender["max_hp"]:
		return damage
	if _has_ability(defender, "sturdy") and not _is_mold_breaker_attack(attacker):
		battle_message.emit(defender["display_name"] + " endured the hit with Sturdy!")
		return max(defender["current_hp"] - 1, 0)
	if _can_use_held_item(defender) and defender.get("item", "") == "Focus Sash":
		_consume_item(defender, false, defender["display_name"] + " hung on using its Focus Sash!")
		return max(defender["current_hp"] - 1, 0)
	return damage

func _try_synchronize(holder: Dictionary, inflictor: Dictionary, status_name: String, holder_is_yours: bool):
	if holder["ability"] != "synchronize":
		return
	if inflictor["status"] != "":
		return
	if status_name not in ["burn", "poison", "toxic", "paralyze"]:
		return
	if not _can_receive_status(inflictor, status_name):
		return
	inflictor["status"] = status_name
	if status_name == "toxic":
		inflictor["toxic_counter"] = 0
	status_changed.emit(not holder_is_yours, status_name)
	match status_name:
		"burn":
			battle_message.emit(inflictor["display_name"] + " was burned by Synchronize!")
		"poison":
			battle_message.emit(inflictor["display_name"] + " was poisoned by Synchronize!")
		"toxic":
			battle_message.emit(inflictor["display_name"] + " was badly poisoned by Synchronize!")
		"paralyze":
			battle_message.emit(inflictor["display_name"] + " was paralyzed by Synchronize!")
	_try_trigger_status_cure_item(inflictor, not holder_is_yours)

func get_stat_multiplier(stage: int) -> float:
	if stage >= 0:
		return (2.0 + stage) / 2.0
	else:
		return 2.0 / (2.0 - stage)

func get_effective_stat(mon: Dictionary, stat_name: String) -> int:
	var base_val = float(mon[stat_name])
	var stage_key = ""
	match stat_name:
		"attack":  stage_key = "atk_stage"
		"defense": stage_key = "def_stage"
		"sp_atk":  stage_key = "spa_stage"
		"sp_def":  stage_key = "spd_stage"
		"speed":   stage_key = "spe_stage"

	if stage_key == "":
		return int(base_val)

	var effective = base_val * get_stat_multiplier(mon[stage_key])
	var active_weather = _effective_weather()

	match stat_name:
		"attack":
			if _has_ability(mon, "huge-power") or _has_ability(mon, "pure-power"):
				effective *= 2.0
			if _has_ability(mon, "guts") and mon["status"] != "":
				effective *= 1.5
			if _has_ability(mon, "flower-gift") and active_weather == "sun":
				effective *= 1.5
			if _has_ability(mon, "hustle"):
				effective *= 1.5
			if _has_ability(mon, "defeatist") and mon["current_hp"] <= int(mon["max_hp"] / 2):
				effective *= 0.5
			if _has_ability(mon, "slow-start") and mon.get("slow_start_turns", 0) > 0:
				effective *= 0.5
		"defense":
			if _has_ability(mon, "marvel-scale") and mon["status"] != "":
				effective *= 1.5
		"sp_atk":
			if _has_ability(mon, "solar-power") and active_weather == "sun":
				effective *= 1.5
			if _has_ability(mon, "flare-boost") and mon["status"] == "burn":
				effective *= 1.5
			if _has_ability(mon, "defeatist") and mon["current_hp"] <= int(mon["max_hp"] / 2):
				effective *= 0.5
		"sp_def":
			if _has_ability(mon, "flower-gift") and active_weather == "sun":
				effective *= 1.5
		"speed":
			if active_weather == "rain" and _has_ability(mon, "swift-swim"):
				effective *= 2.0
			elif active_weather == "sun" and _has_ability(mon, "chlorophyll"):
				effective *= 2.0
			elif active_weather == "sand" and _has_ability(mon, "sand-rush"):
				effective *= 2.0
			if _has_ability(mon, "quick-feet") and mon["status"] != "":
				effective *= 1.5
			if _has_ability(mon, "unburden") and mon.get("unburden_active", false):
				effective *= 2.0
			if _has_ability(mon, "slow-start") and mon.get("slow_start_turns", 0) > 0:
				effective *= 0.5

	return int(effective)

# Apply stat stage changes to a Pokemon, clamped to [-6, 6], with battle messages.
func apply_stages(mon: Dictionary, stages: Dictionary, is_yours: bool, caused_by_opponent: bool = false):
	var triggered_defiant = false
	var lowered_any_stat = false
	for stat_key in stages:
		var change = stages[stat_key]
		if caused_by_opponent:
			if change < 0 and _has_ability(mon, "clear-body"):
				battle_message.emit(mon["display_name"] + "'s Clear Body prevented its stats from being lowered!")
				continue
			if change < 0 and stat_key == "atk_stage" and _has_ability(mon, "hyper-cutter"):
				battle_message.emit(mon["display_name"] + "'s Hyper Cutter prevented its Attack from being lowered!")
				continue
			if change < 0 and stat_key == "def_stage" and _has_ability(mon, "big-pecks"):
				battle_message.emit(mon["display_name"] + "'s Big Pecks prevented its Defense from being lowered!")
				continue
			if change < 0 and stat_key == "accuracy_stage" and _has_ability(mon, "keen-eye"):
				battle_message.emit(mon["display_name"] + "'s Keen Eye prevented its accuracy from being lowered!")
				continue
		if _has_ability(mon, "contrary"):
			change *= -1
		if _has_ability(mon, "simple"):
			change *= 2
		var old_stage = mon[stat_key]
		mon[stat_key] = clampi(mon[stat_key] + change, -6, 6)
		var actual = mon[stat_key] - old_stage
		if actual == 0:
			battle_message.emit(mon["display_name"] + "'s stats won't go any further!")
			continue
		if actual < 0:
			lowered_any_stat = true
		if caused_by_opponent and actual < 0 and _has_ability(mon, "defiant"):
			triggered_defiant = true
		var stat_display = stat_key.replace("_stage", "").to_upper()
		var direction = "rose" if actual > 0 else "fell"
		var magnitude = ""
		match abs(actual):
			2: magnitude = " sharply"
			3: magnitude = " drastically"
		battle_message.emit(mon["display_name"] + "'s " + stat_display + magnitude + " " + direction + "!")
	if triggered_defiant:
		apply_stages(mon, {"atk_stage": 2}, is_yours)
	elif lowered_any_stat:
		_apply_white_herb(mon, is_yours)

func is_critical_hit(attacker: Dictionary, move: Dictionary) -> bool:
	var crit_stage = 0
	if move["name"] in HIGH_CRIT_MOVES:
		crit_stage += 1
	if _has_ability(attacker, "super-luck"):
		crit_stage += 1
	var threshold = 24
	if crit_stage == 1:
		threshold = 8
	elif crit_stage >= 2:
		threshold = 2
	return randi() % threshold == 0

func calculate_damage(attacker: Dictionary, defender: Dictionary, move: Dictionary) -> Dictionary:
	if move["category"] == "status":
		return {"damage": 0, "crit": false}

	var level = attacker["level"]
	var power = move["power"]

	# --- Variable-power move overrides (must happen before the power == 0 guard) ---
	match move["name"]:
		"return":
			power = max(1, int(attacker.get("friendship", 255) * 2 / 5))
		"frustration":
			power = max(1, int((255 - attacker.get("friendship", 255)) * 2 / 5))
		"gyro-ball":
			var atk_spe = max(1, get_effective_stat(attacker, "speed"))
			var def_spe = max(1, get_effective_stat(defender, "speed"))
			power = min(150, int(ceil(25.0 * def_spe / atk_spe)))
		"low-kick", "grass-knot":
			power = team_gen.get_weight_power(defender["name"])
		"heat-crash", "heavy-slam":
			var atk_w = team_gen.get_pokemon_weight(attacker["name"])
			var def_w = team_gen.get_pokemon_weight(defender["name"])
			var wrat  = atk_w / max(1.0, def_w)
			if   wrat >= 5.0: power = 120
			elif wrat >= 4.0: power = 100
			elif wrat >= 3.0: power = 80
			elif wrat >= 2.0: power = 60
			else:             power = 40
		"electro-ball":
			var as2 = max(1.0, float(get_effective_stat(attacker, "speed")))
			var ds2 = max(1.0, float(get_effective_stat(defender, "speed")))
			var sr  = as2 / ds2
			if   sr >= 4.0: power = 150
			elif sr >= 3.0: power = 120
			elif sr >= 2.0: power = 80
			else:           power = 60
		"reversal", "flail":
			var hp_r = float(attacker["current_hp"]) / float(attacker["max_hp"])
			if   hp_r <= 0.0417: power = 200
			elif hp_r <= 0.1042: power = 150
			elif hp_r <= 0.2083: power = 100
			elif hp_r <= 0.3542: power = 80
			elif hp_r <= 0.6875: power = 40
			else:                power = 20
		"wring-out", "crush-grip":
			power = max(1, int(120.0 * float(defender["current_hp"]) / float(defender["max_hp"])))
		"punishment":
			var pos_stages = 0
			for sk in ["atk_stage","def_stage","spa_stage","spd_stage","spe_stage","accuracy_stage","evasion_stage"]:
				pos_stages += max(0, defender[sk])
			power = min(200, 60 + 20 * pos_stages)
		"magnitude":
			var mr = randi() % 100
			if   mr < 5:  power = 10
			elif mr < 15: power = 30
			elif mr < 35: power = 50
			elif mr < 65: power = 70
			elif mr < 85: power = 90
			elif mr < 95: power = 110
			else:         power = 150
		"trump-card":
			var pp_left = move.get("current_pp", 0)
			if   pp_left <= 1: power = 200
			elif pp_left == 2: power = 80
			elif pp_left == 3: power = 60
			elif pp_left == 4: power = 50
			else:              power = 40

	# Moves with power 0 that we can't resolve to a real power use the fixed-damage path instead
	if power == 0:
		return {"damage": 0, "crit": false}

	var attacker_breaks = _is_mold_breaker_attack(attacker)
	var crit = false if (_has_ability(defender, "battle-armor") or _has_ability(defender, "shell-armor")) and not attacker_breaks else is_critical_hit(attacker, move)

	var atk: float
	var def_stat: float
	if move["category"] == "physical":
		atk = get_effective_stat(attacker, "attack")
		def_stat = get_effective_stat(defender, "defense")
		# Burn halves attack, but not on a crit (crits ignore negative stat changes,
		# but burn is a condition — in Gen 6+ burn still applies on crits)
		if attacker["status"] == "burn" and attacker["ability"] != "guts":
			atk *= 0.5
	else:
		atk = get_effective_stat(attacker, "sp_atk")
		def_stat = get_effective_stat(defender, "sp_def")

	# Crits use attacker's stat ignoring negative stages, defender's ignoring positive stages
	if crit:
		if move["category"] == "physical":
			var burn_mod = 0.5 if attacker["status"] == "burn" and attacker["ability"] != "guts" else 1.0
			atk = max(attacker["attack"] * burn_mod, get_effective_stat(attacker, "attack") * burn_mod)
			def_stat = min(float(defender["defense"]), get_effective_stat(defender, "defense"))
		else:
			atk = max(float(attacker["sp_atk"]), get_effective_stat(attacker, "sp_atk"))
			def_stat = min(float(defender["sp_def"]), get_effective_stat(defender, "sp_def"))

	if _has_ability(attacker, "unaware"):
		if move["category"] == "physical":
			def_stat = float(defender["defense"])
		else:
			def_stat = float(defender["sp_def"])
	if _has_ability(defender, "unaware"):
		if move["category"] == "physical":
			atk = float(attacker["attack"])
			if attacker["status"] == "burn" and attacker["ability"] != "guts":
				atk *= 0.5
		else:
			atk = float(attacker["sp_atk"])

	var base_damage = ((2.0 * level / 5.0 + 2.0) * power * atk / def_stat) / 50.0 + 2.0

	var stab = 1.0
	if move["type"] in attacker["types"]:
		stab = 1.5
		if attacker["ability"] == "adaptability":
			stab = 2.0

	var effectiveness = get_move_effectiveness(attacker, move["type"], defender["types"])
	if _has_ability(defender, "wonder-guard") and effectiveness <= 1.0 and not attacker_breaks:
		return {"damage": 0, "crit": false}

	var ability_mod = 1.0
	var active_weather = _effective_weather()
	if move["type"] == "fire" and active_weather == "sun":
		ability_mod *= 1.5
	elif move["type"] == "water" and active_weather == "rain":
		ability_mod *= 1.5
	elif move["type"] == "fire" and active_weather == "rain":
		ability_mod *= 0.5
	elif move["type"] == "water" and active_weather == "sun":
		ability_mod *= 0.5

	if attacker["current_hp"] <= int(attacker["max_hp"] / 3):
		if move["type"] == "fire" and _has_ability(attacker, "blaze"):
			ability_mod *= 1.5
		elif move["type"] == "water" and _has_ability(attacker, "torrent"):
			ability_mod *= 1.5
		elif move["type"] == "grass" and _has_ability(attacker, "overgrow"):
			ability_mod *= 1.5
		elif move["type"] == "bug" and _has_ability(attacker, "swarm"):
			ability_mod *= 1.5
	if move["category"] == "physical" and attacker["status"] in ["poison", "toxic"] and _has_ability(attacker, "toxic-boost"):
		ability_mod *= 1.5

	if _has_ability(attacker, "flash-fire") and attacker.get("flash_fire_active", false) and move["type"] == "fire":
		ability_mod *= 1.5
	if _has_ability(attacker, "iron-fist") and PUNCHING_MOVES.has(move["name"]):
		ability_mod *= 1.2
	if _has_ability(attacker, "technician") and power <= 60:
		ability_mod *= 1.5
	if _has_ability(attacker, "reckless") and (RECOIL_FRACTION.has(move["name"]) or move["name"] in ["jump-kick", "high-jump-kick"]):
		ability_mod *= 1.2
	if _has_ability(attacker, "sheer-force") and _move_has_secondary_effect(move["name"]):
		ability_mod *= 1.3
	if effectiveness < 1.0 and _has_ability(attacker, "tinted-lens"):
		ability_mod *= 2.0
	if effectiveness > 1.0 and (_has_ability(defender, "filter") or _has_ability(defender, "solid-rock")) and not attacker_breaks:
		ability_mod *= 0.75
	if _has_ability(defender, "thick-fat") and move["type"] in ["fire", "ice"] and not attacker_breaks:
		ability_mod *= 0.5
	if _has_ability(defender, "heatproof") and move["type"] == "fire" and not attacker_breaks:
		ability_mod *= 0.5
	if _has_ability(defender, "dry-skin") and move["type"] == "fire" and not attacker_breaks:
		ability_mod *= 1.25
	if _has_ability(defender, "multiscale") and defender["current_hp"] == defender["max_hp"] and not attacker_breaks:
		ability_mod *= 0.5
	if _has_ability(attacker, "analytic") and attacker.get("analytic_active", false):
		ability_mod *= 1.3
	if _has_ability(attacker, "rivalry") and attacker["gender"] != "" and defender["gender"] != "":
		ability_mod *= 1.25 if attacker["gender"] == defender["gender"] else 0.75
	var random_roll = randf_range(0.85, 1.0)
	var crit_mod = 3.0 if crit and _has_ability(attacker, "sniper") else (2.0 if crit else 1.0)

	var item_mod = 1.0
	if _can_use_held_item(attacker):
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
		if move.get("gem_boost", false):
			item_mod *= 1.5

	var final_damage = int(base_damage * stab * effectiveness * random_roll * crit_mod * item_mod * ability_mod)
	return {"damage": max(final_damage, 1), "crit": crit}

func get_type_effectiveness(move_type: String, defender_types: Array) -> float:
	var type_chart = team_gen.type_chart
	var multiplier = 1.0
	for def_type in defender_types:
		if type_chart.has(move_type) and type_chart[move_type].has(def_type):
			multiplier *= type_chart[move_type][def_type]
	return multiplier

func accuracy_check(attacker: Dictionary, defender: Dictionary, move: Dictionary) -> bool:
	if _has_ability(attacker, "no-guard") or _has_ability(defender, "no-guard"):
		return true
	if move["accuracy"] == 0:
		return true

	var accuracy = float(move["accuracy"])
	var stage_diff = attacker["accuracy_stage"] - defender["evasion_stage"]
	var stage_mod = get_stat_multiplier(clampi(stage_diff, -6, 6))
	if _has_ability(attacker, "compound-eyes"):
		accuracy *= 1.3
	if _has_ability(attacker, "victory-star"):
		accuracy *= 1.1
	if _has_ability(attacker, "hustle") and move["category"] == "physical":
		accuracy *= 0.8
	if defender.get("is_confused", false) and _has_ability(defender, "tangled-feet"):
		accuracy *= 0.5
	if _effective_weather() == "sand" and _has_ability(defender, "sand-veil"):
		accuracy *= 0.8
	if _has_ability(defender, "wonder-skin") and move["category"] == "status":
		accuracy = min(accuracy, 50.0)

	var final_accuracy = int(min(100.0, accuracy * stage_mod))
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

	var your_move = _resolve_choice_locked_move(your_mon, your_mon["moveset"][your_move_index])
	var opp_move = _resolve_choice_locked_move(opp_mon, opp_mon["moveset"][opponent_move_index])

	var your_priority = your_move["priority"]
	var opp_priority = opp_move["priority"]
	if your_move["category"] == "status" and _has_ability(your_mon, "prankster"):
		your_priority += 1
	if opp_move["category"] == "status" and _has_ability(opp_mon, "prankster"):
		opp_priority += 1

	var your_speed = get_effective_stat(your_mon, "speed")
	var opp_speed = get_effective_stat(opp_mon, "speed")

	if your_mon["status"] == "paralyze" and not _has_ability(your_mon, "quick-feet"):
		your_speed = int(your_speed * 0.25)
	if opp_mon["status"] == "paralyze" and not _has_ability(opp_mon, "quick-feet"):
		opp_speed = int(opp_speed * 0.25)

	if _can_use_held_item(your_mon) and your_mon["item"] == "Choice Scarf":
		your_speed = int(your_speed * 1.5)
	if _can_use_held_item(opp_mon) and opp_mon["item"] == "Choice Scarf":
		opp_speed = int(opp_speed * 1.5)

	var you_go_first: bool
	if your_priority != opp_priority:
		you_go_first = your_priority > opp_priority
	elif _has_ability(your_mon, "stall") != _has_ability(opp_mon, "stall"):
		you_go_first = not _has_ability(your_mon, "stall")
	elif your_speed != opp_speed:
		you_go_first = your_speed > opp_speed
	else:
		you_go_first = randi() % 2 == 0

	# Reset per-turn flags
	your_mon["is_flinched"] = false
	opp_mon["is_flinched"]  = false
	your_mon["analytic_active"] = false
	opp_mon["analytic_active"] = false
	_pending_uturn          = {"yours": false, "opp": false}
	_current_turn_moves     = {"yours": your_move["name"], "opp": opp_move["name"]}
	_last_hit_received      = {"yours": {"damage": 0, "category": ""}, "opp": {"damage": 0, "category": ""}}

	if you_go_first:
		execute_move(your_mon, opp_mon, your_move, true)
		if _pending_uturn["yours"]:
			# Player used U-turn — defer the rest of the turn until they pick a switch
			_deferred_turn = {
				"opp_move": opp_move,
				"you_go_first": true,
			}
			_do_uturn_switch(true)
			return  # Turn resumes in _resume_turn_after_uturn()
		var opp_after_first = opponent_team[opponent_active]
		if not opp_after_first["is_fainted"] and not opp_after_first["is_flinched"]:
			opp_after_first["analytic_active"] = true
			execute_move(opp_after_first, your_team[your_active], opp_move, false)
			if _pending_uturn["opp"]:
				_do_uturn_switch(false)
	else:
		execute_move(opp_mon, your_mon, opp_move, false)
		if _pending_uturn["opp"]:
			_do_uturn_switch(false)
		if not your_mon["is_fainted"] and not your_mon["is_flinched"]:
			your_team[your_active]["analytic_active"] = true
			execute_move(your_team[your_active], opponent_team[opponent_active], your_move, true)
			if _pending_uturn["yours"]:
				_deferred_turn = {
					"opp_move": null,
					"you_go_first": false,
				}
				_do_uturn_switch(true)
				return
	_finish_turn()

func execute_move(attacker: Dictionary, defender: Dictionary, move: Dictionary, is_yours: bool):
	if attacker["is_fainted"]:
		return

	# Status immobilization checks — clear last_move_used so protect resets
	var move_name = move["name"]
	if _can_use_held_item(attacker) and _is_choice_item(attacker.get("item", "")) and attacker.get("choice_lock", "") != "" and attacker["choice_lock"] != move_name:
		move = _resolve_choice_locked_move(attacker, move)
		move_name = move["name"]
	if attacker.get("disable_turns", 0) > 0 and attacker.get("disabled_move", "") == move_name:
		attacker["last_move_used"] = ""
		battle_message.emit(attacker["display_name"] + "'s " + _format_name(move_name) + " is disabled!")
		return
	if _has_ability(attacker, "truant"):
		if attacker.get("truant_loafing", false):
			attacker["truant_loafing"] = false
			attacker["last_move_used"] = ""
			battle_message.emit(attacker["display_name"] + " is loafing around!")
			return
		attacker["truant_loafing"] = true

	if attacker["status"] == "paralyze" and randi() % 4 == 0:
		attacker["last_move_used"] = ""
		battle_message.emit(attacker["display_name"] + " is fully paralyzed!")
		return

	if attacker["status"] == "sleep":
		attacker["sleep_turns"] -= 2 if _has_ability(attacker, "early-bird") else 1
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

	if attacker.get("infatuated_with", "") != "":
		battle_message.emit(attacker["display_name"] + " is in love!")
		if randi() % 2 == 0:
			attacker["last_move_used"] = ""
			battle_message.emit(attacker["display_name"] + " is immobilized by love!")
			return

	if attacker.get("is_confused", false):
		if attacker.get("confusion_turns", 0) <= 0:
			attacker["is_confused"] = false
			battle_message.emit(attacker["display_name"] + " snapped out of its confusion!")
		else:
			attacker["confusion_turns"] -= 1
			battle_message.emit(attacker["display_name"] + " is confused!")
			if randi() % 3 == 0:
				attacker["last_move_used"] = ""
				_apply_confusion_self_hit(attacker, is_yours)
				return
			if attacker["confusion_turns"] <= 0:
				attacker["is_confused"] = false
				battle_message.emit(attacker["display_name"] + " snapped out of its confusion!")

	# Destiny Bond resets when the user moves again (unless using Destiny Bond itself)
	if move["name"] != "destiny-bond":
		attacker["destiny_bond"] = false

	attacker["last_move_used"] = move_name
	if move.has("current_pp"):
		var pp_cost = 1
		if _move_targets_opponent(move_name, move) and _has_ability(defender, "pressure"):
			pp_cost += 1
		move["current_pp"] = max(0, move["current_pp"] - pp_cost)
	battle_message.emit(attacker["display_name"] + " used " + _format_name(move_name) + "!")
	var prepared_move = _prepare_move_for_use(attacker, move)
	move = prepared_move

	# --- Sucker Punch: fails if the defender did not choose a damaging move this turn ---
	if move_name == "sucker-punch":
		var def_side     = "opp" if is_yours else "yours"
		var def_chosen   = _current_turn_moves.get(def_side, "")
		var def_mdata    = team_gen.get_move_details(def_chosen)
		if def_mdata["category"] == "status" or def_chosen == "":
			battle_message.emit("But it failed!")
			return

	if not accuracy_check(attacker, defender, move):
		battle_message.emit("It missed!")
		return

	if _is_move_blocked_by_ability(attacker, defender, move, is_yours):
		return

	if _can_use_held_item(attacker) and _is_choice_item(attacker.get("item", "")) and attacker.get("choice_lock", "") == "":
		attacker["choice_lock"] = move_name

	# --- Status / effect-only moves ---
	if move["category"] == "status":
		_apply_status_move(attacker, defender, move, is_yours)
		return

	# --- Damaging moves ---
	if defender["is_protected"]:
		battle_message.emit(defender["display_name"] + " protected itself!")
		return

	if _can_use_held_item(attacker) and move.get("gem_boost", false):
		var gem_name = attacker.get("item", "")
		_consume_item(attacker, is_yours, attacker["display_name"] + " strengthened " + _format_name(move_name) + " with its " + gem_name + "!")

	# --- OHKO moves ---
	if move_name in OHKO_MOVES:
		# Fail if attacker's level is lower than defender's
		if attacker["level"] < defender["level"]:
			battle_message.emit("It doesn't affect " + defender["display_name"] + "...")
			return
		# Type immunity (e.g. Guillotine/Horn Drill are Normal — no effect on Ghost)
		var ohko_eff = get_move_effectiveness(attacker, move["type"], defender["types"])
		if ohko_eff == 0.0:
			battle_message.emit("It had no effect!")
			return
		# Level-adjusted accuracy: 30 + (atk_level - def_level)
		var ohko_acc = 30 + (attacker["level"] - defender["level"])
		if randi() % 100 >= ohko_acc:
			battle_message.emit("It missed!")
			return
		battle_message.emit("It's a one-hit KO!")
		_deal_damage(defender, defender["current_hp"], attacker, is_yours, move)
		return

	# --- Fixed-damage moves (level-based, HP-based, etc.) ---
	if move_name in FIXED_DAMAGE_MOVES:
		var eff_check = get_move_effectiveness(attacker, move["type"], defender["types"])
		if eff_check == 0.0:
			battle_message.emit("It had no effect!")
			return
		var fixed_dmg = 0
		var failed    = false
		match move_name:
			"seismic-toss":
				# No effect on Ghost types (already caught above by Fighting type chart)
				fixed_dmg = attacker["level"]
			"night-shade":
				# No effect on Normal types (Ghost type chart)
				fixed_dmg = attacker["level"]
			"dragon-rage":
				fixed_dmg = 40
			"sonic-boom":
				fixed_dmg = 20
			"super-fang":
				fixed_dmg = max(1, defender["current_hp"] / 2)
			"endeavor":
				if attacker["current_hp"] >= defender["current_hp"]:
					failed = true
				else:
					fixed_dmg = defender["current_hp"] - attacker["current_hp"]
			"final-gambit":
				fixed_dmg = attacker["current_hp"]
			"psywave":
				fixed_dmg = max(1, int(attacker["level"] * randi_range(5, 15) / 10.0))
			"counter":
				var my_side_c = "yours" if is_yours else "opp"
				var last_c    = _last_hit_received[my_side_c]
				if last_c["category"] != "physical" or last_c["damage"] == 0:
					failed = true
				else:
					fixed_dmg = last_c["damage"] * 2
			"mirror-coat":
				var my_side_m = "yours" if is_yours else "opp"
				var last_m    = _last_hit_received[my_side_m]
				if last_m["category"] != "special" or last_m["damage"] == 0:
					failed = true
				else:
					fixed_dmg = last_m["damage"] * 2
		if failed:
			battle_message.emit("But it failed!")
			return
		if fixed_dmg > 0:
			_deal_damage(defender, fixed_dmg, attacker, is_yours, move)
			# Final Gambit: attacker faints after use
			if move_name == "final-gambit" and not attacker["is_fainted"]:
				attacker["current_hp"] = 0
				attacker["is_fainted"] = true
				hp_changed.emit(is_yours, 0, attacker["max_hp"])
				battle_message.emit(attacker["display_name"] + " fainted!")
				pokemon_fainted.emit(is_yours, attacker["name"])
		return

	var effectiveness = get_move_effectiveness(attacker, move["type"], defender["types"])

	if effectiveness == 0.0:
		battle_message.emit("It had no effect!")
		return

	attack_effectiveness.emit(effectiveness)

	# --- Multi-hit moves (handled separately) ---
	if move_name in MULTI_HIT_MOVES or move_name in ["triple-kick", "beat-up"]:
		_execute_multi_hit(attacker, defender, move, is_yours)
		return

	var result = calculate_damage(attacker, defender, move)
	var damage = result["damage"]
	var hit_substitute = defender["substitute_hp"] > 0
	var hp_damage = 0

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
	if hit_substitute:
		defender["substitute_hp"] = max(defender["substitute_hp"] - damage, 0)
		if result["crit"]:
			battle_message.emit("A critical hit!")
		if defender["substitute_hp"] <= 0:
			battle_message.emit(defender["display_name"] + "'s substitute broke!")
		else:
			battle_message.emit("The substitute took the hit!")
	else:
		# Normal HP damage
		damage = _apply_sturdy(defender, attacker, damage)
		defender["current_hp"] = max(defender["current_hp"] - damage, 0)
		hp_changed.emit(not is_yours, defender["current_hp"], defender["max_hp"])
		hp_damage = damage
		if hp_damage > 0:
			_break_illusion(defender, not is_yours)

		if result["crit"]:
			battle_message.emit("A critical hit!")
			if _has_ability(defender, "anger-point"):
				defender["atk_stage"] = 6
				battle_message.emit(defender["display_name"] + "'s Anger Point maxed its Attack!")
		if effectiveness > 1.0:
			battle_message.emit("It's super effective!")
		elif effectiveness < 1.0:
			battle_message.emit("It's not very effective...")

		# Track last hit for Counter / Mirror Coat (only real HP damage, not substitute)
		var def_side_key = "opp" if is_yours else "yours"
		_last_hit_received[def_side_key]["damage"]   = damage
		_last_hit_received[def_side_key]["category"] = move["category"]
		if move["type"] == "dark" and _has_ability(defender, "justified"):
			apply_stages(defender, {"atk_stage": 1}, not is_yours)
		if _has_ability(defender, "color-change") and defender["current_hp"] > 0:
			defender["types"] = [move["type"]]
			battle_message.emit(defender["display_name"] + " transformed into the " + move["type"].capitalize() + " type!")

	if DRAINING_MOVES.has(move_name):
		_apply_drain_heal(attacker, defender, move_name, hp_damage, is_yours)
	_handle_on_hit_abilities(attacker, defender, move, is_yours, hp_damage, hit_substitute)
	_handle_on_hit_items(attacker, defender, move, is_yours, hp_damage, hit_substitute)

	# --- Secondary effects ---
	if SECONDARY_EFFECTS.has(move_name) and not defender["is_fainted"] and effectiveness > 0.0 and not (_has_ability(attacker, "sheer-force") and _move_has_secondary_effect(move_name)):
		_apply_secondary(attacker, defender, SECONDARY_EFFECTS[move_name], is_yours, hit_substitute)
	elif _has_ability(attacker, "stench") and not defender["is_fainted"] and not hit_substitute and randi() % 100 < 10 and not _has_ability(defender, "inner-focus"):
		defender["is_flinched"] = true
		if _has_ability(defender, "steadfast"):
			apply_stages(defender, {"spe_stage": 1}, not is_yours)
	if CONFUSION_SECONDARY_MOVES.has(move_name) and not defender["is_fainted"] and not hit_substitute and hp_damage > 0 and not (_has_ability(attacker, "sheer-force") and _move_has_secondary_effect(move_name)):
		_apply_secondary(attacker, defender, {"chance": CONFUSION_SECONDARY_MOVES[move_name], "confuse": true}, is_yours, false)

	# --- Phazing damage moves (Dragon Tail, Circle Throw) ---
	if move_name in PHAZING_DAMAGE_MOVES and not defender["is_fainted"]:
		if _has_ability(defender, "suction-cups") and not _is_mold_breaker_attack(attacker):
			battle_message.emit(defender["display_name"] + " anchored itself with Suction Cups!")
			return
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
		_try_trigger_hp_item(attacker, is_yours)

	# --- Life Orb recoil ---
	if _can_use_held_item(attacker) and attacker["item"] == "Life Orb" and attacker["ability"] != "magic-guard" and not (_has_ability(attacker, "sheer-force") and _move_has_secondary_effect(move_name)):
		var lo_recoil = max(int(attacker["max_hp"] / 10), 1)
		attacker["current_hp"] = max(attacker["current_hp"] - lo_recoil, 0)
		hp_changed.emit(is_yours, attacker["current_hp"], attacker["max_hp"])
		battle_message.emit(attacker["display_name"] + " lost HP to Life Orb!")
		_try_trigger_hp_item(attacker, is_yours)

	# --- Post-hit self stat drops ---
	if USER_STAGE_AFTER.has(move_name):
		apply_stages(attacker, USER_STAGE_AFTER[move_name], is_yours)

	# --- Self-faint moves (Explosion, Self-Destruct) ---
	if move_name in SELF_FAINT_MOVES and not attacker["is_fainted"]:
		attacker["current_hp"] = 0
		attacker["is_fainted"] = true
		hp_changed.emit(is_yours, 0, attacker["max_hp"])
		battle_message.emit(attacker["display_name"] + " fainted!")
		pokemon_fainted.emit(is_yours, attacker["name"])

	# --- Faint checks ---
	if defender["current_hp"] <= 0 and not defender["is_fainted"]:
		defender["is_fainted"] = true
		battle_message.emit(defender["display_name"] + " fainted!")
		pokemon_fainted.emit(not is_yours, defender["name"])
		if _has_ability(attacker, "moxie"):
			apply_stages(attacker, {"atk_stage": 1}, is_yours)
		# Destiny Bond: if the defender had Destiny Bond active, attacker also faints
		if defender["destiny_bond"] and not attacker["is_fainted"]:
			attacker["current_hp"] = 0
			attacker["is_fainted"] = true
			hp_changed.emit(is_yours, 0, attacker["max_hp"])
			battle_message.emit(attacker["display_name"] + " was taken down by Destiny Bond!")
			pokemon_fainted.emit(is_yours, attacker["name"])

	if attacker["current_hp"] <= 0 and not attacker["is_fainted"]:
		attacker["is_fainted"] = true
		battle_message.emit(attacker["display_name"] + " fainted!")
		pokemon_fainted.emit(is_yours, attacker["name"])

	_handle_contact_abilities(attacker, defender, move_name, is_yours)

	# --- U-turn / Volt Switch: flag a switch after this move resolves ---
	if move_name in UTURN_MOVES and not attacker["is_fainted"]:
		if _random_alive_not_active(is_yours) != -1:
			_pending_uturn["yours" if is_yours else "opp"] = true

# Handles all category=="status" moves: healing, status infliction, and stat changes.
func _apply_status_move(attacker: Dictionary, defender: Dictionary, move: Dictionary, is_yours: bool, reflected: bool = false):
	var move_name = move["name"]

	if _has_ability(defender, "magic-bounce") and _move_targets_opponent(move_name, move) and not reflected:
		if _has_ability(attacker, "magic-bounce"):
			battle_message.emit("But it failed!")
			return
		if move_name == "memento":
			battle_message.emit(defender["display_name"] + " bounced the move back!")
			apply_stages(attacker, OPP_STAGE_MOVES[move_name], is_yours, true)
			attacker["current_hp"] = 0
			attacker["is_fainted"] = true
			hp_changed.emit(is_yours, 0, attacker["max_hp"])
			battle_message.emit(attacker["display_name"] + " fainted!")
			pokemon_fainted.emit(is_yours, attacker["name"])
			return
		battle_message.emit(defender["display_name"] + " bounced the move back!")
		_apply_status_move(defender, attacker, move, not is_yours, true)
		return

	# --- Entry hazard setup (Stealth Rock, Spikes, Toxic Spikes) ---
	if HAZARD_SETUP.has(move_name):
		var hkey    = _opposing_side_key(is_yours)
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

	# --- Leech Seed ---
	if move_name == "leech-seed":
		if "grass" in defender["types"]:
			battle_message.emit("It doesn't affect " + defender["display_name"] + "...")
			return
		if defender["substitute_hp"] > 0:
			battle_message.emit("But it failed!")
			return
		if defender["leech_seed_source"] != "":
			battle_message.emit("But it failed!")
			return
		defender["leech_seed_source"] = _side_key(is_yours)
		battle_message.emit(defender["display_name"] + " was seeded!")
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
		if _has_ability(defender, "suction-cups") and not _is_mold_breaker_attack(attacker):
			battle_message.emit(defender["display_name"] + " anchored itself with Suction Cups!")
			return
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
		_try_trigger_status_cure_item(attacker, is_yours)
		return

	# --- Wish: delayed 50% heal, applied next end-of-turn ---
	if move_name == "wish":
		var wish_key = _side_key(is_yours)
		if wish_pending[wish_key]["turns"] > 0:
			battle_message.emit("But it failed!")
			return
		wish_pending[wish_key] = {
			"amount": max(int(attacker["max_hp"] / 2), 1),
			"turns": 2,
		}
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
		if not _can_receive_status(defender, new_status):
			battle_message.emit(defender["display_name"] + " is immune!")
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
		if new_status == "toxic":
			defender["toxic_counter"] = 0
		status_changed.emit(not is_yours, new_status)
		_try_synchronize(defender, attacker, new_status, not is_yours)
		match new_status:
			"toxic":   battle_message.emit(defender["display_name"] + " was badly poisoned!")
			"poison":  battle_message.emit(defender["display_name"] + " was poisoned!")
			"paralyze":battle_message.emit(defender["display_name"] + " was paralyzed!")
			"burn":    battle_message.emit(defender["display_name"] + " was burned!")
			"sleep":
				defender["sleep_turns"] = randi_range(2, 5)
				battle_message.emit(defender["display_name"] + " fell asleep!")
		_try_trigger_status_cure_item(defender, not is_yours)
		return

	if move_name in ["confuse-ray", "supersonic", "teeter-dance"]:
		if defender["substitute_hp"] > 0:
			battle_message.emit("But it failed!")
			return
		if defender.get("is_confused", false):
			battle_message.emit("But it failed!")
			return
		_apply_confusion(defender, not is_yours)
		return

	if move_name == "swagger":
		if defender["substitute_hp"] > 0:
			battle_message.emit("But it failed!")
			return
		if defender.get("is_confused", false):
			battle_message.emit("But it failed!")
			return
		apply_stages(defender, {"atk_stage": 2}, not is_yours)
		_apply_confusion(defender, not is_yours)
		return

	if move_name == "attract":
		if defender["substitute_hp"] > 0:
			battle_message.emit("But it failed!")
			return
		if defender.get("infatuated_with", "") != "":
			battle_message.emit("But it failed!")
			return
		_apply_infatuation(attacker, defender, not is_yours)
		return

	if move_name == "transform":
		if attacker.get("transformed", false):
			battle_message.emit("But it failed!")
			return
		_apply_transform(attacker, defender, is_yours)
		return

	# --- Self-boosting moves ---
	if SELF_STAGE_MOVES.has(move_name):
		apply_stages(attacker, SELF_STAGE_MOVES[move_name], is_yours)
		return

	# --- Destiny Bond ---
	if move_name == "destiny-bond":
		attacker["destiny_bond"] = true
		battle_message.emit(attacker["display_name"] + " is trying to take its foe down with it!")
		return

	# --- Perish Song ---
	if move_name == "perish-song":
		var already_active: bool = attacker["perish_count"] >= 0 and defender["perish_count"] >= 0
		if already_active:
			battle_message.emit("But it failed!")
			return
		attacker["perish_count"] = 3
		defender["perish_count"] = 3
		battle_message.emit("All Pokemon hearing the song will faint in three turns!")
		return

	# --- Opponent-debuffing moves ---
	if OPP_STAGE_MOVES.has(move_name):
		# Memento: user faints after using it
		if move_name == "memento":
			apply_stages(defender, OPP_STAGE_MOVES[move_name], not is_yours, true)
			attacker["current_hp"] = 0
			attacker["is_fainted"] = true
			hp_changed.emit(is_yours, 0, attacker["max_hp"])
			battle_message.emit(attacker["display_name"] + " fainted!")
			pokemon_fainted.emit(is_yours, attacker["name"])
			return
		apply_stages(defender, OPP_STAGE_MOVES[move_name], not is_yours, true)
		return

	# Fallback for unimplemented status moves
	battle_message.emit("But nothing happened!")

func apply_end_of_turn(mon: Dictionary, is_yours: bool):
	if mon["is_fainted"]:
		return

	if mon.get("disable_turns", 0) > 0:
		mon["disable_turns"] -= 1
		if mon["disable_turns"] <= 0:
			mon["disable_turns"] = 0
			mon["disabled_move"] = ""

	# Wish heal arrives
	var wish_key = _side_key(is_yours)
	var wish = wish_pending[wish_key]
	if wish["turns"] > 0:
		wish["turns"] -= 1
		if wish["turns"] == 0 and wish["amount"] > 0 and mon["current_hp"] < mon["max_hp"]:
			mon["current_hp"] = min(mon["current_hp"] + wish["amount"], mon["max_hp"])
			hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
			battle_message.emit(mon["display_name"] + "'s wish came true!")
			wish["amount"] = 0
		elif wish["turns"] == 0:
			wish["amount"] = 0
		wish_pending[wish_key] = wish

	_try_activate_orb(mon, is_yours)
	_try_trigger_status_cure_item(mon, is_yours)

	if mon["status"] == "burn":
		var burn_dmg = max(int(mon["max_hp"] / (16 if _has_ability(mon, "heatproof") else 8)), 1)
		mon["current_hp"] = max(mon["current_hp"] - burn_dmg, 0)
		hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
		battle_message.emit(mon["display_name"] + " was hurt by its burn!")
		if _resolve_faint_from_residual(mon, is_yours):
			return

	if mon["status"] == "poison":
		if _has_ability(mon, "poison-heal"):
			_heal_mon(mon, max(int(mon["max_hp"] / 8), 1), is_yours, mon["display_name"] + " restored HP with Poison Heal!")
		else:
			var poison_dmg = max(int(mon["max_hp"] / 8), 1)
			mon["current_hp"] = max(mon["current_hp"] - poison_dmg, 0)
			hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
			battle_message.emit(mon["display_name"] + " was hurt by poison!")
			if _resolve_faint_from_residual(mon, is_yours):
				return

	if mon["status"] == "toxic":
		if _has_ability(mon, "poison-heal"):
			_heal_mon(mon, max(int(mon["max_hp"] / 8), 1), is_yours, mon["display_name"] + " restored HP with Poison Heal!")
		else:
			mon["toxic_counter"] += 1
			var toxic_dmg = max(int(mon["max_hp"] * mon["toxic_counter"] / 16), 1)
			mon["current_hp"] = max(mon["current_hp"] - toxic_dmg, 0)
			hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
			battle_message.emit(mon["display_name"] + " was badly hurt by poison!")
			if _resolve_faint_from_residual(mon, is_yours):
				return

	if _effective_weather() == "rain":
		if _has_ability(mon, "rain-dish"):
			_heal_mon(mon, max(int(mon["max_hp"] / 16), 1), is_yours, mon["display_name"] + " restored HP with Rain Dish!")
		if _has_ability(mon, "dry-skin"):
			_heal_mon(mon, max(int(mon["max_hp"] / 8), 1), is_yours, mon["display_name"] + " restored HP with Dry Skin!")
		if _has_ability(mon, "hydration") and mon["status"] != "":
			mon["status"] = ""
			mon["sleep_turns"] = 0
			mon["toxic_counter"] = 0
			status_changed.emit(is_yours, "")
			battle_message.emit(mon["display_name"] + "'s Hydration cured its status!")

	if _effective_weather() == "hail":
		if _has_ability(mon, "ice-body"):
			_heal_mon(mon, max(int(mon["max_hp"] / 16), 1), is_yours, mon["display_name"] + " restored HP with Ice Body!")
		elif "ice" not in mon["types"] and mon["ability"] != "overcoat" and mon["ability"] != "ice-body" and mon["ability"] != "magic-guard":
			_damage_mon(mon, max(int(mon["max_hp"] / 16), 1), is_yours, mon["display_name"] + " was buffeted by the hail!")
			if _resolve_faint_from_residual(mon, is_yours):
				return

	if _effective_weather() == "sand":
		if "rock" not in mon["types"] and "ground" not in mon["types"] and "steel" not in mon["types"] \
				and mon["ability"] not in ["sand-veil", "sand-rush", "sand-force", "magic-guard", "overcoat"]:
			_damage_mon(mon, max(int(mon["max_hp"] / 16), 1), is_yours, mon["display_name"] + " was buffeted by the sandstorm!")
			if _resolve_faint_from_residual(mon, is_yours):
				return

	if _effective_weather() == "sun" and _has_ability(mon, "dry-skin"):
		_damage_mon(mon, max(int(mon["max_hp"] / 8), 1), is_yours, mon["display_name"] + " was hurt by Dry Skin!")
		if _resolve_faint_from_residual(mon, is_yours):
			return

	if _effective_weather() == "sun" and _has_ability(mon, "solar-power"):
		_damage_mon(mon, max(int(mon["max_hp"] / 8), 1), is_yours, mon["display_name"] + " was hurt by Solar Power!")
		if _resolve_faint_from_residual(mon, is_yours):
			return

	if _has_ability(mon, "shed-skin") and mon["status"] != "" and randi() % 3 == 0:
		mon["status"] = ""
		mon["sleep_turns"] = 0
		mon["toxic_counter"] = 0
		status_changed.emit(is_yours, "")
		battle_message.emit(mon["display_name"] + "'s Shed Skin cured its status!")

	if _has_ability(mon, "speed-boost"):
		apply_stages(mon, {"spe_stage": 1}, is_yours)

	if _has_ability(mon, "moody"):
		var raiseable: Array = []
		var lowerable: Array = []
		for stat_name in ["atk_stage", "def_stage", "spa_stage", "spd_stage", "spe_stage", "accuracy_stage", "evasion_stage"]:
			if mon[stat_name] < 6:
				raiseable.append(stat_name)
			if mon[stat_name] > -6:
				lowerable.append(stat_name)
		if not raiseable.is_empty():
			var raise_stat = raiseable[randi() % raiseable.size()]
			apply_stages(mon, {raise_stat: 2}, is_yours)
			lowerable.erase(raise_stat)
			if not lowerable.is_empty():
				var lower_stat = lowerable[randi() % lowerable.size()]
				apply_stages(mon, {lower_stat: -1}, is_yours)

	var sleeping_foe = _get_active_mon(not is_yours)
	if _has_ability(mon, "bad-dreams") and not sleeping_foe["is_fainted"] and sleeping_foe["status"] == "sleep":
		_damage_mon(sleeping_foe, max(int(sleeping_foe["max_hp"] / 8), 1), not is_yours, sleeping_foe["display_name"] + " is tormented by Bad Dreams!")
		_resolve_faint_from_residual(sleeping_foe, not is_yours)

	if _has_ability(mon, "slow-start") and mon.get("slow_start_turns", 0) > 0:
		mon["slow_start_turns"] -= 1

	if mon["leech_seed_source"] != "" and mon["current_hp"] > 0:
		var seed_dmg = max(int(mon["max_hp"] / 8), 1)
		mon["current_hp"] = max(mon["current_hp"] - seed_dmg, 0)
		hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
		battle_message.emit(mon["display_name"] + " was sapped by Leech Seed!")
		var source_is_yours = mon["leech_seed_source"] == "yours"
		var source_mon = _get_active_mon(source_is_yours)
		if not source_mon["is_fainted"]:
			if mon["ability"] == "liquid-ooze":
				source_mon["current_hp"] = max(source_mon["current_hp"] - seed_dmg, 0)
				hp_changed.emit(source_is_yours, source_mon["current_hp"], source_mon["max_hp"])
				battle_message.emit(source_mon["display_name"] + " sucked up the liquid ooze!")
				_resolve_faint_from_residual(source_mon, source_is_yours)
			elif source_mon["current_hp"] < source_mon["max_hp"]:
				source_mon["current_hp"] = min(source_mon["current_hp"] + seed_dmg, source_mon["max_hp"])
				hp_changed.emit(source_is_yours, source_mon["current_hp"], source_mon["max_hp"])
				battle_message.emit(source_mon["display_name"] + " restored HP with Leech Seed!")
		if _resolve_faint_from_residual(mon, is_yours):
			return

	if _can_use_held_item(mon) and (mon["item"] == "Leftovers" or mon["item"] == "Black Sludge"):
		if mon["item"] == "Black Sludge" and "poison" not in mon["types"]:
			var sludge_dmg = max(int(mon["max_hp"] / 8), 1)
			mon["current_hp"] = max(mon["current_hp"] - sludge_dmg, 0)
			hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
			battle_message.emit(mon["display_name"] + " was hurt by Black Sludge!")
			if _resolve_faint_from_residual(mon, is_yours):
				return
		elif mon["current_hp"] < mon["max_hp"]:
			var heal = max(int(mon["max_hp"] / 16), 1)
			mon["current_hp"] = min(mon["current_hp"] + heal, mon["max_hp"])
			hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
			battle_message.emit(mon["display_name"] + " restored HP with " + mon["item"] + "!")

	if _has_ability(mon, "harvest") and mon["item"] == "" and _is_berry_item(mon.get("last_consumed_item", "")):
		var harvest_roll = 100 if _effective_weather() == "sun" else 50
		if randi() % 100 < harvest_roll:
			mon["item"] = mon["last_consumed_item"]
			battle_message.emit(mon["display_name"] + " harvested a " + mon["item"] + "!")

	# Perish Song countdown
	if mon["perish_count"] > 0:
		mon["perish_count"] -= 1
		battle_message.emit(mon["display_name"] + "'s perish count fell to " + str(mon["perish_count"]) + "!")
	if mon["perish_count"] == 0 and not mon["is_fainted"]:
		mon["current_hp"] = 0
		mon["is_fainted"] = true
		hp_changed.emit(is_yours, 0, mon["max_hp"])
		battle_message.emit(mon["display_name"] + " fainted due to Perish Song!")
		pokemon_fainted.emit(is_yours, mon["name"])
		return

	_resolve_faint_from_residual(mon, is_yours)

func check_faint(is_yours: bool):
	var team = your_team if is_yours else opponent_team
	var active = your_active if is_yours else opponent_active

	if not team[active]["is_fainted"]:
		return
	var foe = _get_active_mon(not is_yours)
	if foe.get("infatuated_with", "") == _side_key(is_yours):
		foe["infatuated_with"] = ""

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
		# Let the player choose which pokemon to send in
		faint_switch_request.emit()
	else:
		_switch_in_pokemon(false, next)

func complete_faint_switch(index: int):
	var mon = your_team[index]
	if mon["is_fainted"]:
		return
	_switch_in_pokemon(true, index)

func find_next_alive(team: Array) -> int:
	for i in team.size():
		if not team[i]["is_fainted"]:
			return i
	return -1

func switch_pokemon(is_yours: bool, index: int):
	var team = your_team if is_yours else opponent_team
	var active = your_active if is_yours else opponent_active
	if index < 0 or index >= team.size():
		return
	if index == active:
		return
	if team[index]["is_fainted"]:
		return
	_clear_switch_out_state(_get_active_mon(is_yours), is_yours)
	_switch_in_pokemon(is_yours, index)

# ─── Fixed-damage helper ──────────────────────────────────────────────────────
# Applies a flat damage amount to `defender`, handles faint + Destiny Bond.
# Used by OHKO moves, Counter, Mirror Coat, Seismic Toss, etc.
func _deal_damage(defender: Dictionary, dmg: int, attacker: Dictionary, is_yours: bool, _move: Dictionary):
	dmg = _apply_sturdy(defender, attacker, dmg)
	defender["current_hp"] = max(defender["current_hp"] - dmg, 0)
	hp_changed.emit(not is_yours, defender["current_hp"], defender["max_hp"])
	if dmg > 0:
		_break_illusion(defender, not is_yours)
	_handle_on_hit_abilities(attacker, defender, _move, is_yours, dmg, false)
	_handle_on_hit_items(attacker, defender, _move, is_yours, dmg, false)
	if defender["current_hp"] <= 0 and not defender["is_fainted"]:
		defender["is_fainted"] = true
		battle_message.emit(defender["display_name"] + " fainted!")
		pokemon_fainted.emit(not is_yours, defender["name"])
		if _has_ability(attacker, "moxie"):
			apply_stages(attacker, {"atk_stage": 1}, is_yours)
		if defender["destiny_bond"] and not attacker["is_fainted"]:
			attacker["current_hp"] = 0
			attacker["is_fainted"] = true
			hp_changed.emit(is_yours, 0, attacker["max_hp"])
			battle_message.emit(attacker["display_name"] + " was taken down by Destiny Bond!")
			pokemon_fainted.emit(is_yours, attacker["name"])
	_handle_contact_abilities(attacker, defender, _move["name"], is_yours)

# ─── Multi-hit move execution ────────────────────────────────────────────────
# Handles all multi-hit, Triple Kick, and Beat Up logic.
func _execute_multi_hit(attacker: Dictionary, defender: Dictionary, move: Dictionary, is_yours: bool):
	var move_name  = move["name"]
	var hit_count  = 0
	var hp_damage  = 0  # damage that landed on real HP (for Life Orb trigger)

	# ── Beat Up (each alive party member lands one hit) ──────────────────────
	if move_name == "beat-up":
		var team: Array = your_team if is_yours else opponent_team
		for contributor in team:
			if contributor["is_fainted"] or defender["current_hp"] <= 0:
				continue
			var base_atk = team_gen.gen5_pokemon.get(contributor["name"], {}).get("attack", 80)
			var bu_move  = move.duplicate()
			bu_move["power"] = int(base_atk / 10) + 5
			var res     = calculate_damage(attacker, defender, bu_move)
			if defender["substitute_hp"] > 0:
				defender["substitute_hp"] = max(defender["substitute_hp"] - res["damage"], 0)
				if defender["substitute_hp"] <= 0:
					battle_message.emit(defender["display_name"] + "'s substitute broke!")
			else:
				res["damage"] = _apply_sturdy(defender, attacker, res["damage"])
				defender["current_hp"] = max(defender["current_hp"] - res["damage"], 0)
				hp_changed.emit(not is_yours, defender["current_hp"], defender["max_hp"])
				if res["damage"] > 0:
					_break_illusion(defender, not is_yours)
				hp_damage += res["damage"]
			battle_message.emit(contributor["display_name"] + "'s attack!")
			hit_count += 1
		battle_message.emit("Hit " + str(hit_count) + " time(s)!")
		_multihit_finish(attacker, defender, move, is_yours, hp_damage)
		return

	# ── Determine number of hits ──────────────────────────────────────────────
	var num_hits = 1
	if move_name == "triple-kick":
		num_hits = 3
	elif MULTI_HIT_MOVES.has(move_name):
		var hit_spec = MULTI_HIT_MOVES[move_name]
		if hit_spec is int:
			num_hits = hit_spec
		else:
			# Variable 2-5 hit distribution: 35% / 35% / 15% / 15%
			if attacker["ability"] == "skill-link":
				num_hits = 5
			else:
				var roll = randi() % 100
				if   roll < 35: num_hits = 2
				elif roll < 70: num_hits = 3
				elif roll < 85: num_hits = 4
				else:           num_hits = 5

	# ── Execute each hit ──────────────────────────────────────────────────────
	for i in num_hits:
		if defender["current_hp"] <= 0:
			break

		# Triple Kick: accuracy checked per hit and power increases each hit
		if move_name == "triple-kick":
			if not accuracy_check(attacker, defender, move):
				break
			var tk_move  = move.duplicate()
			tk_move["power"] = 10 * (i + 1)
			var res = calculate_damage(attacker, defender, tk_move)
			if res["crit"]:
				battle_message.emit("A critical hit!")
			if defender["substitute_hp"] > 0:
				defender["substitute_hp"] = max(defender["substitute_hp"] - res["damage"], 0)
				if defender["substitute_hp"] <= 0:
					battle_message.emit(defender["display_name"] + "'s substitute broke!")
			else:
				res["damage"] = _apply_sturdy(defender, attacker, res["damage"])
				defender["current_hp"] = max(defender["current_hp"] - res["damage"], 0)
				hp_changed.emit(not is_yours, defender["current_hp"], defender["max_hp"])
				if res["damage"] > 0:
					_break_illusion(defender, not is_yours)
				hp_damage += res["damage"]
			hit_count += 1
			continue

		# Standard hit
		var res = calculate_damage(attacker, defender, move)
		var hit_substitute = defender["substitute_hp"] > 0
		if res["crit"]:
			battle_message.emit("A critical hit!")
		if hit_substitute:
			defender["substitute_hp"] = max(defender["substitute_hp"] - res["damage"], 0)
			if defender["substitute_hp"] <= 0:
				battle_message.emit(defender["display_name"] + "'s substitute broke!")
		else:
			res["damage"] = _apply_sturdy(defender, attacker, res["damage"])
			defender["current_hp"] = max(defender["current_hp"] - res["damage"], 0)
			hp_changed.emit(not is_yours, defender["current_hp"], defender["max_hp"])
			hp_damage += res["damage"]
		hit_count += 1

		# Twineedle: 20% chance to poison per hit
		if move_name == "twineedle" and not hit_substitute and defender["status"] == "" and defender["current_hp"] > 0:
			if "poison" not in defender["types"] and "steel" not in defender["types"]:
				if randi() % 100 < 20:
					defender["status"] = "poison"
					status_changed.emit(not is_yours, "poison")
					battle_message.emit(defender["display_name"] + " was poisoned!")

	battle_message.emit("Hit " + str(hit_count) + " time(s)!")
	_multihit_finish(attacker, defender, move, is_yours, hp_damage)

# Shared post-hit cleanup for multi-hit moves (Life Orb + faint checks).
func _multihit_finish(attacker: Dictionary, defender: Dictionary, move: Dictionary, is_yours: bool, hp_damage: int):
	_handle_on_hit_abilities(attacker, defender, move, is_yours, hp_damage, false)
	_handle_on_hit_items(attacker, defender, move, is_yours, hp_damage, false)
	if hp_damage > 0 and _can_use_held_item(attacker) and attacker["item"] == "Life Orb" and attacker["ability"] != "magic-guard":
		var lo = max(int(attacker["max_hp"] / 10), 1)
		attacker["current_hp"] = max(attacker["current_hp"] - lo, 0)
		hp_changed.emit(is_yours, attacker["current_hp"], attacker["max_hp"])
		battle_message.emit(attacker["display_name"] + " lost HP to Life Orb!")
		_try_trigger_hp_item(attacker, is_yours)
	if defender["current_hp"] <= 0 and not defender["is_fainted"]:
		defender["is_fainted"] = true
		battle_message.emit(defender["display_name"] + " fainted!")
		pokemon_fainted.emit(not is_yours, defender["name"])
		if _has_ability(attacker, "moxie"):
			apply_stages(attacker, {"atk_stage": 1}, is_yours)
		if defender["destiny_bond"] and not attacker["is_fainted"]:
			attacker["current_hp"] = 0
			attacker["is_fainted"] = true
			hp_changed.emit(is_yours, 0, attacker["max_hp"])
			battle_message.emit(attacker["display_name"] + " was taken down by Destiny Bond!")
			pokemon_fainted.emit(is_yours, attacker["name"])
	_handle_contact_abilities(attacker, defender, move["name"], is_yours)
	if attacker["current_hp"] <= 0 and not attacker["is_fainted"]:
		attacker["is_fainted"] = true
		battle_message.emit(attacker["display_name"] + " fainted!")
		pokemon_fainted.emit(is_yours, attacker["name"])

# ─── Entry hazards ────────────────────────────────────────────────────────────

func apply_entry_hazards(mon: Dictionary, is_yours: bool):
	if mon["is_fainted"]:
		return
	var hkey    = "yours" if is_yours else "opp"
	var hazards = field_hazards[hkey]
	var is_grounded = "flying" not in mon["types"] and mon["ability"] != "levitate"
	var avoids_hazard_damage = mon["ability"] == "magic-guard"

	# Toxic Spikes: absorbed by incoming Poison-type, otherwise poison/badly poison
	if hazards["toxic_spikes"] > 0 and is_grounded:
		if "poison" in mon["types"]:
			hazards["toxic_spikes"] = 0
			battle_message.emit(mon["display_name"] + " absorbed the toxic spikes!")
		elif mon["status"] == "" and "steel" not in mon["types"] and _can_receive_status(mon, "toxic"):
			if hazards["toxic_spikes"] >= 2:
				mon["status"] = "toxic"
				mon["toxic_counter"] = 0
				status_changed.emit(is_yours, "toxic")
				battle_message.emit(mon["display_name"] + " was badly poisoned by the spikes!")
				_try_trigger_status_cure_item(mon, is_yours)
			else:
				mon["status"] = "poison"
				status_changed.emit(is_yours, "poison")
				battle_message.emit(mon["display_name"] + " was poisoned by the spikes!")
				_try_trigger_status_cure_item(mon, is_yours)

	# Spikes: 1/8, 1/6, 1/4 HP based on layers
	if hazards["spikes"] > 0 and is_grounded and not avoids_hazard_damage:
		var fracs = [0.125, 0.1666, 0.25]
		var dmg = max(int(mon["max_hp"] * fracs[hazards["spikes"] - 1]), 1)
		mon["current_hp"] = max(mon["current_hp"] - dmg, 0)
		hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
		battle_message.emit(mon["display_name"] + " was hurt by the spikes!")
		if _resolve_faint_from_residual(mon, is_yours):
			return

	# Stealth Rock: Rock-type effectiveness damage
	if hazards["stealth_rock"] and not avoids_hazard_damage:
		var eff = get_type_effectiveness("rock", mon["types"])
		var dmg = max(int(mon["max_hp"] * 0.125 * eff), 1)
		mon["current_hp"] = max(mon["current_hp"] - dmg, 0)
		hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
		battle_message.emit(mon["display_name"] + " was hurt by the stealth rocks!")
		_resolve_faint_from_residual(mon, is_yours)

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
	var old_mon = _get_active_mon(is_yours)
	_clear_switch_out_state(old_mon, is_yours)
	var old_name = old_mon["display_name"]
	battle_message.emit(old_name + " came back!")
	if is_yours:
		# Let the player choose who to switch in
		uturn_switch_request.emit()
	else:
		_force_switch(is_yours, idx)

func complete_uturn_switch(index: int):
	_force_switch(true, index)
	_resume_turn_after_uturn()

func _resume_turn_after_uturn():
	if _deferred_turn.is_empty():
		_finish_turn()
		return
	var opp_move = _deferred_turn.get("opp_move")
	var you_went_first: bool = _deferred_turn.get("you_go_first", true)
	_deferred_turn = {}

	if you_went_first and opp_move != null:
		# Opponent still needs to attack the new switch-in
		var opp_mon = opponent_team[opponent_active]
		if not opp_mon["is_fainted"] and not opp_mon["is_flinched"]:
			opp_mon["analytic_active"] = true
			execute_move(opp_mon, your_team[your_active], opp_move, false)
			if _pending_uturn["opp"]:
				_do_uturn_switch(false)
	_finish_turn()

func _finish_turn():
	apply_end_of_turn(your_team[your_active], true)
	apply_end_of_turn(opponent_team[opponent_active], false)
	_refresh_active_ability_state()
	check_faint(true)
	check_faint(false)

func _force_switch(is_yours: bool, index: int):
	_clear_switch_out_state(_get_active_mon(is_yours), is_yours)
	_switch_in_pokemon(is_yours, index)

# ─── Secondary effect application ─────────────────────────────────────────────

func _apply_secondary(attacker: Dictionary, defender: Dictionary,
		effect: Dictionary, is_yours: bool, blocked_by_substitute: bool = false):
	var chance = effect["chance"]
	if _has_ability(attacker, "serene-grace"):
		chance = min(chance * 2, 100)
	var roll = randi() % 100
	if roll >= chance:
		return

		# Status effect on defender
	if effect.has("status"):
		if blocked_by_substitute:
			return
		if defender["status"] != "":
			return
		var new_status: String = effect["status"]
		if not _can_receive_status(defender, new_status):
			return
		if _has_ability(defender, "shield-dust"):
			return
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
		_try_synchronize(defender, attacker, new_status, not is_yours)
		if new_status == "freeze":
			battle_message.emit(defender["display_name"] + " was frozen solid!")
		elif new_status == "burn":
			battle_message.emit(defender["display_name"] + " was burned!")
		elif new_status == "paralyze":
			battle_message.emit(defender["display_name"] + " was paralyzed!")
		_try_trigger_status_cure_item(defender, not is_yours)
		return

	if effect.get("confuse", false):
		if blocked_by_substitute:
			return
		if _has_ability(defender, "shield-dust"):
			return
		_apply_confusion(defender, not is_yours)
		return

	# Stat drop on defender
	if effect.has("stat"):
		if blocked_by_substitute:
			return
		if _has_ability(defender, "shield-dust"):
			return
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
		if blocked_by_substitute:
			return
		if _has_ability(defender, "inner-focus") or _has_ability(defender, "shield-dust"):
			return
		defender["is_flinched"] = true
		if _has_ability(defender, "steadfast"):
			apply_stages(defender, {"spe_stage": 1}, not is_yours)

func _format_name(mon_name: String) -> String:
	return mon_name.replace("-", " ").capitalize()

func execute_switch_turn(switch_index: int):
	if battle_over:
		return
	if not _can_switch_out(true):
		battle_message.emit("You can't switch out!")
		return

	turn_count += 1
	var your_mon = your_team[your_active]
	var opp_mon = opponent_team[opponent_active]

	your_mon["is_protected"] = false
	opp_mon["is_protected"]  = false
	if your_mon["last_move_used"] not in PROTECT_MOVES:
		your_mon["protect_consecutive"] = 0
	if opp_mon["last_move_used"] not in PROTECT_MOVES:
		opp_mon["protect_consecutive"] = 0

	# Player switches — counts as their action for the turn
	battle_message.emit(your_mon["display_name"] + ", come back!")
	switch_pokemon(true, switch_index)

	# Opponent still attacks the new Pokemon
	var opp_move_idx = get_opponent_move()
	var opp_move = opp_mon["moveset"][opp_move_idx]
	opp_mon["is_flinched"] = false
	opp_mon["analytic_active"] = true
	_current_turn_moves  = {"yours": "", "opp": opp_move["name"]}
	_last_hit_received   = {"yours": {"damage": 0, "category": ""}, "opp": {"damage": 0, "category": ""}}
	execute_move(opp_mon, your_team[your_active], opp_move, false)
	if _pending_uturn["opp"]:
		_do_uturn_switch(false)

	apply_end_of_turn(your_team[your_active], true)
	apply_end_of_turn(opponent_team[opponent_active], false)
	_refresh_active_ability_state()

	check_faint(true)
	check_faint(false)

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
